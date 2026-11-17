import 'opening_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/focus_claim.dart';
import '../export/pdf_vector_export.dart';
import '../export/print_page.dart';
import '../model/models.dart';
import '../planner/agenda.dart';
import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../study/study_stats.dart';
import '../theme/onote_theme.dart';
import 'exam_date.dart';
import 'notebook_manager.dart';
import 'protect_dialog.dart';
import 'sync_dot.dart';
import 'planner_format.dart';
import '../theme/section_palette.dart';
import '../theme/tokens.dart';
import 'onote_dialog.dart';
import 'toast.dart';

Color _sectionColor(String? token, bool dark) => sectionColorFor(token, dark);

/// The ring that marks a section, in its colour (see `theme/section_palette`).
class _SectionRing extends StatelessWidget {
  const _SectionRing({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
      width: 16,
      height: 16,
      child: CustomPaint(painter: SectionRingPainter(color)));
}

/// Hover wash for navigator rows: neutral, and quieter than the tinted wash a
/// selected section gets, so the two never read as the same thing.
Color _hoverWash(bool dark) =>
    dark ? const Color(0x12E6E3EC) : const Color(0x0F211F1B);

/// A group's colour, from the first section on its rail.
Color _groupColor(AppState app, TreeNode group, bool dark) {
  final first = app.nodes
      .where((n) => n.kind == NodeKind.section && n.parentId == group.id)
      .firstOrNull;
  return groupColorFor(first?.color, dark, hasSections: first != null);
}

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
          // The sections column folded away is width the navigator stops
          // spending, which is the whole point of folding it — see
          // [AppState.navSectionsCollapsed].
          width: app.navSectionsCollapsed
              ? app.navPagesW
              : app.navSectionsW + app.navPagesW,
          color: context.surfaces.chrome2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _NotebookHeader(app: app),
              _searchRow(context),
              const Divider(height: 1),
              Expanded(
                child: _NavPaneKeys(
                  app: app,
                  child: searching
                      ? _searchResults(context)
                      : _twoColumnBody(context),
                ),
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
    final l = L.of(context);
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
                  hintText: l.navSearchHint,
                  hintStyle: const TextStyle(fontSize: 13),
                  prefixIcon: const Icon(Icons.search, size: 16),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  suffixIcon: _query.isEmpty
                      ? null
                      : InkWell(
                          mouseCursor: WidgetStateMouseCursor.clickable,
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
    final l = L.of(context);
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
        child: Text(l.navNoMatches(_query.trim()),
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
            child: Text(l.navInPageContent,
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
              title: Text(app.node(h.pageId)?.title ?? l.navUntitled,
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
    final l = L.of(context);
    final sections =
        app.nodes.where((n) => n.kind == NodeKind.section).toList();
    if (sections.isEmpty && app.openingNotebook) return const OpeningMark();
    if (sections.isEmpty) {
      return _EmptyHint(
        icon: Icons.folder_outlined,
        text: l.navNoSections,
        actionLabel: l.navNewSection,
        onAction: app.addSection,
      );
    }
    final active = app.activeSection ?? sections.first;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Both of these go together: a drag handle for a column that is not
        // there resizes nothing and sits in the way of the pages.
        if (!app.navSectionsCollapsed) ...[
          SizedBox(
            width: app.navSectionsW,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionsHeader(app: app),
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
        ],
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
    final l = L.of(context);
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
              _SectionRing(color: color),
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
              _PlusButton(
                key: const ValueKey('nav-add-page'),
                label: l.navNewPageIn(section.title),
                onPressed: () => app.addPage(sectionId: section.id),
              ),
            ],
          ),
        ),
        Expanded(
          child: _DropAtEnd(
            app: app,
            kind: NodeKind.page,
            child: pages.isEmpty
                ? Center(
                    child: Text(l.navNoPages,
                        style: TextStyle(
                            fontSize: 12,
                            color: context.surfaces.textSecondary)),
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 12),
                    children: pages,
                  ),
          ),
        ),
      ],
    );
  }

  // ── Section list (groups → sections) ──────────────────────────────────

  Widget _sectionsColumn(BuildContext context) {
    final l = L.of(context);
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
        text: l.navNoSections,
        actionLabel: l.navNewSection,
        onAction: app.addSection,
      );
    }

    Widget row(TreeNode s) => _SectionHeader(
        key: ValueKey(s.id),
        app: app,
        section: s,
        dark: dark,
        active: app.activeSectionId == s.id);

    return _DropAtEnd(
      app: app,
      kind: NodeKind.section,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 8),
        children: [
        for (final g in groups) ...[
          _GroupHeader(key: ValueKey(g.id), app: app, group: g),
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
                        width: 2, color: _groupColor(app, g, dark)),
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
      ),
    );
  }

  // ── Footer toolbar ────────────────────────────────────────────────────

  /// Whether the recycle bin's panel is up, so its place can show it.
  bool _binOpen = false;

  /// **Places, not buttons.** Adding a section or a group moved to the plus
  /// above the section list, which leaves the foot of the navigator for where
  /// you go: Recent, and the Recycle bin. Both on one row, so they take half
  /// the height the two stacked rows did. See [_Places].
  Widget _footer(BuildContext context) => _Places(
        app: app,
        binOpen: _binOpen,
        onBin: (row) async {
          setState(() => _binOpen = true);
          await showRecycleBin(context, app, anchor: row);
          if (mounted) setState(() => _binOpen = false);
        },
      );
}

class _GroupHeader extends StatefulWidget {
  const _GroupHeader({super.key, required this.app, required this.group});
  final AppState app;
  final TreeNode group;

  @override
  State<_GroupHeader> createState() => _GroupHeaderState();
}

class _GroupHeaderState extends State<_GroupHeader> {
  bool _renaming = false;

  /// Turn this row into a field. The menu's Rename and the double-click are
  /// the same gesture as far as the row is concerned.
  void _startRename() {
    if (mounted) setState(() => _renaming = true);
  }
  final _taps = _DoubleTapGate();
  Offset _downPos = Offset.zero; // last pointer-down, for long-press menus

  /// This row's place in the keyboard, handed to its `InkWell` so there is one
  /// focus node rather than two — see [_nodeDeleteKey].
  late final NavRowFocus _rowFocus = NavRowFocus(
      debugLabel: 'nav-group',
      onKeyEvent: (n, e) => _nodeDeleteKey(context, app, group, n, e));

  AppState get app => widget.app;
  TreeNode get group => widget.group;

  @override
  void initState() {
    super.initState();
    // A group that has just been made opens for its name to be typed over.
    if (app.groupToRename == group.id) {
      app.groupToRename = null;
      _renaming = true;
    }
  }

  @override
  void dispose() {
    _DropPill.hide();
    _rowFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final collapsed = app.collapsedGroups.contains(group.id);
    final scheme = Theme.of(context).colorScheme;
    final l = L.of(context);
    // Drop a section ONTO a group → move it into the group (ORG-1).
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) =>
          app.node(d.data)?.kind == NodeKind.section,
      onMove: (d) => _DropPill.show(
          context, d.offset, l.dropMoveIntoGroup, Icons.folder_outlined),
      onLeave: (_) => _DropPill.hide(),
      onAcceptWithDetails: (d) {
        _DropPill.hide();
        app.moveSectionToGroup(d.data, group.id);
      },
      builder: (ctx, cand, rej) {
        final target = cand.isNotEmpty;
        final labelStyle = TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontStyle: target ? FontStyle.italic : FontStyle.normal,
            color: target ? scheme.primary : null);
        return InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          focusNode: _rowFocus,
          onFocusChange: (has) {
            if (has) _keyboardEnteredRow(app);
          },
          // No onDoubleTap — it deferred every click (see _DoubleTapGate).
          onTap: _renaming
              ? null
              : () {
                  if (_taps.tap()) {
                    setState(() => _renaming = true);
                    return;
                  }
                  // The click is what aims the keyboard at this row; an InkWell
                  // does not take focus on tap of its own accord.
                  _rowFocus.requestFocus();
                  app.toggleGroupCollapsed(group.id);
                },
          onTapDown: (d) => _downPos = d.globalPosition,
          onSecondaryTapUp: (d) => showNodeMenu(context, app, group,
              canIndent: false,
              position: d.globalPosition,
              onRename: _startRename),
          onLongPress: () => showNodeMenu(context, app, group,
              canIndent: false, position: _downPos, onRename: _startRename),
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
                const SizedBox(width: 6),
                // A small folder in the group's colour, not a dot: a dot beside
                // a name is what "unread" and "unsaved" look like.
                Icon(Icons.folder_outlined,
                    size: 14,
                    color: _groupColor(app, group,
                        Theme.of(context).brightness == Brightness.dark)),
                const SizedBox(width: 8),
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
                      : Text(group.title,
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
/// **The empty space under a list is "put it at the end".**
///
/// The owner: *"if i drop it anywhere in the column below the existing pages,
/// it should move it to the bottom."* Dragging in this navigator only ever
/// aimed at a ROW — one to go above, below, or inside — so a drop into the
/// space past the last row hit nothing at all and the drag was abandoned.
/// That space is the most obvious place to aim for "last", and it is exactly
/// where a hand overshooting a short list ends up.
///
/// It WRAPS the list rather than sitting under it, because a list that fills
/// its column leaves nothing to sit under. Flutter resolves a drop to the
/// innermost target beneath the pointer, so a row still answers for itself
/// and this only hears about the drops no row wanted.
class _DropAtEnd extends StatefulWidget {
  const _DropAtEnd(
      {required this.app, required this.kind, required this.child});

  final AppState app;

  /// What this list holds, and therefore what it will take. A page dropped on
  /// the sections column is not "the last section".
  final NodeKind kind;

  final Widget child;

  @override
  State<_DropAtEnd> createState() => _DropAtEndState();
}

class _DropAtEndState extends State<_DropAtEnd> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) =>
          widget.app.node(d.data)?.kind == widget.kind,
      onMove: (_) {
        if (!_over) setState(() => _over = true);
      },
      onLeave: (_) => setState(() => _over = false),
      onAcceptWithDetails: (d) {
        setState(() => _over = false);
        // A section dropped below every group belongs to the notebook now,
        // not to whichever group it was dragged out of. A page's section is
        // decided by the column it was dropped in, which has not changed.
        widget.app.moveNodeToEnd(d.data,
            reparent: widget.kind == NodeKind.section);
      },
      builder: (ctx, cand, rej) => Stack(children: [
        Positioned.fill(child: widget.child),
        // The same insertion line a row draws, at the end of the list, so the
        // affordance says the same thing in both places.
        if (_over && cand.isNotEmpty)
          Positioned(
            left: 8,
            right: 8,
            bottom: 6,
            child: Container(height: 2, color: scheme.primary),
          ),
      ]),
    );
  }
}

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

/// A plus beside a list's heading: 28 square, tinted while what it opened is
/// still open. The page list's and the section list's are the same button, so
/// the two headings line up and the two plusses read as one idea.
class _PlusButton extends StatelessWidget {
  const _PlusButton(
      {super.key,
      required this.label,
      required this.onPressed,
      this.open = false});

  /// What it does, for a screen reader. No tooltip: a plus beside a list's
  /// heading says what it adds to, and a bubble on hover is clutter.
  final String label;
  final VoidCallback onPressed;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: label,
      button: true,
      excludeSemantics: true,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(6),
        onTap: onPressed,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
              color: open ? scheme.primary.withValues(alpha: .14) : null,
              borderRadius: BorderRadius.circular(6)),
          child: Icon(Icons.add,
              size: 16,
              color: open ? scheme.primary : context.surfaces.textPrimary),
        ),
      ),
    );
  }
}

/// The heading above the section list, with the plus that adds to it.
///
/// **One plus, like the page list has.** It opens a short menu rather than
/// adding at once, because a section list can be added to two ways: a section,
/// or a group to put sections in. The new-section row carries the colour the
/// section would take, so nothing about it is a surprise.
class _SectionsHeader extends StatefulWidget {
  const _SectionsHeader({required this.app});
  final AppState app;

  @override
  State<_SectionsHeader> createState() => _SectionsHeaderState();
}

class _SectionsHeaderState extends State<_SectionsHeader> {
  bool _open = false;

  Future<void> _menu(BuildContext button) async {
    final app = widget.app;
    final l = L.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final overlay = Overlay.of(button).context.findRenderObject() as RenderBox;
    final box = button.findRenderObject() as RenderBox;
    final rect = Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero),
            ancestor: overlay));
    setState(() => _open = true);
    final chosen = await showMenu<String>(
      context: button,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      items: [
        PopupMenuItem<String>(
          value: 'section',
          height: 36,
          child: Row(children: [
            _SectionRing(
                color: _sectionColor(app.nextSectionColorToken, dark)),
            const SizedBox(width: 10),
            Expanded(
                child: Text(l.navNewSection,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13))),
          ]),
        ),
        _nodeItem('group', Icons.create_new_folder_outlined,
            l.navNewSectionGroup),
      ],
    );
    if (mounted) setState(() => _open = false);
    switch (chosen) {
      case 'section':
        await app.addSection();
      case 'group':
        app.addSectionGroup();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l.navSectionsHeader.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: .6,
                color: dark ? OnoteColors.moon300 : OnoteColors.graphite500,
              ),
            ),
          ),
          Builder(
            builder: (button) => _PlusButton(
                key: const ValueKey('nav-add-section'),
                label: l.navNewSectionOrGroup,
                open: _open,
                onPressed: () => _menu(button)),
          ),
        ],
      ),
    );
  }
}

/// The label that follows the pointer while something is dragged over the
/// navigator, saying what letting go will do.
///
/// Drawn in the overlay, not in the row: a row is clipped to its list and
/// painted over by the row below it, and this has to sit across both. One at a
/// time, so it is one shared thing rather than one per row.
class _DropPill {
  static OverlayEntry? _entry;
  static final _what =
      ValueNotifier<({Offset at, String label, IconData icon})?>(null);

  static void show(
      BuildContext context, Offset at, String label, IconData icon) {
    _what.value = (at: at, label: label, icon: icon);
    if (_entry != null) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _entry = OverlayEntry(
      builder: (ctx) => ValueListenableBuilder(
        valueListenable: _what,
        builder: (ctx, v, _) {
          if (v == null) return const SizedBox.shrink();
          final s = ctx.surfaces;
          return Positioned(
            left: v.at.dx + 18,
            top: v.at.dy + 30,
            child: IgnorePointer(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: s.textPrimary,
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x66000000),
                          blurRadius: 12,
                          offset: Offset(0, 4))
                    ],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(v.icon, size: 16, color: s.canvas),
                    const SizedBox(width: 6),
                    Text(v.label,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: s.canvas)),
                  ]),
                ),
              ),
            ),
          );
        },
      ),
    );
    overlay.insert(_entry!);
  }

  static void hide() {
    _what.value = null;
    final e = _entry;
    _entry = null;
    if (e == null) return;
    e.remove();
    e.dispose();
  }
}

/// The places at the foot of the navigator: **Recent** and the **Recycle bin**,
/// on one row.
///
/// Not two buttons stacked, and not a bare icon: a place with a name and a
/// count reads as somewhere you go, where a bin with a small arrow in it read
/// as "delete this". The navigator's own width decides how much is drawn: the
/// bin's name goes first, the count moves onto its corner, and below that only
/// the icons stay, each with its tooltip.
class _Places extends StatelessWidget {
  const _Places({required this.app, required this.binOpen, required this.onBin});
  final AppState app;
  final bool binOpen;

  /// Called with the rectangle of the whole row, so the panel can open above it.
  final void Function(Rect row) onBin;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final recentLabel = w > 150;
      final binLabel = w > 230;
      final count = app.binCount;
      return SizedBox(
        height: 36,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Flexible(
              child: _Place(
                  icon: Icons.history,
                  label: recentLabel ? l.navRecent : null,
                  tooltip: l.navRecentTip,
                  on: app.navHome,
                  onTap: app.openHome),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: _Place(
                  icon: Icons.delete_outline,
                  label: binLabel ? l.navRecycleBin : null,
                  tooltip: l.navRecycleBin,
                  on: binOpen,
                  count: count,
                  badge: !binLabel,
                  onTap: () {
                    final row = context.findRenderObject() as RenderBox;
                    onBin(row.localToGlobal(Offset.zero) & row.size);
                  }),
            ),
          ]),
        ),
      );
    });
  }
}

class _Place extends StatelessWidget {
  const _Place({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.label,
    this.on = false,
    this.count = 0,
    this.badge = false,
  });
  final IconData icon;
  final String? label;
  final String tooltip;
  final bool on;
  final int count;

  /// The count sits on the icon's corner instead of beside the name.
  final bool badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = context.surfaces;
    final fg = on ? scheme.primary : s.textSecondary;
    // A place with its name showing needs no bubble saying it again. Only when
    // the navigator is too narrow for the name (the icon stands alone) does
    // the tooltip earn its place.
    Widget named(Widget child) =>
        label == null ? Tooltip(message: tooltip, child: child) : child;
    return named(
      InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            height: 28,
            padding: EdgeInsets.symmetric(horizontal: label == null ? 8 : 9),
            decoration: BoxDecoration(
                color: on ? scheme.primary.withValues(alpha: .14) : null,
                borderRadius: BorderRadius.circular(6)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: fg),
              if (label != null) ...[
                const SizedBox(width: 7),
                Flexible(
                  child: Text(label!,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: fg)),
                ),
              ],
              if (count > 0 && !badge) ...[
                const SizedBox(width: 7),
                _CountPill(count, small: false),
              ],
            ]),
          ),
          if (count > 0 && badge)
            Positioned(top: -3, right: -3, child: _CountPill(count, small: true)),
        ]),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill(this.n, {required this.small});
  final int n;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final h = small ? 16.0 : 18.0;
    return Container(
      constraints: BoxConstraints(minWidth: h),
      height: h,
      padding: EdgeInsets.symmetric(horizontal: small ? 4 : 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: small ? s.border : s.border.withValues(alpha: .7),
          borderRadius: BorderRadius.circular(h / 2)),
      child: Text('$n',
          style: TextStyle(
              fontSize: small ? 10 : 11, height: 1, color: s.textSecondary)),
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
    final l = L.of(context);
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
          mouseCursor: WidgetStateMouseCursor.clickable,
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
                    Text(page.title.isEmpty ? l.navUntitled : page.title,
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
    final l = L.of(context);
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
            Text(l.navComingUp,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .6,
                    color: context.surfaces.textSecondary)),
            const Spacer(),
            InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
              onTap: app.openPlanner,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(total > _max ? l.navAllCount(total) : l.navOpen,
                    style: TextStyle(fontSize: 11, color: scheme.primary)),
              ),
            ),
          ]),
        ),
        if (alerts > 0)
          InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
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
            mouseCursor: WidgetStateMouseCursor.clickable,
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
    final l = L.of(context);
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
            tooltip: l.navExpand,
            visualDensity: VisualDensity.compact,
            onPressed: app.toggleNavCollapsed,
          ),
          Tooltip(
            message: current.title,
            child: InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
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
            tooltip: l.navRecentTip,
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
                          mouseCursor: WidgetStateMouseCursor.clickable,
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
    final l = L.of(context);
    final scheme = Theme.of(context).colorScheme;
    final current =
        app.notebooks.firstWhere((n) => n.id == app.notebookId,
            // **Never throws.** This ran `firstWhere` with no `orElse`, so a
            // `notebookId` naming a notebook that had just been deleted took
            // the entire sidebar down with `Bad state: No element` — and an
            // error widget inside a stretched Column then reported an
            // overflow of ninety-odd thousand pixels, which is what somebody
            // actually sees.
            //
            // The cause is fixed where it belongs, in
            // `discardImportedNotebook`. This stays because a header is not
            // a place worth crashing from: whatever goes wrong upstream, the
            // chrome should still draw.
            orElse: () => NotebookRef(
                  id: app.notebookId ?? '',
                  title: '',
                  file: '',
                ));
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 4),
      child: Tooltip(
        message: l.navNotebooksTip,
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
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
                // **Beside the one that folds the whole navigator**, because
                // it is the same question asked about a smaller part of it.
                // Not in the pages pane's own header, which would read better
                // and is not drawn on Home — and a button you can fold the
                // sections away with but then cannot find again is worse than
                // no button at all.
                IconButton(
                  icon: Icon(
                      app.navSectionsCollapsed
                          ? Icons.chevron_right
                          : Icons.chevron_left,
                      size: 16),
                  tooltip: app.navSectionsCollapsed
                      ? l.navShowSections
                      : l.navHideSections,
                  isSelected: app.navSectionsCollapsed,
                  visualDensity: VisualDensity.compact,
                  onPressed: app.toggleNavSectionsCollapsed,
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_double_arrow_left, size: 16),
                  tooltip: l.navCollapse,
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
    super.key,
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

  /// Turn this row into a field. The menu's Rename and the double-click are
  /// the same gesture as far as the row is concerned.
  void _startRename() {
    if (mounted) setState(() => _renaming = true);
  }
  final _taps = _DoubleTapGate();
  Offset _downPos = Offset.zero; // last pointer-down, for long-press menus

  /// This row's place in the keyboard, handed to its `InkWell` so there is one
  /// focus node rather than two — see [_nodeDeleteKey].
  late final NavRowFocus _rowFocus = NavRowFocus(
      debugLabel: 'nav-section',
      onKeyEvent: (n, e) => _nodeDeleteKey(context, app, section, n, e));

  AppState get app => widget.app;
  TreeNode get section => widget.section;
  bool get dark => widget.dark;

  @override
  void dispose() {
    _DropPill.hide();
    _rowFocus.dispose();
    super.dispose();
  }

  /// Where in the row a dragged SECTION hovers: the top and bottom quarters
  /// put it above or below, the middle joins the two. The same three places a
  /// dragged page has on a page row.
  _DropZone _zone = _DropZone.none;

  _DropZone _dropZoneAt(Offset globalOffset) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.height <= 0) {
      return _DropZone.into;
    }
    final y = box.globalToLocal(globalOffset).dy / box.size.height;
    if (y < 0.25) return _DropZone.before;
    if (y > 0.75) return _DropZone.after;
    return _DropZone.into;
  }

  bool _isSection(String id) => app.node(id)?.kind == NodeKind.section;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    // Two kinds of thing can be let go here. A PAGE dropped on a section is
    // moved into it (ORG-2); a SECTION dropped on one goes above or below it,
    // or, in the middle, is grouped with it.
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) =>
          app.node(d.data)?.kind == NodeKind.page ||
          (d.data != section.id && _isSection(d.data)),
      onMove: (d) {
        if (!_isSection(d.data)) {
          _DropPill.show(context, d.offset, l.dropMoveToSection,
              Icons.drive_file_move_outlined);
          return;
        }
        final zone = _dropZoneAt(d.offset);
        if (zone != _zone) setState(() => _zone = zone);
        _DropPill.show(
            context,
            d.offset,
            switch (zone) {
              _DropZone.before => l.dropMoveAbove,
              _DropZone.after => l.dropMoveBelow,
              _ => section.parentId != null
                  ? l.dropMoveIntoGroup
                  : l.dropGroupTogether,
            },
            zone == _DropZone.before || zone == _DropZone.after
                ? Icons.drag_indicator
                : Icons.folder_outlined);
      },
      onLeave: (_) {
        _DropPill.hide();
        if (_zone != _DropZone.none) setState(() => _zone = _DropZone.none);
      },
      onAcceptWithDetails: (d) {
        _DropPill.hide();
        final zone = _zone;
        setState(() => _zone = _DropZone.none);
        if (!_isSection(d.data)) {
          app.movePageToSection(d.data, section.id);
          return;
        }
        switch (zone) {
          case _DropZone.before:
            app.reorderNode(d.data, section.id, after: false);
          case _DropZone.after:
            app.reorderNode(d.data, section.id, after: true);
          case _DropZone.into:
          case _DropZone.none:
            app.groupSectionsTogether(d.data, section.id);
        }
      },
      builder: (ctx, cand, rej) {
        final over = cand.isNotEmpty;
        final sectionOver = over && _isSection(cand.first!);
        final edge = sectionOver &&
            (_zone == _DropZone.before || _zone == _DropZone.after);
        // The row lights up for a page dropped on it, and for a section
        // dropped on its middle: the two places letting go puts the thing
        // INSIDE it.
        final header = _header(context,
            target: over && !edge);
        if (_renaming) return header;
        // Section itself is draggable: into groups, and above or below others.
        final row = Draggable<String>(
          data: section.id,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: dragChip(context, section.title, Icons.folder_outlined),
          childWhenDragging: Opacity(opacity: .4, child: _header(context)),
          child: header,
        );
        if (!edge) return row;
        // The insertion line, the same one a page row draws.
        final line = Container(
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: Theme.of(context).colorScheme.primary);
        return Column(mainAxisSize: MainAxisSize.min, children: [
          if (_zone == _DropZone.before) line,
          row,
          if (_zone == _DropZone.after) line,
        ]);
      },
    );
  }

  Widget _header(BuildContext context, {bool target = false}) {
    final pageTarget = target;
    final color = _sectionColor(section.color, dark);
    final scheme = Theme.of(context).colorScheme;
    final active = widget.active;
    // Plain 12px rows, not tracked small-caps: a narrow sections column has
    // to fit real course names, and the caps identity now lives on the pages
    // pane's header where there is room for it.
    final labelStyle = TextStyle(
        fontSize: 12,
        fontWeight:
            (active || pageTarget) ? FontWeight.w600 : FontWeight.w400,
        fontStyle: pageTarget ? FontStyle.italic : FontStyle.normal,
        // The selected row is told apart by its tint and weight, not by
        // recolouring the name: the colour belongs to the section's ring.
        color: pageTarget
            ? scheme.primary
            : dark
                ? OnoteColors.moon100
                : OnoteColors.graphite700);
    return InkWell(
      mouseCursor: WidgetStateMouseCursor.clickable,
      hoverColor: _hoverWash(dark),
      focusNode: _rowFocus,
      onFocusChange: (has) {
        if (has) _keyboardEnteredRow(app);
      },
      // No onDoubleTap — it deferred every click (see _DoubleTapGate).
      onTap: _renaming
          ? null
          : () {
              if (_taps.tap()) {
                setState(() => _renaming = true);
                return;
              }
              // The click is what aims the keyboard at this row; an InkWell
              // does not take focus on tap of its own accord.
              _rowFocus.requestFocus();
              app.activateSection(section.id);
            },
      onTapDown: (d) => _downPos = d.globalPosition,
      onSecondaryTapUp: (d) => showNodeMenu(context, app, section,
          canIndent: false,
          position: d.globalPosition,
          onRename: _startRename),
      onLongPress: () => showNodeMenu(context, app, section,
          canIndent: false, position: _downPos, onRename: _startRename),
      child: Container(
        decoration: pageTarget
            ? BoxDecoration(
                border: Border.all(color: scheme.primary, width: 1.5),
                borderRadius: BorderRadius.circular(6),
                color: scheme.primary.withValues(alpha: .06))
            : active
                ? BoxDecoration(
                    color: color.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(6))
                : null,
        padding: const EdgeInsets.fromLTRB(6, 7, 6, 7),
        child: Row(
          children: [
            const SizedBox(width: 4),
            _SectionRing(color: color),
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
                      section.title,
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

/// "Section · 2 days ago": what a recycle bin row is, and when it went in.
String _binLine(L l, String kind, int deletedAtMs) {
  final days = DateTime.now()
      .difference(DateTime.fromMillisecondsSinceEpoch(deletedAtMs))
      .inDays;
  final when = days <= 0
      ? l.navBinWhenToday
      : days == 1
          ? l.navBinWhenYesterday
          : l.navBinWhenDaysAgo(days);
  final what = switch (kind) {
    'page' => l.navBinKindPage,
    'section' => l.navBinKindSection,
    'notebook' => l.navBinKindNotebook,
    _ => l.navBinKindGroup,
  };
  return l.navBinItemLine(what, when);
}

/// The recycle bin (ORG-7): restore or remove for good what was deleted from
/// the open notebook, and deleted notebooks. Things go for good on their own
/// after the retention window (swept when this opens).
///
/// A small panel that opens above [anchor] (the places row it came from), not
/// a dialog in the middle of the window: it is somewhere you glance into. The
/// main action on a row is **Restore**; removing for good is a small cross,
/// which asks first, as does **Empty**.
Future<void> showRecycleBin(BuildContext context, AppState app,
    {Rect? anchor}) async {
  await app.purgeExpiredTrash();
  if (!context.mounted) return;
  final size = MediaQuery.sizeOf(context);
  const width = 304.0;
  await showOnoteDialog<void>(
    context: context,
    growFrom: anchor == null ? null : Offset(anchor.left + 20, anchor.top),
    builder: (ctx) {
      final panel = _RecycleBinPanel(app: app, width: width);
      if (anchor == null) return Center(child: panel);
      final left = anchor.left.clamp(8.0, size.width - width - 8.0);
      return Stack(children: [
        Positioned(
          left: left,
          bottom: size.height - anchor.top + 4,
          child: panel,
        ),
      ]);
    },
  );
}

class _RecycleBinPanel extends StatefulWidget {
  const _RecycleBinPanel({required this.app, required this.width});
  final AppState app;
  final double width;

  @override
  State<_RecycleBinPanel> createState() => _RecycleBinPanelState();
}

class _RecycleBinPanelState extends State<_RecycleBinPanel> {
  AppState get app => widget.app;

  Future<bool> _sure(String body, {String? extra, String? confirm}) async {
    final l = L.of(context);
    final ok = await showOnoteDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(confirm == null
            ? l.navDeleteForeverTitle
            : l.navBinEmptyTitle),
        content: Text(extra == null ? body : '$body\n\n$extra'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: OnoteColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirm ?? l.navDeleteForever),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _removeNotebook(NotebookRef nb) async {
    if (app.livesInSharedFolder(nb.id)) {
      final choice = await askSharedRemoval(context, nb);
      if (choice == SharedRemoval.cancel) return;
      if (choice == SharedRemoval.everywhere) {
        await app.purgeNotebookEverywhere(nb.id);
      } else {
        await app.purgeNotebook(nb.id);
      }
    } else {
      final ok = await _confirmPurgeNotebook(context, nb,
          caveat: app.purgeCaveat(nb.id));
      if (!ok) return;
      await app.purgeNotebook(nb.id);
    }
    if (mounted) setState(() {});
  }

  Future<void> _empty(List<NotebookRef> notebooks,
      List<({String id, String kind, String title, int deletedAt})> items) async {
    final l = L.of(context);
    final shared = notebooks.any((n) => app.livesInSharedFolder(n.id));
    final ok = await _sure(l.navBinEmptyBody,
        extra: shared ? l.navBinEmptySharedNote : null,
        confirm: l.navBinEmptyAction);
    if (!ok) return;
    for (final it in items) {
      app.purgeDeleted(it.id);
    }
    // A notebook in a shared folder is taken off this computer only: the same
    // default as removing it from here by hand, and the note above says so.
    for (final nb in notebooks) {
      await app.purgeNotebook(nb.id);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final s = context.surfaces;
    final notebooks = app.trashedNotebooks;
    final items = app.deletedNodes();
    final empty = notebooks.isEmpty && items.isEmpty;
    final retention = app.recycleRetentionDays;
    final maxH = MediaQuery.sizeOf(context).height * .6;
    return Material(
      color: s.raised,
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: widget.width, minWidth: widget.width, maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
              child: Row(children: [
                Expanded(
                  child: Text(l.navRecycleBin,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                      minimumSize: const Size(0, 24),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      foregroundColor: s.textSecondary),
                  onPressed: empty ? null : () => _empty(notebooks, items),
                  child: Text(l.navBinEmptyAction,
                      style: const TextStyle(fontSize: 12)),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(l.navBinRetention(retention),
                  style: TextStyle(fontSize: 11, color: s.textSecondary)),
            ),
            Divider(height: 1, color: s.border),
            if (empty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l.navBinEmpty,
                    style: TextStyle(fontSize: 12, color: s.textSecondary)),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    for (final nb in notebooks)
                      _BinRow(
                        icon: Icons.menu_book_outlined,
                        title: nb.title,
                        line: _binLine(l, 'notebook', nb.deletedAt ?? 0),
                        onRestore: () async {
                          await app.restoreNotebook(nb.id);
                          if (mounted) setState(() {});
                        },
                        onForever: () => _removeNotebook(nb),
                      ),
                    for (final it in items)
                      _BinRow(
                        icon: it.kind == 'page'
                            ? Icons.description_outlined
                            : it.kind == 'section'
                                ? Icons.folder_outlined
                                : Icons.topic_outlined,
                        title: it.title,
                        line: _binLine(l, it.kind, it.deletedAt),
                        onRestore: () async {
                          await app.restoreDeleted(it.id);
                          if (mounted) setState(() {});
                        },
                        onForever: () async {
                          if (await _sure(l.navBinDeleteOneBody(it.title))) {
                            app.purgeDeleted(it.id);
                            if (mounted) setState(() {});
                          }
                        },
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One thing in the recycle bin: what it is and when it went in, a **Restore**
/// that does what it says, and a small cross that only turns red when the
/// pointer reaches for it.
class _BinRow extends StatefulWidget {
  const _BinRow({
    required this.icon,
    required this.title,
    required this.line,
    required this.onRestore,
    required this.onForever,
  });
  final IconData icon;
  final String title;
  final String line;
  final VoidCallback onRestore;
  final VoidCallback onForever;

  @override
  State<_BinRow> createState() => _BinRowState();
}

class _BinRowState extends State<_BinRow> {
  bool _overCross = false;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final s = context.surfaces;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
      child: Row(children: [
        Icon(widget.icon, size: 16, color: s.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title.isEmpty ? l.navUntitled : widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500)),
              Text(widget.line,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: s.textSecondary)),
            ],
          ),
        ),
        TextButton.icon(
          style: TextButton.styleFrom(
              minimumSize: const Size(0, 26),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              foregroundColor: scheme.primary),
          icon: const Icon(Icons.restore_from_trash_outlined, size: 16),
          label: Text(l.navRestore, style: const TextStyle(fontSize: 12)),
          onPressed: widget.onRestore,
        ),
        MouseRegion(
          onEnter: (_) => setState(() => _overCross = true),
          onExit: (_) => setState(() => _overCross = false),
          child: Tooltip(
            message: l.navDeletePermanently,
            child: InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
              borderRadius: BorderRadius.circular(6),
              onTap: widget.onForever,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                    color: _overCross ? s.border.withValues(alpha: .7) : null,
                    borderRadius: BorderRadius.circular(6)),
                child: Icon(Icons.close,
                    size: 16,
                    color: _overCross ? OnoteColors.danger : s.textSecondary),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

Future<bool> _confirmPurgeNotebook(BuildContext context, NotebookRef nb,
    {String? caveat}) async {
  final ok = await showOnoteDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(L.of(ctx).navDeleteForeverTitle),
      content: Text(
          '“${nb.title}” and all its pages will be removed for good. This can\'t '
          'be undone.${caveat == null ? '' : '\n\n$caveat'}'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(L.of(ctx).commonCancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: OnoteColors.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(L.of(ctx).navDeleteForever),
        ),
      ],
    ),
  );
  return ok == true;
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
      // Same hazard as the page title: this field is opened by a click and
      // can only ask once it exists, so it asks through `claimKeyboard` to
      // stop a standing claim on the canvas taking the keyboard back.
      claimKeyboard(_focus);
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

  /// Turn this row into a field. The menu's Rename and the double-click are
  /// the same gesture as far as the row is concerned.
  void _startRename() {
    if (mounted) setState(() => _renaming = true);
  }
  final _taps = _DoubleTapGate();
  Offset _downPos = Offset.zero; // last pointer-down, for long-press menus

  /// This row's place in the keyboard, handed to its `InkWell` so there is one
  /// focus node rather than two — see [_nodeDeleteKey].
  late final NavRowFocus _rowFocus = NavRowFocus(
      debugLabel: 'nav-page',
      onKeyEvent: (n, e) => _nodeDeleteKey(context, app, page, n, e));

  AppState get app => widget.app;
  TreeNode get page => widget.page;

  @override
  void dispose() {
    _DropPill.hide();
    _rowFocus.dispose();
    super.dispose();
  }

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
        final l = L.of(context);
        _DropPill.show(
            context,
            d.offset,
            switch (zone) {
              _DropZone.before => l.dropMoveAbove,
              _DropZone.after => l.dropMoveBelow,
              _ => l.dropMakeSubpage,
            },
            switch (zone) {
              _DropZone.before || _DropZone.after => Icons.drag_indicator,
              _ => Icons.subdirectory_arrow_right,
            });
      },
      onLeave: (_) {
        _DropPill.hide();
        setState(() => _zone = _DropZone.none);
      },
      onAcceptWithDetails: (d) {
        _DropPill.hide();
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
        mouseCursor: WidgetStateMouseCursor.clickable,
        focusNode: _rowFocus,
        onFocusChange: (has) {
          if (has) _keyboardEnteredRow(app);
        },
        // No onDoubleTap — it deferred every click (see _DoubleTapGate).
        onTap: _renaming
            ? null
            : () {
                if (_taps.tap()) {
                  setState(() => _renaming = true);
                  return;
                }
                // The click is what aims the keyboard at this row; an InkWell
                // does not take focus on tap of its own accord.
                _rowFocus.requestFocus();
                app.selectPage(page.id);
              },
        onTapDown: (d) => _downPos = d.globalPosition,
        onSecondaryTapUp: (d) => showNodeMenu(context, app, page,
            canIndent: true,
            position: d.globalPosition,
            onRename: _startRename),
        onLongPress: () => showNodeMenu(context, app, page,
            canIndent: true, position: _downPos, onRename: _startRename),
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
                        mouseCursor: WidgetStateMouseCursor.clickable,
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
                        page.title,
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
      // **Expanded, like the canvas menu this claims to mirror.** A bare
      // `Text` here sizes to its content, and a popup menu is narrower than
      // the longest label in this menu ("Sort pages by last edited", and the
      // exam row carries a date) — so the row overflowed by up to 98px, which
      // is a layout error Flutter paints a striped banner over. It went
      // unnoticed because nothing opened this menu in a test until
      // `node_menu_rename_test.dart` did.
      Expanded(
        child: Text(label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: color)),
      ),
    ]),
  );
}

// ── Delete from the keyboard ──────────────────────────────────────────────
//
// Eric: "Pressing 'Del' when clicking on a page or group doesnt delete it -
// only way to delete is right click and press delete." Kept beside
// [showNodeMenu] on purpose: these are two routes to one soft delete, and
// they drift apart the moment they stop being read together.

/// A focus node belonging to the navigator: a row, or the pane behind the
/// rows.
///
/// The type IS the signal. The shell needs to know "is the keyboard aimed at
/// the tree right now" so that clicking the toolbar can stand a section row
/// down without standing a TEXT FIELD down — and standing text fields down is
/// not survivable, because a toolbar button that took focus from the
/// paragraph would close the editor it was about to format. Asking the type
/// answers exactly that question, where a name or a flag on AppState would be
/// a second thing to keep true.
class NavRowFocus extends FocusNode {
  NavRowFocus({super.debugLabel, super.onKeyEvent, super.skipTraversal});
}

/// The navigator's background: clicking it aims a bare Delete at THE PAGE YOU
/// ARE ON, and — the half that matters — takes the aim off whichever row had
/// it.
///
/// Reported: *"if i click a page it deletes that page, but if i click
/// elsewhere (i.e. in the bar not on a page ...) it will delete the section,
/// it should delete the page here and only delete a section if i manually
/// click on it then press delete"*. Clicking a row focuses it
/// ([_nodeDeleteKey]) and nothing ever took that focus back, so a click on
/// empty space left the keyboard still pointed at a section the user had
/// stopped thinking about — and focus is invisible here, so there was nothing
/// on screen to say which row was armed. A whole section went on one keypress.
///
/// The pointer-down is what re-aims: a row's own `InkWell` claims focus on
/// TAP, which lands after this, so clicking a row still wins and a section is
/// still deleted by clicking that section and pressing Delete. Only clicks
/// that hit no row end up here.
class _NavPaneKeys extends StatefulWidget {
  const _NavPaneKeys({required this.app, required this.child});
  final AppState app;
  final Widget child;

  @override
  State<_NavPaneKeys> createState() => _NavPaneKeysState();
}

class _NavPaneKeysState extends State<_NavPaneKeys> {
  late final NavRowFocus _pane = NavRowFocus(
      debugLabel: 'nav-pane', skipTraversal: true, onKeyEvent: _onKey);

  AppState get app => widget.app;

  @override
  void dispose() {
    _pane.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode n, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey != LogicalKeyboardKey.delete &&
        e.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    // The search field lives in this subtree, and a row sits above its own
    // rename field — the same trap [_textFieldHasKeyboard] was written for.
    if (_textFieldHasKeyboard()) return KeyEventResult.ignored;
    final page = app.node(app.pageId);
    if (page == null) return KeyEventResult.ignored;
    if (app.protectionFor(page.id) != null || app.isLocked(page.id)) {
      ScaffoldMessenger.of(context).showToast(SnackBar(
          content: Text(L.of(context).navLockedCannotDelete(page.title))));
      return KeyEventResult.handled;
    }
    _deleteFromPane(page);
    return KeyEventResult.handled;
  }

  Future<void> _deleteFromPane(TreeNode page) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = L.of(context);
    await app.deleteNode(page.id);
    if (app.node(page.id) != null) return;
    showDeletedSnackBar(messenger, l, app, page);
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _pane.requestFocus(),
        child: Focus(focusNode: _pane, child: widget.child),
      );
}

/// The keyboard's answer to right-click ▸ Delete, for the row that holds focus.
///
/// **Why focus, and not a `selectedNodeId` on [AppState].** The navigator had
/// no notion of "the row you are on": a page row highlights off `app.pageId`
/// and section and group rows carried no selection state at all. A field on
/// [AppState] would be a second source of truth to invalidate on every delete,
/// notebook switch and tree reload — and it still would not say whether the
/// KEYBOARD is aimed here rather than at the canvas. Flutter's focus answers
/// both questions, every row is already an `InkWell` carrying a focus node, and
/// hanging the handler off that node is the shape [_InlineRename] already uses.
///
/// **No confirmation**, because right-click ▸ Delete does not confirm either
/// and two routes to the same recoverable action must not disagree about how
/// dangerous it is — `AppState.deleteNode` soft-deletes into the 30-day recycle
/// bin. The snackbar is the acknowledgement instead: a whole page leaving the
/// tree on one keystroke with nothing said is the failure to avoid.
KeyEventResult _nodeDeleteKey(BuildContext context, AppState app, TreeNode node,
    FocusNode row, KeyEvent e) {
  if (e is! KeyDownEvent) return KeyEventResult.ignored;
  // Both keys, because the key people reach for depends on the keyboard in
  // front of them: Del on Windows and Linux, Backspace on a Mac laptop, which
  // has no Del at all. A `KeyRepeatEvent` is not a `KeyDownEvent`, so holding
  // the key down does not walk the list deleting everything under it.
  if (e.logicalKey != LogicalKeyboardKey.delete &&
      e.logicalKey != LogicalKeyboardKey.backspace) {
    return KeyEventResult.ignored;
  }
  if (_textFieldHasKeyboard()) return KeyEventResult.ignored;
  // A passcode is a standing "not by accident" mark on this node. The menu
  // still offers Delete on a locked one — that is aimed, you opened a menu and
  // chose the red row — but a bare Del is precisely the slip a passcode exists
  // to catch, on a row that may have been clicked only to look at it. Both
  // halves matter: [AppState.protectionFor] is a passcode ON this node, and
  // [AppState.isLocked] catches a page sitting inside a section that is still
  // locked.
  if (app.protectionFor(node.id) != null || app.isLocked(node.id)) {
    ScaffoldMessenger.of(context).showToast(SnackBar(
        content: Text(L.of(context).navLockedCannotDelete(node.title))));
    return KeyEventResult.handled;
  }
  _deleteNodeFromKey(context, app, node, row);
  return KeyEventResult.handled;
}

/// "Deleted section X" with an **Undo** beside it, for every route that
/// deletes a node.
///
/// Short on purpose. It used to read "Deleted “X” — restore it from the
/// recycle bin", which is a sentence asking you to go and find something at
/// the moment you have just realised you did not mean to do it. The button
/// puts it straight back, and Ctrl+Z now does the same
/// ([AppState.pushNodeUndo]), so the sentence has nothing left to explain.
void showDeletedSnackBar(
    ScaffoldMessengerState messenger, L l, AppState app, TreeNode node) {
  final title = node.title;
  final text = switch (node.kind) {
    NodeKind.page => l.navDeletedPage(title),
    NodeKind.section => l.navDeletedSection(title),
    NodeKind.sectionGroup => l.navDeletedGroup(title),
  };
  messenger.hideCurrentSnackBar();
  final toast = messenger.showToast(SnackBar(
    content: Text(text),
    action: SnackBarAction(
        label: l.navUndo, onPressed: () => app.undoNodeDelete(node.id)),
  ));
  // Ctrl+Z (or anything else that brings the thing back) leaves a button on
  // screen offering to do what has already been done. Close the notice the
  // moment the node is in the tree again. Armed only once it has been seen
  // gone, so a caller that shows this a beat before the delete lands is safe.
  var wasGone = app.node(node.id) == null;
  void watch() {
    final back = app.node(node.id) != null;
    if (!back) {
      wasGone = true;
    } else if (wasGone) {
      toast.close();
    }
  }

  app.addListener(watch);
  toast.closed.whenComplete(() => app.removeListener(watch));
}

Future<void> _deleteNodeFromKey(BuildContext context, AppState app,
    TreeNode node, FocusNode row) async {
  final messenger = ScaffoldMessenger.of(context);
  // Taken BEFORE the await below: by the time the delete returns, this row's
  // element may be gone and its context no good for a lookup.
  final deleted = L.of(context);
  // Hand the keyboard on BEFORE this row is destroyed, and before the await:
  // once the tile leaves the tree its focus node is detached and focus falls
  // back to the root scope, leaving the navigator keyboard-dead until the next
  // mouse click. Downwards, because that is where a file explorer leaves you
  // and it puts the row that slid up into this one's place under the keyboard.
  row.nextFocus();
  await app.deleteNode(node.id);
  // Ask the TREE whether it went, rather than assuming the keypress did
  // something. `deleteNode` returns without doing anything on a read-only
  // notebook (see [AppState.notebookIsReadOnly]), and "Deleted X" while X is
  // still sitting in the list is worse than saying nothing at all.
  if (app.node(node.id) != null) return;
  showDeletedSnackBar(messenger, deleted, app, node);
}

/// Is a TEXT FIELD holding the keyboard?
///
/// The gate that keeps Del and Backspace out of the inline rename. A row sits
/// ABOVE its own rename field in the focus chain and Flutter walks that chain
/// upwards from the focused node — so a row's handler runs BEFORE the text
/// editing shortcuts, which live at the `WidgetsApp` root above the whole
/// navigator. Without this, backspacing a typo out of a page's new name deleted
/// the page.
///
/// The same rule the shell stands its own bare keys down on
/// (`AppShell._editableFocused`), minus that one's `MathField` arm: no equation
/// field is ever built inside the navigator.
bool _textFieldHasKeyboard() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  if (ctx.widget is EditableText) return true;
  var found = false;
  ctx.visitAncestorElements((el) {
    if (el.widget is EditableText) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// The keyboard has just landed on a navigator row.
///
/// Clearing the page's block selection is what stops ONE Del deleting TWO
/// things. The shell's global Delete handler (`app_shell.dart`) runs before
/// focus dispatch and cannot see that the navigator now owns the key, so with a
/// block still selected — click a block, click the header of the section you
/// are already in, press Del — the block AND the section both went. Clicking a
/// PAGE row never showed it, because `selectPage` clears the selection on the
/// way past; a section or group row does not go near it.
void _keyboardEnteredRow(AppState app) {
  if (app.selectedIds.isNotEmpty) app.select(null);
}

/// Pop-out node menu (§7a.1): a compact menu anchored at the pointer, focused
/// on actions that can *only* be done here — reorder and structural moves.
///
/// **Rename is here too, despite also being inline.** It used to be left out
/// on the grounds that double-clicking the title already does it, which is
/// true and was not enough: a right-click menu is where people look for "what
/// can I do to this thing", and an action missing from it reads as an action
/// that does not exist. It is first in the list because it is the one most
/// often wanted.
///
/// [onRename] turns the row itself into a field rather than opening a dialog,
/// which is the same thing the double-click does — the row owns that state, so
/// the menu asks it rather than reaching for it. Required, so a new kind of
/// row cannot quietly ship without it.
Future<void> showNodeMenu(BuildContext context, AppState app, TreeNode node,
    {required bool canIndent,
    required Offset position,
    required VoidCallback onRename}) async {
  final l = L.of(context);
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
      _nodeItem('rename', Icons.edit_outlined, l.navMenuRename),
      // Beside Rename rather than down with print and PDF: these two are the
      // things you do to the page ITSELF, and everything below is about where
      // it sits or what comes out of it. Pages only — duplicating a section
      // would mean copying every page in it, which is a different question.
      if (isPage)
        _nodeItem('duplicate', Icons.copy_all_outlined, l.navMenuDuplicate),
      const PopupMenuDivider(),
      _nodeItem('up', Icons.keyboard_arrow_up, l.navMenuMoveUp),
      _nodeItem('down', Icons.keyboard_arrow_down, l.navMenuMoveDown),
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
        _nodeItem('newpage', Icons.note_add_outlined, l.navMenuNewPage),
        _nodeItem('togroup', Icons.drive_file_move_outline, l.navMenuMoveToGroup),
        _nodeItem('sortaz', Icons.sort_by_alpha, l.navMenuSortAZ),
        _nodeItem('sortdate', Icons.schedule, l.navMenuSortEdited),
        // The navigator is where a student thinks in subjects rather than in
        // decks, so it is the more natural of the two places an exam date is
        // set. The label carries the current value: a menu that says only
        // "Exam date…" makes you open a dialog to find out whether there is
        // one.
        // The unit a student shares is "my notes for week 6", which is a
        // section far more often than a page — and for an imported deck it is
        // the whole deck. Vector export made the output worth sending.
        _nodeItem('sectionpdf', Icons.picture_as_pdf_outlined,
            l.navMenuExportSectionPdf),
        _nodeItem('printsection', Icons.print_outlined, l.navMenuPrintSection),
        if (app.study.examDate(node.id) case final exam?) ...[
          _nodeItem('exam', Icons.flag_outlined,
              _examMenuLabel(context, app, node.id, exam)),
          _nodeItem('examclear', Icons.event_busy_outlined, l.navMenuRemoveExam),
        ] else
          _nodeItem('exam', Icons.event_outlined, l.navMenuSetExam),
      ],
      // A page can always indent (make subpage) or outdent (promote) at some
      // level in 0..2, so the separator is shown whenever those items are.
      if (canIndent) const PopupMenuDivider(),
      if (canIndent && node.level < 2)
        _nodeItem('indent', Icons.subdirectory_arrow_right, l.navMenuMakeSubpage),
      if (canIndent && node.level > 0)
        _nodeItem('outdent', Icons.arrow_back, l.navMenuMoveBackOut),
      if (isPage) ...[
        const PopupMenuDivider(),
        _nodeItem(
            'favourite',
            app.isFavourite(node.id) ? Icons.star : Icons.star_border,
            app.isFavourite(node.id) ? l.navMenuRemoveFavourite : l.navMenuAddFavourite),
        _nodeItem('sharepdf', Icons.picture_as_pdf_outlined, l.navMenuSharePdf),
        _nodeItem('print', Icons.print_outlined, l.navMenuPrint),
        _nodeItem('copylink', Icons.link, l.navMenuCopyLink),
      ],
      const PopupMenuDivider(),
      // Available on every kind, because the ask was "a page ... a section, or
      // a section group" and protection is resolved by walking up from a page
      // to whichever of those carries it.
      if (app.protectionFor(node.id) != null)
        _nodeItem('unprotect', Icons.lock_open_outlined, l.navMenuRemovePasscode)
      else
        _nodeItem('protect', Icons.lock_outline, l.navMenuLock),
      const PopupMenuDivider(),
      _nodeItem('delete', Icons.delete_outline, l.navMenuDelete, danger: true),
    ],
  );
  if (!context.mounted) return;
  switch (action) {
    case 'duplicate':
      // No snackbar: the copy opens, with its title selected, which says
      // what happened better than a message about it would.
      await app.duplicatePage(node.id);
    case 'rename':
      onRename();
    case 'protect':
      final set = await askNewPasscode(context, node.title);
      if (set == null) return;
      app.protectNode(node.id, set.passcode, set.policy);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showToast(SnackBar(
            content: Text(L.of(context).navLockedNotEncrypted(node.title))));
      }
    case 'unprotect':
      final ok = await askToUnlock(
          context, node.title, (pw) => app.unprotectNode(node.id, pw));
      if (ok && context.mounted) {
        ScaffoldMessenger.of(context).showToast(
            SnackBar(content: Text(L.of(context).navPasscodeRemoved(node.title))));
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
    // **These five VISIT another page and come home.**
    //
    // Each of them needs the page open to work on it, and each used to leave
    // the student sitting on it afterwards — with the page they had been
    // writing on now behind them and its undo stack cleared, because
    // `selectPage` clears it. They asked to print a page, not to go there.
    case 'print':
      await _onPage(app, node.id, () => printCurrentPage(app));
    case 'printsection':
      await printSection(app, node.id);
    case 'sharepdf':
      if (app.pageId != node.id) await app.selectPage(node.id);
      if (!context.mounted) return;
      final cameFrom = app.pageId == node.id ? null : app.pageId;
      final saved = await exportPagePdfVector(app);
      if (cameFrom != null) await app.selectPage(cameFrom);
      if (saved != null && context.mounted) {
        ScaffoldMessenger.of(context)
            .showToast(SnackBar(content: Text(l.navSavedTo(saved))));
      }
    case 'sectionpdf':
      final messenger = ScaffoldMessenger.of(context);
      final saved = await exportSectionPdfVector(app, node.id);
      if (saved != null) {
        messenger.showToast(SnackBar(content: Text(l.navSavedTo(saved))));
      }
    case 'copylink':
      // The wiki-link form the editor already resolves. Copying it means
      // cross-referencing is paste, not retype-and-hope.
      await Clipboard.setData(
          ClipboardData(text: '[[${node.title}|${node.id}]]'));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showToast(SnackBar(
            content: Text(L.of(context).navLinkCopied)));
      }
    case 'togroup':
      final groups = app.nodes
          .where((n) => n.kind == NodeKind.sectionGroup)
          .toList();
      final choice = await showOnoteDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(L.of(ctx).navMoveSectionTo),
          children: [
            SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, ''),
                child: Text(L.of(ctx).navNoGroupTopLevel)),
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
    case 'delete':
      final messenger = ScaffoldMessenger.of(context);
      final l = L.of(context);
      await app.deleteNode(node.id);
      // The menu route said nothing at all before, so the ONE route with a
      // confirmation was the keyboard's. Same acknowledgement, same Undo.
      if (app.node(node.id) == null) {
        showDeletedSnackBar(messenger, l, app, node);
      }
  }
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
    final l = L.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final rawCurrent = widget.app.node(widget.section.id)?.color;
    final current = pickerTokenFor(rawCurrent);
    return Row(children: [
      Text(l.navColour,
          style: TextStyle(fontSize: 13, color: OnoteColors.graphite500)),
      const SizedBox(width: 10),
      // A colour from an earlier version isn't offered again, but a section
      // wearing one still shows it here, chosen, so nothing looks unset.
      if (isLegacySectionColor(rawCurrent))
        Padding(
          padding: const EdgeInsets.only(right: 3),
          child: Container(
            width: 17,
            height: 17,
            decoration: BoxDecoration(
              color: _sectionColor(rawCurrent, dark),
              shape: BoxShape.circle,
              border: Border.all(color: scheme.onSurface, width: 2),
            ),
          ),
        ),
      // Eight swatches (nine when a section carries an older colour) have to
      // fit the menu's 256 px beside the label, hence 17 px with 3 px between.
      for (final token in AppState.sectionColorTokens)
        Padding(
          padding: const EdgeInsets.only(right: 3),
          child: Tooltip(
            message: sectionPalette
                .firstWhere((h) => h.token == token,
                    orElse: () => sectionPalette.first)
                .name,
            child: InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                widget.app.setNodeColor(widget.section.id, token);
                Navigator.of(context).pop();
              },
              child: Container(
                width: 17,
                height: 17,
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

/// Do something that needs [pageId] open, then go back to where you were.
///
/// `selectPage` also clears the undo stack, so the cost of the detour is not
/// only the view: a student who printed a neighbouring page lost the ability
/// to undo on the one they were writing.
Future<void> _onPage(AppState app, String pageId, Future<void> Function() body)
    async {
  final cameFrom = app.pageId;
  if (cameFrom != pageId) await app.selectPage(pageId);
  try {
    await body();
  } finally {
    if (cameFrom != null && cameFrom != pageId && app.pageId == pageId) {
      await app.selectPage(cameFrom);
    }
  }
}

