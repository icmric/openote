// In-place inline equation editing (plan: v0.20 §B, §C).
//
// The card is dead. An equation in a sentence is edited WHERE IT SITS: the
// span that draws it carries the live EquationEditor while it is being
// written. These tests run the REAL path — a real AppState on a real
// repository, the real TextBlockView, the real session — because the defect
// this replaces was invisible to any narrower harness: the card and the
// paragraph each claimed focus post-frame on every rebuild, so keystrokes
// alternated between the equation and the sentence ("randomly overwriting
// characters, going in weird orders").
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/inline_math_editor.dart';
import 'package:openote/editor/text_block_view.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/math/equation_editor.dart';
import 'package:openote/math/math_field.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Future<AppState> newApp(WidgetTester tester) async {
    late AppState app;
    final tmp = Directory.systemTemp.createTempSync('onote_inplace_');
    late Repository repo;
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await tester.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Maths');
      app = AppState(repo)..notebookId = nb.id;
    });
    return app;
  }

  Block textBlock(String id, String text) => Block(
        id: id,
        type: BlockType.text,
        x: 0,
        y: 0,
        w: 400,
        content: {'text': text, 'autoWidth': false},
      );

  Widget host(AppState app, Block b) => MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child:
                SizedBox(width: 400, child: TextBlockView(block: b, app: app)),
          ),
        ),
      );

  /// Settle without pumpAndSettle — the app's save debounce and the spell
  /// checker both hold timers that would hang it.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> typeChar(WidgetTester tester, String ch) async {
    final key = switch (ch) {
      '+' => LogicalKeyboardKey.equal, // shifted =; the field reads .character
      '^' => LogicalKeyboardKey.digit6,
      _ => LogicalKeyboardKey(ch.codeUnitAt(0) + 0x00000000),
    };
    await tester.sendKeyDownEvent(
        ch.codeUnitAt(0) >= 0x61 && ch.codeUnitAt(0) <= 0x7a
            ? LogicalKeyboardKey(ch.codeUnitAt(0))
            : key,
        character: ch);
    await tester.sendKeyUpEvent(
        ch.codeUnitAt(0) >= 0x61 && ch.codeUnitAt(0) <= 0x7a
            ? LogicalKeyboardKey(ch.codeUnitAt(0))
            : key);
    await settle(tester);
  }

  // The binding checks for pending timers BEFORE tearDowns run, so every
  // test ends by cancelling the app's save debounce explicitly.
  Future<(AppState, Block)> openEditing(WidgetTester tester, String text,
      {String id = 'b1'}) async {
    final app = await newApp(tester);
    final b = textBlock(id, text);
    app.blocks.add(b);
    app.editingBlockId = id;
    await tester.pumpWidget(host(app, b));
    await settle(tester);
    return (app, b);
  }

  /// Open the (first) equation in the sentence by clicking its RIGHT edge.
  ///
  /// A plain `tester.tap` lands dead centre, which a click-position-aware
  /// caret (math_click_position_test.dart) can resolve to either end of a
  /// short equation — these tests are about what happens once you are
  /// editing, not about where a click lands, so they open the same way a
  /// click on the last character always has: caret at the end, ready to
  /// keep typing.
  Future<void> tapToOpen(WidgetTester tester) async {
    final r = tester.getRect(find.byType(InlineMathAtom).first);
    await tester.tapAt(Offset(r.right - 1, r.center.dy));
  }

  testWidgets('clicking an equation edits it IN PLACE — no card, no overlay',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, b) = await openEditing(tester, r'we know $x$ here');

    await tapToOpen(tester);
    await settle(tester);

    expect(find.byType(EquationEditor), findsOneWidget,
        reason: 'the editor mounts inside the paragraph span');
    expect(find.byType(MathField), findsOneWidget);
    // The editor is INSIDE the text block's subtree — not floating above it.
    expect(
        find.descendant(
            of: find.byType(TextBlockView),
            matching: find.byType(EquationEditor)),
        findsOneWidget);
    expect(app.activeSession!.inlineMathFocused, isTrue,
        reason: 'the equation holds the keyboard after one click');
    expect(b.content['text'], r'we know $x$ here',
        reason: 'entering changes nothing');
    app.cancelPendingSave();
  });

  testWidgets('typing lands in the equation, in order, and nowhere else',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, b) = await openEditing(tester, r'we know $x$ here');

    await tapToOpen(tester);
    await settle(tester);

    await typeChar(tester, '+');
    await typeChar(tester, '2');
    await typeChar(tester, 'y');

    expect(b.content['text'], r'we know $x+2y$ here',
        reason: 'three keystrokes, three characters, in order — the focus '
            'war scattered them between the equation and the sentence');
    expect(app.activeSession!.inlineMathFocused, isTrue,
        reason: 'focus must survive every rebuild the keystrokes cause');
    app.cancelPendingSave();
  });

  testWidgets('the host paragraph hides its own caret while the equation '
      'has the keyboard', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, _) = await openEditing(tester, r'we know $x$ here');

    await tapToOpen(tester);
    await settle(tester);

    final tf = tester.widget<TextField>(find.byType(TextField));
    expect(tf.showCursor, isFalse,
        reason: 'two blinking carets — the paragraph\'s and the equation\'s '
            '— is the "weird" the owner reported');
    app.cancelPendingSave();
  });

  testWidgets('Escape finishes: equation kept, caret after it, focus back',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, b) = await openEditing(tester, r'we know $x$ here');

    await tapToOpen(tester);
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);

    expect(find.byType(EquationEditor), findsNothing);
    expect(b.content['text'], r'we know $x$ here');
    expect(app.activeSession!.inlineMathFocused, isFalse);
    final sel = app.activeEditor!.controller.selection;
    expect(sel.baseOffset, r'we know $x$'.length,
        reason: 'the caret lands just after the equation');
    app.cancelPendingSave();
  });

  testWidgets('Alt+= starts an empty equation at the caret — chip, no dollars',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, b) = await openEditing(tester, 'area is ');

    app.activeEditor!.controller.selection =
        const TextSelection.collapsed(offset: 8);
    expect(app.activeSession!.startInlineMath(), isTrue);
    await settle(tester);

    expect(b.content['text'], r'area is $$');
    expect(find.byType(EquationEditor), findsOneWidget,
        reason: 'the editor mounts immediately, in the sentence');
    expect(app.activeSession!.inlineMathFocused, isTrue,
        reason: 'typing must work right off the bat');

    await typeChar(tester, 'b');
    await typeChar(tester, 'h');
    expect(b.content['text'], r'area is $bh$');
    app.cancelPendingSave();
  });

  testWidgets('Alt+= then Escape leaves NOTHING behind — the pair is swept',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, b) = await openEditing(tester, 'area is ');

    app.activeEditor!.controller.selection =
        const TextSelection.collapsed(offset: 8);
    app.activeSession!.startInlineMath();
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);

    expect(b.content['text'], 'area is ',
        reason: r'an abandoned equation must not leave $$ in the note');
    expect(find.byType(EquationEditor), findsNothing);
    app.cancelPendingSave();
  });

  testWidgets('emptying the equation with Backspace keeps the editor mounted',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, b) = await openEditing(tester, r'so $x$ then');

    await tapToOpen(tester);
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await settle(tester);

    expect(b.content['text'], r'so $$ then',
        reason: 'while editing, empty stays as the pair — removing the '
            'dollars would unmount the editor mid-typing');
    expect(find.byType(EquationEditor), findsOneWidget);
    expect(app.activeSession!.inlineMathFocused, isTrue);

    await typeChar(tester, 'y');
    expect(b.content['text'], r'so $y$ then',
        reason: 'and typing again refills the same equation');
    app.cancelPendingSave();
  });

  testWidgets('Backspace at the right edge steps INSIDE, eating nothing',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, b) = await openEditing(tester, r'so $x^2$ then');

    final end = r'so $x^2$'.length;
    app.activeEditor!.controller.selection =
        TextSelection.collapsed(offset: end);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await settle(tester);

    expect(b.content['text'], r'so $x^2$ then',
        reason: 'the closing dollar is a marker, not a character — deleting '
            'it would revert the equation to source');
    expect(find.byType(EquationEditor), findsOneWidget,
        reason: 'Backspace at the edge means "step into the equation"');
    expect(app.activeSession!.inlineMathFocused, isTrue);
    app.cancelPendingSave();
  });

  testWidgets('plain ArrowLeft at the right edge steps inside too',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, _) = await openEditing(tester, r'so $x$ then');

    app.activeEditor!.controller.selection =
        TextSelection.collapsed(offset: r'so $x$'.length);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await settle(tester);

    expect(find.byType(EquationEditor), findsOneWidget);
    expect(app.activeSession!.inlineMathFocused, isTrue);
    app.cancelPendingSave();
  });

  testWidgets('leaving left lands the caret before the equation',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, _) = await openEditing(tester, r'so $x$ then');

    app.activeEditor!.controller.selection =
        TextSelection.collapsed(offset: r'so $x$'.length);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft); // step in, at end
    await settle(tester);
    // x is one atom: one Left reaches the equation's start, one more leaves.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await settle(tester);

    expect(find.byType(EquationEditor), findsNothing);
    expect(app.activeEditor!.controller.selection.baseOffset, 3,
        reason: 'MathExit.left lands just before the opening dollar');
    app.cancelPendingSave();
  });

  testWidgets('a click elsewhere in the paragraph closes the equation '
      'without yanking the caret back', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, b) = await openEditing(tester, r'aa $x$ bb cc dd');

    await tapToOpen(tester);
    await settle(tester);
    expect(app.activeSession!.inlineMathFocused, isTrue);

    // Click on the text well after the equation.
    final field = tester.getTopLeft(find.byType(TextField));
    await tester.tapAt(field + const Offset(120, 8));
    await settle(tester);

    expect(find.byType(EquationEditor), findsNothing,
        reason: 'clicking away commits, like every other editor here');
    expect(b.content['text'], r'aa $x$ bb cc dd');
    app.cancelPendingSave();
  });

  testWidgets('the whole equation survives a paragraph edit on either side',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, b) = await openEditing(tester, r'sum $\frac{1}{2}$ end');

    await tapToOpen(tester);
    await settle(tester);
    await typeChar(tester, '+');
    await typeChar(tester, 'z');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);

    expect(b.content['text'], r'sum $\frac{1}{2}+z$ end',
        reason: 'the words on both sides are untouched by equation edits');
    app.cancelPendingSave();
  });

  testWidgets('tearing the block down with an EMPTY equation open sweeps it '
      'without throwing', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, b) = await openEditing(tester, 'area is ');

    app.activeEditor!.controller.selection =
        const TextSelection.collapsed(offset: 8);
    app.activeSession!.startInlineMath();
    await settle(tester);
    expect(b.content['text'], contains(RegExp(r'\$\$')));

    // Switching page tears the widget down with the equation still open —
    // dispose runs the same one exit path, so the pair must go and nothing
    // may touch a disposed controller.
    app.cancelPendingSave();
    await tester.pumpWidget(const MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: SizedBox(),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    app.cancelPendingSave();
    expect(b.content['text'], 'area is ',
        reason: 'the dispose path swept the abandoned pair');
  });

  group('Draw the graph / Evaluate at a value, from an inline equation', () {
    // Both reach the toolbar through `ActiveMathEditor` exactly the way a
    // BLOCK equation's do (see math_toolbar_test.dart's own end-to-end
    // pair) — but an inline equation follows by TEXT (`fromLatex`), not by
    // id, and its host is the paragraph rather than the equation itself.
    // Nothing above ever drove either closure for a REAL inline session, so
    // these are the first thing that would have caught either wiring being
    // wrong for this half of the app.
    testWidgets('Draw the graph inserts a graph that follows the sentence',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (app, b) = await openEditing(tester, r'we know $y=3x+10$ here');

      await tapToOpen(tester);
      await settle(tester);
      expect(app.activeMath?.drawGraph, isNotNull);

      app.activeMath!.drawGraph!();
      await settle(tester);

      final graphs = app.blocks.where((x) => x.type == BlockType.graph);
      expect(graphs.length, 1);
      expect(graphs.single.content['from'], b.id);
      expect(graphs.single.content['fromLatex'], 'y=3x+10');
      expect(graphs.single.content['latex'], 'y=3x+10');
      app.cancelPendingSave();
    });

    testWidgets(
        'Evaluate at a value inserts a substitute block that follows the '
        'sentence', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (app, b) = await openEditing(tester, r'we know $y=3x+10$ here');

      await tapToOpen(tester);
      await settle(tester);
      expect(app.activeMath?.evaluateAtValue, isNotNull);

      app.activeMath!.evaluateAtValue!();
      await settle(tester);

      final subs = app.blocks.where((x) => x.type == BlockType.substitute);
      expect(subs.length, 1);
      expect(subs.single.content['from'], b.id);
      expect(subs.single.content['fromLatex'], 'y=3x+10');
      expect(subs.single.content['latex'], 'y=3x+10');
      app.cancelPendingSave();
    });
  });
}
