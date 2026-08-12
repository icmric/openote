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
import 'dart:typed_data';

import 'package:path/path.dart' as p;

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

  Uint8List? readBlob(String hash) {
    final f = blobFile(hash);
    return f.existsSync() ? f.readAsBytesSync() : null;
  }

  /// Store blob bytes. Idempotent and immutable — content-addressed data can
  /// never legitimately change, so an existing file is always already correct
  /// and re-importing the same notebook rewrites nothing.
  ///
  /// Written via temp + rename because, unlike the append-only logs, a torn
  /// blob is not a recoverable tail — it is a corrupt image that would look
  /// like a decoding bug forever after.
  void writeBlob(String hash, Uint8List bytes) {
    if (hasBlob(hash)) return;
    blobsDir.createSync(recursive: true);
    final target = blobFile(hash);
    final tmp = File('${target.path}.tmp');
    tmp.writeAsBytesSync(bytes, flush: true);
    tmp.renameSync(target.path);
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
  List<Op> readDevice(String device) {
    final f = logFor(device);
    if (!f.existsSync()) return const [];
    final ops = <Op>[];
    for (final line in const LineSplitter().convert(f.readAsStringSync())) {
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
  ({List<Op> ops, int next}) readDeviceFrom(String device, int from) {
    final f = logFor(device);
    if (!f.existsSync()) return (ops: const [], next: 0);
    final len = f.lengthSync();
    // A file that SHRANK is not the file we had an offset into — a fresh
    // clone, a restore, a compaction. Start over rather than read from a
    // meaningless position.
    var start = (from > 0 && from <= len) ? from : 0;
    if (start >= len) return (ops: const [], next: len);

    final raf = f.openSync();
    final Uint8List bytes;
    try {
      raf.setPositionSync(start);
      bytes = raf.readSync(len - start);
    } finally {
      raf.closeSync();
    }

    // Where the last newline is, so a torn tail is left for next time.
    var lastNl = -1;
    for (var i = bytes.length - 1; i >= 0; i--) {
      if (bytes[i] == 0x0A) {
        lastNl = i;
        break;
      }
    }
    if (lastNl < 0) {
      // No complete line in this window yet.
      return (ops: const [], next: start);
    }

    final text = utf8.decode(
        Uint8List.sublistView(bytes, 0, lastNl + 1),
        allowMalformed: true);
    final ops = <Op>[];
    for (final line in const LineSplitter().convert(text)) {
      final op = Op.decode(line);
      if (op != null) ops.add(op);
    }
    return (ops: ops, next: start + lastNl + 1);
  }

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
  void append(String device, List<Op> ops) {
    if (ops.isEmpty) return;
    opsDir.createSync(recursive: true);
    final sink = logFor(device).openSync(mode: FileMode.append);
    try {
      sink.writeStringSync('${ops.map((o) => o.encode()).join('\n')}\n');
      sink.flushSync();
    } finally {
      sink.closeSync();
    }
  }
}
