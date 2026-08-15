/// Simplified version history (v0.17 plan, Step 8a): who changed what you can
/// see, and the last ten notable deletions.
///
/// **Nothing here is stored in a log, and nothing here is synced.** Every
/// answer is a fold of ops the app already writes: [Op] stamps `dev` and `ts`
/// on every record, [Op.compare] gives a deterministic total order across
/// devices, and each op names its target (`block.set` carries the block, with
/// its id, inside `{pageId, block}`; `ink.strokes` carries `{pageId, blockId}`;
/// `block.remove` carries `{pageId, blockId}`; `node.delete`/`node.purge`
/// carry the node id). So *"who last changed this block"* is simply **the last
/// op in total order that names that block** — no new op kind, not one new byte
/// in any log, envelope `v` unchanged.
///
/// The result is **one entry per block that currently exists**, which is the
/// whole difference from the `page_versions` table this replaces: that one is
/// bounded by how long a notebook has been edited, i.e. by nothing, and this
/// one is bounded by how big the notebook is.
///
/// **This file is pure.** No clock, no filesystem, no SQLite — the same ops in
/// must give the same index out, on every device, or the "rebuilt from the log
/// equals maintained on save" check that guards this design would be measuring
/// the machine instead of the code.
library;

import '../sync/op.dart';

/// A block whose last content is this many characters or more counts as a
/// notable deletion on its own.
///
/// **A knob, and the plan is honest that it is one:** no `block.remove` count
/// has ever been taken on the owner's real logs, so 280 is a paragraph-sized
/// bar chosen to be argued with, not a measurement. Below it, deleting text is
/// editing, and editing's remedy is undo — which keeps a hundred page
/// snapshots and is untouched by any of this.
const int kNotableTextChars = 280;

/// How many notable deletions are remembered. **The cap is the prune** — ten
/// rows cannot leak, so there is no retention sweep to get wrong (which is
/// exactly what commit `1be2d28` had to repair for `page_versions`).
const int kRecentDeletionsKept = 10;

/// Block types that hold or name something that cannot be retyped.
///
/// A paragraph can be rewritten from memory; a lecture recording cannot. So
/// these are notable when removed **regardless of size**, and a short caption
/// is not.
const Set<String> kUnretypableBlockKinds = {
  'image',
  'file',
  'video',
  'pdf',
  'embed',
  'ink',
  'code',
};

/// Inline images live in markdown, not in a `blob` key: `![alt](sha256:…)`.
/// Same expression as `NotebookWriter._inlineImgRe`, which builds `blob_refs`
/// from the identical text — the two must agree about what a page reaches or
/// the ten-deep list would fail to pin a picture the page really used.
final RegExp _inlineImageRe =
    RegExp(r'!\[[^\]]*\]\(sha256:([0-9a-fA-F]{64})(?:\s+=\d+x\d+)?\)');

/// Who last changed one block, and just enough about it to classify its
/// removal later.
///
/// The digest fields ([blockKind], [chars], [pins]) are **not** decoration.
/// Without them a `block.remove` arriving in a later session — after the app
/// has restarted and the in-memory fold is gone — cannot be told from any
/// other, so a deleted lecture recording would be filed as an ordinary edit.
/// See the note in `docs` reporting for why the plan's sketched schema is one
/// column short of workable.
class BlockAuthor {
  const BlockAuthor({
    required this.pageId,
    required this.blockId,
    required this.device,
    required this.lamport,
    required this.seq,
    required this.changedAt,
    required this.blockKind,
    required this.chars,
    required this.pins,
  });

  final String pageId;
  final String blockId;

  /// The device that wrote the last op naming this block.
  final String device;

  final int lamport;
  final int seq;

  /// Wall clock of that op. Informative only — [Op.timestamp]'s own doc comment
  /// says so, and nothing here orders by it.
  final int changedAt;

  /// The block's `type` string, verbatim (so a type this build does not know
  /// is still classified by whatever it names rather than being coerced).
  final String blockKind;

  /// Characters of text-shaped content.
  final int chars;

  /// Content-addressed hashes and stored media names this block reaches. The
  /// ten-deep deletion list is a garbage-collection root, and this is what it
  /// roots.
  final List<String> pins;

  /// Whether removing this block is worth remembering.
  bool get notableIfRemoved =>
      pins.isNotEmpty || kUnretypableBlockKinds.contains(blockKind) ||
      chars >= kNotableTextChars;

  /// A word a student would use for this, for the deletions list. Never a type
  /// name from the file format.
  String get friendlyKind => switch (blockKind) {
        'image' => 'Picture',
        'ink' => 'Drawing',
        'file' => 'File',
        'video' => 'Video',
        'pdf' => 'PDF',
        'embed' => 'Linked page',
        'code' => 'Code',
        'table' => 'Table',
        'math' => 'Maths',
        'flashcard' => 'Flashcard',
        'board' => 'Board',
        _ => chars >= kNotableTextChars ? 'Writing' : 'Note',
      };
}

/// What kind of thing a remembered deletion was.
enum DeletionKind { page, section, sectionGroup, block }

/// One entry in the ten-deep list.
///
/// **Deliberately not keyed on `nodes`.** A purged page has no `nodes` row, and
/// that is precisely the entry a student most needs; a foreign key here would
/// delete exactly the wrong rows.
class NotableDeletion {
  const NotableDeletion({
    required this.kind,
    required this.targetId,
    required this.pageId,
    required this.what,
    required this.device,
    required this.lamport,
    required this.seq,
    required this.deletedAt,
    required this.pins,
  });

  final DeletionKind kind;

  /// Node id, or block id.
  final String targetId;

  /// The page a removed block was on. Null for a node deletion.
  final String? pageId;

  /// The plain-words name of the thing: a page or section title, or a word
  /// like *Picture*. Never an id.
  final String what;

  final String device;
  final int lamport;
  final int seq;
  final int deletedAt;

  /// Every stored name this deletion keeps alive. Blob GC declines to free a
  /// hash named here — a bounded, explicit, ten-deep root, where
  /// `page_versions` pinned blobs by accident and for ever.
  final List<String> pins;

  /// The row's identity for the flush: the op that caused it.
  String get opKey => '$device#$seq';

  /// Whether this is a whole page/section rather than one block on a page.
  bool get isNode => kind != DeletionKind.block;
}

/// A node as far as this index needs to know it: enough to name a deleted
/// section in plain words and to collapse a subtree into ONE entry.
class HistoryNode {
  HistoryNode(this.id);
  final String id;
  String kind = 'page';
  String? parentId;
  String title = '';
}

/// The derived index: attribution for every live block, plus the ten-deep
/// deletion list.
///
/// Fold ops into it with [apply]. It is the same class whether the ops come
/// from a full log replay or from the tail appended by one save — and that
/// equality is the entire premise of Step 8a, so it is asserted by a test
/// rather than argued (see `simplified_history_test.dart`).
class NotebookHistory {
  /// Ops folded by every instance since the process started, and rows written
  /// by every flush.
  ///
  /// **These are the "attribution is free" measurement.** The claim is one
  /// upsert per op the save was already writing — linear in what changed, not
  /// in how long the notebook has been edited. A test that edits one block 500
  /// times reads both counters; if maintenance ever became a re-scan, the
  /// op counter would go quadratic and say so.
  static int debugOpsFolded = 0;
  static int debugRowWrites = 0;

  final Map<String, BlockAuthor> _authors = {};
  final Map<String, HistoryNode> _nodes = {};
  final List<NotableDeletion> _deletions = [];
  final Set<String> _deletedNodes = {};

  // Since the last flush.
  final Map<String, BlockAuthor> _pendingUpserts = {};
  final Map<String, BlockAuthor> _pendingDeletes = {};
  bool _deletionsChanged = false;

  static String keyFor(String pageId, String blockId) =>
      '$pageId $blockId';

  /// Attribution for every block that currently exists, keyed by [keyFor].
  Map<String, BlockAuthor> get authors => Map.unmodifiable(_authors);

  /// Who last changed [blockId] on [pageId], or null when it was never
  /// recorded. **Null renders as "not recorded", never as a wrong name.**
  BlockAuthor? authorOf(String pageId, String blockId) =>
      _authors[keyFor(pageId, blockId)];

  /// The remembered deletions, newest first.
  List<NotableDeletion> get deletions => List.unmodifiable(_deletions);

  bool get hasPendingWrites =>
      _pendingUpserts.isNotEmpty ||
      _pendingDeletes.isNotEmpty ||
      _deletionsChanged;

  /// Every stored name the deletion list is holding alive — the GC root set.
  Set<String> get pinnedNames => {for (final d in _deletions) ...d.pins};

  // ── Loading a persisted index back ───────────────────────────────────

  /// Install rows read from the container, without marking them dirty.
  void seed({
    required Iterable<BlockAuthor> authors,
    required Iterable<NotableDeletion> deletions,
    required Iterable<HistoryNode> nodes,
  }) {
    for (final a in authors) {
      _authors[keyFor(a.pageId, a.blockId)] = a;
    }
    _deletions
      ..addAll(deletions)
      ..sort(_newestFirst);
    for (final n in nodes) {
      _nodes[n.id] = n;
    }
  }

  /// Take what the next flush must write, and forget it.
  ({List<BlockAuthor> upserts, List<BlockAuthor> deletes, bool deletions})
      takePending() {
    final r = (
      upserts: _pendingUpserts.values.toList(),
      deletes: _pendingDeletes.values.toList(),
      deletions: _deletionsChanged,
    );
    _pendingUpserts.clear();
    _pendingDeletes.clear();
    _deletionsChanged = false;
    return r;
  }

  // ── The fold ─────────────────────────────────────────────────────────

  void applyAll(Iterable<Op> ops) {
    for (final op in ops) {
      apply(op);
    }
  }

  void apply(Op op) {
    debugOpsFolded++;
    // An op this build cannot read must not be attributed to anybody: its
    // payload may not even be a map. Same gate, and the same reasoning, as
    // `Materializer.apply`.
    if (op.version > opFormatVersion || op.encryption != 'none') return;
    final d = op.map;
    switch (op.kind) {
      case OpKind.blockSet:
        final pid = d['pageId'] as String?;
        final b = d['block'];
        if (pid == null || b is! Map) return;
        final bid = b['id'] as String?;
        if (bid == null) return;
        _record(op, _digest(op, pid, bid, b.cast<String, dynamic>()));

      case OpKind.inkStrokes:
        // A per-stroke edit changes who last touched the block and nothing
        // else this index knows. **It is never a deletion, however large its
        // `del` list is** — an eraser gesture is an edit, and one cleanup
        // session would fill all ten slots by itself, which is the
        // "every keystroke" failure the owner ruled out.
        final pid = d['pageId'] as String?;
        final bid = d['blockId'] as String?;
        if (pid == null || bid == null) return;
        final prev = _authors[keyFor(pid, bid)];
        if (prev == null) return; // a stroke edit to a block we never saw set
        _record(
            op,
            BlockAuthor(
              pageId: pid,
              blockId: bid,
              device: op.device,
              lamport: op.lamport,
              seq: op.seq,
              changedAt: op.timestamp,
              blockKind: prev.blockKind,
              chars: prev.chars,
              pins: prev.pins,
            ));

      case OpKind.blockRemove:
        final pid = d['pageId'] as String?;
        final bid = d['blockId'] as String?;
        if (pid == null || bid == null) return;
        final gone = _authors.remove(keyFor(pid, bid));
        if (gone != null) {
          _pendingUpserts.remove(keyFor(pid, bid));
          _pendingDeletes[keyFor(pid, bid)] = gone;
        }
        // **Wrong-by-omission is the safe direction.** With no row for the
        // block we cannot tell a deleted recording from a deleted comma, and
        // guessing "notable" would let ordinary editing evict the real
        // deletions from a ten-deep list.
        if (gone == null || !gone.notableIfRemoved) return;
        _remember(NotableDeletion(
          kind: DeletionKind.block,
          targetId: bid,
          pageId: pid,
          what: gone.friendlyKind,
          device: op.device,
          lamport: op.lamport,
          seq: op.seq,
          deletedAt: op.timestamp,
          pins: gone.pins,
        ));

      case OpKind.nodeUpsert:
        final id = d['id'] as String?;
        if (id == null) return;
        final n = _nodes.putIfAbsent(id, () => HistoryNode(id));
        n.kind = d['kind'] as String? ?? n.kind;
        n.parentId =
            d.containsKey('parentId') ? d['parentId'] as String? : n.parentId;
        n.title = d['title'] as String? ?? n.title;

      case OpKind.nodeRestore:
        final id = d['id'] as String?;
        if (id == null) return;
        _deletedNodes.remove(id);
        // The entry goes with it: a page you have put back is not a deletion
        // you might want back, and leaving it there would keep a blob pinned
        // by a root that no longer means anything.
        _forget(id);

      case OpKind.nodeDelete:
      case OpKind.nodePurge:
        final id = d['id'] as String?;
        if (id == null) return;
        _deleteNode(op, id, purge: op.kind == OpKind.nodePurge);

      case OpKind.pageProps:
      case OpKind.blobPut:
      case OpKind.notebookMeta:
      case OpKind.unknown:
        break;
    }
  }

  // ── Internals ────────────────────────────────────────────────────────

  BlockAuthor _digest(
      Op op, String pageId, String blockId, Map<String, dynamic> block) {
    final content = (block['content'] as Map?)?.cast<String, dynamic>() ?? {};
    final text = content['text'] ?? content['md'];
    final pins = <String>[];
    // The same four paths `NotebookWriter.writePage` walks to build
    // `blob_refs`, plus `media` — a video is a file beside the notebook rather
    // than a blob inside it, and it is the largest single thing Openote stores.
    for (final key in const ['blob', 'pdf']) {
      final h = content[key];
      if (h is String && h.isNotEmpty) pins.add(h.replaceFirst('sha256:', ''));
    }
    final ink = content['ink'];
    if (ink is Map) {
      final base = ink['base'];
      if (base is String && base.isNotEmpty) {
        pins.add(base.replaceFirst('sha256:', ''));
      }
      for (final a in (ink['add'] as List? ?? const [])) {
        if (a is String && a.isNotEmpty) pins.add(a.replaceFirst('sha256:', ''));
      }
    }
    final media = content['media'];
    if (media is String && media.isNotEmpty) pins.add(media);
    if (text is String && text.contains('](sha256:')) {
      for (final m in _inlineImageRe.allMatches(text)) {
        pins.add(m.group(1)!.toLowerCase());
      }
    }
    return BlockAuthor(
      pageId: pageId,
      blockId: blockId,
      device: op.device,
      lamport: op.lamport,
      seq: op.seq,
      changedAt: op.timestamp,
      blockKind: block['type'] as String? ?? 'unknown',
      chars: text is String ? text.length : 0,
      pins: List.unmodifiable(pins),
    );
  }

  /// Install [next] only when its op really is the latest one naming that
  /// block **in total order**.
  ///
  /// This is not belt and braces. Ops arrive in whatever order logs turn up in
  /// — a foreign log synced hours late can carry a LOWER Lamport than one this
  /// device wrote a minute ago — so last-applied-wins and last-in-total-order
  /// -wins are different answers. Only the second matches a rebuild from the
  /// log, which is the property Step 8a stands on.
  void _record(Op op, BlockAuthor next) {
    final key = keyFor(next.pageId, next.blockId);
    final prev = _authors[key];
    if (prev != null && !_isAfter(op, prev)) return;
    _authors[key] = next;
    _pendingDeletes.remove(key);
    _pendingUpserts[key] = next;
  }

  static bool _isAfter(Op op, BlockAuthor prev) {
    // [Op.compare]'s order, spelled against a stored row: Lamport, then device
    // id, then seq.
    if (op.lamport != prev.lamport) return op.lamport > prev.lamport;
    final d = op.device.compareTo(prev.device);
    if (d != 0) return d > 0;
    return op.seq > prev.seq;
  }

  void _deleteNode(Op op, String id, {required bool purge}) {
    final node = _nodes[id];
    // **One entry for the whole subtree.** Deleting a section that holds eight
    // pages must not fill all ten slots and push out everything else, so a
    // node under an already-deleted ancestor is silently absorbed.
    if (_hasDeletedAncestor(node)) {
      _deletedNodes.add(id);
      return;
    }
    _deletedNodes.add(id);
    final pages = _pagesUnder(id);
    final pins = <String>[];
    for (final a in _authors.values) {
      if (pages.contains(a.pageId)) pins.addAll(a.pins);
    }
    if (purge) {
      // A purge takes the `nodes` row, and `block_authors` cascades with it —
      // the foreign key `page_versions` never declared, which is the whole of
      // commit `1be2d28`. Mirror that in memory so the two never disagree.
      for (final key in _authors.keys.toList()) {
        final a = _authors[key]!;
        if (pages.contains(a.pageId)) {
          _authors.remove(key);
          _pendingUpserts.remove(key);
          _pendingDeletes[key] = a;
        }
      }
      _nodes.remove(id);
    }
    final kind = switch (node?.kind) {
      'section' => DeletionKind.section,
      'section_group' || 'sectionGroup' => DeletionKind.sectionGroup,
      _ => DeletionKind.page,
    };
    final title = (node?.title ?? '').trim();
    _remember(NotableDeletion(
      kind: kind,
      targetId: id,
      pageId: null,
      what: title.isEmpty ? 'Untitled' : title,
      device: op.device,
      lamport: op.lamport,
      seq: op.seq,
      deletedAt: op.timestamp,
      pins: List.unmodifiable(pins),
    ));
  }

  bool _hasDeletedAncestor(HistoryNode? node) {
    var parent = node?.parentId;
    // Bounded by tree depth, and guarded anyway: a log that has been merged
    // from two devices can in principle describe a cycle, and an unguarded
    // walk would hang the save path rather than mis-classify one deletion.
    for (var hops = 0; parent != null && hops < 64; hops++) {
      if (_deletedNodes.contains(parent)) return true;
      parent = _nodes[parent]?.parentId;
    }
    return false;
  }

  Set<String> _pagesUnder(String id) {
    final out = {id};
    var grew = true;
    while (grew) {
      grew = false;
      for (final n in _nodes.values) {
        final p = n.parentId;
        if (p != null && out.contains(p) && out.add(n.id)) grew = true;
      }
    }
    return out;
  }

  /// Add [d], replacing any earlier entry for the same thing, and keep the ten
  /// newest.
  ///
  /// Replacing matters: a page is soft-deleted and then purged thirty days
  /// later, which is two ops about one page. Two entries would spend two of
  /// the ten slots saying the same thing.
  void _remember(NotableDeletion d) {
    _deletions
      ..removeWhere((e) => e.targetId == d.targetId && e.pageId == d.pageId)
      ..add(d)
      ..sort(_newestFirst);
    if (_deletions.length > kRecentDeletionsKept) {
      _deletions.removeRange(kRecentDeletionsKept, _deletions.length);
    }
    _deletionsChanged = true;
  }

  /// Drop the entry for [targetId] — it has been put back, so it is no longer
  /// something the student might want back, and its blobs stop being pinned by
  /// a root that no longer means anything.
  void forget(String targetId) => _forget(targetId);

  void _forget(String targetId) {
    final before = _deletions.length;
    _deletions.removeWhere((e) => e.targetId == targetId);
    if (_deletions.length != before) _deletionsChanged = true;
  }

  static int _newestFirst(NotableDeletion a, NotableDeletion b) {
    if (a.lamport != b.lamport) return b.lamport.compareTo(a.lamport);
    final d = b.device.compareTo(a.device);
    if (d != 0) return d;
    return b.seq.compareTo(a.seq);
  }
}

/// What the interface calls a device.
///
/// **Never a raw device id.** Attribution that says *"last changed by
/// 019fdff4-8c31-7a2e-…"* is worse than no attribution: it is jargon, it is
/// unreadable, and it is the thing a student would screenshot to ask what went
/// wrong. When the notebook's manifest has no name for a device, the line reads
/// *"another computer"*, which is true and is not jargon.
String deviceDisplayName(String? label, {bool isThisComputer = false}) {
  final l = label?.trim();
  if (l != null && l.isNotEmpty) return l;
  return isThisComputer ? 'this computer' : 'another computer';
}
