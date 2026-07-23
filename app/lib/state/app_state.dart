import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../canvas/canvas_controller.dart';
import '../core/engine.dart';
import '../core/ids.dart';
import '../model/models.dart';
import '../store/repository.dart';

enum Tool { select, text, pen, highlighter, eraser }

/// App-wide state. Deliberately simple (ChangeNotifier) for the MVP; the
/// domain layer beneath it is what carries forward.
class AppState extends ChangeNotifier {
  AppState(this.repo) : engine = MirrorEngine(repo);

  final Repository repo;
  final DocumentEngine engine;

  /// Shared so toolbar/shortcuts can drive zoom (style guide §8.2).
  final canvas = CanvasController();

  /// RepaintBoundary key for whole-page capture (PDF export).
  final canvasKey = GlobalKey();

  // Workspace / navigation
  String? notebookId;
  List<TreeNode> nodes = [];
  String? pageId;
  final Set<String> collapsedGroups = {};

  // Page content
  List<Block> blocks = [];
  PageProps pageProps = PageProps();

  // Selection (CANVAS-7: single + multi)
  final Set<String> selectedIds = {};
  String? selectedBlockId; // primary (gets handles/chrome)
  String? editingBlockId;

  /// Bumped when block content changes from OUTSIDE its own editor widgets
  /// (undo/redo, page load) so views rebuild from model state.
  int docRevision = 0;

  /// Measured render sizes of auto-height blocks (runtime only; used for
  /// culling, marquee hit-testing, and content bounds).
  final Map<String, Size> renderSizes = {};

  /// Pointer ids claimed by block widgets this gesture, so the canvas-level
  /// handler ignores them (see BlockView / PageCanvas).
  final Set<int> claimedPointers = {};

  // Canvas settings
  Tool tool = Tool.select;
  bool snapToGrid = false;
  double gridSize = 20;
  int penColor = 0;
  double penSize = 2.5;

  // True while the in-page title field is focused (suppresses tool shortcuts).
  bool titleEditing = false;
  void setTitleEditing(bool v) {
    titleEditing = v;
    notifyListeners();
  }

  // Find (TEXT-7)
  bool findOpen = false;
  String findQuery = '';
  List<String> findMatches = [];
  int findIndex = 0;

  // Save & undo
  Timer? _saveDebounce;
  bool _dirty = false;
  bool get hasUnsavedChanges => _dirty;
  final List<String> _undo = [];
  final List<String> _redo = [];
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  Future<void> init() async {
    notebookId = repo.notebooks.first.id;
    await _loadNotebook();
  }

  Future<void> _loadNotebook() async {
    nodes = repo.loadNodes(notebookId!);
    final firstPage = nodes.where((n) => n.kind == NodeKind.page).firstOrNull;
    await selectPage(firstPage?.id);
  }

  Future<void> selectNotebook(String id) async {
    await flushSave();
    notebookId = id;
    await _loadNotebook();
    notifyListeners();
  }

  Future<void> createNotebook(String title) async {
    await flushSave();
    final ref = await repo.createNotebook(title);
    await selectNotebook(ref.id);
  }

  Future<void> selectPage(String? id) async {
    await flushSave();
    pageId = id;
    select(null);
    _undo.clear();
    _redo.clear();
    renderSizes.clear();
    findMatches = [];
    findQuery = '';
    if (id == null) {
      blocks = [];
      pageProps = PageProps();
    } else {
      final data = await engine.loadPage(notebookId!, id);
      blocks = data.blocks;
      pageProps = data.props;
    }
    docRevision++;
    notifyListeners();
  }

  // ── Page-surface geometry (CANVAS-1 v0.3) ──────────────────────────────

  static const double defaultPageHeight = 1400;
  static const double pageGrowMargin = 240;
  // In-page title band + left writing margin (OneNote-like page).
  static const double pageLeftMargin = 44;
  static const double titleBandHeight = 84; // title + date live here
  static const double contentTop = titleBandHeight + 8;

  /// Content-only extent (right & bottom edges), for page growth & fit.
  ({double right, double bottom}) contentExtent() {
    var right = pageLeftMargin, bottom = contentTop;
    for (final b in blocks) {
      final bh = b.h ?? renderSizes[b.id]?.height ?? 60;
      if (b.x + b.w > right) right = b.x + b.w;
      if (b.y + bh > bottom) bottom = b.y + bh;
    }
    return (right: right, bottom: bottom);
  }

  /// Content-based page size (used off-view, e.g. export). The on-screen page
  /// additionally grows to fill the viewport — computed in the canvas widget.
  Size pageSize() {
    final e = contentExtent();
    return Size(
      math.max(pageProps.pageWidth, e.right + pageGrowMargin),
      math.max(defaultPageHeight, e.bottom + pageGrowMargin),
    );
  }

  /// OneNote-style intelligent placement: create near the click, but align to
  /// the writing margin and to nearby content instead of landing pixel-exact.
  Offset smartTextPosition(Offset click) {
    const alignX = 56.0; // snap-to-left-edge threshold
    const alignY = 22.0; // snap-to-neighbour threshold
    final contentBlocks =
        blocks.where((b) => b.type != BlockType.ink).toList();

    // Empty page, clicked anywhere up top → the standard top-left spot.
    if (contentBlocks.isEmpty && click.dy < contentTop + 220) {
      return const Offset(pageLeftMargin, contentTop);
    }

    // X: snap to the writing margin or a nearby block's left edge.
    final xs = <double>[pageLeftMargin, ...contentBlocks.map((b) => b.x)];
    var x = click.dx;
    var bestX = double.infinity;
    for (final cx in xs) {
      if ((cx - click.dx).abs() < (bestX - click.dx).abs()) bestX = cx;
    }
    x = (bestX - click.dx).abs() < alignX ? bestX : math.max(click.dx, pageLeftMargin);

    // Y: snap just under a nearby block, or align with a block's top.
    var y = math.max(click.dy - 12, contentTop);
    final ys = <double>[];
    for (final b in contentBlocks) {
      final bh = b.h ?? renderSizes[b.id]?.height ?? 60;
      ys..add(b.y)..add(b.y + bh + 14);
    }
    var bestY = double.infinity;
    for (final cy in ys) {
      if ((cy - y).abs() < (bestY - y).abs()) bestY = cy;
    }
    if (bestY.isFinite && (bestY - y).abs() < alignY) y = bestY;

    return Offset(math.max(x, pageLeftMargin), math.max(y, contentTop));
  }

  Rect contentBounds() {
    if (blocks.isEmpty) return Rect.fromLTWH(0, 0, pageProps.pageWidth, 400);
    var r = Rect.zero;
    var first = true;
    for (final b in blocks) {
      final bh = b.h ?? renderSizes[b.id]?.height ?? 60;
      final br = Rect.fromLTWH(b.x, b.y, b.w, bh);
      r = first ? br : r.expandToInclude(br);
      first = false;
    }
    return r;
  }

  /// Content never above/left of the page origin (CANVAS-1 v0.3).
  void clampBlockToPage(Block b) {
    if (b.x < 0) b.x = 0;
    if (b.y < 0) b.y = 0;
  }

  // ── Tree ops ───────────────────────────────────────────────────────────

  static const _sectionColors = [
    'ink-500', 'brass-400', 'green', 'blue', 'violet', 'red'
  ];

  Future<void> addSection({String? groupId}) async {
    final count = nodes.where((n) => n.kind == NodeKind.section).length;
    final n = repo.upsertNode(
        notebookId!,
        TreeNode(
            kind: NodeKind.section,
            parentId: groupId,
            title: 'Section ${count + 1}',
            color: _sectionColors[count % _sectionColors.length],
            position: _nextPosition()));
    nodes = repo.loadNodes(notebookId!);
    await addPage(sectionId: n.id);
  }

  void addSectionGroup() {
    final count = nodes.where((n) => n.kind == NodeKind.sectionGroup).length;
    repo.upsertNode(
        notebookId!,
        TreeNode(
            kind: NodeKind.sectionGroup,
            title: 'Group ${count + 1}',
            position: _nextPosition()));
    nodes = repo.loadNodes(notebookId!);
    notifyListeners();
  }

  Future<void> addPage({String? sectionId}) async {
    sectionId ??= sectionOf(pageId) ??
        nodes.where((n) => n.kind == NodeKind.section).firstOrNull?.id;
    if (sectionId == null) return;
    final n = repo.upsertNode(
        notebookId!,
        TreeNode(
            kind: NodeKind.page,
            parentId: sectionId,
            title: 'Untitled page',
            position: _nextPosition()));
    nodes = repo.loadNodes(notebookId!);
    await selectPage(n.id);
  }

  void renameNode(String id, String title) {
    final n = nodes.firstWhere((n) => n.id == id);
    n.title = title;
    repo.upsertNode(notebookId!, n);
    notifyListeners();
  }

  /// Subpage indent (ORG-6): level 0..2.
  void indentPage(String id, int delta) {
    final n = nodes.firstWhere((n) => n.id == id);
    if (n.kind != NodeKind.page) return;
    n.level = (n.level + delta).clamp(0, 2);
    repo.upsertNode(notebookId!, n);
    notifyListeners();
  }

  /// Reorder among siblings (ORG-2, menu-driven for MVP).
  void moveNode(String id, int delta) {
    final n = nodes.firstWhere((n) => n.id == id);
    final siblings = nodes
        .where((s) => s.kind == n.kind && s.parentId == n.parentId)
        .toList();
    final i = siblings.indexWhere((s) => s.id == id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= siblings.length) return;
    final other = siblings[j];
    final tmp = n.position;
    n.position = other.position;
    other.position = tmp;
    repo.upsertNode(notebookId!, n);
    repo.upsertNode(notebookId!, other);
    nodes = repo.loadNodes(notebookId!);
    notifyListeners();
  }

  void moveSectionToGroup(String sectionId, String? groupId) {
    final n = nodes.firstWhere((n) => n.id == sectionId);
    if (n.kind != NodeKind.section) return;
    n.parentId = groupId;
    repo.upsertNode(notebookId!, n);
    nodes = repo.loadNodes(notebookId!);
    notifyListeners();
  }

  TreeNode? node(String id) => nodes.where((n) => n.id == id).firstOrNull;

  List<TreeNode> get pages =>
      nodes.where((n) => n.kind == NodeKind.page).toList();

  TreeNode? pageByTitle(String title) {
    final t = title.trim().toLowerCase();
    return pages.where((p) => p.title.trim().toLowerCase() == t).firstOrNull;
  }

  /// Resolve a wiki-link target (EMBED-1): prefer the stable id, fall back to
  /// title match, and navigate.
  void openWikiLink(String label, String? id) {
    final target = (id != null && node(id) != null) ? id : pageByTitle(label)?.id;
    if (target != null) selectPage(target);
  }

  /// Insert a page-link (EMBED-1) as a new text block referencing the target
  /// by stable id: `[[Title|id]]`.
  void insertPageLink(String targetPageId) {
    final target = node(targetPageId);
    if (target == null) return;
    final pos = smartTextPosition(const Offset(pageLeftMargin, contentTop));
    final b = addBlock(Block(
      type: BlockType.text,
      x: pos.dx,
      y: pos.dy,
      w: 320,
      content: {'text': '[[${target.title}|${target.id}]]'},
    ));
    select(b.id);
  }

  /// Drag a page into another section (ORG-2): reparent, level 0, append.
  void movePageToSection(String pageId, String sectionId) {
    final n = node(pageId);
    final s = node(sectionId);
    if (n == null || n.kind != NodeKind.page || s?.kind != NodeKind.section) {
      return;
    }
    n
      ..parentId = sectionId
      ..level = 0
      ..position = _nextPosition();
    repo.upsertNode(notebookId!, n);
    nodes = repo.loadNodes(notebookId!);
    notifyListeners();
  }

  /// Drag a page onto another page → make it a subpage (ORG-6): same section,
  /// indented one level deeper, positioned right after the target.
  void makeSubpageOf(String pageId, String targetPageId) {
    if (pageId == targetPageId) return;
    final n = node(pageId);
    final target = node(targetPageId);
    if (n == null || target == null || target.kind != NodeKind.page) return;
    n
      ..parentId = target.parentId
      ..level = (target.level + 1).clamp(0, 2)
      ..position = '${target.position}m'; // sorts immediately after target
    repo.upsertNode(notebookId!, n);
    nodes = repo.loadNodes(notebookId!);
    notifyListeners();
  }

  void toggleGroupCollapsed(String id) {
    collapsedGroups.contains(id)
        ? collapsedGroups.remove(id)
        : collapsedGroups.add(id);
    notifyListeners();
  }

  Future<void> deleteNode(String id) async {
    repo.softDeleteNode(notebookId!, id);
    nodes = repo.loadNodes(notebookId!);
    if (pageId == id || !nodes.any((n) => n.id == pageId)) {
      await selectPage(
          nodes.where((n) => n.kind == NodeKind.page).firstOrNull?.id);
    }
    notifyListeners();
  }

  String? sectionOf(String? page) =>
      nodes.where((n) => n.id == page).firstOrNull?.parentId;

  String _nextPosition() =>
      'a${(nowMs() % 100000000).toString().padLeft(9, '0')}';

  // ── Undo / redo (page-scoped snapshots) ────────────────────────────────

  String _snapshot() => jsonEncode({
        'page': pageProps.toJson(),
        'blocks': [for (final b in blocks) b.toJson()],
      });

  void _restore(String snap) {
    final j = jsonDecode(snap) as Map<String, dynamic>;
    pageProps = PageProps.fromJson((j['page'] as Map?)?.cast<String, dynamic>());
    blocks = [
      for (final b in (j['blocks'] as List))
        Block.fromJson((b as Map).cast<String, dynamic>())
    ];
    selectedIds.clear();
    selectedBlockId = null;
    editingBlockId = null;
    docRevision++;
    markDirty();
    notifyListeners();
  }

  void pushUndo() {
    _undo.add(_snapshot());
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_snapshot());
    _restore(_undo.removeLast());
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_snapshot());
    _restore(_redo.removeLast());
  }

  // ── Selection & block ops ──────────────────────────────────────────────

  double snap(double v) => snapToGrid ? (v / gridSize).round() * gridSize : v;

  Block addBlock(Block b, {bool recordUndo = true}) {
    if (recordUndo) pushUndo();
    b
      ..x = snap(b.x)
      ..y = snap(b.y)
      ..placement = snapToGrid ? 'snapped' : 'free'
      ..z = (blocks.isEmpty
          ? 0
          : blocks.map((e) => e.z).reduce((a, c) => a > c ? a : c) + 1);
    clampBlockToPage(b);
    blocks.add(b);
    markDirty();
    notifyListeners();
    return b;
  }

  void updateBlock(Block b) {
    b.updatedAt = nowMs();
    markDirty();
    notifyListeners();
  }

  void removeBlock(String id, {bool recordUndo = true}) {
    if (recordUndo) pushUndo();
    blocks.removeWhere((b) => b.id == id);
    selectedIds.remove(id);
    if (selectedBlockId == id) selectedBlockId = selectedIds.firstOrNull;
    if (editingBlockId == id) editingBlockId = null;
    markDirty();
    notifyListeners();
  }

  void removeSelected() {
    if (selectedIds.isEmpty) return;
    pushUndo();
    blocks.removeWhere((b) => selectedIds.contains(b.id));
    selectedIds.clear();
    selectedBlockId = null;
    editingBlockId = null;
    markDirty();
    notifyListeners();
  }

  /// Duplicate with FRESH ids (Data Model Spec §2 rule 3).
  void duplicateBlock(String id) {
    final src = blocks.where((b) => b.id == id).firstOrNull;
    if (src == null) return;
    pushUndo();
    final fresh = Block(
      id: newId(),
      type: src.type,
      x: src.x + 24,
      y: src.y + 24,
      w: src.w,
      h: src.h,
      placement: src.placement,
      content: jsonDecode(jsonEncode(src.content)) as Map<String, dynamic>,
    );
    if (fresh.type == BlockType.ink) {
      for (final sj in (fresh.content['strokes'] as List)) {
        (sj as Map)['id'] = newId();
      }
    }
    addBlock(fresh, recordUndo: false);
    select(fresh.id);
  }

  void select(String? id, {bool edit = false, bool additive = false}) {
    if (id == null) {
      selectedIds.clear();
      selectedBlockId = null;
      editingBlockId = null;
    } else if (additive) {
      if (!selectedIds.add(id)) selectedIds.remove(id);
      selectedBlockId =
          selectedIds.contains(id) ? id : selectedIds.firstOrNull;
      editingBlockId = null;
    } else {
      selectedIds
        ..clear()
        ..add(id);
      selectedBlockId = id;
      editingBlockId = edit ? id : null;
    }
    notifyListeners();
  }

  void selectMany(Iterable<String> ids) {
    selectedIds
      ..clear()
      ..addAll(ids);
    selectedBlockId = selectedIds.firstOrNull;
    editingBlockId = null;
    notifyListeners();
  }

  /// Move every selected block by a page-space delta (ink blocks translate
  /// their stroke coordinates — Ink Spec §3, coordinates are page-absolute).
  void moveSelectedBy(double dx, double dy) {
    for (final b in blocks.where((b) => selectedIds.contains(b.id))) {
      b.x += dx;
      b.y += dy;
      if (b.type == BlockType.ink) {
        for (final sj in (b.content['strokes'] as List)) {
          final m = (sj as Map);
          m['x'] = [for (final v in (m['x'] as List)) (v as num) + dx];
          m['y'] = [for (final v in (m['y'] as List)) (v as num) + dy];
        }
      }
    }
    markDirty();
    notifyListeners();
  }

  /// Snap + clamp all selected at drag end.
  void settleSelected() {
    for (final b in blocks.where((b) => selectedIds.contains(b.id))) {
      if (snapToGrid && b.type != BlockType.ink) {
        b.x = snap(b.x);
        b.y = snap(b.y);
        b.placement = 'snapped';
      }
      clampBlockToPage(b);
    }
    markDirty();
    notifyListeners();
  }

  void setTool(Tool t) {
    tool = t;
    if (t != Tool.select) select(null);
    notifyListeners();
  }

  void toggleSnap() {
    snapToGrid = !snapToGrid;
    notifyListeners();
  }

  void setBackground(String bg) {
    pushUndo();
    pageProps.background = bg;
    markDirty();
    notifyListeners();
  }

  void refresh() => notifyListeners();

  // ── Find (TEXT-7, current page) ────────────────────────────────────────

  void toggleFind() {
    findOpen = !findOpen;
    if (!findOpen) {
      findQuery = '';
      findMatches = [];
    }
    notifyListeners();
  }

  void setFindQuery(String q) {
    findQuery = q;
    final needle = q.toLowerCase();
    findMatches = needle.isEmpty
        ? []
        : [
            for (final b in blocks)
              if (_blockText(b).toLowerCase().contains(needle)) b.id
          ];
    findIndex = 0;
    if (findMatches.isNotEmpty) _jumpToMatch();
    notifyListeners();
  }

  void findNext(int dir) {
    if (findMatches.isEmpty) return;
    findIndex = (findIndex + dir) % findMatches.length;
    if (findIndex < 0) findIndex += findMatches.length;
    _jumpToMatch();
    notifyListeners();
  }

  void _jumpToMatch() {
    final id = findMatches[findIndex];
    final b = blocks.where((b) => b.id == id).firstOrNull;
    if (b == null) return;
    selectedIds
      ..clear()
      ..add(id);
    selectedBlockId = id;
    editingBlockId = null;
    final h = b.h ?? renderSizes[id]?.height ?? 60;
    canvas.centerOn(Offset(b.x + b.w / 2, b.y + h / 2));
  }

  String _blockText(Block b) => switch (b.type) {
        BlockType.text => b.content['text'] as String? ?? '',
        BlockType.code => b.content['source'] as String? ?? '',
        BlockType.math => '${b.content['latex'] ?? ''} ${b.content['linearSource'] ?? ''}',
        _ => '',
      };

  // ── Persistence ────────────────────────────────────────────────────────

  void markDirty() {
    _dirty = true;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 700), flushSave);
    notifyListeners();
  }

  Future<void> flushSave() async {
    _saveDebounce?.cancel();
    if (!_dirty || pageId == null || notebookId == null) return;
    _dirty = false;
    await engine.savePage(notebookId!, pageId!, blocks, pageProps);
    notifyListeners();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    repo.dispose();
    super.dispose();
  }
}
