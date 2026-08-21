// What an answer says about itself: its unit, and how many figures.
//
// The owner, after testing: *"given it can change though it would be good to
// denote if it is degrees or radians (and give units when it could only be
// that unit, like with deg/rad. Would also like to be able to right click on
// an answer and choose number of significant figures, dec/frac mode, all
// those little things."*
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/math/evaluate.dart';
import 'package:openote/math/math_editor.dart';
import 'package:openote/math/math_tree.dart';

MathEditor worked(String latex) {
  final e = MathEditor.empty();
  e.insertSource(latex);
  e.placeAtEnd();
  e.insertChar('=');
  e.insertChar(' ');
  return e;
}

MAnswer answerIn(MathEditor e) => e.root.children.whereType<MAnswer>().first;

void main() {
  tearDown(() => mathAngleMode = AngleMode.degrees);

  group('an answer says what it is, when it can only be one thing', () {
    test('an angle in degrees wears the degree sign', () {
      mathAngleMode = AngleMode.degrees;
      final e = worked(r'\sin^{-1}(0.5)');
      expect(e.latex, endsWith(r'=\boxed{30{}^{\circ}}'),
          reason: 'sin inverse of a half is thirty DEGREES, and thirty on '
              'its own is the same answer as 0.5236 with nothing to say '
              'which');
    });

    test('and in radians it is a bare number, because that is what a radian '
        'is', () {
      mathAngleMode = AngleMode.radians;
      final e = worked(r'\sin^{-1}(0.5)');
      expect(e.latex, contains(r'\boxed{0.5235987756}'));
      expect(e.latex, isNot(contains('circ')),
          reason: 'a bare number IS radians, on every calculator and in every '
              'textbook — the ring being absent is what says so');
    });

    test('a ratio wears nothing at all', () {
      // sin 30 is a half. Half of nothing in particular.
      expect(worked(r'\sin(30)').latex, endsWith(r'=\boxed{0.5}'));
      expect(worked('2+3').latex, endsWith(r'=\boxed{5}'));
    });

    test('an angle with arithmetic done to it is no longer an angle', () {
      // `asin(0.5)+1` is 31, and 31 of what is a guess. The app does not
      // guess.
      final e = worked(r'\sin^{-1}(0.5)+1');
      expect(e.latex, endsWith(r'=\boxed{31}'));
      expect(e.latex, isNot(contains('circ')));
    });

    test('the degree sign travels with the number, so it still works out', () {
      // The answer above, reused: sin of it must still be a half, in either
      // mode, because the ring says degrees whatever the mode is.
      for (final m in AngleMode.values) {
        mathAngleMode = m;
        final e = MathEditor.empty()..insertSource(r'\sin(30{}^{\circ})');
        e.placeAtEnd();
        e.insertChar('=');
        e.insertChar(' ');
        expect(e.latex, endsWith(r'=\boxed{0.5}'), reason: '\$m');
      }
    });
  });

  group('significant figures', () {
    test('ten by default, the way a school calculator shows it', () {
      expect(worked(r'\cos(45)').latex, endsWith(r'=\boxed{0.7071067812}'),
          reason: 'it used to be twelve, which is enough to leak the '
              'floating point: 0.707106781187');
      expect(evaluateLinear('1/3').display, '0.3333333333');
    });

    test('a whole number stays whole', () {
      expect(worked('2*3').latex, endsWith(r'=\boxed{6}'));
      expect(worked('10/2').latex, endsWith(r'=\boxed{5}'));
    });

    test('choosing three figures pads with the zeros that say so', () {
      final e = worked('1/2');
      final a = answerIn(e);
      expect(e.setAnswerForm(a, fraction: false), isTrue);
      expect(e.setAnswerSigFigs(a, 3), isTrue);
      expect(e.latex, endsWith(r'=\boxed{0.500}'),
          reason: 'three figures is 0.500 — the zeros ARE the setting');
    });

    test('and the zeros are read back as the setting', () {
      expect(MathEditor.sigFigsOf('0.500'), 3);
      expect(MathEditor.sigFigsOf('0.5'), 1);
      expect(MathEditor.sigFigsOf('0.0500'), 3);
      expect(MathEditor.sigFigsOf('12.30'), 4);
      expect(MathEditor.sigFigsOf('1230'), 3,
          reason: 'a whole number keeps the modest reading');
      expect(MathEditor.sigFigsOf('0'), 1);
      expect(MathEditor.sigFigsOf('-0.250'), 3);
    });

    test('the choice survives the working changing under it', () {
      final e = worked(r'\cos(45)');
      final a = answerIn(e);
      e.setAnswerSigFigs(a, 3);
      expect(e.latex, contains(r'\boxed{0.707}'));
      // Now change the working: cos 45 becomes cos 60.
      e.placeAt(0);
      // Rewrite the argument the way a student would: caret after the 5,
      // two backspaces, type 60.
      e.placeAt(4);
      e.backspace();
      e.backspace();
      e.insertChar('6');
      e.insertChar('0');
      expect(e.refreshAnswers(), isTrue);
      expect(e.latex, contains(r'\boxed{0.500}'),
          reason: 'still three figures — the student asked once');
    });

    test('and survives a save and a reopen, with nothing stored but digits',
        () {
      final e = worked(r'\cos(45)');
      e.setAnswerSigFigs(answerIn(e), 3);
      final saved = e.latex;
      expect(saved, contains('0.707'));
      final reopened = MathEditor.open(saved);
      expect(reopened, isNotNull);
      expect(reopened!.latex, saved, reason: 'the round trip is exact');
      expect(reopened.refreshAnswers(), isFalse,
          reason: 'nothing has changed, so nothing is rewritten — and the '
              'three figures are read straight off the digits');
    });
  });

  group('the little things an answer can be asked to do', () {
    test('decimal and fraction are set, not just flipped', () {
      final e = worked('1/2');
      final a = answerIn(e);
      expect(e.answerIsFraction(a), isTrue);
      expect(e.setAnswerForm(a, fraction: true), isFalse,
          reason: 'already a fraction — nothing to do, and no undo step');
      expect(e.setAnswerForm(a, fraction: false), isTrue);
      expect(e.latex, contains(r'\boxed{0.5}'));
    });

    test('a whole number is not offered a fraction', () {
      final e = worked('2+3');
      expect(e.answerHasFraction(answerIn(e)), isFalse);
    });

    test('the fraction comes from the WORKING, not from the rounded digits',
        () {
      // A third shown to three figures is 0.333, and 333/1000 is not a third.
      final e = worked('1/3');
      final a = answerIn(e);
      e.setAnswerForm(a, fraction: false);
      e.setAnswerSigFigs(a, 3);
      expect(e.latex, contains('0.333'));
      expect(e.setAnswerForm(a, fraction: true), isTrue);
      expect(e.latex, contains(r'\frac{1}{3}'),
          reason: 'a third, not 333 over a thousand');
    });

    test('recalculating is what to press after switching degrees to radians',
        () {
      mathAngleMode = AngleMode.degrees;
      final e = worked(r'\sin(30)');
      expect(e.latex, contains(r'\boxed{0.5}'));
      mathAngleMode = AngleMode.radians;
      expect(e.latex, contains(r'\boxed{0.5}'),
          reason: 'nothing on the page changes on its own — the owner asked '
              'for exactly that');
      expect(e.recalculateAnswer(answerIn(e)), isTrue);
      expect(e.latex, contains(r'\boxed{-0.9880316241}'));
    });

    test('removing an answer keeps the working', () {
      final e = worked('2+3');
      expect(e.removeAnswer(answerIn(e)), isTrue);
      expect(e.latex, '2+3=');
      expect(e.root.children.whereType<MAnswer>(), isEmpty);
    });
  });
}
