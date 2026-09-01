// Highlighting part of an equation, and cutting only that part.
//
// The owner, twice: "I also still cant highlight text, and when i cut it cuts
// all the content, id love to be able to highlight and cut only part of the
// equation."
//
// The model, and the one thing worth knowing about it: **a selection is a
// contiguous run of siblings in ONE row.** Not a range over the whole tree. A
// run that started in a numerator and ended outside the fraction would have no
// meaning to copy, cut or replace, and every operation on it would need a
// special case. Shift+arrow therefore steps OVER a structure rather than into
// it — dragging across a fraction selects the whole fraction, which is what a
// student means by doing that.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/math/math_editor.dart';
import 'package:openote/math/math_field.dart';
import 'package:openote/math/math_inventory.dart';
import 'package:openote/math/math_tree.dart';
import 'package:openote/math/math_view.dart';

MathEditor typed(String s) {
  final e = MathEditor.empty();
  for (final ch in s.split('')) {
    e.insertChar(ch);
  }
  return e;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the model', () {
    test('shift-left builds a run backwards from the caret', () {
      final e = typed('abcd');
      expect(e.hasSelection, isFalse);
      expect(e.extendBy(-1), isTrue);
      expect(e.extendBy(-1), isTrue);
      expect(e.hasSelection, isTrue);
      expect(e.selectionStart, 2);
      expect(e.selectionEnd, 4);
      expect(e.selectionLatex, 'cd');
    });

    test('and shift-right builds it forwards', () {
      final e = typed('abcd');
      e.placeAtStart();
      e.extendBy(1);
      e.extendBy(1);
      expect(e.selectionLatex, 'ab');
    });

    test('it stops at the row edge rather than escaping the row', () {
      final e = typed('ab');
      e.placeAtStart();
      expect(e.extendBy(-1), isFalse, reason: 'nothing to the left');
      e.placeAtEnd();
      expect(e.extendBy(1), isFalse, reason: 'nothing to the right');
    });

    test('a structure is taken WHOLE, never half', () {
      // The reason the run lives in one row: half a fraction is not an
      // equation, and nothing sensible could be done with it.
      final e = typed('1/2');
      e.placeAtEnd();
      expect(e.extendBy(-1), isTrue);
      expect(e.selectionLatex, r'\frac{1}{2}',
          reason: 'the whole fraction, not its denominator');
    });

    test('Ctrl+A takes the row the caret is in', () {
      final e = typed('x+y');
      expect(e.selectAll(), isTrue);
      expect(e.selectionLatex, 'x+y');
    });

    test('any plain movement lets it go', () {
      // A highlight that survives an arrow key is one the student has stopped
      // seeing, and the next keystroke would eat it.
      final e = typed('abc');
      e.selectAll();
      expect(e.hasSelection, isTrue);
      e.moveLeft();
      expect(e.hasSelection, isFalse);
    });

    test('deleting takes exactly the run, and the caret lands where it was',
        () {
      final e = typed('abcd');
      e.extendBy(-1);
      e.extendBy(-1);
      expect(e.deleteSelection(), isTrue);
      expect(e.latex, 'ab');
      expect(e.caretIndex, 2);
      expect(e.hasSelection, isFalse);
    });

    test('typing over a highlight replaces it', () {
      final e = typed('abcd');
      e.selectAll();
      e.insertChar('z');
      expect(e.latex, 'z');
    });

    test('and so does a palette press', () {
      final e = typed('abcd');
      e.selectAll();
      e.insertItem(mathItemsById['pi']!);
      expect(e.latex.trim(), r'\pi');
    });
  });

  group('what it looks like', () {
    testWidgets('the highlighted run is painted, and the rest is not',
        (tester) async {
      final e = typed('abcd');
      e.extendBy(-1);
      e.extendBy(-1);
      final drawn = e.renderTex(const MathTexCtx());
      // `\fcolorbox`, because `\colorbox` never paints its fill in
      // flutter_math_fork 0.7.4 — the same discovery that made the active-slot
      // box visible in the first place.
      expect(drawn, contains(r'\fcolorbox'));
      // …and it still draws.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OnoteMath(drawn,
              textStyle: const TextStyle(fontSize: 20, color: Colors.black)),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(MathSourceFallback), findsNothing,
          reason: 'a highlight that breaks the render is worse than none');
    });

    testWidgets('a highlight over a structure draws too', (tester) async {
      final e = typed('1/2');
      e.placeAtEnd();
      e.extendBy(-1);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OnoteMath(e.renderTex(const MathTexCtx()),
              textStyle: const TextStyle(fontSize: 20, color: Colors.black)),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(MathSourceFallback), findsNothing);
    });
  });

  group('cut and copy take only what is highlighted', () {
    late MathEditor editor;
    late Map<String, String> clipboard;

    setUp(() {
      clipboard = {};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard['text'] = call.arguments['text'] as String;
        }
        if (call.method == 'Clipboard.getData') {
          return {'text': clipboard['text'] ?? ''};
        }
        return null;
      });
    });

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MathField(
            editor: editor,
            textStyle: const TextStyle(fontSize: 20, color: Colors.black),
            onChanged: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> chord(WidgetTester tester, LogicalKeyboardKey k,
        {bool shift = false}) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(k);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    testWidgets('Shift+arrow highlights, and Ctrl+X takes only that',
        (tester) async {
      editor = typed('abcd');
      await pump(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      await chord(tester, LogicalKeyboardKey.keyX);
      expect(clipboard['text'], r'$cd$');
      expect(editor.latex, 'ab', reason: 'the rest of the equation stays');
    });

    testWidgets('Ctrl+C with a highlight copies only that', (tester) async {
      editor = typed('abcd');
      await pump(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      await chord(tester, LogicalKeyboardKey.keyC);
      expect(clipboard['text'], r'$d$');
      expect(editor.latex, 'abcd');
    });

    testWidgets('with nothing highlighted, Ctrl+X still takes it all',
        (tester) async {
      editor = typed('abcd');
      await pump(tester);
      await chord(tester, LogicalKeyboardKey.keyX);
      expect(clipboard['text'], r'$abcd$');
      expect(editor.latex, '');
    });

    testWidgets('Ctrl+A then Ctrl+X clears the equation', (tester) async {
      editor = typed('x+y');
      await pump(tester);
      await chord(tester, LogicalKeyboardKey.keyA);
      expect(editor.hasSelection, isTrue);
      await chord(tester, LogicalKeyboardKey.keyX);
      expect(editor.latex, '');
      expect(clipboard['text'], r'$x+y$');
    });

    // Reported: "navigating with ctrl and arrow keys should jump over entire
    // numbers, operators, or sections. At the moment it does nothing." It
    // reached nowhere near its own arrow handling — "everything else with
    // Ctrl belongs to the app" swallowed the whole chord first, at the
    // WIDGET's key handler, above where any test of `MathEditor` alone could
    // have caught it. This is that handler, actually pressing the keys.
    testWidgets('Ctrl+Right actually reaches the field, and jumps the number',
        (tester) async {
      editor = typed('12+x');
      editor.placeAtStart();
      await pump(tester);
      await chord(tester, LogicalKeyboardKey.arrowRight);
      expect(editor.caretIndex, 2,
          reason: 'past both digits of 12 — previously nothing moved at all');
    });

    testWidgets('Ctrl+Shift+Right highlights the same run', (tester) async {
      editor = typed('12+x');
      editor.placeAtStart();
      await pump(tester);
      await chord(tester, LogicalKeyboardKey.arrowRight, shift: true);
      expect(editor.selectionLatex, '12');
    });
  });
}
