import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../l10n/l10n.dart';
import '../theme/onote_theme.dart';
import '../theme/tokens.dart';
import 'latex_compat.dart';
import 'math_parse.dart';

/// The body text size the editor uses when a block does not override it.
/// Named here so the maths scale below has something to be a scale OF.
const double kEditorBodyFontSize = 15.0;

/// The size an equation in a box of its own is drawn at.
const double kMathBlockFontSize = 22.0;

/// **One size for maths, wherever it sits.**
///
/// The owner: *"Would like all the sizing to be consistent between the
/// inserted maths block and the inline maths."* They were not — an equation
/// block drew at 22px and the same equation in a sentence drew at the
/// paragraph's 15px, so a fraction was 44px tall in one place and 30px in the
/// other, and the inline one read as *"constrained height wise to the text"*.
/// Nothing was clipped and the line did grow (measured: a 15px paragraph
/// holding a fraction is 46px against 39px plain); it was simply smaller.
///
/// A ratio rather than a fixed number, because a paragraph does not have to
/// be 15px — a heading is 22, and an imported OneNote box carries whatever
/// size Word gave it. Maths keeps its relationship to the words around it,
/// and in ordinary body text that relationship lands exactly on the block's
/// own 22px.
const double kMathScale = kMathBlockFontSize / kEditorBodyFontSize;

/// The style an equation is drawn in, given the text it sits among.
TextStyle mathStyleIn(TextStyle text) =>
    text.copyWith(fontSize: (text.fontSize ?? kEditorBodyFontSize) * kMathScale);

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

  /// Inline use (mid-sentence): the explanation moves into a tooltip, so a
  /// paragraph isn't broken open by a notice box.
  ///
  /// It used to mean TeX *text* style as well — script-size numerators,
  /// limits beside the sign rather than above it — to match OneNote's own
  /// export (measured there at a 0.727 ratio). **The owner has overruled
  /// that**: *"i want it to still be full size even when inlined with text,
  /// even if it ends up being taller than the text (which means we need to
  /// account for the increased line height too)"*. So the STYLE is display
  /// everywhere now and the line grows to fit; `compact` still says where the
  /// equation lives, for the failure presentation.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // The answer panel's fill. Subtle by construction: the secondary text
    // colour at a low alpha over the surface, so it reads as a quiet
    // highlight in both themes and never as a border.
    final surfaces = Theme.of(context).extension<OnoteSurfaces>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? OnoteSurfaces.dark
            : OnoteSurfaces.light);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fill = _hex(Color.alphaBlend(
      surfaces.textSecondary.withValues(alpha: dark ? 0.26 : 0.13),
      surfaces.chrome,
    ));
    // **A screen reader gets the source.** `Math.tex` paints glyph boxes and
    // says nothing, so an equation was a silent hole in a page whose prose
    // reads perfectly well (v0.24 §5). The LaTeX is not spoken maths — that
    // is designed in v0.21 and not built — but it is what the student typed,
    // and it is unambiguously better than silence.
    return Semantics(
      label: L.of(context).mathSemanticLabel(tex),
      excludeSemantics: true,
      child: Math.tex(
        renderableLatex(tex, answerFill: fill),
        textStyle: textStyle,
        // Display style, wherever it sits. A fraction is the same size in a
        // sentence as in a box of its own; the line box grows to hold it,
        // which a non-forced strut already allows for (see the field's
        // `strutStyle` note in live_markdown_engine.dart).
        mathStyle: MathStyle.display,
        onErrorFallback: (e) => MathSourceFallback(
          tex: tex,
          note: mathDisplayProblem(e),
          compact: compact,
        ),
      ),
    );
  }
}

String _hex(Color c) {
  final v = c.toARGB32() & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0').toUpperCase()}';
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
