/// Replay an ordered op stream into notebook state (ADR-0006 §3).
///
/// "Merging is then *reading*: concatenate the logs, order the operations,
/// apply." This is that apply step. It must be a **pure function of the ordered
/// op list** — same ops in, same state out, on every device, regardless of the
/// order the logs arrived in. Anything that reads the clock, the filesystem or
/// random state here would break convergence in a way that is very hard to
/// observe.
library;

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

  void applyAll(Iterable<Op> ops) {
    for (final op in ops) {
      apply(op);
    }
  }

  void apply(Op op) {
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
        n.kind = d['kind'] as String? ?? n.kind;
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
