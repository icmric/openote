// How complex an equation the calculator can actually take (owner, v0.21).
//
// The owner asked, before graphing: *"Can it handle more complex equations?"*
// A 92-expression sweep of real school maths said no — and the failures were
// in year-8 material, not year-12, with two of them SILENT wrong answers
// rather than refusals. Each test below is one of those, stated as the input
// a student writes.
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/math/evaluate.dart';
import 'package:openote/math/math_editor.dart';
import 'package:openote/math/math_linear_projection.dart';
import 'package:openote/math/math_tree.dart';

String answerOf(String latex) {
  final e = MathEditor.empty();
  e.insertSource(latex);
  return evaluateLinear(rowToLinear(e.root)).display;
}

MathEditor typedAnswer(String keys) {
  final e = MathEditor.empty();
  for (final ch in keys.split('')) {
    e.insertChar(ch);
  }
  e.placeAtEnd();
  e.insertChar('=');
  e.insertChar(' ');
  return e;
}

void main() {
  group('a power keeps its base when the note is saved and reopened', () {
    // The worst of them: `16²` stored as `{16}^{2}`, and the parser dissolved
    // the group and took only the `6`. So 16² came back as 36, 10⁸ as 0, and
    // compound interest 1000×1.05³ as 125000 — silently, in saved work, and
    // the equation on screen changed too.
    test('the whole base survives the round trip', () {
      for (final entry in {
        '16^2': 256.0,
        '10^8': 100000000.0,
        '100^2': 10000.0,
        '2.5^2': 6.25,
        '1000*1.05^3': 1157.625,
      }.entries) {
        final e = MathEditor.empty();
        for (final ch in entry.key.split('')) {
          e.insertChar(ch);
        }
        final reopened = MathEditor.open(e.latex);
        expect(reopened, isNotNull, reason: entry.key);
        expect(evaluateLinear(rowToLinear(reopened!.root)).value,
            closeTo(entry.value, 1e-9),
            reason: '${entry.key} came back as something else');
        expect(reopened.latex, e.latex,
            reason: 'and the equation itself must not change on screen');
      }
    });
  });

  group('the shapes a textbook and a chat message use', () {
    test('brackets raised to a power', () {
      // Plain `(` `)` are ordinary atoms, so the script attached to the
      // CLOSING bracket and the whole thing errored.
      expect(answerOf(r'(2+3)^{2}'), '25');
      expect(answerOf(r'(-2)^{3}'), '-8');
      expect(answerOf(r'(\sqrt{5})^{2}'), '5');
      expect(answerOf(r'500\times(1+0.06)^{4}'), startsWith('631.2'),
          reason: 'the year-10 compound-interest question');
    });

    test('a power whose base LaTeX leaves outside the braces', () {
      // `16^{1/2}` puts only the `6` under the script — right for a renderer,
      // which draws 16^… either way, and wrong for a calculator.
      expect(answerOf(r'16^{\frac{1}{2}}'), '4');
      expect(answerOf(r'6.02\times10^{23}'), contains('6.02'));
      expect(evaluateLinear(rowToLinear(
              (MathEditor.empty()..insertSource(r'1.5\times10^{-3}')).root))
          .value, closeTo(0.0015, 1e-12));
    });

    test('sin²x + cos²x = 1, the identity that could not be checked', () {
      expect(answerOf(r'\sin^{2}(30)'), '0.25');
      expect(answerOf(r'\sin^{2}(30)+\cos^{2}(30)'), '1');
      expect(answerOf(r'\tan^{2}(45)'), '1');
      // …and the inverse carve-out still stands.
      expect(answerOf(r'\sin^{-1}(0.5)'), '30');
    });

    test('per cent is per cent, not a remainder', () {
      // `%` was an infix modulo, so `20%3` silently answered 2 and the
      // palette's own per-cent button vetoed the whole line.
      expect(answerOf(r'25\%\times80'), '20');
      expect(answerOf(r'50\%'), '0.5');
      expect(answerOf(r'80\times25\%'), '20');
    });
  });

  group('typing that used to destroy the working', () {
    test('a factorial survives the = that follows it', () {
      // `!=` is the not-equals run, and it swallowed the `!` the student had
      // just typed: `20!` became `20≠`, their factorial deleted.
      final e = typedAnswer('5!');
      expect(e.latex, r'5!=\boxed{120}');
      expect(e.latex, isNot(contains('neq')));
    });

    test('but ≠ still works where a factorial cannot be', () {
      final e = MathEditor.empty();
      for (final ch in 'x!='.split('')) {
        e.insertChar(ch);
      }
      expect(e.latex, contains(r'\neq'),
          reason: 'after a letter there is nothing to take the factorial OF');
    });
  });

  group('answers big, small, and exactly what they say', () {
    test('a big answer is written as maths, not as programmer notation', () {
      // These were refused outright: the digits-only test threw them away,
      // so `20!` produced no answer at all.
      final e = typedAnswer('20!');
      expect(e.latex, contains(r'\times'));
      expect(e.latex, contains(r'{10}^{18}'));
      expect(e.latex, isNot(contains('e+')),
          reason: '6.02e+23 is programmer notation and a student reads '
              'straight past it');
    });

    test('a tiny one keeps its sign on the exponent', () {
      final e = MathEditor.empty()..insertSource(r'1.5\times10^{-3}');
      e.placeAtEnd();
      e.insertChar('=');
      e.insertChar(' ');
      expect(e.latex, contains('0.0015'));
    });

    test('the toggle never changes the value, only the form', () {
      // `rationalOf` accepts anything within 1e-9, which turned a decimal
      // typed as 0.6666666667 into 2/3 — and clicking back gave
      // 0.666666666667, a different number with no way back to the first.
      //
      // At ten significant figures those two ARE the same number, so the
      // fraction is now offered and the promise is kept the other way round:
      // there and back is exactly where you started. The stated invariant is
      // the round trip, not the refusal.
      final e = typedAnswer('0.6666666667*1');
      final a = e.root.children.whereType<MAnswer>().first;
      final before = e.latex;
      expect(e.toggleAnswer(a), isTrue);
      expect(e.latex, isNot(before), reason: 'it did change form');
      expect(e.toggleAnswer(a), isTrue);
      expect(e.latex, before,
          reason: 'and back to exactly the digits the student had');
    });

    test('...and a decimal no fraction can say is left alone', () {
      // Pi to ten figures is not 103993/33102 to ten figures, so there is
      // nothing honest to offer and nothing is offered.
      final e = MathEditor.empty()..insertSource(r'\pi');
      e.placeAtEnd();
      e.insertChar('=');
      e.insertChar(' ');
      final a = e.root.children.whereType<MAnswer>().first;
      final before = e.latex;
      expect(e.toggleAnswer(a), isFalse);
      expect(e.latex, before);
    });

    test('…and a real fraction still switches both ways', () {
      final e = typedAnswer('1/2');
      final a = e.root.children.whereType<MAnswer>().first;
      expect(e.toggleAnswer(a), isTrue);
      expect(e.latex, contains(r'\boxed{0.5}'));
      expect(e.toggleAnswer(a), isTrue);
      expect(e.latex, contains(r'\boxed{\frac{1}{2}}'));
    });
  });
}
