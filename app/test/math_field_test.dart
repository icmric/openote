// The visual editor as a student meets it: keys go in, notation comes out,
// and the LaTeX never appears unless they ask for it.
// (plan: docs/planning/v0.18-visual-maths.md §5, §6)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/math/math_editor.dart';
import 'package:openote/math/math_field.dart';
import 'package:openote/math/math_inventory.dart';
import 'package:openote/math/math_view.dart';
import 'package:openote/ui/math_bar.dart';

void main() {
  late MathEditor editor;
  late List<String> commits;
  late List<MathExit> exits;

  setUp(() {
    editor = MathEditor.empty();
    commits = [];
    exits = [];
  });

  Future<void> pump(WidgetTester tester, {bool compact = false}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 600,
            child: MathField(
              editor: editor,
              compact: compact,
              textStyle: const TextStyle(fontSize: 20, color: Colors.black),
              onChanged: commits.add,
              onExit: exits.add,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> typeKeys(WidgetTester tester, String s) async {
    for (final ch in s.split('')) {
      // `sendKeyEvent` alone carries no character on some platforms, and the
      // field reads `event.character` on purpose (`^` is Shift+6). This is the
      // path a real keystroke takes.
      await tester.sendKeyDownEvent(_keyFor(ch), character: ch);
      await tester.sendKeyUpEvent(_keyFor(ch));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('typing 1/2 draws a fraction and stores one', (tester) async {
    await pump(tester);
    await typeKeys(tester, '1/2');
    expect(editor.latex, r'\frac{1}{2}');
    expect(commits.last, r'\frac{1}{2}',
        reason: 'the block writes to the model on every change');
    expect(find.byType(MathSourceFallback), findsNothing,
        reason: 'a fraction being typed must never show as source');
  });

  testWidgets('what is on screen is notation, never the LaTeX', (tester) async {
    await pump(tester);
    await typeKeys(tester, '1/2');
    // The one thing the owner's report is about: no backslashes on screen.
    expect(find.textContaining(r'\frac'), findsNothing);
    expect(find.textContaining(r'\'), findsNothing);
  });

  testWidgets('empty boxes are drawn, and the storage never sees them',
      (tester) async {
    await pump(tester);
    final state = tester.state<MathFieldState>(find.byType(MathField));
    state.insertItem(mathItemsById['sqrt']!);
    await tester.pumpAndSettle();
    expect(find.byType(MathSourceFallback), findsNothing);
    expect(editor.latex, r'\sqrt{}');
    expect(commits.last, isNot(contains('square')));
  });

  testWidgets('Escape finishes the equation', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(exits, [MathExit.done]);
  });

  testWidgets('arrowing off the right-hand end asks to leave', (tester) async {
    await pump(tester);
    await typeKeys(tester, 'x');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(exits, [MathExit.right]);
  });

  testWidgets('backspace on an empty equation asks to leave, going left',
      (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(exits, [MathExit.left]);
  });

  testWidgets('backspace unbuilds rather than deleting the lot',
      (tester) async {
    await pump(tester);
    await typeKeys(tester, '1/2');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // out of the den
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(editor.latex, '1/2',
        reason: 'one keypress must never destroy a fraction and its contents');
    expect(exits, isEmpty);
  });

  testWidgets('Tab walks to the next box to fill', (tester) async {
    await pump(tester);
    final state = tester.state<MathFieldState>(find.byType(MathField));
    state.insertItem(mathItemsById['frac']!);
    await tester.pumpAndSettle();
    expect(editor.caretRow.name, 'num');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(editor.caretRow.name, 'den');
  });

  testWidgets('Enter in a display equation adds a row to a piecewise',
      (tester) async {
    await pump(tester);
    final state = tester.state<MathFieldState>(find.byType(MathField));
    state.insertItem(mathItemsById['cases']!);
    await tester.pumpAndSettle();
    final before = editor.latex.split(r'\\').length;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(editor.latex.split(r'\\').length, before + 1);
    expect(exits, isEmpty);
  });

  testWidgets('Enter in an INLINE equation finishes it instead (Q4)',
      (tester) async {
    await pump(tester, compact: true);
    final state = tester.state<MathFieldState>(find.byType(MathField));
    state.insertItem(mathItemsById['cases']!);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(exits, [MathExit.done],
        reason: 'mid-sentence, Enter belongs to the sentence');
  });

  group('the maths bar', () {
    testWidgets('shows the structures and inserts one on tap', (tester) async {
      MathItem? inserted;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MathBar(
            latexMode: false,
            onToggleLatex: () {},
            onInsert: (i) => inserted = i,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      // Every button face draws as notation, not as source.
      expect(find.byType(MathSourceFallback), findsNothing);
      await tester.tap(find.byTooltip('fraction — type 1/2'));
      await tester.pumpAndSettle();
      expect(inserted?.id, 'frac');
    });

    testWidgets('searching in plain words finds the symbol', (tester) async {
      MathItem? inserted;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MathBar(
            latexMode: false,
            onToggleLatex: () {},
            onInsert: (i) => inserted = i,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'not equal');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(inserted?.id, 'neq',
          reason: 'Enter takes the first hit — the fast path for a student '
              'who knows what the thing is called but not where it lives');
    });

    testWidgets('a search with no hits points at the LaTeX view, not a wall',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MathBar(
            latexMode: false,
            onToggleLatex: () {},
            onInsert: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'zzzznothing');
      await tester.pumpAndSettle();
      expect(find.textContaining('LaTeX view can write anything'),
          findsOneWidget);
    });

    testWidgets('the LaTeX fold is one button, and off by default',
        (tester) async {
      var toggled = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MathBar(
            latexMode: false,
            onToggleLatex: () => toggled++,
            onInsert: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('LaTeX'), findsOneWidget);
      await tester.tap(find.text('LaTeX'));
      expect(toggled, 1);
    });
  });
}

/// The logical key that produces a character, for the ones these tests type.
LogicalKeyboardKey _keyFor(String ch) => switch (ch) {
      '/' => LogicalKeyboardKey.slash,
      '^' => LogicalKeyboardKey.digit6,
      '_' => LogicalKeyboardKey.minus,
      '(' => LogicalKeyboardKey.digit9,
      ')' => LogicalKeyboardKey.digit0,
      '+' => LogicalKeyboardKey.equal,
      '=' => LogicalKeyboardKey.equal,
      ' ' => LogicalKeyboardKey.space,
      _ => LogicalKeyboardKey(ch.codeUnitAt(0)),
    };
