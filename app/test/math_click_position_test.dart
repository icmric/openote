// Clicking with the mouse to get INTO an equation, and to move around once
// you are (owner, verbatim): "there has been an issue for a while where i
// cant navigate in maths with my mouse. like clicking into an equation just
// puts me at [a fixed spot] every time, and even once I'm in clicking in it
// does not actually move me there, nothing happens."
//
// Two separate defects, both reproduced here through the REAL widgets:
//
//  (a) Opening an equation for editing — a click on a closed block, or on an
//      `InlineMathAtom` in a sentence — always placed the caret at a fixed
//      end/start regardless of where the click landed. The hit-testing
//      itself (`MathHitTable`, proven in math_pointer_test.dart) was never
//      wrong; nothing at either "open for edit" call site ever asked it.
//
//  (b) A SECOND click, once the equation is already open, is meant to move
//      the caret exactly like the first one did — this proves it does.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/block_view.dart';
import 'package:openote/editor/inline_math_editor.dart';
import 'package:openote/editor/text_block_view.dart';
import 'package:openote/math/math_field.dart';
import 'package:openote/math/math_view.dart';
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
    tmp = Directory.systemTemp.createTempSync('onote_mathclick_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('C');
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

  Future<void> settle(WidgetTester tester) async {
    app.editingBlockId = null;
    await tester.pumpWidget(const SizedBox());
    app.cancelPendingSave();
    await tester.pump(const Duration(seconds: 2));
  }

  /// The hit table is measured offstage a frame after the gesture that asked
  /// for it — every click here is followed by this, never a single pump.
  Future<void> resolve(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();
    await tester.pump();
  }

  group('a math BLOCK', () {
    Block mathBlock(String latex) {
      final b = Block(
          id: 'b1',
          type: BlockType.math,
          x: 0,
          y: 0,
          w: 420,
          content: {'latex': latex, 'display': true});
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
            builder: (_, __) => Stack(
              children: [BlockView(block: b, app: app, controller: app.canvas)],
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets(
        'clicking a closed equation opens it with the caret where you '
        'clicked, not always at the end', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final b = mathBlock('12345');
      await mount(tester, b);

      // Captured BEFORE the click opens the editor — the read-mode display
      // and the field draw the same glyphs in very nearly the same place.
      final mathRect = tester.getRect(find.byType(OnoteMath));
      await tester.tapAt(Offset(mathRect.left + 3, mathRect.center.dy));
      await resolve(tester);

      expect(app.editingBlockId, 'b1');
      final field = tester.widget<MathField>(find.byType(MathField));
      expect(field.editor.caretIndex, lessThanOrEqualTo(1),
          reason: 'a click at the far left of the equation belongs at the '
              'start of it — it used to jump to the end (or start) no '
              'matter where it landed');
      await settle(tester);
    });

    testWidgets(
        'a second click, once the equation is already open, moves the '
        'caret there too', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final b = mathBlock('12345');
      app.editingBlockId = 'b1';
      await mount(tester, b);
      await tester.pump();

      // Pin the caret to a KNOWN position with the keyboard first, so the
      // click that follows is the only thing that can move it — isolating
      // this from whatever the open itself did.
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      var field = tester.widget<MathField>(find.byType(MathField));
      expect(field.editor.caretIndex, 5, reason: 'End really did move it');

      final fieldRect = tester.getRect(find.byType(MathField));
      await tester.tapAt(Offset(fieldRect.left + 2, fieldRect.center.dy));
      await resolve(tester);

      field = tester.widget<MathField>(find.byType(MathField));
      expect(field.editor.caretIndex, lessThanOrEqualTo(1),
          reason: 'reported: "even once I\'m in clicking in it does not '
              'actually move me there, nothing happens"');
      await settle(tester);
    });
  });

  group('an inline equation', () {
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

    testWidgets(
        'clicking a closed equation opens it with the caret where you '
        'clicked, not always at the end', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final b = para(r'we know $12345$ here');
      app.editingBlockId = 'b1';
      await mount(tester, b);

      final atomRect = tester.getRect(find.byType(InlineMathAtom));
      await tester.tapAt(Offset(atomRect.left + 2, atomRect.center.dy));
      await resolve(tester);

      final field = tester.widget<MathField>(find.byType(MathField));
      expect(field.editor.caretIndex, lessThanOrEqualTo(1),
          reason: 'a click at the far left of the equation belongs at the '
              'start of it — for years it landed at a fixed spot no matter '
              'where it landed');
      await settle(tester);
    });

    testWidgets(
        'a second click, once the equation is already open, moves the '
        'caret there too', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final b = para(r'we know $12345$ here');
      app.editingBlockId = 'b1';
      await mount(tester, b);

      await tester.tap(find.byType(InlineMathAtom));
      await resolve(tester);

      // Pin the caret to a KNOWN position with the keyboard first, so the
      // click that follows is the only thing that can move it — isolating
      // this from whatever the open itself did.
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      var field = tester.widget<MathField>(find.byType(MathField));
      expect(field.editor.caretIndex, 5, reason: 'End really did move it');

      final fieldRect = tester.getRect(find.byType(MathField));
      await tester.tapAt(Offset(fieldRect.left + 2, fieldRect.center.dy));
      await resolve(tester);

      field = tester.widget<MathField>(find.byType(MathField));
      expect(field.editor.caretIndex, lessThanOrEqualTo(1),
          reason: 'reported: "even once I\'m in clicking in it does not '
              'actually move me there, nothing happens"');
      await settle(tester);
    });
  });
}
