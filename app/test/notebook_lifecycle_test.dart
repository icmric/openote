// Regression coverage for the notebook recycle-bin lifecycle added in the
// navigator rework: delete → recycle bin → restore, rename, permanent purge
// (removes the .onote file), workspace persistence of the trashed list, and the
// AppState guard that refuses to delete the only notebook.
//
// Pure repository/state logic over a real temp SQLite workspace — no widgets,
// no document engine. Skips if the bundled sqlite3.dll isn't present.
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';

import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var haveSqlite = false;
  setUpAll(() {
    for (final rel in [
      'build/windows/x64/runner/Debug/sqlite3.dll',
      'build/windows/x64/runner/Release/sqlite3.dll',
    ]) {
      final f = File(rel);
      if (f.existsSync()) {
        open.overrideForAll(() => DynamicLibrary.open(f.absolute.path));
        haveSqlite = true;
        break;
      }
    }
  });

  test('notebook trash → restore → rename → purge, and it persists', () async {
    if (!haveSqlite) {
      markTestSkipped('sqlite3.dll not built');
      return;
    }
    final tmp = Directory.systemTemp.createTempSync('onote_nb_');
    var repo = await Repository.openAt(tmp);
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {/* best-effort */}
    });

    final a = await repo.createNotebook('Alpha');
    final b = await repo.createNotebook('Beta');
    expect(repo.notebooks.map((n) => n.id), [a.id, b.id]);
    expect(repo.trashedNotebooks, isEmpty);

    // Trash Beta: leaves the active list, joins the bin, file stays on disk.
    await repo.trashNotebook(b.id);
    expect(repo.notebooks.map((n) => n.id), [a.id]);
    expect(repo.trashedNotebooks.map((n) => n.id), [b.id]);
    expect(repo.trashedNotebooks.single.deletedAt, isNotNull);
    expect(File(b.file).existsSync(), true, reason: 'restore must be lossless');

    // Restore brings it back with its deletion mark cleared.
    await repo.restoreNotebook(b.id);
    expect(repo.notebooks.map((n) => n.id).toSet(), {a.id, b.id});
    expect(repo.trashedNotebooks, isEmpty);

    // Rename sticks on the active ref.
    await repo.renameNotebook(a.id, 'Alpha renamed');
    expect(repo.notebooks.firstWhere((n) => n.id == a.id).title,
        'Alpha renamed');

    // Purge deletes the .onote for good.
    await repo.trashNotebook(a.id);
    await repo.purgeNotebook(a.id);
    expect(File(a.file).existsSync(), false);
    expect(repo.trashedNotebooks, isEmpty);
    expect(repo.notebooks.map((n) => n.id), [b.id]);

    // Persistence: a trashed notebook survives reopening the workspace.
    await repo.trashNotebook(b.id);
    expect(repo.notebooks, isEmpty);
    repo.dispose();
    repo = await Repository.openAt(tmp);
    expect(repo.trashedNotebooks.map((n) => n.id), [b.id]);
    expect(repo.notebooks, isEmpty);
  });

  test('retention auto-purges expired trashed notebooks, keeps fresh ones',
      () async {
    if (!haveSqlite) {
      markTestSkipped('sqlite3.dll not built');
      return;
    }
    final tmp = Directory.systemTemp.createTempSync('onote_ret_');
    final repo = await Repository.openAt(tmp);
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {/* best-effort */}
    });

    await repo.createNotebook('Keep');
    final fresh = await repo.createNotebook('Fresh');
    final old = await repo.createNotebook('Old');
    await repo.trashNotebook(fresh.id);
    await repo.trashNotebook(old.id);

    // Backdate "Old" past the retention window; "Fresh" stays recent.
    final beyond = DateTime.now().millisecondsSinceEpoch -
        const Duration(days: Repository.recycleRetentionDays + 1).inMilliseconds;
    repo.trashedNotebooks.firstWhere((n) => n.id == old.id).deletedAt = beyond;

    final purged = await repo.purgeExpiredNotebooks();
    expect(purged, 1);
    expect(repo.trashedNotebooks.map((n) => n.id), [fresh.id],
        reason: 'the fresh one survives the sweep');
    expect(File(old.file).existsSync(), false, reason: 'expired file removed');
    expect(File(fresh.file).existsSync(), true);
  });

  test('AppState.deleteNotebook refuses the only notebook', () async {
    if (!haveSqlite) {
      markTestSkipped('sqlite3.dll not built');
      return;
    }
    final tmp = Directory.systemTemp.createTempSync('onote_nb1_');
    final repo = await Repository.openAt(tmp);
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {/* best-effort */}
    });

    final only = await repo.createNotebook('Solo');
    final app = AppState(repo);
    app.notebookId = only.id;

    // Guard returns false before any teardown; the notebook stays put.
    expect(await app.deleteNotebook(only.id), false);
    expect(repo.notebooks.map((n) => n.id), [only.id]);
    expect(repo.trashedNotebooks, isEmpty);
    // AppState isn't init()'d, so no debounce timer to cancel; the teardown
    // disposes the shared repo (AppState.dispose would double-dispose it).
  });
}
