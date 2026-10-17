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

/// **Marks a persisted ink block whose strokes are not a group.**
///
/// A stroke is its own object on the canvas — issue #20, and the owner twice
/// on inferred grouping — but a block is an expensive way to say so on disk.
/// Measured, 200 strokes of 40 points on one page: 26 KB as one block and
/// 123 KB as 200, and the difference is almost all **envelope**. 380 bytes per
/// block, of which an id is 43, two timestamps are 50, a blob reference is
/// 147, and 80 are fields that are null or zero for every stroke anybody has
/// ever drawn. The owner: *"that is considerably less space efficient than i
/// was expecting it to be, surley there has to be a way to provide more
/// control over ink strokes without an almost 5x increase in storage use."*
///
/// There is, and it is this: **selection granularity and storage granularity
/// are different questions.** Loose strokes travel to disk in one block and
/// come back as one block each, so the canvas keeps the per-stroke objects it
/// needs and the page keeps the one envelope and one blob it needs. The split
/// is derived — a child's id is `<parent>#<index>` — so it costs nothing to
/// store and is stable across reloads.
///
/// A block with more than one stroke and no [kLooseKey] is a **group**: what
/// the lasso makes when somebody says "these belong together". It is written
/// and read exactly as before, which is what keeps grouping a thing the
/// student decides rather than a consequence of how the file is laid out.
const String kLooseKey = 'loose';

/// Separates a loose stroke's derived id from the block it came out of.
///
/// Not `#`, which the link grammar reserves for the block anchor in
/// `onote://notebook/page#block` (Data Model §5.2), and not `.`, which reads
/// as a file extension wherever an id reaches a filename. A tilde cannot
/// appear in a UUID and means nothing to either, so a derived id is still one
/// unambiguous token everywhere an id travels.
const String kLooseSep = '~';

/// **Working form only: the block revision these strokes were decoded at.**
///
/// Written by [InkStorage.toWorking] and stripped by [InkStorage.toPersisted],
/// so it never reaches a file. It is what lets a save tell handwriting that
/// has been edited from handwriting that has only been looked at: a block's
/// `updatedAt` moves on every change to it, so strokes decoded at one
/// revision and persisted at another have been touched in between.
///
/// Absent means "nobody said", and the answer to that is to re-encode. A
/// wrong re-encode costs an encode nobody needed; a wrong skip loses whatever
/// the person just did.
const String kInkFromKey = 'inkFrom';

abstract final class InkStorage {
  /// Does this block's content hold ink in the persisted (blob-ref) form?
  static bool isRefForm(Map<String, dynamic> content) =>
      content[kInkKey] is Map;

  /// Does it hold ink in the legacy inline-JSON form?
  static bool isLegacyForm(Map<String, dynamic> content) =>
      content[kStrokesKey] is List;

  /// The working stroke list, or an empty one.
  ///
  /// **The canvas's safe door onto `content['strokes']`.** Every reader there
  /// used to cast it unchecked, so a block that was not in working form — a
  /// ref whose blob is missing, a legacy shape, anything a future format adds
  /// — threw during build and took the whole page down as a grey rectangle.
  /// [toWorking] is what normally guarantees the key is there; this is what
  /// makes a page survive the day it does not.
  ///
  /// Mutating the result is safe only when [isLegacyForm] is true; the empty
  /// list handed back otherwise is const.
  static List<dynamic> strokesOf(Map<String, dynamic> content) {
    final s = content[kStrokesKey];
    return s is List ? s : const <dynamic>[];
  }

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
  ///
  /// [rev] is the block's `updatedAt`. Given it, strokes that have not changed
  /// since [toWorking] decoded them are written back as the reference they
  /// came from rather than re-encoded; without it every block is re-encoded,
  /// which is slower and never wrong. See [kInkFromKey].
  static Map<String, dynamic> toPersisted(
    Map<String, dynamic> content,
    String Function(Uint8List bytes) putBlob, {
    int? rev,
  }) {
    if (isRefForm(content)) {
      // **Already a reference — but drop the working strokes on the way out.**
      //
      // [toWorking] puts a decoded `strokes` list beside the `ink` descriptor
      // so every existing consumer keeps seeing what it always saw. Returning
      // that untouched wrote BOTH to disk, which undid the entire point: a
      // converted page grew its geometry back on the very next save, the
      // notebook never actually shrank, and — because the conversion's search
      // looks for `"strokes":[{` while this bails on `isRefForm` — every page
      // stayed a candidate that could never be converted again.
      //
      // Reported exactly that way: "it could not shrink any of the 113 pages —
      // a page matched the search but held no convertable handwriting".
      if (content[kStrokesKey] is! List) return content;
      final from = content[kInkFromKey];
      if (rev != null && from is int && from == rev) {
        return Map<String, dynamic>.of(content)
          ..remove(kStrokesKey)
          ..remove(kInkFromKey);
      }
      // **Touched since it was decoded, so the reference no longer describes
      // it.** Dropping the working strokes here is what lost a move, an erase
      // and a recolour: the rectangle on disk was the new one and the
      // handwriting inside it was the old one, which is the mismatch between a
      // selection box and its contents that issue #20 reported.
      //
      // Re-encoding is not a migration back to the inline shape — the output
      // is a fresh `ink` reference. The old `add`/`gone` go with it because
      // [toWorking] has already applied both, so the live strokes are what
      // those described.
      return _encoded(content, putBlob, over: content[kInkKey]);
    }
    if (content[kStrokesKey] is! List) return content;
    return _encoded(content, putBlob);
  }

  /// Encode `content[kStrokesKey]` into a blob and return the reference form.
  ///
  /// [over] is the reference being replaced, if there was one: a decode that
  /// could not reach its bytes hands back an empty working list (see
  /// [_blank]), and encoding that over a reference to real handwriting would
  /// destroy it. So an empty result never replaces a reference that claims
  /// strokes — the save keeps the reference and loses the edit instead, which
  /// is the smaller of the two losses and the one that is recoverable.
  static Map<String, dynamic> _encoded(
    Map<String, dynamic> content,
    String Function(Uint8List bytes) putBlob, {
    Object? over,
  }) {
    // Keep what is already on disk and write nothing new. For a block that
    // arrived as a reference that is the reference itself; for one that
    // arrived inline it is the inline strokes, which still render and still
    // save, just not smaller.
    Map<String, dynamic> keepWhatIsThere() => over == null
        ? content
        : (Map<String, dynamic>.of(content)
          ..remove(kStrokesKey)
          ..remove(kInkFromKey));

    final strokes = <Stroke>[];
    for (final s in (content[kStrokesKey] as List)) {
      if (s is Map) {
        try {
          strokes.add(Stroke.fromJson(s.cast<String, dynamic>()));
        } catch (_) {
          // A stroke this build cannot parse. Dropping it silently would lose
          // handwriting.
          return keepWhatIsThere();
        }
      }
    }

    if (strokes.isEmpty) {
      if (over is Map && ((over['n'] as num?) ?? 0) > 0) {
        return keepWhatIsThere();
      }
      // An empty ink block has no blob. Writing a zero-stroke object would
      // create a hash every empty block shared, which is harmless but
      // pointless.
      return Map<String, dynamic>.of(content)
        ..remove(kStrokesKey)
        ..remove(kInkFromKey)
        ..[kInkKey] = {
          'v': 1, 'base': '', 'add': const [], 'gone': '', 'n': 0,
          'o': const [0.0, 0.0],
        };
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

    final hash = putBlob(InkCodec.encode(strokes, originX: ox, originY: oy));
    return Map<String, dynamic>.of(content)
      ..remove(kStrokesKey)
      ..remove(kInkFromKey)
      ..[kInkKey] = {
        'v': 1,
        'base': hash,
        'add': const <String>[],
        'gone': '',
        'n': strokes.length,
        'o': [ox, oy],
      };
  }

  /// The working form of [content], reading blobs through [getBlob].
  ///
  /// Returns [content] unchanged when it is already inline, or when the bytes
  /// are not available — a notebook joined from a git remote can legitimately
  /// hold a ref whose blob has not arrived yet, and the right behaviour then is
  /// an ink block that draws nothing rather than a page that fails to open.
  ///
  /// [rev] is the block's `updatedAt`, recorded under [kInkFromKey] so a later
  /// save can tell whether these strokes have been edited since.
  static Map<String, dynamic> toWorking(
    Map<String, dynamic> content,
    Uint8List? Function(String hash) getBlob, {
    int? rev,
  }) {
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
        // **Ref present, bytes absent.** The ref is kept — a save must not
        // overwrite it with an empty stroke list, which is exactly how a
        // half-synced notebook would lose its ink. [toPersisted] guarantees
        // that: content in ref form has its working strokes dropped on the way
        // out and the identical descriptor put back.
        //
        // But it returns an EMPTY WORKING LIST rather than the content
        // untouched, and that difference is the whole of this fix. Untouched
        // meant no `strokes` key at all, and every reader on the canvas does
        // `content['strokes'] as List` — so one unresolvable blob threw a
        // TypeError out of `_strokesOf` during build and took the entire page
        // down with it. In a release build that is an `ErrorWidget`: a plain
        // grey rectangle over the canvas, with no way back in and nothing
        // said. Found on the owner's own demo notebook, whose eight ink blocks
        // all referenced blobs that were no longer on disk.
        //
        // The doc comment above this method already promised the right
        // behaviour — *"an ink block that draws nothing rather than a page
        // that fails to open"* — and the code did the opposite.
        return _blank(content);
      }
      try {
        strokes.addAll(InkCodec.decode(bytes,
            originX: ox,
            originY: oy,
            // Ids derive from the blob so they are stable across decodes.
            idPrefix: base.length > 20 ? base.substring(base.length - 12) : base));
      } catch (_) {
        // Bytes that are there but will not decode: same answer. The block
        // draws nothing, the ref survives, the page opens.
        return _blank(content);
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
    // re-encoding and re-hashing bytes that have not changed. Which of the two
    // happened is what [kInkFromKey] records.
    out[kStrokesKey] = [for (final s in live) s.toJson()];
    if (rev != null) out[kInkFromKey] = rev;
    return out;
  }

  /// The content with an empty working stroke list beside its untouched ref.
  ///
  /// "Draws nothing" has to be said in the working vocabulary, because that is
  /// the only vocabulary the canvas reads. Saying it by omission is what the
  /// grey page was.
  static Map<String, dynamic> _blank(Map<String, dynamic> content) =>
      Map<String, dynamic>.of(content)..[kStrokesKey] = const <dynamic>[];

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

  /// **One block per stroke, out of the one block they were stored in.**
  ///
  /// Null when there is nothing to split: no working strokes at all, which is
  /// what an unresolvable blob looks like. That block passes through whole, so
  /// its reference survives the save that follows — the same guarantee
  /// [toWorking] makes about bytes that have not arrived yet.
  ///
  /// Every child keeps the parent's ink reference and its [kInkFromKey] stamp.
  /// That is what lets a save that changed nothing put the identical
  /// reference back instead of re-encoding: the stamp says which revision
  /// these strokes were decoded at, and [_gatherLoose] hands it on.
  static List<Block>? _split(Block parent, Map<String, dynamic> working) {
    final strokes = working[kStrokesKey];
    if (strokes is! List || strokes.isEmpty) return null;
    final out = <Block>[];
    for (var i = 0; i < strokes.length; i++) {
      final sj = strokes[i];
      if (sj is! Map) continue;
      final j = parent.toJson();
      j['id'] = '${parent.id}$kLooseSep$i';
      j['content'] = {
        for (final e in working.entries)
          if (e.key != kStrokesKey) e.key: e.value,
        kStrokesKey: [sj],
      };
      final b = Block.fromJson(j);
      _refit(b);
      out.add(b);
    }
    return out.isEmpty ? null : out;
  }

  /// **The inverse: loose strokes back into the block they belong to.**
  ///
  /// Grouped by where they came from, which their ids already say: a stroke
  /// split out of block P is `P#i`, and one drawn in this session has a UUID
  /// and joins the block named after the first of them. So a page ends up with
  /// one loose block per source rather than one per stroke, two devices
  /// writing on the same page never name the same block (their UUIDs differ),
  /// and nothing has to be stored to make either true.
  ///
  /// Each group lands where its first member was, so ink keeps its order
  /// relative to everything else on the page — and relative to itself, which
  /// is the order overlapping strokes are painted in.
  static List<Block> _gatherLoose(List<Block> blocks) {
    // A candidate is an ink block holding exactly one stroke. Anything with
    // more is a group; anything with none is a reference whose bytes have not
    // arrived, and both pass through untouched.
    bool loose(Block b) =>
        b.type == BlockType.ink &&
        (b.content[kStrokesKey] is List) &&
        (b.content[kStrokesKey] as List).length == 1;

    if (blocks.where(loose).length < 2) return blocks;

    final groups = <String, List<Block>>{};
    final order = <String>[];
    for (final b in blocks) {
      if (!loose(b)) continue;
      final at = b.id.indexOf(kLooseSep);
      final key = at > 0 ? b.id.substring(0, at) : '';
      (groups[key] ??= <Block>[]).add(b);
      if (!order.contains(key)) order.add(key);
    }
    // A single stroke on its own is not worth a block of its own, but it is
    // not worth rewriting either: leave a group of one exactly as it is.
    groups.removeWhere((_, v) => v.length < 2);
    if (groups.isEmpty) return blocks;

    final out = <Block>[];
    final done = <String>{};
    for (final b in blocks) {
      if (loose(b)) {
        final at = b.id.indexOf(kLooseSep);
        final key = at > 0 ? b.id.substring(0, at) : '';
        final group = groups[key];
        if (group != null) {
          if (done.add(key)) out.add(_merge(key.isEmpty ? group.first.id : key, group));
          continue;
        }
      }
      out.add(b);
    }
    return out;
  }

  /// One block holding [parts]' strokes, in [parts]' order.
  static Block _merge(String id, List<Block> parts) {
    final first = parts.first;
    final strokes = <dynamic>[
      for (final p in parts) (p.content[kStrokesKey] as List).first
    ];
    // **The revision the merged block is claimed to be at**, which decides
    // whether the strokes are re-encoded or the old reference goes back.
    //
    // Null — "nobody said", which [toPersisted] answers by re-encoding —
    // unless every part is still at the revision it was decoded at AND there
    // are as many of them as the reference says. The count is half of it: a
    // stroke rubbed out leaves the others untouched, so without it an erase
    // would put the old reference back and the stroke would return from the
    // dead on the next page load.
    final from = first.content[kInkFromKey];
    final ref = first.content[kInkKey];
    final n = (ref is Map) ? (ref['n'] as num?)?.toInt() : null;
    final unchanged = from is int &&
        n == parts.length &&
        parts.every((p) =>
            p.updatedAt == from && p.content[kInkFromKey] == from);

    final j = first.toJson();
    j['id'] = id;
    j['updatedAt'] = unchanged
        ? from
        : parts.map((p) => p.updatedAt).reduce((a, b) => a > b ? a : b);
    j['content'] = {
      for (final e in first.content.entries)
        if (e.key != kStrokesKey && e.key != kInkFromKey) e.key: e.value,
      if (unchanged) kInkFromKey: from,
      kLooseKey: true,
      kStrokesKey: strokes,
    };
    final b = Block.fromJson(j);
    _refit(b);
    return b;
  }

  /// A block's rectangle, from the strokes in it.
  ///
  /// Derived on both sides of the boundary rather than stored, which is what
  /// makes splitting and merging lossless: `x`/`y`/`w`/`h` are the bounds of
  /// whatever strokes the block holds, so neither direction has to carry a
  /// geometry that would then disagree with its contents.
  static void _refit(Block b) {
    final strokes = b.content[kStrokesKey];
    if (strokes is! List || strokes.isEmpty) return;
    var mnx = double.infinity, mny = double.infinity;
    var mxx = -double.infinity, mxy = -double.infinity;
    for (final sj in strokes) {
      if (sj is! Map) continue;
      final bb = Stroke.fromJson(sj.cast<String, dynamic>()).bounds();
      if (bb.minX < mnx) mnx = bb.minX;
      if (bb.minY < mny) mny = bb.minY;
      if (bb.maxX > mxx) mxx = bb.maxX;
      if (bb.maxY > mxy) mxy = bb.maxY;
    }
    if (!mnx.isFinite || !mxx.isFinite) return;
    b
      ..x = mnx
      ..y = mny
      ..w = mxx - mnx
      ..h = mxy - mny;
  }

  /// Persist every ink block of [blocks]. Returns fresh [Block]s; the input is
  /// not mutated, because the caller's list is the live editor state.
  ///
  /// Loose strokes are gathered first — see [kLooseKey] — so what reaches
  /// disk is one block per group and one block per source of loose strokes,
  /// not one per stroke.
  static List<Block> persistAll(
      List<Block> blocks, String Function(Uint8List) putBlob) {
    final gathered = _gatherLoose(blocks);
    var touched = !identical(gathered, blocks);
    final out = <Block>[];
    for (final b in gathered) {
      if (b.type != BlockType.ink) {
        out.add(b);
        continue;
      }
      final next = toPersisted(b.content, putBlob, rev: b.updatedAt);
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

  /// The inverse, for a page just read from disk. A loose block comes back as
  /// one block per stroke — see [kLooseKey].
  static List<Block> workingAll(
      List<Block> blocks, Uint8List? Function(String) getBlob) {
    var touched = false;
    final out = <Block>[];
    for (final b in blocks) {
      if (b.type != BlockType.ink) {
        out.add(b);
        continue;
      }
      final next = toWorking(b.content, getBlob, rev: b.updatedAt);
      if (b.content[kLooseKey] == true) {
        final split = _split(b, next);
        if (split != null) {
          touched = true;
          out.addAll(split);
          continue;
        }
      }
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
