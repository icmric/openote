/// The phone's two pieces of chrome: a slim top bar, and the navigator as a
/// drawer. On a phone the page gets the screen; where you are in the notebook
/// is something you ask for (the menu button or a swipe from the left edge) and
/// it goes away when you have chosen. See the "Phone layout" board on the design
/// canvas.
///
/// Used below [kPhoneMaxWidth]. Wider windows, tablets included, keep the
/// desktop layout.
library;

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/section_palette.dart';
import '../theme/tokens.dart';
import 'folder_spike_page.dart';
import 'icon_tap.dart';
import 'notebook_manager.dart';
import 'review_panel.dart';
import 'settings_dialog.dart';
import 'sidebar.dart' show showRecycleBin;

/// Narrower than this is a phone.
const double kPhoneMaxWidth = 600;

bool isPhoneWidth(BuildContext context) =>
    MediaQuery.sizeOf(context).width < kPhoneMaxWidth;

/// The one row above the page: the menu, where you are, the writing review, and
/// a few things that do not earn a button.
class PhoneTopBar extends StatelessWidget {
  const PhoneTopBar({super.key, required this.app, required this.onMenu});
  final AppState app;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final s = context.surfaces;
    final page = app.nodes.where((n) => n.id == app.pageId).firstOrNull;
    final section = app.activeSection;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: s.chrome,
        border: Border(bottom: BorderSide(color: s.border)),
      ),
      child: Row(children: [
        IconTap(
            icon: Icons.menu,
            label: l.navSectionsHeader,
            size: 22,
            width: 44,
            height: 44,
            onPressed: onMenu),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(page?.title ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  Text(
                      [app.currentNotebook.title, if (section != null) section.title]
                          .join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: s.textSecondary)),
                ]),
          ),
        ),
        if (app.review.available) ...[
          ReviewChip(app: app),
          const SizedBox(width: 4),
        ],
        PopupMenuButton<String>(
          tooltip: '',
          icon: Icon(Icons.more_vert, color: s.textSecondary),
          padding: EdgeInsets.zero,
          onSelected: (v) {
            switch (v) {
              case 'find':
                app.toggleFind();
              case 'study':
                app.toggleStudyPanel();
              case 'planner':
                app.togglePlannerPanel();
              case 'overview':
                app.togglePageOverview();
              case 'settings':
                showSettingsDialog(context, app);
              case 'spike':
                Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const FolderSpikePage()));
            }
          },
          itemBuilder: (_) => [
            // A temporary test of syncing through a Drive folder (Android only).
            if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
              const PopupMenuItem(
                  value: 'spike', height: 48, child: Text('Folder test (temporary)')),
            for (final (v, icon, label) in [
              ('find', Icons.search, l.barFindOnPage),
              ('study', Icons.school_outlined, l.barStudy),
              ('planner', Icons.event_note_outlined, l.barPlanner),
              ('overview', Icons.toc, l.barPageOverview),
            ])
              PopupMenuItem(
                  value: v,
                  height: 48,
                  child: Row(children: [
                    Icon(icon, size: 20),
                    const SizedBox(width: 12),
                    Text(label),
                  ])),
            PopupMenuItem(
                value: 'settings',
                height: 48,
                child: Row(children: [
                  const Icon(Icons.settings_outlined, size: 20),
                  const SizedBox(width: 12),
                  Text(l.barSettings),
                ])),
          ],
        ),
      ]),
    );
  }
}

/// Notebook, then section, then page: a single column, one section open at a
/// time. Choosing a page closes the drawer ([onPicked]).
class PhoneNavigator extends StatefulWidget {
  const PhoneNavigator({super.key, required this.app, required this.onPicked});
  final AppState app;
  final VoidCallback onPicked;

  @override
  State<PhoneNavigator> createState() => _PhoneNavigatorState();
}

class _PhoneNavigatorState extends State<PhoneNavigator> {
  AppState get app => widget.app;

  /// The section showing its pages. Starts on the one being worked in.
  String? _open;

  @override
  void initState() {
    super.initState();
    _open = app.activeSectionId;
  }

  List<TreeNode> _children(String? parent, NodeKind kind) => [
        for (final n in app.nodes)
          if (n.kind == kind && n.parentId == parent) n
      ]..sort((a, b) => a.position.compareTo(b.position));

  Future<void> _pick(String id) async {
    widget.onPicked();
    await app.selectPage(id);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final s = context.surfaces;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        // Top level, in order: loose sections and groups share one list.
        final top = <TreeNode>[
          ..._children(null, NodeKind.section),
          ..._children(null, NodeKind.sectionGroup),
        ]..sort((a, b) => a.position.compareTo(b.position));

        Widget sectionRow(TreeNode sec, {double indent = 0}) {
          final open = _open == sec.id;
          final pages = open ? app.pagesOf(sec.id) : const <TreeNode>[];
          return Column(mainAxisSize: MainAxisSize.min, children: [
            InkWell(
              onTap: () => setState(() => _open = open ? null : sec.id),
              child: Container(
                height: 48,
                padding: EdgeInsets.only(left: 16 + indent, right: 10),
                color: sec.id == app.activeSectionId
                    ? scheme.primary.withValues(alpha: .10)
                    : null,
                child: Row(children: [
                  Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: sectionColorFor(sec.color, dark),
                              width: 3))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(sec.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500))),
                  Icon(open ? Icons.expand_more : Icons.chevron_right,
                      size: 20, color: s.textSecondary),
                ]),
              ),
            ),
            if (open)
              Container(
                color: s.chrome2,
                child: Column(children: [
                  for (final p in pages)
                    InkWell(
                      onTap: () => _pick(p.id),
                      child: Container(
                        height: 46,
                        padding: EdgeInsets.only(
                            left: 46 + indent + p.level * 18.0, right: 14),
                        color: p.id == app.pageId
                            ? scheme.primary.withValues(alpha: .12)
                            : null,
                        child: Row(children: [
                          Icon(Icons.description_outlined,
                              size: 18,
                              color: p.id == app.pageId
                                  ? scheme.primary
                                  : s.textSecondary),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(p.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: p.id == app.pageId
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: p.id == app.pageId
                                          ? scheme.primary
                                          : null))),
                        ]),
                      ),
                    ),
                  InkWell(
                    onTap: () {
                      widget.onPicked();
                      app.addPage(sectionId: sec.id);
                    },
                    child: Container(
                      height: 46,
                      padding: EdgeInsets.only(left: 46 + indent, right: 14),
                      child: Row(children: [
                        Icon(Icons.add, size: 18, color: scheme.primary),
                        const SizedBox(width: 12),
                        Text(l.navMenuNewPage,
                            style: TextStyle(
                                fontSize: 14, color: scheme.primary)),
                      ]),
                    ),
                  ),
                ]),
              ),
          ]);
        }

        Widget groupRow(TreeNode g) {
          final collapsed = app.collapsedGroups.contains(g.id);
          return Column(mainAxisSize: MainAxisSize.min, children: [
            InkWell(
              onTap: () => app.toggleGroupCollapsed(g.id),
              child: Container(
                height: 48,
                padding: const EdgeInsets.only(left: 14, right: 10),
                child: Row(children: [
                  Icon(Icons.folder_outlined, size: 20, color: s.textSecondary),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(g.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600))),
                  Icon(collapsed ? Icons.chevron_right : Icons.expand_more,
                      size: 20, color: s.textSecondary),
                ]),
              ),
            ),
            if (!collapsed)
              for (final sec in _children(g.id, NodeKind.section))
                sectionRow(sec, indent: 14),
          ]);
        }

        return Material(
          color: s.chrome,
          child: SafeArea(
            child: Column(children: [
              // The notebook: tap to change or manage notebooks.
              InkWell(
                onTap: () => showNotebookManager(context, app),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
                  child: Row(children: [
                    Icon(Icons.auto_stories, color: scheme.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(app.currentNotebook.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600))),
                    Icon(Icons.unfold_more, size: 20, color: s.textSecondary),
                  ]),
                ),
              ),
              Divider(height: 1, color: s.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 4, 0),
                child: Row(children: [
                  Expanded(
                    child: Text(l.navSectionsHeader.toUpperCase(),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .6,
                            color: s.textSecondary)),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '',
                    icon: Icon(Icons.add, color: s.textSecondary),
                    onSelected: (v) {
                      widget.onPicked();
                      if (v == 'section') {
                        app.addSection();
                      } else {
                        app.addSectionGroup();
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                          value: 'section',
                          height: 48,
                          child: Text(l.navNewSection)),
                      PopupMenuItem(
                          value: 'group',
                          height: 48,
                          child: Text(l.navNewSectionGroup)),
                    ],
                  ),
                ]),
              ),
              Expanded(
                child: ListView(padding: EdgeInsets.zero, children: [
                  for (final n in top)
                    n.kind == NodeKind.sectionGroup ? groupRow(n) : sectionRow(n),
                ]),
              ),
              Divider(height: 1, color: s.border),
              InkWell(
                onTap: () {
                  final rb = context.findRenderObject() as RenderBox;
                  showRecycleBin(context, app,
                      anchor: rb.localToGlobal(Offset.zero) & rb.size);
                },
                child: SizedBox(
                  height: 52,
                  child: Row(children: [
                    const SizedBox(width: 16),
                    Icon(Icons.delete_outline, size: 20, color: s.textSecondary),
                    const SizedBox(width: 12),
                    Text(l.navRecycleBin,
                        style: TextStyle(fontSize: 14, color: s.textSecondary)),
                  ]),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}
