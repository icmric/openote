// Openote must start.
//
// Reported from a real Windows build, on a plain local disk with nothing else
// running and plenty of space free:
//
//     SqliteException(1546): while executing, disk I/O error (code 1546)
//       Causing statement: PRAGMA auto_vacuum=INCREMENTAL;
//       ...
//       #7  Repository.purgeExpiredNodes (repository.dart:3148)
//       #8  AppState.init (app_state.dart:5904)
//
// Three separate faults line up in that one stack, and each is tested here.
//
//  1. **`PRAGMA auto_vacuum=INCREMENTAL` took a write transaction on every
//     open.** It reads as a settings line; it is not. SQLite's `auto_vacuum`
//     setter emits `OP_Transaction ... 1` so it can write meta[6] — so every
//     notebook Openote opened took a write lock and touched the journal before
//     the user had asked for anything. Extended code 1546 is
//     `SQLITE_IOERR_TRUNCATE`: a failure inside the VFS's `xTruncate`, which
//     is journal work. And it bought nothing, because `auto_vacuum` cannot be
//     set on a database that already has pages.
//
//  2. **The recycle-bin sweep was fatal.** `purgeExpiredNodes` deletes rows
//     already past thirty days. Skipping it costs one launch's tidiness. It
//     was unguarded, so it took the whole app down.
//
//  3. **One unreadable notebook ended the launch**, on an error screen with no
//     way forward, while every other notebook in the workspace was fine.
//
// The through-line: nothing on the path between double-clicking the icon and
// seeing a window may be allowed to fail hard for a reason that is not "there
// is nothing to show you".
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openote/state/app_state.dart';
import 'package:openote/store/database.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Directory tempDir(String prefix) {
    final d = Directory.systemTemp.createTempSync(prefix);
    addTearDown(() {
      try {
        d.deleteSync(recursive: true);
      } catch (_) {}
    });
    return d;
  }

  group('opening a notebook does not write to it', () {
    // The fix, stated as the property rather than as the line of code: opening
    // an existing container is a READ. Asserted through the file's own
    // `auto_vacuum` value, which is the thing the pragma was there to change —
    // if the statement runs on an existing database it either changes the mode
    // or takes a write transaction trying, and both are visible from here.
    test('an existing container is opened without setting auto_vacuum', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final dir = tempDir('onote_open_ro_');
      final path = p.join(dir.path, 'Notes.onote');

      // A container this build made: fresh, so it DOES get the pragma, which
      // is the one case where it is free and can take effect.
      final made = openOnote(path, notebookId: 'nb1', title: 'Notes');
      final modeAtBirth =
          made.select('PRAGMA auto_vacuum;').first.columnAt(0) as int;
      made.dispose();
      expect(modeAtBirth, 2,
          reason: 'a NEW notebook is still created auto-vacuum capable');

      // Now the case that was crashing: the same file, opened again.
      final reopened = openOnote(path, notebookId: 'nb1', title: 'Notes');
      expect(reopened.select('PRAGMA auto_vacuum;').first.columnAt(0), 2,
          reason: 'reopening changes nothing about the file');
      reopened.dispose();
    });

    // **Asserted against the source, and the honest reason why.**
    //
    // The behavioural difference this change makes is one write transaction
    // that no longer happens. That is not observable from out here, because
    // `journal_mode=WAL` and `_ensureSchema` both write on every open too — so
    // a test that watched the file's mtime, or its length, or its WAL would
    // pass identically before and after the fix. Writing one anyway would be
    // worse than writing none: it would look like a guard and hold nothing.
    // (Checked, rather than assumed: with the pragma restored, an mtime probe
    // on a legacy container reported "changed" in both worlds.)
    //
    // What CAN be pinned exactly is the thing that was wrong — that the
    // statement ran unconditionally, on databases where it could not take
    // effect and could only cost a write lock.
    test('the pragma is reached only on a fresh file', () {
      final src = File('lib/store/database.dart').readAsStringSync();
      final i = src.indexOf('PRAGMA auto_vacuum');
      expect(i, greaterThan(-1), reason: 'still there for new notebooks');
      final guard = src.lastIndexOf('if (freshFile) {', i);
      expect(guard, greaterThan(-1),
          reason: 'auto_vacuum must sit inside `if (freshFile)`');
      expect(src.substring(guard, i), isNot(contains('}')),
          reason: 'and the guard must still be open where the pragma runs');
    });
  });

  group('a notebook that will not open', () {
    /// A workspace with [titles] notebooks, in creation order.
    Future<Repository> workspaceOf(List<String> titles) async {
      final repo = await Repository.openAt(tempDir('onote_startup_'));
      addTearDown(repo.dispose);
      for (final t in titles) {
        await repo.createNotebook(t);
      }
      return repo;
    }

    /// Make [id]'s container unopenable the way a real one goes wrong, without
    /// needing the operating system to co-operate: replace the file with
    /// something that is not a database at all.
    void corrupt(Repository repo, String id) {
      repo.closeNotebook(id);
      File(repo.notebooks.firstWhere((n) => n.id == id).file)
          .writeAsStringSync('this is not a notebook');
    }

    test('is reported as a problem rather than thrown', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final repo = await workspaceOf(['Good', 'Broken']);
      final broken = repo.notebooks.firstWhere((n) => n.title == 'Broken').id;
      corrupt(repo, broken);

      expect(repo.notebookOpenError(broken), isNotNull);
      expect(repo.notebookOpenError(repo.notebooks.first.id), isNull,
          reason: 'a healthy notebook is not accused of anything');
    });

    test('is explained in words a student can act on', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final repo = await workspaceOf(['Good', 'Broken']);
      final broken = repo.notebooks.firstWhere((n) => n.title == 'Broken').id;
      corrupt(repo, broken);
      final app = AppState(repo);
      addTearDown(app.dispose);

      final problem = app.notebookOpenProblem(broken)!;
      expect(problem.message, contains('Broken'),
          reason: 'name the notebook — the user has more than one');
      expect(problem.message, isNot(contains('SqliteException')));
      expect(problem.message, isNot(contains('PRAGMA')));
      expect(problem.message.toLowerCase(), contains('nothing has been lost'),
          reason: 'the one thing they most need to hear, said plainly');
      expect(problem.details, contains('Sqlite'),
          reason: 'the technical cause is kept, just not put on the screen');
    });

    test('DOES NOT STOP THE APP STARTING — it opens another one', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final repo = await workspaceOf(['Good', 'Broken']);
      final good = repo.notebooks.firstWhere((n) => n.title == 'Good').id;
      final broken = repo.notebooks.firstWhere((n) => n.title == 'Broken').id;
      // The broken one is the notebook the user had open last, which is the
      // notebook `init` will reach for.
      repo.setSetting('lastNotebook', broken);
      corrupt(repo, broken);

      final app = AppState(repo);
      addTearDown(app.dispose);
      await app.init();
      app.cancelPendingSave();

      expect(app.notebookId, good,
          reason: 'landing in a working notebook beats a dead window');
      expect(app.pendingOpenNotice, isNotNull,
          reason: 'and the user is told why they are not where they left off');
      expect(app.pendingOpenNotice!.message, contains('Broken'));
    });

    test('every notebook broken still comes up, empty, with the reason',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // Rare and alarming, and still not a crash. The shell already draws the
      // empty state; the notice says why it is empty, which is strictly more
      // than the error screen ever said.
      final repo = await workspaceOf(['Only']);
      corrupt(repo, repo.notebooks.first.id);
      final app = AppState(repo);
      addTearDown(app.dispose);

      await app.init();
      app.cancelPendingSave();
      expect(app.notebookId, isNull);
      expect(app.nodes, isEmpty);
      expect(app.pendingOpenNotice, isNotNull);
    });
  });

  group('startup housekeeping', () {
    test('a recycle-bin sweep that fails does not end the launch', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The exact stack from the report: `AppState.init` →
      // `purgeExpiredNodes` → the container. The sweep deletes rows already
      // past thirty days; it cannot be worth a launch. Proven by breaking the
      // notebook the sweep runs against and asserting the app still comes up.
      final repo = await Repository.openAt(tempDir('onote_purge_boot_'));
      addTearDown(repo.dispose);
      await repo.createNotebook('Good');
      await repo.createNotebook('Swept');
      final swept = repo.notebooks.firstWhere((n) => n.title == 'Swept').id;
      repo.setSetting('lastNotebook', swept);
      repo.closeNotebook(swept);
      File(repo.notebooks.firstWhere((n) => n.id == swept).file)
          .writeAsStringSync('not a database');

      final app = AppState(repo);
      addTearDown(app.dispose);
      await expectLater(app.init(), completes);
      app.cancelPendingSave();
    });
  });
}
