import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../theme/onote_theme.dart';
import '../theme/tokens.dart';
import 'latex_compat.dart';
import 'math_parse.dart';

/// The one place the app turns LaTeX into something on screen.
///
/// Two jobs the bare `Math.tex` doesn't do:
///
///  1. It runs [renderableLatex] first, so the constructs the renderer lacks
///     (`\begin{align}`, a top-level `\\`, an equation still wrapped in its
///     `$…$`) are rewritten into ones it has instead of being lost.
///  2. When an equation genuinely cannot be drawn, it says so in words and
///     shows the source. The old behaviour printed the raw LaTeX in grey with
///     no explanation at all — indistinguishable, to a student, from the app
///     having eaten their equation and left the backslashes behind.
class OnoteMath extends StatelessWidget {
  const OnoteMath(
    this.tex, {
    super.key,
    required this.textStyle,
    this.compact = false,
  });

  /// LaTeX as stored. Rewriting happens here, not in storage.
  final String tex;
  final TextStyle textStyle;

  /// Inline use (mid-sentence): the explanation moves into a tooltip so a
  /// paragraph isn't broken open by a notice box, AND the equation is set in
  /// TeX's *text* style rather than *display* style.
  ///
  /// That second half is measured, not stylistic. In OneNote's own PDF export
  /// of "Finite and Infinite Countable Sets", the inline `f(n) = ⟨cases⟩` has
  /// prose at 10.82 pt and the fractions' numerators and denominators at
  /// 7.87 pt — a 0.727 ratio, i.e. script size, i.e. `\textstyle`. Ours ran at
  /// `Math.tex`'s default `MathStyle.display`, which sets numerator and
  /// denominator at FULL size, so an inline fraction came out around 40%
  /// taller than the source it was imported from and shoved its line apart by
  /// that much more than OneNote does.
  final bool compact;

  @override
  Widget build(BuildContext context) => Math.tex(
        renderableLatex(tex),
        textStyle: textStyle,
        mathStyle: compact ? MathStyle.text : MathStyle.display,
        onErrorFallback: (e) => MathSourceFallback(
          tex: tex,
          note: mathDisplayProblem(e),
          compact: compact,
        ),
      );
}

/// What a student sees when the display, not the maths, is the limitation.
class MathSourceFallback extends StatelessWidget {
  const MathSourceFallback({
    super.key,
    required this.tex,
    required this.note,
    this.compact = false,
  });

  final String tex;
  final String note;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final surfaces = Theme.of(context).extension<OnoteSurfaces>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? OnoteSurfaces.dark
            : OnoteSurfaces.light);
    // textSecondary, not graphite400: this is text a reader has to be able to
    // read, and graphite400 fails the contrast audit at 2.80:1.
    final sourceStyle = TextStyle(
      fontFamily: 'JetBrains Mono',
      fontFamilyFallback: onoteFontFallback,
      fontSize: 13,
      color: surfaces.textPrimary,
    );

    if (compact) {
      return Tooltip(
        message: note,
        child: Text(tex, style: sourceStyle),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: surfaces.chrome2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: surfaces.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.info_outline, size: 14, color: surfaces.textSecondary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                note,
                style: TextStyle(fontSize: 12, color: surfaces.textSecondary),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          SelectableText(tex, style: sourceStyle),
        ],
      ),
    );
  }
}


/// Everything the app agrees is "maths on the clipboard".
///
/// One place, because the answer is needed by four: the equation's own Ctrl+C,
/// its Ctrl+V, a paste into a paragraph, and a paste onto the canvas. They
/// disagreed before, and the symptom was always the same — the student looked
/// at backslashes.
class MathClipboard {
  MathClipboard._();

  /// The wrappers people actually paste. `$…$` and `$$…$$` are Markdown's;
  /// `\(…\)` and `\[…\]` are what ChatGPT, MathJax and most LaTeX editors
  /// hand you, and both were recognised by the renderer and by neither paste
  /// path.
  static const List<(String, String)> _wrappers = [
    (r'$$', r'$$'),
    (r'\[', r'\]'),
    (r'\(', r'\)'),
    (r'$', r'$'),
  ];

  /// Strip any delimiters off, so the inside can be parsed as maths.
  static String unwrap(String source) {
    var t = source.trim();
    for (final (open, close) in _wrappers) {
      if (t.length > open.length + close.length &&
          t.startsWith(open) &&
          t.endsWith(close)) {
        return t.substring(open.length, t.length - close.length).trim();
      }
    }
    return t;
  }

  /// Wrap for a SENTENCE. Copying without the dollars is why a pasted equation
  /// stayed plain text in a paragraph for ever — nothing downstream could tell
  /// it was maths.
  ///
  /// A trailing `\ ` is dropped: the inline grammar requires a non-space
  /// before the closing `$` (Pandoc's rule, and the thing that stops two
  /// prices in one sentence becoming an equation), so an equation ending in a
  /// typed space would have printed its own source.
  static String wrapInline(String latex) {
    var t = latex.trim();
    // A trailing typed space serialises as `\ `, and `trim()` takes only
    // the space — leaving a DANGLING backslash, which breaks the render more
    // thoroughly than the space did. Both halves have to go.
    while (t.isNotEmpty && (t.endsWith(r'\') || t.endsWith(r'\ '))) {
      t = t.substring(0, t.length - 1).trimRight();
    }
    if (t.isEmpty) return '';
    return '\$$t\$';
  }

  /// Does this text look like maths a student meant to paste as maths?
  ///
  /// Deliberately narrow. A false positive turns someone's prose into an
  /// equation, which is worse than a false negative leaving them to press the
  /// button — so it wants either real delimiters or a backslash command, and
  /// it will not fire on a single line of ordinary words.
  static bool looksLikeMaths(String source) {
    final t = source.trim();
    if (t.isEmpty || t.contains('\n')) return false;
    for (final (open, close) in _wrappers) {
      if (t.length > open.length + close.length &&
          t.startsWith(open) &&
          t.endsWith(close)) {
        return true;
      }
    }
    // Not "does it contain a backslash word" — `C:\\Users\\me` does, and a
    // pasted file path becoming an equation is exactly the false positive
    // that costs more than the miss. The honest test is whether it would
    // actually PARSE as maths, which is self-maintaining: every command the
    // editor learns, this learns with it.
    if (!t.contains(r'\')) return false;
    return parseLatex(t).supported;
  }
}
