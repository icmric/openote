// The menu an answer carries (owner, v0.23).
//
// *"Would also like to be able to right click on an answer and choose number
// of significant figures, dec/frac mode, all those little things."*
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/math/answer_menu.dart';
import 'package:openote/math/evaluate.dart';
import 'package:openote/math/math_editor.dart';
import 'package:openote/math/math_field.dart';
import 'package:openote/math/math_tree.dart';
import 'package:openote/math/math_view.dart';

MathEditor worked(String chars) {
  final e = MathEditor.empty();
  for (final ch in chars.split('')) {
    e.insertChar(ch);
  }
  e.placeAtEnd();
  e.insertChar('=');
  e.insertChar(' ');
  return e;
}

void main() {
  tearDown(() => mathAngleMode = AngleMode.degrees);

  var commits = 0;

  Future<void> pump(WidgetTester tester, MathEditor e) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    commits = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: MathField(
            editor: e,
            textStyle: const TextStyle(fontSize: 22),
            onChanged: (_) => commits++,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Right-click the last few pixels of the equation, which is where the
  /// answer sits.
  Future<void> rightClickAnswer(WidgetTester tester) async {
    final r = tester.getRect(find.byType(MathField));
    final g = await tester.startGesture(
        Offset(r.right - 8, r.center.dy),
        buttons: kSecondaryButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await g.up();
    await tester.pumpAndSettle();
  }

  testWidgets('right-clicking an answer offers the two ways of writing it',
      (tester) async {
    final e = worked('1/2');
    expect(e.latex, contains(r'\boxed{\frac{1}{2}}'));
    await pump(tester, e);
    await rightClickAnswer(tester);

    // Two form rows, each drawn as the number itself rather than named.
    expect(find.byKey(const ValueKey('answer-decimal')), findsOneWidget);
    expect(find.byKey(const ValueKey('answer-fraction')), findsOneWidget);
    expect(find.text('Work it out again'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('answer-decimal')));
    await tester.pumpAndSettle();
    expect(e.latex, contains(r'\boxed{0.5}'));
    expect(commits, 1, reason: 'one change, one commit');
  });

  testWidgets('a whole number is offered no fraction and no figures',
      (tester) async {
    final e = worked('2+3');
    await pump(tester, e);
    await rightClickAnswer(tester);
    expect(find.byKey(const ValueKey('answer-fraction')), findsNothing,
        reason: 'five has no fraction worth showing');
    expect(find.byKey(const ValueKey('answer-decimal')), findsOneWidget);
    expect(find.text('Figures'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(e.latex, '2+3=');
  });

  testWidgets('the figures chips set the precision, and say which is on',
      (tester) async {
    final e = worked('2/3');
    // Start from the decimal so the figures row is there.
    final a = e.root.children.whereType<MAnswer>().first;
    e.setAnswerForm(a, fraction: false);
    await pump(tester, e);
    await rightClickAnswer(tester);

    expect(find.text('Auto'), findsOneWidget);
    for (final f in ['3', '4', '5', '6', '10']) {
      expect(find.text(f), findsWidgets, reason: 'chip \$f');
    }
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    expect(e.latex, contains(r'\boxed{0.667}'));
    expect(commits, 1);

    // And re-opening ticks the one that is on.
    await rightClickAnswer(tester);
    expect(e.answerSigFigs(a), 3);
    await tester.tap(find.text('Auto'));
    await tester.pumpAndSettle();
    expect(e.latex, contains(r'\boxed{0.6666666667}'));
  });

  testWidgets('the mode is named only when the answer depends on it',
      (tester) async {
    final plain = worked('2+3');
    await pump(tester, plain);
    await rightClickAnswer(tester);
    expect(find.text('DEG'), findsNothing,
        reason: 'two plus three is two plus three in any mode, and a label '
            'that is usually meaningless is worse than none');
    await tester.tapAt(const Offset(1200, 700)); // dismiss
    await tester.pumpAndSettle();

    final trig = MathEditor.empty()..insertSource(r'\sin(30)');
    trig.placeAtEnd();
    trig.insertChar('=');
    trig.insertChar(' ');
    await pump(tester, trig);
    await rightClickAnswer(tester);
    expect(find.text('DEG'), findsOneWidget);
    await tester.tap(find.text('Work it out again'));
    await tester.pumpAndSettle();
    expect(trig.latex, contains(r'\boxed{0.5}'),
        reason: 'nothing changed, so nothing changed');
  });

  testWidgets('working it out again is how a mode switch reaches an old '
      'answer', (tester) async {
    mathAngleMode = AngleMode.degrees;
    final e = MathEditor.empty()..insertSource(r'\cos(60)');
    e.placeAtEnd();
    e.insertChar('=');
    e.insertChar(' ');
    expect(e.latex, contains(r'\boxed{0.5}'));
    mathAngleMode = AngleMode.radians;
    await pump(tester, e);
    await rightClickAnswer(tester);
    expect(find.text('RAD'), findsOneWidget,
        reason: 'the row names the mode it would use');
    await tester.tap(find.text('Work it out again'));
    await tester.pumpAndSettle();
    expect(e.latex, contains(r'\boxed{-0.9524129804}'));
    expect(commits, 1);
  });

  testWidgets('right-clicking anywhere else does nothing at all',
      (tester) async {
    final e = worked('2+3');
    await pump(tester, e);
    final r = tester.getRect(find.byType(MathField));
    final g = await tester.startGesture(
        Offset(r.left + 4, r.center.dy),
        buttons: kSecondaryButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await g.up();
    await tester.pumpAndSettle();
    expect(find.text('Work it out again'), findsNothing);
    expect(e.latex, r'2+3=\boxed{5}', reason: 'and the caret was not moved');
    expect(commits, 0);
  });

  test('the figure choices are the ones a student is asked for', () {
    expect(kAnswerFigureChoices, [null, 3, 4, 5, 6, 10]);
  });

  testWidgets('the equation keeps the keyboard after the menu closes',
      (tester) async {
    final e = worked('2+3');
    await pump(tester, e);
    await rightClickAnswer(tester);
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    // The proof is behavioural: the next keystroke lands in the equation.
    expect(find.byType(OnoteMath), findsWidgets);
  });

  group('a menu verb on an answer that is no longer there', () {
    // The tree can move under an open menu: the 400ms recheck removes an
    // answer whose working stopped working out. Three of the four verbs
    // already declined in that state; the fourth rewrote a node that was not
    // in the equation any more and reported success, so the host redrew for
    // an edit that never happened.
    MathEditor withAnswer() {
      final e = MathEditor.empty()..insertSource('2+3');
      e.placeAtEnd();
      e.insertChar('=');
      e.insertChar(' ');
      return e;
    }

    test('setting the figures declines', () {
      final e = withAnswer();
      final a = e.root.children.whereType<MAnswer>().first;
      e.removeAnswer(a);
      expect(e.setAnswerSigFigs(a, 3), isFalse);
    });

    test('and so do the other three', () {
      final e = withAnswer();
      final a = e.root.children.whereType<MAnswer>().first;
      e.removeAnswer(a);
      expect(e.setAnswerForm(a, fraction: true), isFalse);
      expect(e.recalculateAnswer(a), isFalse);
      expect(e.removeAnswer(a), isFalse);
    });
  });

  group('an answer with no working in front of it', () {
    test('its degree sign is a label, not an instruction', () {
      // `30°` handed straight to the evaluator comes back 0.5235987756 — the
      // ring read as "turn this into radians". An answer pasted on its own
      // was worth 0.524 the moment its menu was touched.
      mathAngleMode = AngleMode.degrees;
      final e = MathEditor.open(r'\boxed{30{}^{\circ}}')!;
      final a = e.root.children.whereType<MAnswer>().first;
      expect(e.setAnswerSigFigs(a, 3), isTrue);
      expect(e.latex, r'\boxed{30.0{}^{\circ}}');
    });
  });

}
