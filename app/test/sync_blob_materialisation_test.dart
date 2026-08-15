// A notebook's images are in `.onotebook/blobs/` **always** — v0.17 Step 5.
//
// **This file used to pin the opposite, and the reversal is the point.**
// Storage wave 1a deferred the bytes for any notebook nothing else was going to
// read, on a measurement worth having: a synthetic 40-page, 20-image notebook
// went 17.39 MB → 9.57 MB (2.23× → 1.23×) by storing each picture once. The
// argument for it was "deferred is not lost — the container is authoritative
// and still holds every byte".
//
// That argument was true and the consequence was still unacceptable, because
// it made the *log* unable to rebuild the notebook it describes. Measured on
// the owner's real post-Phase-1 import: **378 of the 488 blobs its log names
// had no bytes on disk — every one an `image/png`, 26,325,596 B** — so a
// rebuild produced a structurally perfect notebook (same=329 differing=0) in
// which 271 of 271 image blocks were broken across 44 pages. Nothing said so,
// because a page names a picture by hash and a page whose bytes are gone is
// byte-identical to the same page with its bytes intact.
//
// So the trade is reversed: every notebook pays the second copy, and the log is
// a complete rebuild authority for the local-only majority as well as for the
// shared few. Step 7 of the plan takes the container's copy away again, at
// which point "stored once" is true and it is the log's copy that survives.
// What these tests now pin is that no path — import, move, mirror, sync root —
// can leave a picture with only one copy of itself in the wrong place. The
// byte-level half of the invariant is `blob_proof_test.dart`.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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

  /// The notebook's log, wherever it actually is.
  ///
  /// **Through `logDir`, not the container's sibling.** Since v0.17 Step 4 a
  /// notebook moved into a sync folder leaves its container in the workspace
  /// and sends only the `.onotebook`, so deriving the log path from `.file`
  /// finds an empty directory beside the container and every assertion below
  /// silently passes on nothing.
  OpLogStore logOf(Repository repo, String nb) {
    final ref = repo.notebooks.firstWhere((n) => n.id == nb);
    return OpLogStore.forNotebook(ref.file, logDir: ref.logDir);
  }

  Uint8List image(int seed) =>
      Uint8List.fromList(List.generate(4096, (i) => (i * seed) & 0xFF));

  test('a local-only notebook writes its images out too', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, nb, _, _) = await fixture('onote_mat_local_');

    final bytes = image(3);
    final hash = app.importBlob(nb, bytes, 'image/png');
    final store = logOf(repo, nb);

    // The container has them — it is still authoritative until Step 7.
    expect(repo.getBlob(nb, hash), bytes);
    // And so does the log's folder, which is the reversal. This assertion was
    // `isFalse` until Step 5, and every byte of the owner's 26.3 MB hole was
    // written by the branch that made it false.
    expect(store.hasBlob(hash), isTrue,
        reason: 'a notebook nothing else reads today may be shared, mirrored '
            'or rebuilt tomorrow, and only the bytes decide whether its '
            'pictures survive that');
    expect(store.readBlob(hash), bytes,
        reason: 'present is not enough — the same bytes, or the picture is '
            'broken in a way nothing on screen can show');

    // The OP is written either way, and always was. It costs ~100 bytes and it
    // keeps the op stream identical whether or not a notebook syncs.
    final puts = store.readAll().where((o) => o.kind == OpKind.blobPut);
    expect(puts, hasLength(1));
    expect(puts.single.map['hash'], hash);
    expect(puts.single.map['size'], bytes.length);

    // The dot still says "this computer only": how many copies of the bytes
    // exist and how many machines hold the notebook are different questions,
    // and Step 5 changed only the first.
    expect(syncStateOf(app, nb), SyncState.local);
  });

  test('moving a notebook into a sync folder materialises what it already had',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, nb, _, cloud) = await fixture('onote_mat_move_');

    // Two images written while the notebook was private — and already
    // materialised, since Step 5.
    final a = app.importBlob(nb, image(5), 'image/png');
    final b = app.importBlob(nb, image(9), 'image/jpeg');
    await app.settleBackgroundWork();
    expect(logOf(repo, nb).hasBlob(a), isTrue);

    await app.moveNotebookToFolder(nb, cloud.path);
    await app.awaitBlobBackfill(nb);

    // **The move must carry the bytes, not merely the ops.** `moveNotebookTo`
    // relocates the whole `.onotebook`, so this is really asking that the
    // pictures went with it — and that the backfill at the destination, which
    // reads from the container, would have supplied any that had not.
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
    await app.settleBackgroundWork();

    // A PLAIN mirror: keepVersions 0 copies `.onotebook/` and not the
    // container, so an unmaterialised notebook would mirror out to a notebook
    // with no images in it — which looks like a backup and is not one. Step 5
    // makes that unreachable rather than merely repaired in time: the assertion
    // below is now true before `addMirror` is called as well as after, and the
    // mirrored copy is what actually proves it.
    app.addMirror(nb, MirrorTarget(path: cloud.path, keepVersions: 0));
    await app.awaitBlobBackfill(nb);
    // `addMirror` fires a run and doesn't wait; join it here so it can't land
    // after this fixture's directories are gone and fail the next test.
    await app.awaitMirrorRun(nb);

    expect(syncStateOf(app, nb), SyncState.mirrored);
    expect(logOf(repo, nb).hasBlob(hash), isTrue);
    expect(
        File(p.join(cloud.path, 'Images.onotebook', 'blobs', hash))
            .readAsBytesSync(),
        image(13),
        reason: 'the backup has to contain the picture, not a reference to one');
  });

  test('naming the folder a notebook already sits in materialises it too',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, nb, ws, _) = await fixture('onote_mat_root_');

    final hash = app.importBlob(nb, image(17), 'image/png');
    await app.settleBackgroundWork();

    // The notebook does not move; the user tells us its existing home is a sync
    // location. Same consequence, so it must have the same effect — this is the
    // path a self-hosted Nextcloud or a relocated OneDrive takes.
    app.rememberSyncRoot(ws.path);
    await app.awaitBlobBackfill(nb);

    expect(syncStateOf(app, nb), SyncState.synced);
    expect(logOf(repo, nb).hasBlob(hash), isTrue);
  });

  test('a notebook whose bytes predate Step 5 is materialised on demand',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, nb, _, _) = await fixture('onote_mat_explicit_');

    // Written straight through Repository, so nothing materialises it and no
    // op names it: the exact state every notebook imported before Step 5 is in,
    // and the state the owner's Honours-4 was measured in.
    final hash = repo.putBlob(nb, image(19), 'image/png');
    expect(app.syncMissingBlobs(nb), isEmpty,
        reason: 'the log does not name it yet, so it is not yet MISSING — '
            'which is exactly why the backfill works from the container index '
            'and not from the log');

    // **The return value is not the assertion, and this is the trap the plan
    // names.** `syncBackfillBlobs` opens a recorder, and opening one now starts
    // its own backfill, so by the time this call looks there may be nothing
    // left to copy and it returns 0 — the same number it returns when it was
    // never allowed to look. Only the bytes on disk answer the question.
    await app.syncBackfillBlobs(nb);
    await app.settleBackgroundWork();

    expect(logOf(repo, nb).readBlob(hash), image(19));
    expect(app.syncMissingBlobs(nb), isEmpty);
    expect((await app.proveBlobBytes(nb)).ok, isTrue);
  });

  test('nothing that adds a picture can leave it with one copy in `blobs/`',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, nb, _, cloud) = await fixture('onote_mat_allpaths_');

    // Each of the four states a notebook can be in, one picture added in each.
    final local = app.importBlob(nb, image(21), 'image/png');
    app.rememberSyncRoot(cloud.path);
    final root = app.importBlob(nb, image(23), 'image/png');
    app.addMirror(nb, MirrorTarget(path: cloud.path, keepVersions: 0));
    final mirrored = app.importBlob(nb, image(25), 'image/png');
    app.debugSetGitSetting(nb, 'https://example.invalid/notes.git');
    final gitted = app.importBlob(nb, image(27), 'image/png');

    await app.settleBackgroundWork();
    await app.awaitMirrorRun(nb);

    final store = logOf(repo, nb);
    for (final (name, hash, bytes) in [
      ('local-only', local, image(21)),
      ('sync root remembered', root, image(23)),
      ('mirrored', mirrored, image(25)),
      ('git remote', gitted, image(27)),
    ]) {
      expect(store.readBlob(hash), bytes, reason: 'added while $name');
    }
    expect(app.syncMissingBlobs(nb), isEmpty);
    expect((await app.proveBlobBytes(nb)).ok, isTrue);
  });
}
