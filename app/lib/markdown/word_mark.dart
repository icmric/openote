/// A highlight behind ONE word of a rendered line, found by asking the line's
/// own text layout where the word is.
///
/// Used by Review writing to show which word is being looked at on the page. The
/// review knows the word and where it starts in the raw text; the page shows the
/// text without its Markdown marks, so offsets do not carry across. What does
/// carry is "the Nth time this word appears in this line", which is how the
/// widget is told: it finds that occurrence in the rendered paragraph and paints
/// a soft rounded fill under it. Nothing about the text or its layout changes.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Whole-word occurrences of [word] in [text] that start before [limit] (all of
/// them when null).
int wholeWordCount(String text, String word, {int? limit}) {
  var n = 0;
  var from = 0;
  while (true) {
    final i = text.indexOf(word, from);
    if (i < 0 || (limit != null && i >= limit)) return n;
    if (_isWholeWord(text, i, word.length)) n++;
    from = i + word.length;
  }
}

final RegExp _letter = RegExp(r"[\p{L}\p{N}'’]", unicode: true);

bool _isWholeWord(String t, int i, int len) {
  final before = i == 0 ? '' : t[i - 1];
  final after = i + len >= t.length ? '' : t[i + len];
  return !(before.isNotEmpty && _letter.hasMatch(before)) &&
      !(after.isNotEmpty && _letter.hasMatch(after));
}

class WordMark extends SingleChildRenderObjectWidget {
  const WordMark({
    super.key,
    required this.word,
    required this.occurrence,
    required this.color,
    super.child,
  });

  final String word;

  /// Which whole-word occurrence of [word] in the line, from zero.
  final int occurrence;
  final Color color;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderWordMark(word, occurrence, color);

  @override
  void updateRenderObject(BuildContext context, _RenderWordMark r) {
    r
      ..word = word
      ..occurrence = occurrence
      ..color = color;
  }
}

class _RenderWordMark extends RenderProxyBox {
  _RenderWordMark(this._word, this._occurrence, this._color);

  String _word;
  int _occurrence;
  Color _color;

  set word(String v) {
    if (v == _word) return;
    _word = v;
    markNeedsPaint();
  }

  set occurrence(int v) {
    if (v == _occurrence) return;
    _occurrence = v;
    markNeedsPaint();
  }

  set color(Color v) {
    if (v == _color) return;
    _color = v;
    markNeedsPaint();
  }

  void _paragraphs(RenderObject node, List<RenderParagraph> out) {
    if (node is RenderParagraph) {
      out.add(node);
      return;
    }
    node.visitChildren((c) => _paragraphs(c, out));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null && _word.isNotEmpty) {
      final found = <RenderParagraph>[];
      _paragraphs(child!, found);
      var left = _occurrence;
      for (final p in found) {
        if (!p.hasSize) continue;
        final plain = p.text.toPlainText();
        var from = 0;
        while (true) {
          final i = plain.indexOf(_word, from);
          if (i < 0) break;
          from = i + _word.length;
          if (!_isWholeWord(plain, i, _word.length)) continue;
          if (left-- > 0) continue;
          final boxes = p.getBoxesForSelection(
              TextSelection(baseOffset: i, extentOffset: i + _word.length));
          final to = p.getTransformTo(this);
          // A strong fill and a solid outline in the finding's colour, so the
          // word stands out from the page at a glance, not just on looking.
          final fill = Paint()..color = _color.withValues(alpha: .42);
          final edge = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = _color;
          for (final b in boxes) {
            final r = MatrixUtils.transformRect(to, b.toRect()).inflate(3);
            final rr = RRect.fromRectAndRadius(
                r.shift(offset), const Radius.circular(5));
            context.canvas.drawRRect(rr, fill);
            context.canvas.drawRRect(rr, edge);
          }
          left = -1;
          break;
        }
        if (left < 0) break;
      }
    }
    super.paint(context, offset);
  }
}
