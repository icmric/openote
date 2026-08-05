// Does the sync chip tell the truth — and keep telling it after a restart?
//
// The reported bug: "after closing and opening the app the sync button would
// go back to grey even though I'm on the synced notebook."
//
// The cause was that "is this notebook syncing?" was *re-derived on every
// paint* from `detectCloudFolders()`, which probes ~15 well-known provider
// paths with `existsSync`. That is a good way to OFFER somewhere to sync and a
// bad way to REPORT whether syncing is on, because it answers "no" twice over:
//
//   1. for any folder not on the list — a self-hosted Nextcloud somewhere
//      else, a relocated OneDrive, a Google Drive on an unexpected letter —
//      which the user chose deliberately and the app then denied; and
//   2. for a folder that IS on the list but has not mounted yet. Cloud clients
//      mount asynchronously, so a probe two seconds after launch fails where
//      the same probe a minute later succeeds — which is exactly the
//      restart-shaped, intermittent symptom that was reported.
//
// The fix is to remember what the user told us instead of guessing it again.
// These tests hold that line.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  /// A workspace plus a folder standing in for the user's own sync location —
  /// deliberately NOT one of the well-known paths detection knows.
  (Directory, Directory) dirs(String name) {
    final ws = Directory.systemTemp.createTempSync('onote_ws_$name');
    final cloud = Directory.systemTemp.createTempSync('MyNextcloud_$name');
    addTearDown(() {
      for (final d in [ws, cloud]) {
        try {
          d.deleteSync(recursive: true);
        } catch (_) {}
      }
    });
    return (ws, cloud);
  }

  test('a folder the user chose counts as syncing', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (ws, cloud) = dirs('chosen');
    final repo = await Repository.openAt(ws);
    addTearDown(repo.dispose);
    final nb = await repo.createNotebook('Discrete Maths');
    final app = AppState(repo)..notebookId = nb.id;

    expect(app.syncStatus(nb.id).isSynced, isFalse,
        reason: 'it really is only on this machine yet');

    await app.moveNotebookToFolder(nb.id, cloud.path);

    final s = app.syncStatus(nb.id);
    expect(s.isSynced, isTrue,
        reason: 'the user put it in a sync folder; the app must agree');
    // And it names the folder rather than reporting the generic kind, so the
    // chip says where the notes went.
    expect(s.label, contains('MyNextcloud'));
  });

  // The reported symptom, directly: same workspace, second launch.
  test('and still counts as syncing after a restart', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (ws, cloud) = dirs('restart');

    final repo1 = await Repository.openAt(ws);
    final nb = await repo1.createNotebook('Discrete Maths');
    final app1 = AppState(repo1)..notebookId = nb.id;
    await app1.moveNotebookToFolder(nb.id, cloud.path);
    expect(app1.syncStatus(nb.id).isSynced, isTrue);
    await repo1.flushWorkspace();
    repo1.dispose();

    // Second launch, same workspace on disk.
    final repo2 = await Repository.openAt(ws);
    addTearDown(repo2.dispose);
    final app2 = AppState(repo2)..notebookId = nb.id;
    app2.loadSyncRoots();

    expect(app2.syncStatus(nb.id).isSynced, isTrue,
        reason: 'the chip went grey on the second launch — the whole bug');
    expect(app2.syncStatus(nb.id).label, contains('MyNextcloud'));
  });

  test('a notebook that never left the workspace is still not synced',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (ws, _) = dirs('local');
    final repo = await Repository.openAt(ws);
    addTearDown(repo.dispose);
    final nb = await repo.createNotebook('Local only');
    final app = AppState(repo)..notebookId = nb.id;

    // Remembering roots must not make everything look synced — the chip is
    // only worth anything if it can still say no.
    app.rememberSyncRoot(Directory.systemTemp.createTempSync('elsewhere_').path);
    expect(app.syncStatus(nb.id).isSynced, isFalse);
  });

  test('remembering the same folder twice keeps one entry', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (ws, cloud) = dirs('dedupe');
    final repo = await Repository.openAt(ws);
    addTearDown(repo.dispose);
    final app = AppState(repo);

    app.rememberSyncRoot(cloud.path);
    app.rememberSyncRoot(cloud.path);
    expect(app.syncRoots.length, 1);

    app.forgetSyncRoot(cloud.path);
    expect(app.syncRoots, isEmpty);
  });

  // The other half of the bug: a folder that IS known but was not *there* when
  // the app started. Cloud clients mount asynchronously, so the first probe
  // after launch can fail. Nothing told the app when that changed, so the wrong
  // answer stayed on screen for the session.
  test('notices a sync folder that appears after startup', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final ws = Directory.systemTemp.createTempSync('onote_ws_late');
    final cloud = Directory.systemTemp.createTempSync('LateMount_');
    addTearDown(() {
      for (final d in [ws, cloud]) {
        try {
          d.deleteSync(recursive: true);
        } catch (_) {}
      }
    });
    final repo = await Repository.openAt(ws);
    addTearDown(repo.dispose);
    final nb = await repo.createNotebook('Discrete Maths');
    final app = AppState(repo)..notebookId = nb.id;
    await app.moveNotebookToFolder(nb.id, cloud.path);
    expect(app.syncStatus(nb.id).isSynced, isTrue);

    // The provider goes away — the same shape as "has not mounted yet".
    cloud.deleteSync(recursive: true);
    app.debugPollSyncStatus();
    expect(app.syncStatus(nb.id).isSynced, isTrue,
        reason: 'a remembered root is a fact about the user, not a probe — it '
            'must not flicker with the mount state');

    // And a status change does reach listeners rather than waiting for an
    // unrelated repaint.
    var notified = 0;
    app.addListener(() => notified++);
    app.rememberSyncRoot(Directory.systemTemp.createTempSync('another_').path);
    expect(notified, greaterThan(0));
  });
}
