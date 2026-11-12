// Closing the window must never become impossible.
//
// PR #9 made closing wait for the last save, and refuse to close if it failed,
// so that an edit cannot vanish silently. That is right for a save that
// FAILED (the disk is full, the file is locked): the person should hear about
// it. It is wrong in three cases the PR did not consider, each of which left
// the window impossible to close for good:
//
//  * the page is dirty in a notebook Openote is only SHOWING (its log is from a
//    newer build), which by design is never written, so it is dirty forever;
//  * the page is dirty with no page open to save it to;
//  * the save really does fail and keeps failing, so the only way out was to
//    kill the process, which loses the edit anyway, only less politely.
//
// So: a refused close says so, and a second deliberate close leaves.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());
  setUp(() => AppState.syncLogEnabled = false);
  tearDown(() => AppState.syncLogEnabled = true);

  late Directory tmp;
  late Repository repo;
  late AppState app;
  late String nb;
  late Database db;

  Future<void> boot() async {
    tmp = Directory.systemTemp.createTempSync('onote_exit_');
    repo = await Repository.openAt(tmp);
    final n = await repo.createNotebook('Exit');
    nb = n.id;
    app = AppState(repo);
    db = sqlite3.open(n.file);
    app.notebookId = nb;
    app.nodes = repo.loadNodes(nb);
    app.pageId = app.nodes.firstWhere((x) => x.kind == NodeKind.page).id;
    app.blocks = [
      Block(type: BlockType.text, x: 0, y: 0, content: {'text': 'before'})
    ];
    app.markDirty();
    await app.flushSave();
  }

  tearDown(() {
    try {
      db.dispose();
      app.dispose();
      repo.dispose();
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  void breakTheDisk() => db.execute(
      "CREATE TRIGGER fail_save BEFORE INSERT ON page_mirror "
      "BEGIN SELECT RAISE(ABORT, 'disk write rejected'); END");

  Future<void> edit(String text) async {
    app.blocks.single.content['text'] = text;
    app.markDirty();
  }

  test('a notebook that is only being shown never blocks closing', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await boot();
    app.debugMarkReadOnly(nb);
    await edit('edited in a read-only notebook');
    expect(app.hasUnsavedChanges, isTrue);

    // Must finish, and must not spin: it is dirty for good, by design.
    await app.shutdown().timeout(const Duration(seconds: 5));
    expect(await app.requestExit().timeout(const Duration(seconds: 5)), isTrue);
  });

  test('a dirty flag with no page open to save it to never blocks closing',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await boot();
    await edit('then the page closes');
    app.pageId = null;
    await app.shutdown().timeout(const Duration(seconds: 5));
    expect(await app.requestExit().timeout(const Duration(seconds: 5)), isTrue);
  });

  group('a save that really fails', () {
    late DateTime clock;
    Future<void> failing() async {
      await boot();
      clock = DateTime(2026, 11, 12, 9);
      app.clockForTest = () => clock;
      breakTheDisk();
      await edit('after');
    }

    test('the first close is refused, and says why', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await failing();
      expect(await app.requestExit(), isFalse);
      expect(app.saveError, isNotNull);
      expect(app.saveError!.message, contains('close the window again'),
          reason: 'the person must be told how to leave');
      expect(app.hasUnsavedChanges, isTrue, reason: 'nothing was thrown away');
    });

    test('a second, deliberate close leaves', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await failing();
      expect(await app.requestExit(), isFalse);
      clock = clock.add(const Duration(seconds: 3));
      expect(await app.requestExit(), isTrue);
      expect(
          repo.readPage(nb, app.pageId!).blocks.single.content['text'], 'before',
          reason: 'and the unsaved edit really was not written');
    });

    test('a double-click on the close button is not a second, deliberate close',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await failing();
      expect(await app.requestExit(), isFalse);
      clock = clock.add(const Duration(milliseconds: 300));
      expect(await app.requestExit(), isFalse,
          reason: 'too soon: that is the same click arriving twice');
    });

    test('and an old refusal does not make a much later close instant',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await failing();
      expect(await app.requestExit(), isFalse);
      clock = clock.add(const Duration(minutes: 30));
      expect(await app.requestExit(), isFalse,
          reason: 'half an hour later this is a fresh attempt, and is refused '
              'once with the reason, not waved through');
    });

    test('if the disk comes back, the next close simply saves and leaves',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await failing();
      expect(await app.requestExit(), isFalse);
      db.execute('DROP TRIGGER fail_save');
      clock = clock.add(const Duration(seconds: 3));
      expect(await app.requestExit(), isTrue);
      expect(
          repo.readPage(nb, app.pageId!).blocks.single.content['text'], 'after',
          reason: 'the retry saved it; nothing was lost');
      expect(app.saveError, isNull);
    });

    test('a refusal is forgotten once a close succeeds', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await failing();
      expect(await app.requestExit(), isFalse);
      db.execute('DROP TRIGGER fail_save');
      clock = clock.add(const Duration(seconds: 3));
      expect(await app.requestExit(), isTrue);
      breakTheDisk();
      await edit('again');
      clock = clock.add(const Duration(seconds: 3));
      expect(await app.requestExit(), isFalse,
          reason: 'a new failure starts a new first refusal');
    });
  });
}
