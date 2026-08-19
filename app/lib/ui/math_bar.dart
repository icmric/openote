/// The maths bar (plan: v0.18 §5.2).
///
/// It docks to the equation being edited rather than living up in the toolbar,
/// because the student's eyes are already on the equation — near-the-caret
/// beats far-and-canonical for discovery every time.
///
/// Three rows, always in the same order: the structures, whose positions never
/// change so muscle memory can form; the symbols, by category, with the most
/// used first; and a search that speaks student ("square root", "not equal",
/// "choose") plus the LaTeX fold for people who want it.
library;

import 'package:flutter/material.dart';

import '../math/math_inventory.dart';
import '../math/math_view.dart';
import '../theme/tokens.dart';

class MathBar extends StatefulWidget {
  const MathBar({
    super.key,
    required this.onInsert,
    required this.latexMode,
    required this.onToggleLatex,
    this.latexAvailable = true,
    this.trailing,
  });

  final ValueChanged<MathItem> onInsert;

  /// Whether the block is currently showing the raw LaTeX view.
  final bool latexMode;
  final VoidCallback onToggleLatex;

  /// False when the equation cannot be opened visually at all, so the toggle
  /// would take the student somewhere that immediately bounces them back.
  final bool latexAvailable;

  /// The live result (`= 42`), when there is one.
  final Widget? trailing;

  @override
  State<MathBar> createState() => _MathBarState();
}

class _MathBarState extends State<MathBar> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  MathCat _tab = MathCat.common;
  String _query = '';

  /// The structures row: fixed, in this order, forever. Everything else can be
  /// reordered; these cannot, because their positions are the muscle memory.
  static const _structureIds = [
    'frac', 'power', 'subscript', 'sqrt', 'nthroot', 'sum', 'int', 'prod',
    'lim', 'ddx', 'paren', 'abs', 'cases', 'matrix', 'binom', 'bar', 'vec',
    'words',
  ];

  static const _symbolTabs = [
    MathCat.common,
    MathCat.greek,
    MathCat.compare,
    MathCat.sets,
    MathCat.stats,
    MathCat.geometry,
    MathCat.science,
    MathCat.functions,
  ];

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _insert(MathItem item) {
    widget.onInsert(item);
    if (_query.isNotEmpty) {
      // A search is a one-shot errand: clear it so the next glance shows the
      // ordinary palette rather than a stale result set.
      _search.clear();
      setState(() => _query = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final surfaces = Theme.of(context).extension<OnoteSurfaces>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? OnoteSurfaces.dark
            : OnoteSurfaces.light);

    final results = _query.isEmpty ? const <MathItem>[] : searchMathItems(_query);

    return Container(
      decoration: BoxDecoration(
        color: surfaces.chrome,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: surfaces.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!widget.latexMode) ...[
            _Chips(
              items: [
                for (final id in _structureIds)
                  if (mathItemsById[id] != null) mathItemsById[id]!
              ],
              onTap: _insert,
              surfaces: surfaces,
            ),
            const SizedBox(height: 6),
            if (_query.isEmpty) ...[
              _tabStrip(surfaces),
              const SizedBox(height: 4),
              _Chips(
                items: mathItemsIn(_tab),
                onTap: _insert,
                surfaces: surfaces,
              ),
            ] else
              _Chips(
                items: results,
                onTap: _insert,
                surfaces: surfaces,
                emptyMessage: 'Openote doesn\'t have that as a button yet. '
                    'The LaTeX view can write anything.',
              ),
            const SizedBox(height: 6),
          ],
          Row(children: [
            if (!widget.latexMode)
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: TextField(
                    controller: _search,
                    focusNode: _searchFocus,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search,
                          size: 15, color: surfaces.textSecondary),
                      prefixIconConstraints:
                          const BoxConstraints(minWidth: 28, minHeight: 20),
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      border: const OutlineInputBorder(),
                      hintText: 'Type what you need — "square root", "theta"',
                      hintStyle: TextStyle(
                          fontSize: 12, color: surfaces.textSecondary),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                    onSubmitted: (_) {
                      if (results.isNotEmpty) _insert(results.first);
                    },
                  ),
                ),
              )
            else
              Expanded(
                child: Text(
                  'Writing the LaTeX by hand. Anything the buttons can\'t do '
                  'goes here.',
                  style:
                      TextStyle(fontSize: 12, color: surfaces.textSecondary),
                ),
              ),
            if (widget.trailing != null) ...[
              const SizedBox(width: 8),
              widget.trailing!,
            ],
            const SizedBox(width: 8),
            // The Advanced fold. One button, off to the side, never in the way
            // of a student who will never press it.
            Tooltip(
              message: widget.latexAvailable
                  ? (widget.latexMode
                      ? 'Back to the buttons'
                      : 'Write the LaTeX by hand')
                  : 'This equation uses something the buttons can\'t show yet, '
                      'so it stays in the LaTeX view',
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
          ]),
        ],
      ),
    );
  }

  Widget _tabStrip(OnoteSurfaces surfaces) => SizedBox(
        height: 24,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final c in _symbolTabs)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(5),
                  onTap: () => setState(() => _tab = c),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _tab == c ? surfaces.chrome2 : null,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      c.title,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            _tab == c ? FontWeight.w600 : FontWeight.w400,
                        color: _tab == c
                            ? surfaces.textPrimary
                            : surfaces.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

class _Chips extends StatelessWidget {
  const _Chips({
    required this.items,
    required this.onTap,
    required this.surfaces,
    this.emptyMessage,
  });

  final List<MathItem> items;
  final ValueChanged<MathItem> onTap;
  final OnoteSurfaces surfaces;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty && emptyMessage != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(emptyMessage!,
            style: TextStyle(fontSize: 12, color: surfaces.textSecondary)),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 108),
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 3,
          runSpacing: 3,
          children: [for (final i in items) _Chip(item: i, onTap: onTap, surfaces: surfaces)],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.item, required this.onTap, required this.surfaces});

  final MathItem item;
  final ValueChanged<MathItem> onTap;
  final OnoteSurfaces surfaces;

  @override
  Widget build(BuildContext context) {
    final preview = item.preview;
    // The tooltip is the teaching surface: the name a student would say, then
    // the keyboard route if there is one. Every palette press is a chance to
    // make the next one unnecessary.
    final tip = item.typeIt == null
        ? item.name
        : '${item.name} — type ${item.typeIt}';

    return Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 350),
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: () => onTap(item),
        child: Container(
          constraints: const BoxConstraints(minWidth: 32, minHeight: 30),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
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
                    textStyle: TextStyle(
                        fontSize: 13, color: surfaces.textPrimary),
                  ),
                )
              : Text(
                  item.label ?? item.name,
                  style: TextStyle(fontSize: 14, color: surfaces.textPrimary),
                ),
        ),
      ),
    );
  }
}
