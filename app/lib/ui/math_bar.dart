/// The **Maths** tab of the toolbar (plan: v0.18 §5.2, revised twice).
///
/// It appears only while an equation is being written and goes away the moment
/// you finish — a contextual tab, the way OneNote does it.
///
/// **Round one** put the palette inside the equation's own box. The owner:
/// *"this isnt great. I want them in the bar up the top like it is in
/// onenote."*
///
/// **Round two** put it in the toolbar and it was, in their word, chaotic —
/// and measurably so. The row came to **1725–2230 px** against an app whose
/// default window is **1280**, so the search box, the answer and the LaTeX
/// escape hatch were simply off the right-hand edge, with no scrollbar and a
/// mouse wheel that did nothing. Twenty-seven controls, eighteen of them
/// ragged-width shape chips in a flat undifferentiated run, then eight
/// word-labelled drop-downs. Every symbol gallery it opened was **one symbol
/// per row** — Greek was a 1119 px column — because a `Container` with an
/// `alignment` expands to its loose constraints, so every chip was full width.
///
/// **This round: twelve controls, grouped.** Eight shapes a student reaches
/// for daily, then one door per kind of thing:
///
/// ```
///  ½  x²  √  Σ  ∫  (□)  {cases  [matrix]  │  ⊞ More shapes ▾  Ω Symbols ▾  │  = 0.5   ⋯
/// ```
///
/// The rules kept from round two: the shapes never move (their positions ARE
/// the muscle memory), every tooltip teaches the keyboard route, the search
/// speaks plain student, and the LaTeX view is one item behind `⋯`.
library;

import 'package:flutter/material.dart';

import '../math/math_inventory.dart';
import '../math/math_view.dart';
import '../theme/tokens.dart';

/// The eight shapes that stay on the bar, in this order, forever.
///
/// Chosen by what a year-10 to first-year student reaches for in an afternoon,
/// not by what is interesting. Everything else is one click further away.
/// FIVE, not eight. Once every kind of thing has its own named door the row
/// is 1385 px measured, which is wider than the 1280 px window the app opens
/// at — so the chips pay for the doors, and these are the five that survive a
/// "would a student reach for this today" test.
const List<String> kMathQuickShapes = [
  'frac', 'power', 'sqrt', 'paren', 'words',
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

const List<MathDoor> kMathDoors = [
  (
    label: 'Shapes',
    tip: 'Roots, derivatives, brackets, accents',
    ids: [
      'subscript', 'subsup', 'nthroot', 'ddx', 'partial', 'binom',
      'floor', 'ceil', 'determinant', 'prime',
      'bar', 'hat', 'vec', 'dot', 'tilde',
    ],
  ),
  (
    label: 'Big',
    tip: 'Sums, integrals, products, limits',
    ids: ['sum', 'int', 'iint', 'oint', 'prod', 'lim'],
  ),
  (
    label: 'Operators',
    tip: 'Plus or minus, times, divide, and the rest',
    ids: [
      'pm', 'times', 'div', 'cdot', 'percent', 'factorial', 'degree',
      'cup', 'cap', 'setminus', 'oplus', 'land', 'lor', 'lnot',
      'infty', 'ldots', 'propto', 'nabla',
    ],
  ),
  (
    label: 'Compare',
    tip: 'Equals, inequalities, arrows',
    ids: [
      'eq', 'neq', 'approx', 'leq', 'geq', 'lt', 'gt', 'll', 'gg',
      'equiv', 'cong', 'sim', 'to', 'gets', 'leftrightarrow',
      'implies', 'impliedby', 'iff', 'mapsto', 'therefore', 'because',
    ],
  ),
  (
    label: 'Greek',
    tip: 'The whole alphabet, by name',
    ids: [],
  ),
  (
    label: 'Sets',
    tip: 'Membership, subsets, number systems, logic',
    ids: [
      'in', 'notin', 'subset', 'subseteq', 'notsubset', 'emptyset',
      'naturals', 'integers', 'rationals', 'reals', 'complex',
      'forall', 'exists', 'mid', 'nmid',
    ],
  ),
  (
    label: 'Functions',
    tip: 'sin, cos, log, and friends',
    ids: [],
  ),
  (
    label: 'More',
    tip: 'Geometry, statistics, science',
    ids: [],
  ),
];

/// Doors whose contents come from a whole category rather than a list.
const Map<String, List<MathCat>> kMathDoorCats = {
  'Greek': [MathCat.greek],
  'Functions': [MathCat.functions],
  'More': [MathCat.geometry, MathCat.stats, MathCat.science],
};

/// What a door shows, resolved from either source.
List<MathItem> mathDoorItems(MathDoor door) {
  final cats = kMathDoorCats[door.label];
  if (cats != null) {
    return [for (final c in cats) ...mathItemsIn(c)];
  }
  return [
    for (final id in door.ids)
      if (mathItemsById[id] case final i?) i
  ];
}

class MathBar extends StatelessWidget {
  const MathBar({
    super.key,
    required this.onInsert,
    required this.latexMode,
    required this.onToggleLatex,
    this.latexAvailable = true,
    this.result,
    this.onUseResult,
    this.recentIds = const [],
  });

  final ValueChanged<MathItem> onInsert;
  final bool latexMode;
  final VoidCallback onToggleLatex;
  final bool latexAvailable;

  /// The live arithmetic answer, when the equation reduces to one.
  final String? result;

  /// Put the answer into the equation — `= 0.5` appended at the caret.
  final VoidCallback? onUseResult;

  /// Symbols used lately, newest first. Shown at the top of the symbol panel,
  /// never inline on the row: a chip that changes identity under the pointer
  /// is worse than no shortcut at all.
  final List<String> recentIds;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;

    if (latexMode) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 10),
          child: Text(
            'Writing the LaTeX by hand — anything the buttons can\'t do goes '
            'here.',
            style: OnoteType.small.copyWith(color: s.textSecondary),
          ),
        ),
        _AnswerSlot(result: result, onUse: onUseResult, surfaces: s),
        _MoreMenu(
          latexMode: latexMode,
          latexAvailable: latexAvailable,
          onToggleLatex: onToggleLatex,
          surfaces: s,
        ),
      ]);
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (final id in kMathQuickShapes)
        if (mathItemsById[id] case final item?)
          MathChip(item: item, onTap: onInsert, surfaces: s),
      _Sep(surfaces: s),
      for (final door in kMathDoors)
        _DoorButton(door: door, onInsert: onInsert, surfaces: s),
      _Sep(surfaces: s),
      _SearchButton(onInsert: onInsert, surfaces: s, recentIds: recentIds),
      _AnswerSlot(result: result, onUse: onUseResult, surfaces: s),
      _MoreMenu(
        latexMode: latexMode,
        latexAvailable: latexAvailable,
        onToggleLatex: onToggleLatex,
        surfaces: s,
      ),
    ]);
  }
}

class _Sep extends StatelessWidget {
  const _Sep({required this.surfaces});
  final OnoteSurfaces surfaces;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: SizedBox(
          height: 20,
          child: VerticalDivider(width: 1, color: surfaces.border),
        ),
      );
}

/// The answer, in a slot of FIXED width.
///
/// It used to be built only when there was one, so the row jumped 30–177 px
/// sideways as the student typed and, on a long decimal, pushed the LaTeX
/// button off the edge. A slot that is always there cannot do that. Clicking
/// it writes the answer into the equation — a calculator OneNote charges for.
class _AnswerSlot extends StatelessWidget {
  const _AnswerSlot({
    required this.result,
    required this.onUse,
    required this.surfaces,
  });

  final String? result;
  final VoidCallback? onUse;
  final OnoteSurfaces surfaces;

  @override
  Widget build(BuildContext context) {
    final r = result;
    return SizedBox(
      width: 104,
      height: OnoteSize.button,
      child: r == null
          ? const SizedBox.shrink()
          : Tooltip(
              message: 'What this works out to — click to put it in',
              child: InkWell(
                borderRadius: BorderRadius.circular(5),
                onTap: onUse,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '= $r',
                      overflow: TextOverflow.ellipsis,
                      style: OnoteType.small.copyWith(
                        fontWeight: FontWeight.w600,
                        color: surfaces.textPrimary,
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
        },
        itemBuilder: (_) => [
          PopupMenuItem<String>(
            value: 'latex',
            enabled: latexAvailable,
            child: Text(latexMode
                ? 'Back to the buttons'
                : 'Write the LaTeX by hand'),
          ),
          const PopupMenuItem<String>(
            value: 'help',
            enabled: false,
            child: Text('Tips: 1/2 makes a fraction · type sqrt, sum, theta · '
                'Tab moves to the next box'),
          ),
        ],
      );
}

class _Gallery extends StatelessWidget {
  const _Gallery({required this.width, required this.children});
  final double width;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Wrap(spacing: 3, runSpacing: 3, children: children),
      );
}

/// A gallery, laid out as a GRID.
///
/// Width and height are fixed here and every chip inside is explicitly sized,
/// because a `Container` with an `alignment` expands to its loose constraints
/// — which is why every gallery used to come out one symbol per row.
/// One door on the row, named for what is behind it.
class _DoorButton extends StatelessWidget {
  const _DoorButton({
    required this.door,
    required this.onInsert,
    required this.surfaces,
  });

  final MathDoor door;
  final ValueChanged<MathItem> onInsert;
  final OnoteSurfaces surfaces;

  @override
  Widget build(BuildContext context) {
    final items = mathDoorItems(door);
    return _MenuButton(
      label: door.label,
      tooltip: door.tip,
      surfaces: surfaces,
      builder: (close) => ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: SingleChildScrollView(
          child: _Gallery(
            width: 320,
            children: [
              for (final i in items)
                MathChip(
                  item: i,
                  surfaces: surfaces,
                  onTap: (x) {
                    close();
                    onInsert(x);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The search, on its own small button.
///
/// It is the answer to "I don't know what this is called or which door it is
/// behind" — which is a different question from any of the doors, so it gets
/// its own control rather than living inside one of them.
class _SearchButton extends StatefulWidget {
  const _SearchButton({
    required this.onInsert,
    required this.surfaces,
    required this.recentIds,
  });

  final ValueChanged<MathItem> onInsert;
  final OnoteSurfaces surfaces;
  final List<String> recentIds;

  @override
  State<_SearchButton> createState() => _SearchButtonState();
}

class _SearchButtonState extends State<_SearchButton> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.surfaces;
    return _MenuButton(
      icon: Icons.search,
      tooltip: 'Find a symbol by name',
      surfaces: s,
      onClosed: _search.clear,
      builder: (close) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final q = _search.text.trim();
          final hits = q.isEmpty ? const <MathItem>[] : searchMathItems(q);
          void pick(MathItem i) {
            close();
            widget.onInsert(i);
          }

          return SizedBox(
            width: 336,
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
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 6, horizontal: 4),
                      border: const OutlineInputBorder(),
                      hintText: 'What are you after? "not equal", "theta"',
                      hintStyle:
                          OnoteType.small.copyWith(color: s.textSecondary),
                    ),
                    onChanged: (_) => setLocal(() {}),
                    onSubmitted: (_) {
                      if (hits.isNotEmpty) pick(hits.first);
                    },
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: SingleChildScrollView(
                    child: q.isEmpty
                        ? _section(
                            'Recent',
                            [
                              for (final id in widget.recentIds)
                                if (mathItemsById[id] case final i?) i
                            ],
                            pick,
                            s,
                          )
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
                            : _section('Matches — Enter takes the first', hits,
                                pick, s),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _section(String title, List<MathItem> items,
          ValueChanged<MathItem> pick, OnoteSurfaces s) =>
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
              for (final i in items)
                MathChip(item: i, surfaces: s, onTap: pick),
            ],
          ),
        ],
      );
}

/// A labelled door on the row, opening a panel underneath it.
class _MenuButton extends StatefulWidget {
  const _MenuButton({
    this.icon,
    this.label,
    required this.tooltip,
    required this.surfaces,
    required this.builder,
    this.onClosed,
  });

  /// A door carries a WORD; the search carries a glyph. Both, and the row
  /// stops reading as a row of controls and starts reading as a paragraph.
  final IconData? icon;
  final String? label;
  final String tooltip;
  final OnoteSurfaces surfaces;
  final Widget Function(VoidCallback close) builder;
  final VoidCallback? onClosed;

  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton> {
  final _key = GlobalKey();

  Future<void> _open() async {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final rect = RelativeRect.fromLTRB(
      origin.dx,
      origin.dy + box.size.height + 2,
      overlay.size.width - origin.dx - 340,
      0,
    );
    await showMenu<void>(
      context: context,
      position: rect,
      // ONE item holding the whole panel: an entry per symbol would be a
      // forty-row list to scroll for a character you can already see.
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: widget.builder(() => Navigator.of(context).pop()),
          ),
        ),
      ],
    );
    widget.onClosed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    return Padding(
      padding: const EdgeInsets.only(right: 3),
      child: Tooltip(
        message: widget.tooltip,
        child: InkWell(
          key: _key,
          borderRadius: BorderRadius.circular(5),
          onTap: _open,
          child: Container(
            height: OnoteSize.button,
            padding: EdgeInsets.symmetric(horizontal: label == null ? 6 : 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: widget.surfaces.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (widget.icon != null)
                Icon(widget.icon,
                    size: OnoteIcon.sm, color: widget.surfaces.textPrimary),
              if (label != null)
                Text(label,
                    style: OnoteType.small
                        .copyWith(color: widget.surfaces.textPrimary)),
              // No drop-down caret on a labelled door: eight of them is 120 px
              // of pure decoration on a row that has to fit 1280.
              if (label == null)
                Icon(Icons.arrow_drop_down,
                    size: 15, color: widget.surfaces.textSecondary),
            ]),
          ),
        ),
      ),
    );
  }
}

/// One palette button. Draws its own notation where a picture says it best (a
/// fraction), plain text where a character does (π, ≤).
///
/// **Fixed size, deliberately.** The row used to have ragged widths because
/// each chip sized to its own face, and the galleries were one-per-row because
/// a `Container` with an `alignment` expands to fill loose constraints. An
/// explicit box fixes both, and a grid of equal cells is easier to aim at.
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
    final tip =
        item.typeIt == null ? item.name : '${item.name} — type ${item.typeIt}';

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
