// The in-place session against the world (review round 3, quality findings).
//
// The session used to trust its cached [start, end) anchors across buffer
// rewrites it did not make. Two user-reachable routes were probe-proven to
// corrupt the note: the toolbar's Bold button (wraps the word at the parked
// caret INSIDE the equation's run) and Ctrl+Z (reached the host TextField's
// built-in UndoHistory and restored an older buffer under the open editor).
// The next equation keystroke then wrote the tree at the stale range —
// duplicated maths, eaten words. The rule now: any buffer change the session
// did not make closes the session; every own write re-derives its range from
// the buffer first.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/inline_math_editor.dart';
import 'package:openote/editor/text_block_view.dart';
import 'package:openote/math/equation_editor.dart';
import 'package:openote/math/math_editor.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Future<AppState> newApp(WidgetTester tester) async {
    late AppState app;
    final tmp = Directory.systemTemp.createTempSync('onote_robust_');
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
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child:
                SizedBox(width: 400, child: TextBlockView(block: b, app: app)),
          ),
        ),
      );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> typeChar(WidgetTester tester, String ch) async {
    final key = switch (ch) {
      '+' || '=' => LogicalKeyboardKey.equal,
      _ => LogicalKeyboardKey(ch.codeUnitAt(0)),
    };
    await tester.sendKeyDownEvent(key, character: ch);
    await tester.sendKeyUpEvent(key);
    await settle(tester);
  }

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

  testWidgets('a foreign buffer rewrite CLOSES the session instead of '
      'corrupting the note (the toolbar-Bold route)', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, b) = await openEditing(tester, r'aa $x$ bb cc dd');

    await tester.tap(find.byType(InlineMathAtom));
    await settle(tester);
    expect(app.activeSession!.inlineMathFocused, isTrue);

    // The toolbar's Bold button is NOT gated on math focus: it wraps the word
    // at the parked caret, which sits INSIDE the equation's run. Probe-proven
    // before the fix: the next equation keystroke wrote the tree at the stale
    // range, leaving 'aa $x+$x**$ bb cc dd'.
    app.wrapSelection('**');
    await settle(tester);

    expect(find.byType(EquationEditor), findsNothing,
        reason: 'the session cannot survive a rewrite it did not make — its '
            'anchors and its tree are both lies about the new buffer');

    // Whatever the keystroke does now, the note must remain coherent: exactly
    // one equation, no stranded fragments.
    await typeChar(tester, '2');
    final text = b.content['text'] as String;
    expect(RegExp(r'\$').allMatches(text).length, lessThanOrEqualTo(2),
        reason: 'no stranded dollars: was aa \$x+\$x**\$ bb cc dd before '
            'the fix. Got: $text');
    expect(text, contains('bb cc dd'),
        reason: 'the words after the equation are never eaten');
    app.cancelPendingSave();
  });

  testWidgets('a buffer restored under the open session (the undo route) '
      'closes it and eats nothing', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, b) = await openEditing(tester, r'aa $x$ bb');

    await tester.tap(find.byType(InlineMathAtom));
    await settle(tester);
    await typeChar(tester, '+');
    await typeChar(tester, '2');
    expect(b.content['text'], r'aa $x+2$ bb');

    // Undo restoring an older buffer while the editor is open — the same
    // thing the host TextField's UndoHistory did before Ctrl+Z was claimed.
    app.activeSession!.text = r'aa $x+$ bb';
    await settle(tester);

    expect(find.byType(EquationEditor), findsNothing,
        reason: 'the session closes rather than writing its now-stale tree');
    expect(app.activeSession!.text, r'aa $x+$ bb',
        reason: 'the restored buffer stands — before the fix the next '
            'keystroke wrote x+23 at the stale end and ate the space: '
            r'aa $x+23$bb');
    app.cancelPendingSave();
  });

  testWidgets('entering equation B while empty A is open sweeps A first — '
      'one session, no orphaned pair', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, b) = await openEditing(tester, r'start $y^2$ end');

    // Open an EMPTY equation A before the existing equation B.
    app.activeEditor!.controller.selection =
        const TextSelection.collapsed(offset: 0);
    app.activeSession!.startInlineMath();
    await settle(tester);
    expect(b.content['text'], r'$$ start $y^2$ end');

    // Click B while A is still open and empty.
    await tester.tap(find.byType(InlineMathAtom).last);
    await settle(tester);

    final text = b.content['text'] as String;
    expect(text, r'start $y^2$ end',
        reason: 'A was empty, so its pair is swept on the way into B — '
            r'before the fix the $$ chip stayed in the note for ever');
    expect(find.byType(EquationEditor), findsOneWidget,
        reason: 'and B is open for editing, at its re-based offsets');

    await typeChar(tester, '+');
    expect(b.content['text'], r'start $y^{2}+$ end',
        reason: 'the keystroke lands in B exactly — re-based, not stale');
    app.cancelPendingSave();
  });

  testWidgets('Alt+= mid-word then Escape leaves the word whole',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, b) = await openEditing(tester, 'notebook');

    app.activeEditor!.controller.selection =
        const TextSelection.collapsed(offset: 4);
    app.activeSession!.startInlineMath();
    await settle(tester);
    expect(b.content['text'], r'note$$ book',
        reason: 'mid-word the pair takes a space so the grammar can see it');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(b.content['text'], 'notebook',
        reason: 'the sweep takes its own pad back out — it used to leave '
            '"note book", a permanent edit from an abandoned equation');
    app.cancelPendingSave();
  });

  group('insertSource and the selection (paste correctness)', () {
    test('paste REPLACES the highlight, like every other insert', () {
      final e = MathEditor.empty();
      for (final ch in '1+2'.split('')) {
        e.insertChar(ch);
      }
      e.selectAll();
      expect(e.insertSource(r'\pi'), InsertOutcome.placed);
      // The trailing space is the TeX word-command separator, not noise.
      expect(e.latex.trim(), r'\pi',
          reason: 'before the fix this was 1+2\\pi with the highlight '
              'spanning everything — one more keystroke wiped the equation');
      expect(e.hasSelection, isFalse);
    });

    test('LaTeX the tree cannot hold is REFUSED, changing nothing', () {
      final e = MathEditor.empty();
      for (final ch in 'x+1'.split('')) {
        e.insertChar(ch);
      }
      e.selectAll();
      expect(e.insertSource(r'\zzznotacommand{q}'), InsertOutcome.refused);
      expect(e.latex, 'x+1',
          reason: 'the old fallback escaped it into TYPESET backslashes — '
              'the clipboard content silently rewritten, no way back');
      expect(e.hasSelection, isTrue,
          reason: 'a refused paste is a no-op, the highlight included');
    });

    test('plain text is never refused', () {
      final e = MathEditor.empty();
      expect(e.insertSource('3x-7'), isNot(InsertOutcome.refused));
      expect(e.latex, isNotEmpty);
    });
  });

  test('caret-only movement commits NOTHING to the host', () {
    // Unit-level pin of the mechanism; the damage it caused was host-side
    // (undo snapshots per arrow key, redo destroyed by navigation alone).
    final e = MathEditor.empty();
    for (final ch in 'x+1'.split('')) {
      e.insertChar(ch);
    }
    final before = e.latex;
    e.placeAtStart();
    e.moveRight();
    e.moveRight();
    e.placeAtEnd();
    expect(e.latex, before, reason: 'movement never changes the projection — '
        'which is what lets MathField compare and skip the commit');
  });
}
