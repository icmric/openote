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

import 'evaluate.dart';
import 'math_inventory.dart';

@immutable
class ActiveMathEditor {
  const ActiveMathEditor({
    required this.owner,
    required this.insert,
    required this.latexMode,
    required this.latexAvailable,
    required this.toggleLatex,
    this.drawGraph,
    this.rework,
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

  /// Draw the equation being written, as a graph beside it.
  ///
  /// A CLOSURE, and null when this equation cannot be graphed — not a stored
  /// `bool canGraph`, because `setActiveMath` is called from the editor's own
  /// `build` and deliberately does not notify: a value captured there would
  /// be one keystroke stale for ever. The row asks when the menu opens.
  final VoidCallback? drawGraph;

  /// Work this equation's answers out again, in place.
  ///
  /// The page-wide pass that follows a degrees/radians switch deliberately
  /// SKIPS the equation being written — rewriting its stored text from
  /// outside would have the editor write the old tree back on the next
  /// keystroke, and for one inside a sentence it reads as a foreign edit and
  /// closes the equation. So the open one is asked to do it itself, which is
  /// also what keeps the caret where it is.
  /// [writtenIn] is the mode the page's answers were worked out in, which is
  /// what reads back how many figures each one was showing.
  final void Function(AngleMode writtenIn)? rework;

  // There WAS a live `= 42` readout on the bar here, with a button to put the
  // answer in. The owner: *"rather than having it appear up the top though
  // since that isnt intuitive, maybe we make it so that … when the person
  // puts an = sign and presses space afterwards it inserts the solution?"*
  // So the answer arrives where the student is typing — `MathEditor
  // .answerAfterEquals` — and the toolbar carries nothing about it.
}
