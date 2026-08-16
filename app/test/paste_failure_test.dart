// A paste that cannot be written must FAIL LOUDLY, never silently no-op.
//
// `OpLogStore.writeBlob` throws a synchronous `FileSystemException` on a full
// disk, a read-only folder, or a cloud directory that is offline — and every
// interactive route (paste, drag-and-drop, Insert ▸ Image / File) reached it
// through fire-and-forget async handlers. The throw vanished into a console
// nobody runs the app from; on screen, the paste simply did nothing, and the
// user walked away believing their screenshot was in their notes. Losing the
// thing that was just added is the one failure that must be visible, so
// `AppState.tryAddBlob` turns it into the same plain-words `saveError` chip
// every other write failure uses, and no block referencing unstored bytes is
// ever created.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/media_drop.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/sync/op_log.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  final png = Uint8List.fromList(List.filled(64, 7));

  Future<(Repository, AppState, String, OpLogStore)> fixture() async {
    final tmp = Directory.systemTemp.createTempSync('onote_pastefail_');
    final repo = await Repository.openAt(tmp);
    late AppState created;
    addTearDown(() async {
      created.cancelPendingSave();
      await created.settleBackgroundWork();
      await repo.flushWorkspace();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final nb = await repo.createNotebook('Paste');
    final app = created = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    await app.selectPage(
        app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
    // Let the open-time background work (recorder warm, backfill) finish
    // BEFORE the store is sabotaged, so the failure under test is the paste's.
    await app.settleBackgroundWork();
    final ref = repo.notebooks.firstWhere((n) => n.id == nb.id);
    return (repo, app, nb.id, OpLogStore.forNotebook(ref.file, logDir: ref.logDir));
  }

  /// Make every blob write fail the way a broken disk does: a plain file
  /// squatting where the `blobs/` directory must be created makes
  /// `createSync(recursive: true)` throw `FileSystemException`, synchronously,
  /// on every platform.
  void breakBlobStore(OpLogStore store) {
    if (store.blobsDir.existsSync()) {
      store.blobsDir.deleteSync(recursive: true);
    }
    store.dir.createSync(recursive: true);
    File(store.blobsDir.path).writeAsStringSync('in the way');
  }

  void repairBlobStore(OpLogStore store) {
    final f = File(store.blobsDir.path);
    if (f.existsSync()) f.deleteSync();
  }

  test('a paste that cannot be written is refused loudly, not silently',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (_, app, _, store) = await fixture();
    breakBlobStore(store);

    var notified = 0;
    app.addListener(() => notified++);
    final before = app.blocks.length;

    // MUTATION: swap `tryAddBlob` back to `addBlob` in `insertImageBytes`
    // and this test fails by THROWING — which on screen was a paste that
    // did nothing at all.
    final b = insertImageBytes(app, png, 'image/png', const Offset(200, 200));

    expect(b, isNull);
    expect(app.blocks.length, before,
        reason: 'no block may reference bytes nothing holds — it would '
            'render as a broken picture that LOOKS like the paste worked');
    final problem = app.saveError;
    expect(problem, isNotNull,
        reason: 'the failure must be on the status bar, not in a console');
    // Year-10 words on the surface; the exception behind the Advanced fold.
    expect(problem!.message, isNot(contains('Exception')));
    expect(problem.message.toLowerCase(), contains('disk'));
    expect(problem.details, isNotNull);
    expect(notified, greaterThan(0),
        reason: 'the status bar only repaints if someone tells it to');
  });

  test('the attachment route fails the same visible way', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (_, app, _, store) = await fixture();
    breakBlobStore(store);

    final before = app.blocks.length;
    final b = insertFileBytes(app, png, 'handout.pdf', const Offset(80, 80));
    expect(b, isNull);
    expect(app.blocks.length, before,
        reason: 'an attachment chip whose bytes were never stored is a file '
            'the user believes is kept and is not');
    expect(app.saveError, isNotNull);
  });

  test('a normal paste still works, and clears the notice', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (_, app, _, store) = await fixture();

    // Fail once so there is a notice to clear.
    breakBlobStore(store);
    expect(insertImageBytes(app, png, 'image/png', const Offset(200, 200)),
        isNull);
    expect(app.saveError, isNotNull);

    // The disk comes back (space freed, folder writable again).
    repairBlobStore(store);
    final b = insertImageBytes(app, png, 'image/png', const Offset(200, 200));
    expect(b, isNotNull, reason: 'the ordinary paste path still places a block');
    expect((b!.content['blob'] as String), startsWith('sha256:'));
    expect(app.blob(b.content['blob'] as String), isNotNull,
        reason: 'and the bytes are really stored under that hash');
    // MUTATION: stop clearing `_blobWriteError` on a successful `tryAddBlob`
    // and this fails — the chip would cry wolf for the rest of the session.
    expect(app.saveError, isNull);
  });
}
