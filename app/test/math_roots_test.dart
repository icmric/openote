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
}
