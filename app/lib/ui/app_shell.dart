import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../canvas/media_drop.dart';
import '../canvas/page_canvas.dart';
import '../model/models.dart';
import '../model/tags.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'command_bar.dart';
import 'sidebar.dart';

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

  /// Ctrl+V on the canvas: system clipboard media if there is any, else our
  /// own copied blocks.
  Future<void> _pasteFromSystemOrBlocks() async {
    final at = app.canvas.screenToPage(Offset(
        app.canvas.viewport.width / 2, app.canvas.viewport.height / 2));
    final result = await pasteOntoCanvas(app, at);
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
      app.navSplit,
      app.notebookId,
      app.collapsedPages.length,
      app.collapsedGroups.length,
      app.notebooks.length,
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
                    if (page != null) _PageHeader(app: app, page: page),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: page == null
                                ? _EmptyState(app: app)
                                : PageCanvas(
                                    key: ValueKey(app.pageId), state: app),
                          ),
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
            style: TextStyle(fontSize: 12, color: OnoteColors.graphite400),
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
                size: 17),
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
        TextStyle(fontSize: 11.5, color: OnoteColors.graphite400);
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final all = app.allTags();
    final byKind = <TagKind, List<({String pageId, String pageTitle, NoteTag tag, String text})>>{};
    for (final e in all) {
      byKind.putIfAbsent(e.tag.kind, () => []).add(e);
    }
    return Container(
      width: 260,
      color: dark ? OnoteColors.night0 : OnoteColors.paper50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
            child: Row(children: [
              const Icon(Icons.label_outline,
                  size: 14, color: OnoteColors.graphite400),
              const SizedBox(width: 6),
              Text('TAGS',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .6,
                      color: OnoteColors.graphite400)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 15),
                visualDensity: VisualDensity.compact,
                tooltip: 'Close tags',
                onPressed: app.toggleTagsPanel,
              ),
            ]),
          ),
          if (all.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Text(
                  'No tags in this notebook yet.\nTag a line from the Home tab.',
                  style:
                      TextStyle(fontSize: 11.5, color: OnoteColors.graphite400)),
            )
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  for (final kind in byKind.keys)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                          child: Row(children: [
                            Icon(kind.icon, size: 13, color: kind.color),
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
                                              ? OnoteColors.graphite400
                                              : null)),
                                  Text(e.pageTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 10.5,
                                          color: OnoteColors.graphite400)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final items = app.pageOutline();
    return Container(
      width: 240,
      color: dark ? OnoteColors.night0 : OnoteColors.paper50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
            child: Row(children: [
              const Icon(Icons.toc, size: 14, color: OnoteColors.graphite400),
              const SizedBox(width: 6),
              Text('OUTLINE',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .6,
                      color: OnoteColors.graphite400)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 15),
                visualDensity: VisualDensity.compact,
                tooltip: 'Close outline',
                onPressed: app.toggleTocPanel,
              ),
            ]),
          ),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Text('No headings on this page.\nStart a line with # to add one.',
                  style:
                      TextStyle(fontSize: 11.5, color: OnoteColors.graphite400)),
            )
          else
            Expanded(
              child: ListView.builder(
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
            ),
        ],
      ),
    );
  }
}

class _LinksPanel extends StatelessWidget {
  const _LinksPanel({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final backlinks = app.backlinksForCurrent();
    final outgoing = app.outgoingLinksForCurrent();

    Widget section(String label, IconData icon, List<TreeNode> pages,
        String empty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(children: [
              Icon(icon, size: 14, color: OnoteColors.graphite400),
              const SizedBox(width: 6),
              Text(label.toUpperCase(),
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .6,
                      color: OnoteColors.graphite400)),
              const Spacer(),
              Text('${pages.length}',
                  style:
                      TextStyle(fontSize: 11, color: OnoteColors.graphite400)),
            ]),
          ),
          if (pages.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Text(empty,
                  style:
                      TextStyle(fontSize: 12, color: OnoteColors.graphite400)),
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
                        size: 14, color: Theme.of(context).colorScheme.primary),
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

    return Container(
      width: 240,
      color: dark ? OnoteColors.night100 : OnoteColors.paper100,
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 6, 4),
            child: Row(children: [
              const Text('Links',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                visualDensity: VisualDensity.compact,
                onPressed: app.toggleLinksPanel,
              ),
            ]),
          ),
          section('Linked from', Icons.call_received, backlinks,
              'No pages link here yet.'),
          const SizedBox(height: 8),
          section('Links to', Icons.call_made, outgoing,
              'This page links nowhere yet.'),
        ],
      ),
    );
  }
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
                  size: 12,
                  color: failed
                      ? OnoteColors.danger
                      : saved
                          ? OnoteColors.success
                          : OnoteColors.graphite400),
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
                          : OnoteColors.graphite400)),
            ]),
          ),
          const SizedBox(width: 12),
          // Sync (ADR-0006). Shown only once a second device has touched this
          // notebook — until then there is nothing to say, and a permanent
          // "1 device" chip would be noise.
          if (app.notebookId != null && app.syncDeviceCount(app.notebookId!) > 1)
            Tooltip(
              message: 'This notebook has been edited on '
                  '${app.syncDeviceCount(app.notebookId!)} devices.\n'
                  'Click to pull in changes from the others.',
              child: InkWell(
                onTap: () async {
                  final n = await app.syncPull(app.notebookId!);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(n == 0
                          ? 'Already up to date.'
                          : 'Pulled $n change${n == 1 ? '' : 's'} from another device.')));
                },
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.devices, size: 12,
                      color: OnoteColors.graphite400),
                  const SizedBox(width: 5),
                  Text('${app.syncDeviceCount(app.notebookId!)} devices',
                      style: const TextStyle(
                          fontSize: 11, color: OnoteColors.graphite400)),
                ]),
              ),
            ),
          const SizedBox(width: 12),
          // Active compute engine (§ADR-0002): green chip when the Rust core
          // is linked, with the live page content-hash it computed on save.
          Tooltip(
            message: rust
                ? 'The Rust core (onote-core) is linked and computing this '
                    'page\'s content hash on save.'
                : 'Running the pure-Dart engine. Build the onote-core library '
                    'to link the Rust core.',
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.memory,
                  size: 12,
                  color: rust ? OnoteColors.success : OnoteColors.graphite400),
              const SizedBox(width: 4),
              Text(
                rust && hash != null && hash.length >= 8
                    ? '${app.engineLabel} · ${hash.substring(0, 8)}'
                    : app.engineLabel,
                style: TextStyle(
                    fontSize: 11,
                    color: rust ? OnoteColors.success : OnoteColors.graphite400),
              ),
            ]),
          ),
          const Spacer(),
          Text(
            'V select · T text · P pen · H highlight · E erase · '
            'Ctrl+Z undo · Ctrl+scroll zoom',
            style: TextStyle(fontSize: 11, color: OnoteColors.graphite400),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
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
              size: 44, color: OnoteColors.graphite400),
          const SizedBox(height: 12),
          const Text('An open page awaits',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            'Everything you make here lives on your device,\nin an open format you own.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: OnoteColors.graphite400),
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
