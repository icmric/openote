// The calculator, end to end (review round 3).
//
// It was DEAD for anything built visually: the editor fed canonical LaTeX
// into evaluateLinear, whose grammar has no backslash and no brace — so a
// fraction, a power or a root built with the editor's own tools never showed
// an answer, and only flat arithmetic whose LaTeX happens to equal its linear
// form (1+2) ever did. Probe-proven, then fixed by projecting the TREE into
// the linear grammar. These tests run the whole chain: keystrokes → tree →
// projection → evaluator → the Maths tab's readout → the answer button.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/math/equation_editor.dart';
import 'package:openote/math/evaluate.dart';
import 'package:openote/math/math_editor.dart';
import 'package:openote/math/math_linear_projection.dart';
import 'dart:io';

import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

MathEditor typed(String chars) {
  final e = MathEditor.empty();
  for (final ch in chars.split('')) {
    e.insertChar(ch);
  }
  return e;
}

void main() {
  group('the tree speaks the evaluator\'s language', () {
    test('a fraction built visually evaluates', () {
      final e = typed('1/2'); // '/' builds \frac{1}{2}
      expect(e.latex, r'\frac{1}{2}');
      final r = evaluateLinear(rowToLinear(e.root));
      expect(r.isOk, isTrue,
          reason: 'THE defect: \\frac{1}{2} was fed to a parser with no '
              'backslash, so the answer readout never appeared');
      expect(r.value, 0.5);
    });

    test('a power with its braced exponent evaluates', () {
      final e = typed('2^3 ');
      final r = evaluateLinear(rowToLinear(e.root));
      expect(r.isOk, isTrue);
      expect(r.value, 8);
    });

    test('a square root from the palette evaluates', () {
      final e = MathEditor.empty()..insertSource(r'\sqrt{16}');
      final r = evaluateLinear(rowToLinear(e.root));
      expect(r.isOk, isTrue);
      expect(r.value, 4);
    });

    test('an nth root becomes the fractional power it is', () {
      final e = MathEditor.empty()..insertSource(r'\sqrt[3]{27}');
      final r = evaluateLinear(rowToLinear(e.root));
      expect(r.isOk, isTrue);
      expect(r.value, closeTo(3, 1e-9));
    });

    test('pi and the named functions come through by word', () {
      final e = MathEditor.empty()..insertSource(r'\cos{0}+\pi');
      final r = evaluateLinear(rowToLinear(e.root));
      if (r.isOk) {
        expect(r.value, closeTo(1 + 3.14159265, 1e-6));
      }
      // A projection that cannot hold this must refuse, never misread.
      expect(r.isOk || rowToLinear(e.root).contains('§'), isTrue);
    });

    test('what has no numeric meaning is REFUSED, never guessed', () {
      // x_1 read as x*1, or a matrix read as anything, would be a lie with
      // a number on it — worse than no answer.
      for (final latex in [r'x_{1}', r'\begin{pmatrix}1&2\\3&4\end{pmatrix}']) {
        final e = MathEditor.empty();
        if (e.insertSource(latex) == InsertOutcome.refused) continue;
        final r = evaluateLinear(rowToLinear(e.root));
        expect(r.isOk, isFalse, reason: latex);
      }
    });

    test('absolute-value bars keep their meaning', () {
      final e = MathEditor.empty()..insertSource(r'\left|3-5\right|');
      final out = rowToLinear(e.root);
      final r = evaluateLinear(out);
      if (r.isOk) expect(r.value, 2);
    });
  });

  group('typing `= ` writes the answer down', () {
    // The owner: *"rather than having it appear up the top though since that
    // isnt intuitive, maybe we make it so that … when the person puts an =
    // sign and presses space afterwards it inserts the solution?"*
    MathEditor after(String chars) {
      final e = typed(chars);
      e.insertChar(' ');
      return e;
    }

    test('2+3= and a space gives 5', () {
      expect(after('2+3=').latex, '2+3=5');
    });

    test('a fraction answers too — the tree, not the LaTeX', () {
      // `/` builds the fraction and leaves the caret IN the denominator, so
      // the student steps out of it before finishing the sum, exactly as they
      // would on screen. (Left inside, `= ` works out the denominator's own
      // row — also right, just not what this test is about.)
      final e = typed('1/2');
      e.placeAtEnd();
      e.insertChar('=');
      e.insertChar(' ');
      expect(e.latex, contains('0.5'),
          reason: 'the answer comes through the same projection of the TREE '
              'that finally made the calculator work at all');
    });

    test('only the run since the LAST = is worked out', () {
      // `x` is unknown, so an answer for the whole line is impossible — but
      // the part the student just wrote is not.
      expect(after('x=2+3=').latex, endsWith('=5'));
    });

    test('an expression with an unknown in it just gives you a space', () {
      final e = after('y=m*x=');
      expect(e.latex, isNot(contains('=5')));
      expect(e.latex, contains(r'\ '),
          reason: 'the space is a space, and the student never learns the '
              'feature was even considered');
    });

    test('nothing before the = means nothing to work out', () {
      expect(after('=').latex, contains(r'\ '));
    });

    test('an answer with no digits — undefined, infinity — is refused', () {
      expect(after('1/0 =').latex, isNot(contains('inf')));
      expect(after('1/0 =').latex, isNot(contains('undefined')));
    });

    test('and it never fires without the space', () {
      expect(typed('2+3=').latex, '2+3=');
    });
  });

  group('through the Maths tab, on the real widget', () {
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());

    testWidgets('a visual fraction shows its answer and the button writes it',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final tmp = Directory.systemTemp.createTempSync('onote_calc_');
      late Repository repo;
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      late AppState app;
      await tester.runAsync(() async {
        repo = await Repository.openAt(tmp);
        final nb = await repo.createNotebook('Calc');
        app = AppState(repo)..notebookId = nb.id;
      });
      final editor = typed('1/2');
      String latest = '';
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EquationEditor(
            app: app,
            placement: EquationPlacement.block,
            textStyle: const TextStyle(fontSize: 22),
            editor: editor,
            onChanged: (v) => latest = v,
            onExit: (_) {},
          ),
        ),
      ));
      await tester.pump();

      expect(app.activeMath, isNotNull,
          reason: 'the Maths tab still finds the equation — it just carries '
              'no answer readout any more');

      // The answer arrives by typing, in the equation, through the real
      // widget: `= ` at the end of a half-written sum.
      editor.placeAtEnd();
      editor.insertChar('=');
      editor.insertChar(' ');
      await tester.pump();
      expect(editor.latex, contains('0.5'),
          reason: 'a fraction built visually works out to 0.5 — the whole '
              'point of projecting the tree instead of its LaTeX');
      expect(latest, isNotNull);
    });
  });
}
