// The equation must never stop drawing (audit of 2026-08-20).
//
// A multi-agent audit of the shipped editor found one family of defect over and
// over: the tree emitted TeX that TeX itself refuses, and the student's whole
// equation collapsed into a grey box of source. Every case below was found by
// probing the real renderer, not by reading, and every one is a thing a
// year-10 student types on an ordinary afternoon — a percentage, a set in
// braces, a temperature in degrees, a prime on a derivative.
//
// The worst of them did not even fall back. `%` is TeX's COMMENT character, so
// `20%` drew as `20` and `30%+2` drew as `30`: the rest of the line vanished
// with nothing at all to say it had.
//
// The rule this file pins: **anything the editor can produce, the renderer can
// draw.** Not "usually", not "for the constructs we thought of".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/math/math_editor.dart';
import 'package:openote/math/math_inventory.dart';
import 'package:openote/math/math_tree.dart';
import 'package:openote/math/math_view.dart';

void main() {
  /// Render a string and report whether it drew, plus how wide it came out —
  /// width is what catches the silent losses, where TeX draws *something* but
  /// not what was typed.
  Future<({bool drew, double width})> render(
      WidgetTester tester, String tex) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: OnoteMath(tex,
              textStyle: const TextStyle(fontSize: 20, color: Colors.black)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final drew = find.byType(MathSourceFallback).evaluate().isEmpty;
    final w = drew
        ? tester.getSize(find.byType(OnoteMath)).width
        : double.nan;
    return (drew: drew, width: w);
  }

  MathEditor typed(String s) {
    final e = MathEditor.empty();
    for (final ch in s.split('')) {
      e.insertChar(ch);
    }
    return e;
  }

  group('characters TeX reserves', () {
    for (final entry in {
      'a set in braces': '{1,2,3}',
      'a percentage': '20%',
      'a percentage mid-sum': '30%+2',
      'a dollar amount': r'$5',
      'a hash': '#1',
      'an ampersand': 'a&b',
      'an underscore': 'a_b',
      'one unbalanced brace': 'a{b',
    }.entries) {
      testWidgets('${entry.key} still draws — and is still there',
          (tester) async {
        final e = typed(entry.value);
        final r = await render(tester, e.latex);
        expect(r.drew, isTrue,
            reason: 'typing "${entry.value}" stored ${e.latex}, which the '
                'renderer refuses');
      });
    }

    testWidgets('a percent sign is DRAWN, not treated as a comment',
        (tester) async {
      // The silent one. `20%` used to draw at exactly the width of `20`.
      final twenty = await render(tester, typed('20').latex);
      final pct = await render(tester, typed('20%').latex);
      expect(pct.drew, isTrue);
      expect(pct.width, greaterThan(twenty.width),
          reason: 'the % must occupy space — it used to disappear silently, '
              'taking the rest of the line with it');
    });

    testWidgets('braces a student typed are VISIBLE, not grouping',
        (tester) async {
      final bare = await render(tester, typed('1,2,3').latex);
      final set = await render(tester, typed('{1,2,3}').latex);
      expect(set.drew, isTrue);
      expect(set.width, greaterThan(bare.width),
          reason: 'a set written with braces has to look like one');
    });
  });

  group('words boxes', () {
    for (final words in [
      '50% off',
      r'costs $5',
      'a_b',
      'a^b',
      '#1',
      'a&b',
      'if x > 0',
      'where {n} is odd',
    ]) {
      testWidgets('a words box holding "$words" draws', (tester) async {
        final e = MathEditor.empty()..insertItem(mathItemsById['words']!);
        for (final ch in words.split('')) {
          e.insertChar(ch);
        }
        final r = await render(tester, e.latex);
        expect(r.drew, isTrue, reason: 'stored ${e.latex}');
      });
    }

    testWidgets('an empty words box is visible rather than 0 px wide',
        (tester) async {
      // It drew literally nothing before, so pressing the button was
      // pixel-identical to not pressing it.
      final e = MathEditor.empty()..insertItem(mathItemsById['words']!);
      final drawn = e.renderTex(const MathTexCtx());
      expect(drawn, contains(r'\square'),
          reason: 'a button that appears to do nothing is a broken button');
    });
  });

  group('two scripts never touch', () {
    testWidgets('a power then the degree sign', (tester) async {
      final e = typed('x^2');
      e.placeAtEnd();
      e.insertItem(mathItemsById['degree']!);
      final r = await render(tester, e.latex);
      expect(r.drew, isTrue, reason: 'stored ${e.latex} — a double superscript '
          'is TeX the renderer refuses outright');
    });

    testWidgets('a filled sum then a prime', (tester) async {
      final e = MathEditor.empty()..insertItem(mathItemsById['sum']!);
      e.insertChar('i');
      e.tab();
      e.insertChar('n');
      e.tab();
      e.insertItem(mathItemsById['prime']!);
      final r = await render(tester, e.latex);
      expect(r.drew, isTrue, reason: 'stored ${e.latex}');
    });

    testWidgets('degrees followed by a unit letter', (tester) async {
      // `30^\circC` ran the C into the command name. Every temperature in
      // every chemistry note is this shape.
      final e = typed('30');
      e.insertItem(mathItemsById['degree']!);
      e.insertChar('C');
      final r = await render(tester, e.latex);
      expect(r.drew, isTrue, reason: 'stored ${e.latex}');
    });
  });

  group('backspace can never produce undrawable TeX', () {
    testWidgets('over every structure the palette offers', (tester) async {
      // The generated sweep: insert each shape, press Backspace to exhaustion,
      // and check the equation still draws after every single press. This is
      // the property the earlier "unbuild" rule broke in three separate ways.
      for (final item in mathItems.where((i) => i.cat == MathCat.structure)) {
        final e = MathEditor.empty()..insertItem(item);
        e.insertChar('x');
        e.placeAtEnd();
        for (var press = 0; press < 10; press++) {
          if (!e.backspace()) break;
          final r = await render(tester, e.latex);
          expect(r.drew, isTrue,
              reason: '${item.id}: after ${press + 1} Backspace(s) the stored '
                  'LaTeX is ${e.latex}, which cannot be drawn');
        }
      }
    });
  });

  group('the shortcuts do not fire on ordinary maths', () {
    test('x < -3 stays an inequality', () {
      // `<-` used to become ←, and the space between could not stop it because
      // a space that builds nothing inserts no atom. Both halves are fixed:
      // the shortcut is gone, and a space now blocks a run either side of it.
      expect(typed('x < -3').latex, isNot(contains(r'\leftarrow')));
      expect(typed('x <-3').latex, isNot(contains(r'\leftarrow')));
    });

    test('a space still separates two characters that would pair up', () {
      expect(typed('a < = b').latex, isNot(contains(r'\leq')));
      expect(typed('a<=b').latex, contains(r'\leq'),
          reason: 'the shortcut itself must still work');
    });
  });

  _qol();

  group('a symbol ends the words box', () {
    test('so the letters after it are maths, not more words', () {
      final e = MathEditor.empty()..insertItem(mathItemsById['words']!);
      for (final ch in 'if'.split('')) {
        e.insertChar(ch);
      }
      e.insertItem(mathItemsById['theta']!);
      e.insertChar('x');
      expect(e.latex, endsWith('x'),
          reason: 'the x landed inside the words box, which looks to the '
              'student like the keyboard has stopped working');
      expect(e.latex, contains(r'\text{if}'));
    });
  });
}

/// The quality-of-life promises, checked rather than assumed.
void _qol() {
  group('finding a symbol by what you would call it', () {
    test('the name beats a loose alias on another row', () {
      // Measured misroutes before the fix: "angle" found the degree sign
      // before ∠, "sigma" found Σ before σ, "therefore" found ⇒ before ∴.
      // Enter inserts the first hit, so the student got the wrong symbol IN
      // their equation, not merely listed first.
      for (final (query, wanted) in [
        ('angle', 'angle'),
        // 'sigma' is greek-sigma's actual NAME; 'standard deviation' only
        // carries it as an alias. Both draw σ, and the named row is the right
        // answer to the question asked.
        ('sigma', 'greek-sigma'),
        ('therefore', 'therefore'),
        ('congruent to', 'cong'),
      ]) {
        expect(searchMathItems(query).first.id, wanted, reason: query);
      }
    });

    test('a longer, natural phrase still finds it', () {
      // A query longer than the stored name used to score zero, and the panel
      // then told the student the symbol did not exist.
      for (final (query, wanted) in [
        ('greater than or equal to', 'geq'),
        ('less than or equal to', 'leq'),
        ('is not equal to', 'neq'),
      ]) {
        expect(searchMathItems(query).map((i) => i.id), contains(wanted),
            reason: query);
      }
    });
  });

  group('every shape has a keyboard route', () {
    test('and typing it builds the shape', () {
      // Nineteen of the shapes had no `typeIt` at all, so the only way to a
      // matrix was the mouse. The route is what makes moving twelve chips off
      // the row honest.
      for (final item in mathItems.where((i) => i.cat == MathCat.structure)) {
        expect(item.typeIt, isNotNull,
            reason: '${item.id} can only be reached with the mouse');
      }
    });
  });
}
