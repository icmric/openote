import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../math/evaluate.dart';
import '../math/linear_math.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';

/// Math block: linear/LaTeX entry while editing, rendered 2-D notation
/// otherwise. Commit runs on the editing→not state transition (F-3 fix) so
/// clicking anywhere else can never lose an edit. Storage: canonical LaTeX
/// (content['latex']); the user's linear input preserved (linearSource).
class MathBlockView extends StatefulWidget {
  const MathBlockView({super.key, required this.block, required this.app});
  final Block block;
  final AppState app;

  @override
  State<MathBlockView> createState() => _MathBlockViewState();
}

class _MathBlockViewState extends State<MathBlockView> {
  late final TextEditingController _controller;
  final _focus = FocusNode();
  bool _wasEditing = false;
  bool _undoPushed = false;

  bool get editing => widget.app.editingBlockId == widget.block.id;

  // MATH-4 (starter palette): each chip inserts its linear form at the caret
  // — the palette teaches the syntax (style guide principle).
  static const _palette = <(String, String)>[
    ('∑', r'\sum_( )^( ) '), ('∫', r'\int_( )^( ) '), ('∏', r'\prod_( )^( ) '),
    ('lim', r'lim_(x\to 0) '), ('a/b', '( )/( )'), ('√', '√( )'),
    ('ⁿ√', '√(n& )'), ('x²', '^2'), ('xₙ', '_n'), ('matrix', '■(a&b@c&d)'),
    ('cases', r'\cases(x&x>0@-x&x≤0)'), ('|x|', r'\abs( )'),
    ('π', 'π'), ('∞', '∞'), ('α', 'α'), ('β', 'β'), ('θ', 'θ'), ('λ', 'λ'),
    ('≤', '≤'), ('≥', '≥'), ('≠', '≠'), ('±', '±'), ('→', '→'), ('∈', '∈'),
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
        text: widget.block.content['linearSource'] as String? ??
            widget.block.content['latex'] as String? ??
            '');
  }

  /// Write the linear source + canonical LaTeX straight to the model on every
  /// keystroke — same as the text/code editors. Committing live (rather than
  /// only on the editing→not transition) means a page/notebook switch, which
  /// tears the widget down *before* any `editing==false` build runs, can no
  /// longer drop the edit (the old F-3-class hazard, this time on math).
  void _commit(String v) {
    final src = v.trim();
    widget.block.content['linearSource'] = v;
    widget.block.content['latex'] = src.isEmpty ? '' : linearToLatex(src);
    widget.block.content['display'] = true;
    widget.block.updatedAt = nowMs();
    widget.app.markDirty();
  }

  /// On exit, only clean up an equation the user left empty. The content is
  /// already committed live by [_commit], and we deliberately DON'T re-run
  /// `linearToLatex` here — re-entering a LaTeX-authored equation and leaving
  /// it untouched must not rewrite its canonical storage.
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
    _wasEditing = editing;
  }

  /// The evaluated value of what's typed, or null when there's nothing to
  /// evaluate. Recomputed per build — parsing a line of arithmetic is trivial
  /// next to laying out the LaTeX preview beside it.
  EvalResult? get _evaluated {
    final src = _controller.text.trim();
    if (src.isEmpty) return null;
    final r = evaluateLinear(src);
    return r.isOk ? r : null;
  }

  void _insertAtCaret(String s) {
    final sel = _controller.selection;
    final text = _controller.text;
    final at = sel.isValid ? sel.start : text.length;
    final atEnd = sel.isValid ? sel.end : text.length;
    _controller.text = text.replaceRange(at, atEnd, s);
    // Place caret inside the first placeholder "( )" if present, else after.
    final ph = s.indexOf('( )');
    final caret = ph >= 0 ? at + ph + 1 : at + s.length;
    _controller.selection = TextSelection.collapsed(offset: caret);
    _focus.requestFocus();
    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _handleExitTransition();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final textColor = dark ? OnoteColors.moon0 : OnoteColors.graphite900;

    if (editing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_focus.hasFocus) _focus.requestFocus();
      });
      final preview = linearToLatex(_controller.text);
      return Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              focusNode: _focus,
              maxLines: null,
              style: const TextStyle(fontFamily: 'JetBrains Mono', fontFamilyFallback: onoteFontFallback, fontSize: 14),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: r'Linear math… e.g. \sum_(n=1)^oo 1/n^2',
              ),
              onChanged: (v) {
                if (!_undoPushed) {
                  widget.app.pushUndo();
                  _undoPushed = true;
                }
                _commit(v);
                setState(() {});
              },
            ),
            // Symbol & structure palette (MATH-4 starter)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final (label, insert) in _palette)
                    InkWell(
                      borderRadius: BorderRadius.circular(5),
                      onTap: () => _insertAtCaret(insert),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: dark
                              ? OnoteColors.night100
                              : OnoteColors.paper100,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(label,
                            style: TextStyle(
                                fontSize: 12,
                                color: dark
                                    ? OnoteColors.moon100
                                    : OnoteColors.graphite700)),
                      ),
                    ),
                ],
              ),
            ),
            // Live numeric result (MATH-7). OneNote paywalls math answers
            // behind an Education subscription; we own the grammar, so this is
            // free. A calculator, not a solver — an expression it can't reduce
            // simply shows nothing rather than an error the user didn't ask for.
            if (_evaluated case final r? when r.isOk) ...[
              const SizedBox(height: 6),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text('= ',
                    style: TextStyle(
                        fontSize: 14, color: OnoteColors.graphite400)),
                SelectableText(
                  r.display,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: dark ? OnoteColors.moon0 : OnoteColors.graphite900,
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Insert the result into the equation',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => _insertAtCaret(' = ${r.display}'),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.subdirectory_arrow_left, size: 15),
                    ),
                  ),
                ),
              ]),
            ],
            if (preview.isNotEmpty) ...[
              const Divider(height: 14),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Math.tex(
                  preview,
                  textStyle: TextStyle(fontSize: 20, color: textColor),
                  onErrorFallback: (e) => Text(
                    preview,
                    style: const TextStyle(
                        fontFamily: 'JetBrains Mono', fontFamilyFallback: onoteFontFallback,
                        color: OnoteColors.graphite400),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    final latex = widget.block.content['latex'] as String? ?? '';
    if (latex.isEmpty) {
      // F-3: never render an invisible, unclickable husk.
      return Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.functions, size: 16, color: OnoteColors.graphite400),
            const SizedBox(width: 6),
            Text('Empty equation — click to edit',
                style:
                    TextStyle(fontSize: 12, color: OnoteColors.graphite400)),
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
        child: Math.tex(
          latex,
          textStyle: TextStyle(fontSize: 22, color: textColor),
          onErrorFallback: (e) => Text(latex,
              style: const TextStyle(
                  fontFamily: 'JetBrains Mono', fontFamilyFallback: onoteFontFallback, color: OnoteColors.graphite400)),
        ),
      ),
    );
  }
}
