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
/// not by what is interesting: a fraction, a power, a root, the two big
/// operators, growing brackets, a piecewise definition, a matrix. Everything
/// else is one click further away and none of it is common enough to notice.
const List<String> kMathQuickShapes = [
  'frac', 'power', 'sqrt', 'sum', 'int', 'paren', 'cases', 'matrix',
];

/// The rest of the shapes, behind **More shapes**.
const List<String> kMathMoreShapes = [
  'subscript', 'subsup', 'nthroot', 'prod', 'lim', 'ddx', 'partial',
  'iint', 'oint', 'abs', 'floor', 'ceil', 'determinant', 'binom',
  'bar', 'hat', 'vec', 'dot', 'tilde', 'prime', 'words',
];

const List<MathCat> kMathSymbolTabs = [
  MathCat.common,
  MathCat.greek,
  MathCat.compare,
  MathCat.sets,
  MathCat.stats,
  MathCat.geometry,
  MathCat.science,
  MathCat.functions,
];

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
      _ShapesMenu(onInsert: onInsert, surfaces: s),
      _SymbolsMenu(onInsert: onInsert, surfaces: s, recentIds: recentIds),
      _Sep(surfaces: s),
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

/// A drop-down whose contents are a GRID.
///
/// The width and height are fixed here, and every chip inside is given an
/// explicit size, because a `Container` with an `alignment` expands to its
/// loose constraints — which is why every gallery used to be one symbol per
/// row.
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

class _ShapesMenu extends StatelessWidget {
  const _ShapesMenu({required this.onInsert, required this.surfaces});
  final ValueChanged<MathItem> onInsert;
  final OnoteSurfaces surfaces;

  @override
  Widget build(BuildContext context) => _MenuButton(
        icon: Icons.grid_view_outlined,
        label: 'More shapes',
        surfaces: surfaces,
        builder: (close) => _Gallery(
          width: 320,
          children: [
            for (final id in kMathMoreShapes)
              if (mathItemsById[id] case final item?)
                MathChip(
                  item: item,
                  surfaces: surfaces,
                  onTap: (i) {
                    close();
                    onInsert(i);
                  },
                ),
          ],
        ),
      );
}

/// One door to every symbol, with the search at the top of it.
///
/// Eight word-labelled drop-downs on the row was most of "chaotic": 1010 px of
/// the width, and it still made the student guess which category `≅` was filed
/// under. One panel, searchable, with the sections stacked inside it, answers
/// the guess instead of posing it.
class _SymbolsMenu extends StatefulWidget {
  const _SymbolsMenu({
    required this.onInsert,
    required this.surfaces,
    required this.recentIds,
  });

  final ValueChanged<MathItem> onInsert;
  final OnoteSurfaces surfaces;
  final List<String> recentIds;

  @override
  State<_SymbolsMenu> createState() => _SymbolsMenuState();
}

class _SymbolsMenuState extends State<_SymbolsMenu> {
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
      icon: Icons.emoji_symbols_outlined,
      label: 'Symbols',
      surfaces: s,
      onClosed: () {
        _search.clear();
      },
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
            height: 340,
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
                      prefixIcon: Icon(Icons.search,
                          size: 15, color: s.textSecondary),
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
                    child: q.isNotEmpty
                        ? _resultsSection(hits, pick, s)
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (widget.recentIds.isNotEmpty)
                                _section(
                                  'Recent',
                                  [
                                    for (final id in widget.recentIds)
                                      if (mathItemsById[id] case final i?) i
                                  ],
                                  pick,
                                  s,
                                ),
                              for (final cat in kMathSymbolTabs)
                                _section(cat.title, mathItemsIn(cat), pick, s),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _resultsSection(
      List<MathItem> hits, ValueChanged<MathItem> pick, OnoteSurfaces s) {
    if (hits.isEmpty) {
      // A miss is a pointer, never a dead end (§4.3) — and it is shown IN the
      // panel, where the student is looking, rather than as a message that
      // appears somewhere else after they press Enter.
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          'Openote doesn\'t have that as a button yet. Anything at all can be '
          'written by hand from ⋯ ▸ Write the LaTeX by hand.',
          style: OnoteType.small.copyWith(color: s.textSecondary),
        ),
      );
    }
    return _section('Matches — press Enter for the first', hits, pick, s);
  }

  Widget _section(String title, List<MathItem> items,
          ValueChanged<MathItem> pick, OnoteSurfaces s) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 6, 2, 4),
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
    required this.icon,
    required this.label,
    required this.surfaces,
    required this.builder,
    this.onClosed,
  });

  final IconData icon;
  final String label;
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 3),
        child: Tooltip(
          message: widget.label,
          child: InkWell(
            key: _key,
            borderRadius: BorderRadius.circular(5),
            onTap: _open,
            child: Container(
              height: OnoteSize.button,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: widget.surfaces.border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(widget.icon,
                    size: OnoteIcon.sm, color: widget.surfaces.textPrimary),
                const SizedBox(width: 5),
                Text(widget.label,
                    style: OnoteType.small
                        .copyWith(color: widget.surfaces.textPrimary)),
                Icon(Icons.arrow_drop_down,
                    size: 15, color: widget.surfaces.textSecondary),
              ]),
            ),
          ),
        ),
      );
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
