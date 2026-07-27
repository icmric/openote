import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'notebook_manager.dart';

Color _sectionColor(String? token, bool dark) => switch (token) {
      'brass-400' => OnoteColors.brass400,
      'green' => OnoteColors.success,
      'blue' => const Color(0xFF2F6FB3),
      'violet' => const Color(0xFF6A4BC0),
      'red' => OnoteColors.danger,
      _ => dark ? OnoteColors.ink400 : OnoteColors.ink500,
    };

/// The page rows for a section, honouring subpage collapse (a collapsed page
/// hides everything indented beneath it).
List<Widget> _pageEntriesFor(AppState app, TreeNode section) {
  final pages = app.nodes
      .where((n) => n.kind == NodeKind.page && n.parentId == section.id)
      .toList(); // already ordered by position
  final out = <Widget>[];
  int? hideDeeperThan;
  for (var i = 0; i < pages.length; i++) {
    final p = pages[i];
    if (hideDeeperThan != null) {
      if (p.level > hideDeeperThan) continue;
      hideDeeperThan = null;
    }
    final hasKids = i + 1 < pages.length && pages[i + 1].level > p.level;
    final collapsed = app.collapsedPages.contains(p.id);
    out.add(_PageTile(
        app: app, page: p, hasChildren: hasKids, collapsed: collapsed));
    if (hasKids && collapsed) hideDeeperThan = p.level;
  }
  return out;
}

/// Navigator (style guide §7b): a notebook bar, a search/jump box, then two
/// stacked zones — sections above, the **active** section's pages below — split
/// by a resizable divider. One section is focused at a time, which is what keeps
/// long notebooks scannable.
class Sidebar extends StatefulWidget {
  const Sidebar({super.key, required this.app});
  final AppState app;

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final _searchCtl = TextEditingController();
  String _query = '';

  AppState get app => widget.app;

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchCtl.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final searching = _query.trim().isNotEmpty;
    return Container(
      width: 250,
      color: dark ? OnoteColors.night100 : OnoteColors.paper100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _NotebookHeader(app: app),
          _searchRow(context),
          const Divider(height: 1),
          Expanded(
            child: searching ? _searchResults(context) : _stackedBody(context),
          ),
          const Divider(height: 1),
          _footer(context),
        ],
      ),
    );
  }

  // ── Search / quick-jump ───────────────────────────────────────────────

  Widget _searchRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 4, 6),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _searchCtl,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  hintText: 'Search or jump to…',
                  hintStyle: const TextStyle(fontSize: 13),
                  prefixIcon: const Icon(Icons.search, size: 16),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  suffixIcon: _query.isEmpty
                      ? null
                      : InkWell(
                          onTap: _clearSearch,
                          child: const Icon(Icons.close, size: 15),
                        ),
                  suffixIconConstraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: scheme.outline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: scheme.outline.withValues(alpha: .6)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchResults(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final results = app.nodes
        .where((n) =>
            (n.kind == NodeKind.page || n.kind == NodeKind.section) &&
            n.title.toLowerCase().contains(q))
        .toList();
    if (results.isEmpty) {
      return Center(
        child: Text('No matches for “${_query.trim()}”',
            style: const TextStyle(fontSize: 12, color: OnoteColors.graphite400)),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        for (final n in results)
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: Icon(
                n.kind == NodeKind.section
                    ? Icons.folder_outlined
                    : n.level == 0
                        ? Icons.description_outlined
                        : Icons.subdirectory_arrow_right,
                size: 16),
            title: Text(n.title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13)),
            subtitle: n.kind == NodeKind.page
                ? Text(app.node(n.parentId)?.title ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11))
                : null,
            onTap: () {
              if (n.kind == NodeKind.page) {
                app.selectPage(n.id);
              } else {
                app.activateSection(n.id);
              }
              _clearSearch();
            },
          ),
      ],
    );
  }

  // ── Stacked zones (sections above, active section's pages below) ───────

  Widget _stackedBody(BuildContext context) {
    final sections =
        app.nodes.where((n) => n.kind == NodeKind.section).toList();
    if (sections.isEmpty) {
      return _EmptyHint(
        icon: Icons.folder_outlined,
        text: 'No sections yet.\nCreate one to get started.',
        actionLabel: 'New section',
        onAction: app.addSection,
      );
    }
    final active = app.activeSection ?? sections.first;
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final h = constraints.maxHeight;
        final secH = (h * app.navSplit).clamp(72.0, h - 120.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: secH, child: _sectionsColumn(context)),
            _dividerHandle(context, h),
            Expanded(child: _pagesZone(context, active)),
          ],
        );
      },
    );
  }

  Widget _dividerHandle(BuildContext context, double h) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (d) {
          app.navSplit = (app.navSplit + d.delta.dy / h).clamp(0.15, 0.7);
          app.refresh();
        },
        onVerticalDragEnd: (_) => app.setNavSplit(app.navSplit),
        child: Container(
          height: 11,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor),
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Container(
            width: 26,
            height: 3,
            decoration: BoxDecoration(
              color: dark ? OnoteColors.night300 : OnoteColors.paper300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pagesZone(BuildContext context, TreeNode section) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = _sectionColor(section.color, dark);
    final pages = _pageEntriesFor(app, section);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 2),
          child: Row(
            children: [
              Container(
                width: 3.5,
                height: 14,
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  section.title.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .6,
                    color: dark
                        ? OnoteColors.moon300
                        : OnoteColors.graphite500,
                  ),
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
        Expanded(
          child: pages.isEmpty
              ? const Center(
                  child: Text('No pages yet',
                      style: TextStyle(
                          fontSize: 12, color: OnoteColors.graphite400)),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 12),
                  children: pages,
                ),
        ),
      ],
    );
  }

  // ── Section list (groups → sections) ──────────────────────────────────

  Widget _sectionsColumn(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final groups = app.nodes
        .where((n) => n.kind == NodeKind.sectionGroup && n.parentId == null)
        .toList();
    final looseSections = app.nodes
        .where((n) => n.kind == NodeKind.section && n.parentId == null)
        .toList();

    if (groups.isEmpty && looseSections.isEmpty) {
      return _EmptyHint(
        icon: Icons.folder_outlined,
        text: 'No sections yet.\nCreate one to get started.',
        actionLabel: 'New section',
        onAction: app.addSection,
      );
    }

    Widget row(TreeNode s) => _SectionHeader(
        app: app,
        section: s,
        dark: dark,
        active: app.activeSectionId == s.id);

    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        for (final g in groups) ...[
          _GroupHeader(app: app, group: g),
          if (!app.collapsedGroups.contains(g.id))
            for (final s in app.nodes.where(
                (n) => n.kind == NodeKind.section && n.parentId == g.id))
              row(s),
        ],
        for (final s in looseSections) row(s),
      ],
    );
  }

  // ── Footer toolbar ────────────────────────────────────────────────────

  Widget _footer(BuildContext context) => Padding(
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
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 16),
              tooltip: 'Recycle bin',
              onPressed: () => showRecycleBin(context, app),
            ),
          ],
        ),
      );
}

class _GroupHeader extends StatefulWidget {
  const _GroupHeader({required this.app, required this.group});
  final AppState app;
  final TreeNode group;

  @override
  State<_GroupHeader> createState() => _GroupHeaderState();
}

class _GroupHeaderState extends State<_GroupHeader> {
  bool _renaming = false;
  Offset _downPos = Offset.zero; // last pointer-down, for long-press menus

  AppState get app => widget.app;
  TreeNode get group => widget.group;

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
        final labelStyle = TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            fontStyle: target ? FontStyle.italic : FontStyle.normal,
            color: target ? scheme.primary : null);
        return InkWell(
          onTap: _renaming ? null : () => app.toggleGroupCollapsed(group.id),
          onTapDown: (d) => _downPos = d.globalPosition,
          onDoubleTap: () => setState(() => _renaming = true),
          onSecondaryTapUp: (d) => showNodeMenu(context, app, group,
              canIndent: false, position: d.globalPosition),
          onLongPress: () => showNodeMenu(context, app, group,
              canIndent: false, position: _downPos),
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
                const Icon(Icons.topic_outlined,
                    size: 15, color: OnoteColors.graphite500),
                const SizedBox(width: 6),
                Expanded(
                  child: _renaming
                      ? _InlineRename(
                          initial: group.title,
                          style: labelStyle,
                          onSubmit: (v) {
                            app.renameNode(group.id, v);
                            if (mounted) setState(() => _renaming = false);
                          },
                          onCancel: () {
                            if (mounted) setState(() => _renaming = false);
                          },
                        )
                      : Text(target ? 'move section here' : group.title,
                          overflow: TextOverflow.ellipsis, style: labelStyle),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The notebook bar: shows the current notebook and opens the notebook manager.
///
/// **One surface, not two.** This used to be a dropdown for switching plus a
/// manager panel for everything else, which read as two different menus for one
/// job. The manager now does both — its rows switch notebooks *and* carry the
/// per-notebook actions — so there is a single place notebooks are dealt with,
/// and switching still takes the same two clicks it did through the dropdown.
class _NotebookHeader extends StatelessWidget {
  const _NotebookHeader({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current =
        app.repo.notebooks.firstWhere((n) => n.id == app.notebookId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 4),
      child: Tooltip(
        message: 'Notebooks — switch, rename, duplicate, import',
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => showNotebookManager(context, app),
          onSecondaryTapUp: (_) =>
              showNotebookManager(context, app, focusId: current.id),
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
      ),
    );
  }
}

class _SectionHeader extends StatefulWidget {
  const _SectionHeader({
    required this.app,
    required this.section,
    required this.dark,
    required this.active,
  });
  final AppState app;
  final TreeNode section;
  final bool dark;
  final bool active;

  @override
  State<_SectionHeader> createState() => _SectionHeaderState();
}

class _SectionHeaderState extends State<_SectionHeader> {
  bool _renaming = false;
  Offset _downPos = Offset.zero; // last pointer-down, for long-press menus

  AppState get app => widget.app;
  TreeNode get section => widget.section;
  bool get dark => widget.dark;

  @override
  Widget build(BuildContext context) {
    // Drop a page ONTO a section header → move it into that section (ORG-2).
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => app.node(d.data)?.kind == NodeKind.page,
      onAcceptWithDetails: (d) => app.movePageToSection(d.data, section.id),
      builder: (ctx, cand, rej) {
        final header = _header(context, pageTarget: cand.isNotEmpty);
        if (_renaming) return header;
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
    final active = widget.active;
    final emphasised = pageTarget || active;
    final labelStyle = TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: .6,
        fontStyle: pageTarget ? FontStyle.italic : FontStyle.normal,
        color: emphasised
            ? scheme.primary
            : dark
                ? OnoteColors.moon300
                : OnoteColors.graphite500);
    return InkWell(
      onTap: _renaming ? null : () => app.activateSection(section.id),
      onTapDown: (d) => _downPos = d.globalPosition,
      onDoubleTap: () => setState(() => _renaming = true),
      onSecondaryTapUp: (d) => showNodeMenu(context, app, section,
          canIndent: false, position: d.globalPosition),
      onLongPress: () => showNodeMenu(context, app, section,
          canIndent: false, position: _downPos),
      child: Container(
        decoration: pageTarget
            ? BoxDecoration(
                border: Border.all(color: scheme.primary, width: 1.5),
                borderRadius: BorderRadius.circular(6),
                color: scheme.primary.withValues(alpha: .06))
            : active
                ? BoxDecoration(
                    color: scheme.primary.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(6))
                : null,
        padding: const EdgeInsets.fromLTRB(6, 12, 4, 4),
        child: Row(
          children: [
            const SizedBox(width: 4),
            Container(
              width: 3.5,
              height: 16,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _renaming
                  ? _InlineRename(
                      initial: section.title,
                      style: labelStyle.copyWith(letterSpacing: 0),
                      onSubmit: (v) {
                        app.renameNode(section.id, v);
                        if (mounted) setState(() => _renaming = false);
                      },
                      onCancel: () {
                        if (mounted) setState(() => _renaming = false);
                      },
                    )
                  : Text(
                      pageTarget ? 'move here' : section.title.toUpperCase(),
                      overflow: TextOverflow.ellipsis,
                      style: labelStyle,
                    ),
            ),
            if (!_renaming)
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
}

/// How long until a trashed item (deleted at [deletedAt]) is auto-purged.
String _retentionSubtitle(int deletedAt, int retentionDays) {
  final expireMs =
      deletedAt + Duration(days: retentionDays).inMilliseconds;
  final remaining = expireMs - DateTime.now().millisecondsSinceEpoch;
  final days = (remaining / const Duration(days: 1).inMilliseconds).ceil();
  if (days <= 0) return 'Deletes soon';
  return 'Deletes in $days day${days == 1 ? '' : 's'}';
}

/// Recycle bin (ORG-7): restore or permanently delete soft-deleted notebooks
/// and, within the current notebook, sections/pages/groups. Items are
/// auto-purged after the retention window (swept on open).
Future<void> showRecycleBin(BuildContext context, AppState app) async {
  await app.purgeExpiredTrash();
  if (!context.mounted) return;
  final retention = app.recycleRetentionDays;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final notebooks = app.trashedNotebooks;
        final items = app.deletedNodes();
        return AlertDialog(
          title: const Text('Recycle bin'),
          content: SizedBox(
            width: 400,
            child: (notebooks.isEmpty && items.isEmpty)
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Nothing deleted.'))
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 400),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
                          child: Text(
                              'Items here are permanently deleted after $retention days.',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: OnoteColors.graphite400)),
                        ),
                        if (notebooks.isNotEmpty) ...[
                          const _BinSectionLabel('Notebooks'),
                          for (final nb in notebooks)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.menu_book_outlined,
                                  size: 16),
                              title: Text(nb.title,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13)),
                              subtitle: Text(
                                  _retentionSubtitle(
                                      nb.deletedAt ?? 0, retention),
                                  style: const TextStyle(fontSize: 11)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    onPressed: () async {
                                      await app.restoreNotebook(nb.id);
                                      setLocal(() {});
                                    },
                                    child: const Text('Restore'),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_forever,
                                        size: 16, color: OnoteColors.danger),
                                    tooltip: 'Delete permanently',
                                    onPressed: () async {
                                      final ok =
                                          await _confirmPurgeNotebook(ctx, nb);
                                      if (ok) {
                                        await app.purgeNotebook(nb.id);
                                        setLocal(() {});
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          if (items.isNotEmpty) const _BinSectionLabel('Items'),
                        ],
                        for (final it in items)
                          ListTile(
                            dense: true,
                            leading: Icon(
                                it.kind == 'page'
                                    ? Icons.description_outlined
                                    : it.kind == 'section'
                                        ? Icons.folder_outlined
                                        : Icons.topic_outlined,
                                size: 16),
                            title: Text(it.title,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13)),
                            subtitle: Text(
                                _retentionSubtitle(it.deletedAt, retention),
                                style: const TextStyle(fontSize: 11)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: () async {
                                    await app.restoreDeleted(it.id);
                                    setLocal(() {});
                                  },
                                  child: const Text('Restore'),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_forever,
                                      size: 16, color: OnoteColors.danger),
                                  tooltip: 'Delete permanently',
                                  onPressed: () {
                                    app.purgeDeleted(it.id);
                                    setLocal(() {});
                                  },
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        );
      },
    ),
  );
}

Future<bool> _confirmPurgeNotebook(BuildContext context, NotebookRef nb) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete permanently?'),
      content: Text(
          '“${nb.title}” and all its pages will be removed for good. This can\'t '
          'be undone.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: OnoteColors.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete forever'),
        ),
      ],
    ),
  );
  return ok == true;
}

class _BinSectionLabel extends StatelessWidget {
  const _BinSectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .6,
                color: OnoteColors.graphite400)),
      );
}

/// Inline rename field (§7a: rename is a direct-manipulation action, no
/// dialog). Autofocuses, selects all, commits on Enter or blur, cancels on
/// Escape or an empty/unchanged value.
class _InlineRename extends StatefulWidget {
  const _InlineRename({
    required this.initial,
    required this.style,
    required this.onSubmit,
    required this.onCancel,
  });
  final String initial;
  final TextStyle style;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  @override
  State<_InlineRename> createState() => _InlineRenameState();
}

class _InlineRenameState extends State<_InlineRename> {
  late final TextEditingController _c =
      TextEditingController(text: widget.initial);
  late final FocusNode _focus = FocusNode(onKeyEvent: (_, e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  });
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      _c.selection =
          TextSelection(baseOffset: 0, extentOffset: _c.text.length);
    });
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  void _commit() {
    if (_done) return;
    _done = true;
    final v = _c.text.trim();
    if (v.isNotEmpty && v != widget.initial) {
      widget.onSubmit(v);
    } else {
      widget.onCancel();
    }
  }

  void _cancel() {
    if (_done) return;
    _done = true;
    widget.onCancel();
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: _c,
      focusNode: _focus,
      style: widget.style,
      cursorColor: scheme.primary,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide: BorderSide(color: scheme.primary),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
      onSubmitted: (_) => _commit(),
    );
  }
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

class _PageTile extends StatefulWidget {
  const _PageTile({
    required this.app,
    required this.page,
    this.hasChildren = false,
    this.collapsed = false,
  });
  final AppState app;
  final TreeNode page;
  final bool hasChildren;
  final bool collapsed;

  @override
  State<_PageTile> createState() => _PageTileState();
}

class _PageTileState extends State<_PageTile> {
  bool _renaming = false;
  Offset _downPos = Offset.zero; // last pointer-down, for long-press menus

  AppState get app => widget.app;
  TreeNode get page => widget.page;

  @override
  Widget build(BuildContext context) {
    // Drop a page ONTO this page → make it a subpage (ORG-6).
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) =>
          d.data != page.id && app.node(d.data)?.kind == NodeKind.page,
      onAcceptWithDetails: (d) => app.makeSubpageOf(d.data, page.id),
      builder: (ctx, cand, rej) {
        final tile = _tile(context, subpageTarget: cand.isNotEmpty);
        // Don't wrap in a Draggable while renaming — the text field needs the
        // pointer for caret placement and selection.
        if (_renaming) return tile;
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
    final labelStyle = TextStyle(
      fontSize: 13,
      fontStyle: subpageTarget ? FontStyle.italic : FontStyle.normal,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      color: selected || subpageTarget ? scheme.primary : null,
    );
    return Material(
      color:
          selected ? scheme.primary.withValues(alpha: .10) : Colors.transparent,
      child: InkWell(
        onTap: _renaming ? null : () => app.selectPage(page.id),
        onTapDown: (d) => _downPos = d.globalPosition,
        onDoubleTap: () => setState(() => _renaming = true),
        onSecondaryTapUp: (d) => showNodeMenu(context, app, page,
            canIndent: true, position: d.globalPosition),
        onLongPress: () => showNodeMenu(context, app, page,
            canIndent: true, position: _downPos),
        child: Container(
          decoration: subpageTarget
              ? BoxDecoration(
                  border: Border.all(color: scheme.primary, width: 1.5),
                  borderRadius: BorderRadius.circular(6),
                  color: scheme.primary.withValues(alpha: .06))
              : null,
          padding: EdgeInsets.only(
              left: 8.0 + page.level * 15, right: 4, top: 6, bottom: 6),
          child: Row(
            children: [
              // Collapse chevron (only when the page has subpages)
              SizedBox(
                width: 16,
                child: widget.hasChildren
                    ? InkWell(
                        onTap: () => app.togglePageCollapsed(page.id),
                        child: Icon(
                            widget.collapsed
                                ? Icons.chevron_right
                                : Icons.expand_more,
                            size: 15,
                            color: OnoteColors.graphite400),
                      )
                    : null,
              ),
              Icon(
                  page.level == 0
                      ? Icons.description_outlined
                      : Icons.subdirectory_arrow_right,
                  size: 15,
                  color: selected ? scheme.primary : OnoteColors.graphite400),
              const SizedBox(width: 7),
              Expanded(
                child: _renaming
                    ? _InlineRename(
                        initial: page.title,
                        style: labelStyle,
                        onSubmit: (v) {
                          app.renameNode(page.id, v);
                          if (mounted) setState(() => _renaming = false);
                        },
                        onCancel: () {
                          if (mounted) setState(() => _renaming = false);
                        },
                      )
                    : Text(
                        subpageTarget ? '↳ make subpage' : page.title,
                        overflow: TextOverflow.ellipsis,
                        style: labelStyle,
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
              style: const TextStyle(
                  fontSize: 12, color: OnoteColors.graphite400)),
          const SizedBox(height: 10),
          FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

/// One entry in the pop-out node menu (mirrors the canvas context menus).
PopupMenuItem<String> _nodeItem(String v, IconData icon, String label,
    {bool danger = false}) {
  final color = danger ? OnoteColors.danger : null;
  return PopupMenuItem<String>(
    value: v,
    height: 36,
    child: Row(children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 10),
      Text(label, style: TextStyle(fontSize: 13, color: color)),
    ]),
  );
}

/// Pop-out node menu (§7a.1): a compact menu anchored at the pointer, focused
/// on actions that can *only* be done here. Rename lives inline (double-click
/// the title) so it's not in this list; reorder + structural moves are.
Future<void> showNodeMenu(BuildContext context, AppState app, TreeNode node,
    {required bool canIndent, required Offset position}) async {
  final isPage = node.kind == NodeKind.page;
  final isSection = node.kind == NodeKind.section;
  final overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox?;
  final action = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      overlay == null ? position.dx : overlay.size.width - position.dx,
      position.dy,
    ),
    items: [
      _nodeItem('up', Icons.keyboard_arrow_up, 'Move up'),
      _nodeItem('down', Icons.keyboard_arrow_down, 'Move down'),
      if (isSection) ...[
        const PopupMenuDivider(),
        _nodeItem('togroup', Icons.drive_file_move_outline, 'Move to group…'),
      ],
      // A page can always indent (make subpage) or outdent (promote) at some
      // level in 0..2, so the separator is shown whenever those items are.
      if (canIndent) const PopupMenuDivider(),
      if (canIndent && node.level < 2)
        _nodeItem('indent', Icons.subdirectory_arrow_right, 'Make subpage'),
      if (canIndent && node.level > 0)
        _nodeItem('outdent', Icons.arrow_back, 'Promote page'),
      if (isPage) ...[
        const PopupMenuDivider(),
        _nodeItem('history', Icons.history, 'Version history…'),
        _nodeItem('template', Icons.bookmark_add_outlined, 'Save as template…'),
      ],
      const PopupMenuDivider(),
      _nodeItem('delete', Icons.delete_outline, 'Delete', danger: true),
    ],
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
    case 'indent':
      app.indentPage(node.id, 1);
    case 'outdent':
      app.indentPage(node.id, -1);
    case 'history':
      if (app.pageId != node.id) await app.selectPage(node.id);
      if (context.mounted) await showVersionHistory(context, app);
    case 'template':
      if (app.pageId != node.id) await app.selectPage(node.id);
      if (context.mounted) await _promptSaveTemplate(context, app);
    case 'delete':
      await app.deleteNode(node.id);
  }
}

Future<void> _promptSaveTemplate(BuildContext context, AppState app) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Save as template'),
      content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Template name'),
          onSubmitted: (v) => Navigator.pop(ctx, v)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save')),
      ],
    ),
  );
  if (name != null && name.trim().isNotEmpty) {
    app.saveCurrentAsTemplate(name.trim());
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Template "${name.trim()}" saved')));
    }
  }
}

/// Version history dialog (SYNC-8): restore any snapshot of the current page.
Future<void> showVersionHistory(BuildContext context, AppState app) async {
  final versions = app.pageVersions();
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Version history'),
      content: SizedBox(
        width: 340,
        child: versions.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                    'No versions yet — snapshots are taken automatically as you edit (about every 10 minutes).'))
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final at in versions)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.history, size: 16),
                        title: Text(_fmtWhen(at),
                            style: const TextStyle(fontSize: 13)),
                        trailing: TextButton(
                          child: const Text('Restore'),
                          onPressed: () async {
                            await app.restoreVersion(at);
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                        ),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
      ],
    ),
  );
}

String _fmtWhen(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final hm =
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (day == today) return 'Today $hm';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday $hm';
  return '${d.day}/${d.month}/${d.year} $hm';
}
