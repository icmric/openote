/// **Plug a value into an equation, see the result.**
///
/// The graph's sibling for a single point rather than a curve. Reported
/// alongside the graph work: *"would love a way to be able to sub in a value
/// for x or whatever variable and get the result, this doesnt have to be
/// linked to the graph though"* — and, on where the UI for it should live,
/// *"Primarily a dedicated small block ... but also id love the ability to
/// inline it too even if its just a shortcut."* The inline half is the same
/// `ActiveMathEditor.evaluateAtValue` closure the graph button already uses
/// (see `math_bar.dart`'s `_MoreMenu`); this file is the small block.
///
/// ## What it stores, and why
///
/// ```
/// content: {
///   'latex':     'y=3x+10',     // its OWN copy of the equation
///   'from':      '<block id>',  // the equation it follows, when there is one
///   'fromLatex': '3x+10',       // an equation INSIDE a sentence has no id
///   'value':     '2',           // what the student last typed to plug in
/// }
/// ```
///
/// Same reasoning as the graph block throughout: a block that only pointed
/// at its equation would show nothing once that equation was deleted, so the
/// latex is copied in and `from`/`fromLatex` is how it follows
/// (`AppState.pushEquationToSubstitutes`, `pushInlineEquationToSubstitutes`).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../math/graph_plot.dart';
import '../math/math_view.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';

class SubstituteBlockView extends StatefulWidget {
  const SubstituteBlockView({super.key, required this.block, required this.app});

  final Block block;
  final AppState app;

  @override
  State<SubstituteBlockView> createState() => _SubstituteBlockViewState();
}

class _SubstituteBlockViewState extends State<SubstituteBlockView> {
  Block get b => widget.block;

  String get _latex => b.content['latex'] as String? ?? '';

  late final TextEditingController _controller =
      TextEditingController(text: b.content['value'] as String? ?? '');
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    b.content['value'] = text;
    b.updatedAt = nowMs();
    widget.app.markDirty();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final latex = _latex;

    if (latex.isEmpty) {
      // Same rule as a graph or an equation with nothing in it (F-3): never
      // an invisible, unclickable husk.
      return Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.calculate_outlined, size: 16, color: s.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Nothing to evaluate — its equation is gone',
                  style: OnoteType.small.copyWith(color: s.textSecondary)),
            ),
          ],
        ),
      );
    }

    final source = graphSourceFromLatex(latex);
    final typed = _controller.text.trim();
    final SubstituteResult? outcome =
        typed.isEmpty ? null : substituteInto(source, typed);
    final variable = source.fn?.variable ?? 'x';

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: OnoteMath(latex,
                textStyle: TextStyle(fontSize: 16, color: s.textPrimary),
                compact: true),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('$variable =',
                  style: OnoteType.small.copyWith(
                      color: s.textSecondary, fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              SizedBox(
                width: 84,
                height: OnoteSize.button,
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  onChanged: _onChanged,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true, signed: true),
                  inputFormatters: [
                    // Numbers, and the handful of things `evaluateLinear`
                    // reads as one: pi, e, +-*/^(), a decimal point.
                    FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9a-zA-Z.+\-*/^() ]')),
                  ],
                  style: OnoteType.small
                      .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5),
                        borderSide: BorderSide(color: s.border)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  outcome == null
                      ? 'enter a value'
                      : '= ${outcome.result.display}',
                  overflow: TextOverflow.ellipsis,
                  style: OnoteType.small.copyWith(
                    color: outcome != null && !outcome.result.isOk
                        ? Theme.of(context).colorScheme.error
                        : s.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
