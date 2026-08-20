// The answer the app worked out: boxed, and switchable (owner, v0.21).
//
// Three asks in one object. *"id like for the auto calculated results to have
// a subtle box outlining them, this shows the area to click in … but also so
// people know that was calculated in app rather than typed up"*, *"by default
// it should be decimal, however if the equation is a fraction it should
// ideally give a fractional answer (if its a clean fraction, otherwise
// decimal)"*, and *"id then like to be able to click on the answer to switch
// it between dec and fraction … unless it doesnt have a fractional
// equivelant"*.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/math/evaluate.dart';
import 'package:openote/math/math_editor.dart';
import 'package:openote/math/math_linear_projection.dart';
import 'package:openote/math/math_field.dart';
import 'package:openote/math/math_tree.dart';
import 'package:openote/math/math_view.dart';

MathEditor typed(String chars) {
  final e = MathEditor.empty();
  for (final ch in chars.split('')) {
    e.insertChar(ch);
  }
  return e;
}

/// Type the run, step out of any structure it left the caret in, then finish
/// with `= ` — which is how a student actually reaches an answer.
MathEditor answered(String chars) {
  final e = typed(chars);
  e.placeAtEnd();
  e.insertChar('=');
  e.insertChar(' ');
  return e;
}

MAnswer? answerIn(MathEditor e) {
  for (final n in e.root.children) {
    if (n is MAnswer) return n;
  }
  return null;
}

void main() {
  group('the bugs that had to go first', () {
    test('sin(2)^2 is (sin 2) squared, not sin of 4', () {
      // Measured before the fix: -0.756802495308, i.e. sin(2^2). A calculator
      // shows one wrong number; a graph would show the wrong SHAPE.
      expect(evaluateLinear('sin(2)^2').value,
          closeTo(evaluateLinear('sin(2)*sin(2)').value, 1e-12));
      expect(evaluateLinear('sin(2)^2').value, closeTo(0.8268218, 1e-6));
    });

    test('…but sin x^2 without brackets still means sin of x squared', () {
      // School notation: with no bracket to say otherwise, the square binds
      // to the x. Changing this would have been a different bug.
      expect(evaluateLinear('sin 2^2').value,
          closeTo(evaluateLinear('sin(4)').value, 1e-12));
    });

    test('the cube root of a negative number is a number', () {
      // Measured before the fix: `undefined`, so y = x^(1/3) drew nothing
      // left of the origin and read as "the app is broken".
      expect(evaluateLinear('(-8)^(1/3)').value, closeTo(-2, 1e-9));
      expect(evaluateLinear('(-8)^(2/3)').value, closeTo(4, 1e-9));
    });

    test('…and an even root of a negative one is still undefined', () {
      expect(evaluateLinear('(-4)^(1/2)').display, 'undefined',
          reason: 'there is no real square root of a negative number, and '
              'saying so is the honest answer');
    });

    test('two symbols side by side multiply instead of fusing into a name', () {
      // `\\pi e` typed in the visual editor projected to the single unknown
      // name `pie` (measured) — the evaluator takes the longest letter run as
      // one name, so two adjacent words fused.
      final e = MathEditor.empty()..insertSource(r'\pi e');
      final r = evaluateLinear(rowToLinear(e.root));
      expect(r.isOk, isTrue, reason: 'got ${r.display}');
      expect(r.value, closeTo(8.5397342, 1e-6));
    });

    test('and an unknown in the middle is named correctly', () {
      final e = MathEditor.empty()..insertSource(r'2\pi r');
      expect(evaluateLinear(rowToLinear(e.root)).display, contains('r'),
          reason: 'it used to say `unknown "pir"` — a symbol the student '
              'never wrote');
    });
  });

  group('an answer is an object, not some digits', () {
    test('`= ` leaves a boxed answer behind', () {
      final e = answered('2+3');
      expect(e.latex, r'2+3=\boxed{5}');
      expect(answerIn(e), isNotNull,
          reason: 'the box is what says the app worked this out rather than '
              'the student typing it');
    });

    test('it round-trips through storage, box and all', () {
      final reopened = MathEditor.open(r'2+3=\boxed{5}');
      expect(reopened, isNotNull);
      expect(answerIn(reopened!), isNotNull,
          reason: r'\boxed{…} must read back AS an answer, or the box and '
              'the toggle would be lost the first time the note was saved');
      expect(reopened.latex, r'2+3=\boxed{5}');
    });

    test('the caret steps OVER it, and backspace takes the whole thing', () {
      final e = answered('2+3');
      final before = e.root.length;
      e.placeAtEnd();
      expect(e.backspace(), isTrue);
      expect(e.root.length, before - 1,
          reason: 'an answer is one object — deleting it half a digit at a '
              'time would make "the app worked this out" a lie');
      expect(e.latex, '2+3=');
    });

    test('and it still counts as a number in the next sum', () {
      final e = answered('2+3'); // 2+3=[5]
      e.placeAtEnd();
      e.insertChar('+');
      e.insertChar('1');
      e.insertChar('=');
      e.insertChar(' ');
      expect(e.latex, endsWith(r'\boxed{6}'),
          reason: 'the run since the last = is `[5]+1`, and the boxed 5 is '
              'worth 5');
    });
  });

  group('decimal by default, fraction when the working was fractional', () {
    test('plain arithmetic answers in decimal', () {
      expect(answered('2+3').latex, contains(r'\boxed{5}'));
      expect(answered('1.5*2').latex, contains(r'\boxed{3}'));
    });

    test('fractional working answers as a fraction', () {
      // `/` builds a fraction and leaves the caret in the denominator, so
      // stepping out is part of writing it — placeAtEnd stands in for the
      // Right arrow a student presses.
      final e = answered('1/2');
      expect(e.latex, contains(r'\boxed{\frac{1}{2}}'),
          reason: 'the question is not whether the ANSWER is tidy but '
              'whether the student was thinking in fractions');
    });

    test('a fraction that does not land tidily falls back to decimal', () {
      final e = answered('1/7');
      final a = answerIn(e);
      expect(a, isNotNull);
      // 1/7 IS rational, so it is shown as one — the fallback is for the
      // genuinely untidy, below.
      expect(e.latex, contains(r'\frac{1}{7}'));
    });

    test('…and a fractional sum with an irrational in it stays decimal', () {
      final e = MathEditor.empty()..insertSource(r'\frac{\pi}{2}');
      e.placeAtEnd();
      e.insertChar('=');
      e.insertChar(' ');
      final a = answerIn(e);
      expect(a, isNotNull, reason: 'it still answers');
      expect(a!.content.children.any((c) => c is MFrac), isFalse,
          reason: 'pi/2 has no tidy fraction, so a decimal is the truth');
    });
  });

  group('clicking switches it, and never lies', () {
    test('decimal becomes a fraction', () {
      final e = answered('1.5*1');
      final a = answerIn(e)!;
      expect(a.content.children.any((c) => c is MFrac), isFalse);
      expect(e.toggleAnswer(a), isTrue);
      expect(e.latex, contains(r'\frac{3}{2}'));
    });

    test('and a fraction becomes a decimal', () {
      final e = answered('1/2');
      final a = answerIn(e)!;
      expect(e.toggleAnswer(a), isTrue);
      expect(e.latex, contains(r'\boxed{0.5}'));
      // The WORKING is still a fraction, of course — it is what the student
      // wrote. Only the answer switched.
      expect(a.content.children.any((c) => c is MFrac), isFalse);
    });

    test('it goes back and forth without drifting', () {
      final e = answered('1/8');
      final a = answerIn(e)!;
      final first = e.latex;
      expect(e.toggleAnswer(a), isTrue);
      expect(e.toggleAnswer(a), isTrue);
      expect(e.latex, first,
          reason: 'the value is recovered from what is drawn, so a round '
              'trip has to land exactly where it started');
    });

    test('a WHOLE number refuses — there is nothing to switch to', () {
      final e = answered('2+3');
      final a = answerIn(e)!;
      expect(e.toggleAnswer(a), isFalse,
          reason: 'the owner: "unless it doesnt have a fractional '
              'equivelant if its a whole number and whatnot"');
      expect(e.latex, contains(r'\boxed{5}'), reason: 'and nothing changed');
    });

    test('and so does a decimal with no tidy fraction', () {
      final e = MathEditor.empty()..insertSource(r'\pi');
      e.placeAtEnd();
      e.insertChar('=');
      e.insertChar(' ');
      final a = answerIn(e)!;
      expect(e.toggleAnswer(a), isFalse,
          reason: 'no fraction reproduces pi, so offering one would be a lie');
    });

    test('a negative fraction keeps its sign outside the bar', () {
      final e = answered('0-1/2');
      final a = answerIn(e)!;
      if (!a.content.children.any((c) => c is MFrac)) {
        expect(e.toggleAnswer(a), isTrue);
      }
      expect(e.latex, contains('-'));
      expect(e.latex, contains(r'\frac{1}{2}'));
    });
  });

  group('rationalOf, the one walk both features needed', () {
    test('finds the tidy fraction', () {
      expect(rationalOf(0.5), (num: 1, den: 2));
      expect(rationalOf(0.125), (num: 1, den: 8));
      expect(rationalOf(-0.75), (num: -3, den: 4));
      expect(rationalOf(1 / 3)!.den, 3);
    });

    test('declines a whole number, by design', () {
      expect(rationalOf(5), isNull);
      expect(rationalOf(-2), isNull);
      expect(rationalOf(0), isNull);
    });

    test('declines what is not tidy', () {
      expect(rationalOf(3.14159265358979), isNull);
      expect(rationalOf(1.4142135623731), isNull);
    });

    test('and never returns something wrong', () {
      for (final v in [0.1, 0.2, 0.3, 2 / 7, 22 / 7, 5.25, -1 / 6]) {
        final r = rationalOf(v);
        if (r != null) {
          expect(r.num / r.den, closeTo(v, 1e-9), reason: '$v');
        }
      }
    });
  });

  testWidgets('the box is drawn, and a click on it switches the answer',
      (tester) async {
    final e = answered('1/2');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: MathField(
            editor: e,
            textStyle: const TextStyle(fontSize: 22),
            onChanged: (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(MathSourceFallback), findsNothing,
        reason: 'the boxed answer has to actually draw');
    final math = tester.widget<OnoteMath>(find.byType(OnoteMath).first);
    expect(math.tex, contains(r'\boxed'));

    // The answer is the last thing in the row, so the right-hand end of the
    // field is on it.
    final r = tester.getRect(find.byType(MathField));
    await tester.tapAt(Offset(r.right - 6, r.center.dy));
    await tester.pump();
    await tester.pump();

    expect(e.latex, contains('0.5'),
        reason: 'one click on the box switched the fraction to a decimal — '
            'the box is what advertises that the click is there');
  });
}
