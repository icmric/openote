import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../canvas/page_canvas.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'sidebar.dart';
import 'toolbar.dart';

/// Layout per style guide §5.4: navigator | (toolbar / canvas-as-hero / status).
/// Keyboard shortcuts live here; letter shortcuts are guarded so they never
/// fire while a text field is being edited.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.app});
  final AppState app;

  /// True whenever a text field may own the keyboard (block editor, page
  /// title, or find bar) — letter shortcuts must never fire then.
  bool get _typing =>
      app.editingBlockId != null || app.findOpen || app.titleEditing;

  Map<ShortcutActivator, VoidCallback> _bindings(BuildContext context) => {
        // Tools (guarded)
        const SingleActivator(LogicalKeyboardKey.keyV): () {
          if (!_typing) app.setTool(Tool.select);
        },
        const SingleActivator(LogicalKeyboardKey.keyT): () {
          if (!_typing) app.setTool(Tool.text);
        },
        const SingleActivator(LogicalKeyboardKey.keyP): () {
          if (!_typing) app.setTool(Tool.pen);
        },
        const SingleActivator(LogicalKeyboardKey.keyH): () {
          if (!_typing) app.setTool(Tool.highlighter);
        },
        const SingleActivator(LogicalKeyboardKey.keyE): () {
          if (!_typing) app.setTool(Tool.eraser);
        },
        // Block ops (guarded)
        const SingleActivator(LogicalKeyboardKey.delete): () {
          if (!_typing && app.selectedIds.isNotEmpty) {
            app.removeSelected();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          app.toggleFind();
        },
        const SingleActivator(LogicalKeyboardKey.keyD, control: true): () {
          if (!_typing && app.selectedBlockId != null) {
            app.duplicateBlock(app.selectedBlockId!);
          }
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (app.findOpen) {
            app.toggleFind();
          } else {
            app.select(null);
          }
        },
        // History (guarded — text fields have their own undo)
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () {
          if (!_typing) app.undo();
        },
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): () {
          if (!_typing) app.redo();
        },
        const SingleActivator(LogicalKeyboardKey.keyZ,
            control: true, shift: true): () {
          if (!_typing) app.redo();
        },
        // Zoom (always available)
        const SingleActivator(LogicalKeyboardKey.equal, control: true): () =>
            app.canvas.setZoom(app.canvas.scale * 1.2),
        const SingleActivator(LogicalKeyboardKey.minus, control: true): () =>
            app.canvas.setZoom(app.canvas.scale / 1.2),
        const SingleActivator(LogicalKeyboardKey.digit0, control: true): () =>
            app.canvas.reset(),
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final page = app.nodes.where((n) => n.id == app.pageId).firstOrNull;
        return CallbackShortcuts(
          bindings: _bindings(context),
          child: Focus(
            autofocus: true,
            child: Scaffold(
              body: Row(
                children: [
                  Sidebar(app: app),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      children: [
                        OnoteToolbar(app: app),
                        if (app.findOpen) _FindBar(app: app),
                        if (page != null) _PageHeader(app: app, page: page),
                        Expanded(
                          child: page == null
                              ? _EmptyState(app: app)
                              : PageCanvas(key: ValueKey(app.pageId), state: app),
                        ),
                        _StatusBar(app: app),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Find-on-page bar (TEXT-7): live matches, next/prev cycles & centers.
class _FindBar extends StatelessWidget {
  const _FindBar({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
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
            onPressed:
                app.findMatches.isEmpty ? null : () => app.findNext(-1),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: app.findMatches.isEmpty ? null : () => app.findNext(1),
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

/// Slim breadcrumb — the editable TITLE now lives in the page itself
/// (PageTitleView); this only shows notebook › section context.
class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.app, required this.page});
  final AppState app;
  final TreeNode page;

  @override
  Widget build(BuildContext context) {
    final section = app.node(page.parentId ?? '');
    final notebook =
        app.repo.notebooks.firstWhere((n) => n.id == app.notebookId);
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

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final saved = !app.hasUnsavedChanges;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Icon(saved ? Icons.check_circle_outline : Icons.sync,
              size: 12,
              color: saved ? OnoteColors.success : OnoteColors.graphite400),
          const SizedBox(width: 5),
          Text(saved ? 'Saved on this device' : 'Saving…',
              style:
                  TextStyle(fontSize: 11, color: OnoteColors.graphite400)),
          const Spacer(),
          Text(
            'V select · T text · P pen · H highlight · E erase · '
            'Ctrl+Z undo · Ctrl+scroll zoom · double-click for text',
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
