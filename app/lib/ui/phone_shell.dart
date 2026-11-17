/// The phone's two pieces of chrome: a slim top bar, and the navigator as a
/// drawer. On a phone the page gets the screen; where you are in the notebook
/// is something you ask for (the menu button or a swipe from the left edge) and
/// it goes away when you have chosen. See the "Phone layout" board on the design
/// canvas.
///
/// Used below [kPhoneMaxWidth]. Wider windows, tablets included, keep the
/// desktop layout.
library;

export 'device_class.dart' show isPhoneWidth, isTablet, isTabletPortrait, kPhoneMaxWidth;

import 'opening_mark.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart' show OnoteColors;
import '../theme/section_palette.dart';
import '../theme/tokens.dart';
import 'device_class.dart';
import 'icon_tap.dart';
import 'notebook_manager.dart';
import 'review_panel.dart';
import 'save_problem_dialog.dart';
import 'settings_dialog.dart';
import 'onote_dialog.dart' show promptForText;
import 'sidebar.dart' show showNodeMenu, showRecycleBin;
import 'sync_dot.dart';

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
        _SaveMark(app: app),
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
            }
          },
          itemBuilder: (_) => [
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

/// **Is what I wrote safe?** The desktop answers in its status bar, which a phone
/// does not have, so the answer lives in the top bar as one small mark in a slot
/// of its own (so nothing beside it moves): a tick when it is saved, turning
/// arrows while it is being, and a red warning, which can be pressed for the
/// reason, when it could not be. Colour is never the only cue: the three are
/// three different shapes.
class _SaveMark extends StatelessWidget {
  const _SaveMark({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final problem = app.saveError;
    // Arrows while a notebook is still being read in as well as while saving:
    // a tick would say "all done" about something not finished.
    final saved = !app.hasUnsavedChanges && !app.openingNotebook;
    final s = context.surfaces;
    final icon = problem != null
        ? Icons.error_outline
        : saved
            ? Icons.check_circle_outline
            : Icons.sync;
    final colour = problem != null
        ? OnoteColors.danger
        : saved
            ? OnoteColors.success
            : s.textSecondary;
    return SizedBox(
      width: 32,
      height: 44,
      child: problem == null
          ? Icon(icon, size: 18, color: colour)
          : IconTap(
              icon: icon,
              label: problem.short,
              size: 20,
              width: 32,
              height: 44,
              color: colour,
              onPressed: () => showSaveProblemDialog(context, problem),
            ),
    );
  }
}

enum PhoneNavStart { sections, search, recent }

/// Notebook, then section, then page: a single column, one section open at a
/// time. Choosing a page closes the drawer ([onPicked]).
///
/// Everything the desktop navigator offers is here in a phone's terms: a
/// search-or-jump box, Recent and favourites, the recycle bin, settings, and
/// a long press on any row for the menu a right-click gives on the desktop.
class PhoneNavigator extends StatefulWidget {
  const PhoneNavigator(
      {super.key,
      required this.app,
      required this.onPicked,
      this.start = PhoneNavStart.sections});
  final AppState app;
  final VoidCallback onPicked;

  /// What it opens showing (the rail on a tablet opens it straight to search or
  /// to Recent).
  final PhoneNavStart start;

  @override
  State<PhoneNavigator> createState() => _PhoneNavigatorState();
}

class _PhoneNavigatorState extends State<PhoneNavigator> {
  AppState get app => widget.app;

  /// The section showing its pages. Starts on the one being worked in.
  String? _open;

  /// Showing Recent and favourites instead of the sections.
  bool _home = false;

  final _searchCtl = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';

  /// Where the last finger went down, for the long-press menu.
  Offset _down = Offset.zero;

  @override
  void initState() {
    super.initState();
    _open = app.activeSectionId;
    _home = widget.start == PhoneNavStart.recent;
    if (widget.start == PhoneNavStart.search) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _searchFocus.requestFocus());
    }
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<TreeNode> _children(String? parent, NodeKind kind) => [
        for (final n in app.nodes)
          if (n.kind == kind && n.parentId == parent) n
      ]..sort((a, b) => a.position.compareTo(b.position));

  Future<void> _pick(String id) async {
    widget.onPicked();
    await app.selectPage(id);
  }

  /// The row's menu (the desktop's right-click), with Rename asking in a small
  /// dialog because there is no row to type into here.
  void _menu(TreeNode n, {required bool canIndent}) {
    showNodeMenu(context, app, n,
        canIndent: canIndent,
        position: _down,
        onRename: () async {
          final l = L.of(context);
          final t = await promptForText(context,
              title: l.nbRename, okLabel: l.nbRename, hintText: n.title);
          if (t != null) app.renameNode(n.id, t);
        });
  }

  Widget _row(
      {required Widget child,
      required VoidCallback onTap,
      TreeNode? node,
      bool canIndent = false}) {
    return InkWell(
      onTap: onTap,
      onTapDown: (d) => _down = d.globalPosition,
      onLongPress: node == null ? null : () => _menu(node, canIndent: canIndent),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final s = context.surfaces;
    final scheme = Theme.of(context).colorScheme;
    final searching = _query.trim().isNotEmpty;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
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
                    // Where it lives, as the same dot the notebook list shows.
                    SyncDot(app: app, notebookId: app.currentNotebook.id),
                    const SizedBox(width: 4),
                    Icon(Icons.unfold_more, size: 20, color: s.textSecondary),
                  ]),
                ),
              ),
              // A thin bar while the notebook is still being read in.
              if (app.openingNotebook)
                const LinearProgressIndicator(minHeight: 2),
              _searchBox(context),
              Expanded(
                child: searching
                    ? _results(context)
                    : _home
                        ? _homePane(context)
                        : _sections(context),
              ),
              Divider(height: 1, color: s.border),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(children: [
                  Expanded(
                      child: _footButton(
                          key: const ValueKey('phone-nav-recent'),
                          icon: Icons.history,
                          label: l.navRecent,
                          on: _home,
                          onTap: () => setState(() => _home = !_home))),
                  Expanded(
                      child: _footButton(
                          icon: Icons.delete_outline,
                          label: l.navRecycleBin,
                          onTap: () {
                            final rb = context.findRenderObject() as RenderBox;
                            showRecycleBin(context, app,
                                anchor: rb.localToGlobal(Offset.zero) & rb.size);
                          })),
                  IconTap(
                      icon: Icons.settings_outlined,
                      label: l.barSettings,
                      size: 22,
                      width: 46,
                      height: 46,
                      onPressed: () => showSettingsDialog(context, app)),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _footButton(
      {Key? key,
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool on = false}) {
    final s = context.surfaces;
    final c = on ? Theme.of(context).colorScheme.primary : s.textSecondary;
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: SizedBox(
        height: 46,
        child: Row(children: [
          const SizedBox(width: 10),
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 8),
          Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: c))),
        ]),
      ),
    );
  }

  // ── Search or jump to ──────────────────────────────────────────────────

  Widget _searchBox(BuildContext context) {
    final l = L.of(context);
    final s = context.surfaces;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: SizedBox(
        height: 42,
        child: TextField(
          controller: _searchCtl,
          focusNode: _searchFocus,
          onChanged: (v) => setState(() => _query = v),
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            hintText: l.navSearchHint,
            prefixIcon: Icon(Icons.search, size: 18, color: s.textSecondary),
            suffixIcon: _query.isEmpty
                ? null
                : IconTap(
                    icon: Icons.close,
                    label: l.commonCancel,
                    size: 18,
                    width: 40,
                    height: 40,
                    onPressed: () => setState(() {
                          _searchCtl.clear();
                          _query = '';
                        })),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: s.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: s.border)),
          ),
        ),
      ),
    );
  }

  void _clearSearch() => setState(() {
        _searchCtl.clear();
        _query = '';
      });

  Widget _results(BuildContext context) {
    final l = L.of(context);
    final s = context.surfaces;
    final q = _query.trim().toLowerCase();
    // Locked pages are left out of search, as on the desktop: a title is what
    // a lock is hiding.
    final titles = [
      for (final n in app.nodes)
        if ((n.kind == NodeKind.page || n.kind == NodeKind.section) &&
            n.title.toLowerCase().contains(q) &&
            !app.isLocked(n.id))
          n
    ];
    final seen = {for (final n in titles) n.id};
    final content = q.length < 3
        ? const <({String pageId, String snippet})>[]
        : [
            for (final h in app.searchContent(q))
              if (!seen.contains(h.pageId)) h
          ];
    if (titles.isEmpty && content.isEmpty) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(l.navNoMatches(_query.trim()),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: s.textSecondary)),
      ));
    }
    return ListView(padding: EdgeInsets.zero, children: [
      for (final n in titles)
        _row(
          node: n,
          canIndent: n.kind == NodeKind.page,
          onTap: () {
            widget.onPicked();
            n.kind == NodeKind.page
                ? app.selectPage(n.id)
                : app.activateSection(n.id);
            _clearSearch();
          },
          child: SizedBox(
            height: 52,
            child: Row(children: [
              const SizedBox(width: 16),
              Icon(
                  n.kind == NodeKind.section
                      ? Icons.folder_outlined
                      : Icons.description_outlined,
                  size: 18,
                  color: s.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(n.title.isEmpty ? l.navUntitled : n.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14)),
                    if (n.kind == NodeKind.page)
                      Text(app.node(n.parentId)?.title ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: s.textSecondary)),
                  ])),
              const SizedBox(width: 12),
            ]),
          ),
        ),
      if (content.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(l.navInPageContent.toUpperCase(),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .6,
                  color: s.textSecondary)),
        ),
        for (final h in content)
          _row(
            onTap: () {
              widget.onPicked();
              app.selectPage(h.pageId);
              _clearSearch();
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
              child: Row(children: [
                Icon(Icons.search, size: 18, color: s.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(app.node(h.pageId)?.title ?? l.navUntitled,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14)),
                      if (h.snippet.isNotEmpty)
                        Text(h.snippet,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(fontSize: 12, color: s.textSecondary)),
                    ])),
              ]),
            ),
          ),
      ],
    ]);
  }

  // ── Recent and favourites ──────────────────────────────────────────────

  Widget _homePane(BuildContext context) {
    final l = L.of(context);
    final s = context.surfaces;
    final favourites = app.favouritePages();
    final recents = app.recentPages(max: 12);
    if (favourites.isEmpty && recents.isEmpty) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(l.navHomeEmpty,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.45, color: s.textSecondary)),
      ));
    }
    Widget label(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(t.toUpperCase(),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .6,
                  color: s.textSecondary)),
        );
    Widget page(TreeNode p, IconData icon, {Color? color}) => _row(
          node: p,
          canIndent: true,
          onTap: () => _pick(p.id),
          child: SizedBox(
            height: 52,
            child: Row(children: [
              const SizedBox(width: 16),
              Icon(icon, size: 18, color: color ?? s.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(p.title.isEmpty ? l.navUntitled : p.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14)),
                    Text(app.node(p.parentId)?.title ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: s.textSecondary)),
                  ])),
              const SizedBox(width: 12),
            ]),
          ),
        );
    return ListView(padding: EdgeInsets.zero, children: [
      if (favourites.isNotEmpty) ...[
        for (final p in favourites) page(p, Icons.star, color: OnoteColors.brass400),
      ],
      if (recents.isNotEmpty) ...[
        label(l.navRecent),
        for (final p in recents) page(p, Icons.history),
      ],
    ]);
  }

  // ── Sections and their pages ───────────────────────────────────────────

  Widget _sections(BuildContext context) {
    final l = L.of(context);
    final s = context.surfaces;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Top level, in order: loose sections and groups share one list.
    final top = <TreeNode>[
      ..._children(null, NodeKind.section),
      ..._children(null, NodeKind.sectionGroup),
    ]..sort((a, b) => a.position.compareTo(b.position));
    // Not "no sections": on its way.
    if (top.isEmpty && app.openingNotebook) return const OpeningMark();

    Widget sectionRow(TreeNode sec, {double indent = 0}) {
      final open = _open == sec.id;
      final all = app.pagesOf(sec.id);
      final pages = open ? all : const <TreeNode>[];
      return Column(mainAxisSize: MainAxisSize.min, children: [
        _row(
          node: sec,
          onTap: () => setState(() => _open = open ? null : sec.id),
          child: Container(
            height: 48,
            padding: EdgeInsets.only(left: 16 + indent, right: 10),
            color: sec.id == app.activeSectionId
                ? scheme.primary.withValues(alpha: .10)
                : null,
            child: Row(children: [
              // The same marker the desktop navigator draws (an open ring
              // with a dot), not a plain circle.
              SizedBox(
                  width: 16,
                  height: 16,
                  child: CustomPaint(
                      painter:
                          SectionRingPainter(sectionColorFor(sec.color, dark)))),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(sec.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500))),
              Text('${all.length}',
                  style: TextStyle(fontSize: 12, color: s.textSecondary)),
              const SizedBox(width: 6),
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
                _row(
                  node: p,
                  canIndent: true,
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
                          child: Text(p.title.isEmpty ? l.navUntitled : p.title,
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
              _row(
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
                        style: TextStyle(fontSize: 14, color: scheme.primary)),
                  ]),
                ),
              ),
            ]),
          ),
      ]);
    }

    Widget groupRow(TreeNode g) {
      final collapsed = app.collapsedGroups.contains(g.id);
      final inside = _children(g.id, NodeKind.section);
      return Column(mainAxisSize: MainAxisSize.min, children: [
        _row(
          node: g,
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
              Text('${inside.length}',
                  style: TextStyle(fontSize: 12, color: s.textSecondary)),
              const SizedBox(width: 6),
              Icon(collapsed ? Icons.chevron_right : Icons.expand_more,
                  size: 20, color: s.textSecondary),
            ]),
          ),
        ),
        if (!collapsed)
          for (final sec in inside) sectionRow(sec, indent: 14),
      ]);
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
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
                  value: 'section', height: 48, child: Text(l.navNewSection)),
              PopupMenuItem(
                  value: 'group', height: 48, child: Text(l.navNewSectionGroup)),
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
    ]);
  }
}

/// **The navigator folded to a rail**, for a tablet held upright, where there is
/// no room for it beside the page. Four buttons down the left edge; each opens
/// the same drawer a phone has (the menu on the sections, the magnifier on the
/// search box, the clock on Recent) and the bin opens as it does everywhere.
class TabletRail extends StatelessWidget {
  const TabletRail({super.key, required this.app, required this.onOpen});
  final AppState app;
  final void Function(PhoneNavStart start) onOpen;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final s = context.surfaces;
    return Container(
      width: 56,
      color: s.chrome,
      child: SafeArea(
        right: false,
        child: Column(children: [
          const SizedBox(height: 6),
          IconTap(
              icon: Icons.menu,
              label: l.navSectionsHeader,
              size: 22,
              width: 48,
              height: 48,
              onPressed: () => onOpen(PhoneNavStart.sections)),
          IconTap(
              icon: Icons.search,
              label: l.navSearchHint,
              size: 22,
              width: 48,
              height: 48,
              onPressed: () => onOpen(PhoneNavStart.search)),
          IconTap(
              icon: Icons.history,
              label: l.navRecent,
              size: 22,
              width: 48,
              height: 48,
              onPressed: () => onOpen(PhoneNavStart.recent)),
          const Spacer(),
          Builder(
            builder: (c) => IconTap(
                icon: Icons.delete_outline,
                label: l.navRecycleBin,
                size: 22,
                width: 48,
                height: 48,
                onPressed: () {
                  final rb = c.findRenderObject() as RenderBox;
                  showRecycleBin(c, app,
                      anchor: rb.localToGlobal(Offset.zero) & rb.size);
                }),
          ),
          const SizedBox(height: 6),
        ]),
      ),
    );
  }
}
