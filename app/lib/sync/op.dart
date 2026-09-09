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

import 'package:crypto/crypto.dart';

/// **The newest envelope this build can APPLY.**
///
/// Not the same number as the one it writes, and conflating the two is how a
/// format bump takes every older install offline at once. Reading is a
/// capability — "I understand v2 records" — while writing is a *choice* about
/// who else will still be able to open the notebook afterwards. See
/// [opWriteVersion].
const int opFormatVersion = 2;

/// **The envelope this build writes for ops every released build understands.**
///
/// Almost everything. An op kind an older build does not know is skipped
/// harmlessly (see [OpKind.unknown]); what an older build must NOT do is
/// half-read a log and then write on top of it, which is what the envelope
/// version guards.
const int opWriteVersion = 1;

/// **The envelope for an op only a v2 reader can be trusted with.**
///
/// [OpKind.blockPatch] alone, today. A v1 build meeting one of these does the
/// safe thing already, and has since v0.17: `Materializer.apply` files it under
/// `unsupported`, and `SyncRecorder.logIsAhead` turns that into a read-only
/// notebook — because every op that recorder would write is a diff against a
/// history it has only half read.
///
/// So the cost of writing one is precise and worth stating: **the first text
/// patch written into a notebook makes that notebook read-only on every
/// Openote older than 1.0.** That is why it is spent now, when the oldest
/// build in the world is four days old, rather than later.
const int opPatchVersion = 2;

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

  /// **The characters that changed in one string, rather than the block.**
  ///
  /// `{'pageId', 'blockId', 'k': contentKey, 'base': fingerprint,
  /// 'at': index, 'del': count, 'ins': text, 'rect': {x,y,w,h}?, 'updatedAt'}`
  ///
  /// Exists for the same reason [inkStrokes] does, measured the same way. A
  /// `block.set` carries the ENTIRE block, and an autosave fires at every
  /// pause in a sentence — so one character added to a 2,000-character
  /// paragraph cost ~2.5 KB of permanent, replicated log, and paid it again a
  /// moment later. On the author's own notebooks, text `block.set` was **52.6%
  /// of the whole log** (`test/oplog_composition_test.dart` measures this; do
  /// not take the number on faith, re-run it).
  ///
  /// `at`/`del`/`ins` is a single splice in UTF-16 code units, computed from
  /// the common prefix and suffix and **snapped to whole runes**, so a
  /// boundary never lands between the halves of a surrogate pair.
  ///
  /// **`base` is what makes it safe to merge.** A patch is meaningless against
  /// text it was not computed from, and logs from two devices merge as the
  /// union in a total order — so a patch really can arrive to be applied on
  /// top of some other device's `block.set`. Applied blind that is silent
  /// corruption; today the same collision resolves last-writer-wins and gives
  /// you a coherent block. So the op carries a fingerprint of the string it
  /// was computed against, and a reader that does not match it **drops the
  /// patch**, which lands exactly on the last-writer-wins behaviour that was
  /// there before. Written at [opPatchVersion]; see there for the cost.
  blockPatch('block.patch'),

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

/// One change to a string: replace [del] code units at [at] with [ins].
class TextSplice {
  const TextSplice(this.at, this.del, this.ins);
  final int at;
  final int del;
  final String ins;
}

bool _isHigh(int u) => u >= 0xD800 && u <= 0xDBFF;
bool _isLow(int u) => u >= 0xDC00 && u <= 0xDFFF;

/// Would cutting [s] at [i] land between the halves of one character?
bool _splitsPair(String s, int i) =>
    i > 0 && i < s.length && _isLow(s.codeUnitAt(i)) && _isHigh(s.codeUnitAt(i - 1));

/// **The one splice that turns [old] into [now]**, from their common prefix
/// and suffix. Null when they are already equal.
///
/// Dart strings are UTF-16, so the obvious loop over code units will happily
/// cut an emoji, a musical symbol or a rarer CJK character in half — and each
/// half is not a character at all, it is an unpaired surrogate. Both ends back
/// off to a whole-character boundary, and both strings are checked at each:
/// the prefix is shared, but which side runs out first is not.
///
/// Deliberately one splice rather than a real diff. An autosave records what
/// changed since the last pause in a sentence, which is almost always one
/// insertion, one deletion, or a typed-over selection; anything more
/// scattered simply produces a bigger splice, and the caller falls back to
/// recording the whole block when it stops paying.
TextSplice? spliceBetween(String old, String now) {
  if (old == now) return null;
  final limit = old.length < now.length ? old.length : now.length;
  var at = 0;
  while (at < limit && old.codeUnitAt(at) == now.codeUnitAt(at)) {
    at++;
  }
  while (at > 0 && (_splitsPair(old, at) || _splitsPair(now, at))) {
    at--;
  }

  final maxSuffix =
      (old.length - at) < (now.length - at) ? old.length - at : now.length - at;
  var suffix = 0;
  while (suffix < maxSuffix &&
      old.codeUnitAt(old.length - 1 - suffix) ==
          now.codeUnitAt(now.length - 1 - suffix)) {
    suffix++;
  }
  while (suffix > 0 &&
      (_splitsPair(old, old.length - suffix) ||
          _splitsPair(now, now.length - suffix))) {
    suffix--;
  }

  return TextSplice(
      at, old.length - at - suffix, now.substring(at, now.length - suffix));
}

/// **Apply one [OpKind.blockPatch] payload to [old]**, or null to refuse.
///
/// One function, called by both the materialiser and anything else that
/// replays a log, so there is exactly one reading of the guard. Null means
/// "leave the text alone", which lands on the last-writer-wins behaviour that
/// was there before patches existed:
///
///  * **the fingerprint does not match** — this patch was computed against a
///    different string, so another device's `block.set` is ordered between the
///    two halves of this edit. Applying it anyway is silent corruption; that
///    is the whole reason `base` is on the wire;
///  * the payload is malformed, or its range does not fit the string.
String? applyTextPatch(String old, Map<String, dynamic> d) {
  if (d['base'] != textFingerprint(old)) return null;
  final at = (d['at'] as num?)?.toInt();
  final del = (d['del'] as num?)?.toInt();
  final ins = d['ins'];
  if (at == null || del == null || ins is! String) return null;
  if (at < 0 || del < 0 || at + del > old.length) return null;
  return old.substring(0, at) + ins + old.substring(at + del);
}

/// **The fingerprint of the string a [OpKind.blockPatch] was computed from.**
///
/// Here rather than beside either user of it, because a writer and a reader
/// that disagree about this function do not fail loudly — the reader simply
/// drops every patch and the log quietly grows the way it used to.
///
/// Truncated to sixteen hex characters: this guards against applying a splice
/// to the wrong text, not against an adversary, and a collision would have to
/// be between two strings one of which somebody actually wrote.
String textFingerprint(String s) =>
    sha256.convert(utf8.encode(s)).toString().substring(0, 16);

/// One record in a device's log.
class Op {
  Op({
    required this.device,
    required this.seq,
    required this.lamport,
    required this.timestamp,
    required this.kind,
    required this.data,
    this.version = opWriteVersion,
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
        version: j['v'] as int? ?? 1,
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
