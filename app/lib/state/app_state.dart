import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart'; // ThemeMode + widgets (re-exports foundation)

import '../canvas/canvas_controller.dart';
import '../core/engine.dart';
import '../core/ids.dart';
import '../core/onote_ffi.dart';
import '../model/models.dart';
import '../store/repository.dart';

enum Tool { select, text, pen, highlighter, eraser, lasso }

/// App-wide state. Deliberately simple (ChangeNotifier) for the MVP; the
/// domain layer beneath it is what carries forward.
class AppState extends ChangeNotifier {
  AppState(this.repo) : engine = _selectEngine(repo);

  final Repository repo;
  final DocumentEngine engine;

  /// Use the Rust core when its native library is linked, else the pure-Dart
  /// engine. Chosen once at construction — the app depends only on the seam.
  static DocumentEngine _selectEngine(Repository repo) {
    final core = OnoteCore.instance;
    return core != null ? RustEngine(repo, core) : MirrorEngine(repo);
  }

  /// Shared so toolbar/shortcuts can drive zoom (style guide §8.2).
  final canvas = CanvasController();

  /// RepaintBoundary key for whole-page capture (PDF export).
  final canvasKey = GlobalKey();

  // Workspace / navigation
  String? notebookId;
  List<TreeNode> nodes = [];
  String? pageId;
  final Set<String> collapsedGroups = {};

  // Navigator (stacked): the focused section, whose pages fill the lower zone.
  String? activeSectionId;
  double navSplit = 0.38; // sections/pages height ratio (0..1)

  TreeNode? get activeSection => node(activeSectionId);

  void setNavSplit(double v) {
    navSplit = v.clamp(0.15, 0.7);
    repo.setSetting('navSplit', navSplit);
    notifyListeners();
  }

  /// Focus a section (the pages zone shows its pages). When the current page
  /// isn't inside the section, jump to its first page.
  void activateSection(String id) {
    activeSectionId = id;
    final cur = node(pageId);
    if (cur == null || cur.parentId != id) {
      final first = nodes
          .where((n) => n.kind == NodeKind.page && n.parentId == id)
          .firstOrNull;
      if (first != null) {
        selectPage(first.id); // sets activeSectionId + notifies
        return;
      }
    }
    notifyListeners();
  }

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
  bool snapToGrid = true; // on by default; the grid only shows while dragging
  int penColor = 0;
  double penSize = 2.5;

  // True while a block is being dragged — the canvas shows a faint grid then.
  bool draggingBlock = false;
  void setDragging(bool v) {
    if (draggingBlock == v) return;
    draggingBlock = v;
    notifyListeners();
  }

  // Collapse state (OneNote-style hierarchy folding).
  final Set<String> collapsedSections = {};
  final Set<String> collapsedPages = {};
  void toggleSectionCollapsed(String id) {
    collapsedSections.contains(id)
        ? collapsedSections.remove(id)
        : collapsedSections.add(id);
    notifyListeners();
  }

  void togglePageCollapsed(String id) {
    collapsedPages.contains(id)
        ? collapsedPages.remove(id)
        : collapsedPages.add(id);
    notifyListeners();
  }

  // ── UI chrome state (Phase 2) ──────────────────────────────────────────

  ThemeMode themeMode = ThemeMode.system;
  void setThemeMode(ThemeMode m) {
    themeMode = m;
    repo.setSetting('themeMode', m.name); // persist (§7a.5)
    notifyListeners();
  }

  /// The text/code editor currently mounted & editing, registered by its view
  /// so command-bar formatting can act on the live selection.
  ({TextEditingController controller, Block block, String contentKey})?
      activeEditor;
  void setActiveEditor(
      TextEditingController c, Block b, String key) {
    activeEditor = (controller: c, block: b, contentKey: key);
    // No notify: called during build; enablement rides the select() notify.
  }

  void clearActiveEditor(String blockId) {
    if (activeEditor?.block.id == blockId) activeEditor = null;
  }

  void _commitActiveEditor() {
    final ae = activeEditor;
    if (ae == null) return;
    ae.block.content[ae.contentKey] = ae.controller.text;
    ae.block.updatedAt = nowMs();
    markDirty();
  }

  /// True when the block being edited is a text box (enables the Home-tab
  /// formatting buttons immediately, independent of child build order).
  bool get canFormatText {
    final id = editingBlockId;
    if (id == null) return false;
    return blocks.where((b) => b.id == id).firstOrNull?.type == BlockType.text;
  }

  /// Insert text at the caret of the active editor (e.g. a page link inline).
  void insertTextAtActiveCursor(String s) {
    final ae = activeEditor;
    if (ae == null) return;
    final c = ae.controller;
    final sel = c.selection;
    final at = sel.isValid ? sel.start : c.text.length;
    final end = sel.isValid ? sel.end : c.text.length;
    pushUndo();
    c.text = c.text.replaceRange(at, end, s);
    c.selection = TextSelection.collapsed(offset: at + s.length);
    _commitActiveEditor();
    notifyListeners();
  }

  // ── Text colour (inline {{#RRGGBB text}}) ──────────────────────────────

  String lastColor = 'C63838'; // last-used ink colour; default red
  final List<String> customColors = []; // recent/custom, persisted
  void rememberCustomColor(String hex) {
    customColors.remove(hex);
    customColors.insert(0, hex);
    if (customColors.length > 12) customColors.removeLast();
    repo.setSetting('customColors', customColors);
    notifyListeners();
  }

  static final _colorOpenRe =
      RegExp(r'\{\{#([0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?) $');
  // Matches a whole wrapper as the entire selection: {{#hex inner}}.
  static final _colorWholeRe = RegExp(
      r'^\{\{#([0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?) (.*)\}\}$',
      dotAll: true);

  void applyTextColor(String hex) {
    final ae = activeEditor;
    if (ae == null) return;
    lastColor = hex;
    final c = ae.controller;
    final sel = c.selection;
    if (!sel.isValid || sel.isCollapsed) {
      notifyListeners();
      return;
    }
    final t = c.text;
    final s = math.min(sel.baseOffset, sel.extentOffset);
    final e = math.max(sel.baseOffset, sel.extentOffset);

    // Re-colour, don't nest (user report): if the selection is already the
    // inner content of an existing {{#hex …}} wrapper, or the selection spans
    // a whole wrapper, replace the existing colour in place.

    // Case A: selection is the INNER content of an existing wrapper —
    //   …{{#oldhex |selected|}}…  → swap oldhex for the new hex.
    final openBefore = _colorOpenRe.firstMatch(t.substring(0, s));
    if (openBefore != null &&
        e + 2 <= t.length &&
        t.substring(e, e + 2) == '}}') {
      pushUndo();
      final openLen = openBefore.group(0)!.length;
      const newOpenPrefix = '{{#';
      final newOpen = '$newOpenPrefix$hex ';
      c.text = t.replaceRange(s - openLen, s, newOpen);
      final shift = newOpen.length - openLen;
      c.selection =
          TextSelection(baseOffset: s + shift, extentOffset: e + shift);
      _commitActiveEditor();
      notifyListeners();
      return;
    }

    // Case B: the selection spans an ENTIRE wrapper — {{#oldhex inner}} —
    // e.g. selecting the coloured word including its markers. Rewrite it.
    final whole = _colorWholeRe.firstMatch(t.substring(s, e));
    if (whole != null) {
      pushUndo();
      final inner = whole.group(2)!;
      c.text = t.replaceRange(s, e, '{{#$hex $inner}}');
      final openLen = hex.length + 4; // '{{#' + hex + ' '
      c.selection = TextSelection(
          baseOffset: s + openLen, extentOffset: s + openLen + inner.length);
      _commitActiveEditor();
      notifyListeners();
      return;
    }

    // Case C: fresh selection — wrap it.
    pushUndo();
    final selText = t.substring(s, e);
    c.text = t.replaceRange(s, e, '{{#$hex $selText}}');
    final openLen = hex.length + 4; // '{{#' + hex + ' '
    c.selection = TextSelection(
        baseOffset: s + openLen, extentOffset: s + openLen + selText.length);
    _commitActiveEditor();
    notifyListeners();
  }

  /// The "flick" hotkey: colour the selection with the last colour, or strip
  /// the colour if it's already coloured (back to default).
  void toggleTextColor() {
    final ae = activeEditor;
    if (ae == null) return;
    final c = ae.controller;
    final sel = c.selection;
    if (!sel.isValid || sel.isCollapsed) return;
    final s = math.min(sel.baseOffset, sel.extentOffset);
    final e = math.max(sel.baseOffset, sel.extentOffset);
    final t = c.text;
    final m = _colorOpenRe.firstMatch(t.substring(0, s));
    if (m != null && e + 2 <= t.length && t.substring(e, e + 2) == '}}') {
      pushUndo();
      final openLen = m.group(0)!.length;
      c.text = t.replaceRange(e, e + 2, '').replaceRange(s - openLen, s, '');
      c.selection =
          TextSelection(baseOffset: s - openLen, extentOffset: e - openLen);
      _commitActiveEditor();
      notifyListeners();
    } else {
      applyTextColor(lastColor);
    }
  }

  // ── Text-box font family (box-level) ───────────────────────────────────

  void setActiveBlockFont(String font) {
    final id = editingBlockId;
    if (id == null) return;
    final b = blocks.where((x) => x.id == id).firstOrNull;
    if (b == null || b.type != BlockType.text) return;
    pushUndo();
    // Any system family name; '' or 'sans' = default. Legacy 'serif'/'mono'
    // map in the view.
    if (font.isEmpty || font == 'sans') {
      b.content.remove('font');
    } else {
      b.content['font'] = font;
    }
    updateBlock(b);
  }

  // ── New-page title flow ────────────────────────────────────────────────

  String? pendingTitleEdit; // page whose title should auto-focus on show

  /// Enter pressed in the title → drop into the first body text box.
  void startBodyFromTitle() {
    final pos = smartTextPosition(const Offset(pageLeftMargin, contentTop));
    final b = addBlock(Block(
        type: BlockType.text, x: pos.dx, y: pos.dy, w: 320, content: {'text': ''}));
    select(b.id, edit: true);
  }

  /// Toggle-wrap the live selection with markers (Ctrl+B/I, command bar).
  void wrapSelection(String mark, [String? closeMark]) {
    final ae = activeEditor;
    if (ae == null) return;
    final c = ae.controller;
    final sel = c.selection;
    if (!sel.isValid) return;
    final close = closeMark ?? mark;
    final s = math.min(sel.baseOffset, sel.extentOffset);
    final e = math.max(sel.baseOffset, sel.extentOffset);
    final t = c.text;
    pushUndo();
    final already = s >= mark.length &&
        e + close.length <= t.length &&
        t.substring(s - mark.length, s) == mark &&
        t.substring(e, e + close.length) == close;
    if (already) {
      c.text = t
          .replaceRange(e, e + close.length, '')
          .replaceRange(s - mark.length, s, '');
      c.selection = TextSelection(
          baseOffset: s - mark.length, extentOffset: e - mark.length);
    } else {
      c.text = t.replaceRange(s, e, '$mark${t.substring(s, e)}$close');
      c.selection =
          TextSelection(baseOffset: s + mark.length, extentOffset: e + mark.length);
    }
    _commitActiveEditor();
    notifyListeners();
  }

  /// Toggle a line prefix (headings, lists, checkboxes) on the selected lines.
  void toggleLinePrefix(String prefix, {bool exclusive = true}) {
    final ae = activeEditor;
    if (ae == null) return;
    final c = ae.controller;
    final sel = c.selection;
    if (!sel.isValid) return;
    pushUndo();
    final t = c.text;
    final s = math.min(sel.baseOffset, sel.extentOffset);
    final e = math.max(sel.baseOffset, sel.extentOffset);
    final lineStart = t.lastIndexOf('\n', math.max(0, s - 1)) + 1;
    var lineEnd = t.indexOf('\n', e);
    if (lineEnd < 0) lineEnd = t.length;
    final region = t.substring(lineStart, lineEnd);
    final stripRe = exclusive
        ? RegExp(r'^(#{1,3} |- \[[ xX]\] |[-*] |\d+\. |> )')
        : RegExp('^${RegExp.escape(prefix)}');
    final lines = region.split('\n');
    final allHave = lines.every((l) => l.startsWith(prefix));
    final out = [
      for (final l in lines)
        allHave
            ? l.substring(prefix.length)
            : '$prefix${l.replaceFirst(stripRe, '')}'
    ].join('\n');
    c.text = t.replaceRange(lineStart, lineEnd, out);
    c.selection = TextSelection.collapsed(
        offset: math.min(lineStart + out.length, c.text.length));
    _commitActiveEditor();
    notifyListeners();
  }

  // ── Block clipboard (internal, Ctrl+C/X/V when not typing) ────────────

  String? _blockClipboard;
  bool get canPasteBlocks => _blockClipboard != null;

  void copySelectedBlocks() {
    if (selectedIds.isEmpty) return;
    _blockClipboard = jsonEncode([
      for (final b in blocks.where((b) => selectedIds.contains(b.id))) b.toJson()
    ]);
    notifyListeners();
  }

  void cutSelectedBlocks() {
    copySelectedBlocks();
    removeSelected();
  }

  void pasteBlocks({Offset? at}) {
    final raw = _blockClipboard;
    if (raw == null) return;
    pushUndo();
    final list = (jsonDecode(raw) as List)
        .map((j) => Block.fromJson((j as Map).cast<String, dynamic>()))
        .toList();
    // Fresh identities (Data Model §2 rule 3), offset placement.
    final newIds = <String>[];
    for (final src in list) {
      final fresh = Block(
        id: newId(),
        type: src.type,
        x: (at?.dx ?? src.x + 28),
        y: (at?.dy ?? src.y + 28),
        w: src.w,
        h: src.h,
        placement: src.placement,
        content: jsonDecode(jsonEncode(src.content)) as Map<String, dynamic>,
      );
      if (fresh.type == BlockType.ink) {
        final dx = fresh.x - src.x, dy = fresh.y - src.y;
        for (final sj in (fresh.content['strokes'] as List)) {
          final m = (sj as Map);
          m['id'] = newId();
          m['x'] = [for (final v in (m['x'] as List)) (v as num) + dx];
          m['y'] = [for (final v in (m['y'] as List)) (v as num) + dy];
        }
      }
      clampBlockToPage(fresh);
      blocks.add(fresh);
      newIds.add(fresh.id);
    }
    selectMany(newIds);
    markDirty();
  }

  // ── Z-order (context menu) ─────────────────────────────────────────────

  void bringToFront(String id) {
    final b = blocks.where((b) => b.id == id).firstOrNull;
    if (b == null || blocks.isEmpty) return;
    pushUndo();
    b.z = blocks.map((e) => e.z).reduce(math.max) + 1;
    updateBlock(b);
  }

  void sendToBack(String id) {
    final b = blocks.where((b) => b.id == id).firstOrNull;
    if (b == null || blocks.isEmpty) return;
    pushUndo();
    b.z = blocks.map((e) => e.z).reduce(math.min) - 1;
    updateBlock(b);
  }

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

  // ── Document engine (Rust core, optional) ─────────────────────────────

  /// Human-readable label for the active engine, shown in the status bar
  /// ("Rust core vX" or "Dart engine").
  String get engineLabel => engine.label;

  /// Content hash of the most recently saved page (Rust core only); drives the
  /// status-bar chip. Null on the pure-Dart engine.
  String? get pageContentHash => engine.lastSavedHash;

  Future<void> init() async {
    // Session restore (§7a.5): theme, custom colours, per-page views, last loc.
    final tm = repo.getSetting('themeMode') as String?;
    if (tm != null) themeMode = ThemeMode.values.asNameMap()[tm] ?? themeMode;
    final ns = repo.getSetting('navSplit');
    if (ns is num) navSplit = ns.toDouble().clamp(0.15, 0.7);
    final cc = repo.getSetting('customColors');
    if (cc is List) customColors.addAll(cc.cast<String>());
    final vm = repo.getSetting('viewMemory');
    if (vm is Map) {
      vm.forEach((k, v) {
        if (v is List && v.length == 3) {
          _viewMemory[k as String] =
              [for (final x in v) (x as num).toDouble()];
        }
      });
    }
    final lastNb = repo.getSetting('lastNotebook') as String?;
    notebookId = repo.notebooks.any((n) => n.id == lastNb)
        ? lastNb!
        : repo.notebooks.first.id;
    // Clear out anything that has outlived the recycle-bin retention window.
    await repo.purgeExpiredNotebooks();
    repo.purgeExpiredNodes(notebookId!);
    nodes = repo.loadNodes(notebookId!);
    final lastPage = repo.getSetting('lastPage') as String?;
    final target = nodes.any((n) => n.id == lastPage && n.kind == NodeKind.page)
        ? lastPage
        : nodes.where((n) => n.kind == NodeKind.page).firstOrNull?.id;
    await selectPage(target);
  }

  // ── Per-page view memory (§7a.5) ───────────────────────────────────────

  final Map<String, List<double>> _viewMemory = {};

  List<double>? viewFor(String id) => _viewMemory[id];

  void _rememberView() {
    final id = pageId;
    if (id == null) return;
    _viewMemory[id] = [canvas.scale, canvas.offset.dx, canvas.offset.dy];
    if (_viewMemory.length > 300) _viewMemory.remove(_viewMemory.keys.first);
  }

  void _persistSession() {
    repo.setSetting('viewMemory', _viewMemory);
    repo.setSetting('lastNotebook', notebookId);
    repo.setSetting('lastPage', pageId);
  }

  Future<void> _loadNotebook() async {
    nodes = repo.loadNodes(notebookId!);
    // Reset the focused section for the new notebook (selectPage refines it).
    activeSectionId =
        nodes.where((n) => n.kind == NodeKind.section).firstOrNull?.id;
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

  Future<void> renameNotebook(String id, String title) async {
    await repo.renameNotebook(id, title);
    notifyListeners();
  }

  /// Soft-delete a notebook to the recycle bin. Refuses the last one (there's
  /// always somewhere to be). Returns false if it couldn't (only notebook).
  Future<bool> deleteNotebook(String id) async {
    if (repo.notebooks.length <= 1) return false;
    await flushSave();
    final wasCurrent = id == notebookId;
    await repo.trashNotebook(id);
    if (wasCurrent) {
      notebookId = repo.notebooks.first.id;
      await _loadNotebook();
    }
    notifyListeners();
    return true;
  }

  List<NotebookRef> get trashedNotebooks => repo.trashedNotebooks;

  /// How long trashed items live before auto-deletion (recycle-bin retention).
  int get recycleRetentionDays => Repository.recycleRetentionDays;

  /// Sweep expired recycle-bin entries (notebooks + the current notebook's
  /// nodes). Runs at startup and whenever the recycle bin is opened.
  Future<void> purgeExpiredTrash() async {
    await repo.purgeExpiredNotebooks();
    if (notebookId != null) repo.purgeExpiredNodes(notebookId!);
    notifyListeners();
  }

  Future<void> restoreNotebook(String id) async {
    await repo.restoreNotebook(id);
    notifyListeners();
  }

  Future<void> purgeNotebook(String id) async {
    await repo.purgeNotebook(id);
    notifyListeners();
  }

  Future<void> selectPage(String? id) async {
    _rememberView(); // keep your place when flicking between pages (§7a.5)
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
      // Keep the navigator's focused section in sync with the open page.
      activeSectionId = nodes.where((n) => n.id == id).firstOrNull?.parentId ??
          activeSectionId;
    }
    docRevision++;
    _persistSession();
    notifyListeners();
  }

  // ── Version history (SYNC-8) ───────────────────────────────────────────

  List<int> pageVersions() =>
      pageId == null ? [] : repo.listVersions(notebookId!, pageId!);

  Future<void> restoreVersion(int at) async {
    if (pageId == null) return;
    final json = repo.versionJson(notebookId!, pageId!, at);
    if (json == null) return;
    pushUndo();
    final j = jsonDecode(json) as Map<String, dynamic>;
    pageProps = PageProps.fromJson((j['page'] as Map?)?.cast<String, dynamic>());
    blocks = [
      for (final b in (j['blocks'] as List))
        Block.fromJson((b as Map).cast<String, dynamic>())
    ];
    docRevision++;
    markDirty();
    notifyListeners();
  }

  // ── Page templates (ORG-9) ─────────────────────────────────────────────

  List<String> templateNames() {
    final t = repo.getSetting('templates');
    return t is Map ? t.keys.cast<String>().toList() : [];
  }

  void saveCurrentAsTemplate(String name) {
    final t = (repo.getSetting('templates') as Map?)?.cast<String, dynamic>() ?? {};
    t[name] = jsonEncode({
      'page': pageProps.toJson(),
      'blocks': [for (final b in blocks) b.toJson()],
    });
    repo.setSetting('templates', t);
    notifyListeners();
  }

  void applyTemplate(String name) {
    final t = repo.getSetting('templates');
    final raw = t is Map ? t[name] as String? : null;
    if (raw == null) return;
    pushUndo();
    final j = jsonDecode(raw) as Map<String, dynamic>;
    pageProps = PageProps.fromJson((j['page'] as Map?)?.cast<String, dynamic>());
    for (final bj in (j['blocks'] as List)) {
      final src = Block.fromJson((bj as Map).cast<String, dynamic>());
      final fresh = Block(
        id: newId(),
        type: src.type,
        x: src.x,
        y: src.y,
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
      blocks.add(fresh);
    }
    docRevision++;
    markDirty();
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
    pendingTitleEdit = n.id; // cursor lands in the title (OneNote behaviour)
    notifyListeners();
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

  TreeNode? node(String? id) =>
      id == null ? null : nodes.where((n) => n.id == id).firstOrNull;

  // ── Recycle bin (ORG-7) ────────────────────────────────────────────────

  List<({String id, String kind, String title, int deletedAt})>
      deletedNodes() => repo.loadDeletedNodes(notebookId!);

  Future<void> restoreDeleted(String id) async {
    repo.restoreNode(notebookId!, id);
    nodes = repo.loadNodes(notebookId!);
    notifyListeners();
  }

  void purgeDeleted(String id) {
    repo.purgeNode(notebookId!, id);
    notifyListeners();
  }

  // ── Backlinks (TEXT-8) ─────────────────────────────────────────────────

  bool showLinksPanel = false;
  void toggleLinksPanel() {
    showLinksPanel = !showLinksPanel;
    notifyListeners();
  }

  List<TreeNode> backlinksForCurrent() {
    if (pageId == null) return [];
    return repo
        .backlinkPageIds(notebookId!, pageId!)
        .map(node)
        .whereType<TreeNode>()
        .toList();
  }

  /// Outgoing wiki-links found in the current page's text blocks.
  List<TreeNode> outgoingLinksForCurrent() {
    final ids = <String>{};
    final re = RegExp(r'\[\[[^\]|]+\|([^\]]+)\]\]');
    for (final b in blocks.where((b) => b.type == BlockType.text)) {
      for (final m in re.allMatches(b.content['text'] as String? ?? '')) {
        ids.add(m.group(1)!);
      }
    }
    return ids.map(node).whereType<TreeNode>().toList();
  }

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
      // Sorts after the target (target.position is a prefix) and before its
      // next sibling; the full-millisecond suffix keeps repeated drops unique.
      ..position = '${target.position}m${nowMs().toString().padLeft(15, '0')}';
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

  // Append-ordered position key. Time-based (siblings sort by creation), padded
  // to a fixed width so lexicographic == numeric order. NOT the CRDT
  // fractional-index of Data Model Spec §1 — that lands with the Loro engine;
  // until then reorder is swap-based ([moveNode]) and insert-after-target uses a
  // suffix ([makeSubpageOf]), neither of which needs true between-key insertion.
  // (The old `% 1e8` truncation wrapped every ~28h, letting new nodes sort
  // before old ones — fixed by keeping the full millisecond value.)
  String _nextPosition() => 'a${nowMs().toString().padLeft(15, '0')}';

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

  // Snap step comes from the page's own grid (Data Model Spec §3), so a page's
  // stored gridSize actually drives placement instead of being dead state.
  double get gridSize => pageProps.gridSize;
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
    addBlock(fresh, recordUndo: false); // snaps + clamps fresh.x/y to final pos
    if (fresh.type == BlockType.ink) {
      // Translate strokes to the block's FINAL (snapped/clamped) position so the
      // duplicate's ink renders under its new rect, not on top of the original.
      final dx = fresh.x - src.x, dy = fresh.y - src.y;
      for (final sj in (fresh.content['strokes'] as List)) {
        final m = (sj as Map);
        m['x'] = [for (final v in (m['x'] as List)) (v as num) + dx];
        m['y'] = [for (final v in (m['y'] as List)) (v as num) + dy];
      }
      fresh.updatedAt = nowMs(); // refresh the canvas stroke cache key
    }
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
        // The canvas caches decoded strokes by `id#updatedAt`; bump it so the
        // painted ink follows the block instead of lagging until a reload.
        b.updatedAt = nowMs();
      }
    }
    markDirty();
    notifyListeners();
  }

  /// Snap + clamp all selected at drag end. Ongoing left-margin alignment:
  /// if a block lands near the invisible writing margin, tuck it to the
  /// margin so everything stays neat (matches the smart initial placement).
  void settleSelected() {
    for (final b in blocks.where((b) => selectedIds.contains(b.id))) {
      if (b.type != BlockType.ink) {
        if ((b.x - pageLeftMargin).abs() < 26) {
          b.x = pageLeftMargin;
        } else if (snapToGrid) {
          b.x = snap(b.x);
        }
        if (snapToGrid) b.y = snap(b.y);
        b.placement = snapToGrid ? 'snapped' : 'free';
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
    // The engine owns persistence: version snapshot (throttled, SYNC-8) + the
    // mirror write, plus content-hash change-detection on the Rust engine (a
    // save whose hash is unchanged is skipped). See RustEngine/MirrorEngine.
    await engine.savePage(notebookId!, pageId!, blocks, pageProps);
    // Keep session state fresh so closing the app never loses your place.
    _rememberView();
    _persistSession();
    notifyListeners();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    repo.dispose();
    super.dispose();
  }
}
