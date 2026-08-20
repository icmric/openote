/// The handle the toolbar's Maths tab drives (plan: v0.18 §5.2, revised).
///
/// The palette moved out of the equation's own box and into a contextual tab
/// in the toolbar, the way OneNote does it. That put a gap between the buttons
/// and the equation they act on: the bar is built by `CommandBar`, while the
/// caret lives in a `MathField` somewhere else entirely — on the page, or
/// inside the very sentence the equation sits in.
///
/// This is the whole of what crosses that gap. Deliberately a record of
/// closures rather than a reference to the widget: the toolbar has no business
/// knowing where the equation it is driving lives (a block of its own, or a
/// span inside a sentence), and this way it cannot find out.
library;

import 'package:flutter/foundation.dart';

import 'math_inventory.dart';

@immutable
class ActiveMathEditor {
  const ActiveMathEditor({
    required this.owner,
    required this.insert,
    required this.latexMode,
    required this.latexAvailable,
    required this.toggleLatex,
    this.result,
    this.useResult,
  });

  /// Whoever registered this — the `State` object of the editor. Used only so
  /// a late teardown cannot unregister a *different* editor that has since
  /// taken over (`AppState.clearActiveMath`).
  final Object owner;

  /// Drop a palette entry at the caret and give the equation the keyboard back.
  final void Function(MathItem item) insert;

  /// Whether the raw LaTeX is showing instead of the visual editor.
  final bool latexMode;

  /// False when this equation cannot be shown visually at all, so the toggle
  /// would bounce the student straight back.
  final bool latexAvailable;

  final VoidCallback toggleLatex;

  /// The live arithmetic result (`= 42`), when the expression reduces to one.
  final String? result;

  /// Put that result into the equation. A calculator OneNote paywalls; the
  /// click is what turns it from a readout into a tool.
  final VoidCallback? useResult;
}
