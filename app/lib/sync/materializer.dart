/// Replay an ordered op stream into notebook state (ADR-0006 §3).
///
/// "Merging is then *reading*: concatenate the logs, order the operations,
/// apply." This is that apply step. It must be a **pure function of the ordered
/// op list** — same ops in, same state out, on every device, regardless of the
/// order the logs arrived in. Anything that reads the clock, the filesystem or
/// random state here would break convergence in a way that is very hard to
/// observe.
library;

import '../model/models.dart' show nodeKindFromWire;
import 'op.dart';

/// A node as reconstructed from the log.
class MatNode {
  MatNode(this.id);
  final String id;
  String kind = 'page';
  String? parentId;
  String title = '';
  String position = 'a0';
  String? color;
  int level = 0;
  int createdAt = 0;
  int updatedAt = 0;

  /// Set by `node.delete`, cleared **only** by `node.restore`.
  int? deletedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'parentId': parentId,
        'title': title,
        'position': position,
        'color': color,
        'level': level,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'deletedAt': deletedAt,
      };
}

/// A page's content as reconstructed from the log.
class MatPage {
  final Map<String, Map<String, dynamic>> blocks = {};
  Map<String, dynamic> props = {};
}

/// Notebook state rebuilt from ops.
class Materializer {
  final Map<String, MatNode> nodes = {};
  final Map<String, MatPage> pages = {};
  final Set<String> blobs = {};
  Map<String, dynamic> meta = {};

  /// Ops this build could not apply because they were written by a newer
  /// version. Retained rather than ignored so the caller can tell "the log
  /// replayed completely" from "the log replayed as far as I understand it" —
  /// a distinction that matters enormously for the rebuild-equals-container
  /// check, which would otherwise report a spurious mismatch as data loss.
  final List<Op> skipped = [];

  /// The subset of [skipped] this build must not merely ignore: ops whose
  /// **envelope** — not their kind — is beyond it.
  ///
  /// An unknown op *kind* is designed to be skippable ([OpKind.unknown]): a v1
  /// device replaying a newer device's log skips what it cannot apply and
  /// keeps everything it can. An unknown envelope is the opposite. `v: 2` means
  /// the record itself is laid out differently, and `enc` means the payload is
  /// ciphertext — in both cases this build cannot even tell what the op
  /// touched, so anything it writes afterwards is written on top of a history
  /// it has only half read. Callers use a non-empty list here to put the
  /// notebook read-only.
  final List<Op> unsupported = [];

  void applyAll(Iterable<Op> ops) {
    for (final op in ops) {
      apply(op);
    }
  }

  void apply(Op op) {
    // **THE ENVELOPE GATE.** `Op.decode` has always read `v` and `enc` into
    // [Op.version] and [Op.encryption], and nothing ever compared either of
    // them to what this build can actually apply. Measured before this line
    // existed: a hand-written `{"v":2,…,"op":"block.set"}` carrying the
    // structured `{nodes:[…]}` model ADR-0006 §4 plans **was applied as if it
    // were a v1 payload, with `skipped=0`** — a v1 device adopting a v2 record
    // and then reporting the notebook as verified. An `{"enc":"aes-gcm"}` op
    // decoded to an empty map and was dropped, also with `skipped=0`, so
    // `SyncRecorder.verifyPage`'s "inconclusive rather than incomplete" escape
    // hatch never fired and a real divergence would have been reported to the
    // user as data loss. The container has had this gate since it existed
    // (`database.dart` throws on `user_version > 1`); the log had none
    // (v0.17 plan, Step 3).
    //
    // Strictly `>`: a v1 op is the entire population of every log on disk
    // today and must go straight through.
    if (op.version > opFormatVersion || op.encryption != 'none') {
      unsupported.add(op);
      skipped.add(op);
      return;
    }
    final d = op.map;
    switch (op.kind) {
      case OpKind.nodeUpsert:
        final id = d['id'] as String?;
        if (id == null) return;
        final n = nodes.putIfAbsent(id, () => MatNode(id));
        // NOTE: `deletedAt` is deliberately NOT touched here. This single
        // omission is what implements delete-wins (ADR-0006 §6a.3): an edit
        // that raced a delete cannot resurrect the node, no matter which one
        // sorts later. Only an explicit restore brings it back.
        // **An unrecognised kind is recorded, not coerced.** The string is kept
        // verbatim — a re-serialised node still says what the writer said — and
        // the op is reported as skipped so nothing downstream writes it out as
        // something else. The fold in `AppState._syncPullLocked` used to map
        // any unknown word to `NodeKind.page`, which is how `sectionGroup`
        // turned six section groups per notebook into pages, and a page carries
        // a `page_mirror` foreign key and a `level` that a section group has no
        // business having (v0.17 plan, Step 3).
        final wireKind = d['kind'] as String?;
        if (wireKind != null && nodeKindFromWire(wireKind) == null) {
          skipped.add(op);
        }
        n.kind = wireKind ?? n.kind;
        n.parentId = d.containsKey('parentId') ? d['parentId'] as String? : n.parentId;
        n.title = d['title'] as String? ?? n.title;
        n.position = d['position'] as String? ?? n.position;
        n.color = d.containsKey('color') ? d['color'] as String? : n.color;
        n.level = (d['level'] as num?)?.toInt() ?? n.level;
        n.createdAt = (d['createdAt'] as num?)?.toInt() ?? n.createdAt;
        n.updatedAt = (d['updatedAt'] as num?)?.toInt() ?? n.updatedAt;

      case OpKind.nodeDelete:
        final id = d['id'] as String?;
        if (id == null) return;
        final n = nodes.putIfAbsent(id, () => MatNode(id));
        n.deletedAt = (d['deletedAt'] as num?)?.toInt() ?? op.timestamp;

      case OpKind.nodeRestore:
        final id = d['id'] as String?;
        nodes[id]?.deletedAt = null;

      case OpKind.nodePurge:
        final id = d['id'] as String?;
        if (id == null) return;
        nodes.remove(id);
        pages.remove(id);

      case OpKind.blockSet:
        final pid = d['pageId'] as String?;
        final b = d['block'];
        if (pid == null || b is! Map) return;
        final bid = b['id'] as String?;
        if (bid == null) return;
        pages.putIfAbsent(pid, MatPage.new).blocks[bid] =
            b.cast<String, dynamic>();

      case OpKind.inkStrokes:
        final pid = d['pageId'] as String?;
        final bid = d['blockId'] as String?;
        if (pid == null || bid == null) return;
        final block = pages[pid]?.blocks[bid];
        // Absent page or block → drop the op. Either a concurrent
        // `block.remove` ordered earlier (and resurrecting it would break
        // delete-wins), or an op from a device that never saw the creation.
        if (block == null) return;
        // Rebuild with fresh untyped maps rather than writing through `cast`
        // views — a view is backed by the ORIGINAL map, and if that map arrived
        // with a narrower inferred type (a decoded op, a test literal), the
        // write-back throws a cast error at runtime.
        final content = <String, dynamic>{
          ...?(block['content'] as Map?)?.cast<String, dynamic>()
        };
        final strokes = [...((content['strokes'] as List?) ?? const [])];
        final del = ((d['del'] as List?) ?? const []).cast<String>().toSet();
        final puts = ((d['put'] as List?) ?? const [])
            .whereType<Map>()
            .map((p) => p.cast<String, dynamic>())
            .toList();
        // Upsert semantics: a put replaces the stroke wherever it was, so
        // remove both deleted ids and re-put ids first…
        final putIds = {
          for (final p in puts)
            if (p['s'] is Map) (p['s'] as Map)['id']
        };
        strokes.removeWhere((s) =>
            s is Map && (del.contains(s['id']) || putIds.contains(s['id'])));
        // …then insert at the recorded positions, ascending. This reproduces
        // the after-list exactly as long as unchanged strokes kept their
        // relative order — which every current editor operation does, and the
        // shadow verification would expose if one stopped doing.
        puts.sort((a, b) =>
            ((a['i'] as num?) ?? 0).compareTo(((b['i'] as num?) ?? 0)));
        for (final p in puts) {
          final i = ((p['i'] as num?)?.toInt() ?? strokes.length)
              .clamp(0, strokes.length);
          strokes.insert(i, p['s']);
        }
        content['strokes'] = strokes;
        final updated = <String, dynamic>{...block, 'content': content};
        final rect = (d['rect'] as Map?)?.cast<String, dynamic>();
        if (rect != null) {
          for (final k in const ['x', 'y', 'w', 'h']) {
            if (rect[k] != null) updated[k] = rect[k];
          }
        }
        if (d['updatedAt'] != null) updated['updatedAt'] = d['updatedAt'];
        pages[pid]!.blocks[bid] = updated;

      case OpKind.blockRemove:
        final pid = d['pageId'] as String?;
        final bid = d['blockId'] as String?;
        if (pid == null || bid == null) return;
        // Blocks are last-writer-wins by total order, NOT tombstoned. Removing
        // a block is an ordinary edit within a page, and tombstoning would
        // break undo — which legitimately re-adds a block under its own id.
        pages[pid]?.blocks.remove(bid);

      case OpKind.pageProps:
        final pid = d['pageId'] as String?;
        final props = d['props'];
        if (pid == null || props is! Map) return;
        pages.putIfAbsent(pid, MatPage.new).props = props.cast<String, dynamic>();

      case OpKind.blobPut:
        final h = d['hash'] as String?;
        if (h != null) blobs.add(h);

      case OpKind.notebookMeta:
        meta = {...meta, ...d};

      case OpKind.unknown:
        skipped.add(op);
    }
  }

  /// The page mirror JSON this page would have, in the same shape
  /// `Repository.writePage` persists — so the two can be compared directly.
  ///
  /// Blocks are emitted **sorted by id**, not in insertion order. The container
  /// stores whatever order the app's list happened to be in, which carries no
  /// meaning (render order is the `z` field), so comparing insertion order
  /// would produce differences that are not differences.
  Map<String, dynamic> pageMirror(String pageId) {
    final page = pages[pageId];
    final ids = (page?.blocks.keys.toList() ?? <String>[])..sort();
    return {
      'schema': 'onote-page/1',
      'pageId': pageId,
      'page': page?.props ?? {},
      'blocks': [for (final id in ids) page!.blocks[id]],
    };
  }

  /// Live (non-deleted) nodes, ordered as the navigator orders them.
  List<MatNode> liveNodes() {
    final live = nodes.values.where((n) => n.deletedAt == null).toList();
    live.sort((a, b) {
      final p = a.position.compareTo(b.position);
      return p != 0 ? p : a.id.compareTo(b.id);
    });
    return live;
  }
}
