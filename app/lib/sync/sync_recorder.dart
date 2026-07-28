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

import 'dart:typed_data';

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
    required Object? Function(String key) readSetting,
    required void Function(String key, Object? value) writeSetting,
  }) {
    final store = OpLogStore.forNotebook(notebookPath);
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

    final state = Materializer()..applyAll(store.readAll());
    final recorder = SyncRecorder._(
      notebookId: notebookId,
      store: store,
      device: device,
      state: state,
      lamport: store.highestLamport(),
      seq: store.lastSeq(device.id),
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
      final json = b.toJson();
      final before = prev?.blocks[b.id];
      // Canonical compare: an unchanged block must not produce an op, or every
      // autosave would append the whole page and the log would grow without
      // bound.
      if (before != null && canonicalJson(before) == canonicalJson(json)) {
        continue;
      }
      ops.add(_op(OpKind.blockSet, {'pageId': pageId, 'block': json}));
    }
    for (final goneId in (prev?.blocks.keys.toList() ?? const <String>[])) {
      if (!seen.contains(goneId)) {
        ops.add(_op(
            OpKind.blockRemove, {'pageId': pageId, 'blockId': goneId}));
      }
    }
    final propsJson = props.toJson();
    if (prev == null || canonicalJson(prev.props) != canonicalJson(propsJson)) {
      ops.add(_op(OpKind.pageProps, {'pageId': pageId, 'props': propsJson}));
    }
    _commit(ops);
  }

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
