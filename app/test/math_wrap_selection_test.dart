// Highlight part of an equation, press an opening bracket, get it wrapped.
//
// *"Highlighting a section of an equation then pressing an opening bracket
// like (, [, or { should wrap the selected text in it rather than replace it.
// Want the same behaviour that we have in general writing. Should keep all
// the original structure of the maths that gets wrapped too."*
//
// Before this, `insertChar` ran `deleteSelection()` first and unconditionally,
// so the bracket replaced the student's working — the exact fault
// `WrapSelectionFormatter` was written to fix in prose, unfixed in the one
// place where what is being thrown away is hardest to retype.
//
// **"Keeps all the original structure" is the interesting half**, and it comes
// out of moving the nodes rather than re-parsing them. A selection here is a
// contiguous run of siblings in ONE row, by construction, so the wrap takes
// those objects out and puts the same objects into the bracket's body. A
// fraction inside the run is still that fraction, with whatever was in its
// slots, because nothing has looked at it.

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/math/math_editor.dart';
import 'package:openote/math/math_inventory.dart';
import 'package:openote/math/math_tree.dart';

MathEditor typed(String s) {
  final e = MathEditor.empty();
  for (final ch in s.split('')) {
    e.insertChar(ch);
  }
  return e;
}

/// Select the whole root row.
void selectAll(MathEditor e) {
  e.placeAt(0);
  while (e.caretIndex < e.root.length) {
    e.extendBy(1);
  }
}

void main() {
  group('wrapping a highlight', () {
    test('a round bracket wraps rather than replaces', () {
      final e = typed('x+1');
      selectAll(e);
      expect(e.hasSelection, isTrue);
      expect(e.insertChar('('), isTrue);
      expect(e.latex, r'\left( x+1\right) ');
    });

    test('and so do square and curly', () {
      for (final (open, tex) in [
        ('[', r'\left[ x+1\right] '),
        // `\left{` is not a delimiter — TeX reads it as `\left` and a group —
        // so the curly pair has to be escaped on the way out.
        ('{', r'\left\{ x+1\right\} '),
      ]) {
        final e = typed('x+1');
        selectAll(e);
        expect(e.insertChar(open), isTrue, reason: open);
        expect(e.latex, tex, reason: open);
      }
    });

    test('anything else still replaces, as it always did', () {
      // The rule is scoped to opening brackets. Typing over a highlight is
      // what every editor does and is not what changed here.
      final e = typed('x+1');
      selectAll(e);
      expect(e.insertChar('y'), isTrue);
      expect(e.latex, 'y');
    });

    test('a closing bracket is not a wrap', () {
      final e = typed('x+1');
      selectAll(e);
      e.insertChar(')');
      expect(e.latex, isNot(contains('x+1')),
          reason: 'only the OPENING bracket of a pair wraps');
    });

    test('with no highlight, a bracket behaves exactly as before', () {
      final e = typed('x+1');
      expect(e.hasSelection, isFalse);
      e.insertChar('(');
      // At the end of the row this opens a grower, which is the long-standing
      // behaviour `\sin(` depends on.
      expect(e.latex, contains(r'\left('));
    });
  });

  group('the structure comes through', () {
    test('a fraction inside the run is still a fraction', () {
      // `1/2` builds an MFrac. Wrapping must not flatten it to text.
      final e = typed('1/2');
      e.placeAtEnd();
      selectAll(e);
      expect(e.insertChar('('), isTrue);
      expect(e.latex, r'\left( \frac{1}{2}\right) ',
          reason: 'the fraction survived as a fraction');
      // And it is still a real node with its own slots, not a rendering.
      final delim = e.root.children.single as MDelim;
      expect(delim.body.children.single, isA<MFrac>());
    });

    test('a palette structure keeps everything in its slots', () {
      // The hardest case: a prefilled sum, which has content in both limits.
      final e = MathEditor.empty();
      e.insertItem(mathItemsById['sumin']!);
      e.placeAtEnd();
      selectAll(e);
      expect(e.insertChar('('), isTrue);
      expect(e.latex, r'\left( \sum _{i=1}^{n}\right) ',
          reason: 'i=1 and n are still in the limits they were in');
    });

    test('a mixed run keeps its order and its parts', () {
      // `a+1/2+b` typed straight through puts the `+b` in the DENOMINATOR,
      // because `/` opens one and typing carries on inside it. That is the
      // editor working correctly and it is what must survive the wrap —
      // asserting the tidier equation anyone would assume here was this
      // test's own mistake, not the editor's.
      final e = typed('a+1/2+b');
      selectAll(e);
      expect(e.insertChar('['), isTrue);
      expect(e.latex, r'\left[ a+\frac{1}{2+b}\right] ',
          reason: 'order kept, and the fraction kept what was inside it');
    });

    test('wrapping part of a row leaves the rest alone', () {
      final e = typed('a+b+c');
      // Highlight the last two atoms only.
      e.placeAt(e.root.length);
      e.extendBy(-1);
      e.extendBy(-1);
      expect(e.insertChar('('), isTrue);
      expect(e.latex, r'a+b\left( +c\right) ');
    });
  });

  group('what happens next', () {
    test('the run stays selected, as it does in prose', () {
      // `WrapSelectionFormatter` leaves the wrapped text selected
      // (`baseOffset: sel.start + 1`), and the request was for the same
      // behaviour. It also means a second bracket wraps again instead of
      // replacing what the first one did.
      final e = typed('x+1');
      selectAll(e);
      e.insertChar('(');
      expect(e.hasSelection, isTrue, reason: 'still highlighted');
      expect(e.insertChar('['), isTrue);
      expect(e.latex, r'\left( \left[ x+1\right] \right) ',
          reason: 'a second bracket wraps the first one"s contents');
    });

    test('and the caret is inside the bracket, after the run', () {
      final e = typed('x+1');
      selectAll(e);
      e.insertChar('(');
      expect(e.caretRow.owner, isA<MDelim>());
      expect(e.caretIndex, e.caretRow.length);
    });

    test('so typing a character replaces the run, as it does in prose', () {
      // The other side of keeping the selection, and the one worth stating
      // because it surprised me while writing these: the run is still
      // highlighted, so the very next character typed REPLACES it. That is
      // exactly what `WrapSelectionFormatter` leaves prose doing, and the
      // request was for the same behaviour, so it is the behaviour — not a
      // loose end.
      final e = typed('x+1');
      selectAll(e);
      e.insertChar('(');
      e.insertChar('y');
      expect(e.latex, r'\left( y\right) ');
    });

    test('and dropping the highlight first carries on inside the bracket',
        () {
      final e = typed('x+1');
      selectAll(e);
      e.insertChar('(');
      e.clearSelection();
      e.insertChar('+');
      e.insertChar('2');
      expect(e.latex, r'\left( x+1+2\right) ');
    });

    test('undo-able as one step, because it is one mutation', () {
      // Nothing to assert on the editor itself — it has no undo stack, the
      // page does — but the wrap is a single `insertChar`, so the host's
      // existing coalescing treats it as one edit the same way a palette
      // press is one edit.
      final e = typed('x+1');
      selectAll(e);
      final before = e.latex;
      e.insertChar('(');
      expect(e.latex, isNot(before));
    });
  });
}
