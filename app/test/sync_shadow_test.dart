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

  test('erasing one stroke appends a small ink op, not the whole block',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp) = await freshRepo('onote_shadow_ink_');
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    final nb = await repo.createNotebook('Ink');
    final app = AppState(repo);
    app.notebookId = nb.id;
    app.reloadNodes();
    app.pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;

    // A dense ink block — the imported-notebook shape (one block, many
    // strokes). 200 strokes × 50 points is ~350 KB serialized.
    List<double> ramp(int n, double base) =>
        [for (var i = 0; i < n; i++) base + i.toDouble()];
    final strokes = [
      for (var s = 0; s < 200; s++)
        Stroke(
          tool: 'pen',
          colorHex: '#000000',
          size: 2.5,
          x: ramp(50, s * 10.0),
          y: ramp(50, 0),
        ).toJson()
    ];
    final ink = Block(type: BlockType.ink, x: 0, y: 0, content: {
      'strokes': strokes,
    });
    app.blocks = [ink];
    app.markDirty();
    await app.flushSave();

    final ref = repo.notebooks.firstWhere((n) => n.id == nb.id);
    final store = OpLogStore.forNotebook(ref.file);
    final logFile = store.logFor(
        store.deviceIds().single); // one device in this test
    final sizeAfterBaseline = logFile.lengthSync();

    // Erase-like edit: split stroke 10 into two fragments at its position —
    // exactly what _eraseAt does.
    final list = (ink.content['strokes'] as List);
    final victim = (list[10] as Map).cast<String, dynamic>();
    final frag1 = Stroke(
            tool: 'pen',
            colorHex: '#000000',
            size: 2.5,
            x: ((victim['x'] as List).cast<double>()).sublist(0, 20),
            y: ((victim['y'] as List).cast<double>()).sublist(0, 20))
        .toJson();
    final frag2 = Stroke(
            tool: 'pen',
            colorHex: '#000000',
            size: 2.5,
            x: ((victim['x'] as List).cast<double>()).sublist(30),
            y: ((victim['y'] as List).cast<double>()).sublist(30))
        .toJson();
    list
      ..removeAt(10)
      ..insert(10, frag1)
      ..insert(11, frag2);
    ink.updatedAt = nowMs() + 5;
    app.markDirty();
    await app.flushSave();

    final appended = logFile.lengthSync() - sizeAfterBaseline;
    final ops = store.readAll();
    expect(ops.last.kind, OpKind.inkStrokes,
        reason: 'an erase must not re-record the whole block');
    // The whole block is ~350 KB; the erase touched one stroke. The appended
    // record must be O(changed strokes), not O(block).
    expect(appended, lessThan(20 * 1024),
        reason: 'appended $appended bytes for a one-stroke split');

    // And the rebuild still matches the container byte-for-byte — order
    // included, which is the risky part of positional inserts.
    expect(canonicalJson(rebuild(repo, nb.id, app.pageId!)),
        canonicalJson({
          'schema': 'onote-page/1',
          'pageId': app.pageId,
          'page': app.pageProps.toJson(),
          'blocks': [ink.toJson()],
        }));
  });

  test('dragging an ink block falls back to block.set (the >50% guard)',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp) = await freshRepo('onote_shadow_inkmove_');
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    final nb = await repo.createNotebook('InkMove');
    final app = AppState(repo);
    app.notebookId = nb.id;
    app.reloadNodes();
    app.pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;

    final ink = Block(type: BlockType.ink, x: 0, y: 0, content: {
      'strokes': [
        for (var s = 0; s < 4; s++)
          Stroke(
                  tool: 'pen',
                  colorHex: '#000000',
                  size: 2.5,
                  x: [s * 10.0, s * 10.0 + 1],
                  y: [0, 1])
              .toJson()
      ],
    });
    app.blocks = [ink];
    app.markDirty();
    await app.flushSave();

    // A drag rewrites EVERY stroke's coordinates — a per-stroke record would
    // be larger than the block itself.
    for (final s in (ink.content['strokes'] as List)) {
      final m = (s as Map).cast<String, dynamic>();
      m['x'] = [for (final v in (m['x'] as List)) (v as num) + 100.0];
      m['y'] = [for (final v in (m['y'] as List)) (v as num) + 100.0];
    }
    ink.x += 100;
    ink.y += 100;
    ink.updatedAt = nowMs() + 5;
    app.markDirty();
    await app.flushSave();

    final ref = repo.notebooks.firstWhere((n) => n.id == nb.id);
    final store = OpLogStore.forNotebook(ref.file);
    expect(store.readAll().last.kind, OpKind.blockSet);
    expect(canonicalJson(rebuild(repo, nb.id, app.pageId!)),
        canonicalJson({
          'schema': 'onote-page/1',
          'pageId': app.pageId,
          'page': app.pageProps.toJson(),
          'blocks': [ink.toJson()],
        }));
  });

  group('two devices (ADR-0006 step 3)', () {
    /// Write ops as if another machine had synced its log in beside ours.
    /// That IS the transport in this design: a device only ever appends to its
    /// own file, so "another device edited" and "a file appeared" are the same
    /// event, and there is nothing to resolve.
    void otherDeviceWrites(OpLogStore store, List<Op> ops) =>
        store.append('other-device', ops);

    Op op(int seq, int lamport, OpKind kind, Map<String, dynamic> d) => Op(
        device: 'other-device',
        seq: seq,
        lamport: lamport,
        timestamp: 1000 + seq,
        kind: kind,
        data: d);

    test('a remote page edit lands in the container', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp) = await freshRepo('onote_sync_pull_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final nb = await repo.createNotebook('Pull');
      final app = AppState(repo);
      app.notebookId = nb.id;
      app.reloadNodes();
      final pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
      app.pageId = pageId;
      app.blocks = [
        Block(type: BlockType.text, x: 0, y: 0, content: {'text': 'mine'})
      ];
      app.markDirty();
      await app.flushSave();

      final ref = repo.notebooks.firstWhere((n) => n.id == nb.id);
      final store = OpLogStore.forNotebook(ref.file);

      // The other device adds a DIFFERENT block to the same page — the case
      // block-level ops exist to make work.
      otherDeviceWrites(store, [
        op(1, 500, OpKind.blockSet, {
          'pageId': pageId,
          'block': {
            'id': 'remote-block',
            'type': 'text',
            'x': 0,
            'y': 100,
            'w': 320,
            'content': {'text': 'theirs'}
          }
        }),
      ]);

      final pulled = await app.syncPull(nb.id);
      expect(pulled, 1);

      // Both edits survive, in the container, not just in memory.
      final stored = repo.readPage(nb.id, pageId);
      final texts = [
        for (final b in stored.blocks) b.content['text'] as String?
      ];
      expect(texts, containsAll(<String>['mine', 'theirs']));
    });

    test('pulling twice is a no-op (the watermark holds)', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp) = await freshRepo('onote_sync_twice_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final nb = await repo.createNotebook('Twice');
      final app = AppState(repo);
      app.notebookId = nb.id;
      app.reloadNodes();
      final pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
      app.pageId = pageId;

      final ref = repo.notebooks.firstWhere((n) => n.id == nb.id);
      final store = OpLogStore.forNotebook(ref.file);
      otherDeviceWrites(store, [
        op(1, 500, OpKind.blockSet, {
          'pageId': pageId,
          'block': {
            'id': 'r1',
            'type': 'text',
            'x': 0,
            'y': 0,
            'w': 320,
            'content': {'text': 'remote'}
          }
        }),
      ]);

      expect(await app.syncPull(nb.id), 1);
      expect(await app.syncPull(nb.id), 0,
          reason: 'already folded in; re-applying would be work for nothing');
    });

    test('a remote page creation appears in the tree', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp) = await freshRepo('onote_sync_tree_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final nb = await repo.createNotebook('Tree');
      final app = AppState(repo);
      app.notebookId = nb.id;
      app.reloadNodes();
      final section =
          app.nodes.firstWhere((n) => n.kind == NodeKind.section).id;

      final ref = repo.notebooks.firstWhere((n) => n.id == nb.id);
      final store = OpLogStore.forNotebook(ref.file);
      otherDeviceWrites(store, [
        op(1, 500, OpKind.nodeUpsert, {
          'id': 'remote-page',
          'kind': 'page',
          'parentId': section,
          'title': 'Made elsewhere',
          'position': 'a999',
          'level': 0,
          'createdAt': 1,
          'updatedAt': 2,
        }),
      ]);

      await app.syncPull(nb.id);
      expect(app.nodes.map((n) => n.title), contains('Made elsewhere'));
    });

    test('a remote delete wins over a local edit', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp) = await freshRepo('onote_sync_del_');
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
      final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
      // Local edit of the page's title, recorded to our own log.
      app.renameNode(page.id, 'Renamed here');

      final ref = repo.notebooks.firstWhere((n) => n.id == nb.id);
      final store = OpLogStore.forNotebook(ref.file);
      otherDeviceWrites(store, [
        op(1, 1, OpKind.nodeDelete, {'id': page.id, 'deletedAt': 500}),
      ]);

      await app.syncPull(nb.id);
      // ADR-0006 §6a.3: delete wins, whichever sorts later — and it is
      // recoverable because it lands in the recycle bin, not the void.
      expect(app.nodes.map((n) => n.id), isNot(contains(page.id)));
    });
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
