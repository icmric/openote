import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart'; // ThemeMode + widgets (re-exports foundation)

import '../canvas/canvas_controller.dart';
import '../core/engine.dart';
import '../core/ids.dart';
import '../core/onote_ffi.dart';
import '../export/onenote_import.dart' show oneNoteLineHeight;
import '../model/models.dart';
import '../store/repository.dart';
import '../model/tags.dart';
import 'builtin_templates.dart';
import '../sync/sync_recorder.dart';

enum Tool { select, text, pen, highlighter, eraser, lasso }

/// How the eraser removes ink (INK-6).
enum EraserMode {
  /// Rub points out; surviving runs split into new strokes. The precise mode.
  area,

  /// Any touched stroke is removed whole — OneNote's default, and the fast way
  /// to delete a scribbled-out word.
  stroke;

  String get label => switch (this) {
        EraserMode.area => 'Area',
        EraserMode.stroke => 'Whole stroke',
      };
}

/// Whether a finger draws when an ink tool is selected (INK-1 / INK-4).
enum TouchDrawing {
  /// Draw with touch, unless a stylus is in use — then touch pans so a resting
  /// palm can't mark the page. The default: it gives pen users OneNote's palm
  /// rejection while leaving ink reachable on a touch-only tablet.
  auto,

  /// Always draw with touch, even with a stylus present.
  always,

  /// Never draw with touch; fingers only pan and pinch. OneNote's strict
  /// behaviour, and what Openote used to do unconditionally.
  never;

  String get label => switch (this) {
        TouchDrawing.auto => 'Auto (pen takes over)',
        TouchDrawing.always => 'Always',
        TouchDrawing.never => 'Never',
      };
}

/// App-wide state. Deliberately simple (ChangeNotifier) for the MVP; the
/// domain layer beneath it is what carries forward.
class AppState extends ChangeNotifier {
  AppState(this._repo) : engine = _selectEngine(_repo);

  final Repository _repo;
  final DocumentEngine engine;

  /// Use the Rust core when its native library is linked, else the pure-Dart
  /// engine. Chosen once at construction — the app depends only on the seam.
  static DocumentEngine _selectEngine(Repository repo) {
    final core = OnoteCore.instance;
    return core != null ? RustEngine(repo, core) : MirrorEngine(repo);
  }

  // ── Storage facade ───────────────────────────────────────────────────
  //
  // `_repo` is private, and these are the only ways into it from outside this
  // class. That is not tidiness. ADR-0006 puts an append-only operation log
  // underneath persistence, and a log is only correct if it observes *every*
  // mutation — the failure mode of a second write path is not a crash but a
  // log that is quietly incomplete, which surfaces much later as a device that
  // won't converge. One funnel now is what makes "rebuild the container from
  // the log and compare" a usable check later.
  //
  // Widgets previously reached `app.repo` directly for blob reads inside
  // `build()`, and both importers wrote through it and then hand-patched
  // `app.nodes` — so any invariant on `nodes` was silently bypassed by import.

  /// Bytes of a blob in the current notebook, or null.
  Uint8List? blob(String hash) =>
      notebookId == null ? null : _repo.getBlob(notebookId!, hash);

  /// Store bytes in the current notebook, returning the content hash.
  String addBlob(Uint8List bytes, String mime) =>
      importBlob(notebookId!, bytes, mime);

  /// Every notebook in the workspace (registry order).
  List<NotebookRef> get notebooks => _repo.notebooks;

  /// The open notebook's registry entry.
  NotebookRef get currentNotebook =>
      _repo.notebooks.firstWhere((n) => n.id == notebookId);

  /// Read a page of the current notebook without making it the active page —
  /// used by exporters, which walk every page in turn.
  PageData readPage(String id) => _repo.readPage(notebookId!, id);

  /// Pages in this notebook whose *content* matches [query] (TEXT-7).
  /// The navigator searches titles itself; this is the other half.
  List<({String pageId, String snippet})> searchContent(String query) =>
      notebookId == null
          ? const []
          : _repo.searchPageContent(notebookId!, query);

  /// Re-read the tree from storage into [nodes], bumping [nodesRevision].
  /// Replaces the `app.nodes = repo.loadNodes(id)` line that used to be copied
  /// at every mutation site, importers included.
  void reloadNodes() {
    if (notebookId != null) nodes = _repo.loadNodes(notebookId!);
  }

  // ── Operation log (ADR-0006, shadow mode) ────────────────────────────
  //
  // Every mutation below also records an op into
  // `<Notebook>.onotebook/ops/<device>.oplog`, beside the `.onote`. The
  // container stays authoritative; the log is written alongside so that
  // "rebuild from the log and compare" is a check we can run today. When the
  // two agree consistently, the container can be demoted to a rebuildable
  // cache and the log becomes the synced artifact — at which point none of the
  // call sites below change.

  /// One recorder per notebook touched this session. Keyed because **imports
  /// write into a notebook that isn't the open one**, and a log that misses
  /// imported content is exactly the kind of quiet incompleteness this whole
  /// arrangement exists to catch.
  final Map<String, SyncRecorder> _recorders = {};

  /// Set false by tests that don't want log files written beside their fixture.
  static bool syncLogEnabled = true;

  SyncRecorder? _recorderFor(String nb) {
    if (!syncLogEnabled) return null;
    final existing = _recorders[nb];
    if (existing != null) return existing;
    final ref = _repo.notebooks.where((n) => n.id == nb).firstOrNull;
    if (ref == null) return null;
    try {
      final r = SyncRecorder.open(
        notebookId: nb,
        notebookPath: ref.file,
        title: ref.title,
        readSetting: _repo.getSetting,
        writeSetting: _repo.setSetting,
      );
      _recorders[nb] = r;
      // Notebooks created before the log existed hold every image in SQLite
      // alone, so a rebuild from the log would reconstruct page structure
      // referencing bytes it cannot supply — a log that looks complete and
      // isn't. Backfill in the background: on a real imported notebook this is
      // hundreds of images, and doing it inline would stall the open.
      unawaited(r
          .backfillBlobs(
            index: _repo.blobIndex(nb),
            read: (h) => _repo.getBlob(nb, h),
          )
          .catchError((Object e) {
        debugPrint('[openote/sync] blob backfill for $nb stopped: $e');
        return 0;
      }));
      return r;
    } catch (e) {
      // Shadow mode must never be able to break saving. The container is still
      // authoritative, so a log we cannot write is a degraded check, not lost
      // data — and failing the user's save to protect a shadow would be an
      // absurd trade.
      debugPrint('[openote/sync] log unavailable for $nb: $e');
      return null;
    }
  }

  /// Pull another device's changes into this notebook (ADR-0006 step 3).
  ///
  /// This is the moment sync exists: the transport is whatever put the other
  /// device's `.oplog` next to ours — a synced folder, a USB stick, rsync — and
  /// because each device only ever appends to its OWN log, there is nothing to
  /// resolve. Merging is reading: sort the union, apply, write the result.
  ///
  /// Returns the number of ops folded in.
  Future<int> syncPull(String nb) async {
    final r = _recorderFor(nb);
    if (r == null) return 0;
    final pending = r.pendingForeignOps(_repo.getSetting);
    if (pending.isEmpty) return 0;

    // Flush first: a local edit still sitting in the debounce would otherwise
    // be overwritten by the materialised page we're about to write.
    await flushSave();

    final changed = r.applyForeign(pending);

    _repo.runInTransaction(nb, () {
      for (final pageId in changed.pages) {
        final mirror = r.materialisedPage(pageId);
        final blocks = [
          for (final b in (mirror['blocks'] as List? ?? const []))
            Block.fromJson((b as Map).cast<String, dynamic>())
        ];
        final props =
            PageProps.fromJson((mirror['page'] as Map?)?.cast<String, dynamic>());
        _repo.writePage(nb, pageId, blocks, props);
      }
      if (changed.treeChanged) {
        // Deletions first: a node the log says is gone must leave the
        // container, or a remote delete would be silently ignored and
        // "delete wins" would become "delete loses". Soft-delete, so it
        // lands in the recycle bin exactly as a local delete would.
        for (final id in r.materialisedDeletedIds()) {
          _repo.softDeleteNode(nb, id);
        }
        for (final n in r.materialisedNodes()) {
          _repo.upsertNode(
              nb,
              TreeNode(
                id: n.id,
                kind: NodeKind.values.firstWhere((k) => k.name == n.kind,
                    orElse: () => NodeKind.page),
                parentId: n.parentId,
                title: n.title,
                position: n.position,
                color: n.color,
                level: n.level,
                createdAt: n.createdAt == 0 ? null : n.createdAt,
              ));
        }
      }
    });

    // Watermark per device, only after the writes landed — a crash mid-pull
    // must re-apply rather than skip.
    final highest = <String, int>{};
    for (final op in pending) {
      if (op.seq > (highest[op.device] ?? 0)) highest[op.device] = op.seq;
    }
    highest.forEach((dev, seq) => r.markForeignSeen(dev, seq, _repo.setSetting));

    // Re-read whatever the user is looking at.
    reloadNodes();
    if (pageId != null && changed.pages.contains(pageId)) {
      final data = await engine.loadPage(nb, pageId!);
      blocks = data.blocks;
      pageProps = data.props;
      docRevision++;
    }
    lastSyncPull = pending.length;
    notifyListeners();
    return pending.length;
  }

  /// Ops folded in by the last [syncPull], for the status surface.
  int lastSyncPull = 0;

  /// Devices that have written to this notebook, for the status surface.
  int syncDeviceCount(String nb) =>
      _recorderFor(nb)?.store.deviceIds().length ?? 0;

  /// Blobs the log references but whose bytes are not yet in `blobs/`.
  ///
  /// Empty means a rebuild from the log could reconstruct this notebook's
  /// content in full, not merely its structure — the distinction that decides
  /// whether the container is safe to demote to a cache.
  Set<String> syncMissingBlobs(String nb) =>
      _recorderFor(nb)?.missingBlobs() ?? const {};

  /// Run the blob backfill to completion. Normally it runs in the background
  /// when a notebook's log is opened; this is for tests and for a future
  /// "prepare this notebook for sync" action.
  Future<int> syncBackfillBlobs(String nb) async =>
      await _recorderFor(nb)?.backfillBlobs(
        index: _repo.blobIndex(nb),
        read: (h) => _repo.getBlob(nb, h),
      ) ??
      0;

  /// Upsert a node and record it. Every tree mutation funnels through here.
  TreeNode _putNode(String nb, TreeNode n) {
    final saved = _repo.upsertNode(nb, n);
    _recorderFor(nb)?.node(saved);
    return saved;
  }

  // ── Import write path ────────────────────────────────────────────────
  //
  // Importers write in bulk, into a notebook that may not be the open one, and
  // outside the interactive edit path. They still go through here rather than
  // touching the repository, for the reason above. The `import` prefix marks
  // them as the bulk path — an interactive edit must never use them, because
  // they deliberately skip autosave, undo and selection handling.

  /// Create a node during import. Returns the stored node.
  TreeNode importNode(String nb, TreeNode n) => _putNode(nb, n);

  /// Write a page's blocks during import.
  void importPage(String nb, String pageId, List<Block> blocks, PageProps p) {
    _repo.writePage(nb, pageId, blocks, p);
    _recorderFor(nb)?.page(pageId, blocks, p);
  }

  /// Store a blob during import (images pulled out of a `.one` file).
  String importBlob(String nb, Uint8List bytes, String mime) {
    final hash = _repo.putBlob(nb, bytes, mime);
    // The op records only the hash, mime and size; the bytes are written to
    // `blobs/<sha256>` — content-addressed and immutable, so they need no merge
    // logic and can be fetched lazily (ADR-0006 §3). Putting megabytes of image
    // into an append-only log would make it unbounded and unreadable.
    _recorderFor(nb)?.blob(hash, mime, bytes.length, bytes);
    return hash;
  }

  /// Hard-delete a node during import — used to clear a partially seeded
  /// notebook before re-seeding it, never on user data.
  void importPurgeNode(String nb, String id) {
    _repo.purgeNode(nb, id);
    _recorderFor(nb)?.nodePurged(id);
  }

  /// The tree of any notebook, open or not.
  List<TreeNode> importNodes(String nb) => _repo.loadNodes(nb);

  /// Run [body] as ONE transaction. Import writes hundreds of pages; without
  /// this each would pay its own commit.
  T importBatch<T>(String nb, T Function() body) =>
      _repo.runInTransaction(nb, body);

  /// Create the notebook an import targets. Unlike [createNotebook] this does
  /// not switch to it or flush the current page: the importer builds the whole
  /// notebook first and only then calls [selectNotebook], which flushes. The
  /// asymmetry is deliberate — switching mid-import would show the user a
  /// half-built notebook — and it is safe only because of that later switch.
  Future<NotebookRef> importCreateNotebook(String title) =>
      _repo.createNotebook(title);

  /// Shared so toolbar/shortcuts can drive zoom (style guide §8.2).
  final canvas = CanvasController();

  /// RepaintBoundary key for whole-page capture (PDF export).
  final canvasKey = GlobalKey();

  // Workspace / navigation
  String? notebookId;

  List<TreeNode> _nodes = [];

  /// The current notebook's tree, ordered by position.
  List<TreeNode> get nodes => _nodes;
  set nodes(List<TreeNode> v) {
    _nodes = v;
    nodesRevision++;
  }

  /// Bumped whenever the tree changes shape *or* a node's rendered fields
  /// change. The navigator memoises its widget subtree on this, so typing in a
  /// page no longer rebuilds every section and page tile (§7a.6).
  int nodesRevision = 0;

  /// Call after mutating a [TreeNode] in place (rename, indent) — those don't
  /// replace the list, so the setter above wouldn't notice.
  void bumpNodes() => nodesRevision++;

  String? pageId;
  final Set<String> collapsedGroups = {};

  // Navigator (stacked): the focused section, whose pages fill the lower zone.
  String? activeSectionId;
  double navSplit = 0.38; // sections/pages height ratio (0..1)

  TreeNode? get activeSection => node(activeSectionId);

  void setNavSplit(double v) {
    navSplit = v.clamp(0.15, 0.7);
    _repo.setSetting('navSplit', navSplit);
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

  // ── Tags (TEXT-5) ────────────────────────────────────────────────────

  /// Apply or remove [kind] on the line the caret is in, for the block being
  /// edited (or the selected one).
  ///
  /// Toggling is per (line, kind): applying the same tag to the same line
  /// removes it, which is what a toolbar button that shows its own state has
  /// to do.
  void toggleTagOnSelection(TagKind kind, {int? line}) {
    final b = blocks.where((x) => x.id == (editingBlockId ?? selectedBlockId))
        .firstOrNull;
    if (b == null || b.type != BlockType.text) return;
    final idx = line ?? _caretLine(b);
    pushUndo();
    final tags = [...NoteTag.listFrom(b.content)];
    final at = tags.indexWhere((t) => t.line == idx && t.kind == kind);
    if (at >= 0) {
      tags.removeAt(at);
    } else {
      tags.add(NoteTag(
          kind: kind,
          line: idx,
          checked: kind == TagKind.todo ? false : null));
    }
    NoteTag.writeInto(b.content, tags);
    updateBlock(b);
    docRevision++;
    notifyListeners();
  }

  /// Flip a to-do tag's completion.
  void setTagChecked(String blockId, int line, bool checked) {
    final b = blocks.where((x) => x.id == blockId).firstOrNull;
    if (b == null) return;
    pushUndo();
    final tags = [
      for (final t in NoteTag.listFrom(b.content))
        if (t.line == line && t.kind == TagKind.todo)
          t.copyWith(checked: checked)
        else
          t
    ];
    NoteTag.writeInto(b.content, tags);
    updateBlock(b);
    docRevision++;
    notifyListeners();
  }

  /// Tags on the caret's line, so the toolbar can show which are active.
  Set<TagKind> tagsAtCaret() {
    final b = blocks.where((x) => x.id == (editingBlockId ?? selectedBlockId))
        .firstOrNull;
    if (b == null || b.type != BlockType.text) return const {};
    final idx = _caretLine(b);
    return {
      for (final t in NoteTag.listFrom(b.content))
        if (t.line == idx) t.kind
    };
  }

  /// Which line the caret sits on, so a tag lands where the user is looking.
  /// Falls back to line 0 when nothing is being edited (a tag applied to a
  /// merely-selected block is a tag on its first line).
  int _caretLine(Block b) {
    final ctl = activeEditor?.block.id == b.id ? activeEditor?.controller : null;
    final text = b.content['text'] as String? ?? '';
    if (ctl == null || !ctl.selection.isValid) return 0;
    final at = ctl.selection.baseOffset.clamp(0, text.length);
    return '\n'.allMatches(text.substring(0, at)).length;
  }

  /// Every tagged line in the notebook, for the find-tags rollup.
  ///
  /// Scans page mirrors rather than a maintained index: same reasoning as
  /// notebook-wide search — one source of truth beats an index that can drift,
  /// until it measurably hurts.
  List<({String pageId, String pageTitle, NoteTag tag, String text})>
      allTags() {
    if (notebookId == null) return const [];
    final out = <({String pageId, String pageTitle, NoteTag tag, String text})>[];
    for (final n in nodes.where((n) => n.kind == NodeKind.page)) {
      // The open page's in-memory blocks are fresher than the container.
      final blocksOf = n.id == pageId ? blocks : readPage(n.id).blocks;
      for (final b in blocksOf) {
        if (b.type != BlockType.text) continue;
        final tags = NoteTag.listFrom(b.content);
        if (tags.isEmpty) continue;
        final lines = (b.content['text'] as String? ?? '').split('\n');
        for (final t in tags) {
          out.add((
            pageId: n.id,
            pageTitle: n.title,
            tag: t,
            text: t.line < lines.length ? lines[t.line].trim() : '',
          ));
        }
      }
    }
    return out;
  }

  bool showTagsPanel = false;
  void toggleTagsPanel() {
    showTagsPanel = !showTagsPanel;
    notifyListeners();
  }

  // ── Favourites & recents (ORG-10) ────────────────────────────────────
  //
  // Keys are '<notebookId>:<pageId>'. Settings are WORKSPACE-scoped, so a bare
  // page id would collide across notebooks and dangle after one is deleted.

  final Set<String> _favourites = {};
  final List<String> _recents = [];

  static const _recentsCap = 20;

  String _pageKey(String pageId, [String? nb]) => '${nb ?? notebookId}:$pageId';

  bool isFavourite(String pageId) => _favourites.contains(_pageKey(pageId));

  /// Favourite page ids in THIS notebook, in tree order.
  List<TreeNode> favouritePages() => [
        for (final n in nodes)
          if (n.kind == NodeKind.page && _favourites.contains(_pageKey(n.id))) n
      ];

  void toggleFavourite(String pageId) {
    final k = _pageKey(pageId);
    _favourites.contains(k) ? _favourites.remove(k) : _favourites.add(k);
    _repo.setSetting('favourites', _favourites.toList());
    notifyListeners();
  }

  /// Recently visited pages in this notebook, most recent first.
  List<TreeNode> recentPages({int max = 8}) {
    final out = <TreeNode>[];
    for (final k in _recents) {
      final parts = k.split(':');
      if (parts.length != 2 || parts[0] != notebookId) continue;
      final n = node(parts[1]);
      if (n != null) out.add(n);
      if (out.length >= max) break;
    }
    return out;
  }

  void _recordRecent(String pageId) {
    final k = _pageKey(pageId);
    _recents.remove(k);
    _recents.insert(0, k);
    if (_recents.length > _recentsCap) {
      _recents.removeRange(_recentsCap, _recents.length);
    }
    _repo.setSetting('recentPages', _recents);
  }

  /// Sort a section's pages by title or by last edit (ORG-8).
  ///
  /// Subpages move WITH their parent: a page carries the deeper-level pages
  /// that follow it, or sorting would silently reparent every subpage in the
  /// section to whatever landed above it.
  void sortSection(String sectionId, {required bool byTitle}) {
    final pages = nodes
        .where((n) => n.kind == NodeKind.page && n.parentId == sectionId)
        .toList();
    if (pages.length < 2) return;
    // Group each top-level page with its contiguous deeper-level run.
    final groups = <List<TreeNode>>[];
    for (final p in pages) {
      if (p.level == 0 || groups.isEmpty) {
        groups.add([p]);
      } else {
        groups.last.add(p);
      }
    }
    groups.sort((a, b) => byTitle
        ? a.first.title.toLowerCase().compareTo(b.first.title.toLowerCase())
        : b.first.updatedAt.compareTo(a.first.updatedAt));
    var seq = nowMs();
    for (final g in groups) {
      for (final n in g) {
        n.position = 'a${(seq++).toString().padLeft(15, '0')}';
        _putNode(notebookId!, n);
      }
    }
    reloadNodes();
    notifyListeners();
  }

  /// Spell check (TEXT-11). English-only for v0.2 — the bundled wordlist is
  /// en-US, and non-English dictionaries are a recorded follow-up rather than
  /// a half-built option here.
  bool spellCheckEnabled = true;

  void setSpellCheck(bool v) {
    spellCheckEnabled = v;
    _repo.setSetting('spellCheck', v);
    // Re-open the editing session so the change is visible immediately rather
    // than at the next block.
    docRevision++;
    notifyListeners();
  }

  /// Eraser behaviour (INK-6). Session-scoped like tool/penSize — a mode, not
  /// a preference.
  EraserMode eraserMode = EraserMode.area;

  void setEraserMode(EraserMode m) {
    eraserMode = m;
    notifyListeners();
  }

  /// Whether a finger draws (INK-1). Until 2026-07-27 every touch was routed to
  /// pan unconditionally, which meant ink was unreachable on a touch-only
  /// tablet — palm rejection implemented as "fingers never draw" rather than
  /// "fingers don't draw *while a pen is in use*".
  TouchDrawing touchDrawing = TouchDrawing.auto;

  void setTouchDrawing(TouchDrawing v) {
    touchDrawing = v;
    _repo.setSetting('touchDrawing', v.name);
    notifyListeners();
  }

  // True while a block is being dragged — the canvas shows a faint grid then.
  bool draggingBlock = false;
  void setDragging(bool v) {
    if (draggingBlock == v) return;
    draggingBlock = v;
    notifyListeners();
  }

  // Collapse state (OneNote-style hierarchy folding). Sections no longer
  // collapse — the stacked navigator shows one section's pages at a time, so
  // the old per-section collapse set had no readers once the tree layout went.
  final Set<String> collapsedPages = {};

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
    _repo.setSetting('themeMode', m.name); // persist (§7a.5)
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
    _repo.setSetting('customColors', customColors);
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

  /// The font size of the text block being edited, in logical px, or null when
  /// it uses the default. Imported OneNote boxes carry an explicit size.
  double? get activeBlockFontSize {
    final id = editingBlockId;
    if (id == null) return null;
    final b = blocks.where((x) => x.id == id).firstOrNull;
    if (b == null || b.type != BlockType.text) return null;
    return (b.content['fontSize'] as num?)?.toDouble();
  }

  /// Set (or clear, with null) the font size of the text block being edited
  /// (TEXT-1). Sizes are offered in points and stored in the page's 120-dpi px.
  void setActiveBlockFontSize(double? pt) {
    final id = editingBlockId;
    if (id == null) return;
    final b = blocks.where((x) => x.id == id).firstOrNull;
    if (b == null || b.type != BlockType.text) return;
    pushUndo();
    if (pt == null) {
      b.content.remove('fontSize');
      b.content.remove('lineHeight');
    } else {
      b.content['fontSize'] = pt * 120.0 / 72.0;
      // Keep OneNote's pitch so a resized box still lines up with its
      // neighbours (see `oneNoteLineHeight`).
      b.content['lineHeight'] = oneNoteLineHeight;
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
    final tm = _repo.getSetting('themeMode') as String?;
    if (tm != null) themeMode = ThemeMode.values.asNameMap()[tm] ?? themeMode;
    final ns = _repo.getSetting('navSplit');
    if (ns is num) navSplit = ns.toDouble().clamp(0.15, 0.7);
    final sc = _repo.getSetting('spellCheck');
    if (sc is bool) spellCheckEnabled = sc;
    final fav = _repo.getSetting('favourites');
    if (fav is List) _favourites.addAll(fav.cast<String>());
    final rec = _repo.getSetting('recentPages');
    if (rec is List) _recents.addAll(rec.cast<String>());
    final td = _repo.getSetting('touchDrawing') as String?;
    if (td != null) {
      touchDrawing = TouchDrawing.values.asNameMap()[td] ?? touchDrawing;
    }
    final cc = _repo.getSetting('customColors');
    if (cc is List) customColors.addAll(cc.cast<String>());
    final vm = _repo.getSetting('viewMemory');
    if (vm is Map) {
      vm.forEach((k, v) {
        if (v is List && v.length == 3) {
          _viewMemory[k as String] =
              [for (final x in v) (x as num).toDouble()];
        }
      });
    }
    final lastNb = _repo.getSetting('lastNotebook') as String?;
    notebookId = _repo.notebooks.any((n) => n.id == lastNb)
        ? lastNb!
        : _repo.notebooks.first.id;
    // Clear out anything that has outlived the recycle-bin retention window.
    await _repo.purgeExpiredNotebooks();
    _repo.purgeExpiredNodes(notebookId!);
    reloadNodes();
    final lastPage = _repo.getSetting('lastPage') as String?;
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
    _repo.setSetting('viewMemory', _viewMemory);
    _repo.setSetting('lastNotebook', notebookId);
    _repo.setSetting('lastPage', pageId);
  }

  Future<void> _loadNotebook() async {
    reloadNodes();
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
    final ref = await _repo.createNotebook(title);
    await selectNotebook(ref.id);
  }

  Future<void> renameNotebook(String id, String title) async {
    await _repo.renameNotebook(id, title);
    _recorderFor(id)?.notebookMeta({'title': title});
    notifyListeners();
  }

  /// Duplicate a notebook (contents included) without switching to it.
  Future<NotebookRef> duplicateNotebook(String id) async {
    await flushSave(); // the copy is a byte copy — settle pending writes first
    final ref = await _repo.duplicateNotebook(id);
    notifyListeners();
    return ref;
  }

  ({int sections, int pages}) notebookCounts(String id) =>
      _repo.notebookCounts(id);

  /// Soft-delete a notebook to the recycle bin. Refuses the last one (there's
  /// always somewhere to be). Returns false if it couldn't (only notebook).
  Future<bool> deleteNotebook(String id) async {
    if (_repo.notebooks.length <= 1) return false;
    await flushSave();
    final wasCurrent = id == notebookId;
    await _repo.trashNotebook(id);
    if (wasCurrent) {
      notebookId = _repo.notebooks.first.id;
      await _loadNotebook();
    }
    notifyListeners();
    return true;
  }

  List<NotebookRef> get trashedNotebooks => _repo.trashedNotebooks;

  /// How long trashed items live before auto-deletion (recycle-bin retention).
  int get recycleRetentionDays => Repository.recycleRetentionDays;

  /// Sweep expired recycle-bin entries (notebooks + the current notebook's
  /// nodes). Runs at startup and whenever the recycle bin is opened.
  Future<void> purgeExpiredTrash() async {
    await _repo.purgeExpiredNotebooks();
    if (notebookId != null) _repo.purgeExpiredNodes(notebookId!);
    notifyListeners();
  }

  Future<void> restoreNotebook(String id) async {
    await _repo.restoreNotebook(id);
    notifyListeners();
  }

  Future<void> purgeNotebook(String id) async {
    await _repo.purgeNotebook(id);
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
      _recordRecent(id);
    }
    docRevision++;
    _persistSession();
    notifyListeners();
  }

  // ── Version history (SYNC-8) ───────────────────────────────────────────

  List<int> pageVersions() =>
      pageId == null ? [] : _repo.listVersions(notebookId!, pageId!);

  Future<void> restoreVersion(int at) async {
    if (pageId == null) return;
    final json = _repo.versionJson(notebookId!, pageId!, at);
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

  /// Built-ins first, then the user's own. A user template that shares a
  /// built-in's name shadows it (their content wins in [applyTemplate]), so
  /// customising a built-in is just "save under the same name".
  List<String> templateNames() {
    final t = _repo.getSetting('templates');
    final user = t is Map ? t.keys.cast<String>().toList() : <String>[];
    return [
      ...builtinTemplates.keys,
      ...user.where((n) => !builtinTemplates.containsKey(n)),
    ];
  }

  void saveCurrentAsTemplate(String name) {
    final t = (_repo.getSetting('templates') as Map?)?.cast<String, dynamic>() ?? {};
    t[name] = jsonEncode({
      'page': pageProps.toJson(),
      'blocks': [for (final b in blocks) b.toJson()],
    });
    _repo.setSetting('templates', t);
    notifyListeners();
  }

  void applyTemplate(String name) {
    final t = _repo.getSetting('templates');
    // User template first so a same-named save shadows the built-in.
    final raw = (t is Map ? t[name] as String? : null) ?? builtinTemplates[name];
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
    final n = _putNode(
        notebookId!,
        TreeNode(
            kind: NodeKind.section,
            parentId: groupId,
            title: 'Section ${count + 1}',
            color: _sectionColors[count % _sectionColors.length],
            position: _nextPosition()));
    reloadNodes();
    await addPage(sectionId: n.id);
  }

  void addSectionGroup() {
    final count = nodes.where((n) => n.kind == NodeKind.sectionGroup).length;
    _putNode(
        notebookId!,
        TreeNode(
            kind: NodeKind.sectionGroup,
            title: 'Group ${count + 1}',
            position: _nextPosition()));
    reloadNodes();
    notifyListeners();
  }

  Future<void> addPage({String? sectionId}) async {
    sectionId ??= sectionOf(pageId) ??
        nodes.where((n) => n.kind == NodeKind.section).firstOrNull?.id;
    if (sectionId == null) return;
    final n = _putNode(
        notebookId!,
        TreeNode(
            kind: NodeKind.page,
            parentId: sectionId,
            title: 'Untitled page',
            position: _nextPosition()));
    reloadNodes();
    await selectPage(n.id);
    pendingTitleEdit = n.id; // cursor lands in the title (OneNote behaviour)
    notifyListeners();
  }

  void renameNode(String id, String title) {
    final n = node(id);
    if (n == null) return; // deleted while a menu was open
    n.title = title;
    _putNode(notebookId!, n);
    bumpNodes();
    notifyListeners();
  }

  /// Subpage indent (ORG-6): level 0..2.
  void indentPage(String id, int delta) {
    final n = node(id);
    if (n == null || n.kind != NodeKind.page) return;
    n.level = (n.level + delta).clamp(0, 2);
    _putNode(notebookId!, n);
    bumpNodes();
    notifyListeners();
  }

  /// Reorder among siblings (ORG-2, menu-driven for MVP).
  void moveNode(String id, int delta) {
    final n = node(id);
    if (n == null) return;
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
    _putNode(notebookId!, n);
    _putNode(notebookId!, other);
    reloadNodes();
    notifyListeners();
  }

  void moveSectionToGroup(String sectionId, String? groupId) {
    final n = node(sectionId);
    if (n == null || n.kind != NodeKind.section) return;
    n.parentId = groupId;
    _putNode(notebookId!, n);
    reloadNodes();
    notifyListeners();
  }

  TreeNode? node(String? id) =>
      id == null ? null : nodes.where((n) => n.id == id).firstOrNull;

  // ── Recycle bin (ORG-7) ────────────────────────────────────────────────

  List<({String id, String kind, String title, int deletedAt})>
      deletedNodes() => _repo.loadDeletedNodes(notebookId!);

  Future<void> restoreDeleted(String id) async {
    _repo.restoreNode(notebookId!, id);
    // Restore is the ONLY thing that clears a delete (ADR-0006 §6a.3). An edit
    // must never resurrect a deleted node, or "delete wins" would silently
    // become "whichever device wrote last wins".
    _recorderFor(notebookId!)?.nodeRestored(id);
    reloadNodes();
    notifyListeners();
  }

  void purgeDeleted(String id) {
    _repo.purgeNode(notebookId!, id);
    _recorderFor(notebookId!)?.nodePurged(id);
    notifyListeners();
  }

  // ── Backlinks (TEXT-8) ─────────────────────────────────────────────────

  /// Page outline panel (TEXT-10).
  bool showTocPanel = false;
  void toggleTocPanel() {
    showTocPanel = !showTocPanel;
    notifyListeners();
  }

  /// Headings on the current page, in reading order, for the outline panel.
  ///
  /// Cached on the same key as the links panel: without it, the panel rescans
  /// every block's Markdown on each notify — i.e. per keystroke — which is the
  /// exact cost the memoised navigator exists to avoid.
  ({String key, List<({String blockId, int level, String text})> items})?
      _tocCache;

  List<({String blockId, int level, String text})> pageOutline() {
    final key = '$pageId#$docRevision';
    final cached = _tocCache;
    if (cached != null && cached.key == key) return cached.items;
    final items = <({String blockId, int level, String text})>[];
    final ordered = [...blocks.where((b) => b.type == BlockType.text)]
      ..sort((a, b) => a.y.compareTo(b.y));
    for (final b in ordered) {
      final text = b.content['text'];
      if (text is! String) continue;
      for (final line in text.split('\n')) {
        final m = RegExp(r'^(#{1,3})\s+(.+)$').firstMatch(line.trimLeft());
        if (m == null) continue;
        items.add((
          blockId: b.id,
          level: m.group(1)!.length,
          text: m.group(2)!.trim(),
        ));
      }
    }
    _tocCache = (key: key, items: items);
    return items;
  }

  bool showLinksPanel = false;
  void toggleLinksPanel() {
    showLinksPanel = !showLinksPanel;
    notifyListeners();
  }

  // The links panel is rebuilt on every notify while it's open, and both of
  // these are expensive: one is a synchronous SQLite query on the UI thread, the
  // other scans every text block. Cache them against (page, docRevision,
  // nodesRevision) so a keystroke doesn't re-run either.
  ({String key, List<TreeNode> back, List<TreeNode> out})? _linkCache;
  static final _outgoingLinkRe = RegExp(r'\[\[([^\]|]+)(?:\|([^\]]+))?\]\]');

  void _ensureLinks() {
    final key = '$pageId#$docRevision#$nodesRevision#${_dirty ? 1 : 0}';
    if (_linkCache?.key == key) return;
    final back = pageId == null
        ? <TreeNode>[]
        : _repo
            .backlinkPageIds(notebookId!, pageId!)
            .map(node)
            .whereType<TreeNode>()
            .toList();
    // Outgoing: `[[Title|id]]` resolves by id, a bare `[[Title]]` by title —
    // the panel used to ignore the bare form entirely.
    final out = <String, TreeNode>{};
    for (final b in blocks.where((b) => b.type == BlockType.text)) {
      for (final m
          in _outgoingLinkRe.allMatches(b.content['text'] as String? ?? '')) {
        final target = m.group(2) != null
            ? node(m.group(2))
            : pageByTitle(m.group(1)!);
        if (target != null) out[target.id] = target;
      }
    }
    _linkCache = (key: key, back: back, out: out.values.toList());
  }

  List<TreeNode> backlinksForCurrent() {
    _ensureLinks();
    return _linkCache!.back;
  }

  /// Outgoing wiki-links found in the current page's text blocks.
  List<TreeNode> outgoingLinksForCurrent() {
    _ensureLinks();
    return _linkCache!.out;
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
    _putNode(notebookId!, n);
    reloadNodes();
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
    _putNode(notebookId!, n);
    reloadNodes();
    notifyListeners();
  }

  void toggleGroupCollapsed(String id) {
    collapsedGroups.contains(id)
        ? collapsedGroups.remove(id)
        : collapsedGroups.add(id);
    notifyListeners();
  }

  Future<void> deleteNode(String id) async {
    _repo.softDeleteNode(notebookId!, id);
    _recorderFor(notebookId!)?.nodeDeleted(id);
    reloadNodes();
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

  void _jumpToMatch() => jumpToBlock(findMatches[findIndex]);

  /// Select a block and centre the view on it. Shared by find and the page
  /// outline so both behave identically.
  void jumpToBlock(String id) {
    final b = blocks.where((b) => b.id == id).firstOrNull;
    if (b == null) return;
    selectedIds
      ..clear()
      ..add(id);
    selectedBlockId = id;
    editingBlockId = null;
    final h = b.h ?? renderSizes[id]?.height ?? 60;
    canvas.centerOn(Offset(b.x + b.w / 2, b.y + h / 2));
    notifyListeners();
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

  /// The last save failure, or null when the last save succeeded. Surfaced in
  /// the status bar — a silent failed save used to read as "Saved".
  Object? saveError;

  Future<void> flushSave() async {
    _saveDebounce?.cancel();
    if (!_dirty || pageId == null || notebookId == null) return;
    // Keep `_dirty` TRUE until the write actually lands: clearing it first meant
    // a throwing save (disk full, DB locked) left the page marked clean and the
    // status bar claiming "Saved" while the change was never persisted.
    final id = pageId!, nb = notebookId!;
    try {
      // The engine owns persistence: version snapshot (throttled, SYNC-8) + the
      // mirror write, plus content-hash change-detection on the Rust engine (a
      // save whose hash is unchanged is skipped). See RustEngine/MirrorEngine.
      await engine.savePage(nb, id, blocks, pageProps);
      _dirty = false;
      saveError = null;
      // Record AFTER the container write succeeds, so the log never claims a
      // change the notebook doesn't have. The reverse order would be worse than
      // useless: rebuild-from-log would then differ from the container on every
      // failed save, and the divergence would look like a recording bug rather
      // than the disk error it is.
      //
      // The recorder diffs against its replayed state, so an autosave that
      // changed one block appends one op, not the whole page.
      _recorderFor(nb)?.page(id, blocks, pageProps);
    } catch (e) {
      // Stay dirty so the next edit (or exit flush) retries, and tell the user.
      saveError = e;
      notifyListeners();
      return;
    }
    // Keep session state fresh so closing the app never loses your place.
    _rememberView();
    _persistSession();
    notifyListeners();
  }

  /// Persist everything before the process goes away (window close, logout).
  /// Awaited by the app's [AppLifecycleListener]; without it, up to one debounce
  /// interval of edits was silently lost on every close.
  Future<void> shutdown() async {
    _saveDebounce?.cancel();
    try {
      await flushSave();
    } catch (_) {
      // Never block exit on a save failure — flushSave already recorded it.
    }
    _rememberView();
    _persistSession();
    await _repo.flushWorkspace(); // settle the debounced registry write
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    canvas.dispose();
    _repo.dispose();
    super.dispose();
  }
}
