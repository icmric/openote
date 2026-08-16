/// The on-disk operation log — `.onotebook/ops/<device>.oplog`.
///
/// Layout (ADR-0006 §3):
/// ```
/// MyNotebook.onotebook/
///   manifest.json        notebook id, format version, sync scope
///   ops/<device>.oplog   append-only, ONE writer, ever
///   blobs/<sha256>       content-addressed (not yet written here)
/// ```
///
/// Today this sits **beside** the `.onote` container and shadows it: the
/// container is still authoritative and the log is written alongside, so that
/// "rebuild from the log and compare" is a live check rather than a leap of
/// faith. When the flip happens the container becomes `cache.onote` inside this
/// directory and stops being synced.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

// The content-addressing primitive, vendored in the store layer. Imported
// rather than re-implemented: a second SHA-256 would be a second chance to
// disagree with the one that MINTED these names, and the whole point of
// [blobBytesMatch] is that the two must be the same function.
import '../core/open_target.dart' show ensureNotebookPointer;
import '../store/notebook_writer.dart' show sha256Hex;
import 'op.dart';

class OpLogStore {
  OpLogStore(this.dir);

  /// The `.onotebook` directory.
  final Directory dir;

  /// `<workspace>/Foo.onote` → `<workspace>/Foo.onotebook`.
  ///
  /// Deliberately a sibling, not a replacement: migration is non-destructive
  /// (ADR-0006 §6a.5) and there is a real 324-page imported notebook that must
  /// not be risked to a half-built feature.
  /// The log directory for a notebook.
  ///
  /// [logDir] overrides the default sibling-of-the-container location. That
  /// override is what lets a second device keep its own local container while
  /// sharing the logs — see [NotebookRef.logDir].
  factory OpLogStore.forNotebook(String onotePath, {String? logDir}) {
    if (logDir != null && logDir.isNotEmpty) {
      return OpLogStore(Directory(logDir));
    }
    final base = p.withoutExtension(onotePath);
    return OpLogStore(Directory('$base.onotebook'));
  }

  Directory get opsDir => Directory(p.join(dir.path, 'ops'));
  Directory get blobsDir => Directory(p.join(dir.path, 'blobs'));
  File get manifestFile => File(p.join(dir.path, 'manifest.json'));
  File logFor(String device) => File(p.join(opsDir.path, '$device.oplog'));

  /// Content-addressed blob path. The hash IS the name, so two devices that
  /// independently store the same image produce the same file — which is why
  /// blobs need no merge logic at all and can be fetched lazily.
  File blobFile(String hash) =>
      File(p.join(blobsDir.path, hash.replaceFirst('sha256:', '')));

  bool hasBlob(String hash) => blobFile(hash).existsSync();

  /// Bytes of [hash]'s file, or null when there is no file **or it cannot be
  /// read right now** — a cloud client holding a lock, a dehydrated
  /// files-on-demand placeholder, a permission error.
  ///
  /// The try/catch is not tidiness: this is called from `Repository.getBlob`
  /// on the paint path, and `image_block_view` chains every image read behind
  /// the last through one shared queue — so a single unreadable file used to
  /// throw into render and blank every image loaded after it, page after
  /// page. "Could not read" behaves as "absent", which sends the caller to
  /// the container fallback exactly as a not-yet-synced file does.
  Uint8List? readBlob(String hash) {
    final f = blobFile(hash);
    try {
      return f.existsSync() ? f.readAsBytesSync() : null;
    } catch (_) {
      return null;
    }
  }

  /// Store blob bytes. Idempotent and immutable — content-addressed data can
  /// never legitimately change, so an existing file is always already correct
  /// and re-importing the same notebook rewrites nothing.
  ///
  /// Written via temp + rename because, unlike the append-only logs, a torn
  /// blob is not a recoverable tail — it is a corrupt image that would look
  /// like a decoding bug forever after.
  /// **"Always already correct" is an assumption, and [blobBytesMatch] is what
  /// checks it.** Temp+rename means nothing this code writes is ever torn, but
  /// it says nothing about a file a cloud client copied in half, a disk that
  /// went bad, or a hand-edited folder. Because the skip below is unconditional
  /// on existence, such a file is never repaired by any amount of re-running:
  /// `hasBlob` says yes, `missingBlobs()` says the notebook is complete, and
  /// the picture is broken for ever. See [SyncRecorder.proveBlobs].
  void writeBlob(String hash, Uint8List bytes) {
    if (hasBlob(hash)) return;
    blobsDir.createSync(recursive: true);
    final target = blobFile(hash);
    final tmp = File('${target.path}.tmp');
    tmp.writeAsBytesSync(bytes, flush: true);
    tmp.renameSync(target.path);
  }

  /// Whether [hash]'s file exists **and its bytes really are [hash]**.
  ///
  /// [hasBlob] is an `existsSync` and nothing more. Counting files, or checking
  /// their lengths, passes against a file whose bytes were replaced with the
  /// same number of different ones — which is exactly what a half-completed
  /// cloud download or a bad sector leaves behind. Only re-hashing can tell
  /// the difference, and Step 7 of the v0.17 plan deletes the container's copy
  /// on the strength of this answer, so a false "yes" here is data loss later.
  bool blobBytesMatch(String hash) {
    final f = blobFile(hash);
    if (!f.existsSync()) return false;
    try {
      return sha256Hex(f.readAsBytesSync()) == hash.replaceFirst('sha256:', '');
    } catch (_) {
      // Unreadable — a permission error, a file the cloud client has locked.
      // "I could not check" must never read as "it matched".
      return false;
    }
  }

  /// Delete a blob file whose bytes are not what its name says.
  ///
  /// The one and only caller is the repair in [SyncRecorder.proveBlobs], and it
  /// exists solely because [writeBlob] refuses to overwrite: without a way to
  /// remove the wrong file first, a blob that fails [blobBytesMatch] can never
  /// be put right. Deliberately not exposed as "delete a blob" — nothing in
  /// Openote deletes content-addressed bytes, and blob GC (ADR-0007) is a
  /// separate, unbuilt thing.
  ///
  /// **Delete-and-rewrite is only safe when the caller HOLDS verified
  /// replacement bytes**, as the repair does. `blobs/` lives in the shared
  /// folder, so a cloud client replicates whatever happens here: the sync
  /// pull once called this on a bytes-mismatch with no replacement, and the
  /// deletion of one device's half-copied download replicated out and removed
  /// every other device's GOOD copy of the picture. A caller without the
  /// bytes in hand must use `Repository.holdBlobUntilVerified` instead, which
  /// has only local consequences.
  void discardBlob(String hash) {
    final f = blobFile(hash);
    if (f.existsSync()) f.deleteSync();
  }

  /// Hashes present in `blobs/`.
  Set<String> blobHashes() {
    if (!blobsDir.existsSync()) return {};
    return {
      for (final f in blobsDir.listSync())
        if (f is File && !f.path.endsWith('.tmp')) p.basename(f.path)
    };
  }

  bool get exists => dir.existsSync();

  /// Create the directory and manifest if absent. Idempotent.
  void ensureInitialised({required String notebookId, required String title}) {
    opsDir.createSync(recursive: true);
    // The one thing a student can double-click (v0.17 plan, Step 8b). Written
    // HERE because this is the single place every `.onotebook` comes into
    // existence — created fresh, moved into Drive, adopted from a git clone —
    // and a pointer file that only some notebooks had would be worse than none
    // at all. Best-effort and never rewritten; see core/open_target.dart.
    ensureNotebookPointer(dir.path, title: title);
    if (!manifestFile.existsSync()) {
      _writeManifest({
        'format': {'major': 1, 'minor': 0},
        'notebookId': notebookId,
        'title': title,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        // Sync scope is an explicit object rather than an implied "everything
        // under this directory", so that section-level sharing can later be a
        // new scope value instead of a new file layout (ADR-0006 §6a, granularity
        // decision: per notebook now, section later).
        'scope': {'kind': 'notebook', 'id': notebookId},
        // Devices announce themselves here. Informational — a log file's
        // existence is the real registry; this is for showing the user which
        // devices touched a notebook.
        'devices': <String, dynamic>{},
      });
    }
  }

  Map<String, dynamic> readManifest() {
    if (!manifestFile.existsSync()) return {};
    try {
      final j = jsonDecode(manifestFile.readAsStringSync());
      return j is Map<String, dynamic> ? j : {};
    } catch (_) {
      // A torn manifest must not block opening a notebook: every field in it is
      // either recoverable from the logs or cosmetic.
      return {};
    }
  }

  void _writeManifest(Map<String, dynamic> m) {
    // Atomic: temp + rename. Unlike the logs this file is rewritten in place,
    // so a torn write would otherwise be unrecoverable.
    final tmp = File('${manifestFile.path}.tmp');
    tmp.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(m),
        flush: true);
    tmp.renameSync(manifestFile.path);
  }

  /// Record that [device] has written to this notebook.
  void announceDevice(String device, {String? label}) {
    final m = readManifest();
    final devices = (m['devices'] as Map?)?.cast<String, dynamic>() ?? {};
    if (devices.containsKey(device)) return;
    devices[device] = {
      'firstSeen': DateTime.now().millisecondsSinceEpoch,
      if (label != null) 'label': label,
    };
    m['devices'] = devices;
    _writeManifest(m);
  }

  /// Device ids that have a log in this notebook.
  /// How many times the ops directory has actually been listed.
  ///
  /// The same rule as [Repository.debugPageDecodes]: the status bar calls
  /// `syncDeviceCount` on every rebuild — every keystroke — and once a notebook
  /// lives in a cloud folder this is filesystem I/O against a sync-client-backed
  /// path. The cache that stops that was pinned by a wall-clock bar, which on a
  /// loaded runner measures the runner. A working cache does zero further
  /// listings; a broken one does one per call, and neither depends on the clock.
  static int debugDirectoryListings = 0;

  List<String> deviceIds() {
    if (!opsDir.existsSync()) return const [];
    debugDirectoryListings++;
    return [
      for (final f in opsDir.listSync())
        if (f is File && f.path.endsWith('.oplog'))
          p.basenameWithoutExtension(f.path)
    ]..sort();
  }

  /// Every op in one device's log, in write order.
  ///
  /// Unparseable lines are skipped, not fatal — see [Op.decode]. A log whose
  /// last append was interrupted is the normal case, not an exceptional one.
  ///
  /// **Bytes, then a tolerant decode — not `readAsStringSync`.** That helper
  /// decodes UTF-8 *strictly* and throws `FileSystemException` the moment a
  /// file ends part-way through a multi-byte character, which is exactly what a
  /// torn append looks like when the last op contained a non-ASCII glyph.
  /// [readAll], [highestLamport] and [lastSeq] all route through here, so one
  /// half-written `ℝ` stopped sync outright — and after the container is demoted
  /// to a cache it would be the notebook refusing to open. Measured on the
  /// owner's real 1,523,044-byte log: of 1,487 cuts at every 1 KiB boundary,
  /// **2 made `readAll()` throw**; on a 317-byte log dense with the maths
  /// symbols these notes are full of (ℝ ∃ ∈), **6 of 316 cuts threw**.
  /// [readDeviceFrom] has always decoded the identical bytes with
  /// `allowMalformed: true` (see the `utf8.decode` below in that method); this
  /// now matches it, so the paced and unpaced readers can no longer disagree
  /// about whether a log is readable.
  List<Op> readDevice(String device) {
    final f = logFor(device);
    if (!f.existsSync()) return const [];
    final ops = <Op>[];
    final text = utf8.decode(f.readAsBytesSync(), allowMalformed: true);
    for (final line in const LineSplitter().convert(text)) {
      final op = Op.decode(line);
      if (op != null) ops.add(op);
    }
    return ops;
  }

  /// [readDevice] from a byte offset, for a caller that has already seen the
  /// prefix.
  ///
  /// **Why this exists.** `pendingForeignOps` ran `readDevice` for every
  /// foreign device on EVERY pull — and `readDevice` slurps and JSON-parses the
  /// whole file to then discard everything at or below a watermark. Measured on
  /// a real notebook: **1,977 ms to parse one 64.6 MB log**, paid on the UI
  /// thread, every time the sync button was pressed or the watcher fired, even
  /// when nothing had changed. That is most of the reported "app fully locks up
  /// for 10-20s".
  ///
  /// A byte offset is safe here in a way it would not be for a general file,
  /// and the reason is the transport's central rule: **a device's log is
  /// append-only and has exactly one writer.** Bytes below the offset can never
  /// change, so they never need re-reading.
  ///
  /// Returns the ops found after [from] and the offset to resume at. The
  /// resume offset is the end of the last COMPLETE line — a log being written
  /// by a cloud client routinely ends mid-line, and resuming inside that line
  /// next time would silently lose the op it belongs to.
  ///
  /// **Paced, because the offset alone did not make the first read cheap.**
  /// Once a log has never been read (a git join, a restored offset, a device
  /// that just joined the folder) `from` is 0 and this reads the whole thing.
  /// Measured on a generated 64.6 MB log, 138,657 ops: **1,008 ms in one
  /// uninterrupted block**, broken down as read 30 ms, utf8 26 ms, line split
  /// 206 ms, `Op.decode` 764 ms. That is a frozen window, on the UI thread,
  /// and it is what remained after 7851c3d paced everything downstream of it.
  ///
  /// So the bytes are decoded a window at a time with the event loop let go
  /// between windows. **The ops still come back as one list and the caller
  /// still sorts the whole batch before applying any of it** — pacing changes
  /// only when the work happens, never which ops are in the answer or what
  /// order they end up in. See `SyncRecorder.pendingForeignOps`.
  Future<({List<Op> ops, int next})> readDeviceFrom(
      String device, int from) async {
    final f = logFor(device);
    if (!f.existsSync()) return (ops: const <Op>[], next: 0);
    final len = f.lengthSync();
    // A file that SHRANK is not the file we had an offset into — a fresh
    // clone, a restore, a compaction. Start over rather than read from a
    // meaningless position.
    final start = (from > 0 && from <= len) ? from : 0;
    // The overwhelmingly common pull: nothing new. No read, no yield, no cost.
    if (start >= len) return (ops: const <Op>[], next: len);

    final ops = <Op>[];
    // Where the last COMPLETE line ended. Stays at [start] until one is found,
    // which reproduces the old "no complete line in this window yet" answer.
    var next = start;

    // ONE handle held across the whole windowed read, deliberately. The
    // offsets we hand back are only meaningful against the file we started
    // from, and the log is append-only with a single writer, so bytes at or
    // below `len` cannot change under us — appends past `len` are simply next
    // pull's business.
    final raf = f.openSync();
    try {
      var pos = start;
      // Bytes of a line that straddled a window boundary. A single op can be
      // several megabytes (an ink block.set), so this is allowed to outgrow
      // the window rather than being treated as a torn tail.
      final carry = BytesBuilder();
      while (pos < len) {
        raf.setPositionSync(pos);
        final chunk = raf.readSync(math.min(_parseWindow, len - pos));
        if (chunk.isEmpty) break; // truncated under us; take what we have
        pos += chunk.length;

        var lastNl = -1;
        for (var i = chunk.length - 1; i >= 0; i--) {
          if (chunk[i] == 0x0A) {
            lastNl = i;
            break;
          }
        }
        if (lastNl >= 0) {
          carry.add(Uint8List.sublistView(chunk, 0, lastNl + 1));
          final complete = carry.takeBytes();
          carry.add(Uint8List.sublistView(chunk, lastNl + 1));
          next += complete.length;
          final text = utf8.decode(complete, allowMalformed: true);
          for (final line in const LineSplitter().convert(text)) {
            final op = Op.decode(line);
            if (op != null) ops.add(op);
          }
        } else {
          carry.add(chunk);
        }

        // A REAL delay, not `Duration.zero`. Same lesson as
        // `SyncRecorder.backfillBlobs` and `AppState._inChunks`: on Windows
        // the UI isolate lives on the Win32 message loop, where posted
        // messages outrank hardware input, so a zero-duration timer is work
        // due immediately and the queue never goes idle — the window would
        // still not answer the mouse. One millisecond lets it actually wait.
        if (pos < len) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      }
    } finally {
      raf.closeSync();
    }
    return (ops: ops, next: next);
  }

  /// Bytes decoded per turn of the event loop by [readDeviceFrom].
  ///
  /// Measured at ~16 ms per megabyte (1,058 ms for 64.6 MB, three quarters of
  /// it `jsonDecode`), so half a megabyte is ~8 ms — inside a frame with room
  /// for the frame itself, the same budget `AppState._pullPageChunk` picked.
  static const int _parseWindow = 512 * 1024;

  /// The union of every device's log, in deterministic total order.
  /// This is the merge: there is no conflict resolution step, only a sort.
  List<Op> readAll() {
    final all = <Op>[];
    for (final d in deviceIds()) {
      all.addAll(readDevice(d));
    }
    all.sort(Op.compare);
    return all;
  }

  /// Highest Lamport value anywhere in this notebook, 0 if empty. A writer
  /// starts from `this + 1` so its ops sort after everything it has seen.
  int highestLamport() {
    var hi = 0;
    for (final d in deviceIds()) {
      for (final op in readDevice(d)) {
        if (op.lamport > hi) hi = op.lamport;
      }
    }
    return hi;
  }

  /// Highest seq in [device]'s own log, 0 if none. Used by the fork-on-conflict
  /// check in `device_identity.dart`.
  int lastSeq(String device) {
    var hi = 0;
    for (final op in readDevice(device)) {
      if (op.seq > hi) hi = op.seq;
    }
    return hi;
  }

  /// Append to [device]'s log.
  ///
  /// Append-only, so no temp-and-rename dance is needed: a torn append damages
  /// only the final line, which the reader discards. `flush: true` because the
  /// whole point of the log is to survive the crash that loses the container.
  ///
  /// **The missing newline is glued back on first.** A tear one byte from the
  /// end leaves a *complete* JSON record with no terminator, and the next
  /// append used to concatenate straight onto it — welding two valid records
  /// into one unparseable line. Measured: append 3 ops, drop one byte, append 2
  /// more, and [readDevice] returned seqs **[1, 2, 5]**. Two ops lost for one
  /// lost byte, where this format's whole promise ([Op.decode]) is that a torn
  /// tail costs the last line and nothing else. With the terminator restored
  /// the same sequence returns all five: the record that lost only its newline
  /// was never damaged, just unterminated.
  void append(String device, List<Op> ops) {
    if (ops.isEmpty) return;
    opsDir.createSync(recursive: true);
    final f = logFor(device);
    final glue = _endsMidLine(f) ? '\n' : '';
    final sink = f.openSync(mode: FileMode.append);
    try {
      sink.writeStringSync('$glue${ops.map((o) => o.encode()).join('\n')}\n');
      sink.flushSync();
    } finally {
      sink.closeSync();
    }
  }

  /// Whether [f] ends in something other than a line terminator — i.e. whether
  /// the previous append was cut short. One byte read, only on append, so this
  /// costs nothing next to the `flushSync` it precedes.
  static bool _endsMidLine(File f) {
    if (!f.existsSync()) return false;
    final len = f.lengthSync();
    if (len == 0) return false;
    final raf = f.openSync();
    try {
      raf.setPositionSync(len - 1);
      final last = raf.readSync(1);
      return last.isNotEmpty && last[0] != 0x0A;
    } finally {
      raf.closeSync();
    }
  }
}
