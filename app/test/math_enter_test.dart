// Getting INTO an equation, and knowing you are in one (v0.24, owner).
//
// Two complaints, one theme: the app knew perfectly well that the caret was
// at an equation and did not act on it, and once you were in an empty one
// there was almost nothing on screen to say so.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/block_view.dart';
import 'package:openote/editor/inline_math_editor.dart';
import 'package:openote/editor/text_block_view.dart';
import 'package:openote/math/equation_editor.dart';
import 'package:openote/math/math_editor.dart';
import 'package:openote/math/math_tree.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_enter_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('E');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
  });

  tearDown(() {
    AppState.syncLogEnabled = true;
    if (!haveSqlite) return;
    app.cancelPendingSave();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Block para(String text) {
    final b = Block(
        id: 'b1',
        type: BlockType.text,
        x: 0,
        y: 0,
        w: 400,
        content: {'text': text, 'autoWidth': false});
    app.blocks.add(b);
    return b;
  }

  Future<void> mount(WidgetTester tester, Block b) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: app,
          builder: (_, __) =>
              SizedBox(width: 400, child: TextBlockView(block: b, app: app)),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
  }

  Future<void> settle(WidgetTester tester) async {
    app.editingBlockId = null;
    await tester.pumpWidget(const SizedBox());
    app.cancelPendingSave();
    await tester.pump(const Duration(seconds: 2));
  }

  group('clicking past an equation that ends the line', () {
    // The owner: "clicking on the end of a text box doesnt at the moment
    // automatically put me into the maths editor." ArrowLeft from that exact
    // caret offset had always stepped inside; the click did not.
    testWidgets('steps into it', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final b = para(r'the answer is $y=3x$');
      app.editingBlockId = 'b1';
      await mount(tester, b);

      final atom = tester.getRect(find.byType(InlineMathAtom));
      await tester.tapAt(Offset(atom.right + 40, atom.center.dy));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.byType(EquationEditor), findsOneWidget,
          reason: 'the click had nowhere else it could have meant');
      await settle(tester);
    });

    testWidgets('and below the last line does too', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final b = para(r'the answer is $y=3x$');
      app.editingBlockId = 'b1';
      await mount(tester, b);

      final atom = tester.getRect(find.byType(InlineMathAtom));
      await tester.tapAt(Offset(atom.right + 40, atom.bottom + 6));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.byType(EquationEditor), findsOneWidget);
      await settle(tester);
    });

    testWidgets('but NOT when there are words after it', (tester) async {
      // This is what keeps ordinary text after an equation typable: the seam
      // between `$y=3x$` and ` and more` is a real caret position and has to
      // stay one.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final b = para(r'the answer is $y=3x$ and more');
      app.editingBlockId = 'b1';
      await mount(tester, b);

      final atom = tester.getRect(find.byType(InlineMathAtom));
      await tester.tapAt(Offset(atom.right + 3, atom.center.dy));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.byType(EquationEditor), findsNothing);
      await settle(tester);
    });

    testWidgets('and a click in ordinary text is still just a click',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final b = para(r'the answer is $y=3x$');
      app.editingBlockId = 'b1';
      await mount(tester, b);

      final atom = tester.getRect(find.byType(InlineMathAtom));
      await tester.tapAt(Offset(atom.left - 30, atom.center.dy));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.byType(EquationEditor), findsNothing);
      await settle(tester);
    });

    testWidgets('the FIRST click into a block that was not being edited',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final b = para(r'the answer is $y=3x$');
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: app,
            builder: (_, __) => Stack(
              children: [
                BlockView(block: b, app: app, controller: app.canvas)
              ],
            ),
          ),
        ),
      ));
      await tester.pump();

      final rect = tester.getRect(find.byType(BlockView));
      await tester.tapAt(Offset(rect.right - 24, rect.center.dy));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));

      expect(app.editingBlockId, 'b1');
      expect(find.byType(EquationEditor), findsOneWidget);
      await settle(tester);
    });
  });

  group('an empty equation you are inside', () {
    // The owner: "when there is an empty equation and im in the edit mode for
    // it, the cursor is off to the side of the box so it isnt intuitive or
    // clear that its actually in edit mode for it." It was literally beside
    // it: a caret atom, then a box atom, drawn one after the other.
    const ctx = MathTexCtx(
        decorate: true, accent: '#2563EB', tint: '#DBEAFE', dim: '#94A3B8');

    test('draws the caret INSIDE the box, as one thing', () {
      final e = MathEditor.empty();
      final tex = e.renderTex(ctx);
      expect(tex, ctx.caretSlotTex);
      expect(tex, startsWith(r'\fcolorbox'));
      expect(tex, contains(r'\rule'), reason: 'the caret is in there');
      expect(tex.indexOf(r'\rule'), greaterThan(tex.indexOf(r'\fcolorbox')),
          reason: 'INSIDE the box, not before it');
    });

    test('and an empty one nobody is in draws nothing at all', () {
      final e = MathEditor.empty();
      expect(e.renderTex(const MathTexCtx(decorate: true)), isNotEmpty);
      // No caret row => not being edited.
      final idle = rowToTex(
          e.root,
          const MathTexCtx(
              decorate: true, accent: '#2563EB', tint: '#DBEAFE'));
      expect(idle, isEmpty);
    });

    test('every empty slot says the same thing', () {
      // A fraction's denominator and a root's index learned it first; the
      // equation's own row now agrees with them.
      final f = MathEditor.empty()..insertSource(r'\frac{1}{}');
      f.tab();
      expect(f.renderTex(ctx), contains(ctx.caretSlotTex));

      final g = MathEditor.empty()..insertSource(r'\sqrt[]{2}');
      g.tab();
      expect(g.renderTex(ctx), contains(ctx.caretSlotTex));
    });

    test('the box does not change width when you step into it', () {
      // `\phantom{\square}` is what holds it: a slot that grew on entry would
      // shove the rest of the sentence along as the caret moved through it.
      expect(ctx.caretSlotTex, contains(r'\phantom{\square}'));
      expect(ctx.activeSlotTex, contains(r'\square'));
    });
  });
}
