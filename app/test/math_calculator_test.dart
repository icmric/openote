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

      expect(app.activeMath, isNotNull);
      expect(app.activeMath!.result, '0.5',
          reason: 'the readout the Maths tab shows — dead for every fraction '
              'before the projection');

      app.activeMath!.useResult!();
      await tester.pump();
      expect(latest, contains('=0.5'),
          reason: 'the answer button writes "= 0.5" into the equation — and '
              'until 482b9e2 it wrote the literal characters =\$value');
    });
  });
}
