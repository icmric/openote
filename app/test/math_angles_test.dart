// Angles, and the panel an answer sits in (owner, v0.21).
//
// The owner, testing it: *"i dont think the sin and cosine (and i assume tan,
// their inverses, etc) arent calculating properly, they are definitley giving
// the wrong results. I also didnt test it, but id like it to be able to
// handle radians (i.e. being able to put \pi in there)."* Measured: `sin(30)`
// answered −0.988, because 30 was taken as radians. A year-10 student writing
// `sin(30)` means thirty degrees, and every school calculator agrees.
//
// The rule is one sentence: **degrees, unless the angle contains π** (or a
// degree sign, which converts itself, or the word `rad`). Nobody writes
// `sin(π/6)` meaning degrees, so a π in the angle is the student saying which
// they meant — which is what was asked for.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/math/evaluate.dart';
import 'package:openote/math/latex_compat.dart';
import 'package:openote/math/math_editor.dart';
import 'package:openote/math/math_linear_projection.dart';
import 'package:openote/math/math_view.dart';

String answerOf(String latex) {
  final e = MathEditor.empty();
  e.insertSource(latex);
  return evaluateLinear(rowToLinear(e.root)).display;
}

void main() {
  group('degrees, the way a school calculator does it', () {
    test('the ones every student checks', () {
      expect(answerOf(r'\sin(30)'), '0.5');
      expect(answerOf(r'\cos(60)'), '0.5');
      expect(answerOf(r'\tan(45)'), '1');
      expect(answerOf(r'\sin(90)'), '1');
      expect(answerOf(r'\cos(0)'), '1');
    });

    test('and the answer is exact enough to read as exact', () {
      // Floating point makes sin 30 land at 0.49999999999999994; the display
      // rounding is what turns that back into the half a student expects.
      expect(evaluateLinear('sin(30)').value, closeTo(0.5, 1e-12));
      expect(evaluateLinear('sin(180)').display, '0',
          reason: 'sin 180 is zero, not 1.2e-16');
    });
  });

  group('radians, when the angle says so', () {
    test('a π in the angle means radians', () {
      expect(answerOf(r'\sin(\frac{\pi}{6})'), '0.5');
      expect(answerOf(r'\cos(\pi)'), '-1');
      expect(answerOf(r'\sin(\pi)'), '0');
      expect(answerOf(r'\tan(\frac{\pi}{4})'), '1');
    });

    test('π anywhere in the angle counts, not just alone', () {
      expect(evaluateLinear('sin(2*pi)').value, closeTo(0, 1e-12));
      expect(evaluateLinear('cos(pi/3)').value, closeTo(0.5, 1e-12));
    });

    test('and a degree sign forces degrees even beside a π', () {
      // The sign converts itself on the spot, so nothing converts twice.
      expect(evaluateLinear('30°').value, closeTo(0.5235987, 1e-6));
      expect(answerOf(r'\sin(30^{\circ})'), '0.5');
      expect(answerOf(r'\sin(45^{\circ})'),
          evaluateLinear('sin(45)').display);
    });
  });

  group('the inverses', () {
    test('sin⁻¹ is the inverse, not one over sin', () {
      // The owner chose `⁻¹` over `arcsin` for the palette, so this IS the
      // app's inverse trigonometry — and it projected to `(sin )^(-1)`,
      // which the evaluator read as a reciprocal and then choked on. Every
      // inverse trig button was dead to the calculator.
      final e = MathEditor.empty()..insertSource(r'\sin^{-1}(0.5)');
      expect(rowToLinear(e.root), startsWith('asin'));
      expect(evaluateLinear(rowToLinear(e.root)).display, '30');
    });

    test('they give degrees back, because degrees go in', () {
      expect(answerOf(r'\cos^{-1}(0.5)'), '60');
      expect(answerOf(r'\tan^{-1}(1)'), '45');
    });

    test('and they come home', () {
      expect(evaluateLinear('asin(sin(30))').value, closeTo(30, 1e-9));
      expect(evaluateLinear('atan(tan(20))').value, closeTo(20, 1e-9));
    });
  });

  group('through the whole chain, as a student writes it', () {
    test('`= ` after a trig sum writes the right answer', () {
      final e = MathEditor.empty()..insertSource(r'\sin(30)');
      e.placeAtEnd();
      e.insertChar('=');
      e.insertChar(' ');
      expect(e.latex, endsWith(r'=\boxed{0.5}'));
    });

    test('and a radian one', () {
      final e = MathEditor.empty()..insertSource(r'\cos(\pi)');
      e.placeAtEnd();
      e.insertChar('=');
      e.insertChar(' ');
      expect(e.latex, endsWith(r'=\boxed{-1}'));
    });
  });

  group('the answer sits in a soft panel, not an outline', () {
    // The owner: *"rather than the white outline like that, could we maybe do
    // a more subtle grey background?"* `\boxed` draws a RULE in the current
    // colour; `\fcolorbox` with one colour for border and fill is a panel
    // with no line at all — and it is the only fill flutter_math paints.
    test('the box is repainted as a filled panel', () {
      final out = renderableLatex(r'2+3=\boxed{5}', answerFill: '#EEEEEE');
      expect(out, contains(r'\fcolorbox{#EEEEEE}{#EEEEEE}'));
      expect(out, isNot(contains(r'\boxed')));
    });

    test('STORAGE keeps the theme-free form', () {
      final e = MathEditor.empty()..insertSource(r'2+3=\boxed{5}');
      expect(e.latex, r'2+3=\boxed{5}',
          reason: 'the note holds real LaTeX that exports as a boxed number; '
              'only the renderer knows whether it is drawing on paper or in '
              'the dark');
    });

    test('an answer holding a fraction keeps its own braces', () {
      final out =
          renderableLatex(r'\boxed{\frac{1}{2}}', answerFill: '#EEEEEE');
      expect(out, contains(r'\frac{1}{2}'));
      expect(out, isNot(contains(r'\boxed')));
    });

    test('two answers are both repainted', () {
      final out =
          renderableLatex(r'\boxed{5}+\boxed{6}', answerFill: '#EEEEEE');
      expect(RegExp(r'\\fcolorbox').allMatches(out).length, 2);
    });

    test('and an unbalanced one is left exactly as it came', () {
      expect(renderableLatex(r'\boxed{', answerFill: '#EEEEEE'),
          contains(r'\boxed{'),
          reason: 'never rewrite what cannot be read');
    });

    testWidgets('the panel content is the same size as the working',
        (tester) async {
      // A `$` re-enters maths in TEXT style, which set the answer smaller
      // than the identical fraction three characters to its left (measured
      // 37.4px against 53.7px). The panel carries \displaystyle for the same
      // reason the selection highlight does.
      Future<Size> sizeOf(String tex) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: OnoteMath(tex, textStyle: const TextStyle(fontSize: 20)),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        return tester.getSize(find.byType(OnoteMath));
      }

      final bare = await sizeOf(r'\frac{1}{2}');
      final boxed = await sizeOf(r'\boxed{\frac{1}{2}}');
      expect(boxed.height - bare.height, closeTo(0.68 * 20, 1.0),
          reason: 'the panel costs its padding and nothing else — the '
              'fraction inside is the same size as the one outside');
    });

    testWidgets('and it still draws, in both themes', (tester) async {
      for (final dark in [false, true]) {
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: OnoteMath(r'2+3=\boxed{5}',
                  textStyle: TextStyle(fontSize: 20)),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.byType(MathSourceFallback), findsNothing,
            reason: 'dark=$dark');
      }
    });
  });
}
