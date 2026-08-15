import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../export/pdf_vector_export.dart';
import '../export/print_page.dart';
import '../model/models.dart';
import '../planner/agenda.dart';
import '../state/app_state.dart';
import '../study/study_stats.dart';
import '../theme/onote_theme.dart';
import 'exam_date.dart';
import 'notebook_manager.dart';
import 'protect_dialog.dart';
import 'sync_dot.dart';
import 'planner_format.dart';
import '../theme/tokens.dart';
import 'onote_dialog.dart';

Color _sectionColor(String? token, bool dark) => switch (token) {
      'brass-400' => OnoteColors.brass400,
      'green' => OnoteColors.success,
      'blue' => const Color(0xFF2F6FB3),
      'violet' => const Color(0xFF6A4BC0),
      'red' => OnoteColors.danger,
      _ => dark ? OnoteColors.ink400 : OnoteColors.ink500,
    };

/// The page rows for a section, honouring subpage collapse. Children are
/// NESTED under a [_Reveal] rather than skipped from a flat list, so
/// collapsing a page animates its subpages closed instead of them blinking
/// out of existence.
List<Widget> _pageEntriesFor(AppState app, TreeNode section) {
  final pages = app.pagesOf(section.id); // already ordered by position
  List<Widget> range(int start, int end) {
    final out = <Widget>[];
    var i = start;
    while (i < end) {
      final p = pages[i];
      var j = i + 1;
      while (j < end && pages[j].level > p.level) {
        j++;
      }
      final hasKids = j > i + 1;
      final collapsed = app.collapsedPages.contains(p.id);
      out.add(_PageTile(
          app: app, page: p, hasChildren: hasKids, collapsed: collapsed));
      if (hasKids) {
        out.add(_Reveal(
          open: !collapsed,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: range(i + 1, j),
          ),
        ));
      }
      i = j;
    }
    return out;
  }

  return range(0, pages.length);
}

/// Detects a double-click WITHOUT a DoubleTap recognizer. An InkWell that
/// binds `onDoubleTap` defers EVERY single tap by the double-tap window
/// (~300 ms) while the gesture arena waits to see whether a second tap
/// follows — which was the "very consistent" delay on every sidebar click
/// (pages, sections, groups all bound it for rename; hotkeys were instant
/// because they skip the pointer pipeline entirely). With this gate the
/// first click ACTS immediately and a second within the window renames —
/// the file-explorer behaviour, and the whole delay gone.
class _DoubleTapGate {
  DateTime? _last;

  /// True when this tap is the second of a double-click.
  bool tap() {
    final now = sidebarNow();
    final isDouble = _last != null &&
        now.difference(_last!) < const Duration(milliseconds: 300);
    _last = isDouble ? null : now;
    return isDouble;
  }
}

/// The clock [_DoubleTapGate] measures the double-click window against.
///
/// A seam, because the window is **wall-clock** and a widget test's clock is
/// not. `tester.pump(Duration)` advances the fake clock; it does not advance
/// `DateTime.now()`. So the probe that guards this affordance was really
/// measuring how fast the machine could rebuild the sidebar between two taps —
/// it passed where that took under 300 ms and failed where it did not, which is
/// a test that reports the hardware rather than the code.
///
/// Production keeps real time, because a double-click IS a real-time gesture
/// and the 300 ms window has to match the one the user's hand is aiming at.
@visibleForTesting
DateTime Function() sidebarNow = DateTime.now;

/// Animated expand/collapse for tree groups (Eric: "an animation when
/// opening and closing groups (both page and section)"). The child stays
/// in the tree; its height animates between natural and zero in the app's
/// one motion register (150 ms, ease-out).
class _Reveal extends StatelessWidget {
  const _Reveal({required this.open, required this.child});
  final bool open;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: open
            ? child
            : const SizedBox(width: double.infinity, height: 0),
      ),
    );
  }
}

/// Navigator (style guide §7b): a notebook bar, a search/jump box, then TWO
/// COLUMNS — sections on the left, the active section's pages on the right —
/// each independently scrollable and resizable, collapsible to a 44px rail.
///
/// The OneNote shape, adopted because the previous stacked layout made
/// sections and pages fight over one column's height: with a real notebook
/// both zones scrolled, and you could never see the section list and a page
/// list at once. Beyond the shape itself, three things OneNote doesn't do:
/// a Home pane (favourites + recents), a remembered per-section page so
/// browsing never loses your place, and the rail.
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

    if (app.navCollapsed) return _NavRail(app: app, dark: dark);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: app.navSectionsW + app.navPagesW,
          color: context.surfaces.chrome2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _NotebookHeader(app: app),
              _searchRow(context),
              const Divider(height: 1),
              Expanded(
                child: searching
                    ? _searchResults(context)
                    : _twoColumnBody(context),
              ),
              const Divider(height: 1),
              _footer(context),
            ],
          ),
        ),
        // The navigator's own right edge resizes the pages column, so the
        // whole thing grows and shrinks from where your cursor already is.
        _VDragHandle(
          onDrag: (dx) {
            app.navPagesW = (app.navPagesW + dx).clamp(140.0, 320.0);
            app.refresh();
          },
          onEnd: () => app.setNavPagesW(app.navPagesW),
        ),
      ],
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
                          child: const Icon(Icons.close, size: 16),
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
            n.title.toLowerCase().contains(q) &&
            // Titles are excluded for the same reason content is (see
            // AppState.searchContent). A page called "Therapy" leaks the thing
            // that made it worth locking, and half a search box that honours
            // the passcode while the other half does not is not a gate. The
            // tree still shows it, so a locked page is never unreachable —
            // search is where you would stumble ON it.
            !app.isLocked(n.id))
        .toList();
    // Notebook-wide content search (TEXT-7). Titles match first because a
    // title hit is almost always what you meant; content hits follow, minus
    // any page already listed above.
    final titleHits = {for (final n in results) n.id};
    final contentHits = [
      for (final h in _contentHitsFor(q))
        if (!titleHits.contains(h.pageId)) h
    ];
    if (results.isEmpty && contentHits.isEmpty) {
      return Center(
        child: Text('No matches for “${_query.trim()}”',
            style: TextStyle(fontSize: 12, color: context.surfaces.textSecondary)),
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
        if (contentHits.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Text('In page content',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.surfaces.textSecondary)),
          ),
          for (final h in contentHits)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: const Icon(Icons.search, size: 16),
              title: Text(app.node(h.pageId)?.title ?? 'Untitled',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13)),
              subtitle: h.snippet.isEmpty
                  ? null
                  : Text(h.snippet,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11)),
              onTap: () {
                app.selectPage(h.pageId);
                _clearSearch();
              },
            ),
        ],
      ],
    );
  }

  /// Content hits, cached per query so the SQLite scan doesn't re-run on every
  /// rebuild while the results are on screen.
  String? _contentQuery;
  List<({String pageId, String snippet})> _contentCache = const [];

  List<({String pageId, String snippet})> _contentHitsFor(String q) {
    // Below 3 characters the result set is everything, which is neither useful
    // nor cheap.
    if (q.length < 3) return const [];
    if (_contentQuery == q) return _contentCache;
    _contentQuery = q;
    _contentCache = app.searchContent(q);
    return _contentCache;
  }

  // ── Two columns: sections | pages (the OneNote shape) ──────────────────
  //
  // Side by side rather than stacked, because the old stack made sections and
  // pages fight over one column's HEIGHT: with a real notebook both zones
  // scrolled, the split handle needed constant fiddling, and you could never
  // see the section list and a page list at the same time — which is the
  // thing that makes OneNote's navigator effortless to scan.

  Widget _twoColumnBody(BuildContext context) {
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: app.navSectionsW,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HomeTile(app: app),
              Expanded(child: _sectionsColumn(context)),
            ],
          ),
        ),
        _VDragHandle(
          onDrag: (dx) {
            app.navSectionsW = (app.navSectionsW + dx).clamp(96.0, 220.0);
            app.refresh();
          },
          onEnd: () => app.setNavSectionsW(app.navSectionsW),
        ),
        // The pages pane sits on the lighter surface colour — the same
        // two-tone depth cue the canvas already uses, no new tokens.
        Expanded(
          child: Container(
            color: context.surfaces.chrome,
            child: app.navHome
                ? _HomePane(app: app)
                : _pagesZone(context, active),
          ),
        ),
      ],
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
                    color: color, borderRadius: BorderRadius.circular(4)),
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
                icon: const Icon(Icons.add, size: 16),
                visualDensity: VisualDensity.compact,
                tooltip: 'New page in ${section.title}',
                onPressed: () => app.addPage(sectionId: section.id),
              ),
            ],
          ),
        ),
        Expanded(
          child: pages.isEmpty
              ? Center(
                  child: Text('No pages yet',
                      style: TextStyle(
                          fontSize: 12, color: context.surfaces.textSecondary)),
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
          // Indented AND railed. Indentation alone says "these are children";
          // the rail is what says where the group ENDS — with several groups
          // in a column, an indent that just stops is ambiguous, because the
          // next group's header looks like an outdented sibling either way.
          _Reveal(
            open: !app.collapsedGroups.contains(g.id),
            child: Padding(
              padding: const EdgeInsets.only(left: 13),
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                        color: dark
                            ? OnoteColors.night300
                            : OnoteColors.paper300),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final s in app.nodes.where((n) =>
                        n.kind == NodeKind.section && n.parentId == g.id))
                      row(s),
                  ],
                ),
              ),
            ),
          ),
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
  final _taps = _DoubleTapGate();
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
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontStyle: target ? FontStyle.italic : FontStyle.normal,
            color: target ? scheme.primary : null);
        return InkWell(
          // No onDoubleTap — it deferred every click (see _DoubleTapGate).
          onTap: _renaming
              ? null
              : () {
                  if (_taps.tap()) {
                    setState(() => _renaming = true);
                    return;
                  }
                  app.toggleGroupCollapsed(group.id);
                },
          onTapDown: (d) => _downPos = d.globalPosition,
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
                    size: 16, color: context.surfaces.textSecondary),
                const SizedBox(width: 4),
                const Icon(Icons.topic_outlined,
                    size: 16, color: OnoteColors.graphite500),
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

/// A vertical grab strip for resizing a navigator column.
///
/// 5px wide and visually just the divider line — the affordance is the cursor
/// change, which is how every two-pane app on the desktop does it.
class _VDragHandle extends StatelessWidget {
  const _VDragHandle({required this.onDrag, required this.onEnd});
  final void Function(double dx) onDrag;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
        onHorizontalDragEnd: (_) => onEnd(),
        child: Container(
          width: 5,
          alignment: Alignment.center,
          child: Container(width: 1, color: Theme.of(context).dividerColor),
        ),
      ),
    );
  }
}

/// The Home entry above the section list: favourites and recents, which were
/// persisted state with no surface at all until this pane existed.
class _HomeTile extends StatelessWidget {
  const _HomeTile({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = app.navHome;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: app.openHome,
        child: Container(
          decoration: active
              ? BoxDecoration(
                  color: scheme.primary.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(6))
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(children: [
            Icon(Icons.star_outline,
                size: 16,
                color: active ? scheme.primary : OnoteColors.brass400),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Home',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: active ? scheme.primary : null)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The Home pane: favourites, then recents. A springboard, not a place — any
/// page tap returns the pane to that page's section.
class _HomePane extends StatelessWidget {
  const _HomePane({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final favourites = app.favouritePages();
    final recents = app.recentPages(max: 8);

    Widget label(String s) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Text(s,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .6,
                  color: context.surfaces.textSecondary)),
        );

    Widget row(TreeNode page, IconData icon, {Color? iconColor}) => InkWell(
          onTap: () => app.selectPage(page.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(children: [
              Icon(icon, size: 16, color: iconColor ?? context.surfaces.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(page.title.isEmpty ? 'Untitled' : page.title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                    Text(app.node(page.parentId)?.title ?? '',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11, color: context.surfaces.textSecondary)),
                  ],
                ),
              ),
            ]),
          ),
        );

    if (favourites.isEmpty && recents.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: Text(
          'Nothing here yet.\n\nRight-click a page and choose Favourite to '
          'pin it; pages you visit show up under Recent.',
          style: TextStyle(fontSize: 12, height: 1.45),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        _ComingUp(app: app),
        if (favourites.isNotEmpty) ...[
          label('FAVOURITES'),
          for (final p in favourites)
            row(p, Icons.star, iconColor: OnoteColors.brass400),
        ],
        if (recents.isNotEmpty) ...[
          label('RECENT'),
          for (final p in recents) row(p, Icons.history),
        ],
      ],
    );
  }
}

/// The planner, in the Home pane (v0.5 §3).
///
/// **A summary, not the planner.** The navigator is 96–320px wide and is a
/// place you pass through; the planner is a working surface where dates get
/// re-dated. So Home answers "have I got anything on" in three rows and hands
/// off. That split is also what let the exam countdown stop hiding: this is the
/// first surface in the app where a date is visible without having navigated to
/// the thing it belongs to.
///
/// Hidden entirely when there is nothing dated — an empty heading over an empty
/// list is the "row of zeroes" the study stats deliberately avoid.
class _ComingUp extends StatelessWidget {
  const _ComingUp({required this.app});
  final AppState app;

  /// Rows before it defers to the panel. Three fits above the fold beside
  /// favourites and recents, and "what's next" is a shorter question than
  /// "what have I got".
  static const _max = 3;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final sections = app.planner.sections(now: now);
    // Overdue and today first, then whatever is next — the same order the
    // panel shows, truncated rather than re-sorted so the two never disagree.
    final rows = <DatedItem>[];
    var total = 0;
    for (final s in sections) {
      if (s.bucket == AgendaBucket.done) continue;
      total += s.items.length;
      for (final it in s.items) {
        if (rows.length < _max) rows.add(it);
      }
    }
    final alerts = app.planner.pendingAlerts.length;
    if (rows.isEmpty && alerts == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 6, 4),
          child: Row(children: [
            Text('COMING UP',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .6,
                    color: context.surfaces.textSecondary)),
            const Spacer(),
            InkWell(
              onTap: app.openPlanner,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(total > _max ? 'All $total' : 'Open',
                    style: TextStyle(fontSize: 11, color: scheme.primary)),
              ),
            ),
          ]),
        ),
        if (alerts > 0)
          InkWell(
            onTap: app.openPlanner,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 3, 12, 3),
              child: Row(children: [
                Icon(Icons.notifications_active_outlined,
                    size: 16, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      '$alerts reminder${alerts == 1 ? '' : 's'} waiting',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary)),
                ),
              ]),
            ),
          ),
        for (final it in rows)
          InkWell(
            onTap: () {
              if (it.pageId != null) {
                app.selectPage(it.pageId!);
              } else {
                app.openPlanner();
              }
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 3, 12, 3),
              child: Row(children: [
                Icon(_icon(it.kind),
                    size: OnoteIcon.sm,
                    color: _colour(it.kind, scheme, context.surfaces)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(it.title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          decoration:
                              it.done ? TextDecoration.lineThrough : null)),
                ),
                const SizedBox(width: 6),
                Text(plannerWhen(it, now),
                    style: TextStyle(
                        fontSize: 11,
                        color: bucketFor(it, now) == AgendaBucket.overdue
                            ? OnoteColors.danger
                            : context.surfaces.textSecondary)),
              ]),
            ),
          ),
      ],
    );
  }

  static IconData _icon(DatedKind k) => switch (k) {
        DatedKind.exam => Icons.flag_outlined,
        DatedKind.task => Icons.check_box_outline_blank,
        DatedKind.reminder => Icons.notifications_none,
        DatedKind.event => Icons.schedule,
      };

  static Color _colour(
          DatedKind k, ColorScheme scheme, OnoteSurfaces s) =>
      switch (k) {
        DatedKind.exam => OnoteColors.brass500,
        DatedKind.task => scheme.primary,
        DatedKind.reminder => OnoteColors.ink400,
        DatedKind.event => s.textSecondary,
      };
}

/// The collapsed navigator: a 44px rail that keeps every destination one
/// click away — expand, notebooks, Home, and a chip per section.
class _NavRail extends StatelessWidget {
  const _NavRail({required this.app, required this.dark});
  final AppState app;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = app.notebooks.firstWhere((n) => n.id == app.notebookId);
    final sections =
        app.nodes.where((n) => n.kind == NodeKind.section).toList();
    return Container(
      width: 44,
      color: context.surfaces.chrome2,
      child: Column(
        children: [
          const SizedBox(height: 6),
          IconButton(
            icon: const Icon(Icons.keyboard_double_arrow_right, size: 18),
            tooltip: 'Expand the navigator  (Ctrl+\\)',
            visualDensity: VisualDensity.compact,
            onPressed: app.toggleNavCollapsed,
          ),
          Tooltip(
            message: current.title,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => showNotebookManager(context, app),
              child: Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .14),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  current.title.isEmpty
                      ? '?'
                      : current.title.characters.first.toUpperCase(),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary),
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          IconButton(
            icon: const Icon(Icons.star_outline, size: 16),
            color: OnoteColors.brass400,
            tooltip: 'Home — favourites & recents',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              app.toggleNavCollapsed();
              app.openHome();
            },
          ),
          const Divider(height: 10, indent: 10, endIndent: 10),
          // Initial chips, not bare colour dots: section colours only exist on
          // imported notebooks, so dots alone would be fifteen identical grey
          // circles. A letter is scannable either way; the colour tints it
          // when there is one.
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                for (final s in sections)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Center(
                      child: Tooltip(
                        message: s.title,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () {
                            app.toggleNavCollapsed();
                            app.activateSection(s.id);
                          },
                          child: Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _sectionColor(s.color, dark)
                                  .withValues(alpha: .18),
                              borderRadius: BorderRadius.circular(6),
                              border: app.activeSectionId == s.id
                                  ? Border.all(color: scheme.primary)
                                  : null,
                            ),
                            child: Text(
                              s.title.isEmpty
                                  ? '·'
                                  : s.title.characters.first.toUpperCase(),
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: dark
                                      ? OnoteColors.moon100
                                      : OnoteColors.graphite700),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
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
        app.notebooks.firstWhere((n) => n.id == app.notebookId);
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(current.title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                      // Where the open notebook lives, said once where the
                      // notebook is named. The status bar's chip answers the
                      // same question but is easy to never look at.
                      SyncDotWithLabel(app: app, notebookId: current.id),
                    ],
                  ),
                ),
                const Icon(Icons.unfold_more, size: 16),
                IconButton(
                  icon: const Icon(Icons.keyboard_double_arrow_left, size: 16),
                  tooltip: 'Collapse the navigator  (Ctrl+)',
                  visualDensity: VisualDensity.compact,
                  onPressed: app.toggleNavCollapsed,
                ),
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
  final _taps = _DoubleTapGate();
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
    // Plain 12px rows, not tracked small-caps: a narrow sections column has
    // to fit real course names, and the caps identity now lives on the pages
    // pane's header where there is room for it.
    final labelStyle = TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        fontStyle: pageTarget ? FontStyle.italic : FontStyle.normal,
        color: emphasised
            ? scheme.primary
            : dark
                ? OnoteColors.moon100
                : OnoteColors.graphite700);
    return InkWell(
      // No onDoubleTap — it deferred every click (see _DoubleTapGate).
      onTap: _renaming
          ? null
          : () {
              if (_taps.tap()) {
                setState(() => _renaming = true);
                return;
              }
              app.activateSection(section.id);
            },
      onTapDown: (d) => _downPos = d.globalPosition,
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
        padding: const EdgeInsets.fromLTRB(6, 7, 6, 7),
        child: Row(
          children: [
            const SizedBox(width: 4),
            Container(
              width: 3.5,
              height: 16,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(4)),
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
                      pageTarget ? 'move here' : section.title,
                      overflow: TextOverflow.ellipsis,
                      style: labelStyle,
                    ),
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
  await showOnoteDialog<void>(
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
                              style: TextStyle(
                                  fontSize: 11,
                                  color: context.surfaces.textSecondary)),
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
                                      final ok = await _confirmPurgeNotebook(
                                          ctx, nb,
                                          caveat: app.purgeCaveat(nb.id));
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

Future<bool> _confirmPurgeNotebook(BuildContext context, NotebookRef nb,
    {String? caveat}) async {
  final ok = await showOnoteDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete permanently?'),
      content: Text(
          '“${nb.title}” and all its pages will be removed for good. This can\'t '
          'be undone.${caveat == null ? '' : '\n\n$caveat'}'),
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
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: .6,
                color: context.surfaces.textSecondary)),
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
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: scheme.primary),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
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
        Icon(icon, size: 16, color: Colors.white),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 12)),
      ]),
    ),
  );
}

/// What dropping at the current pointer position would do (ORG-2).
enum _DropZone { none, before, into, after }

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
  final _taps = _DoubleTapGate();
  Offset _downPos = Offset.zero; // last pointer-down, for long-press menus

  AppState get app => widget.app;
  TreeNode get page => widget.page;

  @override
  Widget build(BuildContext context) {
    // Drop a page ONTO this page → make it a subpage (ORG-6).
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) =>
          d.data != page.id && app.node(d.data)?.kind == NodeKind.page,
      onMove: (d) {
        // Which third of the tile the pointer is over decides the gesture:
        // edges reorder, middle nests. Tracked on move so the affordance can
        // show what the drop will do BEFORE the user commits (ORG-2).
        final zone = _dropZoneAt(d.offset);
        if (zone != _zone) setState(() => _zone = zone);
      },
      onLeave: (_) => setState(() => _zone = _DropZone.none),
      onAcceptWithDetails: (d) {
        final zone = _zone;
        setState(() => _zone = _DropZone.none);
        switch (zone) {
          case _DropZone.before:
            app.reorderNode(d.data, page.id, after: false);
          case _DropZone.after:
            app.reorderNode(d.data, page.id, after: true);
          case _DropZone.into:
          case _DropZone.none:
            app.makeSubpageOf(d.data, page.id);
        }
      },
      builder: (ctx, cand, rej) {
        final active = cand.isNotEmpty;
        final tile = _tile(context,
            subpageTarget: active && _zone == _DropZone.into);
        if (active && (_zone == _DropZone.before || _zone == _DropZone.after)) {
          // An insertion line, the universal "it will land here" signal.
          final line = Container(
            height: 2,
            color: Theme.of(context).colorScheme.primary,
          );
          return Column(mainAxisSize: MainAxisSize.min, children: [
            if (_zone == _DropZone.before) line,
            tile,
            if (_zone == _DropZone.after) line,
          ]);
        }
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

  /// Where in the tile a drag currently hovers.
  _DropZone _zone = _DropZone.none;

  /// Edges reorder, middle nests. A quarter each end is enough to hit without
  /// making nesting hard to reach.
  _DropZone _dropZoneAt(Offset globalOffset) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return _DropZone.into;
    final local = box.globalToLocal(globalOffset);
    final h = box.size.height;
    if (h <= 0) return _DropZone.into;
    if (local.dy < h * 0.25) return _DropZone.before;
    if (local.dy > h * 0.75) return _DropZone.after;
    return _DropZone.into;
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
        // No onDoubleTap — it deferred every click (see _DoubleTapGate).
        onTap: _renaming
            ? null
            : () {
                if (_taps.tap()) {
                  setState(() => _renaming = true);
                  return;
                }
                app.selectPage(page.id);
              },
        onTapDown: (d) => _downPos = d.globalPosition,
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
                            size: 16,
                            color: context.surfaces.textSecondary),
                      )
                    : null,
              ),
              Icon(
                  page.level == 0
                      ? Icons.description_outlined
                      : Icons.subdirectory_arrow_right,
                  size: 16,
                  color: selected ? scheme.primary : context.surfaces.textSecondary),
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
          Icon(icon, size: OnoteIcon.xl, color: context.surfaces.textSecondary),
          const SizedBox(height: 8),
          Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, color: context.surfaces.textSecondary)),
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
        // The colour chip is the obvious thing to right-click, so this is
        // where people look for it — a row of swatches rather than a submenu,
        // because picking a colour is one glance and one click.
        PopupMenuItem<String>(
          enabled: false,
          height: 34,
          child: _SectionColorRow(app: app, section: node),
        ),
        const PopupMenuDivider(),
        // The one-click add lived on every section row until the two-column
        // layout tightened those rows; the pages pane's [+] covers the ACTIVE
        // section, and this covers the rest.
        _nodeItem('newpage', Icons.note_add_outlined, 'New page'),
        _nodeItem('togroup', Icons.drive_file_move_outline, 'Move to group…'),
        _nodeItem('sortaz', Icons.sort_by_alpha, 'Sort pages A→Z'),
        _nodeItem('sortdate', Icons.schedule, 'Sort pages by last edited'),
        // The navigator is where a student thinks in subjects rather than in
        // decks, so it is the more natural of the two places an exam date is
        // set. The label carries the current value: a menu that says only
        // "Exam date…" makes you open a dialog to find out whether there is
        // one.
        // The unit a student shares is "my notes for week 6", which is a
        // section far more often than a page — and for an imported deck it is
        // the whole deck. Vector export made the output worth sending.
        _nodeItem('sectionpdf', Icons.picture_as_pdf_outlined,
            'Export section as PDF…'),
        _nodeItem('printsection', Icons.print_outlined, 'Print section…'),
        if (app.study.examDate(node.id) case final exam?) ...[
          _nodeItem('exam', Icons.flag_outlined,
              _examMenuLabel(context, app, node.id, exam)),
          _nodeItem('examclear', Icons.event_busy_outlined, 'Remove exam date'),
        ] else
          _nodeItem('exam', Icons.event_outlined, 'Set exam date…'),
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
        _nodeItem(
            'favourite',
            app.isFavourite(node.id) ? Icons.star : Icons.star_border,
            app.isFavourite(node.id) ? 'Remove favourite' : 'Add to favourites'),
        _nodeItem('sharepdf', Icons.picture_as_pdf_outlined, 'Share as PDF…'),
        _nodeItem('print', Icons.print_outlined, 'Print…'),
        _nodeItem('copylink', Icons.link, 'Copy link to page'),
        _nodeItem('history', Icons.history, 'Version history…'),
        _nodeItem('template', Icons.bookmark_add_outlined, 'Save as template…'),
      ],
      const PopupMenuDivider(),
      // Available on every kind, because the ask was "a page ... a section, or
      // a section group" and protection is resolved by walking up from a page
      // to whichever of those carries it.
      if (app.protectionFor(node.id) != null)
        _nodeItem('unprotect', Icons.lock_open_outlined, 'Remove passcode…')
      else
        _nodeItem('protect', Icons.lock_outline, 'Lock with a passcode…'),
      const PopupMenuDivider(),
      _nodeItem('delete', Icons.delete_outline, 'Delete', danger: true),
    ],
  );
  if (!context.mounted) return;
  switch (action) {
    case 'protect':
      final set = await askNewPasscode(context, node.title);
      if (set == null) return;
      app.protectNode(node.id, set.passcode, set.policy);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('“${node.title}” is locked. It is hidden inside '
                'Openote, not encrypted in the file.')));
      }
    case 'unprotect':
      final ok = await askToUnlock(
          context, node.title, (pw) => app.unprotectNode(node.id, pw));
      if (ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Passcode removed from “${node.title}”.')));
      }
    case 'up':
      app.moveNode(node.id, -1);
    case 'down':
      app.moveNode(node.id, 1);
    case 'newpage':
      await app.addPage(sectionId: node.id);
    case 'sortaz':
      app.sortSection(node.id, byTitle: true);
    case 'sortdate':
      app.sortSection(node.id, byTitle: false);
    case 'exam':
      await pickExamDate(context, app, node.id);
    case 'examclear':
      if (context.mounted) clearExamDate(context, app, node.id);
    case 'favourite':
      app.toggleFavourite(node.id);
    case 'print':
      if (app.pageId != node.id) await app.selectPage(node.id);
      await printCurrentPage(app);
    case 'printsection':
      await printSection(app, node.id);
    case 'sharepdf':
      if (app.pageId != node.id) await app.selectPage(node.id);
      if (!context.mounted) return;
      final saved = await exportPagePdfVector(app);
      if (saved != null && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Saved to $saved')));
      }
    case 'sectionpdf':
      final messenger = ScaffoldMessenger.of(context);
      final saved = await exportSectionPdfVector(app, node.id);
      if (saved != null) {
        messenger.showSnackBar(SnackBar(content: Text('Saved to $saved')));
      }
    case 'copylink':
      // The wiki-link form the editor already resolves. Copying it means
      // cross-referencing is paste, not retype-and-hope.
      await Clipboard.setData(
          ClipboardData(text: '[[${node.title}|${node.id}]]'));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Link copied — paste it into any page')));
      }
    case 'togroup':
      final groups = app.nodes
          .where((n) => n.kind == NodeKind.sectionGroup)
          .toList();
      final choice = await showOnoteDialog<String>(
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
  // Through [promptForText], which owns the field's controller in the dialog's
  // own State. This used to build the field here and `controller.dispose()`
  // straight after the await — the route is popped by then but its 150 ms exit
  // transition has not finished, so the field was still mounted and still
  // rebuilding against a dead controller. Same defect as the new-notebook
  // prompt, which is what crashed the app.
  final name = await promptForText(context,
      title: 'Save as template', okLabel: 'Save', hintText: 'Template name');
  if (name == null) return;
  app.saveCurrentAsTemplate(name);
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Template "$name" saved')));
  }
}

/// Version history dialog (SYNC-8): restore any snapshot of the current page.
Future<void> showVersionHistory(BuildContext context, AppState app) async {
  final versions = app.pageVersions();
  await showOnoteDialog<void>(
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

/// The colour swatches inside a section's context menu.
///
/// Lives in a disabled `PopupMenuItem` so the row itself isn't a menu action —
/// each swatch closes the menu on its own. That keeps the picker inline
/// (one glance, one click) instead of behind a submenu, which is what you
/// want from something you reached by right-clicking the colour chip.
class _SectionColorRow extends StatefulWidget {
  const _SectionColorRow({required this.app, required this.section});
  final AppState app;
  final TreeNode section;

  @override
  State<_SectionColorRow> createState() => _SectionColorRowState();
}

class _SectionColorRowState extends State<_SectionColorRow> {
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final current = widget.app.node(widget.section.id)?.color;
    return Row(children: [
      const Text('Colour',
          style: TextStyle(fontSize: 13, color: OnoteColors.graphite500)),
      const SizedBox(width: 10),
      for (final token in AppState.sectionColorTokens)
        Padding(
          padding: const EdgeInsets.only(right: 5),
          child: Tooltip(
            message: token ?? 'Default',
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                widget.app.setNodeColor(widget.section.id, token);
                Navigator.of(context).pop();
              },
              child: Container(
                width: 19,
                height: 19,
                decoration: BoxDecoration(
                  color: _sectionColor(token, dark),
                  shape: BoxShape.circle,
                  border: token == current
                      ? Border.all(color: scheme.onSurface, width: 2)
                      : null,
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// "Exam 12 Nov, 9:00 am · in 3 weeks…" — the section menu's exam row.
///
/// A function rather than an inline interpolation because the optional time
/// makes it a two-branch string, and a two-branch string inside a list literal
/// is where a `?:` chain stops being readable.
String _examMenuLabel(
    BuildContext context, AppState app, String sectionId, DateTime exam) {
  final now = DateTime.now();
  final minute = app.study.examMinuteOfDay(sectionId);
  final when = minute == null
      ? formatExamDate(exam, now)
      : '${formatExamDate(exam, now)}, ${examTimeLabel(context, minute)}';
  return 'Exam $when · ${formatCountdown(daysBetween(now, exam))}…';
}
