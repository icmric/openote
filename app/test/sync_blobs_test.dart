// Do images survive the trip between devices?
//
// Blobs travel differently from everything else in ADR-0006: an op carries only
// the hash, mime and size, and the bytes go beside the log as a
// content-addressed file. That is the right design — putting megabytes of image
// into an append-only log makes it unbounded — but it means the two halves have
// to be re-joined on the receiving device, and nothing was doing that.
//
// The consequence was worse than a missing picture. `blob_refs.hash` is a
// foreign key onto `blobs`, so writing a page that references bytes the
// container does not hold raises a constraint violation, and it does so inside
// the pull's transaction: **one shared notebook with one image in it stopped
// that device syncing at all**, for every page in the batch, not just the one
// with the picture.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/sync/op.dart';
import 'package:openote/sync/op_log.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  /// A notebook with one page open, plus the shared log store another device
  /// would be writing into.
  Future<(Repository, AppState, String, String, OpLogStore)> fixture(
      String name) async {
    final tmp = Directory.systemTemp.createTempSync(name);
    addTearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final repo = await Repository.openAt(tmp);
    // **Flush before dispose, and before the directory above is deleted.**
    //
    // `selectPage` below marks the session dirty, which arms a 400 ms
    // debounced write of `workspace.json`. `dispose()` cancels that timer, but
    // if it has already FIRED the write is mid-flight and nobody awaits it —
    // so on a slow runner it lands after the temp directory is gone and
    // raises an unhandled `PathNotFoundException`, which `flutter test`
    // charges to whichever test is running at that moment.
    //
    // That is the whole of the intermittent Windows failure in this file: not
    // a filesystem-semantics difference like the previous two, just a machine
    // slow enough to lose a race that Linux and macOS happened to win.
    // `repository.dart` no longer lets that error escape either — belt and
    // braces, because the same shape exists in ten other test files.
    addTearDown(() async {
      await repo.flushWorkspace();
      repo.dispose();
    });
    final nb = await repo.createNotebook('Shared');
    final app = AppState(repo)..notebookId = nb.id;
    app.reloadNodes();
    final pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
    await app.selectPage(pageId);
    final ref = repo.notebooks.firstWhere((n) => n.id == nb.id);
    return (repo, app, nb.id, pageId, OpLogStore.forNotebook(ref.file));
  }

  /// The real content hash of [bytes] — `putBlob` derives it from the bytes
  /// rather than trusting a caller, so a made-up hash would name a different
  /// blob and prove nothing.
  Future<String> hashOf(Uint8List bytes) async {
    final dir = Directory.systemTemp.createTempSync('h_');
    // Cleaned up like every other temp directory here. Four calls per run were
    // leaving ~76 KB each behind for the life of the machine.
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final probe = await Repository.openAt(dir);
    final nb = await probe.createNotebook('probe');
    final h = probe.putBlob(nb.id, bytes, 'image/png');
    await probe.flushWorkspace();
    probe.dispose();
    return 'sha256:$h';
  }

  Uint8List image([int seed = 0]) =>
      Uint8List.fromList(List.generate(2048, (i) => (i + seed) % 256));

  /// What `SyncRecorder.blob()` + `page()` produce on the other machine.
  void otherDeviceAddsImage(
      OpLogStore store, String pageId, String hash, Uint8List bytes,
      {bool withBytes = true, int from = 1}) {
    if (withBytes) store.writeBlob(hash, bytes);
    store.append('other-device', [
      Op(
          device: 'other-device',
          seq: from,
          lamport: 500 + from,
          timestamp: 1000 + from,
          kind: OpKind.blobPut,
          data: {'hash': hash, 'mime': 'image/png', 'size': bytes.length}),
      Op(
          device: 'other-device',
          seq: from + 1,
          lamport: 501 + from,
          timestamp: 1001 + from,
          kind: OpKind.blockSet,
          data: {
            'pageId': pageId,
            'block': {
              'id': 'remote-$from',
              'type': 'text',
              'x': 0.0,
              'y': 0.0,
              'w': 320.0,
              'content': {'text': '![]($hash)'}
            }
          }),
    ]);
  }

  test('an image made on another device arrives with its bytes', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, nb, pageId, store) = await fixture('onote_blob_pull_');
    final bytes = image();
    final hash = await hashOf(bytes);

    otherDeviceAddsImage(store, pageId, hash, bytes);

    // Without the fix this THROWS rather than returning — the assertion that
    // matters most is simply that the pull completes.
    expect(await app.syncPull(nb), 2);
    expect(app.blob(hash), isNotNull,
        reason: 'the page references it, so the container must hold it');
    expect(app.blob(hash)!.length, bytes.length);
  });

  test('a reference whose bytes have not arrived does not break the pull',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, nb, pageId, store) = await fixture('onote_blob_late_');
    final bytes = image(7);
    final hash = await hashOf(bytes);

    // The log synced before the blob file did — normal with any cloud client,
    // which copies the two independently.
    otherDeviceAddsImage(store, pageId, hash, bytes, withBytes: false);
    expect(await app.syncPull(nb), 2,
        reason: 'a not-yet-copied image must not fail the whole batch');
    expect(app.blob(hash), isNull);

    // The text of the page still arrived, which is the point: everything that
    // could be delivered was.
    final stored = repo.readPage(nb, pageId);
    expect(stored.blocks.any((b) => '${b.content['text']}'.contains(hash)),
        isTrue);

    // And when the file turns up, a later pull collects it.
    store.writeBlob(hash, bytes);
    otherDeviceAddsImage(store, pageId, hash, bytes, from: 3);
    await app.syncPull(nb);
    expect(app.blob(hash), isNotNull);
  });

  test('bytes that do not match their hash are refused', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, nb, pageId, store) = await fixture('onote_blob_bad_');
    final bytes = image(3);
    final hash = await hashOf(bytes);

    // A truncated download: the file exists under the right name but holds the
    // wrong bytes. Content-addressing is only worth anything if we check.
    store.writeBlob(hash, Uint8List.fromList([1, 2, 3]));
    store.append('other-device', [
      Op(
          device: 'other-device',
          seq: 1,
          lamport: 500,
          timestamp: 1000,
          kind: OpKind.blobPut,
          data: {'hash': hash, 'mime': 'image/png', 'size': bytes.length}),
    ]);

    await app.syncPull(nb);
    expect(app.blob(hash), isNull,
        reason: 'storing them under their real hash would leave the page '
            'pointing at nothing while looking like it worked');
  });

  // `blobs/` IS the replicated folder: a deletion here is replicated to every
  // other device, removing their GOOD copy under the canonical name — and
  // once Step 7 empties the container there is no copy left anywhere. So the
  // pull may disbelieve a file, but it may never delete it: it holds the hash
  // out of the read path and lets the good copy arrive (or `proveBlobs`'
  // repair, which holds verified container bytes, rewrite it).
  test('a mismatched blob file is held out of reach, never deleted', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, nb, pageId, store) = await fixture('onote_blob_hold_');
    final bytes = image(5);
    final hash = await hashOf(bytes);

    // A half-copied download: right name, wrong bytes.
    store.writeBlob(hash, Uint8List.fromList([1, 2, 3]));
    store.append('other-device', [
      Op(
          device: 'other-device',
          seq: 1,
          lamport: 500,
          timestamp: 1000,
          kind: OpKind.blobPut,
          data: {'hash': hash, 'mime': 'image/png', 'size': bytes.length}),
    ]);
    await app.syncPull(nb);

    expect(app.blob(hash), isNull,
        reason: 'the wrong bytes must not be served as a picture');
    // MUTATION: put `r.store.discardBlob(hash)` back in
    // `_rejectBadForeignBlobs` and this fails — and in the field the cloud
    // client replicates that deletion into every other device's good copy.
    expect(store.hasBlob(hash), isTrue,
        reason: 'deleting in a shared folder on local evidence is the bug');

    // The cloud client finishes (or re-delivers) the copy under the same
    // name. `writeBlob` refuses to overwrite, so this is the client's own
    // file replacement.
    store.blobFile(hash).writeAsBytesSync(bytes, flush: true);
    // MUTATION: drop the held-hash re-verify from `Repository.getBlob` and
    // this fails — the hold would outlive the repair for ever.
    expect(app.blob(hash), bytes,
        reason: 'the hold lifts itself the moment the bytes match the name');
  });

  // A blob file that lands AFTER its op has folded is never named by any
  // later op — the pull's check ran while there was nothing to check, and
  // `getBlob` does not re-hash on the ordinary path. The held register is
  // what closes that gap, for the documented-normal log-before-picture
  // ordering of every cloud client.
  test('a file that lands after its op folded is verified before it is served',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, nb, pageId, store) = await fixture('onote_blob_land_');
    final bytes = image(13);
    final hash = await hashOf(bytes);

    // Log first, picture later — the ordinary cloud-client ordering.
    otherDeviceAddsImage(store, pageId, hash, bytes, withBytes: false);
    expect(await app.syncPull(nb), 2);
    expect(app.blob(hash), isNull);

    // The file starts landing — and is caught half-copied: right name,
    // wrong bytes. No pull will ever name this hash again.
    store.writeBlob(hash, Uint8List.fromList([9, 9, 9]));
    // MUTATION: remove `holdBlobUntilVerified` from the not-arrived branch
    // of `_rejectBadForeignBlobs` and this serves three bytes of garbage as
    // the picture, unverified, all session.
    expect(app.blob(hash), isNull,
        reason: 'an unverified late arrival must not be served');

    // The copy completes; the folder watcher would fire a pull for it.
    store.blobFile(hash).writeAsBytesSync(bytes, flush: true);
    expect(await app.syncPull(nb), 0);
    // MUTATION: remove `_repo.verifyHeldBlobs(nb)` from `syncPull` and this
    // returns 1 — the pull no longer sweeps, leaving verification to chance.
    expect(repo.verifyHeldBlobs(nb), 0,
        reason: 'the pull itself must have already verified and released it');
    expect(app.blob(hash), bytes);
  });

  // `blobBytesMatch` answers false for a file it could not READ — a cloud
  // client's lock, a dehydrated placeholder — and the old code fed that
  // false straight into the discard: a perfectly good file, deleted (and the
  // deletion replicated) because it was momentarily busy.
  test('a file the pull cannot read is not treated as bad', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // Windows enforces file locks against every handle, which is exactly the
    // "cloud client holding the file" shape; elsewhere locks are advisory and
    // the scenario cannot be built.
    if (!Platform.isWindows) {
      return markTestSkipped('needs mandatory file locking');
    }
    final (repo, app, nb, pageId, store) = await fixture('onote_blob_lock_');
    final bytes = image(21);
    final hash = await hashOf(bytes);

    store.writeBlob(hash, bytes); // the GOOD bytes, mid-"sync"
    store.append('other-device', [
      Op(
          device: 'other-device',
          seq: 1,
          lamport: 500,
          timestamp: 1000,
          kind: OpKind.blobPut,
          data: {'hash': hash, 'mime': 'image/png', 'size': bytes.length}),
    ]);

    final raf = store.blobFile(hash).openSync(mode: FileMode.append);
    raf.lockSync();
    try {
      await app.syncPull(nb);
    } finally {
      raf.unlockSync();
      raf.closeSync();
    }

    expect(store.hasBlob(hash), isTrue,
        reason: 'a file that could not be checked was never evidence of '
            'anything — deleting it cost the only copy');
    // MUTATION: classify unreadable as bad (hold it) in
    // `_rejectBadForeignBlobs` and this is 1, not 0.
    expect(repo.verifyHeldBlobs(nb), 0,
        reason: '"could not check" must not put a good file on the register');
    expect(app.blob(hash), bytes, reason: 'released, it reads normally');
  });

  test('a blob already held is not copied again', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, nb, pageId, store) = await fixture('onote_blob_dupe_');
    final bytes = image(11);
    final hash = await hashOf(bytes);

    otherDeviceAddsImage(store, pageId, hash, bytes);
    await app.syncPull(nb);
    final first = app.blob(hash)!.length;

    otherDeviceAddsImage(store, pageId, hash, bytes, from: 3);
    await app.syncPull(nb);
    expect(app.blob(hash)!.length, first);
  });
}
