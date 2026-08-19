// The visual maths editor's engine (plan: docs/planning/v0.18-visual-maths.md).
//
// These are the promises the editor makes to a student who has never heard of
// LaTeX: type `1/2` and it becomes a fraction; press Backspace and it comes
// back as characters; Tab walks the boxes left to fill. The rendering half is
// `math_inventory_test.dart`; this is the behaviour half.
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/math/math_editor.dart';
import 'package:openote/math/math_inventory.dart';
import 'package:openote/math/math_parse.dart';
import 'package:openote/math/math_tree.dart';

/// Type a string one character at a time, exactly as a keyboard delivers it.
MathEditor type(String s, {MathEditor? into}) {
  final e = into ?? MathEditor.empty();
  for (final ch in s.split('')) {
    e.insertChar(ch);
  }
  return e;
}

void main() {
  group('building up as you type', () {
    test('1/2 becomes a fraction', () {
      expect(type('1/2').latex, r'\frac{1}{2}');
    });

    test('the whole number goes on top, not just its last digit', () {
      // `12/5` is the first thing that breaks a naive "take one character"
      // rule — it would build 1·(2/5).
      expect(type('12/5').latex, r'\frac{12}{5}');
    });

    test('brackets group the numerator and then get out of the way', () {
      // A student types the brackets to say what belongs on top. Keeping them
      // afterwards is what makes a typed fraction look unlike a palette one.
      expect(type('(n+1)/2').latex, r'\frac{n+1}{2}');
    });

    test('x^2 raises only the x', () {
      expect(type('x^2').latex, r'{x}^{2}');
    });

    test('a power and an index land on the same letter', () {
      expect(type('x_i^2').latex, r'{x}_{i}^{2}');
    });

    test('a control word becomes its symbol on space', () {
      expect(type('alpha ').latex, r'\alpha ');
    });

    test('an operator ends a control word too, without a space', () {
      // "pi+1" — nobody types a space before the plus.
      expect(type('pi+1').latex, r'\pi +1');
    });

    test('<= becomes one symbol the moment it is complete', () {
      expect(type('a<=b').latex, r'a\leq b');
    });

    test('-> becomes an arrow', () {
      expect(type('x->0').latex, r'x\to 0');
    });

    test('sqrt opens a root with the caret under the sign', () {
      final e = type('sqrt ');
      expect(e.latex, r'\sqrt{}');
      expect(e.caretRow.owner, isA<MSqrt>());
      expect(e.caretRow.name, 'radicand');
      e.insertChar('9');
      expect(e.latex, r'\sqrt{9}');
    });

    test('sum opens with the caret in the lower limit', () {
      final e = type('sum ');
      expect(e.caretRow.name, 'sub');
      type('n=1', into: e);
      expect(e.latex, contains(r'\sum'));
      expect(e.latex, contains('n=1'));
    });

    test('a function name goes upright when the bracket arrives', () {
      final e = type('sin(x');
      expect(e.latex, startsWith(r'\sin '));
      expect(e.latex, contains(r'\left( x'));
    });

    test('typing a bracket opens a grower and the closing one leaves it', () {
      final e = type('(x+1)');
      expect(e.latex, r'\left( x+1\right) ');
      // The caret is outside the brackets, so what follows is not inside them.
      e.insertChar('y');
      expect(e.latex, endsWith('y'));
    });

    test('an unfinished construct is just characters, never an error', () {
      // Math Input Spec §3.3: typing is never blocked.
      expect(type('3x+').latex, '3x+');
    });
  });

  group('backspace never eats what was typed', () {
    test('a fraction unbuilds into the characters that rebuild it', () {
      final e = type('1/2');
      e.moveRight(); // out of the denominator, to the right of the fraction
      expect(e.backspace(), isTrue);
      expect(e.latex, '1/2');
      // …and the linear form really does rebuild the same fraction.
      expect(MathEditor.open('1/2'), isNotNull);
      final again = type('1/2');
      expect(again.latex, r'\frac{1}{2}');
    });

    test('a fraction with a sum on top comes back bracketed, and rebuilds',
        () {
      final e = type('(n+1)/2');
      e.moveRight();
      e.backspace();
      expect(e.latex, '(n+1)/2');
      expect(type('(n+1)/2').latex, r'\frac{n+1}{2}');
    });

    test('a power unbuilds to its caret form', () {
      final e = type('x^2');
      e.moveRight();
      e.backspace();
      expect(e.latex, 'x^2');
    });

    test('a square root unwraps, keeping everything under it', () {
      final e = type('sqrt ');
      type('x+1', into: e);
      e.moveRight();
      expect(e.backspace(), isTrue);
      // No linear form to give back, so the CONTENTS survive instead — the
      // promise is that nothing is destroyed, not that everything round-trips.
      expect(e.latex, 'x+1');
    });

    test('backspacing a symbol gives back the word that produced it', () {
      final e = type('alpha ');
      expect(e.backspace(), isTrue);
      expect(e.latex, 'alpha');
    });

    test('backspace at the very start of the equation reports "leave"', () {
      final e = MathEditor.empty();
      expect(e.backspace(), isFalse);
    });

    test('a matrix keeps every cell when it unwraps', () {
      final e = MathEditor.empty();
      e.insertItem(mathItemsById['matrix']!);
      e.insertChar('a');
      e.tab();
      e.insertChar('b');
      e.tab();
      e.insertChar('c');
      e.tab();
      e.insertChar('d');
      e.placeAtEnd();
      e.backspace();
      final out = e.latex;
      for (final cell in ['a', 'b', 'c', 'd']) {
        expect(out, contains(cell), reason: 'cell $cell was destroyed');
      }
    });
  });

  group('moving around', () {
    test('Tab walks the boxes still waiting to be filled', () {
      final e = MathEditor.empty();
      e.insertItem(mathItemsById['frac']!);
      expect(e.caretRow.name, 'num');
      expect(e.tab(), isTrue);
      expect(e.caretRow.name, 'den');
      // …and wraps back round rather than stopping dead.
      expect(e.tab(), isTrue);
      expect(e.caretRow.name, 'num');
    });

    test('Tab does nothing once every box is full', () {
      final e = type('1/2');
      e.placeAtEnd();
      expect(e.tab(), isFalse);
    });

    test('the right arrow steps INTO a structure, not over it', () {
      final e = type('1/2');
      e.placeAtStart();
      expect(e.moveRight(), isTrue);
      expect(e.caretRow.name, 'num',
          reason: 'stepping over a fraction makes its contents unreachable');
    });

    test('up and down move between the halves of a fraction', () {
      final e = type('1/2');
      expect(e.caretRow.name, 'den');
      expect(e.moveUp(), isTrue);
      expect(e.caretRow.name, 'num');
      expect(e.moveDown(), isTrue);
      expect(e.caretRow.name, 'den');
    });

    test('up from deep inside a nested denominator still climbs', () {
      final e = type('1/2');
      e.insertChar('/'); // denominator now holds a fraction of its own
      expect(e.moveUp(), isTrue);
      expect(e.moveUp(), isTrue);
      expect(e.caretRow.name, 'num');
    });

    test('the left arrow enters a structure from its right edge', () {
      final e = type('1/2');
      e.placeAtEnd();
      expect(e.moveLeft(), isTrue);
      expect(e.caretRow.name, 'den');
    });

    test('moving off the end of the equation reports "leave"', () {
      final e = type('x');
      e.placeAtEnd();
      expect(e.moveRight(), isFalse);
      e.placeAtStart();
      expect(e.moveLeft(), isFalse);
    });
  });

  group('what the block stores', () {
    test('an empty editor stores nothing at all', () {
      expect(MathEditor.empty().latex, '');
      expect(MathEditor.empty().isEmpty, isTrue);
    });

    test('the caret and the empty boxes never reach storage', () {
      final e = MathEditor.empty();
      e.insertItem(mathItemsById['frac']!);
      expect(e.latex, r'\frac{}{}');
      expect(e.latex, isNot(contains('square')));
      expect(e.latex, isNot(contains('rule')));
      expect(e.latex, isNot(contains('colorbox')));
    });

    test('but they DO appear in what gets drawn', () {
      final e = MathEditor.empty();
      e.insertItem(mathItemsById['frac']!);
      final drawn = e.renderTex(const MathTexCtx());
      expect(drawn, contains(r'\square'));
      expect(drawn, contains(r'\colorbox'),
          reason: 'the box the caret is in has to look different');
    });
  });

  group('opening what is already stored', () {
    test('the equation the OneNote importer emits opens for editing', () {
      // The seam from math_block_render_test.dart, now crossing one more
      // boundary: importer → renderer was proven; this is importer → EDITOR.
      const imported =
          r'\begin{cases}\frac{n}{2}\text{ if }\left(2\right| n) '
          r'\\ −\left(\frac{n+1}{2}\right)\text{if }(2∤n)'
          r'\end{cases}';
      final e = MathEditor.open(imported);
      expect(e, isNotNull,
          reason: 'a student who imported this must be able to edit it');
      // Everything that made this string worth pinning survives the trip.
      final out = e!.latex;
      expect(out, contains(r'\begin{cases}'));
      expect(out, contains(r'\frac{n}{2}'));
      expect(out, contains('−'), reason: 'the U+2212 minus, not a hyphen');
      expect(out, contains('∤'), reason: 'the U+2224 "does not divide"');
      expect(out, contains(r'\text{ if }'));
    });

    test('a mismatched delimiter pair survives, because OneNote wrote one',
        () {
      final e = MathEditor.open(r'\left(2\right| n');
      expect(e, isNotNull);
      expect(e!.latex, contains(r'\left('));
      expect(e.latex, contains(r'\right|'));
    });

    test('equations round-trip through the tree unchanged in meaning', () {
      const cases = [
        r'\frac{1}{2}',
        r'{x}^{2}',
        r'\sqrt[3]{x}',
        r'\begin{pmatrix}a & b \\ c & d\end{pmatrix}',
        r'\binom{n}{r}',
        r'\hat{x}',
        r'\text{if }x',
        r'\sum_{n=1}^{\infty }\frac{1}{{n}^{2}}',
      ];
      for (final tex in cases) {
        final e = MathEditor.open(tex);
        expect(e, isNotNull, reason: 'could not open $tex');
        final again = MathEditor.open(e!.latex);
        expect(again, isNotNull, reason: 'could not re-open ${e.latex}');
        expect(again!.latex, e.latex,
            reason: '$tex is not stable across a second trip');
      }
    });

    test('an equation the tree cannot hold refuses instead of guessing', () {
      // `\sideset` is one of the constructs the renderer itself cannot draw.
      // Opening it visually would mean dropping it on the first keystroke, so
      // the editor says no and the block shows the LaTeX view (§6.6).
      expect(MathEditor.open(r'\sideset{_a^b}{_c^d}\sum'), isNull);
      expect(parseLatex(r'\sideset{}{}\sum').unknown, isNotNull);
    });

    test(r'stored $…$ delimiters are not a reason to refuse', () {
      expect(MathEditor.open(r'$\frac{n}{2}$'), isNotNull);
    });
  });

  group('the search a student actually types', () {
    test('plain words find the symbol', () {
      for (final (query, id) in [
        ('square root', 'sqrt'),
        ('not equal', 'neq'),
        ('theta', 'theta'),
        ('choose', 'binom'),
        ('roughly equal', 'approx'),
        ('to the', 'power'),
        ('piecewise', 'cases'),
        ('average', 'bar'),
      ]) {
        final hits = searchMathItems(query);
        expect(hits.map((i) => i.id), contains(id),
            reason: '"$query" should find $id');
      }
    });

    test('arcsin still finds the sin⁻¹ button', () {
      // Q1: the buttons read sin⁻¹, so the other convention has to be findable
      // or half the users conclude it is missing.
      expect(searchMathItems('arcsin').first.id, 'fn-arcsin');
    });

    test('a miss is empty rather than wrong', () {
      expect(searchMathItems('kjhgfd'), isEmpty);
    });
  });
}
