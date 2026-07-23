import 'package:flutter/material.dart';

import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';

Color _sectionColor(String? token, bool dark) => switch (token) {
      'brass-400' => OnoteColors.brass400,
      'green' => OnoteColors.success,
      'blue' => const Color(0xFF2F6FB3),
      'violet' => const Color(0xFF6A4BC0),
      'red' => OnoteColors.danger,
      _ => dark ? OnoteColors.ink400 : OnoteColors.ink500,
    };

/// Navigator: notebook switcher → sections (colored) → pages/subpages
/// (ORG-1..6 MVP cut).
class Sidebar extends StatelessWidget {
  const Sidebar({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final groups = app.nodes
        .where((n) => n.kind == NodeKind.sectionGroup && n.parentId == null)
        .toList();
    final looseSections = app.nodes
        .where((n) => n.kind == NodeKind.section && n.parentId == null)
        .toList();

    List<Widget> sectionEntries(TreeNode s) => [
          _SectionHeader(app: app, section: s, dark: dark),
          for (final p in app.nodes
              .where((n) => n.kind == NodeKind.page && n.parentId == s.id))
            _PageTile(app: app, page: p),
        ];

    return Container(
      width: 250,
      color: dark ? OnoteColors.night100 : OnoteColors.paper100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _NotebookHeader(app: app),
          const Divider(height: 1),
          Expanded(
            child: (groups.isEmpty && looseSections.isEmpty)
                ? _EmptyHint(
                    icon: Icons.folder_outlined,
                    text: 'No sections yet.\nCreate one to get started.',
                    actionLabel: 'New section',
                    onAction: app.addSection,
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 12),
                    children: [
                      // Section groups (ORG-1; single level in MVP)
                      for (final g in groups) ...[
                        _GroupHeader(app: app, group: g),
                        if (!app.collapsedGroups.contains(g.id))
                          for (final s in app.nodes.where((n) =>
                              n.kind == NodeKind.section && n.parentId == g.id))
                            ...sectionEntries(s),
                      ],
                      for (final s in looseSections) ...sectionEntries(s),
                    ],
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    icon: const Icon(Icons.create_new_folder_outlined, size: 16),
                    label: const Text('Section', style: TextStyle(fontSize: 12)),
                    onPressed: app.addSection,
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    icon: const Icon(Icons.note_add_outlined, size: 16),
                    label: const Text('Page', style: TextStyle(fontSize: 12)),
                    onPressed: () => app.addPage(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.topic_outlined, size: 16),
                  tooltip: 'New section group',
                  onPressed: app.addSectionGroup,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.app, required this.group});
  final AppState app;
  final TreeNode group;

  @override
  Widget build(BuildContext context) {
    final collapsed = app.collapsedGroups.contains(group.id);
    final scheme = Theme.of(context).colorScheme;
    // Drop a section ONTO a group → move it into the group (ORG-1).
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) =>
          app.node(d.data)?.kind == NodeKind.section,
      onAcceptWithDetails: (d) => app.moveSectionToGroup(d.data, group.id),
      builder: (ctx, cand, rej) {
        final target = cand.isNotEmpty;
        return InkWell(
          onTap: () => app.toggleGroupCollapsed(group.id),
          onSecondaryTap: () =>
              showNodeMenu(context, app, group, canIndent: false),
          onLongPress: () =>
              showNodeMenu(context, app, group, canIndent: false),
          child: Container(
            decoration: target
                ? BoxDecoration(
                    border: Border.all(color: scheme.primary, width: 1.5),
                    borderRadius: BorderRadius.circular(6),
                    color: scheme.primary.withValues(alpha: .06))
                : null,
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 2),
            child: Row(
              children: [
                Icon(collapsed ? Icons.chevron_right : Icons.expand_more,
                    size: 16, color: OnoteColors.graphite400),
                const SizedBox(width: 4),
                Icon(Icons.topic_outlined,
                    size: 15, color: OnoteColors.graphite500),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(target ? 'move section here' : group.title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          fontStyle:
                              target ? FontStyle.italic : FontStyle.normal,
                          color: target ? scheme.primary : null)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NotebookHeader extends StatelessWidget {
  const _NotebookHeader({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current =
        app.repo.notebooks.firstWhere((n) => n.id == app.notebookId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 8),
      child: MenuAnchor(
        builder: (context, controller, _) => InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              children: [
                Icon(Icons.menu_book_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(current.title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                ),
                const Icon(Icons.unfold_more, size: 16),
              ],
            ),
          ),
        ),
        menuChildren: [
          for (final n in app.repo.notebooks)
            MenuItemButton(
              leadingIcon: Icon(
                n.id == app.notebookId
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 16,
                color: n.id == app.notebookId ? scheme.primary : null,
              ),
              onPressed: () => app.selectNotebook(n.id),
              child: Text(n.title),
            ),
          const Divider(),
          MenuItemButton(
            leadingIcon: const Icon(Icons.add, size: 16),
            onPressed: () => _newNotebook(context),
            child: const Text('New notebook…'),
          ),
        ],
      ),
    );
  }

  Future<void> _newNotebook(BuildContext context) async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New notebook'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Notebook name'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Create')),
        ],
      ),
    );
    if (title != null && title.trim().isNotEmpty) {
      await app.createNotebook(title.trim());
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
      {required this.app, required this.section, required this.dark});
  final AppState app;
  final TreeNode section;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    // Drop a page ONTO a section header → move it into that section (ORG-2).
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) =>
          app.node(d.data)?.kind == NodeKind.page,
      onAcceptWithDetails: (d) => app.movePageToSection(d.data, section.id),
      builder: (ctx, cand, rej) {
        final header = _header(context, pageTarget: cand.isNotEmpty);
        // Section itself is draggable into groups.
        return Draggable<String>(
          data: section.id,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: dragChip(context, section.title, Icons.folder_outlined),
          childWhenDragging: Opacity(opacity: .4, child: _header(context)),
          child: header,
        );
      },
    );
  }

  Widget _header(BuildContext context, {bool pageTarget = false}) {
    final color = _sectionColor(section.color, dark);
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onSecondaryTap: () => _menu(context),
      onLongPress: () => _menu(context),
      child: Container(
        decoration: pageTarget
            ? BoxDecoration(
                border: Border.all(color: scheme.primary, width: 1.5),
                borderRadius: BorderRadius.circular(6),
                color: scheme.primary.withValues(alpha: .06))
            : null,
        padding: const EdgeInsets.fromLTRB(10, 12, 4, 4),
        child: Row(
          children: [
            Container(
              width: 3.5,
              height: 16,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                pageTarget
                    ? 'move here'
                    : section.title.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .6,
                    fontStyle:
                        pageTarget ? FontStyle.italic : FontStyle.normal,
                    color: pageTarget
                        ? scheme.primary
                        : dark
                            ? OnoteColors.moon300
                            : OnoteColors.graphite500),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add, size: 15),
              visualDensity: VisualDensity.compact,
              tooltip: 'New page in ${section.title}',
              onPressed: () => app.addPage(sectionId: section.id),
            ),
          ],
        ),
      ),
    );
  }

  void _menu(BuildContext context) =>
      showNodeMenu(context, app, section, canIndent: false);
}

/// A floating label used as drag feedback in the navigator.
Widget dragChip(BuildContext context, String label, IconData icon) {
  return Material(
    color: Colors.transparent,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2))
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: Colors.white),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 12)),
      ]),
    ),
  );
}

class _PageTile extends StatelessWidget {
  const _PageTile({required this.app, required this.page});
  final AppState app;
  final TreeNode page;

  @override
  Widget build(BuildContext context) {
    // Drop a page ONTO this page → make it a subpage (ORG-6).
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) =>
          d.data != page.id && app.node(d.data)?.kind == NodeKind.page,
      onAcceptWithDetails: (d) => app.makeSubpageOf(d.data, page.id),
      builder: (ctx, cand, rej) {
        final tile = _tile(context, subpageTarget: cand.isNotEmpty);
        return Draggable<String>(
          data: page.id,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: dragChip(context, page.title, Icons.description_outlined),
          childWhenDragging: Opacity(opacity: .4, child: _tile(context)),
          child: tile,
        );
      },
    );
  }

  Widget _tile(BuildContext context, {bool subpageTarget = false}) {
    final scheme = Theme.of(context).colorScheme;
    final selected = app.pageId == page.id;
    return Material(
      color:
          selected ? scheme.primary.withValues(alpha: .10) : Colors.transparent,
      child: InkWell(
        onTap: () => app.selectPage(page.id),
        onSecondaryTap: () => showNodeMenu(context, app, page, canIndent: true),
        onLongPress: () => showNodeMenu(context, app, page, canIndent: true),
        child: Container(
          decoration: subpageTarget
              ? BoxDecoration(
                  border: Border.all(color: scheme.primary, width: 1.5),
                  borderRadius: BorderRadius.circular(6),
                  color: scheme.primary.withValues(alpha: .06))
              : null,
          padding: EdgeInsets.only(
              left: 22.0 + page.level * 16, right: 4, top: 6, bottom: 6),
          child: Row(
            children: [
              Icon(
                  page.level == 0
                      ? Icons.description_outlined
                      : Icons.subdirectory_arrow_right,
                  size: 15,
                  color: selected ? scheme.primary : OnoteColors.graphite400),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  subpageTarget ? '↳ make subpage' : page.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontStyle:
                        subpageTarget ? FontStyle.italic : FontStyle.normal,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected || subpageTarget ? scheme.primary : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(
      {required this.icon,
      required this.text,
      required this.actionLabel,
      required this.onAction});
  final IconData icon;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: OnoteColors.graphite400),
          const SizedBox(height: 8),
          Text(text,
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 12, color: OnoteColors.graphite400)),
          const SizedBox(height: 10),
          FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

/// Shared rename/delete/reorder/indent menu for tree nodes (ORG-2/6).
Future<void> showNodeMenu(BuildContext context, AppState app, TreeNode node,
    {required bool canIndent}) async {
  final action = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(node.title),
      children: [
        SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'rename'),
            child: const Text('Rename')),
        SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'up'),
            child: const Text('Move up')),
        SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'down'),
            child: const Text('Move down')),
        if (node.kind == NodeKind.section)
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'togroup'),
              child: const Text('Move to group…')),
        if (canIndent && node.level < 2)
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'indent'),
              child: const Text('Make subpage  →')),
        if (canIndent && node.level > 0)
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'outdent'),
              child: const Text('←  Promote page')),
        SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'delete'),
            child: const Text('Delete',
                style: TextStyle(color: OnoteColors.danger))),
      ],
    ),
  );
  if (!context.mounted) return;
  switch (action) {
    case 'up':
      app.moveNode(node.id, -1);
    case 'down':
      app.moveNode(node.id, 1);
    case 'togroup':
      final groups = app.nodes
          .where((n) => n.kind == NodeKind.sectionGroup)
          .toList();
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Move section to…'),
          children: [
            SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, ''),
                child: const Text('(No group — top level)')),
            for (final g in groups)
              SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, g.id),
                  child: Text(g.title)),
          ],
        ),
      );
      if (choice != null) {
        app.moveSectionToGroup(node.id, choice.isEmpty ? null : choice);
      }
    case 'rename':
      final controller = TextEditingController(text: node.title);
      final title = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rename'),
          content: TextField(
              controller: controller,
              autofocus: true,
              onSubmitted: (v) => Navigator.pop(ctx, v)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, controller.text),
                child: const Text('Rename')),
          ],
        ),
      );
      if (title != null && title.trim().isNotEmpty) {
        app.renameNode(node.id, title.trim());
      }
    case 'indent':
      app.indentPage(node.id, 1);
    case 'outdent':
      app.indentPage(node.id, -1);
    case 'delete':
      await app.deleteNode(node.id);
  }
}
