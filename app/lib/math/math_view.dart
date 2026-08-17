import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../theme/onote_theme.dart';
import '../theme/tokens.dart';
import 'latex_compat.dart';

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
  /// paragraph isn't broken open by a notice box.
  final bool compact;

  @override
  Widget build(BuildContext context) => Math.tex(
        renderableLatex(tex),
        textStyle: textStyle,
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
