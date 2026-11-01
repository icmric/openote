// The lasso selects what is inside it, whatever that is.
//
// The owner: *"The select lasso works great on ink however it doesnt seem to
// select other boxes, please investigate this as id really like that to work.
// In one case it did select a box but it made the ink move really slowly and
// glitchy, and the box itself never moved."*
//
// It asked ink and nothing else. Handwriting is asked by its points, because a
// stroke is a line and its bounding box is mostly not the stroke; everything
// else is asked by its rectangle, by area, which is the rule the marquee
// already uses — and the reason it has to be area rather than "a corner is
// in" is a loop drawn INSIDE a slide, which must not pick the slide up.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/app.dart';
import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  group('the rule, without a canvas', () {
    List<Offset> loop(Rect r) => [
          r.topLeft,
          r.topRight,
          r.bottomRight,
          r.bottomLeft,
        ];

    test('A LOOP ROUND A BOX CATCHES IT', () {
      expect(
          lassoCatches(loop(const Rect.fromLTWH(0, 0, 400, 400)),
              const Rect.fromLTWH(100, 100, 120, 60)),
          isTrue);
    });

    test('AND A LOOP DRAWN INSIDE ONE DOES NOT', () {
      // The slide case: a small loop well within a big block. "A corner is
      // inside the loop" and "the centre is inside the loop" both get this
      // wrong, and getting it wrong means the page you are annotating comes
      // with you.
      expect(
          lassoCatches(loop(const Rect.fromLTWH(200, 200, 60, 60)),
              const Rect.fromLTWH(0, 0, 800, 600)),
          isFalse);
    });

    test('half in is in, a sliver is not', () {
      const box = Rect.fromLTWH(100, 100, 100, 100);
      // Three quarters of the box.
      expect(lassoCatches(loop(const Rect.fromLTWH(50, 50, 125, 125)), box),
          isTrue);
      // A corner of it.
      expect(lassoCatches(loop(const Rect.fromLTWH(50, 50, 70, 70)), box),
          isFalse);
    });

    test('a loop that is not a loop catches nothing', () {
      expect(lassoCatches(const [Offset.zero, Offset(10, 10)],
              const Rect.fromLTWH(0, 0, 5, 5)),
          isFalse);
    });
  });

  group('on the canvas', () {
    late Directory tmp;
    late Repository repo;
    late AppState app;

    setUp(() {
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_lasso_');
    });

    tearDown(() {
      AppState.syncLogEnabled = true;
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<void> openPage(WidgetTester t) async {
      await t.runAsync(() async {
        repo = await Repository.openAt(tmp);
        final nb = await repo.createNotebook('Lasso');
        app = AppState(repo)..notebookId = nb.id;
        app.reloadNodes();
        await app.selectPage(
            app.nodes.where((n) => n.kind == NodeKind.page).first.id);
      });
      await t.pumpWidget(testApp(Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: ListenableBuilder(
            listenable: app,
            builder: (_, __) => PageCanvas(state: app),
          ),
        ),
      )));
      await t.pump();
      await t.pump();
    }

    Future<void> drag(WidgetTester t, List<Offset> path,
        {PointerDeviceKind kind = PointerDeviceKind.stylus}) async {
      await t.pump();
      final g = await t.startGesture(path.first, kind: kind);
      for (final pt in path.skip(1)) {
        await g.moveTo(pt);
        await t.pump();
      }
      await g.up();
      await t.pump();
      app.cancelPendingSave();
    }

    /// A loop round [r] in page space, sampled along its sides the way a hand
    /// draws one.
    List<Offset> loopAround(Rect r) {
      final corners = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
      final out = <Offset>[];
      for (var i = 0; i < corners.length; i++) {
        final a = corners[i], b = corners[(i + 1) % corners.length];
        for (var s = 0; s < 4; s++) {
          out.add(app.canvas.pageToScreen(Offset.lerp(a, b, s / 4)!));
        }
      }
      out.add(app.canvas.pageToScreen(corners.first));
      return out;
    }

    Future<Block> aStroke(WidgetTester t, Offset from, Offset to) async {
      app.setTool(Tool.pen);
      await drag(t, [from, Offset.lerp(from, to, .5)!, to]);
      return app.blocks.lastWhere((b) => b.type == BlockType.ink);
    }

    testWidgets('A LOOP ROUND A BOX AND A STROKE TAKES BOTH', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await openPage(t);
      final ink = await aStroke(t, const Offset(200, 200), const Offset(250, 215));
      final box = app.addBlock(Block(
          type: BlockType.text,
          x: 300,
          y: 300,
          w: 160,
          h: 80,
          content: {'text': 'hello'}));
      app.select(null);
      app.setTool(Tool.lasso);

      // Round everything on the page, in page space.
      final all = app.blockRect(ink).expandToInclude(app.blockRect(box));
      await drag(t, loopAround(all.inflate(30)));

      expect(app.selectedIds, contains(ink.id));
      expect(app.selectedIds, contains(box.id),
          reason: 'the box was inside the loop too');
    });

    testWidgets('AND DRAGS THE BOX WITH THE INK', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await openPage(t);
      final ink = await aStroke(t, const Offset(200, 200), const Offset(250, 215));
      final box = app.addBlock(Block(
          type: BlockType.text,
          x: 300,
          y: 300,
          w: 160,
          h: 80,
          content: {'text': 'hello'}));
      app.selectMany([ink.id, box.id]);
      // Off, so the answer is the drag rather than the nearest grid line: a
      // box is snapped when it is put down and handwriting is not, and this
      // test is about whether the box moved at all.
      app.toggleSnap();
      final inkX = ink.x, boxX = box.x, boxY = box.y;

      // From inside the selection, which is how the pen moves it now. The pen
      // arrives by hovering rather than by being chosen, which is the half of
      // `setTool` that keeps a selection — being handed the tool is not a
      // decision to drop what is selected.
      app.setTool(Tool.pen, automatic: true);
      final at = app.canvas.pageToScreen(const Offset(330, 330));
      await drag(t, [at, at + const Offset(20, 10), at + const Offset(40, 20)]);

      final moved = 40 / app.canvas.scale;
      expect(app.blocks.firstWhere((b) => b.id == box.id).x,
          closeTo(boxX + moved, 1.5),
          reason: 'the box moved, which is the half that was reported broken');
      expect(app.blocks.firstWhere((b) => b.id == box.id).y,
          closeTo(boxY + 20 / app.canvas.scale, 1.5));
      expect(app.blocks.firstWhere((b) => b.id == ink.id).x,
          closeTo(inkX + moved, 1.5), reason: 'and so did the ink, together');
    });

    testWidgets('a locked slide under the loop is not caught', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await openPage(t);
      // Small, and WELL INSIDE the loop, so that the only thing keeping it
      // out of the selection is that it is locked. A page-sized slide would
      // be left out by the area rule above and prove nothing about this one.
      // A text box rather than a picture only because a picture with no
      // bytes behind it draws a placeholder this fixture has no room for.
      // The rule under test is the LOCK, which is a block's business whatever
      // type it is.
      final slide = app.addBlock(Block(
          type: BlockType.text,
          x: 300,
          y: 180,
          w: 120,
          h: 80,
          content: {'text': 'slide', 'locked': true}));
      final ink = await aStroke(t, const Offset(200, 200), const Offset(250, 215));
      app.select(null);
      app.setTool(Tool.lasso);

      final all =
          app.blockRect(ink).expandToInclude(app.blockRect(slide)).inflate(30);
      expect(lassoCatches(loopAround(all).map(app.canvas.screenToPage).toList(),
              app.blockRect(slide)),
          isTrue,
          reason: 'the loop really is round it, so the only reason to leave '
              'it out is the lock');
      await drag(t, loopAround(all));

      expect(app.selectedIds, contains(ink.id));
      expect(app.selectedIds, isNot(contains(slide.id)),
          reason: 'the page the notes are drawn on is not one of the notes');
    });

    testWidgets('ONE LASSOED STROKE STILL OFFERS A DELETE', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await openPage(t);
      final ink = await aStroke(t, const Offset(200, 200), const Offset(250, 215));
      app.select(null);
      app.setTool(Tool.lasso);

      await drag(t, loopAround(app.blockRect(ink).inflate(30)));

      expect(app.selectedIds, [ink.id]);
      expect(app.showSelectionDelete, isTrue,
          reason: 'painted ink has no move bar, so it has no cross either');
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      await t.tap(find.byIcon(Icons.delete_outline));
      await t.pump();
      expect(app.blocks.where((b) => b.type == BlockType.ink), isEmpty);
      app.cancelPendingSave();
    });

    testWidgets('but never with the eraser in hand', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await openPage(t);
      final ink = await aStroke(t, const Offset(200, 200), const Offset(250, 215));
      app.selectMany([ink.id]);
      app.setTool(Tool.eraser, automatic: true);
      await t.pump();

      expect(app.showSelectionDelete, isFalse,
          reason: 'the eraser takes things away by pointing at them, and a '
              'button floating in the way of the pointer is worse than no '
              'button');
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      app.cancelPendingSave();
    });

    testWidgets('and so does one box with a pen in hand', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await openPage(t);
      final box = app.addBlock(Block(
          type: BlockType.text,
          x: 300,
          y: 300,
          w: 160,
          h: 80,
          content: {'text': 'hello'}));
      app.selectMany([box.id]);
      // A block shows no chrome of its own while a drawing tool is held, so
      // without this there is nothing on screen that deletes it.
      app.setTool(Tool.pen, automatic: true);
      await t.pump();

      expect(app.showSelectionDelete, isTrue);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      app.cancelPendingSave();
    });
  });
}
