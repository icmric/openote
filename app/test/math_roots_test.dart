// Roots you can type (owner, v0.23).
//
// *"\rt should create a generic root, we already have \sqrt for squareroot,
// but maybe we have \cbrt for cube root, then just do \nrt as a shorthand to
// automatically fill out the number for other roots (still supporting 2 and
// 3), and in the case where someone does \2rt, we should render the 2 even
// though its otherwise assumed its 2."*
//
// The tree already held indexed roots — `MSqrt` has had a `degree` slot all
// along, and the parser, the renderer, the projection and the evaluator all
// knew about it. The whole gap was in the TYPING.
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/math/evaluate.dart';
import 'package:openote/math/math_editor.dart';
import 'package:openote/math/math_inventory.dart';
import 'package:openote/math/math_linear_projection.dart';
import 'package:openote/math/math_parse.dart';
import 'package:openote/math/math_tree.dart';

/// One backslash, so the expectations read as what a student types.
final bs = String.fromCharCode(92);

MathEditor typed(String chars) {
  final e = MathEditor.empty();
  for (final ch in chars.split('')) {
    e.insertChar(ch);
  }
  return e;
}

void main() {
  group('the commands', () {
    test(r'\rt opens a root with an empty index box', () {
      final e = typed(bs + 'rt ');
      expect(e.latex, r'\sqrt[]{}');
      final root = e.root.children.single as MSqrt;
      expect(root.degree, isNotNull);
      expect(root.degree!.isEmpty, isTrue);
      expect(identical(e.caretRow, root.degree), isTrue,
          reason: 'the caret lands in the first empty box, which is the index');
    });

    test(r'\cbrt is a cube root, with the three already in it', () {
      final e = typed(bs + 'cbrt ');
      expect(e.latex, r'\sqrt[3]{}');
      final root = e.root.children.single as MSqrt;
      expect(identical(e.caretRow, root.radicand), isTrue,
          reason: 'the index is filled, so the caret goes where the work is');
    });

    test(r'\2rt draws the two, even though a bare radical already means two',
        () {
      final e = typed(bs + '2rt ');
      expect(e.latex, r'\sqrt[2]{}');
    });

    test('and the family runs as far as the numbers do', () {
      for (final n in ['3', '4', '5', '7', '10', '12']) {
        final e = typed(bs + n + 'rt ');
        expect(e.latex, r'\sqrt[' + n + ']{}', reason: n);
      }
    });

    test(r'\sqrt still means a plain square root', () {
      expect(typed(bs + 'sqrt ').latex, r'\sqrt{}');
    });

    test(r'\root and \nrt still reach the generic one', () {
      expect(typed(bs + 'root ').latex, r'\sqrt[]{}');
      expect(typed(bs + 'nrt ').latex, r'\sqrt[]{}',
          reason: 'a student who reads "nrt" as a command should get one');
    });

    test('a bare word is still not a command', () {
      // The central rule of the editor: only a backslash converts.
      expect(typed('2rt ').latex, isNot(contains('sqrt')));
      expect(typed('rt ').latex, isNot(contains('sqrt')));
      expect(typed('cbrt ').latex, isNot(contains('sqrt')));
    });

    test('and widening the walk to digits took nothing away', () {
      // A digit used to stop the walk dead, so `\alpha2` converted nothing.
      // It still converts nothing — it is simply no longer a command.
      expect(typed(bs + 'alpha2 ').latex, isNot(contains(bs + 'alpha')),
          reason: 'the letters are still letters, as they always were');
      expect(typed(bs + 'alpha ').latex, contains('alpha'),
          reason: 'and the ordinary case is untouched');
    });
  });

  group('what a typed root then does', () {
    test('it works out, which the projection already knew how to do', () {
      final e = typed(bs + '3rt ');
      e.insertChar('8');
      expect(rowToLinear(e.root).replaceAll(' ', ''), '((8)^(1/(3)))');
      expect(evaluateLinear(rowToLinear(e.root)).display, '2');
    });

    test('and answers at the caret like anything else', () {
      final e = typed(bs + '4rt ');
      e.insertChar('1');
      e.insertChar('6');
      e.placeAtEnd();
      e.insertChar('=');
      e.insertChar(' ');
      expect(e.latex, r'\sqrt[4]{16}=\boxed{2}');
    });

    test('it survives a save and a reopen', () {
      for (final tex in [r'\sqrt[3]{8}', r'\sqrt[]{x}', r'\sqrt{2}']) {
        final reopened = MathEditor.open(tex);
        expect(reopened, isNotNull, reason: tex);
        expect(reopened!.latex, tex, reason: 'byte for byte: ' + tex);
      }
    });
  });

  group('an empty index takes itself away', () {
    test('backspace in an empty index leaves an ordinary square root', () {
      final e = typed(bs + '3rt ');
      // Caret is in the radicand; write something worth keeping.
      e.insertChar('x');
      // Back up into the index and empty it.
      final root = e.root.children.single as MSqrt;
      e.caretRow = root.degree!;
      e.caretIndex = root.degree!.length;
      expect(e.caretRow.name, 'degree');
      expect(e.backspace(), isTrue); // takes the 3
      expect(e.latex, r'\sqrt[]{x}');
      expect(e.backspace(), isTrue); // …and now the index itself
      expect(e.latex, r'\sqrt{x}',
          reason: 'a root printing an empty box for ever, with no way back to '
              'a plain radical, is a trap');
      expect(e.caretRow.name, 'radicand');
    });

    test('and the work under the sign is never touched', () {
      final e = MathEditor.open(r'\sqrt[3]{2x+1}')!;
      final root = e.root.children.single as MSqrt;
      e.caretRow = root.degree!;
      e.caretIndex = root.degree!.length;
      e.backspace();
      e.backspace();
      expect(e.latex, r'\sqrt{2x+1}');
    });
  });

  group('the palette says so too', () {
    test('there is a cube root button, and it is not hiding behind an alias',
        () {
      final cbrt = mathItemsById['cbrt'];
      expect(cbrt, isNotNull);
      expect(cbrt!.name, 'cube root');
      expect(cbrt.typeIt, r'\cbrt');
      final hits = searchMathItems('cube root');
      expect(hits.first.id, 'cbrt',
          reason: 'the nth-root item used to carry "cube root" as an alias, '
              'which is now misleading');
    });

    test('the nth root advertises the short route', () {
      final nth = mathItemsById['nthroot']!;
      expect(nth.typeIt, r'\rt');
      expect(nth.alsoTypeIt, contains(r'\root'),
          reason: 'a shortcut that used to work and silently stopped is '
              'worse than one that never existed');
    });

    test('and the tooltip reads as one label', () {
      for (final id in ['nthroot', 'cbrt', 'sqrt']) {
        final i = mathItemsById[id]!;
        final tip = '${i.name} (${i.typeIt})';
        expect(tip, isNot(contains('type it')));
        expect(tip, isNot(contains(' - ')));
        expect(tip, startsWith(i.name));
      }
    });
  });

  group('reading a root back off the page', () {
    // A space is the last thing a student types before looking at the answer,
    // and a space is written `\ `. Storing the equation trims it to a lone
    // backslash — which is not a command, and used to throw a RangeError
    // straight out of MathEditor.open. Not "opens in the LaTeX view": throws,
    // from four unguarded call sites, one of them every keystroke.
    test('an equation that ended in a space still opens', () {
      final bs = String.fromCharCode(92);
      for (final src in [r'\sqrt[3]{8}', r'\mathrm{gcd}\left( 12,18\right) ',
        '2+3', r'\frac{1}{2}']) {
        final r = parseLatex(src.trimRight() + bs);
        expect(r.supported, isTrue, reason: src);
        expect(rowToTex(r.root!, const MathTexCtx()),
            rowToTex(parseLatex(src).root!, const MathTexCtx()),
            reason: 'and the trailing space changed nothing at all');
      }
    });

    test('a lone backslash on its own is an empty equation, not a crash', () {
      final r = parseLatex(String.fromCharCode(92));
      expect(r.supported, isTrue);
      expect(r.root!.isEmpty, isTrue);
    });

    test('a root written inside a root index survives being stored', () {
      // `]` used to be looked for with indexOf, which finds the FIRST one —
      // the inner root's — so the equation came back as a different one,
      // with `supported: true` and no warning at all.
      const src = r'\sqrt[\sqrt[3]{2}]{}';
      final r = parseLatex(src);
      expect(r.supported, isTrue);
      final again = rowToTex(r.root!, const MathTexCtx());
      expect(again, r'\sqrt[{\sqrt[3]{2}}]{}');
      expect(rowToTex(parseLatex(again).root!, const MathTexCtx()), again,
          reason: 'and it is stable from there on');
    });

    test('a bracket typed into an index is braced, not left to close it', () {
      final r = parseLatex(r'\sqrt[{n]}]{x}');
      expect(r.supported, isTrue);
      expect(rowToTex(r.root!, const MathTexCtx()), r'\sqrt[{n]}]{x}',
          reason: 'the x is under the sign, and the ] is in the index');
    });

    test('an index the reader cannot read refuses the whole equation', () {
      // Rather than dropping the part it disliked and carrying on, which is
      // how an equation quietly becomes a different equation.
      final r = parseLatex(r'\sqrt[\unknowable{2}]{x}');
      expect(r.supported, isFalse);
      expect(r.unknown, isNotNull);
    });

    test('an ordinary root is untouched by any of it', () {
      for (final src in [r'\sqrt{2}', r'\sqrt[3]{8}', r'\sqrt[\frac{1}{2}]{x}',
        r'\sqrt[n]{x^{2}}']) {
        final r = parseLatex(src);
        expect(r.supported, isTrue, reason: src);
        expect(rowToTex(r.root!, const MathTexCtx()), src, reason: src);
      }
    });
  });


  group('Tab leaves when there is nowhere left to go', () {
    // "A structure you cannot leave by the key that got you into it is a
    // trap" is the rule Tab is written to. When the only empty box left was
    // the one the caret was standing in, Tab wrapped round to it, moved
    // nothing, and swallowed the key: the student was left pressing Tab at a
    // half-filled root with no way out but the mouse.
    test('a root with only its index left empty', () {
      final e = MathEditor.empty()..insertSource(r'\sqrt[]{8}');
      e.tab(); // into the index, the only hole there is
      expect(e.caretRow.name, 'degree');
      expect(e.tab(), isTrue, reason: 'the key is used');
      expect(identical(e.caretRow, e.root), isTrue,
          reason: 'and it came OUT, rather than landing where it started');
    });

    test('with two holes it still goes to the other one', () {
      final e = MathEditor.empty()..insertSource(r'\sqrt[]{}');
      e.tab();
      final first = e.caretRow;
      e.tab();
      expect(identical(e.caretRow, first), isFalse);
      e.tab();
      expect(identical(e.caretRow, first), isTrue, reason: 'and round again');
    });

    test('a call with one box filled leaves by the second', () {
      final e = MathEditor.empty()
        ..insertItem(mathItemsById['fn-gcd']!);
      e.insertChar('9');
      expect(e.tab(), isTrue);
      e.insertChar('6');
      expect(e.tab(), isTrue);
      expect(identical(e.caretRow, e.root), isTrue,
          reason: 'both boxes filled, so Tab means "done here"');
    });
  });

}
