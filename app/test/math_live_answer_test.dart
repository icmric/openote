// Answers follow the working, and degrees or radians is one click.
//
// The owner: *"Please make it update the value when i update the equation,
// but debounce it so its not doing lots of unnesesary updates"*, and *"Please
// also add a way to easily switch between degrees and radians."*
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/math/evaluate.dart';
import 'package:openote/math/math_editor.dart';
import 'package:openote/math/math_field.dart';
import 'package:openote/math/math_tree.dart';
import 'package:openote/ui/math_bar.dart';

MathEditor typed(String chars) {
  final e = MathEditor.empty();
  for (final ch in chars.split('')) {
    e.insertChar(ch);
  }
  return e;
}

MathEditor answered(String chars) {
  final e = typed(chars);
  e.placeAtEnd();
  e.insertChar('=');
  e.insertChar(' ');
  return e;
}

void main() {
  tearDown(() => mathAngleMode = AngleMode.degrees);

  group('an answer follows the working it belongs to', () {
    test('changing the sum changes the answer', () {
      final e = answered('2+3'); // 2+3=[5]
      expect(e.latex, r'2+3=\boxed{5}');
      // Edit the 3 into a 4: caret to just after it, backspace, type 4.
      e.placeAtStart();
      e.moveRight();
      e.moveRight();
      e.moveRight();
      e.backspace();
      e.insertChar('4');
      expect(e.refreshAnswers(), isTrue);
      expect(e.latex, r'2+4=\boxed{6}');
    });

    test('and it stays in the form the student chose', () {
      final e = answered('1/2');
      expect(e.latex, contains(r'\boxed{\frac{1}{2}}'));
      // Switch it to a decimal, then change the working.
      final a = e.root.children.whereType<MAnswer>().first;
      expect(e.toggleAnswer(a), isTrue);
      expect(e.latex, contains(r'\boxed{0.5}'));

      // Change the working — the 2 in the denominator becomes a 4. (The
      // working is what comes BEFORE the `=`; text typed after the answer is
      // not part of the sum, which is why the answer would not budge for it.)
      e.placeAt(1);
      expect(e.moveLeft(), isTrue); // into the fraction
      e.placeAt(1);
      final frac = e.root.children.first as MFrac;
      frac.den.children.clear();
      frac.den.add(MSym('4'));
      expect(e.refreshAnswers(), isTrue);
      expect(e.latex, contains(r'\boxed{0.25}'),
          reason: 'a decimal stays a decimal');
    });

    test('several answers in a line re-work left to right', () {
      final e = answered('2+3');
      e.placeAtEnd();
      e.insertChar('+');
      e.insertChar('1');
      e.insertChar('=');
      e.insertChar(' ');
      expect(e.latex, r'2+3=\boxed{5}+1=\boxed{6}');

      // Change the 2 into a 7: both answers must follow.
      e.placeAtStart();
      e.moveRight();
      e.backspace();
      e.insertChar('7');
      expect(e.refreshAnswers(), isTrue);
      expect(e.latex, r'7+3=\boxed{10}+1=\boxed{11}',
          reason: 'the second answer works out the FIRST answer plus one, so '
              'the first has to be right before the second is asked');
    });

    test('working that stops working out takes its answer with it', () {
      final e = answered('2+3');
      // Turn the 3 into an x — nothing can be worked out any more.
      e.placeAtStart();
      e.moveRight();
      e.moveRight();
      e.moveRight();
      e.backspace();
      e.insertChar('x');
      expect(e.refreshAnswers(), isTrue);
      expect(e.latex, isNot(contains('boxed')),
          reason: 'the box says the app worked this out; an answer it can no '
              'longer stand behind is a lie that looks exactly like a true '
              'one');
      expect(e.latex, '2+x=');
    });

    test('an answer with no = in front of it is left alone', () {
      // A paste, or an edit that took the `=` away. There is no working to
      // re-read, so nothing is touched.
      final e = MathEditor.empty()..insertSource(r'\boxed{5}');
      expect(e.refreshAnswers(), isFalse);
      expect(e.latex, r'\boxed{5}');
    });

    test('re-working an unchanged sum changes nothing at all', () {
      final e = answered('2+3');
      expect(e.refreshAnswers(), isFalse,
          reason: 'no edit, no commit — an undo step for nothing is how the '
              'redo stack got destroyed last time');
    });

    test('hasAnswers is false for an equation with none', () {
      expect(typed('2+3').hasAnswers, isFalse);
      expect(answered('2+3').hasAnswers, isTrue);
    });
  });

  group('the debounce', () {
    testWidgets('one re-work for a burst of typing, not one per key',
        (tester) async {
      final e = answered('2+3');
      var commits = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: MathField(
              editor: e,
              textStyle: const TextStyle(fontSize: 20),
              onChanged: (_) => commits++,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Type into the WORKING — after the 3, before the `=` — quickly, then
      // wait past the gap. (Characters typed after the answer are not part
      // of the sum, so they would rightly change nothing.)
      e.placeAt(3);
      for (final ch in ['0', '0']) {
        await tester.sendKeyDownEvent(
            ch == '+' ? LogicalKeyboardKey.equal : LogicalKeyboardKey(ch.codeUnitAt(0)),
            character: ch);
        await tester.sendKeyUpEvent(
            ch == '+' ? LogicalKeyboardKey.equal : LogicalKeyboardKey(ch.codeUnitAt(0)));
        await tester.pump(const Duration(milliseconds: 40));
      }
      final duringTyping = commits;
      expect(e.latex, contains(r'\boxed{5}'),
          reason: 'mid-burst the old answer is still standing — nothing has '
              'flickered');

      await tester.pump(const Duration(milliseconds: 500));
      expect(e.latex, contains(r'\boxed{302}'),
          reason: 'and once the typing stops, the answer catches up: '
              '2+300 is 302');
      expect(commits, duringTyping + 1,
          reason: 'exactly ONE extra commit for the whole burst');
      await tester.pumpAndSettle();
    });

    testWidgets('an equation with no answer arms no timer', (tester) async {
      // Nothing to re-work means nothing to wake up for; a pending timer
      // would also fail the test binding, which is a useful second check.
      final e = typed('2+3');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: MathField(
              editor: e,
              textStyle: const TextStyle(fontSize: 20),
              onChanged: (_) {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.digit7, character: '7');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.digit7);
      await tester.pump();
      // No pending timer to flush: pumpAndSettle would hang on one.
      await tester.pumpAndSettle();
      expect(e.latex, '2+37');
    });
  });

  group('degrees or radians, in one click', () {
    test('the mode decides', () {
      mathAngleMode = AngleMode.degrees;
      expect(evaluateLinear('sin(30)').value, closeTo(0.5, 1e-12));
      mathAngleMode = AngleMode.radians;
      expect(evaluateLinear('sin(30)').value, closeTo(-0.988031624, 1e-9));
      expect(evaluateLinear('sin(pi/6)').value, closeTo(0.5, 1e-12),
          reason: 'radians are radians either way');
    });

    test('a degree sign still forces degrees, in either mode', () {
      for (final m in AngleMode.values) {
        mathAngleMode = m;
        expect(evaluateLinear('sin(30°)').value, closeTo(0.5, 1e-12),
            reason: '$m');
      }
    });

    test('the inverses answer in the mode they are in', () {
      mathAngleMode = AngleMode.degrees;
      expect(evaluateLinear('asin(0.5)').value, closeTo(30, 1e-9));
      mathAngleMode = AngleMode.radians;
      expect(evaluateLinear('asin(0.5)').value, closeTo(0.5235987, 1e-6),
          reason: 'radians in, radians out');
    });

    testWidgets('the switch is on the bar, and says which mode you are IN',
        (tester) async {
      tester.view.physicalSize = const Size(2600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      var toggled = 0;
      Future<void> pump(AngleMode mode) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: MathBar(
                onInsert: (_) {},
                latexMode: false,
                onToggleLatex: () {},
                angleMode: mode,
                onToggleAngleMode: () => toggled++,
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
      }

      await pump(AngleMode.degrees);
      expect(find.text('DEG'), findsOneWidget);
      expect(find.text('RAD'), findsNothing,
          reason: 'a button labelled with its own opposite is a coin flip '
              'every time');
      await tester.tap(find.text('DEG'));
      expect(toggled, 1);

      await pump(AngleMode.radians);
      expect(find.text('RAD'), findsOneWidget);
    });

    testWidgets('and the row still fits the smallest window', (tester) async {
      tester.view.physicalSize = const Size(2600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: MathBar(
              onInsert: (_) {},
              latexMode: false,
              onToggleLatex: () {},
              angleMode: AngleMode.degrees,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final w = tester.getSize(find.byType(MathBar)).width;
      // See math_toolbar_test.dart for where the headroom went: Graph moved
      // out of the fold and onto the row.
      expect(w, lessThan(1240),
          reason: 'measured $w px; the row has to fit the smallest window '
              'the app opens, which is 1280');
    });
  });
}
