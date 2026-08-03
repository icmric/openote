/// The operation record — the durable unit of change ([ADR-0006](../../../docs/adr/ADR-0006-sync-transport-and-text-model.md)).
///
/// Everything about this file is chosen so that a dumb file-sync service can
/// replicate notebooks correctly. Ops live in an **append-only, single-writer**
/// log per device, so two devices can never produce conflicting versions of one
/// file; merging is then just reading every log and applying the union in a
/// deterministic order.
///
/// **Encoding is JSON Lines** — one self-describing record per line. A torn or
/// partially-flushed tail costs the last line, not the file, which matters
/// because logs are appended to constantly and synced by processes we do not
/// control.
library;

import 'dart:convert';

/// Envelope format version. Bump only for a change a v1 reader cannot skip;
/// new *operations* do not need it (see [OpKind.unknown]).
const int opFormatVersion = 1;

/// What an operation does.
///
/// Ops are **block-level** by decision (ADR-0006 §6a.1): the smallest text
/// change we can express is "this block now holds this content". Concurrent
/// edits to different blocks of a page merge cleanly; concurrent edits to the
/// *same* block resolve last-writer-wins.
///
/// That is deliberately not permanent. Character-level text editing arrives as
/// **new op kinds** (a `text.splice` alongside `block.set`) once the structured
/// `nodes` model lands, which is why unknown kinds must survive rather than
/// abort — a v1 device replaying a newer device's log has to skip what it
/// cannot apply without corrupting everything it can.
enum OpKind {
  nodeUpsert('node.upsert'),
  nodeDelete('node.delete'),
  nodeRestore('node.restore'),
  nodePurge('node.purge'),
  blockSet('block.set'),
  blockRemove('block.remove'),

  /// Per-stroke ink edit: `{'pageId', 'blockId', 'del': [strokeId…],
  /// 'put': [{'i': index, 's': strokeJson}…], 'rect': {x,y,w,h}?, 'updatedAt'}`.
  ///
  /// Exists because ink blocks are HUGE — the importer puts a whole page's
  /// strokes in one block (up to several MB serialized) — and an erase gesture
  /// that split a handful of strokes used to append the entire block as a
  /// `block.set`: 50–1000× write amplification, ~300–400 MB of log for one
  /// heavy cleanup session. This op records only the changed strokes.
  ///
  /// `put` entries are positional inserts applied AFTER the `del` removals,
  /// so the exact strokes-list order is reproduced — the eraser inserts split
  /// fragments mid-list, and the rebuild-equals-container check compares the
  /// list verbatim, so append-only semantics would fail verification on every
  /// single erase.
  inkStrokes('ink.strokes'),
  pageProps('page.props'),
  blobPut('blob.put'),
  notebookMeta('notebook.meta'),

  /// An op written by a newer version than this one. Retained in order and
  /// re-serialised verbatim so a round-trip through an old device is lossless.
  unknown('?');

  const OpKind(this.tag);
  final String tag;

  static OpKind parse(String s) =>
      OpKind.values.firstWhere((k) => k.tag == s, orElse: () => OpKind.unknown);
}

/// One record in a device's log.
class Op {
  Op({
    required this.device,
    required this.seq,
    required this.lamport,
    required this.timestamp,
    required this.kind,
    required this.data,
    this.version = opFormatVersion,
    this.encryption = 'none',
    this.rawTag,
  });

  /// Envelope format version this record was written with.
  final int version;

  /// The device that wrote it. Exactly one device ever appends to a given log,
  /// which is the property that makes conflicts structurally impossible.
  final String device;

  /// Monotonic within [device], starting at 1. Gaps mean a lost write.
  final int seq;

  /// Lamport counter: `max(every lamport seen) + 1` at write time. This is what
  /// orders operations *across* devices. Wall-clock time cannot do that job —
  /// two devices' clocks disagree, and a clock that jumps backwards would
  /// silently reorder history.
  final int lamport;

  /// Wall clock at write time (epoch ms). **Informative only** — shown to
  /// users, never used for ordering or conflict resolution.
  final int timestamp;

  /// Reserved for end-to-end encryption (SYNC-5). Always `'none'` today, and
  /// nothing is encrypted.
  ///
  /// It exists now because logs are append-only and live on devices we do not
  /// control: adding this field later would mean rewriting every byte of every
  /// log everywhere at once. When it becomes real, [data] carries a base64
  /// ciphertext string instead of a map, and everything outside this file is
  /// unaffected.
  final String encryption;

  final OpKind kind;

  /// The payload. A map for every op this version writes; kept as `Object?` so
  /// an encrypted (string) payload needs no format change.
  final Object? data;

  /// The on-the-wire tag when [kind] is [OpKind.unknown], so re-serialising
  /// preserves it exactly.
  final String? rawTag;

  Map<String, dynamic> get map =>
      data is Map<String, dynamic> ? data as Map<String, dynamic> : const {};

  /// Deterministic total order across all devices.
  ///
  /// Lamport first (causality), then device id, then seq. The tie-break on
  /// device id is what makes it *total* rather than partial: two concurrent ops
  /// with the same Lamport value must still order identically on every device,
  /// or replicas diverge — which is the one bug this whole design exists to
  /// prevent, and the one that would be hardest to notice.
  static int compare(Op a, Op b) {
    final l = a.lamport.compareTo(b.lamport);
    if (l != 0) return l;
    final d = a.device.compareTo(b.device);
    if (d != 0) return d;
    return a.seq.compareTo(b.seq);
  }

  Map<String, dynamic> toJson() => {
        'v': version,
        'dev': device,
        'seq': seq,
        'lc': lamport,
        'ts': timestamp,
        'enc': encryption,
        'op': kind == OpKind.unknown ? (rawTag ?? '?') : kind.tag,
        'd': data,
      };

  /// One log line. No trailing newline — the writer adds it, so an interrupted
  /// append leaves an incomplete line the reader can discard rather than a
  /// complete-looking line with a truncated payload.
  String encode() => jsonEncode(toJson());

  /// Parse one line, or null if it is unusable.
  ///
  /// Returns null rather than throwing because the **last line of a log is
  /// routinely torn** — a crash or a sync client copying mid-append leaves a
  /// partial write. Losing that one op is correct; refusing to open the
  /// notebook is not.
  static Op? decode(String line) {
    if (line.trim().isEmpty) return null;
    try {
      final j = jsonDecode(line);
      if (j is! Map<String, dynamic>) return null;
      final dev = j['dev'];
      final seq = j['seq'];
      final lc = j['lc'];
      if (dev is! String || seq is! int || lc is! int) return null;
      final tag = j['op'] as String? ?? '?';
      final kind = OpKind.parse(tag);
      return Op(
        version: j['v'] as int? ?? opFormatVersion,
        device: dev,
        seq: seq,
        lamport: lc,
        timestamp: j['ts'] as int? ?? 0,
        encryption: j['enc'] as String? ?? 'none',
        kind: kind,
        data: j['d'],
        rawTag: kind == OpKind.unknown ? tag : null,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => '${kind.tag}@$device#$seq(lc$lamport)';
}

/// JSON with map keys sorted at every level.
///
/// Used for the rebuild-equals-container check: two structurally identical
/// pages must compare equal even though `dart:convert` preserves insertion
/// order, and insertion order differs between "loaded from SQLite" and "replayed
/// from a log". Without this the check would report false differences and be
/// quietly disabled by whoever got tired of it.
String canonicalJson(Object? value) => jsonEncode(_canonical(value));

Object? _canonical(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    return {for (final k in keys) k: _canonical(v[k])};
  }
  if (v is List) return [for (final e in v) _canonical(e)];
  return v;
}
