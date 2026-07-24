import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

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
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
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
            if (preview.isNotEmpty) ...[
              const Divider(height: 14),
              Math.tex(
                preview,
                textStyle: TextStyle(fontSize: 20, color: textColor),
                onErrorFallback: (e) => Text(
                  preview,
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      color: OnoteColors.graphite400),
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
      child: Math.tex(
        latex,
        textStyle: TextStyle(fontSize: 22, color: textColor),
        onErrorFallback: (e) => Text(latex,
            style: const TextStyle(
                fontFamily: 'monospace', color: OnoteColors.graphite400)),
      ),
    );
  }
}
