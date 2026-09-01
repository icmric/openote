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

    test(
        '( against existing content is just a character — no auto-closed '
        'pair stranding what follows', () {
      // Reported: "if my cursor is right up against the left of some thing
      // in the equation and i press ( … it should not auto complete the
      // closing bracket." The grower always inserted an EMPTY pair and
      // pushed whatever came after the caret out past its `)`, wrapping
      // nothing — a stray `()` in front of the very thing the student was
      // about to type into.
      final e = type('x+1');
      e.placeAtStart();
      e.insertChar('(');
      expect(e.latex, r'(x+1',
          reason: 'one character, not \\left(\\right) around nothing, with '
              'x+1 stranded after it');
    });

    test('( still opens a real grower at the true end of the row', () {
      // The end of a slot is the one place nothing can be stranded — this
      // is what keeps `(x+1)`, above, and `\sin(x`, below, working exactly
      // as they always have.
      final e = type('x+1');
      e.placeAtEnd();
      e.insertChar('(');
      expect(e.caretRow.owner, isA<MDelim>(),
          reason: 'a real grower, caret inside its body');
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

    test(
        'backspacing off the front of a plain exponent unwraps it, at the '
        'boundary it was already on', () {
      // Reported: "cursor is at the start of the exponent box and i press
      // backspace, it should delete the box. If there is stuff in it still
      // it should move that all down into regular text (wherever the
      // cursor would land)." Falling through to the ordinary "step to the
      // previous slot" rule just walked the caret into the base and left
      // the exponent untouched — which looked exactly like nothing had
      // happened.
      final e = type('x^2');
      e.caretIndex = 0; // front of "2", inside the exponent
      expect(e.backspace(), isTrue);
      expect(e.latex, 'x2',
          reason: 'the box goes; both the base and what was raised stay, '
              'in order');
      expect(e.caretIndex, 1,
          reason: 'right where the boundary already was, after the x — '
              'not swept to the front of everything');
      // The caret is back in an ordinary row now, not a script slot: a
      // second Backspace takes the x itself, plainly.
      expect(e.backspace(), isTrue);
      expect(e.latex, '2');
    });

    test('an empty exponent goes on the first Backspace, keeping the base',
        () {
      final e = type('x^'); // opens the exponent; nothing typed into it yet
      expect(e.backspace(), isTrue);
      expect(e.latex, 'x', reason: 'there was nothing in the box to lose');
    });

    test(
        'x_i^2: the front of the exponent still visits the subscript '
        'first', () {
      // Unchanged on purpose — a subscript and superscript are still
      // siblings to step between, which the owner did not ask to change.
      final e = type('x_i^2');
      e.caretIndex = 0; // front of "2"
      expect(e.backspace(), isTrue);
      expect(e.caretRow.name, 'sub', reason: 'stepped to the subscript');
      expect(e.latex, r'x_{i}^{2}',
          reason: 'navigation only — nothing deleted yet');
    });

    test(
        "a fixed base with only one limit is not unwrapped from that "
        "limit's front", () {
      // `\lim` has a subscript and no superscript, so without excluding a
      // fixed base the new exponent/subscript rule above would see exactly
      // the shape it looks for and drain `\lim` itself into the row as a
      // plain, editable run of letters — the same class of summation
      // corruption `fixedBase` exists to prevent (see MScript.fixedBase).
      final e = MathEditor.empty()..insertItem(mathItemsById['lim']!);
      e.insertChar('n');
      e.caretIndex = 0; // front of the limit, its only slot
      expect(e.backspace(), isTrue);
      // Exact, not `contains(r'\lim')`: draining a fixed base as a plain
      // symbol renders as `\lim n`, which still contains the substring
      // "\lim" and reads almost the same at a glance — but the `_{}`
      // structure and the sign's protection are both gone for good, and
      // only an exact match catches that.
      expect(e.latex, r'\lim _{n}',
          reason: 'the sign and its subscript structure must both survive '
              'backspacing off the front of its only limit');
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

  group('a summation is one object, not a box you can fall into', () {
    // The owner: "now the numbers are on top of the summation symbol which is
    // great, although the navigation there is a bit funky. Depending on what i
    // do they sometimes move to the front which isnt ideal."
    //
    // All of it came from one thing: the ∑'s own row was an ordinary,
    // navigable, editable box. The caret could walk in, and then typing
    // brace-wrapped the operator (which throws the limits off the sign for
    // good), the caret rule itself became the thing the script attached to,
    // and two Backspaces deleted the ∑ with nothing to show it had gone.

    MathEditor sum() => MathEditor.empty()..insertItem(mathItemsById['sum']!);

    test('the caret can never enter the operator row', () {
      for (final id in ['sum', 'int', 'prod', 'lim', 'iint', 'oint']) {
        final e = MathEditor.empty()..insertItem(mathItemsById[id]!);
        final reachable = <String>{};
        // Walk the whole equation both ways and collect every row visited.
        e.placeAtStart();
        for (var i = 0; i < 40 && e.moveRight(); i++) {
          reachable.add(e.caretRow.name);
        }
        e.placeAtEnd();
        for (var i = 0; i < 40 && e.moveLeft(); i++) {
          reachable.add(e.caretRow.name);
        }
        expect(reachable, isNot(contains('base')),
            reason: '$id lets the caret into the operator\'s own row');
      }
    });

    test('up and down swap the two limits, and keep swapping', () {
      final e = sum();
      expect(e.caretRow.name, 'sub', reason: 'the lower limit comes first');
      expect(e.moveUp(), isTrue);
      expect(e.caretRow.name, 'sup', reason: 'up goes to the top one');
      expect(e.moveUp(), isTrue);
      expect(e.caretRow.name, 'sub', reason: 'and again brings you back');
      expect(e.moveDown(), isTrue);
      expect(e.caretRow.name, 'sup');
    });

    test('backspacing out of the lower limit cannot delete the sign', () {
      final e = sum();
      e.insertChar('n');
      e.caretIndex = 0;
      final original = e.latex; // r'\sum _{n}^{}'
      // `contains(r'\sum')` alone does not catch the regression this found:
      // draining the fixed base into the row as a plain symbol renders
      // `\sum n`, which still CONTAINS the substring "\sum" and reads
      // almost the same at a glance — the `_{}` structure and the sign's
      // own protection are both gone.
      //
      // Nothing here may change so much as a character. The first press
      // only steps the caret to just before the whole sign — there is
      // nothing between the sign and the front of the equation for it to
      // land on, so a second and third press have nowhere left to go and
      // do nothing at all. Two presses used to take the ∑ itself; a third
      // scrambled the rest.
      for (var i = 0; i < 3; i++) {
        e.backspace();
        expect(e.latex, original,
            reason: 'press ${i + 1} changed the sign: ${e.latex}');
      }
    });

    test('and forward Delete cannot eat it either', () {
      final e = sum();
      e.insertChar('n');
      e.placeAtStart();
      for (var i = 0; i < 3; i++) {
        e.delete();
        if (e.latex.isEmpty) break;
        expect(e.latex, contains(r'\sum'),
            reason: 'delete ${i + 1} lost the sign: ${e.latex}');
      }
    });

    test('an emptied summation goes altogether, sign and all', () {
      // The one case where losing the ∑ is right: there is nothing left.
      final e = sum();
      expect(e.latex, contains(r'\sum'));
      e.placeAtEnd();
      e.backspace();
      expect(e.latex, '', reason: 'an empty summation is nothing to keep');
    });

    test('the limits stay ON the sign however you get there', () {
      // The braced-base defect renders the limits beside the sign instead of
      // above and below it, and nothing in the stored string says so unless
      // you know to look.
      final e = sum();
      e.insertChar('i');
      e.moveUp();
      e.insertChar('n');
      expect(e.latex, startsWith(r'\sum'),
          reason: 'a braced base is a different equation: ${e.latex}');
      expect(e.latex, isNot(contains('{\\sum')));
    });

    test('a big operator typed with ^ still gets the sign as its base', () {
      // ∬ and ∮ are plain symbols until a script lands on them, and an
      // operator used not to count as an operand — so the limits attached to
      // an EMPTY base and sat beside an invisible atom.
      final e = MathEditor.empty()..insertItem(mathItemsById['iint']!);
      e.insertChar('^');
      e.insertChar('2');
      expect(e.latex, contains(r'\iint'));
      expect(e.latex, isNot(startsWith('{}')),
          reason: 'the limit attached to nothing: ${e.latex}');
    });

    test('a plain power still walks base to script as it always did', () {
      // The fixed-base rule must not touch ordinary algebra.
      final e = MathEditor.empty()..insertItem(mathItemsById['power']!);
      expect(e.caretRow.name, 'base',
          reason: 'x^2 has a base the student writes in');
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

  group('Ctrl+arrow jumps a whole run', () {
    // Reported: "navigating with ctrl and arrow keys should jump over
    // entire numbers, operators, or sections. At the moment it does
    // nothing." (The "does nothing" half was the equation swallowing the
    // chord before it ever reached its own key handling — math_field_test
    // covers that wiring; these are the run-finding rules themselves.)

    test('a whole number in one jump, from either side', () {
      final e = type('12+x');
      e.placeAtStart();
      expect(e.moveWord(1), isTrue);
      expect(e.caretIndex, 2, reason: 'past both digits of 12, not just one');
      e.placeAtEnd();
      expect(e.moveWord(-1), isTrue);
      expect(e.caretIndex, 3, reason: 'x is one letter, one jump');
      expect(e.moveWord(-1), isTrue);
      expect(e.caretIndex, 2, reason: 'the + is one operator, one jump');
      expect(e.moveWord(-1), isTrue);
      expect(e.caretIndex, 0, reason: 'and 12 the same jump back');
    });

    test('a run of operator characters moves together', () {
      // Built directly rather than typed: `+-` autocorrects to ± the moment
      // the `-` lands (it is the plus-or-minus symbol's own shortcut), which
      // would test that rule instead of this one. Two adjacent operators
      // that stay two operators is the shape this is actually after.
      final e = MathEditor.empty();
      e.caretRow.insert(0, MSym('*', cls: MClass.op));
      e.caretRow.insert(1, MSym('/', cls: MClass.op));
      e.caretRow.insert(2, MSym('1', cls: MClass.digit));
      e.placeAtStart();
      expect(e.moveWord(1), isTrue);
      expect(e.caretIndex, 2, reason: 'both operator characters in one jump');
    });

    test('a whole structure is one jump, never entered', () {
      // The plain right arrow enters a fraction; Ctrl+Right is the
      // opposite — "get me past this altogether".
      final e = MathEditor.empty()
        ..insertChar('x')
        ..insertItem(mathItemsById['frac']!);
      e.placeAtStart();
      expect(e.moveWord(1), isTrue); // past the x
      expect(e.moveWord(1), isTrue); // past the WHOLE fraction
      expect(e.caretRow.owner, isNull,
          reason: 'still in the root row — the fraction was never entered');
      expect(e.caretIndex, 2);
    });

    test('at the row edge, one Ctrl+arrow is exactly one plain arrow', () {
      // There is no run left inside an empty numerator to jump across, so
      // this is what lets Ctrl+Right escape the fraction at all rather
      // than being trapped in whatever row it started in.
      final e = MathEditor.empty()..insertItem(mathItemsById['frac']!);
      expect(e.caretRow.name, 'num');
      expect(e.moveWord(1), isTrue);
      expect(e.caretRow.name, 'den',
          reason: 'one ordinary Tab-like step, not a jump over more');
    });

    test('nowhere left to jump reports "leave", same as a plain arrow', () {
      final e = type('x');
      e.placeAtEnd();
      expect(e.moveWord(1), isFalse);
      e.placeAtStart();
      expect(e.moveWord(-1), isFalse);
    });

    test('Ctrl+Shift highlights the same run', () {
      final e = type('12+x');
      e.placeAtStart();
      expect(e.extendByWord(1), isTrue);
      expect(e.selectionLatex, '12');
      expect(e.extendByWord(1), isTrue);
      expect(e.selectionLatex, '12+');
    });

    test('the highlight never leaves the row it started in', () {
      // The same invariant `extendBy` already keeps for a plain Shift+
      // arrow — a highlight that could span rows would mean nothing to
      // copy, cut or replace as one thing.
      final e = MathEditor.empty()..insertItem(mathItemsById['frac']!);
      expect(e.extendByWord(1), isFalse,
          reason: 'an empty numerator has no run in it to highlight, and '
              'highlighting must not fall back to leaving the row');
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

  group('sin-1 becomes the inverse function, calculator-shorthand style', () {
    // Owner's ask: "already just typing sin converts it into the sin
    // object … would be great to be able to do sin-1 and have it turn
    // into sin^-1 (arcsin). undoing there should initially turn it int
    // sin-1 (where sin is still interpreted as the operator, so it would
    // be identical to sin(-1)), then pressing it again undoes the sin
    // conversion, so it would take sin as just raw letters."

    for (final f in ['sin', 'cos', 'tan']) {
      test('$f-1 converts the moment the 1 lands', () {
        expect(type('$f-1').latex, '\\$f ^{-1}');
      });
    }

    test('the letters before the dash have to spell a real function', () {
      // Not "xyz-1": nothing in `invertible` answers to "xyz", so this is
      // just four characters and a digit, exactly as typed.
      expect(type('xyz-1').latex, 'xyz-1');
    });

    test('sin-2 is not a shorthand anybody uses — stays a subtraction', () {
      expect(type('sin-2').latex, isNot(contains('^')));
    });

    test('one Backspace undoes the SHORTHAND only: sin(-1), not raw letters',
        () {
      final e = type('sin-1');
      expect(e.backspace(), isTrue);
      expect(e.latex, r'\sin -1',
          reason: 'identical to typing sin(-1) by hand: \\sin is still the '
              'protected function, -1 is plain text after it');
    });

    test('a SECOND Backspace then undoes \\sin itself, down to raw letters',
        () {
      final e = type('sin-1');
      e.backspace(); // stage 1: sin-1 → \sin, -1
      expect(e.backspace(), isTrue); // stage 2: \sin → s, i, n
      expect(e.latex, 'sin-1',
          reason: 'back to exactly what was typed, letter for letter — the '
              'ordinary MSym.typed round-trip every other autocorrected '
              'symbol already gets');
    });

    test('a third Backspace is ordinary again: one letter at a time', () {
      final e = type('sin-1');
      e.backspace();
      e.backspace();
      expect(e.backspace(), isTrue);
      expect(e.latex, 'si-1');
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
