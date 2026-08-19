/// The **Maths** tab of the toolbar (plan: v0.18 §5.2, revised 2026-08-19).
///
/// It appears only while an equation is being written, and it goes away the
/// moment you finish — a contextual tab, exactly as OneNote does it.
///
/// **Why it moved.** The palette originally docked inside the equation's own
/// box. The owner's verdict: *"At the moment you seem to have decided to put
/// all the options in the box itself, this isnt great. I want them in the bar
/// up the top like it is in onenote."* The reason is worth keeping: a palette
/// inside the box competes for the space the student is actually looking at,
/// and it moves every time the equation grows a line. The toolbar stays put.
///
/// ONE row, because that is what every other tab here is: the shapes inline in
/// a fixed order (their positions ARE the muscle memory), then one gallery
/// button per symbol category, then search and the LaTeX fold. It scrolls
/// horizontally rather than wrapping, like the Insert tab.
library;

import 'package:flutter/material.dart';

import '../math/math_inventory.dart';
import '../math/math_view.dart';
import '../theme/tokens.dart';

/// The shapes, in this order, forever — everything else may be reordered.
const List<String> kMathStructureIds = [
  'frac', 'power', 'subscript', 'sqrt', 'nthroot', 'sum', 'int', 'prod',
  'lim', 'ddx', 'paren', 'abs', 'cases', 'matrix', 'binom', 'bar', 'vec',
  'words',
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

class MathBar extends StatefulWidget {
  const MathBar({
    super.key,
    required this.onInsert,
    required this.latexMode,
    required this.onToggleLatex,
    this.latexAvailable = true,
    this.result,
  });

  final ValueChanged<MathItem> onInsert;
  final bool latexMode;
  final VoidCallback onToggleLatex;
  final bool latexAvailable;

  /// The live arithmetic answer, when there is one.
  final String? result;

  @override
  State<MathBar> createState() => _MathBarState();
}

class _MathBarState extends State<MathBar> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _insert(MathItem item) {
    widget.onInsert(item);
    if (_search.text.isNotEmpty) {
      // A search is a one-shot errand — leaving the query up would hide the
      // ordinary palette behind something the student has finished with.
      _search.clear();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final surfaces = Theme.of(context).extension<OnoteSurfaces>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? OnoteSurfaces.dark
            : OnoteSurfaces.light);

    if (widget.latexMode) {
      return Row(children: [
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Text(
            'Writing the LaTeX by hand — anything the buttons can\'t do goes '
            'here.',
            style: TextStyle(fontSize: 12, color: surfaces.textSecondary),
          ),
        ),
        if (widget.result != null) _resultChip(surfaces),
        _latexToggle(context, surfaces),
      ]);
    }

    return Row(children: [
      for (final id in kMathStructureIds)
        if (mathItemsById[id] case final item?)
          MathChip(item: item, onTap: _insert, surfaces: surfaces),
      _divider(surfaces),
      for (final cat in kMathSymbolTabs)
        _CategoryButton(cat: cat, onInsert: _insert, surfaces: surfaces),
      _divider(surfaces),
      _searchBox(context, surfaces),
      if (widget.result != null) _resultChip(surfaces),
      _latexToggle(context, surfaces),
    ]);
  }

  Widget _divider(OnoteSurfaces surfaces) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: SizedBox(
          height: 22,
          child: VerticalDivider(width: 1, color: surfaces.border),
        ),
      );

  Widget _searchBox(BuildContext context, OnoteSurfaces surfaces) => SizedBox(
        width: 190,
        height: 28,
        child: TextField(
          controller: _search,
          focusNode: _searchFocus,
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon:
                Icon(Icons.search, size: 15, color: surfaces.textSecondary),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 26, minHeight: 20),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            border: const OutlineInputBorder(),
            hintText: 'Find a symbol…',
            hintStyle: TextStyle(fontSize: 12, color: surfaces.textSecondary),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (v) {
            final hits = searchMathItems(v);
            if (hits.isNotEmpty) {
              _insert(hits.first);
            } else {
              // A miss is a pointer, never a dead end (§4.3).
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text(
                    'Openote doesn\'t have that as a button yet. The LaTeX '
                    'view can write anything.'),
              ));
            }
          },
        ),
      );

  Widget _resultChip(OnoteSurfaces surfaces) => Padding(
        padding: const EdgeInsets.only(left: 8, right: 2),
        child: Tooltip(
          message: 'What this works out to',
          child: Text('= ${widget.result}',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: surfaces.textPrimary)),
        ),
      );

  /// The Advanced fold: one button, at the end, never in the way of a student
  /// who will never press it.
  Widget _latexToggle(BuildContext context, OnoteSurfaces surfaces) => Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Tooltip(
          message: widget.latexAvailable
              ? (widget.latexMode
                  ? 'Back to the buttons'
                  : 'Write the LaTeX by hand')
              : 'This equation uses something the buttons can\'t show yet, so '
                  'it stays in the LaTeX view',
          child: TextButton(
            onPressed: widget.latexAvailable ? widget.onToggleLatex : null,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              foregroundColor: widget.latexMode
                  ? Theme.of(context).colorScheme.primary
                  : surfaces.textSecondary,
            ),
            child: Text(widget.latexMode ? 'Buttons' : 'LaTeX',
                style: const TextStyle(fontSize: 12)),
          ),
        ),
      );
}

/// A symbol category, opened as a gallery. One row cannot hold two hundred
/// symbols, and a scrolling strip of them would be a lucky dip — the
/// categories are how a student narrows down before they look.
class _CategoryButton extends StatelessWidget {
  const _CategoryButton({
    required this.cat,
    required this.onInsert,
    required this.surfaces,
  });

  final MathCat cat;
  final ValueChanged<MathItem> onInsert;
  final OnoteSurfaces surfaces;

  @override
  Widget build(BuildContext context) {
    final items = mathItemsIn(cat);
    return Padding(
      padding: const EdgeInsets.only(right: 3),
      child: PopupMenuButton<MathItem>(
        tooltip: cat.title,
        position: PopupMenuPosition.under,
        onSelected: onInsert,
        itemBuilder: (ctx) => [
          PopupMenuItem<MathItem>(
            // ONE menu item holding the whole gallery: an entry per symbol
            // would be a forty-row list to scroll for a character you can see.
            enabled: false,
            padding: EdgeInsets.zero,
            child: SizedBox(
              width: 296,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Wrap(
                  spacing: 3,
                  runSpacing: 3,
                  children: [
                    for (final i in items)
                      MathChip(
                        item: i,
                        surfaces: surfaces,
                        onTap: (item) {
                          Navigator.of(ctx).pop();
                          onInsert(item);
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: surfaces.chrome2,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: surfaces.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(cat.title,
                style: TextStyle(fontSize: 12, color: surfaces.textPrimary)),
            Icon(Icons.arrow_drop_down, size: 15, color: surfaces.textSecondary),
          ]),
        ),
      ),
    );
  }
}

/// One palette button. Draws its own notation where a picture says it best (a
/// fraction), plain text where a character does (π, ≤).
class MathChip extends StatelessWidget {
  const MathChip({
    super.key,
    required this.item,
    required this.onTap,
    required this.surfaces,
  });

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
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: () => onTap(item),
          child: Container(
            constraints: const BoxConstraints(minWidth: 32, minHeight: 30),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: surfaces.chrome2,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: surfaces.border),
            ),
            alignment: Alignment.center,
            child: preview != null
                ? IgnorePointer(
                    child: OnoteMath(
                      preview,
                      compact: true,
                      textStyle:
                          TextStyle(fontSize: 13, color: surfaces.textPrimary),
                    ),
                  )
                : Text(
                    item.label ?? item.name,
                    style: TextStyle(fontSize: 14, color: surfaces.textPrimary),
                  ),
          ),
        ),
      ),
    );
  }
}
