// A pinch is a pinch even with a finger on a box, and it holds one point.
//
// The owner, after the first round of touch work: *"zooming in and out is
// still not great. My guess is that this is due to it getting confused with
// multiple inputs and just registering one or the other as it jumps all over
// the place and while it does zoom it does not zoom clearly or well. It seems
// to work better when i try to zoom quicker which is interesting."*
//
// Both halves of that, and the guess was right.
//
// 1. A block claims its pointers so the canvas keeps its hands off that
//    gesture, and the canvas read the claim BEFORE recording the touch — so a
//    pinch with one finger on a box was never a pinch. The canvas saw one
//    finger and panned with it; the box saw its own and panned with that. Two
//    navigations, fighting. A box is most of a page, so this is the ordinary
//    case.
//
// 2. `zoomTo` takes its anchor from whatever is under the focal point at that
//    moment, which for a pinch changes identity on every sample as the
//    fingers move. The page therefore did not travel with the fingers while
//    the zoom centre wandered, and `clampToPage` fed the wander into the next
//    sample's anchor. Fewer samples meant less wander, which is exactly "it
//    works better when I zoom quicker".
import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/canvas_controller.dart';
import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  group('one anchor, in the controller', () {
    late CanvasController c;

    setUp(() {
      c = CanvasController()
        ..viewport = const Size(800, 600)
        ..pageSize = const Size(2000, 2600);
    });

    tearDown(() => c.dispose());

    test('the anchor stays under the fingers while they also travel', () {
      // Fingers spreading AND sliding: both halves come out of the same two
      // numbers, so the page zooms about the point it started on and follows
      // the fingers at the same time.
      c.zoomTo(const Offset(400, 300), 1.0);
      final anchor = c.screenToPage(const Offset(400, 300));

      c.zoomAnchored(const Offset(500, 360), anchor, 2.0);
      expect(c.scale, 2.0);
      expect(c.pageToScreen(anchor).dx, closeTo(500, 0.01));
      expect(c.pageToScreen(anchor).dy, closeTo(360, 0.01));
    });

    test('a sample is a pure function of the fingers, not of the last one',
        () {
      // Ten samples or one, the same fingers give the same view — which is
      // what "zooms clearly" means and why pinching slowly used to be worse.
      c.zoomTo(const Offset(400, 300), 1.0);
      final anchor = c.screenToPage(const Offset(400, 300));
      c.zoomAnchored(const Offset(430, 330), anchor, 2.0);
      final once = (c.scale, c.offset);

      c.zoomTo(const Offset(400, 300), 1.0);
      for (var i = 1; i <= 10; i++) {
        c.zoomAnchored(Offset(400 + 3.0 * i, 300 + 3.0 * i), anchor,
            1.0 + 1.0 * i / 10);
      }
      expect(c.scale, closeTo(once.$1, 0.0001));
      expect((c.offset - once.$2).distance, lessThan(0.01));
    });

    test('two fingers still pan at the zoom limit', () {
      // `zoomTo` returned without moving anything when the scale could not
      // change, so a pinch at full zoom froze the page under the fingers.
      c.zoomTo(const Offset(400, 300), CanvasController.maxScale);
      final anchor = c.screenToPage(const Offset(400, 300));
      final before = c.offset;
      c.zoomAnchored(const Offset(300, 300), anchor, CanvasController.maxScale * 4);
      expect(c.scale, CanvasController.maxScale, reason: 'still clamped');
      expect(c.offset, isNot(before), reason: 'but the page moved with them');
    });

    test('NEGATIVE CONTROL: zoomTo is unchanged for wheel and buttons', () {
      c.zoomTo(const Offset(400, 300), 1.0);
      final under = c.screenToPage(const Offset(300, 250));
      c.zoomTo(const Offset(300, 250), 2.0);
      expect(c.scale, 2.0);
      expect(c.screenToPage(const Offset(300, 250)).dx, closeTo(under.dx, 0.01));
    });
  });

  group('a finger on a box', () {
    late Directory tmp;
    late Repository repo;
    late AppState app;
    late Block box;

    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_pinchbox_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('P');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      await app
          .selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
      // A box covering most of the viewport, which is the situation: there is
      // nowhere to put two fingers that is not on it.
      box = Block(
          type: BlockType.text,
          x: 40,
          y: 40,
          w: 700,
          h: 500,
          content: {'text': 'a page of notes', 'autoWidth': false});
      app.addBlock(box, recordUndo: false);
      app.select(null);
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

    Future<void> pump(WidgetTester t) async {
      await t.pumpWidget(MaterialApp(
        localizationsDelegates: kOnoteLocalizations,
        supportedLocales: kOnoteLocales,
        home: Scaffold(
          body:
              SizedBox(width: 800, height: 600, child: PageCanvas(state: app)),
        ),
      ));
      await t.pump();
      await t.pump();
    }

    /// Two fingers spreading from [a] and [b] by [by] each, outwards.
    Future<void> spread(WidgetTester t, Offset a, Offset b, double by) async {
      final g1 = await t.startGesture(a, kind: PointerDeviceKind.touch);
      final g2 = await t.startGesture(b, kind: PointerDeviceKind.touch);
      final dir = (b - a) / (b - a).distance;
      for (var i = 0; i < 8; i++) {
        await g1.moveBy(-dir * (by / 8));
        await g2.moveBy(dir * (by / 8));
        await t.pump();
      }
      await g1.up();
      await g2.up();
      await t.pump();
    }

    testWidgets('two fingers ON the box zoom the page', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pump(t);
      final was = app.canvas.scale;
      final boxWas = Offset(box.x, box.y);

      // Both fingers land on the box, which claims its pointers.
      await spread(t, const Offset(300, 300), const Offset(440, 300), 200);

      expect(app.canvas.scale, greaterThan(was * 1.5),
          reason: 'it zoomed, instead of two pans fighting');
      expect(Offset(box.x, box.y), boxWas,
          reason: 'and the box itself did not move');
      app.cancelPendingSave();
    });

    testWidgets('one finger on the box and one beside it zoom too', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pump(t);
      final was = app.canvas.scale;
      // (760, 570) is past the box's bottom-right corner.
      await spread(t, const Offset(300, 300), const Offset(760, 570), 160);
      expect(app.canvas.scale, greaterThan(was * 1.2));
      app.cancelPendingSave();
    });

    testWidgets('the pinch ends when the fingers do', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pump(t);
      await spread(t, const Offset(300, 300), const Offset(440, 300), 100);
      expect(app.pinching, isFalse,
          reason: 'a stale flag would leave every block refusing to navigate');
      app.cancelPendingSave();
    });

    testWidgets('NEGATIVE CONTROL: ONE finger on the box still pans',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // Bug 8's fix, which this must not take away: a finger dragged over a
      // box scrolls the page.
      await pump(t);
      final before = app.canvas.offset;
      final g = await t.startGesture(const Offset(300, 300),
          kind: PointerDeviceKind.touch);
      for (var i = 0; i < 4; i++) {
        await g.moveBy(const Offset(-20, -15));
        await t.pump();
      }
      await g.up();
      await t.pump();
      expect(app.canvas.offset, isNot(before));
      expect(app.editingBlockId, isNull);
      app.cancelPendingSave();
    });
  });
}
