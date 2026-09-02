import 'package:flutter/material.dart';

import '../math/equation_editor.dart';
import '../math/math_view.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';

/// Math block: the equation is built VISUALLY while editing — symbols drawn as
/// they will print, with dotted boxes showing where characters go — and drawn
/// as ordinary notation otherwise.
///
/// This replaces a LaTeX text field with a rendered preview underneath it. The
/// owner's report, which is the whole reason: *"for a highschool student or
/// someone non-technical this isnt going to work."*
///
/// The editing machinery itself — the `MathEditor` lifecycle, the LaTeX
/// escape hatch, the palette registration, the calculator — lives in
/// [EquationEditor], shared verbatim with the inline equation editor (v0.20
/// §A). What stays HERE is what only a block can answer: where the equation
/// is stored (`content['latex']`), how undo coalesces, when an empty husk is
/// removed, and how much wider the box may grow.
class MathBlockView extends StatefulWidget {
  const MathBlockView({super.key, required this.block, required this.app});
  final Block block;
  final AppState app;

  @override
  State<MathBlockView> createState() => _MathBlockViewState();
}

class _MathBlockViewState extends State<MathBlockView> {
  bool _wasEditing = false;
  bool _undoPushed = false;

  bool get editing => widget.app.editingBlockId == widget.block.id;

  String get _latex => widget.block.content['latex'] as String? ?? '';

  /// When the last undo point was taken, so a burst of typing is one step.
  int _lastUndoAt = 0;

  /// Take an undo point, at most one per [_undoGap] of continuous typing.
  ///
  /// It used to take exactly ONE for the whole editing session, so Ctrl+Z
  /// after a typo did not take back the typo — it took back the equation, and
  /// with it the block. The punishment for a mistyped character was the whole
  /// thing you were writing.
  ///
  /// Coalescing on time rather than keeping a second undo stack inside the
  /// editor is deliberate: the page already has an undo stack that syncs and
  /// persists, and two stacks means two chances to disagree about which one
  /// Ctrl+Z belongs to.
  static const int _undoGap = 700;

  void _pushUndoOnce({bool force = false}) {
    final now = nowMs();
    if (force || !_undoPushed || now - _lastUndoAt > _undoGap) {
      widget.app.pushUndo();
      _undoPushed = true;
      _lastUndoAt = now;
    }
  }

  /// Write straight to the model on every change, exactly as the text and code
  /// editors do. Committing live rather than on the editing→not transition is
  /// what makes a page or notebook switch — which tears the widget down before
  /// any `editing == false` build runs — unable to drop the edit.
  void _commitLatex(String latex) {
    _pushUndoOnce();
    widget.block.content['latex'] = latex.trim();
    // **A stored source that has gone stale is worse than none.** It is only
    // ever the text somebody typed in the LaTeX view; the moment the equation
    // is edited any other way it describes a DIFFERENT equation, and
    // reopening that view then offered to rebuild the page from it. The
    // source path writes itself back straight after this (see
    // `EquationEditor._commitSource`), so a real source edit survives.
    widget.block.content.remove('linearSource');
    widget.block.content['display'] = true;
    widget.block.updatedAt = nowMs();
    // **Every graph following this equation redraws now**, not on a timer:
    // the owner asked to *"see the graph change as i type"*, and a compiled
    // curve costs microseconds a sample, so there is nothing to debounce.
    // Notify only when something actually moved — a keystroke that changes
    // no graph must not rebuild the page.
    widget.app.pushEquationToGraphs(widget.block.id, latex.trim());
    widget.app.pushEquationToSubstitutes(widget.block.id, latex.trim());
    widget.app.markDirty();
  }

  void _handleExitTransition() {
    if (_wasEditing && !editing) {
      _undoPushed = false;
      // The Maths tab itself is cleared by EquationEditor's own dispose —
      // this widget no longer owns the registration.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if ((widget.block.content['latex'] as String? ?? '').trim().isEmpty) {
          widget.app.removeBlock(widget.block.id, recordUndo: false);
        }
      });
    }
    _wasEditing = editing;
  }

  /// The widest an equation may push its own box before it starts scrolling
  /// instead. Past this a block stops being a block and starts being the page.
  static const double _kMaxMathWidth = 900;

  /// Widen the block to what is actually being written.
  ///
  /// [fieldWidth] is measured from the laid-out equation rather than guessed
  /// from the LaTeX: the caret rule, the empty `\square` boxes and a
  /// summation's stacked limits all add width no string-inspection would
  /// predict. Grow only — never shrink — because shrinking mid-keystroke makes
  /// the box twitch while you type, and a student who has widened it by hand
  /// should keep that width.
  void _growToWidth(double fieldWidth) {
    if (!mounted) return;
    const chrome = 24.0; // the block's own padding, both sides
    final need = fieldWidth + chrome;
    final have = widget.block.w;
    if (need <= have + 1) return;
    final target = need > _kMaxMathWidth ? _kMaxMathWidth : need;
    if (target <= have + 1) return;
    widget.block.w = target;
    widget.block.updatedAt = nowMs();
    widget.app.updateBlock(widget.block);
  }

  /// A graph of this equation, beside it, following it from now on.
  void _drawGraph() {
    final latex = _latex.trim();
    if (latex.isEmpty) return;
    widget.app.pushUndo();
    widget.app.insertGraph(latex: latex, from: widget.block.id);
  }

  /// A value plugged into this equation, beside it, following it from now on.
  void _evaluateAtValue() {
    final latex = _latex.trim();
    if (latex.isEmpty) return;
    widget.app.pushUndo();
    widget.app.insertSubstitute(latex: latex, from: widget.block.id);
  }

  void _leaveEquation() {
    widget.app.select(widget.block.id, edit: false);
  }

  @override
  Widget build(BuildContext context) {
    _handleExitTransition();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final textColor = dark ? OnoteColors.moon0 : OnoteColors.graphite900;

    if (editing) {
      // Consume the click-point token the canvas set, once the field exists
      // — the caret lands where the click did instead of jumping to a fixed
      // end regardless of it ("clicking into an equation just puts me at
      // [a fixed spot] every time").
      final tapAt = widget.app.pendingCaretGlobal;
      if (tapAt != null) widget.app.pendingCaretGlobal = null;
      return Padding(
        padding: const EdgeInsets.all(10),
        child: EquationEditor(
          app: widget.app,
          placement: EquationPlacement.block,
          textStyle:
              TextStyle(fontSize: kMathBlockFontSize, color: textColor),
          latex: _latex,
          linearSource: widget.block.content['linearSource'] as String?,
          onLinearChanged: (v) =>
              widget.block.content['linearSource'] = v,
          onChanged: _commitLatex,
          onExit: (_) => _leaveEquation(),
          onDrawGraph: _drawGraph,
          onEvaluateAtValue: _evaluateAtValue,
          onWidthWanted: _growToWidth,
          initialTapGlobal: tapAt,
        ),
      );
    }

    final latex = _latex;
    if (latex.isEmpty) {
      // F-3: never render an invisible, unclickable husk.
      return const Padding(
        padding: EdgeInsets.all(10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.functions, size: 16, color: OnoteColors.graphite400),
            SizedBox(width: 6),
            Text('Empty equation — click to edit',
                style: TextStyle(fontSize: 12, color: OnoteColors.graphite400)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      // scaleDown: a wide equation shrinks to the block's width instead of
      // overflowing (the imported-equation "pixel overflow" error).
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: OnoteMath(
          latex,
          textStyle:
              TextStyle(fontSize: kMathBlockFontSize, color: textColor),
        ),
      ),
    );
  }
}
