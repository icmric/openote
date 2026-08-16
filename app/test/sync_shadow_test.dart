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

import 'package:openote/ink/ink_storage.dart';
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
    // A SHARED notebook, because since v0.10 the bytes are only materialised
    // when something other than this device is going to read them. Everything
    // in this fixture lives under `tmp`, so calling that a sync location makes
    // the notebook shared without moving a single file.
    app.rememberSyncRoot(tmp.path);

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

  // Since v0.10 this is not only the migration path: every local-only notebook
  // defers its blob bytes, so this is also what runs the moment one is prepared
  // for sync. Same mechanism, now the normal one.
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
    final hash = repo.putContainerBlobForTest(nb.id, bytes, 'image/png');

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

    // **The assertion changed shape because the mechanism did, and the intent
    // is what matters.**
    //
    // This used to require `OpKind.inkStrokes` — a per-stroke diff that
    // existed for one reason: an ink `block.set` carried every stroke as JSON,
    // so re-recording the block cost hundreds of kilobytes. Ink is now a blob
    // reference, so an ink `block.set` is a few hundred BYTES and the
    // per-stroke op has nothing left to optimise. The requirement — an erase
    // must not cost the size of the block — is met more thoroughly than
    // before, not abandoned.
    expect(store.readAll().last.kind, OpKind.blockSet);
    // Tighter than the 20 KB this asked for, because the whole block is now
    // smaller than the old "small" record. What lands is one blob of the
    // re-encoded strokes plus a tiny `block.set`.
    expect(appended, lessThan(20 * 1024),
        reason: 'appended $appended bytes for a one-stroke split');

    // And the rebuild still matches the container exactly — order included,
    // which is the risky part of positional inserts. Compared against what is
    // PERSISTED: the live block holds inline strokes, the container holds the
    // reference, and they are the same handwriting in two representations.
    final stored = repo.readPage(nb.id, app.pageId!);
    final rebuilt = rebuild(repo, nb.id, app.pageId!);
    final rebuiltBlocks = (rebuilt['blocks'] as List);
    expect(rebuiltBlocks, hasLength(1));
    final rebuiltInk =
        Block.fromJson((rebuiltBlocks.single as Map).cast<String, dynamic>());
    expect(InkStorage.refsOf(rebuiltInk.content),
        InkStorage.refsOf(stored.blocks.single.content),
        reason: 'the log and the container must reference the same ink');
    expect(InkStorage.strokeCount(rebuiltInk.content),
        (ink.content['strokes'] as List).length,
        reason: 'and the same number of strokes as the editor holds');
  });

  // Renamed from "falls back to block.set (the >50% guard)". There is no
  // fallback and no guard any more: a `block.set` is what an ink change always
  // writes, and it is small because the geometry is a reference. The property
  // still worth pinning is that a drag — which rewrites every coordinate —
  // stays cheap and still rebuilds correctly.
  test('dragging an ink block stays cheap and rebuilds', () async {
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

    final stored = repo.readPage(nb.id, app.pageId!);
    final rebuiltInk = Block.fromJson(
        ((rebuild(repo, nb.id, app.pageId!)['blocks'] as List).single as Map)
            .cast<String, dynamic>());
    expect(InkStorage.refsOf(rebuiltInk.content),
        InkStorage.refsOf(stored.blocks.single.content));
    expect(rebuiltInk.x, ink.x, reason: 'the block moved');
    expect(rebuiltInk.y, ink.y);
    // The moved strokes come back at their new coordinates.
    final back = stored.blocks.single.content['strokes'] as List;
    final firstStroke =
        Stroke.fromJson((back.first as Map).cast<String, dynamic>());
    expect(firstStroke.x.first, closeTo(100, 0.1),
        reason: 'stroke 0 started at x=0 and the drag added 100');
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

    // A RESTART MUST NOT REVERT THE OTHER DEVICE.
    //
    // The failure, reproduced before the fix: device A quits. Device B adds a
    // block to a page and its log arrives. A relaunches — the recorder's
    // replay folds B's block into `state`, but nothing writes it into A's
    // container, so the editor renders the page without it. A types one
    // character. The save diffs the container's blocks against `state`, sees
    // B's block "missing", and emits `block.remove` at a Lamport ABOVE B's.
    // That op wins the total order on every replica, so B loses a block it
    // wrote and watched appear.
    //
    // The Lamport ordering is why this is data loss rather than a glitch: the
    // replay raises A's clock to the log maximum, so anything A emits
    // afterwards sorts after everything B has ever written.
    test('a save before the fold cannot delete the other device\'s block',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp) = await freshRepo('onote_sync_revert_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final nb = await repo.createNotebook('Revert');
      final ref = repo.notebooks.firstWhere((n) => n.id == nb.id);

      // ── Session one: this device writes a block and quits.
      final first = AppState(repo)..notebookId = nb.id;
      first.reloadNodes();
      final pageId = first.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
      first.pageId = pageId;
      first.blocks = [
        Block(
            id: 'mine-1',
            type: BlockType.text,
            x: 0,
            y: 0,
            content: {'text': 'mine'})
      ];
      first.markDirty();
      await first.flushSave();
      first.cancelPendingSave();

      // ── While it is closed, the other device adds a block to the same page.
      final store = OpLogStore.forNotebook(ref.file);
      otherDeviceWrites(store, [
        op(1, 500, OpKind.blockSet, {
          'pageId': pageId,
          'block': {
            'id': 'theirs-1',
            'type': 'text',
            'x': 0,
            'y': 100,
            'w': 320,
            'content': {'text': 'theirs'}
          }
        }),
      ]);

      // ── Session two. A fresh AppState over the same repository is the
      // restart; the recorder replays every log, B's included.
      final second = AppState(repo)..notebookId = nb.id;
      second.reloadNodes();
      second.pageId = pageId;
      addTearDown(second.cancelPendingSave);

      final recorder = await second.warmRecorder(nb.id);
      expect(recorder, isNotNull);
      // The replay HAS their block, and the container does not. This gap is
      // the bug's precondition, and asserting it here means the test still
      // describes the real hazard if the replay ever changes.
      expect(recorder!.materialisedPage(pageId)['blocks'], isNotNull);
      expect(
          repo.readPage(nb.id, pageId).blocks.map((b) => b.id), ['mine-1'],
          reason: 'the container has not been given their block');

      // Asking arms the guard — and every fold path asks first.
      expect(await recorder.pendingForeignOps(repo.getSetting), hasLength(1));
      expect(recorder.foreignPending, isTrue);

      // ── The keystroke. The page is saved as the CONTAINER knows it.
      second.blocks = [
        Block(
            id: 'mine-1',
            type: BlockType.text,
            x: 0,
            y: 0,
            content: {'text': 'mine, edited'})
      ];
      second.markDirty();
      await second.flushSave();

      // Nothing destructive reached the log.
      final ours = store.readDevice(second.localDeviceId());
      expect(
          ours.where((o) => o.kind == OpKind.blockRemove), isEmpty,
          reason: 'a block this device never saw must not be deleted by it');
      expect(
          ours.where((o) =>
              o.kind == OpKind.blockSet &&
              (o.map['block'] as Map?)?['id'] == 'theirs-1'),
          isEmpty,
          reason: 'nor re-written with stale content, which reverts it just '
              'as effectively');

      // And their block is still there for everyone: a rebuild from the merged
      // log — which is what every other device replays — still has it.
      final rebuilt = Materializer()..applyAll(store.readAll());
      expect(rebuilt.pages[pageId]!.blocks.keys, contains('theirs-1'));

      // ── After the fold, saving records normally again.
      final pulled = await second.syncPull(nb.id);
      expect(pulled, 1);
      expect(recorder.foreignPending, isFalse);
      expect(repo.readPage(nb.id, pageId).blocks.map((b) => b.id),
          containsAll(<String>['mine-1', 'theirs-1']),
          reason: 'the fold puts their block in the container');

      second.blocks = [
        ...repo.readPage(nb.id, pageId).blocks,
        Block(
            id: 'mine-2',
            type: BlockType.text,
            x: 0,
            y: 200,
            content: {'text': 'after'})
      ];
      second.markDirty();
      await second.flushSave();
      final after = Materializer()..applyAll(store.readAll());
      expect(after.pages[pageId]!.blocks.keys,
          containsAll(<String>['mine-1', 'theirs-1', 'mine-2']),
          reason: 'recording resumes once the container has caught up');
    });

    // THE GUARD MUST BE UP *DURING* THE PARSE, NOT ONLY AFTER IT.
    //
    // The test above proves a save is refused once `pendingForeignOps` has
    // ANSWERED. But the parse is paced now (`OpLogStore.readDeviceFrom`
    // yields every half megabyte), so on a big log the answer is ~1 s away —
    // and the save debounce is 700 ms, armed the moment a page is opened
    // (the title-band repair marks it dirty). A guard raised only at the end
    // leaves that whole window open, and a save landing inside it is the
    // exact reproduced disaster the previous test describes: a diff against
    // replayed state that already holds the other device's blocks, emitting
    // `block.remove` at top Lamport on every replica.
    test('the guard is up before the parse finishes, not only after', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp) = await freshRepo('onote_sync_midparse_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final nb = await repo.createNotebook('MidParse');
      final ref = repo.notebooks.firstWhere((n) => n.id == nb.id);

      final first = AppState(repo)..notebookId = nb.id;
      first.reloadNodes();
      final pageId = first.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
      first.pageId = pageId;
      first.blocks = [
        Block(
            id: 'mine-1',
            type: BlockType.text,
            x: 0,
            y: 0,
            content: {'text': 'mine'})
      ];
      first.markDirty();
      await first.flushSave();
      first.cancelPendingSave();

      final store = OpLogStore.forNotebook(ref.file);
      otherDeviceWrites(store, [
        op(1, 500, OpKind.blockSet, {
          'pageId': pageId,
          'block': {
            'id': 'theirs-1',
            'type': 'text',
            'x': 0,
            'y': 100,
            'w': 320,
            'content': {'text': 'theirs'}
          }
        }),
      ]);

      final second = AppState(repo)..notebookId = nb.id;
      second.reloadNodes();
      second.pageId = pageId;
      addTearDown(second.cancelPendingSave);
      final recorder = await second.warmRecorder(nb.id);
      expect(recorder, isNotNull);

      // Start the parse and do NOT await it — this is the paced window.
      final parsing = recorder!.pendingForeignOps(repo.getSetting);
      // MUTATION: move the pre-scan arming out of `pendingForeignOps` (back
      // to end-of-parse only) and this expectation fails — and with it the
      // block below records a destructive diff.
      expect(recorder.foreignPending, isTrue,
          reason: 'the cheap bytes-on-disk pre-scan must raise the guard '
              'before the first await, because the 700 ms save debounce '
              'fires inside the ~1 s paced parse');

      // The mid-parse save: the page as the CONTAINER knows it, without
      // their block. `page()` must refuse to diff it.
      recorder.page(
          pageId,
          [
            Block(
                id: 'mine-1',
                type: BlockType.text,
                x: 0,
                y: 0,
                content: {'text': 'mine, edited mid-parse'})
          ],
          PageProps());

      await parsing;

      final ours = store.readDevice(second.localDeviceId());
      expect(ours.where((o) => o.kind == OpKind.blockRemove), isEmpty,
          reason: 'a save inside the parse window must not delete a block '
              'this device has not folded into its container yet');
      expect(
          ours.where((o) =>
              o.kind == OpKind.blockSet &&
              (o.map['block'] as Map?)?['id'] == 'theirs-1'),
          isEmpty,
          reason: 'nor rewrite it with stale content');
    });

    // Negative control for the pre-scan: a foreign log that is FULLY FOLDED
    // (offset at end of file) must not arm, or every save landing during any
    // pull's check — and the watcher fires one on every folder event — would
    // lose its recording to a phantom window.
    test('no unread foreign bytes leaves saves recording during the check',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp) = await freshRepo('onote_sync_noforeign_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final nb = await repo.createNotebook('Quiet');
      final app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      final pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
      app.pageId = pageId;
      addTearDown(app.cancelPendingSave);

      // A foreign device exists and everything it wrote is already folded —
      // the steady state of every shared notebook. The pre-scan sees a log
      // whose stored offset equals its length: nothing unread.
      final store = OpLogStore.forNotebook(
          repo.notebooks.firstWhere((n) => n.id == nb.id).file);
      otherDeviceWrites(store, [
        op(1, 500, OpKind.blockSet, {
          'pageId': pageId,
          'block': {
            'id': 'theirs-1',
            'type': 'text',
            'x': 0,
            'y': 100,
            'w': 320,
            'content': {'text': 'theirs'}
          }
        }),
      ]);
      expect(await app.syncPull(nb.id), 1, reason: 'precondition: folded');

      final recorder = await app.warmRecorder(nb.id);
      expect(recorder, isNotNull);
      final parsing = recorder!.pendingForeignOps(repo.getSetting);
      // MUTATION: arm the guard unconditionally in the pre-scan and this
      // fails — the phantom window would cost a save its recording on every
      // watcher-fired pull of every shared notebook.
      expect(recorder.foreignPending, isFalse,
          reason: 'no foreign log has unread bytes, so nothing may be armed');
      recorder.page(
          pageId,
          [
            ...repo.readPage(nb.id, pageId).blocks,
            Block(
                id: 'solo-1',
                type: BlockType.text,
                x: 0,
                y: 0,
                content: {'text': 'recorded'})
          ],
          PageProps());
      await parsing;

      final ours = store.readDevice(app.localDeviceId());
      expect(
          ours.where((o) =>
              o.kind == OpKind.blockSet &&
              (o.map['block'] as Map?)?['id'] == 'solo-1'),
          isNotEmpty,
          reason: 'an ordinary save with no pending foreign work records');
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
