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

/// One backslash, named so the test bodies read as what a student presses
/// rather than as escape soup.
const String bs = '\\';

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
      // Unbraced base. `{x}^{2}` draws the same, but `{\int}^{2}` does NOT
      // draw the same as `\int^{2}` — see the big-operator test below.
      expect(type('x^2').latex, r'x^{2}');
    });

    test('a power and an index land on the same letter', () {
      expect(type('x_i^2').latex, r'x_{i}^{2}');
    });

    test('a BACKSLASH command becomes its symbol on space', () {
      expect(type(bs + 'alpha ').latex, r'\alpha ');
    });

    test('an operator finishes a command too, without a space', () {
      // Nobody types a space before the plus.
      expect(type(bs + 'pi+1').latex, r'\pi +1');
    });

    test('but a bare word is just a word', () {
      // **The rule the owner asked for**, replacing "convert everything we
      // recognise the moment a space arrives". `in`, `cap`, `div`, `to`,
      // `dot`, `hat`, `deg` and every Greek letter are ordinary English words
      // and ordinary variable names, so a greedy converter turned a student's
      // own writing into symbols they never asked for.
      expect(type('alpha ').latex, isNot(contains(r'\alpha')));
      expect(type('a in b').latex, isNot(contains(r'\in ')));
      expect(type('sin x').latex, isNot(contains(r'\sin')));
      expect(type('cap ').latex, isNot(contains(r'\cap')));
    });

    test('and a space is a SPACE', () {
      // It used to be swallowed whenever it built nothing, so there was no way
      // to put one in at all — "i can never have a space included".
      expect(type('hello world').latex, r'hello\ world');
      expect(type('x + y').latex, r'x\ +\ y');
    });

    test('an unknown command stays as the characters typed', () {
      // Never an error, and never silently eaten.
      expect(type(bs + 'notacommand ').latex, contains('notacommand'));
    });

    test('<= becomes one symbol the moment it is complete', () {
      expect(type('a<=b').latex, r'a\leq b');
    });

    test('-> becomes an arrow', () {
      expect(type('x->0').latex, r'x\to 0');
    });

    test('sqrt opens a root with the caret under the sign', () {
      final e = type(bs + 'sqrt ');
      expect(e.latex, r'\sqrt{}');
      expect(e.caretRow.owner, isA<MSqrt>());
      expect(e.caretRow.name, 'radicand');
      e.insertChar('9');
      expect(e.latex, r'\sqrt{9}');
    });

    test('sum opens with the caret in the lower limit', () {
      final e = type(bs + 'sum ');
      expect(e.caretRow.name, 'sub');
      type('n=1', into: e);
      expect(e.latex, contains(r'\sum'));
      expect(e.latex, contains('n=1'));
    });

    test('a function name goes upright when the bracket arrives', () {
      final e = type(bs + 'sin(x');
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

    test('a big operator keeps its limits above and below', () {
      // **The equation the owner photographed.** `{\int }_{5}^{2}` and
      // `\int _{5}^{2}` are not the same equation: braces make the base an
      // ORDINARY atom, and TeX only stacks limits on a BIG OPERATOR. Braced,
      // the 5 and the 2 slide out beside the sign like the indices of a
      // variable. Nothing about this is visible in the stored string unless
      // you know to look, which is why it is pinned here.
      for (final id in ['int', 'sum', 'prod', 'iint', 'oint']) {
        final e = MathEditor.empty()..insertItem(mathItemsById[id]!);
        expect(e.latex, isNot(startsWith('{')),
            reason: '\$id must not brace its operator, or its limits move');
      }
      // A base of two or more atoms still needs its braces.
      expect(type('(a+b)^2').latex, contains(r'^{2}'));
      // …and an empty base still needs somewhere to hang the script.
      final bare = MathEditor.empty()..insertItem(mathItemsById['power']!);
      expect(bare.latex, r'{}^{}');
    });

    test('the whole integral, as a student writes it', () {
      // Insert ∫, lower limit, Tab, upper limit, Tab, integrand. Before the
      // Tab-out fix the last Tab did nothing and the integrand was typed into
      // the exponent — `{\int }_{5}^{23x+5dx}` — which is what put the
      // numbers up beside the sign in the owner's screenshot.
      final e = MathEditor.empty()..insertItem(mathItemsById['int']!);
      e.insertChar('5');
      expect(e.tab(), isTrue);
      e.insertChar('2');
      expect(e.tab(), isTrue, reason: 'a structure you cannot Tab out of is a trap');
      expect(e.caretRow.owner, isNull, reason: 'the integrand goes on the baseline');
      for (final ch in '3x+5dx'.split('')) {
        e.insertChar(ch);
      }
      expect(e.latex, r'\int _{5}^{2}3x+5dx');
    });

    test('an unfinished construct is just characters, never an error', () {
      // Math Input Spec §3.3: typing is never blocked.
      expect(type('3x+').latex, '3x+');
    });
  });

  group('backspace never eats what was typed', () {
    // The rule: at a structure's RIGHT edge, Backspace steps inside it at the
    // end. It never takes a structure and its contents together.
    //
    // This replaced an "unbuild back into the characters that made it" rule,
    // which read well and was wrong three measured ways — see the header of
    // math_editor.dart. These are the evidence the replacement keeps the
    // promise the old rule was written for.

    test('backspacing into a fraction enters it, and deletes from there', () {
      final e = type('1/2');
      e.placeAtEnd();
      expect(e.backspace(), isTrue);
      expect(e.caretRow.name, 'den', reason: 'step in, do not destroy');
      expect(e.latex, r'\frac{1}{2}', reason: 'nothing deleted yet');
      expect(e.backspace(), isTrue);
      expect(e.latex, r'\frac{1}{}', reason: 'now the 2 goes');
    });

    test('an empty structure goes on the first press — nothing to step into',
        () {
      final e = MathEditor.empty()..insertItem(mathItemsById['frac']!);
      e.placeAtEnd();
      expect(e.backspace(), isTrue);
      expect(e.latex, '',
          reason: 'stepping into an empty fraction would be a keystroke that '
              'appears to do nothing');
    });

    test('a power NEVER unbuilds to a bare caret', () {
      // The reported shape: an empty script unbuilt to `^`, which is not
      // drawable TeX at all, so the equation vanished into a grey box of
      // source the moment Backspace was pressed.
      for (final id in ['power', 'subscript', 'subsup']) {
        final e = MathEditor.empty()..insertItem(mathItemsById[id]!);
        e.placeAtEnd();
        e.backspace();
        expect(e.latex, isNot(anyOf('^', '_', '_^')),
            reason: '$id backspaced to undrawable TeX');
      }
    });

    test('a square root keeps everything under it', () {
      final e = type(bs + 'sqrt ');
      type('x+1', into: e);
      e.placeAtEnd();
      expect(e.backspace(), isTrue);
      expect(e.latex, contains('x+1'), reason: 'nothing may be destroyed');
    });

    test('deleting off the FRONT unwraps, keeping the contents', () {
      final e = type(bs + 'sqrt ');
      type('x+1', into: e);
      e.caretIndex = 0; // start of the radicand
      expect(e.backspace(), isTrue);
      expect(e.latex, 'x+1', reason: 'the sign goes, what was under it stays');
    });

    test('backspacing a symbol gives back the command that produced it', () {
      final e = type(bs + 'alpha ');
      expect(e.backspace(), isTrue);
      expect(e.latex, contains('alpha'));
    });

    test('backspace at the very start of the equation reports "leave"', () {
      final e = MathEditor.empty();
      expect(e.backspace(), isFalse);
    });

    test('one Backspace can never flatten a filled matrix', () {
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
      expect(e.latex, contains(r'\begin{pmatrix}'),
          reason: 'the grid itself has to survive a single keypress — it used '
              'to flatten to a bare run of its own cells');
      for (final cell in ['a', 'b', 'c', 'd']) {
        expect(e.latex, contains(cell), reason: 'cell $cell was destroyed');
      }
    });

    test('Delete takes one character of a words box, not the whole box', () {
      final e = MathEditor.empty()..insertItem(mathItemsById['words']!);
      for (final ch in 'if'.split('')) {
        e.insertChar(ch);
      }
      e.placeAtStart();
      expect(e.delete(), isTrue);
      expect(e.latex, contains('f'), reason: 'only the i should have gone');
      expect(e.latex, isNot(contains('i')));
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

    test('Tab from a full structure LEAVES it', () {
      final e = type('1/2');
      expect(e.caretRow.name, 'den');
      expect(e.tab(), isTrue);
      expect(e.caretRow.owner, isNull,
          reason: 'the way out has to be the same key as the way in');
      // …and at the top level, with nothing left to leave, it stops.
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
      // `\fcolorbox`, not `\colorbox`: the latter draws its contents and never
      // paints its fill in flutter_math_fork 0.7.4, so the "you are here" box
      // was invisible for as long as it shipped.
      expect(drawn, contains(r'\fcolorbox'),
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
