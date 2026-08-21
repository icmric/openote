/// The **Maths** tab of the toolbar (plan: v0.18 §5.2, revised four times).
///
/// It appears only while an equation is being written and goes away the moment
/// you finish — a contextual tab, the way OneNote does it.
///
/// **Round one** put the palette inside the equation's own box. The owner:
/// *"this isnt great. I want them in the bar up the top like it is in
/// onenote."*
///
/// **Round two** put it in the toolbar and it was, in their word, chaotic —
/// and measurably so: **1725–2230 px** against an app whose default window is
/// **1280**, with no scrollbar and a mouse wheel that did nothing, so the
/// search box and the LaTeX escape hatch sat off the right-hand edge.
/// Twenty-seven controls, eighteen ragged-width chips in a flat run, then
/// eight word-labelled drop-downs — each of which opened a gallery **one
/// symbol per row** (Greek was a 1119 px column), because a `Container` with
/// an `alignment` expands to its loose constraints.
///
/// **Round three** collapsed all of that to twelve controls behind one
/// Symbols door, which fitted — and then had room to spare. The owner: *"We
/// have more space to play with in that bar than your using, so we can break
/// symbols, opperators, large opperators, functions, etc out into their own
/// things."*
///
/// **Round four — this one.** A door per KIND of thing, because one marked
/// "Symbols" is a filing cabinet: a student after a summation still has to
/// know it is filed under symbols rather than under shapes.
///
/// ```
///  1/2  x^2  root  (box)  words  |  Shapes Big Operators Compare Greek
///                                   Sets Functions More  |  find  = 0.5  ...
/// ```
///
/// Every door carries its arrow again (cut in round three for width, asked
/// for back), the panels are owned by the BAR rather than by each button so a
/// second door opens on the FIRST click, and the entrance is 90 ms rather than
/// Material's ~300.
///
/// The rules kept throughout: the shapes never move (their positions ARE the
/// muscle memory), every tooltip teaches the keyboard route, the search speaks
/// plain student, and the LaTeX view is one item behind the ellipsis.
library;

import 'package:flutter/material.dart';

import '../math/evaluate.dart';
import '../math/math_inventory.dart';
import '../math/math_view.dart';
import '../theme/tokens.dart';
import 'shortcut_overlay.dart';

/// The eight shapes that stay on the bar, in this order, forever.
///
/// Chosen by what a year-10 to first-year student reaches for in an afternoon,
/// not by what is interesting. Everything else is one click further away.
/// FIVE, not eight. Once every kind of thing has its own named door the row
/// is 1385 px measured, which is wider than the 1280 px window the app opens
/// at — so the chips pay for the doors, and these are the five that survive a
/// "would a student reach for this today" test.
const List<String> kMathQuickShapes = [
  'frac', 'power', 'sqrt', 'paren',
];

/// One door per KIND of thing, with the room the row actually has.
///
/// Round three collapsed eight category drop-downs into a single Symbols
/// panel, which fitted — and then had room to spare. The owner: *"We have more
/// space to play with in that bar than your using, so we can break symbols,
/// opperators, large opperators, functions, etc out into their own things."*
///
/// Right: one door marked "Symbols" is a filing cabinet, and a student looking
/// for ∑ has to know it is filed under symbols rather than under shapes. Doors
/// named after what is behind them are a shorter path than a search box for
/// anyone who can see the door. The search is still there for the rest.
///
/// Listed by ID rather than by category so a door can draw from several — the
/// large operators are STRUCTURES (they carry limit slots), and ≤ lives with
/// the other comparisons rather than with the arithmetic it is filed under.
typedef MathDoor = ({String label, String tip, List<String> ids});

/// The categories a door SWEEPS UP after its explicit list.
///
/// Without this, adding a symbol to the inventory put it behind no door at all
/// — reachable only by knowing to search for it. Measured after one batch of
/// additions: 44 of 230 items were unreachable by browsing. The explicit list
/// stays, because order is a judgement no rule can make; anything not named
/// there is appended, so a new symbol is browsable the moment it exists.
const Map<String, List<MathCat>> kMathDoorSweeps = {
  'Shapes': [MathCat.structure],
  'Operators': [MathCat.common],
  'Compare': [MathCat.compare],
  'Sets': [MathCat.sets],
};

/// Ordered so a student reading left to right meets things in the order they
/// meet them at school, and so the pairs that belong together sit together.
///
/// The audit found the first cut was ordered by how the inventory happened to
/// be typed: `determinant` with no `matrix` anywhere, `prime` three chips from
/// the derivative it belongs beside, `sin` eighteen chips from `sin⁻¹`, and
/// absolute value, piecewise and matrix in **no door at all** — reachable only
/// by searching for them.
const List<MathDoor> kMathDoors = [
  (
    label: 'Shapes',
    tip: 'Indices, roots, brackets, grids, accents',
    ids: [
      // Scripts, together.
      'subscript', 'subsup',
      // Roots.
      'nthroot',
      // Calculus, and the prime that belongs with it.
      'ddx', 'partial', 'prime',
      // Brackets that grow — abs, floor and ceil are the same idea.
      'abs', 'floor', 'ceil',
      // Grids: the determinant now has its matrix beside it.
      'matrix', 'determinant', 'cases',
      // Counting.
      'binom',
      // Accents last: a decoration on something already written.
      'bar', 'hat', 'vec', 'dot', 'tilde',
      // Words inside maths — "if", "where" — belong with the other things you
      // put INTO an equation rather than on the row itself.
      'words',
    ],
  ),
  (
    // Not "Big": a door named after a size tells a student nothing. These are
    // the operators that carry their limits, and the symbols say so faster
    // than any word available at this width.
    label: '∑ ∫',
    tip: 'Sums, integrals, products and limits',
    ids: ['sum', 'prod', 'int', 'iint', 'oint', 'lim'],
  ),
  (
    label: 'Operators',
    tip: 'Plus or minus, times, divide, and the rest',
    ids: [
      // Arithmetic first — this is what the door is for.
      'pm', 'times', 'div', 'cdot',
      // Then the ones that hang off a number.
      'percent', 'degree', 'factorial',
      // Then the odds and ends.
      'infty', 'ldots', 'propto', 'nabla',
    ],
  ),
  (
    label: 'Compare',
    tip: 'Equals, inequalities, arrows',
    ids: [
      // Equality, then inequality in the order a textbook introduces it:
      // strict before "or equal", and never split across a row break.
      'eq', 'neq', 'approx', 'equiv', 'cong',
      'lt', 'gt', 'leq', 'geq', 'll', 'gg', 'sim',
      // Arrows, then the two that read as words.
      'to', 'gets', 'leftrightarrow', 'mapsto',
      'implies', 'impliedby', 'iff',
      'therefore', 'because',
    ],
  ),
  (
    label: 'Greek',
    tip: 'The whole alphabet, by name',
    ids: [],
  ),
  (
    // Set WORK, not set membership: the operators that combine sets used to
    // live under Operators, so doing any of it meant two doors.
    label: 'Sets',
    tip: 'Membership, subsets, number systems, and logic',
    ids: [
      'in', 'notin', 'subset', 'subseteq', 'notsubset',
      'cup', 'cap', 'setminus', 'emptyset',
      'naturals', 'integers', 'rationals', 'reals', 'complex',
      'forall', 'exists', 'lnot', 'land', 'lor', 'oplus',
      'mid', 'nmid',
    ],
  ),
  (
    label: 'Functions',
    tip: 'sin, cos, log, and friends',
    ids: [],
  ),
  (
    // Renamed from "More", which shared its name with the row's own ellipsis
    // menu and said nothing about what was behind it.
    label: 'Subjects',
    tip: 'Geometry, statistics and science',
    ids: [],
  ),
];

/// Doors whose contents come from a whole category rather than a list.
const Map<String, List<MathCat>> kMathDoorCats = {
  'Greek': [MathCat.greek],
  'Functions': [MathCat.functions],
  'Subjects': [MathCat.geometry, MathCat.stats, MathCat.science],
};

/// Every id named explicitly by SOME door, so a sweep can skip them.
final Set<String> _explicitlyPlaced = {
  for (final d in kMathDoors) ...d.ids,
  ...kMathQuickShapes,
};

/// What a door shows: its curated list first, then anything of its categories
/// that nobody placed by hand.
List<MathItem> mathDoorItems(MathDoor door) {
  final cats = kMathDoorCats[door.label];
  if (cats != null) {
    return [for (final c in cats) ...mathItemsIn(c)];
  }
  final out = <MathItem>[
    for (final id in door.ids)
      if (mathItemsById[id] case final i?) i
  ];
  for (final c in kMathDoorSweeps[door.label] ?? const <MathCat>[]) {
    for (final i in mathItemsIn(c)) {
      if (!_explicitlyPlaced.contains(i.id)) out.add(i);
    }
  }
  return out;
}


/// A door's contents, in the sections they should be read in.
///
/// Most doors are one list and get no heading — the owner's own judgement,
/// and it holds: a heading over the only group on screen is a label for
/// nothing. `More` is the exception, because it is three unrelated subjects
/// sharing a door, and a student looking for an angle should not have to scan
/// past the statistics to find it.
typedef MathGroup = ({String title, List<MathItem> items});

List<MathGroup> mathDoorGroups(MathDoor door) {
  final cats = kMathDoorCats[door.label];
  if (cats != null) {
    return [
      for (final c in cats)
        if (mathItemsIn(c).isNotEmpty)
          (title: c.title, items: mathItemsIn(c))
    ];
  }
  return [(title: door.label, items: mathDoorItems(door))];
}

/// One panel at a time, owned by the BAR rather than by each button.
///
/// Three things the owner asked for fall out of that ownership, and none of
/// them is reachable while every door runs its own `showMenu`:
///
///  * **Clicking a second door while one is open opens it straight away.**
///    A modal route's barrier swallows that first click, so it used to take
///    two — close, then open. The barrier here reports where it was pressed,
///    and if that was over another door, the bar opens it in the same gesture.
///  * **The animation is quick.** `showMenu` runs Material's ~300 ms route
///    transition; this is a 90 ms fade and a slight rise, which is the same
///    register as the toolbar's own tab switch.
///  * **The arrow is back.** It was cut for row width; see [_DoorButton].
class MathBar extends StatefulWidget {
  const MathBar({
    super.key,
    required this.onInsert,
    required this.latexMode,
    required this.onToggleLatex,
    this.latexAvailable = true,
    this.angleMode = AngleMode.degrees,
    this.onDrawGraph,
    this.onToggleAngleMode,
    this.recentIds = const [],
  });

  final ValueChanged<MathItem> onInsert;
  final bool latexMode;
  final VoidCallback onToggleLatex;
  final bool latexAvailable;

  /// Degrees or radians, and the way to change it.
  final AngleMode angleMode;

  /// Draw this equation as a graph, or null when it cannot be.
  final VoidCallback? onDrawGraph;
  final VoidCallback? onToggleAngleMode;

  // The bar used to carry a live `= 42` readout with a button to put the
  // answer in. The owner: *"rather than having it appear up the top though
  // since that isnt intuitive, maybe we make it so that … when the person
  // puts an = sign and presses space afterwards it inserts the solution?"*
  // The answer now lands where the caret already is — see
  // `MathEditor.answerAfterEquals` — and this row says nothing about it.

  /// Symbols used lately, newest first. Shown at the top of the search panel,
  /// never inline on the row: a chip that changes identity under the pointer
  /// is worse than no shortcut at all.
  final List<String> recentIds;

  @override
  State<MathBar> createState() => _MathBarState();
}

/// How long a panel takes to appear. Short on purpose — a menu you are about
/// to read should not be animating while you read it.
const Duration kMathMenuFade = Duration(milliseconds: 90);

class _MathBarState extends State<MathBar> {
  /// One key per door, so the barrier can work out which door a click landed
  /// on without any of them knowing about each other.
  final Map<String, GlobalKey> _doorKeys = {};
  final _searchKey = GlobalKey();
  final _search = TextEditingController();

  OverlayEntry? _entry;
  String? _open;

  GlobalKey _keyFor(String label) =>
      _doorKeys.putIfAbsent(label, () => GlobalKey());

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    _search.dispose();
    super.dispose();
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() => _open = null);
    _open = null;
  }

  /// A press that landed outside the panel. Close — and if it landed on
  /// another door, open that one now rather than making the student click a
  /// second time.
  void _barrierPressed(Offset global) {
    // Which door was open BEFORE the close, so pressing that same door reads
    // as "shut it" rather than closing and immediately reopening it.
    final was = _open;
    _close();
    Rect? rectOf(GlobalKey k) {
      final box = k.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return null;
      return box.localToGlobal(Offset.zero) & box.size;
    }

    for (final door in kMathDoors) {
      final r = rectOf(_keyFor(door.label));
      if (r != null && r.contains(global)) {
        if (was != door.label) _toggle(door.label);
        return;
      }
    }
    final s = rectOf(_searchKey);
    if (s != null && s.contains(global) && was != '__search') {
      _toggle('__search');
    }
  }

  void _toggle(String label) {
    if (_open == label) {
      _close();
      return;
    }
    _close();
    final key = label == '__search' ? _searchKey : _keyFor(label);
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final panelWidth = label == '__search' ? 336.0 : 320.0;
    // Never off the right-hand edge, and never behind the left one.
    final maxLeft = overlay.size.width - panelWidth - 8;
    final left = maxLeft <= 8 ? 8.0 : origin.dx.clamp(8.0, maxLeft);

    _entry = OverlayEntry(
      builder: (ctx) => Stack(children: [
        // Opaque, so a click on the page does not also act on the page — but
        // it reports where it landed, which is what makes door-to-door work.
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) => _barrierPressed(e.position),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: left.toDouble(),
          top: origin.dy + box.size.height + 2,
          width: panelWidth,
          child: _Fade(
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: label == '__search'
                    ? _searchPanel()
                    : _doorPanel(
                        kMathDoors.firstWhere((d) => d.label == label)),
              ),
            ),
          ),
        ),
      ]),
    );
    Overlay.of(context).insert(_entry!);
    setState(() => _open = label);
  }

  void _pick(MathItem item) {
    _close();
    widget.onInsert(item);
  }

  Widget _doorPanel(MathDoor door) {
    final s = context.surfaces;
    final groups = mathDoorGroups(door);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 340),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final g in groups) ...[
              // A heading only where a door holds more than one KIND of thing.
              // The owner doubted headings were needed and was mostly right —
              // most doors are one list and get none.
              if (groups.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 4, 2, 4),
                  child: Text(g.title,
                      style: OnoteType.small.copyWith(
                          color: s.textSecondary,
                          fontWeight: FontWeight.w600)),
                ),
              Wrap(
                spacing: 3,
                runSpacing: 3,
                children: [
                  for (final i in g.items)
                    MathChip(item: i, surfaces: s, onTap: _pick)
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _searchPanel() {
    final s = context.surfaces;
    return StatefulBuilder(builder: (ctx, setLocal) {
      final q = _search.text.trim();
      final hits = q.isEmpty ? const <MathItem>[] : searchMathItems(q);
      return SizedBox(
        height: 300,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 32,
              child: TextField(
                controller: _search,
                autofocus: true,
                style: OnoteType.small,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon:
                      Icon(Icons.search, size: 15, color: s.textSecondary),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 26, minHeight: 20),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  border: const OutlineInputBorder(),
                  hintText: 'What are you after? "not equal", "theta"',
                  hintStyle: OnoteType.small.copyWith(color: s.textSecondary),
                ),
                onChanged: (_) => setLocal(() {}),
                onSubmitted: (_) {
                  if (hits.isNotEmpty) _pick(hits.first);
                },
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: SingleChildScrollView(
                child: q.isEmpty
                    ? _panelSection(
                        'Recent',
                        [
                          for (final id in widget.recentIds)
                            if (mathItemsById[id] case final i?) i
                        ],
                        s)
                    : hits.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              "Openote doesn't have that as a button yet. "
                              'Anything at all can be written by hand from '
                              '⋯ ▸ Write the LaTeX by hand.',
                              style: OnoteType.small
                                  .copyWith(color: s.textSecondary),
                            ),
                          )
                        : _panelSection(
                            'Matches — Enter takes the first', hits, s),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _panelSection(String title, List<MathItem> items, OnoteSurfaces s) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 4, 2, 4),
            child: Text(title,
                style: OnoteType.small.copyWith(
                    color: s.textSecondary, fontWeight: FontWeight.w600)),
          ),
          Wrap(
            spacing: 3,
            runSpacing: 3,
            children: [
              for (final i in items) MathChip(item: i, surfaces: s, onTap: _pick)
            ],
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;

    if (widget.latexMode) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 10),
          child: Text(
            "Writing the LaTeX by hand — anything the buttons can't do goes "
            'here.',
            style: OnoteType.small.copyWith(color: s.textSecondary),
          ),
        ),
        _GraphButton(onDrawGraph: widget.onDrawGraph, surfaces: s),
        _AngleSwitch(
          mode: widget.angleMode,
          onToggle: widget.onToggleAngleMode,
          surfaces: s,
        ),
        _MoreMenu(
          latexMode: widget.latexMode,
          latexAvailable: widget.latexAvailable,
          onToggleLatex: widget.onToggleLatex,
          surfaces: s,
        ),
      ]);
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (final id in kMathQuickShapes)
        if (mathItemsById[id] case final item?)
          MathChip(item: item, onTap: widget.onInsert, surfaces: s),
      _Sep(surfaces: s),
      for (final door in kMathDoors)
        _DoorButton(
          key: _keyFor(door.label),
          label: door.label,
          tooltip: door.tip,
          open: _open == door.label,
          surfaces: s,
          onTap: () => _toggle(door.label),
        ),
      _Sep(surfaces: s),
      _DoorButton(
        key: _searchKey,
        icon: Icons.search,
        tooltip: 'Find a symbol by name',
        open: _open == '__search',
        surfaces: s,
        onTap: () => _toggle('__search'),
      ),
      _GraphButton(onDrawGraph: widget.onDrawGraph, surfaces: s),
      _AngleSwitch(
        mode: widget.angleMode,
        onToggle: widget.onToggleAngleMode,
        surfaces: s,
      ),
      _MoreMenu(
        latexMode: widget.latexMode,
        latexAvailable: widget.latexAvailable,
        onToggleLatex: widget.onToggleLatex,
        surfaces: s,
      ),
    ]);
  }
}

/// The panel's entrance: a quick fade and a 4 px rise, matching the register
/// the toolbar already uses for a tab switch.
class _Fade extends StatefulWidget {
  const _Fade({required this.child});
  final Widget child;

  @override
  State<_Fade> createState() => _FadeState();
}

class _FadeState extends State<_Fade> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: kMathMenuFade)
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curve,
      child: AnimatedBuilder(
        animation: curve,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, 4 * (1 - curve.value)),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

/// A door on the row.
///
/// **The arrow is back.** It was cut last round to save 120 px of row width,
/// and the owner asked for it: *"id like a little arrow on the menu buttons up
/// top when there is a drop down to make it clear they are a menu."* Right —
/// without it a door is indistinguishable from a button that inserts
/// something, which is what every chip beside it does. It is a 12 px caret
/// rather than the 15 px default, and the row was re-measured with it.
///
/// The button also shows when its own panel is open, so the row says where you
/// are rather than leaving the panel to float unattached.
class _DoorButton extends StatelessWidget {
  const _DoorButton({
    super.key,
    this.label,
    this.icon,
    required this.tooltip,
    required this.open,
    required this.surfaces,
    required this.onTap,
  });

  final String? label;
  final IconData? icon;
  final String tooltip;
  final bool open;
  final OnoteSurfaces surfaces;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final ink = open ? accent : surfaces.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(right: 3),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: onTap,
          child: Container(
            height: OnoteSize.button,
            padding: EdgeInsets.only(left: label == null ? 5 : 6, right: 1),
            decoration: BoxDecoration(
              color: open ? accent.withValues(alpha: 0.10) : null,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: open ? accent : surfaces.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) Icon(icon, size: OnoteIcon.sm, color: ink),
              if (label != null)
                Text(label!, style: OnoteType.small.copyWith(color: ink)),
              Icon(Icons.arrow_drop_down, size: 11, color: ink),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Sep extends StatelessWidget {
  const _Sep({required this.surfaces});
  final OnoteSurfaces surfaces;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: SizedBox(
          height: 20,
          child: VerticalDivider(width: 1, color: surfaces.border),
        ),
      );
}

/// Degrees or radians, in one click.
///
/// The owner: *"Please also add a way to easily switch between degrees and
/// radians."* It sits where the answer readout used to, which is the only
/// spare width on a row measured at 1144.75 px against a 1150 px guard — and
/// it is a better tenant, because it is a SETTING (rare, deliberate) rather
/// than a readout (constant, and better placed at the caret).
///
/// The label says the mode you are IN, not the one you would switch to. A
/// button labelled with its own opposite is a coin-flip every time.
/// **Draw this equation as a graph, beside it.**
///
/// On the row rather than behind the `...` fold. It was in the fold because
/// it cost the row no width there, and the owner, on using it: *"i dont love
/// the location of the 'graph this' button, isnt super intuitive. Could we
/// maybe break this out into its own button?"* A command that MAKES something
/// is not an advanced setting, and nobody opens a fold to find out what is in
/// it.
///
/// Always enabled. `drawGraph` is a closure rather than a flag precisely
/// because `setActiveMath` is called from the editor's own build and does not
/// notify — any emptiness captured here would be one keystroke stale — so the
/// question "is there anything to graph" is asked when the button is pressed,
/// and answered there.
class _GraphButton extends StatelessWidget {
  const _GraphButton({required this.onDrawGraph, required this.surfaces});

  final VoidCallback? onDrawGraph;
  final OnoteSurfaces surfaces;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 3),
        child: Tooltip(
          message: 'Draw this equation as a graph beside it',
          child: SizedBox(
            height: OnoteSize.button,
            child: InkWell(
              borderRadius: BorderRadius.circular(5),
              onTap: onDrawGraph,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: surfaces.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.show_chart,
                          size: OnoteIcon.sm, color: surfaces.textPrimary),
                      const SizedBox(width: 4),
                      Text('Graph',
                          style: OnoteType.small.copyWith(
                            fontWeight: FontWeight.w600,
                            color: surfaces.textPrimary,
                          )),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _AngleSwitch extends StatelessWidget {
  const _AngleSwitch({
    required this.mode,
    required this.onToggle,
    required this.surfaces,
  });

  final AngleMode mode;
  final VoidCallback? onToggle;
  final OnoteSurfaces surfaces;

  @override
  Widget build(BuildContext context) {
    final deg = mode == AngleMode.degrees;
    return Padding(
      padding: const EdgeInsets.only(right: 3),
      child: Tooltip(
        message: deg
            ? 'Angles are in degrees — click for radians'
            : 'Angles are in radians — click for degrees',
        child: SizedBox(
          height: OnoteSize.button,
          child: InkWell(
            borderRadius: BorderRadius.circular(5),
            onTap: onToggle,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: surfaces.border),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Center(
                  child: Text(
                    deg ? 'DEG' : 'RAD',
                    style: OnoteType.small.copyWith(
                      fontWeight: FontWeight.w600,
                      color: surfaces.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Advanced fold, and the things that belong beside it. One `⋯`, so the
/// row is not carrying a word-labelled button a student will never press.
class _MoreMenu extends StatelessWidget {
  const _MoreMenu({
    required this.latexMode,
    required this.latexAvailable,
    required this.onToggleLatex,
    required this.surfaces,
  });

  final bool latexMode;
  final bool latexAvailable;
  final VoidCallback onToggleLatex;
  final OnoteSurfaces surfaces;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'More',
        position: PopupMenuPosition.under,
        icon: Icon(Icons.more_horiz, size: OnoteIcon.sm, color: surfaces.textPrimary),
        onSelected: (v) {
          if (v == 'latex') onToggleLatex();
          if (v == 'help') showShortcutOverlay(context);
        },
        itemBuilder: (_) => [
          PopupMenuItem<String>(
            value: 'latex',
            enabled: latexAvailable,
            child: Text(latexMode
                ? 'Back to the buttons'
                : 'Write the LaTeX by hand'),
          ),
          // **With the backslashes.** This line used to read "type sqrt, sum,
          // theta", and typing `sqrt` and a space gives you the four letters:
          // the build-up requires the leading `\`, deliberately, so that
          // `alpha`, `in`, `div` and `deg` stay the ordinary words they are.
          // The one place in the app that taught its own signature feature
          // taught it wrong, greyed out, which reads as "this is broken".
          const PopupMenuItem<String>(
            value: 'help',
            child: Text(r'Tips: 1/2 is a fraction · \sqrt \sum \theta · '
                '= then space works it out · Tab fills the next box'),
          ),
        ],
      );
}


class MathChip extends StatelessWidget {
  const MathChip({
    super.key,
    required this.item,
    required this.onTap,
    required this.surfaces,
  });

  static const double size = 34;

  final MathItem item;
  final ValueChanged<MathItem> onTap;
  final OnoteSurfaces surfaces;

  @override
  Widget build(BuildContext context) {
    final preview = item.preview;
    // The tooltip is a teaching surface: what a student would call it, then
    // the keyboard route. Every press is a chance to make the next one
    // unnecessary.
    // `name (REPLACE_BX)`, not `name — type REPLACE_BX`: the owner's call, and the
    // shorter form reads as one label instead of a sentence with an
    // instruction buried in it.
    final tip = item.typeIt == null
        ? item.name
        : '${item.name} (${item.typeIt})';

    return Padding(
      padding: const EdgeInsets.only(right: 3),
      child: Tooltip(
        message: tip,
        waitDuration: const Duration(milliseconds: 350),
        child: SizedBox(
          width: size,
          height: OnoteSize.button,
          child: InkWell(
            borderRadius: BorderRadius.circular(5),
            onTap: () => onTap(item),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: surfaces.border),
              ),
              child: Center(
                child: preview != null
                    ? IgnorePointer(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: OnoteMath(
                            preview,
                            compact: true,
                            textStyle: TextStyle(
                                fontSize: 12, color: surfaces.textPrimary),
                          ),
                        ),
                      )
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          item.label ?? item.name,
                          maxLines: 1,
                          style: TextStyle(
                              fontSize: 14, color: surfaces.textPrimary),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
