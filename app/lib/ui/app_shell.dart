import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../canvas/media_drop.dart';
import '../canvas/page_canvas.dart';
import '../model/models.dart';
import '../model/tags.dart';
import '../core/onote_ffi.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'command_bar.dart';
import 'onboarding.dart';
import 'planner_panel.dart';
import 'side_panel.dart';
import 'sidebar.dart';
import '../export/print_page.dart';
import 'study_panel.dart';
import 'sync_dialog.dart';
import '../theme/tokens.dart';

/// Layout per style guide §5.4: navigator | (toolbar / canvas-as-hero / status).
///
/// Keyboard handling uses a global HardwareKeyboard handler rather than
/// widget-tree Shortcuts. This is deliberate: on desktop, Flutter's
/// EditableText inserts printable characters via the text-input channel and
/// does NOT consume the raw KeyDownEvent, so ancestor `Shortcuts` with
/// bare-letter activators (V/T/P/H/E …) *shadow* text fields — the exact bug
/// that made those letters untypeable. Here we detect whether a text field is
/// focused and, if so, handle only Escape and let every other key through.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.app});
  final AppState app;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    // Post-frame: the welcome flow needs a Navigator, and there isn't one
    // until this shell is mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowOnboarding(context, app);
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// True when a real text field (block editor, page title, find, or any
  /// dialog field) currently owns the keyboard.
  bool _editableFocused() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    var found = false;
    ctx.visitAncestorElements((e) {
      if (e.widget is EditableText) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    final k = e.logicalKey;
    final editable = _editableFocused();
    final ctrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    // Escape: close find / exit our editors / clear selection. Gated on our
    // own state so a dialog's own Escape-to-cancel still works.
    if (k == LogicalKeyboardKey.escape) {
      if (app.findOpen) {
        app.toggleFind();
        return true;
      }
      if (app.editingBlockId != null || app.titleEditing) {
        FocusManager.instance.primaryFocus?.unfocus();
        app.select(null);
        return true;
      }
      if (!editable && app.selectedIds.isNotEmpty) {
        app.select(null);
        return true;
      }
      return false;
    }

    // Navigator chords, BEFORE the editable early-return: none of these can
    // collide with typing (no field inserts a character for Ctrl+PageDown),
    // and OneNote users reach for them mid-sentence.
    if (ctrl) {
      if (k == LogicalKeyboardKey.pageDown) return _cyclePage(1);
      if (k == LogicalKeyboardKey.pageUp) return _cyclePage(-1);
      if (k == LogicalKeyboardKey.tab) return _cycleSection(shift ? -1 : 1);
      if (k == LogicalKeyboardKey.backslash) {
        app.toggleNavCollapsed();
        return true;
      }
    }

    // While typing: allow only formatting accelerators; everything else
    // flows to the field untouched.
    if (editable) {
      if (ctrl && app.activeEditor != null) {
        if (k == LogicalKeyboardKey.keyB) {
          app.wrapSelection('**');
          return true;
        }
        if (k == LogicalKeyboardKey.keyI) {
          app.wrapSelection('*');
          return true;
        }
        if (k == LogicalKeyboardKey.keyU) {
          app.wrapSelection('++'); // underline (TEXT-1)
          return true;
        }
        // Ctrl+Shift+C — flick the selection to the last colour and back.
        if (shift && k == LogicalKeyboardKey.keyC) {
          app.toggleTextColor();
          return true;
        }
        // Ctrl+1/2/3 — tag the caret's line. OneNote's own chords, so the
        // muscle memory a switching student already has keeps working.
        final tag = switch (k) {
          LogicalKeyboardKey.digit1 => TagKind.todo,
          LogicalKeyboardKey.digit2 => TagKind.important,
          LogicalKeyboardKey.digit3 => TagKind.question,
          LogicalKeyboardKey.digit4 => TagKind.remember,
          LogicalKeyboardKey.digit5 => TagKind.definition,
          _ => null,
        };
        if (tag != null) {
          app.toggleTagOnSelection(tag);
          return true;
        }
        // Ctrl+V with an IMAGE on the clipboard. Flutter's own paste handles
        // text only, so screenshot → click in the box → Ctrl+V silently did
        // nothing. Handled here only when there is an image; anything else
        // falls through to the field's own paste, because breaking plain-text
        // paste into a note would be a far worse bug than the one being fixed.
        if (k == LogicalKeyboardKey.keyV) {
          _pasteImageIntoEditor();
          return false; // never swallow the keystroke
        }
      }
      return false;
    }

    if (ctrl) {
      if (k == LogicalKeyboardKey.keyC) {
        if (app.selectedIds.isEmpty) return false;
        app.copySelectedBlocks();
        return true;
      }
      if (k == LogicalKeyboardKey.keyX) {
        if (app.selectedIds.isEmpty) return false;
        app.cutSelectedBlocks();
        return true;
      }
      if (k == LogicalKeyboardKey.keyV) {
        // System clipboard first (an image from a screenshot tool), our own
        // block clipboard second. The reverse order would make Ctrl+V paste a
        // stale block instead of the screenshot just taken — and copying a
        // block is far rarer than copying an image from elsewhere.
        _pasteFromSystemOrBlocks();
        return true;
      }
      if (k == LogicalKeyboardKey.keyF) {
        app.toggleFind();
        return true;
      }
      if (k == LogicalKeyboardKey.keyP) {
        // Muscle memory, and the reason P13 was worth doing at all: a student
        // printing a revision sheet reaches for Ctrl+P, not a menu. Unawaited
        // because the OS dialog owns the interaction from here.
        unawaited(printCurrentPage(app));
        return true;
      }
      if (k == LogicalKeyboardKey.keyZ && !shift) {
        app.undo();
        return true;
      }
      if ((k == LogicalKeyboardKey.keyZ && shift) ||
          k == LogicalKeyboardKey.keyY) {
        app.redo();
        return true;
      }
      if (k == LogicalKeyboardKey.keyD) {
        final s = app.selectedBlockId;
        if (s != null) app.duplicateBlock(s);
        return true;
      }
      if (k == LogicalKeyboardKey.equal || k == LogicalKeyboardKey.add) {
        app.canvas.setZoom(app.canvas.scale * 1.2);
        return true;
      }
      if (k == LogicalKeyboardKey.minus) {
        app.canvas.setZoom(app.canvas.scale / 1.2);
        return true;
      }
      if (k == LogicalKeyboardKey.digit0) {
        app.canvas.reset();
        return true;
      }
      return false;
    }

    // Bare keys — only reached when no text field is focused.
    if (k == LogicalKeyboardKey.keyV) return _tool(Tool.select);
    if (k == LogicalKeyboardKey.keyT) return _tool(Tool.text);
    if (k == LogicalKeyboardKey.keyP) return _tool(Tool.pen);
    if (k == LogicalKeyboardKey.keyH) return _tool(Tool.highlighter);
    if (k == LogicalKeyboardKey.keyE) return _tool(Tool.eraser);
    if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      if (app.selectedIds.isNotEmpty) {
        app.removeSelected();
        return true;
      }
    }
    return false;
  }

  bool _tool(Tool t) {
    app.setTool(t);
    return true;
  }

  /// Ctrl+PageDown / Ctrl+PageUp — the next/previous page in the active
  /// section, in the navigator's visible order. OneNote's own chords.
  /// Clamped at the ends rather than wrapping: wrapping silently teleports
  /// you from the last page to the first, which reads as "it jumped".
  bool _cyclePage(int dir) {
    final sec = app.activeSectionId;
    if (sec == null) return false;
    final pages = app.pagesOf(sec);
    if (pages.isEmpty) return false;
    final i = pages.indexWhere((n) => n.id == app.pageId);
    final next = pages[(i + dir).clamp(0, pages.length - 1)];
    if (next.id != app.pageId) app.selectPage(next.id);
    return true;
  }

  /// Ctrl+Tab / Ctrl+Shift+Tab — the next/previous section. Wrapping IS right
  /// here: cycling a ring of sections is the mental model, same as browser
  /// tabs.
  bool _cycleSection(int dir) {
    final secs =
        app.nodes.where((n) => n.kind == NodeKind.section).toList();
    if (secs.isEmpty) return false;
    var i = secs.indexWhere((n) => n.id == app.activeSectionId);
    if (i < 0) i = 0;
    app.activateSection(secs[(i + dir + secs.length) % secs.length].id);
    return true;
  }

  /// Ctrl+V while the caret is in a text box, when the clipboard holds an
  /// image: splice an in-flow reference at the caret.
  ///
  /// Deliberately fire-and-forget and never blocking: the keystroke is passed
  /// through to Flutter's own paste regardless, so a clipboard with both an
  /// image and text still pastes the text if the image read fails. In the
  /// normal case the image read wins the race by a frame and the text branch
  /// finds nothing to do.
  Future<void> _pasteImageIntoEditor() async {
    final ae = app.activeEditor;
    if (ae == null) return;
    final bytes = await readClipboardImage();
    if (bytes == null || !mounted) return;
    if (app.activeEditor?.block.id != ae.block.id) return; // moved on
    final hash = app.addBlob(bytes.bytes, bytes.mime);
    app.insertTextAtActiveCursor('\n![](sha256:$hash)\n');
    ae.block.content['autoWidth'] = false;
  }

  /// Ctrl+V on the canvas: system clipboard media if there is any, else our
  /// own copied blocks.
  Future<void> _pasteFromSystemOrBlocks() async {
    final at = app.canvas.screenToPage(Offset(
        app.canvas.viewport.width / 2, app.canvas.viewport.height / 2));
    final result = await pasteOntoCanvas(app, at,
        dark: Theme.of(context).brightness == Brightness.dark);
    if (result == PasteResult.nothing && app.canPasteBlocks) {
      app.pasteBlocks();
    }
  }

  /// Memoised navigator. The whole shell sits under one `ListenableBuilder`, so
  /// *every* notify — each keystroke (`markDirty`), each drag frame — used to
  /// rebuild the navigator too: three `nodes.where(...)` scans plus a nested
  /// per-group scan, and a fresh `_PageTile` (`DragTarget` + `Draggable` +
  /// `InkWell`) for every visible page. Returning the identical widget when
  /// nothing the navigator displays has changed lets Flutter skip that subtree
  /// entirely (§7a.6 keystroke-to-paint budget).
  Widget? _navCache;
  List<Object?>? _navKey;

  Widget _navigator() {
    final key = <Object?>[
      app.nodesRevision,
      app.pageId,
      app.activeSectionId,
      app.notebookId,
      app.notebooks.length,
      // The two-column layout's own state. Every piece of state the navigator
      // RENDERS must appear here, or the change paints only after something
      // else happens to invalidate the memo — a stale-not-broken failure that
      // passes a quick smoke test and fails in real use.
      app.navCollapsed,
      app.navSectionsW,
      app.navPagesW,
      app.navHome,
      // Collapse toggles, favourites, Home — bumped explicitly. A counter and
      // not the sets' lengths, because one collapse plus one expand between
      // frames leaves the length identical while the CONTENTS changed.
      app.navRevision,
    ];
    final cached = _navCache;
    if (cached != null && _navKey != null && _listEq(_navKey!, key)) {
      return cached;
    }
    _navKey = key;
    return _navCache = Sidebar(app: app);
  }

  static bool _listEq(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final page = app.nodes.where((n) => n.id == app.pageId).firstOrNull;
        return Scaffold(
          body: Row(
            children: [
              _navigator(),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  children: [
                    CommandBar(app: app),
                    if (app.findOpen) _FindBar(app: app),
                    // The breadcrumb is CONTEXT, not a second navigator
                    // (§7d). With the navigator expanded it repeats what is
                    // already on screen two inches to the left, so it spends a
                    // full-width row saying nothing. Collapsed — or on the
                    // rail — it is the only place the notebook and section are
                    // named, and it earns the row.
                    if (page != null && app.navCollapsed)
                      _PageHeader(app: app, page: page),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: page == null
                                ? _EmptyState(app: app)
                                : PageCanvas(
                                    key: ValueKey(app.pageId), state: app),
                          ),
                          if (app.showStudyPanel) ...[
                            const VerticalDivider(width: 1),
                            StudyPanel(app: app),
                          ],
                          if (app.showPlannerPanel) ...[
                            const VerticalDivider(width: 1),
                            PlannerPanel(app: app),
                          ],
                          if (app.showTagsPanel) ...[
                            const VerticalDivider(width: 1),
                            _TagsPanel(app: app),
                          ],
                          if (app.showTocPanel && page != null) ...[
                            const VerticalDivider(width: 1),
                            _TocPanel(app: app),
                          ],
                          if (app.showLinksPanel && page != null) ...[
                            const VerticalDivider(width: 1),
                            _LinksPanel(app: app),
                          ],
                        ],
                      ),
                    ),
                    _StatusBar(app: app),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Find-on-page bar (TEXT-7): live matches, next/prev cycles & centers.
class _FindBar extends StatefulWidget {
  const _FindBar({required this.app});
  final AppState app;

  @override
  State<_FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<_FindBar> {
  AppState get app => widget.app;

  /// Replace is opt-in: a permanently visible replace field doubles the height
  /// of the bar for a job most searches don't want.
  bool _showReplace = false;
  final _replaceCtl = TextEditingController();

  @override
  void dispose() {
    _replaceCtl.dispose();
    super.dispose();
  }

  void _replace({required bool all}) {
    final n = app.replaceAll(app.findQuery, _replaceCtl.text,
        onlyCurrent: !all);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(n == 0
            ? 'Nothing replaced'
            : 'Replaced $n occurrence${n == 1 ? '' : 's'}')));
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _findRow(context),
      if (_showReplace) _replaceRow(context),
    ]);
  }

  Widget _replaceRow(BuildContext context) => Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border:
              Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Row(children: [
          const SizedBox(width: 24),
          Expanded(
            child: TextField(
              controller: _replaceCtl,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Replace with…',
              ),
              style: const TextStyle(fontSize: 13),
              onSubmitted: (_) => _replace(all: false),
            ),
          ),
          TextButton(
            onPressed: app.findMatches.isEmpty ? null : () => _replace(all: false),
            child: const Text('Replace', style: TextStyle(fontSize: 12)),
          ),
          TextButton(
            onPressed: app.findMatches.isEmpty ? null : () => _replace(all: true),
            child: const Text('All', style: TextStyle(fontSize: 12)),
          ),
        ]),
      );

  Widget _findRow(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border:
            Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Find on this page…',
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: app.setFindQuery,
              onSubmitted: (_) => app.findNext(1),
            ),
          ),
          Text(
            app.findMatches.isEmpty
                ? (app.findQuery.isEmpty ? '' : 'No matches')
                : '${app.findIndex + 1} of ${app.findMatches.length}',
            style: TextStyle(fontSize: 12, color: context.surfaces.textSecondary),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: app.findMatches.isEmpty ? null : () => app.findNext(-1),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: app.findMatches.isEmpty ? null : () => app.findNext(1),
          ),
          IconButton(
            icon: Icon(
                _showReplace ? Icons.find_replace : Icons.find_replace_outlined,
                size: 18),
            visualDensity: VisualDensity.compact,
            isSelected: _showReplace,
            tooltip: 'Replace',
            onPressed: () => setState(() => _showReplace = !_showReplace),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            visualDensity: VisualDensity.compact,
            tooltip: 'Close (Esc)',
            onPressed: app.toggleFind,
          ),
        ],
      ),
    );
  }
}

/// Slim breadcrumb — the editable TITLE lives in the page itself.
class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.app, required this.page});
  final AppState app;
  final TreeNode page;

  @override
  Widget build(BuildContext context) {
    final section = app.node(page.parentId ?? '');
    final notebook =
        app.notebooks.firstWhere((n) => n.id == app.notebookId);
    final crumbStyle =
        TextStyle(fontSize: 12, color: context.surfaces.textSecondary);
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border:
            Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Text(notebook.title, style: crumbStyle),
          if (section != null) ...[
            Text('  ›  ', style: crumbStyle),
            Text(section.title, style: crumbStyle),
          ],
        ],
      ),
    );
  }
}

/// Right-side links panel: incoming backlinks + outgoing links (TEXT-8).
/// Find tags (TEXT-5): every tagged line in the notebook, grouped by tag.
///
/// This is half the value of tags in OneNote — marking a line is only useful
/// if you can later ask "what did I mark?". Scanning page mirrors rather than
/// maintaining an index, for the same reason as notebook-wide search: one
/// source of truth beats an index that can silently drift.
class _TagsPanel extends StatelessWidget {
  const _TagsPanel({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final all = app.allTags();
    final byKind = <TagKind, List<TaggedLine>>{};
    for (final e in all) {
      byKind.putIfAbsent(e.tag.kind, () => []).add(e);
    }
    return SidePanel(
      title: SidePanelKind.tags.label,
      icon: Icons.label_outline,
      onClose: app.closePanel,
      child: all.isEmpty
          ? PanelEmpty(
              headline: 'No tags in this notebook yet.',
              body: 'Tags mark a line — to do, important, question, '
                  'definition — so you can find it again, revise from it, or '
                  'give it a deadline.',
              actions: [
                PanelAction(
                    icon: Icons.label_outline,
                    label: 'Tag the line you are on',
                    onTap: () => app.toggleTagOnSelection(TagKind.todo)),
              ],
            )
          : ListView(
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  for (final kind in byKind.keys)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                          child: Row(children: [
                            Icon(kind.icon, size: 16, color: kind.color),
                            const SizedBox(width: 5),
                            Text('${kind.label}  (${byKind[kind]!.length})',
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                        for (final e in byKind[kind]!)
                          InkWell(
                            onTap: () => app.selectPage(e.pageId),
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(30, 3, 12, 3),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      e.text.isEmpty ? '(empty line)' : e.text,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 12,
                                          decoration:
                                              (e.tag.checked ?? false)
                                                  ? TextDecoration.lineThrough
                                                  : null,
                                          color: (e.tag.checked ?? false)
                                              ? context.surfaces.textSecondary
                                              : null)),
                                  Text(e.pageTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: context.surfaces.textSecondary)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
    );
  }
}

/// Page outline (TEXT-10): the current page's headings, click to jump.
///
/// Deliberately derived from the Markdown rather than stored: a heading IS
/// `# text` in a text block, so an outline that could disagree with the page
/// would be a second source of truth for no gain.
class _TocPanel extends StatelessWidget {
  const _TocPanel({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final items = app.pageOutline();
    return SidePanel(
      title: SidePanelKind.outline.label,
      icon: Icons.toc,
      onClose: app.closePanel,
      child: items.isEmpty
          ? const PanelEmpty(
              headline: 'No headings on this page.',
              body: 'Start a line with # to make a heading — the outline '
                  'follows the page, so there is nothing separate to keep up '
                  'to date.',
            )
          : ListView.builder(
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final it = items[i];
                  return InkWell(
                    onTap: () => app.jumpToBlock(it.blockId),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                          12.0 + (it.level - 1) * 14.0, 5, 12, 5),
                      child: Text(
                        it.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: it.level == 1 ? 13 : 12,
                          fontWeight: it.level == 1
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  );
                },
              ),
    );
  }
}

class _LinksPanel extends StatelessWidget {
  const _LinksPanel({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final backlinks = app.backlinksForCurrent();
    final outgoing = app.outgoingLinksForCurrent();

    Widget section(String label, IconData icon, List<TreeNode> pages,
        String empty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                OnoteSpace.x5, OnoteSpace.x5, OnoteSpace.x5, OnoteSpace.x1),
            child: Row(children: [
              Icon(icon,
                  size: OnoteIcon.sm, color: context.surfaces.textSecondary),
              const SizedBox(width: OnoteSpace.x3),
              Expanded(
                child: Text(label.toUpperCase(),
                    style: OnoteType.overline
                        .copyWith(color: context.surfaces.textSecondary)),
              ),
              // A plain count, not a badge: a badge in a list header is
              // decoration, and this number is never actionable (§7e).
              Text('${pages.length}',
                  style: OnoteType.caption
                      .copyWith(color: context.surfaces.textSecondary)),
            ]),
          ),
          if (pages.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Text(empty,
                  style:
                      TextStyle(fontSize: 12, color: context.surfaces.textSecondary)),
            )
          else
            for (final p in pages)
              InkWell(
                onTap: () => app.selectPage(p.id),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(children: [
                    Icon(Icons.description_outlined,
                        size: 16, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(p.title,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13))),
                  ]),
                ),
              ),
        ],
      );
    }

    return SidePanel(
      title: SidePanelKind.links.label,
      icon: Icons.account_tree_outlined,
      onClose: app.closePanel,
      child: ListView(
        children: [
          section('Linked from', Icons.call_received, backlinks,
              'No pages link here yet.'),
          const SizedBox(height: OnoteSpace.x4),
          section('Links to', Icons.call_made, outgoing,
              'This page links nowhere yet.'),
        ],
      ),
    );
  }
}

/// One line naming the loaded core's build, for the engine tooltip.
String _coreBuildLine() {
  final id = OnoteCore.instance?.buildId;
  if (id == null) {
    return 'This library predates the build stamp — it is an OLD core. '
        'Rebuild it (flutter build, or sync-core.bat on Windows) before '
        'trusting any importer or repair behaviour.';
  }
  final t = id.built.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  // The path matters as much as the timestamp: the loader picks the NEWEST of
  // several candidates, so "which file won" is half of any stale-library
  // question.
  final from = OnoteCore.loadedFrom;
  return 'Core built ${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)} from ${id.commit}.'
      '${from == null ? '' : '\nLoaded: $from'}';
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final saved = !app.hasUnsavedChanges;
    final rust = app.engineLabel.startsWith('Rust');
    final hash = app.pageContentHash;
    // A failed save must never read as "Saved" — it stays dirty and says so.
    final failed = app.saveError != null;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Tooltip(
            message: failed
                ? "Openote couldn't save this page:\n${app.saveError}\n\n"
                    'Your changes are still in memory and will be retried on the '
                    'next edit. Check free disk space and that the notebook file '
                    'is not open elsewhere.'
                : saved
                    ? 'This page is saved to your local .onote file.'
                    : 'Saving…',
            child: Row(children: [
              Icon(
                  failed
                      ? Icons.error_outline
                      : saved
                          ? Icons.check_circle_outline
                          : Icons.sync,
                  size: OnoteIcon.sm,
                  color: failed
                      ? OnoteColors.danger
                      : saved
                          ? OnoteColors.success
                          : context.surfaces.textSecondary),
              const SizedBox(width: 5),
              Text(
                  failed
                      ? "Couldn't save — changes kept in memory"
                      : saved
                          ? 'Saved on this device'
                          : 'Saving…',
                  style: TextStyle(
                      fontSize: 11,
                      color: failed
                          ? OnoteColors.danger
                          : context.surfaces.textSecondary)),
            ]),
          ),
          const SizedBox(width: 12),
          // Sync (ADR-0006). Shown only once a second device has touched this
          // notebook — until then there is nothing to say, and a permanent
          // "1 device" chip would be noise.
          if (app.notebookId != null) _SyncChip(app: app),
          const SizedBox(width: 12),
          // Active compute engine (§ADR-0002): green chip when the Rust core
          // is linked, with the live page content-hash it computed on save.
          Tooltip(
            // The build stamp is here because the stale-library trap keeps
            // costing real time: the app loads a compiled artefact, so being on
            // the right branch says nothing about what is actually running.
            // Importer and repair fixes live in that library, so "I pulled and
            // it still does the old thing" is answered by reading this line.
            message: rust
                ? 'The Rust core (onote-core) is linked and computing this '
                    "page's content hash on save.\n${_coreBuildLine()}"
                : 'Running the pure-Dart engine. Build the onote-core library '
                    'to link the Rust core.',
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.memory,
                  size: 16,
                  color: rust ? OnoteColors.success : context.surfaces.textSecondary),
              const SizedBox(width: 4),
              Text(
                rust && hash != null && hash.length >= 8
                    ? '${app.engineLabel} · ${hash.substring(0, 8)}'
                    : app.engineLabel,
                style: TextStyle(
                    fontSize: 11,
                    color: rust ? OnoteColors.success : context.surfaces.textSecondary),
              ),
            ]),
          ),
          const Spacer(),
          // The cheat-sheet (§7a.4), dropped whole rather than ellipsised
          // (§7d). Truncating it produces "V select · T text · P pen · H…",
          // which is not a shorter version of the message — it is a different,
          // useless one, and it also drags the state cluster on its left into
          // truncation with it. Below the threshold the shortcuts are still on
          // every button's tooltip, which is where they are actually read.
          Flexible(
            child: _DropIfTight(
              text: 'V select · T text · P pen · H highlight · E erase · '
                  'Ctrl+Z undo · Ctrl+scroll zoom',
              style: OnoteType.caption
                  .copyWith(color: context.surfaces.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders [text] only when it fits whole, and nothing at all when it doesn't.
///
/// The status bar's rule (§7d): **drop, never truncate.** "V select · T text ·
/// P pen · H…" is not a shorter version of the cheat-sheet, it is a different
/// and useless message — and letting it ellipsise also drags the state cluster
/// beside it into competing for the same pixels.
///
/// Measured against the constraints this actually receives rather than against
/// the window width: the right-hand panel slot takes 320px out of the row, so
/// a window-width threshold is wrong exactly when a panel is open.
class _DropIfTight extends StatelessWidget {
  const _DropIfTight({required this.text, required this.style});
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          final tp = TextPainter(
            text: TextSpan(text: text, style: style),
            maxLines: 1,
            textDirection: Directionality.of(context),
          )..layout();
          if (tp.width > c.maxWidth) return const SizedBox.shrink();
          return Text(text, style: style, maxLines: 1, softWrap: false);
        },
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_stories_outlined,
              size: 44, color: context.surfaces.textSecondary),
          const SizedBox(height: 12),
          const Text('An open page awaits',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            'Everything you make here lives on your device,\nin an open format you own.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: context.surfaces.textSecondary),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.note_add_outlined, size: 18),
            label: const Text('Create your first page'),
            onPressed: () => app.addPage(),
          ),
        ],
      ),
    );
  }
}

/// Sync state in the status bar.
///
/// Driven by [SyncStatus] — where the notebook LIVES — rather than by how many
/// devices have written logs. The old chip used the device count as a proxy,
/// so a notebook correctly placed in Google Drive still read "Not synced yet"
/// until a second machine appeared: the app disagreeing with what the user had
/// just successfully done.
class _SyncChip extends StatelessWidget {
  const _SyncChip({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final nb = app.notebookId!;
    final s = app.syncStatus(nb);
    final scheme = Theme.of(context).colorScheme;
    // Green once it is actually somewhere that syncs; grey when it is only on
    // this machine. The colour is the whole at-a-glance answer.
    final color = s.isSynced ? OnoteColors.success : context.surfaces.textSecondary;

    return Tooltip(
      message: _tooltip(s),
      child: InkWell(
        onTap: () => showSyncDialog(context, app),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(s.icon, size: 16, color: color),
            const SizedBox(width: 5),
            Text(s.label, style: TextStyle(fontSize: 11, color: color)),
            if (s.isSynced && s.hasOtherDevices) ...[
              const SizedBox(width: 6),
              InkWell(
                onTap: () async {
                  final n = await app.syncPull(nb);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(n == 0
                          ? 'Already up to date.'
                          : 'Pulled $n change${n == 1 ? '' : 's'}.')));
                },
                child: Icon(Icons.refresh, size: 16, color: scheme.primary),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  String _tooltip(SyncStatus s) {
    final b = StringBuffer();
    if (s.isSynced) {
      b.write('Syncing through ${s.folder!.name}.\n');
      b.write(s.hasOtherDevices
          ? 'Edited on ${s.devices} devices — changes arrive automatically.'
          : 'Open this notebook on another device to sync it.');
    } else {
      b.write('Only on this computer.\n'
          'Click to put it in a folder your cloud already syncs.');
    }
    if (s.mirrors > 0) {
      b.write('\n${s.mirrors} backup destination${s.mirrors == 1 ? '' : 's'}.');
    }
    return b.toString();
  }
}
