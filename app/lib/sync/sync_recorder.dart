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
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../model/models.dart';
import '../ink/ink_codec.dart';
import '../store/notebook_writer.dart' show sha256Hex;
import 'device_identity.dart';
import 'materializer.dart';
import 'op.dart';
import 'op_log.dart';

/// The result of [SyncRecorder.proveBlobs] — the invariant every later step of
/// the v0.17 storage plan is gated on, stated as a value rather than a boolean
/// so a failure can say *which* blobs and *how* they failed.
class BlobProof {
  const BlobProof({
    required this.checked,
    required this.missing,
    required this.repaired,
    required this.damaged,
  });

  /// Blob files whose bytes were re-hashed. Not "files seen" — the number that
  /// distinguishes this from a count of directory entries.
  final int checked;

  /// Named by the log, no bytes on disk, and the container could not supply
  /// them either.
  final Set<String> missing;

  /// Found holding the wrong bytes and rewritten correctly from the container.
  /// Not a failure: this is the repair working, and it is worth logging because
  /// it means something outside Openote damaged the folder.
  final Set<String> repaired;

  /// Found holding the wrong bytes and NOT repairable. The worst outcome, and
  /// the one a count of files reports as success.
  final Set<String> damaged;

  /// True when a rebuild from this log could reconstruct every picture, drawing
  /// and attachment byte for byte. **This is the Step 7 gate.**
  bool get ok => missing.isEmpty && damaged.isEmpty;

  /// How many blobs the notebook cannot supply. What the user is told about.
  int get holes => missing.length + damaged.length;

  @override
  String toString() => 'checked $checked, missing ${missing.length}, '
      'wrong bytes repaired ${repaired.length}, '
      'wrong bytes unrepairable ${damaged.length}';
}

class SyncRecorder {
  SyncRecorder._({
    required this.notebookId,
    required this.store,
    required this.device,
    required this.state,
    required int lamport,
    required int seq,
    required this.onSeq,
    required this.materialiseBlobs,
  })  : _lamport = lamport,
        _seq = seq;

  final String notebookId;
  final OpLogStore store;
  final DeviceIdentity device;

  /// Whether blob **bytes** are written into `blobs/` as well as the container.
  ///
  /// **Why this is optional.** Shadow mode means every image is stored twice —
  /// once in the container's `blobs` table, once as `blobs/<sha256>` — which
  /// measured at a 2.13× disk overhead on an imported notebook, paid by every
  /// notebook including the majority that never leave the machine. The op
  /// *stream* is cheap and always written; the bytes are the expensive half, and
  /// they only earn their cost when something other than this device is going to
  /// read them.
  ///
  /// So the bytes are written when the notebook is shared (in a sync folder, or
  /// mirrored) and deferred otherwise. Deferred, not lost: the container is
  /// authoritative and still holds every byte, so [backfillBlobs] can
  /// materialise the whole set later — which is exactly what it already did for
  /// notebooks created before the log existed. Turning sync on makes the normal
  /// path out of what used to be the migration path.
  ///
  /// Mutable because the answer changes under the app's feet: a notebook moved
  /// into Drive, or given a mirror, must materialise from that moment on. Set it
  /// through `AppState.materialiseBlobsIfShared`, which also runs the backfill —
  /// flipping this alone would write future blobs and leave past ones behind.
  bool materialiseBlobs;

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
  ///
  /// **Synchronous, and priced accordingly.** The replay reads and JSON-decodes
  /// every op ever written — measured at ~0.5 s for a 2000-page imported
  /// notebook's 14 MB log, on a fast machine. On the UI thread that is a
  /// visible freeze, which is why interactive callers go through [openAsync]
  /// and this stays for mutation paths that cannot wait and for tests.
  static SyncRecorder open({
    required String notebookId,
    required String notebookPath,
    required String title,
    String? logDir,
    required Object? Function(String key) readSetting,
    required void Function(String key, Object? value) writeSetting,
    bool materialiseBlobs = true,
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
      materialiseBlobs: materialiseBlobs,
    );
    // Seed the title so a notebook that has never been renamed still carries
    // one in the log. `notebookMeta` diffs, so this writes once and is a no-op
    // on every subsequent open.
    recorder.notebookMeta({'title': title});
    return recorder;
  }

  /// [open], with the heavy half — reading and replaying every op — in a
  /// background isolate.
  ///
  /// The UI thread's share of this is milliseconds regardless of log size: the
  /// manifest touch, the identity check (against seq maxima the replay already
  /// computed, not a re-read), and receiving the replayed state — which
  /// `Isolate.run` hands over via `Isolate.exit`, ownership transfer rather
  /// than copy, so the multi-megabyte materialised state does not repeat the
  /// mistake the import's layout request made.
  ///
  /// **Does NOT seed the title op, deliberately.** The caller decides whether
  /// this recorder is actually installed — a synchronous open may have won the
  /// race while the replay ran, and the loser must be discardable without ever
  /// having written anything. Call [seedTitle] after installing.
  static Future<SyncRecorder> openAsync({
    required String notebookId,
    required String notebookPath,
    required String title,
    String? logDir,
    required Object? Function(String key) readSetting,
    required void Function(String key, Object? value) writeSetting,
    bool materialiseBlobs = true,
  }) async {
    final store = OpLogStore.forNotebook(notebookPath, logDir: logDir);
    store.ensureInitialised(notebookId: notebookId, title: title);

    // One pass over the logs, off-thread. Everything it produces is plain
    // data (maps, sets, lists of ops), which is what makes the O(1) handoff
    // possible.
    final (state, seqByDevice, lamport) =
        await _replayInIsolate(notebookPath, logDir);

    final device = DeviceIdentity.resolve(
      store: store,
      notebookId: notebookId,
      readSetting: readSetting,
      writeSetting: writeSetting,
      lastSeqOf: (id) => seqByDevice[id] ?? 0,
    );
    if (device.forked) {
      debugPrint('[openote/sync] device id forked to ${device.id} — another '
          'installation had written to the previous id\'s log');
    }
    store.announceDevice(device.id);

    return SyncRecorder._(
      notebookId: notebookId,
      store: store,
      device: device,
      state: state,
      lamport: lamport,
      seq: seqByDevice[device.id] ?? 0,
      onSeq: (s) => writeSetting(DeviceIdentity.seqKey(notebookId), s),
      materialiseBlobs: materialiseBlobs,
    );
  }

  /// The title seeding [open] does inline — split out so [openAsync] callers
  /// can defer it until the recorder is definitely the installed one.
  void seedTitle(String title) => notebookMeta({'title': title});

  /// The replay, in its own function so the `Isolate.run` closure's scope
  /// holds exactly two strings and nothing else.
  ///
  /// **Not an inline lambda in [openAsync], and it cannot become one.** A Dart
  /// closure captures its enclosing *context*, not just the variables it
  /// names — inlined, it dragged `writeSetting` along, which is a tearoff of
  /// `Repository.setSetting`, which holds the workspace write-debounce
  /// `Timer`, which is unsendable. The failure is a runtime throw on spawn,
  /// found by test, not by the compiler.
  static Future<(Materializer, Map<String, int>, int)> _replayInIsolate(
      String notebookPath, String? logDir) {
    return Isolate.run(() {
      final store = OpLogStore.forNotebook(notebookPath, logDir: logDir);
      final all = store.readAll();
      var lamport = 0;
      final seqs = <String, int>{};
      for (final op in all) {
        if (op.lamport > lamport) lamport = op.lamport;
        if (op.seq > (seqs[op.device] ?? 0)) seqs[op.device] = op.seq;
      }
      return (Materializer()..applyAll(all), seqs, lamport);
    });
  }

  Op _op(OpKind kind, Map<String, dynamic> data) => Op(
        device: device.id,
        seq: ++_seq,
        lamport: ++_lamport,
        timestamp: nowMs(),
        kind: kind,
        data: data,
      );

  /// Ops in this notebook's log that this build cannot apply because their
  /// **envelope** is newer or encrypted. Empty for every log in existence
  /// today; see [Materializer.unsupported].
  List<Op> get unsupportedOps => state.unsupported;

  /// Whether this log has moved past what this build understands.
  ///
  /// When true the notebook is read-only: nothing may be appended to a history
  /// that has already been half-read, because every op this recorder writes is
  /// a diff against [state], and [state] is missing whatever the unreadable
  /// ops did. An "edit" computed that way is not an edit, it is an undo of
  /// changes the user never asked to lose (v0.17 plan, Step 3).
  bool get logIsAhead => state.unsupported.isNotEmpty;

  /// Append [ops], apply them to the in-memory state, and remember the seq we
  /// reached so the fork check can spot another writer next time.
  void _commit(List<Op> ops) {
    if (ops.isEmpty) return;
    // Silent here on purpose, and only here: the message is already on screen
    // via `AppState.saveError`, and this is the backstop under the gates in
    // `AppState` rather than the thing the user is told by. Same pattern as
    // `Repository._saveWorkspace`'s `registryReadOnly` return.
    if (logIsAhead) return;
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
          // The SPEC spelling, not `n.kind.name`. See [nodeKindWire]: Dart says
          // `sectionGroup`, the published format and the container's own CHECK
          // constraint both say `section_group`, and the reader's fallback
          // turned the difference into six pages per notebook.
          'kind': nodeKindWire(n.kind),
          'parentId': n.parentId,
          'title': n.title,
          'position': n.position,
          'color': n.color,
          'level': n.level,
          'createdAt': n.createdAt,
          'updatedAt': n.updatedAt,
        })
      ]);

  void nodeDeleted(String id, {int? at}) => _commit([
        _op(OpKind.nodeDelete, {'id': id, 'deletedAt': at ?? nowMs()})
      ]);

  void nodeRestored(String id) => _commit([
        _op(OpKind.nodeRestore, {'id': id})
      ]);

  void nodePurged(String id) => _commit([
        _op(OpKind.nodePurge, {'id': id})
      ]);

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
  ///
  /// The **op** is recorded either way; only the bytes wait on
  /// [materialiseBlobs]. Deliberately: hash, mime and size are ~100 bytes, they
  /// are what a later materialisation needs in order to know what to fetch, and
  /// keeping the op stream identical whether or not a notebook syncs means
  /// turning sync on never has to synthesise history it did not record.
  void blob(String hash, String mime, int size, Uint8List bytes) {
    // **Ink is always written, whatever [materialiseBlobs] says.**
    //
    // Deferring blob bytes is a size trade for ATTACHMENTS: an image is also
    // in the container, so a local-only notebook loses nothing by not copying
    // it out, and turning sync on backfills the set.
    //
    // Ink is not an attachment — it is the page's content. Until now an ink
    // block carried its strokes inline in `block.set`, so a local-only log was
    // COMPLETE and a rebuild reconstructed the handwriting. Now the block
    // holds a reference, and deferring the bytes would make the log unable to
    // rebuild the notebook it describes — quietly, and only discoverable on
    // another machine or after a cache rebuild. That is the one property
    // ADR-0006's shadow mode exists to protect.
    //
    // The cost is bounded and small: a whole notebook of handwriting measured
    // 3.2 MB compressed, against the 26 MB of images the deferral was written
    // for.
    if (materialiseBlobs || mime == inkMimeType) {
      store.writeBlob(hash, bytes);
    }
    if (state.blobs.contains(hash))
      return; // already recorded; bytes are immutable
    _commit([
      _op(OpKind.blobPut, {'hash': hash, 'mime': mime, 'size': size})
    ]);
  }

  /// Copy blobs that exist only in the container into `blobs/`.
  ///
  /// Two callers, one mechanism. Notebooks created before the log existed hold
  /// every image in SQLite alone — so a rebuild-from-log would reconstruct page
  /// structure referencing bytes it cannot supply, the difference between a log
  /// that *looks* complete and one that is. And since [materialiseBlobs] made
  /// byte-writing conditional, every local-only notebook is in that same state
  /// by design, so this is also what runs the moment one starts syncing.
  ///
  /// Returns 0 without reading anything when [materialiseBlobs] is false —
  /// otherwise it would pull the whole `blobs` table out of SQLite and throw the
  /// bytes away. Set the flag first (see `AppState.materialiseBlobsIfShared`).
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
    if (!materialiseBlobs) return 0;
    var copied = 0;
    for (final b in index) {
      if (store.hasBlob(b.hash) && state.blobs.contains(b.hash)) continue;
      final bytes = read(b.hash);
      if (bytes == null) continue; // referenced but missing; nothing to copy
      blob(b.hash, b.mime, b.size, bytes);
      copied++;
      // A REAL delay, not Duration.zero. This loop runs on the UI isolate
      // (fsync per blob, hundreds of blobs), and on Windows the UI isolate
      // lives on the Win32 message loop, where posted messages outrank
      // hardware input — a zero timer is itself posted work due immediately,
      // so the queue never goes idle and mouse/keyboard starve for the whole
      // backfill. One millisecond per blob lets the loop actually wait, which
      // is when Win32 delivers input.
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    if (copied > 0) {
      debugPrint('[openote/sync] backfilled $copied blob(s) into '
          '${store.blobsDir.path}');
    }
    return copied;
  }

  /// Re-read every blob the log names and check its bytes against its name.
  ///
  /// **A count is not a proof.** `missingBlobs()` asks `existsSync`, and
  /// `backfillBlobs` skips any hash that already has a file, so a blob written
  /// short by a full disk, or copied in half by a cloud client, is invisible to
  /// both: the notebook reports complete coverage while one of its pictures is
  /// rubbish. A spike stopped a backfill at 100 of 488 blobs, ran the v0.17
  /// migration to completion and it printed MIGRATION COMPLETE with
  /// `integrity_check` ok, having destroyed 193 image blocks across 40 pages —
  /// and that hole was merely *absent* bytes, which is the easy case to notice.
  /// Step 7 deletes the container's copy on the strength of this answer, so
  /// this is the last moment the wrong bytes can be told from the right ones.
  ///
  /// [read] supplies replacement bytes for a file that fails — the container's
  /// `blobs` table while it is still authoritative. A file whose bytes are
  /// wrong is **deleted and rewritten** from it (the only way, since
  /// `writeBlob` refuses to overwrite), and if that cannot be done the hash is
  /// reported [BlobProof.damaged] rather than being left to look fine.
  ///
  /// **The hashing runs off this isolate, and that is not the usual pacing
  /// argument.** `backfillBlobs` yields a real millisecond per blob because its
  /// cost is a write and an fsync, and one blob is a short block. Hashing is
  /// CPU: measured on the owner's Honours-4, re-reading and re-hashing all 488
  /// blobs is 2.8 s of computation, and its worst SINGLE file — 1.8 MB of
  /// binary ink — is a 164 ms block on its own. A per-file yield cannot divide
  /// that, because one file is one block. So the read and the hash both go to a
  /// background isolate in batches, and the UI isolate does only the comparison
  /// and any repair.
  Future<BlobProof> proveBlobs({
    Uint8List? Function(String hash)? read,
  }) async {
    final missing = <String>{};
    final repaired = <String>{};
    final damaged = <String>{};
    final present = <String>[];
    for (final ref in state.blobs) {
      final hash = ref.replaceFirst('sha256:', '');
      if (store.hasBlob(hash)) {
        present.add(hash);
      } else {
        // No bytes at all. Repair is `backfillBlobs`' job and it has already
        // run; still absent here means the container could not supply them
        // either, which is the one outcome Step 7 must never proceed through.
        missing.add(hash);
      }
    }
    var checked = 0;
    for (var i = 0; i < present.length; i += _proveBatch) {
      final slice =
          present.sublist(i, math.min(i + _proveBatch, present.length));
      final actual =
          await _hashFiles([for (final h in slice) store.blobFile(h).path]);
      for (var j = 0; j < slice.length; j++) {
        final hash = slice[j];
        checked++;
        if (actual[j] == hash) continue;
        // Wrong bytes, or unreadable. Either way the name is a lie, and
        // `writeBlob` would skip it for ever, so the file goes first.
        final fresh = read?.call(hash);
        if (fresh != null && sha256Hex(fresh) == hash) {
          try {
            store.discardBlob(hash);
            store.writeBlob(hash, fresh);
            repaired.add(hash);
          } catch (_) {
            // A read-only folder, a full disk. The wrong file may now be gone,
            // and that is deliberate: a hash with no bytes is honestly reported
            // by `missingBlobs()`, where a hash with the wrong bytes is not.
            damaged.add(hash);
          }
        } else {
          damaged.add(hash);
        }
      }
      // The `await` above already hands the loop back, so this is belt and
      // braces for the repair path's writes — and a REAL millisecond, never
      // `Duration.zero`: on Windows a zero timer is posted work due
      // immediately, so the Win32 message loop never goes idle and input
      // starves for the whole run.
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    return BlobProof(
        checked: checked,
        missing: missing,
        repaired: repaired,
        damaged: damaged);
  }

  /// How many blob files one background hash costs. Big enough that isolate
  /// spawn is noise against the hashing, small enough that a batch of huge ink
  /// blobs cannot make the notebook feel stuck at open.
  static const int _proveBatch = 32;

  /// Read and SHA-256 each path, off this isolate, in order.
  ///
  /// Returns null for a path it could not read — a permission error, a file a
  /// cloud client has locked. "I could not check" must never come back looking
  /// like a match, and null matches no hash.
  static Future<List<String?>> _hashFiles(List<String> paths) =>
      Isolate.run(() => [
            for (final path in paths)
              () {
                try {
                  return sha256Hex(File(path).readAsBytesSync());
                } catch (_) {
                  return null;
                }
              }()
          ]);

  // ── Ingestion: other devices' logs ───────────────────────────────────

  /// Ops from OTHER devices that this device has not applied yet.
  ///
  /// The watermark is per foreign device, stored locally. It is not "what
  /// exists" but "what I have folded into my container" — those differ exactly
  /// when another device has synced a log in, which is the whole point.
  ///
  /// **A STAGING BUFFER, SORTED ONCE, APPLIED AS ONE BATCH.**
  /// `OpLogStore.readDeviceFrom`
  /// is paced — it hands the event loop back every half megabyte — so this
  /// method now spans many turns instead of blocking for the ~1,008 ms one
  /// 64.6 MB log costs to parse. What it must NOT become is a per-device read
  /// cap: reading "the next N ops from each device" and folding them would
  /// apply ops in ARRIVAL order, and [Materializer.apply] is last-writer-wins
  /// by application order. Two devices whose logs arrived in different orders
  /// would then hold different content for the same page, for ever, with
  /// nothing to notice it — far worse than a slow fold.
  ///
  /// What keeps that from happening is structural: every op that any device
  /// contributed to this batch is in `out` before the sort runs, the sort is
  /// [Op.compare] (the deterministic total order), and the caller applies the
  /// returned list and nothing else. So the value returned here is the same
  /// list it was when the parse ran in one block — the yields move when the
  /// work happens, not what the answer is.
  Future<List<Op>> pendingForeignOps(
      Object? Function(String key) readSetting) async {
    final out = <Op>[];
    // Built locally and swapped in at the end. The parse yields now, so a
    // second caller could land inside this loop; a half-filled `_resumeAt`
    // would hand [markForeignSeen] an offset past ops the container never
    // received, which is data loss that no later pull would ever repair.
    final resumeAt = <String, int>{};
    for (final dev in store.deviceIds()) {
      if (dev == device.id) continue;
      final seen =
          (readSetting(foreignSeqKey(notebookId, dev)) as num?)?.toInt() ?? 0;
      // **From where we left off, not from the beginning.** This used to run
      // `readDevice`, which slurps and JSON-parses the whole file so the loop
      // below can throw away everything at or under the watermark. Measured on
      // a real notebook that is 1,977 ms per call, on the UI thread, on EVERY
      // pull — including the overwhelmingly common one where nothing changed.
      //
      // The offset is safe because a device's log is append-only with one
      // writer, so its prefix can never change. The seq test stays as the
      // authority: an offset that is stale, missing or invalidated by a
      // shrunken file simply means more re-reading, never a wrong answer.
      final from =
          (readSetting(foreignOffsetKey(notebookId, dev)) as num?)?.toInt() ?? 0;
      final r = await store.readDeviceFrom(dev, from);
      resumeAt[dev] = r.next;
      for (final op in r.ops) {
        if (op.seq > seen) out.add(op);
      }
    }
    // THE WHOLE BATCH, IN ONE SORT, BEFORE ANYTHING IS APPLIED. Measured at
    // 24 ms for 138,657 ops — 2% of the parse it follows — so there is nothing
    // to gain by chunking it and everything to lose: a partially ordered fold
    // is exactly the divergence this guards against.
    out.sort(Op.compare);
    _resumeAt
      ..clear()
      ..addAll(resumeAt);
    // Asking the question is what arms the guard. Every path that folds
    // foreign ops in goes through here first, so this is the one place that
    // reliably knows the answer — and it is answered fresh from disk each
    // time, so a log that arrived while the app was running counts too.
    foreignPending = out.isNotEmpty;
    return out;
  }

  /// True while this device's replayed [state] contains other devices' work
  /// that its container does not.
  ///
  /// Set by [pendingForeignOps], cleared by [markForeignSeen]. While it is
  /// true, [page] refuses to record a diff — see the reasoning there. It
  /// starts FALSE and is only ever raised by an explicit check, so a recorder
  /// nobody has asked about behaves exactly as before.
  bool foreignPending = false;

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

  /// The same nodes, each with the instant the **log** recorded.
  ///
  /// The pull used to write only the ids and let `Repository.softDeleteNode`
  /// stamp this device's own clock, which quietly made two things untrue: two
  /// devices disagreed about when a page had been deleted, so its thirty-day
  /// retention ran out at a different moment on each, and the container stopped
  /// matching its own log — invisible until `rebuildContainerFromLog` compared
  /// them, and then a rebuild refused on any joined notebook with something in
  /// its recycle bin.
  List<(String, int)> materialisedDeletions() => [
        for (final n in state.nodes.values)
          if (n.deletedAt != null) (n.id, n.deletedAt!)
      ];

  /// Record that [device]'s ops up to [seq] are folded in.
  ///
  /// Lowers [foreignPending] — the caller advances the watermark only after
  /// writing the materialised pages into the container, so by the time this
  /// runs, `state` and the container agree again and diffing is safe.
  void markForeignSeen(String dev, int seq,
      void Function(String key, Object? value) writeSetting) {
    writeSetting(foreignSeqKey(notebookId, dev), seq);
    // Persist where the read got to, so the next pull resumes instead of
    // re-parsing megabytes. Written only alongside the seq watermark — the two
    // must advance together, or a crash between them could leave an offset
    // past ops the container never received.
    final at = _resumeAt[dev];
    if (at != null) {
      writeSetting(foreignOffsetKey(notebookId, dev), at);
    }
    foreignPending = false;
  }

  /// Where [pendingForeignOps] stopped reading each foreign log, this call.
  ///
  /// Not persisted here: only [markForeignSeen] writes it, and only for a
  /// device whose ops actually reached the container.
  final Map<String, int> _resumeAt = {};

  /// The byte offset watermark, beside [foreignSeqKey].
  static String foreignOffsetKey(String notebookId, String device) =>
      'syncSeenAt:$notebookId:$device';

  /// Blobs referenced by ops whose bytes are not in `blobs/`. Empty means a
  /// rebuild from this log could reconstruct the notebook's content in full.
  ///
  /// A notebook with [materialiseBlobs] off reports **all** of them, and that is
  /// the honest answer rather than a bug: its log genuinely cannot supply those
  /// bytes yet. It is also the list a "prepare this for sync" action wants —
  /// though the backfill works from the container's index, which is the superset.
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
    // **Do not diff against state the container has not been given.**
    //
    // The replay at open folds EVERY device's log into `state`, including ops
    // this device has never written into its container. The app then saves the
    // page as the container knows it — without the other device's blocks —
    // and the diff below reads that absence as a deletion, emitting
    // `block.remove` at a Lamport above the original. That op wins the total
    // order on every replica, so the other device loses a block it wrote and
    // watched appear. Reproduced: a restart, then one keystroke on a page the
    // other device had also edited.
    //
    // Skipping the whole diff is deliberate rather than skipping only the
    // removals. A block the other device MODIFIED is also mis-seen: the
    // container's older copy differs from `prev`, so it is re-emitted as a
    // `block.set` carrying stale content at a higher Lamport, which reverts
    // their edit just as effectively without ever calling it a removal.
    //
    // The cost is one lost autosave of local edits to this page in the window
    // between launch and the fold — and it is not lost, only unrecorded: the
    // container still has it, and the next save after the fold records it
    // against correct state. A missed op is recoverable; a destructive one
    // that has already replicated is not.
    if (foreignPending) return;
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
        ops.add(_op(OpKind.blockRemove, {'pageId': pageId, 'blockId': goneId}));
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
  Op? _diffInk(
      String pageId, Map<String, dynamic> before, Map<String, dynamic> after) {
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
