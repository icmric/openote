/// Records every persistent mutation as an operation (ADR-0006 step 2).
///
/// **Shadow mode.** The `.onote` container is still authoritative; this writes
/// the log *alongside* each save. That ordering is deliberate — it makes the
/// log's completeness a testable property today, long before anything depends
/// on it: rebuild the container from the log, compare, and any divergence is a
/// mutation path that forgot to record itself. Trusting an unverified log first
/// and discovering the gap after a device fails to converge is the failure this
/// avoids.
///
/// It is attached to `AppState`'s storage facade, which is the single funnel
/// every mutation already passes through.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../model/models.dart';
import 'device_identity.dart';
import 'materializer.dart';
import 'op.dart';
import 'op_log.dart';

class SyncRecorder {
  SyncRecorder._({
    required this.notebookId,
    required this.store,
    required this.device,
    required this.state,
    required int lamport,
    required int seq,
    required this.onSeq,
  })  : _lamport = lamport,
        _seq = seq;

  final String notebookId;
  final OpLogStore store;
  final DeviceIdentity device;

  /// The log replayed into state, kept live so a page save can be diffed into
  /// block-level ops instead of one whole-page write.
  final Materializer state;

  final void Function(int seq) onSeq;

  int _lamport;
  int _seq;

  /// Ops written this session, for diagnostics and the verification report.
  int get opsWritten => _written;
  int _written = 0;

  /// Open (or create) the log for a notebook and replay it into memory.
  static SyncRecorder open({
    required String notebookId,
    required String notebookPath,
    required String title,
    String? logDir,
    required Object? Function(String key) readSetting,
    required void Function(String key, Object? value) writeSetting,
  }) {
    final store = OpLogStore.forNotebook(notebookPath, logDir: logDir);
    store.ensureInitialised(notebookId: notebookId, title: title);
    final device = DeviceIdentity.resolve(
      store: store,
      notebookId: notebookId,
      readSetting: readSetting,
      writeSetting: writeSetting,
    );
    if (device.forked) {
      // Not silent: an install that forked was almost certainly cloned or
      // restored, and the user may be about to see two "devices" that are one
      // machine. Better a log line now than a convergence mystery later.
      debugPrint('[openote/sync] device id forked to ${device.id} — another '
          'installation had written to the previous id\'s log');
    }
    store.announceDevice(device.id);

    // ONE pass over the logs. readAll + highestLamport + lastSeq each re-read
    // every file, which tripled open time — and open time scales with log
    // size, so on a heavily-edited notebook it was the difference between a
    // fast open and a hitch.
    final all = store.readAll();
    var lamport = 0, seq = 0;
    for (final op in all) {
      if (op.lamport > lamport) lamport = op.lamport;
      if (op.device == device.id && op.seq > seq) seq = op.seq;
    }
    final state = Materializer()..applyAll(all);
    final recorder = SyncRecorder._(
      notebookId: notebookId,
      store: store,
      device: device,
      state: state,
      lamport: lamport,
      seq: seq,
      onSeq: (s) => writeSetting(DeviceIdentity.seqKey(notebookId), s),
    );
    // Seed the title so a notebook that has never been renamed still carries
    // one in the log. `notebookMeta` diffs, so this writes once and is a no-op
    // on every subsequent open.
    recorder.notebookMeta({'title': title});
    return recorder;
  }

  Op _op(OpKind kind, Map<String, dynamic> data) => Op(
        device: device.id,
        seq: ++_seq,
        lamport: ++_lamport,
        timestamp: nowMs(),
        kind: kind,
        data: data,
      );

  /// Append [ops], apply them to the in-memory state, and remember the seq we
  /// reached so the fork check can spot another writer next time.
  void _commit(List<Op> ops) {
    if (ops.isEmpty) return;
    store.append(device.id, ops);
    for (final op in ops) {
      state.apply(op);
    }
    _written += ops.length;
    onSeq(_seq);
  }

  // ── Recording ────────────────────────────────────────────────────────

  void node(TreeNode n) => _commit([
        _op(OpKind.nodeUpsert, {
          'id': n.id,
          'kind': n.kind.name,
          'parentId': n.parentId,
          'title': n.title,
          'position': n.position,
          'color': n.color,
          'level': n.level,
          'createdAt': n.createdAt,
          'updatedAt': n.updatedAt,
        })
      ]);

  void nodeDeleted(String id, {int? at}) =>
      _commit([_op(OpKind.nodeDelete, {'id': id, 'deletedAt': at ?? nowMs()})]);

  void nodeRestored(String id) =>
      _commit([_op(OpKind.nodeRestore, {'id': id})]);

  void nodePurged(String id) => _commit([_op(OpKind.nodePurge, {'id': id})]);

  /// Notebook-level properties (title today).
  ///
  /// Without this a rebuild recovers every page and its whole tree but not what
  /// the notebook is *called* — the manifest carries the title only from
  /// creation, so a rename would be invisible to a second device. Small, and
  /// exactly the kind of omission that makes a log "nearly" complete.
  void notebookMeta(Map<String, dynamic> props) {
    final changed = <String, dynamic>{
      for (final e in props.entries)
        if (canonicalJson(state.meta[e.key]) != canonicalJson(e.value))
          e.key: e.value
    };
    if (changed.isEmpty) return;
    _commit([_op(OpKind.notebookMeta, changed)]);
  }

  /// Store a blob's bytes in `blobs/` and record that it exists.
  ///
  /// The op carries only hash, mime and size — the bytes go in a
  /// content-addressed file. Putting megabytes of image into an append-only log
  /// would make it unbounded and unreadable, and defeats the property that
  /// makes blobs easy: identical content produces an identical filename on
  /// every device, so blobs need no merge and can be fetched lazily.
  void blob(String hash, String mime, int size, Uint8List bytes) {
    store.writeBlob(hash, bytes);
    if (state.blobs.contains(hash)) return; // already recorded; bytes are immutable
    _commit([_op(OpKind.blobPut, {'hash': hash, 'mime': mime, 'size': size})]);
  }

  /// Copy blobs that exist only in the container into `blobs/`.
  ///
  /// Needed because notebooks created before the log existed hold every image
  /// in SQLite alone — so a rebuild-from-log would reconstruct page structure
  /// referencing bytes it cannot supply. That is the difference between a log
  /// that *looks* complete and one that is.
  ///
  /// Deliberately incremental and awaitable: a real imported notebook has
  /// hundreds of images totalling tens of megabytes, and doing that
  /// synchronously at open would stall the UI. [read] is called one hash at a
  /// time rather than taking a map, so the whole notebook's images are never in
  /// memory at once.
  Future<int> backfillBlobs({
    required List<({String hash, String mime, int size})> index,
    required Uint8List? Function(String hash) read,
  }) async {
    var copied = 0;
    for (final b in index) {
      if (store.hasBlob(b.hash) && state.blobs.contains(b.hash)) continue;
      final bytes = read(b.hash);
      if (bytes == null) continue; // referenced but missing; nothing to copy
      blob(b.hash, b.mime, b.size, bytes);
      copied++;
      // Yield so a 372-image notebook doesn't block a frame.
      await Future<void>.delayed(Duration.zero);
    }
    if (copied > 0) {
      debugPrint('[openote/sync] backfilled $copied blob(s) into '
          '${store.blobsDir.path}');
    }
    return copied;
  }

  // ── Ingestion: other devices' logs ───────────────────────────────────

  /// Ops from OTHER devices that this device has not applied yet.
  ///
  /// The watermark is per foreign device, stored locally. It is not "what
  /// exists" but "what I have folded into my container" — those differ exactly
  /// when another device has synced a log in, which is the whole point.
  List<Op> pendingForeignOps(
      Object? Function(String key) readSetting) {
    final out = <Op>[];
    for (final dev in store.deviceIds()) {
      if (dev == device.id) continue;
      final seen =
          (readSetting(foreignSeqKey(notebookId, dev)) as num?)?.toInt() ?? 0;
      for (final op in store.readDevice(dev)) {
        if (op.seq > seen) out.add(op);
      }
    }
    out.sort(Op.compare);
    return out;
  }

  static String foreignSeqKey(String notebookId, String device) =>
      'syncSeen:$notebookId:$device';

  /// Fold [ops] into this device's replayed state and report what changed, so
  /// the caller can write exactly those pages and nodes into the container.
  ///
  /// Returns the affected page ids and whether the node tree moved. Note the
  /// ops are applied to the SAME state the recorder diffs against — otherwise
  /// the next local save would re-record the remote's changes as if they were
  /// ours, doubling every incoming edit.
  ({Set<String> pages, bool treeChanged}) applyForeign(List<Op> ops) {
    final pages = <String>{};
    var treeChanged = false;
    for (final op in ops) {
      switch (op.kind) {
        case OpKind.blockSet:
        case OpKind.blockRemove:
        case OpKind.pageProps:
        case OpKind.inkStrokes:
          final pid = op.map['pageId'];
          if (pid is String) pages.add(pid);
        case OpKind.nodeUpsert:
        case OpKind.nodeDelete:
        case OpKind.nodeRestore:
        case OpKind.nodePurge:
          treeChanged = true;
        case OpKind.blobPut:
        case OpKind.notebookMeta:
        case OpKind.unknown:
          break;
      }
      state.apply(op);
      // Keep our Lamport clock ahead of everything seen, or our next op would
      // sort before theirs and replicas would order history differently.
      if (op.lamport > _lamport) _lamport = op.lamport;
    }
    return (pages: pages, treeChanged: treeChanged);
  }

  /// The materialised page after ingestion, in the container's mirror shape.
  Map<String, dynamic> materialisedPage(String pageId) =>
      state.pageMirror(pageId);

  /// Live nodes after ingestion.
  List<MatNode> materialisedNodes() => state.liveNodes();

  /// Nodes the log says are deleted. Needed because writing only the live ones
  /// makes a remote delete invisible — the node simply stays in the container,
  /// which is delete-LOSES, the opposite of the decision.
  List<String> materialisedDeletedIds() => [
        for (final n in state.nodes.values)
          if (n.deletedAt != null) n.id
      ];

  /// Record that [device]'s ops up to [seq] are folded in.
  void markForeignSeen(String dev, int seq,
          void Function(String key, Object? value) writeSetting) =>
      writeSetting(foreignSeqKey(notebookId, dev), seq);

  /// Blobs referenced by ops whose bytes are not in `blobs/`. Empty means a
  /// rebuild from this log could reconstruct the notebook's content in full.
  Set<String> missingBlobs() {
    final have = store.blobHashes();
    return {
      for (final h in state.blobs)
        if (!have.contains(h.replaceFirst('sha256:', ''))) h
    };
  }

  /// Diff a page save into block-level ops.
  ///
  /// The app hands us the whole page because that is how it saves; recording it
  /// as one op would make the smallest representable change "the page is now
  /// this", which is precisely the granularity problem ADR-0006 §4 describes —
  /// only worse, because it would lose concurrent edits to *different pages'*
  /// blocks too. Diffing against the replayed state recovers block granularity
  /// without changing the save path.
  void page(String pageId, List<Block> blocks, PageProps props) {
    final prev = state.pages[pageId];
    final ops = <Op>[];

    final seen = <String>{};
    for (final b in blocks) {
      seen.add(b.id);
      final live = b.toJson();
      final canon = canonicalJson(live);
      final before = prev?.blocks[b.id];
      // Canonical compare: an unchanged block must not produce an op, or every
      // autosave would append the whole page and the log would grow without
      // bound.
      if (before != null && canonicalJson(before) == canon) {
        continue;
      }
      // DETACHED snapshot, not `live`. Block.toJson's `content` aliases the
      // block's live map, so storing it in the replayed state would make the
      // state mutate in lockstep with the app — and every later diff would
      // compare a thing to itself and see nothing. (Found by the ink tests:
      // a block drag looked like a no-op to the recorder.)
      final json = jsonDecode(canon) as Map<String, dynamic>;
      // Ink gets a per-stroke diff when it pays. An imported page's ink is ONE
      // block holding every stroke (multi-MB serialized); recording an erase
      // gesture as a whole `block.set` was 50–1000× write amplification.
      if (before != null && json['type'] == 'ink') {
        final inkOp = _diffInk(pageId, before, json);
        if (inkOp != null) {
          ops.add(inkOp);
          continue;
        }
      }
      ops.add(_op(OpKind.blockSet, {'pageId': pageId, 'block': json}));
    }
    for (final goneId in (prev?.blocks.keys.toList() ?? const <String>[])) {
      if (!seen.contains(goneId)) {
        ops.add(_op(
            OpKind.blockRemove, {'pageId': pageId, 'blockId': goneId}));
      }
    }
    final propsCanon = canonicalJson(props.toJson());
    if (prev == null || canonicalJson(prev.props) != propsCanon) {
      // Detached for the same aliasing reason as blocks (unknownFields is a
      // live map on PageProps).
      ops.add(_op(OpKind.pageProps,
          {'pageId': pageId, 'props': jsonDecode(propsCanon)}));
    }
    _commit(ops);
  }

  /// Diff two versions of an ink block into one [OpKind.inkStrokes] op, or
  /// null when a whole `block.set` is the better record.
  ///
  /// Null falls back deliberately in two cases:
  /// - **the envelope changed beyond geometry** (anything but x/y/w/h/rotation/
  ///   updatedAt): a colour change, a future field — the block op is the honest
  ///   record;
  /// - **more than half the strokes changed**: dragging an ink block rewrites
  ///   every stroke's coordinates in place, and a per-stroke op for that would
  ///   be BIGGER than the block. The guard uses size as a proxy for intent —
  ///   do not "optimize" it away; erasing most of a huge block in one gesture
  ///   correctly lands on `block.set`.
  Op? _diffInk(String pageId, Map<String, dynamic> before,
      Map<String, dynamic> after) {
    final beforeStrokes =
        ((before['content'] as Map?)?['strokes'] as List?) ?? const [];
    final afterStrokes =
        ((after['content'] as Map?)?['strokes'] as List?) ?? const [];
    if (afterStrokes.isEmpty) return null; // emptied → block-level is right

    // The envelope must match apart from geometry, or this op cannot carry the
    // difference.
    Map<String, dynamic> stripped(Map<String, dynamic> b) => {
          for (final e in b.entries)
            if (!const {'content', 'x', 'y', 'w', 'h', 'rotation', 'updatedAt'}
                .contains(e.key))
              e.key: e.value,
          'content': {
            for (final e in ((b['content'] as Map?) ?? const {}).entries)
              if (e.key != 'strokes') e.key: e.value
          },
        };
    if (canonicalJson(stripped(before)) != canonicalJson(stripped(after))) {
      return null;
    }

    String? idOf(Object? s) => s is Map ? s['id'] as String? : null;
    final beforeById = <String, String>{};
    for (final s in beforeStrokes) {
      final id = idOf(s);
      if (id == null) return null; // unidentifiable stroke → whole block
      beforeById[id] = canonicalJson(s);
    }

    final afterIds = <String>{};
    // Positional inserts, computed against the post-delete list: walk the after
    // list; a stroke that is unchanged keeps its place, everything else is a
    // put at its index. Order is load-bearing — the eraser inserts split
    // fragments mid-list and verification compares the list verbatim.
    final puts = <Map<String, dynamic>>[];
    var changed = 0;
    for (var i = 0; i < afterStrokes.length; i++) {
      final s = afterStrokes[i];
      final id = idOf(s);
      if (id == null) return null;
      afterIds.add(id);
      final prevJson = beforeById[id];
      if (prevJson == null || prevJson != canonicalJson(s)) {
        puts.add({'i': i, 's': s});
        changed++;
      }
    }
    final del = [
      for (final id in beforeById.keys)
        if (!afterIds.contains(id)) id
    ];
    changed += del.length;
    if (changed == 0) {
      // Only geometry moved: record the envelope change without the strokes.
      return _op(OpKind.inkStrokes, {
        'pageId': pageId,
        'blockId': after['id'],
        'del': const [],
        'put': const [],
        'rect': _rectOf(after),
        'updatedAt': after['updatedAt'],
      });
    }
    if (changed > afterStrokes.length / 2) return null;

    return _op(OpKind.inkStrokes, {
      'pageId': pageId,
      'blockId': after['id'],
      'del': del,
      'put': puts,
      'rect': _rectOf(after),
      'updatedAt': after['updatedAt'],
    });
  }

  static Map<String, dynamic> _rectOf(Map<String, dynamic> b) => {
        'x': b['x'],
        'y': b['y'],
        'w': b['w'],
        'h': b['h'],
      };

  // ── Verification (the point of shadow mode) ──────────────────────────

  /// Rebuild from the log and compare one page against what the container
  /// holds. Returns null when they agree, else a human-readable difference.
  String? verifyPage(String pageId, List<Block> blocks, PageProps props) {
    final fresh = Materializer()..applyAll(store.readAll());
    final fromLog = canonicalJson(fresh.pageMirror(pageId));
    final ids = [for (final b in blocks) b.id]..sort();
    final byId = {for (final b in blocks) b.id: b.toJson()};
    final fromContainer = canonicalJson({
      'schema': 'onote-page/1',
      'pageId': pageId,
      'page': props.toJson(),
      'blocks': [for (final id in ids) byId[id]],
    });
    if (fromLog == fromContainer) return null;
    if (fresh.skipped.isNotEmpty) {
      return 'page $pageId differs, but the log contains '
          '${fresh.skipped.length} op(s) this version cannot apply — '
          'inconclusive rather than incomplete';
    }
    return 'page $pageId: rebuild-from-log does not match the container';
  }
}
