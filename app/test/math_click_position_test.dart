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
import 'package:openote/l10n/l10n.dart';
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
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
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
        'opening an equation by clicking it never flashes a caret at the '
        'plain default before it resolves', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The click resolves a frame after the equation mounts (the hit table
      // is measured offstage), and the editor's own plain default in the
      // meantime is the END — so the very first rendered frame used to show
      // a caret there, one frame before it jumped to where the click
      // actually was: "it moves the cursor to the end then to the correct
      // position."
      final b = mathBlock('12345');
      await mount(tester, b);

      final mathRect = tester.getRect(find.byType(OnoteMath));
      await tester.tapAt(Offset(mathRect.left + 3, mathRect.center.dy));
      // Exactly ONE pump: the field's first build, with the click not yet
      // resolved — the frame that used to show the wrong-end caret.
      await tester.pump();

      final firstFrame =
          tester.widget<OnoteMath>(find.byType(OnoteMath).first);
      expect(firstFrame.tex, isNot(contains(r'\rule')),
          reason: 'no caret at all is better than one flashed at a place '
              'nobody clicked and nobody meant');

      await resolve(tester);
      final resolved =
          tester.widget<OnoteMath>(find.byType(OnoteMath).first);
      expect(resolved.tex, contains(r'\rule'),
          reason: 'the caret must still land, once the click resolves');
      await settle(tester);
    });

    testWidgets(
        'clicking a closed equation in the MIDDLE opens it with the caret '
        'in the middle, not snapped to either end', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // Nine digits: a click dead centre must land somewhere around index
      // 4-5, not at 0 or 9 — the boundary-only assertions above would also
      // pass for a implementation that silently always opened at one fixed
      // end, so this is the one that actually tells the two apart.
      final b = mathBlock('123456789');
      await mount(tester, b);

      final mathRect = tester.getRect(find.byType(OnoteMath));
      await tester.tapAt(Offset(mathRect.center.dx, mathRect.center.dy));
      await resolve(tester);

      expect(app.editingBlockId, 'b1');
      final field = tester.widget<MathField>(find.byType(MathField));
      expect(field.editor.caretIndex, inInclusiveRange(2, 7),
          reason: 'a click dead centre of nine digits must land somewhere '
              'in the middle of them, not snapped to either end');
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
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
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
        'the VERY FIRST click, on a paragraph that was not being edited '
        'yet, still opens its equation where you clicked', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The realistic sequence: the note is open, nothing is selected, and
      // the student's first-ever click on the page happens to land on an
      // inline equation mid-sentence. Unlike every test above, the block is
      // NOT already in edit mode — so this goes through the real BlockView,
      // whose OWN tap turns "not editing" into "editing", not through
      // InlineMathAtom's tap at all (that widget does not even exist until
      // AFTER this click, since a closed block draws read-only Markdown).
      final b = Block(
        id: 'b1',
        type: BlockType.text,
        x: 0,
        y: 0,
        w: 400,
        content: {'text': r'we know $123456789$ here', 'autoWidth': false},
      );
      app.blocks.add(b);
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
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
      expect(app.editingBlockId, isNot('b1'),
          reason: 'the block must start out NOT being edited for this to '
              'be the scenario it claims to be');

      final atomRect = tester.getRect(find.byType(InlineMathAtom));
      await tester.tapAt(Offset(atomRect.center.dx, atomRect.center.dy));
      await resolve(tester);
      await resolve(tester); // the block's own edit-mode transition, +1 frame

      expect(app.editingBlockId, 'b1',
          reason: 'the click must have entered the paragraph for editing');
      expect(find.byType(MathField), findsOneWidget,
          reason: 'and the click landed ON the equation, so it must have '
              'opened it too — not just parked the host caret beside it');
      final field = tester.widget<MathField>(find.byType(MathField));
      expect(field.editor.caretIndex, inInclusiveRange(2, 7),
          reason: 'a click dead centre of nine digits must land in the '
              'middle of them, even on the very first click');
      await settle(tester);
    });

    testWidgets(
        'the VERY FIRST click on an equation that ENDS its line also opens '
        'it where you clicked, not always at a fixed end', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The other half of the FIRST-click path: an equation with nothing
      // after it goes through `_enterMathOnTapAtLineEnd`'s own, narrower
      // route rather than `_enterMathOnFirstClickInside`'s — and it used to
      // ignore the click position entirely, opening at the end regardless
      // of where on the equation you clicked. This is very likely the
      // owner's actual, exact repro: an equation is very often the last
      // thing on its line ("solve for x: $123456789$").
      final b = Block(
        id: 'b1',
        type: BlockType.text,
        x: 0,
        y: 0,
        w: 400,
        content: {'text': r'solve for x: $123456789$', 'autoWidth': false},
      );
      app.blocks.add(b);
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
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
      expect(app.editingBlockId, isNot('b1'));

      final atomRect = tester.getRect(find.byType(InlineMathAtom));
      await tester.tapAt(Offset(atomRect.left + 2, atomRect.center.dy));
      await resolve(tester);
      await resolve(tester);

      expect(app.editingBlockId, 'b1');
      expect(find.byType(MathField), findsOneWidget,
          reason: 'a trailing equation clicked for the first time must open');
      final field = tester.widget<MathField>(find.byType(MathField));
      expect(field.editor.caretIndex, lessThanOrEqualTo(1),
          reason: 'a click at the far left of a trailing equation, clicked '
              'for the very first time, belongs at the start of it — before '
              'this fix it always opened at the END no matter where you '
              'clicked, since _enterMathOnTapAtLineEnd never carried the '
              'click\'s position at all');
      await settle(tester);
    });

    testWidgets(
        'clicking a closed equation in the MIDDLE opens it with the caret '
        'in the middle, not snapped to either end', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // Nine digits: a click dead centre must land somewhere around index
      // 4-5, not at 0 or 9 — the boundary-only assertion above would also
      // pass for an implementation that silently always opened at one fixed
      // end, so this is the one that actually tells the two apart.
      final b = para(r'we know $123456789$ here');
      app.editingBlockId = 'b1';
      await mount(tester, b);

      final atomRect = tester.getRect(find.byType(InlineMathAtom));
      await tester.tapAt(Offset(atomRect.center.dx, atomRect.center.dy));
      await resolve(tester);

      final field = tester.widget<MathField>(find.byType(MathField));
      expect(field.editor.caretIndex, inInclusiveRange(2, 7),
          reason: 'a click dead centre of nine digits must land somewhere '
              'in the middle of them, not snapped to either end');
      await settle(tester);
    });

    testWidgets(
        'the same MIDDLE click, through the real canvas at 1.6x zoom and '
        'panned off (0, 0), still lands in the middle', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The owner's report was specific to inline equations reached the
      // ordinary way: on the CANVAS, not through a bare TextBlockView — so
      // this goes through the real BlockView, at a non-1:1 zoom and a block
      // that does not sit at the canvas origin, to rule out the pan/zoom
      // Transform as the source of any coordinate mismatch.
      final b = Block(
        id: 'b1',
        type: BlockType.text,
        x: 137,
        y: 82,
        w: 400,
        content: {'text': r'we know $123456789$ here', 'autoWidth': false},
      );
      app.blocks.add(b);
      app.editingBlockId = 'b1';
      app.canvas.scale = 1.6;
      app.canvas.offset = const Offset(53, 19);
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
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
      await tester.pump(const Duration(milliseconds: 20));

      final atomRect = tester.getRect(find.byType(InlineMathAtom));
      await tester.tapAt(Offset(atomRect.center.dx, atomRect.center.dy));
      await resolve(tester);

      expect(find.byType(MathField), findsOneWidget,
          reason: 'the click must have opened the equation at all');
      final field = tester.widget<MathField>(find.byType(MathField));
      expect(field.editor.caretIndex, inInclusiveRange(2, 7),
          reason: 'zoomed and panned, a click dead centre of nine digits '
              'must still land in the middle, not snapped to either end');
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
