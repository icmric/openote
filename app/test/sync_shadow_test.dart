// The completeness check ADR-0006 step 2 asks for: with the log written in
// shadow mode alongside the authoritative `.onote`, **rebuilding a page from
// the log must reproduce what the container holds.**
//
// This is the test that makes the whole arrangement worth having. A mutation
// path that forgets to record itself produces no error and no visible symptom —
// it produces a log that is quietly incomplete, and the damage only appears
// much later as a device that will not converge. Here, that same omission
// fails a test on the machine that introduced it.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/sync/materializer.dart';
import 'package:openote/sync/op.dart';
import 'package:openote/sync/op_log.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Future<(Repository, Directory)> freshRepo(String prefix) async {
    final tmp = Directory.systemTemp.createTempSync(prefix);
    return (await Repository.openAt(tmp), tmp);
  }

  /// Rebuild [pageId] from the notebook's log alone.
  Map<String, dynamic> rebuild(Repository repo, String nbId, String pageId) {
    final ref = repo.notebooks.firstWhere((n) => n.id == nbId);
    final store = OpLogStore.forNotebook(ref.file);
    final m = Materializer()..applyAll(store.readAll());
    expect(m.skipped, isEmpty,
        reason: 'nothing in this test writes ops a v1 reader cannot apply');
    return m.pageMirror(pageId);
  }

  test('a saved page rebuilds from the log byte-for-byte', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp) = await freshRepo('onote_shadow_');
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    final nb = await repo.createNotebook('Shadow');
    final app = AppState(repo);
    app.notebookId = nb.id;
    app.reloadNodes();
    final pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
    app.pageId = pageId;
    app.blocks = [
      Block(type: BlockType.text, x: 10, y: 20, content: {'text': 'hello'}),
      Block(type: BlockType.text, x: 40, y: 80, content: {'text': 'world'}),
    ];
    app.pageProps = PageProps(background: 'grid');
    app.markDirty();
    await app.flushSave();

    // What the container holds, in mirror shape with blocks sorted by id — the
    // same normalisation the materializer applies, since array order carries no
    // meaning (render order is the `z` field).
    final stored = repo.readPage(nb.id, pageId);
    final ids = [for (final b in stored.blocks) b.id]..sort();
    final byId = {for (final b in stored.blocks) b.id: b.toJson()};
    final fromContainer = canonicalJson({
      'schema': 'onote-page/1',
      'pageId': pageId,
      'page': stored.props.toJson(),
      'blocks': [for (final id in ids) byId[id]],
    });

    expect(canonicalJson(rebuild(repo, nb.id, pageId)), fromContainer);
  });

  test('an unchanged save appends nothing', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp) = await freshRepo('onote_shadow_noop_');
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    final nb = await repo.createNotebook('Noop');
    final app = AppState(repo);
    app.notebookId = nb.id;
    app.reloadNodes();
    app.pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
    app.blocks = [
      Block(type: BlockType.text, x: 0, y: 0, content: {'text': 'once'})
    ];
    app.markDirty();
    await app.flushSave();

    final ref = repo.notebooks.firstWhere((n) => n.id == nb.id);
    final store = OpLogStore.forNotebook(ref.file);
    final afterFirst = store.readAll().length;

    // Save again with nothing changed. Without the canonical diff in
    // SyncRecorder.page this would append the whole page on every autosave and
    // the log would grow without bound while the notebook stood still.
    app.markDirty();
    await app.flushSave();
    expect(store.readAll().length, afterFirst);
  });

  test('editing one block of a page appends one op, not the page', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp) = await freshRepo('onote_shadow_gran_');
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    final nb = await repo.createNotebook('Gran');
    final app = AppState(repo);
    app.notebookId = nb.id;
    app.reloadNodes();
    app.pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
    final a = Block(type: BlockType.text, x: 0, y: 0, content: {'text': 'a'});
    final b = Block(type: BlockType.text, x: 0, y: 50, content: {'text': 'b'});
    app.blocks = [a, b];
    app.markDirty();
    await app.flushSave();

    final ref = repo.notebooks.firstWhere((n) => n.id == nb.id);
    final store = OpLogStore.forNotebook(ref.file);
    final before = store.readAll().length;

    // Touch ONE block. Block-level granularity (ADR-0006 §6a.1) is the whole
    // reason two devices editing different parts of a page can both win.
    b.content['text'] = 'b changed';
    b.updatedAt = nowMs() + 1;
    app.markDirty();
    await app.flushSave();

    final added = store.readAll().skip(before).toList();
    expect(added, hasLength(1));
    expect(added.single.kind, OpKind.blockSet);
    expect((added.single.map['block'] as Map)['id'], b.id);
  });

  test('blob bytes land in blobs/, content-addressed and deduplicated',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp) = await freshRepo('onote_shadow_blob_');
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    final nb = await repo.createNotebook('Blobs');
    final app = AppState(repo);
    app.notebookId = nb.id;
    app.reloadNodes();

    final bytes = Uint8List.fromList(List.generate(64, (i) => i));
    final hash = app.addBlob(bytes, 'image/png');

    final ref = repo.notebooks.firstWhere((n) => n.id == nb.id);
    final store = OpLogStore.forNotebook(ref.file);

    // The bytes are a file named by their own hash, not a log entry — which is
    // what lets two devices produce identical files independently and skip
    // merging blobs entirely.
    expect(store.hasBlob(hash), isTrue);
    expect(store.readBlob(hash), bytes);
    expect(store.blobHashes(), contains(hash));

    // The op carries metadata only; the log must not balloon with image bytes.
    final puts =
        store.readAll().where((o) => o.kind == OpKind.blobPut).toList();
    expect(puts, hasLength(1));
    expect(puts.single.map['size'], 64);
    expect(puts.single.map.containsKey('bytes'), isFalse);

    // Storing identical content again is a no-op: content-addressed data can
    // never legitimately change, so re-import rewrites nothing.
    app.addBlob(bytes, 'image/png');
    expect(store.readAll().where((o) => o.kind == OpKind.blobPut), hasLength(1));

    // And nothing referenced by the log is missing its bytes — the property
    // that makes a rebuild able to reconstruct content, not just structure.
    expect(app.syncMissingBlobs(nb.id), isEmpty);
  });

  test('blobs written before the log existed are backfilled', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp) = await freshRepo('onote_shadow_backfill_');
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    final nb = await repo.createNotebook('Backfill');
    // Written straight to the container, as every notebook created before the
    // op log existed was.
    final bytes = Uint8List.fromList(List.filled(32, 7));
    final hash = repo.putBlob(nb.id, bytes, 'image/png');

    final ref = repo.notebooks.firstWhere((n) => n.id == nb.id);
    final store = OpLogStore.forNotebook(ref.file);
    expect(store.hasBlob(hash), isFalse, reason: 'not in the log yet');

    final app = AppState(repo);
    app.notebookId = nb.id;
    app.reloadNodes();
    await app.syncBackfillBlobs(nb.id);

    expect(store.hasBlob(hash), isTrue);
    expect(store.readBlob(hash), bytes);
    expect(app.syncMissingBlobs(nb.id), isEmpty);
  });

  test('a notebook rename reaches the log', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp) = await freshRepo('onote_shadow_meta_');
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    final nb = await repo.createNotebook('Before');
    final app = AppState(repo);
    app.notebookId = nb.id;
    app.reloadNodes();
    await app.renameNotebook(nb.id, 'After');

    final ref = repo.notebooks.firstWhere((n) => n.id == nb.id);
    final store = OpLogStore.forNotebook(ref.file);
    final m = Materializer()..applyAll(store.readAll());
    // Without notebook.meta ops a rebuild recovers every page and the whole
    // tree, but not what the notebook is called.
    expect(m.meta['title'], 'After');

    // Renaming to the same title again records nothing.
    final before = store.readAll().length;
    await app.renameNotebook(nb.id, 'After');
    expect(store.readAll().length, before);
  });

  test('a deleted page is deleted in the log, and restore is what undoes it',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp) = await freshRepo('onote_shadow_del_');
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    final nb = await repo.createNotebook('Del');
    final app = AppState(repo);
    app.notebookId = nb.id;
    app.reloadNodes();
    final pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
    app.pageId = pageId;

    await app.deleteNode(pageId);
    final ref = repo.notebooks.firstWhere((n) => n.id == nb.id);
    final store = OpLogStore.forNotebook(ref.file);

    var m = Materializer()..applyAll(store.readAll());
    expect(m.nodes[pageId]?.deletedAt, isNotNull);
    expect(m.liveNodes().map((n) => n.id), isNot(contains(pageId)));

    await app.restoreDeleted(pageId);
    m = Materializer()..applyAll(store.readAll());
    expect(m.nodes[pageId]?.deletedAt, isNull);
    expect(m.liveNodes().map((n) => n.id), contains(pageId));
  });
}
