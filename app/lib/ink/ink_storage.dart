/// Where ink stops being JSON: the boundary between the app's working shape
/// and what actually goes on disk.
///
/// **Why a boundary and not a rewrite.** Sixteen places read or write
/// `content['strokes']` — the painter, the eraser, lasso, drag, resize,
/// recolour, undo, three exporters, the importer. Converting all of them to a
/// blob-backed representation is the right eventual shape, and it is also a
/// one-way migration of somebody's handwriting done through sixteen edits at
/// once. So the working representation stays exactly what it is, and the
/// conversion happens at the two moments something is persisted and the one
/// moment something is loaded.
///
/// The saving is unaffected by that choice — it is the bytes on disk that were
/// 63 MB — and it costs one encode per ink-block save and one decode per ink
/// page load. Both are *faster* than the JSON they replace: the largest real
/// block encodes in ~40 ms against jsonEncode of 3 MB, and binary decode beats
/// `jsonDecode` plus 64,000 `Stroke.fromJson` calls comfortably.
///
/// **The persisted shape**, deliberately carrying more than is used yet:
///
/// ```json
/// "content": {"ink": {
///   "v": 1,
///   "base": "sha256:…",   // the strokes
///   "add": [],            // future: erase/append overlays
///   "gone": "",           // future: run-length removed indices
///   "n": 612,             // stroke count, so counting never opens a blob
///   "o": [minX, minY]     // the origin the blob's coordinates are relative to
/// }}
/// ```
///
/// `add`/`gone` are read on the way in and preserved on the way out from the
/// start, so the incremental-overlay scheme can land later WITHOUT a second
/// migration of everyone's notebooks.
library;

import 'dart:typed_data';

import '../model/models.dart';
import 'ink_codec.dart';

/// The key inside an ink block's `content` that holds the persisted form.
const String kInkKey = 'ink';

/// The legacy key: a JSON array of strokes. Read forever — `page_versions`
/// snapshots written before the migration hold this shape, and restoring one
/// has to keep working.
const String kStrokesKey = 'strokes';

abstract final class InkStorage {
  /// Does this block's content hold ink in the persisted (blob-ref) form?
  static bool isRefForm(Map<String, dynamic> content) =>
      content[kInkKey] is Map;

  /// Does it hold ink in the legacy inline-JSON form?
  static bool isLegacyForm(Map<String, dynamic> content) =>
      content[kStrokesKey] is List;

  /// How many strokes, WITHOUT opening a blob.
  ///
  /// Several callers only want a count — the export summaries, and the canvas's
  /// "this block is full" guard. Making them decode geometry to count it is
  /// what made those paths expensive.
  static int strokeCount(Map<String, dynamic> content) {
    final ink = content[kInkKey];
    if (ink is Map) return (ink['n'] as num?)?.toInt() ?? 0;
    final legacy = content[kStrokesKey];
    return legacy is List ? legacy.length : 0;
  }

  /// Every blob hash this ink block depends on, for `blob_refs` and for the
  /// missing-bytes check.
  ///
  /// Without this, ADR-0007's garbage collection — which recomputes what is
  /// referenced by scanning pages — would see no path from a page to its
  /// handwriting and collect the entire notebook's ink.
  static List<String> refsOf(Map<String, dynamic> content) {
    final ink = content[kInkKey];
    if (ink is! Map) return const [];
    final base = ink['base'];
    return [
      if (base is String && base.isNotEmpty) base,
      for (final a in (ink['add'] as List? ?? const []))
        if (a is String && a.isNotEmpty) a
    ];
  }

  /// The persisted form of [content], writing the strokes through [putBlob].
  ///
  /// [putBlob] takes bytes and returns the hash as stored — `sha256:<hex>` or
  /// bare hex, whichever the caller's store uses; it is round-tripped verbatim.
  /// It MUST also record the bytes in the operation log, not just the container:
  /// `Repository.putBlob` alone writes the `blobs` table and emits no
  /// `blob.put`, which would leave the log unable to reconstruct the ink it
  /// references.
  ///
  /// Returns [content] unchanged when there is nothing to do — already
  /// persisted, or not ink at all — so this is safe to call on every block of
  /// every page.
  static Map<String, dynamic> toPersisted(
    Map<String, dynamic> content,
    String Function(Uint8List bytes) putBlob,
  ) {
    if (isRefForm(content)) return content;
    final legacy = content[kStrokesKey];
    if (legacy is! List) return content;

    final strokes = <Stroke>[];
    for (final s in legacy) {
      if (s is Map) {
        try {
          strokes.add(Stroke.fromJson(s.cast<String, dynamic>()));
        } catch (_) {
          // A stroke this build cannot parse. Dropping it silently would lose
          // handwriting, so bail out and leave the block in its legacy form —
          // it still renders, it is still saved, it is just not smaller.
          return content;
        }
      }
    }

    // An empty ink block has no blob. Writing a zero-stroke object would
    // create a hash every empty block shared, which is harmless but pointless.
    if (strokes.isEmpty) {
      final out = Map<String, dynamic>.of(content)..remove(kStrokesKey);
      out[kInkKey] = {'v': 1, 'base': '', 'add': const [], 'gone': '', 'n': 0,
        'o': const [0.0, 0.0]};
      return out;
    }

    // The origin is the block's own top-left extent, which is what keeps the
    // deltas small and makes a later drag free.
    var ox = double.infinity, oy = double.infinity;
    for (final s in strokes) {
      for (var i = 0; i < s.x.length; i++) {
        if (s.x[i] < ox) ox = s.x[i];
        if (i < s.y.length && s.y[i] < oy) oy = s.y[i];
      }
    }
    if (!ox.isFinite) ox = 0;
    if (!oy.isFinite) oy = 0;

    final hash =
        putBlob(InkCodec.encode(strokes, originX: ox, originY: oy));
    final out = Map<String, dynamic>.of(content)..remove(kStrokesKey);
    out[kInkKey] = {
      'v': 1,
      'base': hash,
      'add': const <String>[],
      'gone': '',
      'n': strokes.length,
      'o': [ox, oy],
    };
    return out;
  }

  /// The working form of [content], reading blobs through [getBlob].
  ///
  /// Returns [content] unchanged when it is already inline, or when the bytes
  /// are not available — a notebook joined from a git remote can legitimately
  /// hold a ref whose blob has not arrived yet, and the right behaviour then is
  /// an ink block that draws nothing rather than a page that fails to open.
  static Map<String, dynamic> toWorking(
    Map<String, dynamic> content,
    Uint8List? Function(String hash) getBlob,
  ) {
    final ink = content[kInkKey];
    if (ink is! Map) return content;
    final base = ink['base'];
    final o = ink['o'];
    final ox = (o is List && o.isNotEmpty) ? (o[0] as num).toDouble() : 0.0;
    final oy = (o is List && o.length > 1) ? (o[1] as num).toDouble() : 0.0;

    final strokes = <Stroke>[];
    if (base is String && base.isNotEmpty) {
      final bytes = getBlob(base);
      if (bytes == null) {
        // Ref present, bytes absent. Leave the ref alone — a save must not
        // then overwrite it with an empty stroke list, which is exactly how a
        // half-synced notebook would lose its ink.
        return content;
      }
      try {
        strokes.addAll(InkCodec.decode(bytes,
            originX: ox,
            originY: oy,
            // Ids derive from the blob so they are stable across decodes.
            idPrefix: base.length > 20 ? base.substring(base.length - 12) : base));
      } catch (_) {
        return content;
      }
    }
    // Overlays, for when the incremental scheme lands. Absent today.
    for (final a in (ink['add'] as List? ?? const [])) {
      if (a is! String || a.isEmpty) continue;
      final bytes = getBlob(a);
      if (bytes == null) continue;
      try {
        strokes.addAll(InkCodec.decode(bytes,
            originX: ox, originY: oy, idPrefix: a.substring(a.length - 12)));
      } catch (_) {
        // A damaged overlay must not take the base strokes down with it.
      }
    }
    final gone = _parseGone(ink['gone']);
    final live = <Stroke>[];
    for (var i = 0; i < strokes.length; i++) {
      if (!gone.contains(i)) live.add(strokes[i]);
    }

    final out = Map<String, dynamic>.of(content);
    // The ink descriptor is KEPT alongside the working strokes, so a save that
    // does not touch this block can put the identical ref back rather than
    // re-encoding and re-hashing bytes that have not changed.
    out[kStrokesKey] = [for (final s in live) s.toJson()];
    return out;
  }

  /// Run-length indices: `"12,40-57,900"`.
  static Set<int> _parseGone(Object? raw) {
    if (raw is! String || raw.isEmpty) return const {};
    final out = <int>{};
    for (final part in raw.split(',')) {
      final dash = part.indexOf('-');
      if (dash < 0) {
        final v = int.tryParse(part);
        if (v != null) out.add(v);
      } else {
        final a = int.tryParse(part.substring(0, dash));
        final b = int.tryParse(part.substring(dash + 1));
        if (a != null && b != null && b >= a) {
          for (var i = a; i <= b; i++) {
            out.add(i);
          }
        }
      }
    }
    return out;
  }

  /// Persist every ink block of [blocks]. Returns fresh [Block]s; the input is
  /// not mutated, because the caller's list is the live editor state.
  static List<Block> persistAll(
      List<Block> blocks, String Function(Uint8List) putBlob) {
    var touched = false;
    final out = <Block>[];
    for (final b in blocks) {
      if (b.type != BlockType.ink) {
        out.add(b);
        continue;
      }
      final next = toPersisted(b.content, putBlob);
      if (next == b.content) {
        out.add(b);
        continue;
      }
      touched = true;
      // Through the model's own serialisation rather than a hand-built copy.
      // `Block` has no `copyWith`, and enumerating its fields here would mean
      // a new field silently vanishing from every ink block — exactly the
      // forward-compatibility failure `rawType` and `unknownFields` exist to
      // prevent. `toJson`/`fromJson` is the one place that knows them all.
      final j = b.toJson()..['content'] = next;
      out.add(Block.fromJson(j));
    }
    return touched ? out : blocks;
  }

  /// The inverse, for a page just read from disk.
  static List<Block> workingAll(
      List<Block> blocks, Uint8List? Function(String) getBlob) {
    var touched = false;
    final out = <Block>[];
    for (final b in blocks) {
      if (b.type != BlockType.ink) {
        out.add(b);
        continue;
      }
      final next = toWorking(b.content, getBlob);
      if (next == b.content) {
        out.add(b);
        continue;
      }
      touched = true;
      // Through the model's own serialisation rather than a hand-built copy.
      // `Block` has no `copyWith`, and enumerating its fields here would mean
      // a new field silently vanishing from every ink block — exactly the
      // forward-compatibility failure `rawType` and `unknownFields` exist to
      // prevent. `toJson`/`fromJson` is the one place that knows them all.
      final j = b.toJson()..['content'] = next;
      out.add(Block.fromJson(j));
    }
    return touched ? out : blocks;
  }
}
