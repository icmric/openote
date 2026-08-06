// Storage wave 1a: a notebook's images are stored ONCE unless something other
// than this device is going to read them.
//
// **The measurement behind it.** A synthetic imported notebook — 40 pages, 20
// images of 400 KB — occupied 17.39 MB for 7.81 MB of media, a 2.23× overhead,
// because shadow mode writes every image into the container's `blobs` table and
// again as `.onotebook/blobs/<sha256>`. The design reason is real (a log must be
// complete enough to rebuild from), but the cost was paid by every notebook,
// including the majority that never leave the machine. Deferring the bytes for
// those took the same notebook to 9.57 MB — 1.23×.
//
// The contract these pin, in one sentence: **deferred is not lost.** The
// container is authoritative and still holds every byte, so the moment a
// notebook becomes shared the whole set is materialised from it.
//
// The user-visible version of the invariant: a hollow ring on the sync dot
// ("This computer only") means exactly one copy on disk.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/sync/mirrors.dart';
import 'package:openote/sync/op.dart';
import 'package:openote/sync/op_log.dart';
import 'package:openote/ui/sync_dot.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  /// A workspace plus a separate folder to play the part of a cloud drive.
  Future<(Repository, AppState, String, Directory, Directory)> fixture(
      String prefix) async {
    final ws = Directory.systemTemp.createTempSync(prefix);
    final cloud = Directory.systemTemp.createTempSync('${prefix}cloud_');
    final repo = await Repository.openAt(ws);
    addTearDown(() async {
      await repo.flushWorkspace();
      repo.dispose();
      for (final d in [ws, cloud]) {
        try {
          d.deleteSync(recursive: true);
        } catch (_) {}
      }
    });
    final nb = await repo.createNotebook('Images');
    final app = AppState(repo)..notebookId = nb.id;
    app.reloadNodes();
    return (repo, app, nb.id, ws, cloud);
  }

  OpLogStore logOf(Repository repo, String nb) =>
      OpLogStore.forNotebook(repo.notebooks.firstWhere((n) => n.id == nb).file);

  Uint8List image(int seed) =>
      Uint8List.fromList(List.generate(4096, (i) => (i * seed) & 0xFF));

  test('a local-only notebook stores its images once', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, nb, _, _) = await fixture('onote_mat_local_');

    final bytes = image(3);
    final hash = app.importBlob(nb, bytes, 'image/png');
    final store = logOf(repo, nb);

    // The container has them — it is still authoritative, so nothing is at risk.
    expect(repo.getBlob(nb, hash), bytes);
    // The log does not, and that is the whole saving.
    expect(store.hasBlob(hash), isFalse,
        reason: 'a notebook nothing else reads does not need a second copy');
    expect(store.blobsDir.existsSync(), isFalse,
        reason: 'not even an empty directory should be created');

    // The OP is still written. It costs ~100 bytes, it is what a later
    // materialisation needs in order to know what to fetch, and it keeps the op
    // stream identical whether or not a notebook syncs — so turning sync on
    // never has to synthesise history that was not recorded.
    final puts = store.readAll().where((o) => o.kind == OpKind.blobPut);
    expect(puts, hasLength(1));
    expect(puts.single.map['hash'], hash);
    expect(puts.single.map['size'], bytes.length);

    // And the dot says so, which is the point of matching the two rules.
    expect(syncStateOf(app, nb), SyncState.local);
  });

  test('moving a notebook into a sync folder materialises what it already had',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, nb, _, cloud) = await fixture('onote_mat_move_');

    // Two images written while the notebook was private.
    final a = app.importBlob(nb, image(5), 'image/png');
    final b = app.importBlob(nb, image(9), 'image/jpeg');
    expect(logOf(repo, nb).hasBlob(a), isFalse);

    await app.moveNotebookToFolder(nb, cloud.path);
    await app.awaitBlobBackfill(nb);

    // The backfill reads from the container, so the images written BEFORE the
    // move are there too. This is the property that makes deferring safe.
    final moved = logOf(repo, nb);
    expect(moved.hasBlob(a), isTrue,
        reason: 'the other device needs the images that already existed');
    expect(moved.hasBlob(b), isTrue);
    expect(moved.readBlob(a), image(5));
    expect(syncStateOf(app, nb), SyncState.synced);

    // Nothing was recorded twice: the ops were written at import time.
    expect(moved.readAll().where((o) => o.kind == OpKind.blobPut), hasLength(2));
  });

  test('images added after the move go straight out, without a backfill',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, nb, _, cloud) = await fixture('onote_mat_after_');

    await app.moveNotebookToFolder(nb, cloud.path);
    final hash = app.importBlob(nb, image(11), 'image/png');

    expect(logOf(repo, nb).hasBlob(hash), isTrue,
        reason: 'a synced notebook materialises as it writes, not in a sweep');
  });

  test('a mirror counts as shared — a backup without images is worse than none',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, nb, _, cloud) = await fixture('onote_mat_mirror_');

    final hash = app.importBlob(nb, image(13), 'image/png');
    expect(logOf(repo, nb).hasBlob(hash), isFalse);

    // A PLAIN mirror: keepVersions 0 copies `.onotebook/` and not the
    // container, so an unmaterialised notebook would mirror out to a notebook
    // with no images in it — which looks like a backup and is not one.
    app.addMirror(nb, MirrorTarget(path: cloud.path, keepVersions: 0));
    await app.awaitBlobBackfill(nb);
    // `addMirror` fires a run and doesn't wait; join it here so it can't land
    // after this fixture's directories are gone and fail the next test.
    await app.awaitMirrorRun(nb);

    expect(syncStateOf(app, nb), SyncState.mirrored);
    expect(logOf(repo, nb).hasBlob(hash), isTrue);
  });

  test('naming the folder a notebook already sits in materialises it too',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, nb, ws, _) = await fixture('onote_mat_root_');

    final hash = app.importBlob(nb, image(17), 'image/png');
    expect(logOf(repo, nb).hasBlob(hash), isFalse);

    // The notebook does not move; the user tells us its existing home is a sync
    // location. Same consequence, so it must have the same effect — this is the
    // path a self-hosted Nextcloud or a relocated OneDrive takes.
    app.rememberSyncRoot(ws.path);
    await app.awaitBlobBackfill(nb);

    expect(syncStateOf(app, nb), SyncState.synced);
    expect(logOf(repo, nb).hasBlob(hash), isTrue);
  });

  test('asking for it outright materialises a notebook that is not shared',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, nb, _, _) = await fixture('onote_mat_explicit_');

    final hash = app.importBlob(nb, image(19), 'image/png');
    expect(app.syncMissingBlobs(nb), isNotEmpty,
        reason: 'the log genuinely cannot supply those bytes yet, and saying '
            'so is the honest answer rather than a bug');

    final copied = await app.syncBackfillBlobs(nb);

    expect(copied, 1);
    expect(logOf(repo, nb).hasBlob(hash), isTrue);
    expect(app.syncMissingBlobs(nb), isEmpty);
  });
}
