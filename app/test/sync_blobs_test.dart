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
    addTearDown(repo.dispose);
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
    final probe =
        await Repository.openAt(Directory.systemTemp.createTempSync('h_'));
    final nb = await probe.createNotebook('probe');
    final h = probe.putBlob(nb.id, bytes, 'image/png');
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
