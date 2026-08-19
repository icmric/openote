import 'package:flutter/material.dart';

import '../math/evaluate.dart';
import '../math/linear_math.dart';
import '../math/math_editor.dart';
import '../math/math_field.dart';
import '../math/math_view.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../theme/tokens.dart';
import '../ui/math_bar.dart';
import 'wrap_selection.dart';

/// Math block: the equation is built VISUALLY while editing — symbols drawn as
/// they will print, with dotted boxes showing where characters go — and drawn
/// as ordinary notation otherwise.
///
/// This replaces a LaTeX text field with a rendered preview underneath it. The
/// owner's report, which is the whole reason: *"for a highschool student or
/// someone non-technical this isnt going to work."*
///
/// The LaTeX view is still here, one button away, and is where an equation
/// goes when the visual editor cannot safely hold it (see [_openVisual]).
/// Storage is unchanged: canonical LaTeX in `content['latex']`.
class MathBlockView extends StatefulWidget {
  const MathBlockView({super.key, required this.block, required this.app});
  final Block block;
  final AppState app;

  @override
  State<MathBlockView> createState() => _MathBlockViewState();
}

class _MathBlockViewState extends State<MathBlockView> {
  late final TextEditingController _controller;
  final _latexFocus = FocusNode();
  final _fieldFocus = FocusNode();
  final _fieldKey = GlobalKey<MathFieldState>();

  MathEditor? _editor;
  bool _latexMode = false;
  bool _wasEditing = false;
  bool _undoPushed = false;

  bool get editing => widget.app.editingBlockId == widget.block.id;

  String get _latex => widget.block.content['latex'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
        text: widget.block.content['linearSource'] as String? ?? _latex);
    _openVisual();
  }

  /// Try to open the stored equation for visual editing. An equation the tree
  /// cannot hold — an import using a construct we don't model — opens in the
  /// LaTeX view instead, with its source untouched. Guessing here would mean
  /// dropping half a student's equation on their first keystroke.
  void _openVisual() {
    _editor = MathEditor.open(_latex);
    _latexMode = _editor == null;
  }

  @override
  void dispose() {
    _controller.dispose();
    _latexFocus.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  void _pushUndoOnce() {
    if (!_undoPushed) {
      widget.app.pushUndo();
      _undoPushed = true;
    }
  }

  /// Write straight to the model on every change, exactly as the text and code
  /// editors do. Committing live rather than on the editing→not transition is
  /// what makes a page or notebook switch — which tears the widget down before
  /// any `editing == false` build runs — unable to drop the edit.
  void _commitLatex(String latex) {
    _pushUndoOnce();
    widget.block.content['latex'] = latex.trim();
    widget.block.content['display'] = true;
    widget.block.updatedAt = nowMs();
    widget.app.markDirty();
  }

  /// The LaTeX view still accepts the linear grammar, so someone who learned
  /// `1/2` or `\sum_(n=1)^oo` keeps it.
  void _commitSource(String v) {
    _pushUndoOnce();
    final src = v.trim();
    widget.block.content['linearSource'] = v;
    widget.block.content['latex'] = src.isEmpty ? '' : linearToLatex(src);
    widget.block.content['display'] = true;
    widget.block.updatedAt = nowMs();
    widget.app.markDirty();
  }

  void _handleExitTransition() {
    if (_wasEditing && !editing) {
      _undoPushed = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if ((widget.block.content['latex'] as String? ?? '').trim().isEmpty) {
          widget.app.removeBlock(widget.block.id, recordUndo: false);
        }
      });
    }
    if (!_wasEditing && editing) {
      // Re-read on the way IN: the equation may have changed underneath us
      // (undo, sync, an AI edit through MCP) since this widget was built.
      _openVisual();
    }
    _wasEditing = editing;
  }

  void _toggleLatexMode() {
    setState(() {
      if (_latexMode) {
        _openVisual();
        if (_editor != null) _editor!.placeAtEnd();
      } else {
        _controller.text = _latex;
        _latexMode = true;
      }
    });
  }

  EvalResult? get _evaluated {
    final src = _latexMode ? _controller.text.trim() : _latex;
    if (src.isEmpty) return null;
    final r = evaluateLinear(src);
    return r.isOk ? r : null;
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
      return Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_latexMode)
              _latexEditor(textColor)
            else
              MathField(
                key: _fieldKey,
                focusNode: _fieldFocus,
                editor: _editor!,
                textStyle: TextStyle(fontSize: 22, color: textColor),
                onChanged: _commitLatex,
                onExit: (_) => _leaveEquation(),
              ),
            const SizedBox(height: 8),
            MathBar(
              latexMode: _latexMode,
              latexAvailable: _latexMode || _editor != null,
              onToggleLatex: _toggleLatexMode,
              onInsert: (item) => _fieldKey.currentState?.insertItem(item),
              trailing: _result(dark),
            ),
          ],
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
          textStyle: TextStyle(fontSize: 22, color: textColor),
        ),
      ),
    );
  }

  Widget _latexEditor(Color textColor) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _latexMode && !_latexFocus.hasFocus) {
        _latexFocus.requestFocus();
      }
    });
    final preview = linearToLatex(_controller.text);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          focusNode: _latexFocus,
          maxLines: null,
          style: const TextStyle(
              fontFamily: 'JetBrains Mono',
              fontFamilyFallback: onoteFontFallback,
              fontSize: 14),
          inputFormatters: const [
            WrapSelectionFormatter(
                pairs: WrapSelectionFormatter.bracketPairs,
                autoCloseFences: false)
          ],
          decoration: OnoteInput.bare.copyWith(
            hintText: r'LaTeX or linear maths… e.g. \sum_(n=1)^oo 1/n^2',
          ),
          onChanged: (v) {
            _commitSource(v);
            setState(() {});
          },
        ),
        if (preview.isNotEmpty) ...[
          const Divider(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: OnoteMath(preview,
                textStyle: TextStyle(fontSize: 20, color: textColor)),
          ),
        ],
      ],
    );
  }

  /// The live numeric result (MATH-7). OneNote paywalls maths answers behind
  /// an Education subscription; we own the grammar, so this is free. A
  /// calculator, not a solver — an expression it can't reduce shows nothing
  /// rather than an error the student didn't ask for.
  Widget? _result(bool dark) {
    final r = _evaluated;
    if (r == null) return null;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Text('= ',
          style: TextStyle(fontSize: 13, color: OnoteColors.graphite400)),
      Text(
        r.display,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: dark ? OnoteColors.moon0 : OnoteColors.graphite900,
        ),
      ),
    ]);
  }
}
