// Touch navigation: a finger scrolls, and a pinch comes back where it started.
//
// The owner's own note before release: *"improve touch navigation (dragging
// over a box still selects it. zoom is jumpy ...)"*, and later: *"for memory
// too it was a bit funky at different zoom levels."*
//
// Two of the three parts are here. A finger drag on EMPTY page already panned
// (canvas_interaction_test pins that); a finger drag on a BOX selected its
// words, and a box is most of the page, so a tablet had almost nowhere to
// scroll from. And the pinch measured each sample against the last one, which
// compounds its rounding and — because the scale is clamped — threw away
// ratio at the limits, so fingers returned to where they started left the page
// at a different zoom.
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

  group('the pinch, in the controller', () {
    late CanvasController c;

    setUp(() {
      c = CanvasController()
        ..viewport = const Size(800, 600)
        ..pageSize = const Size(1100, 1400);
    });

    tearDown(() => c.dispose());

    /// A pinch: fingers [from] apart, moved to [to] apart, one sample per
    /// step — the way a real gesture arrives.
    void pinch(double from, double to, {int steps = 20}) {
      final base = c.scale;
      for (var i = 1; i <= steps; i++) {
        final d = from + (to - from) * i / steps;
        c.zoomTo(const Offset(400, 300), base * d / from);
      }
    }

    test('out and back in comes home', () {
      c.zoomTo(const Offset(400, 300), 1.0);
      pinch(200, 500);
      final out = c.scale;
      expect(out, closeTo(2.5, 0.001), reason: 'the span decided it');
      // The same gesture in reverse. Measured from its own start, so the
      // fingers coming back means the zoom comes back.
      final base = out;
      for (var i = 1; i <= 20; i++) {
        final d = 500 + (200 - 500) * i / 20;
        c.zoomTo(const Offset(400, 300), base * d / 500);
      }
      expect(c.scale, closeTo(1.0, 0.001));
    });

    test('a hundred samples do not drift', () {
      // Each sample is a pure function of the span, so dividing the same
      // gesture into more pieces changes nothing.
      c.zoomTo(const Offset(400, 300), 1.0);
      pinch(200, 400, steps: 2);
      final coarse = c.scale;
      c.zoomTo(const Offset(400, 300), 1.0);
      pinch(200, 400, steps: 200);
      expect(c.scale, closeTo(coarse, 0.0001));
    });

    test('past the limit and back still comes home', () {
      // The scale is clamped, and the old code re-based its reference anyway,
      // so ratio pushed past the limit was consumed and never given back.
      c.zoomTo(const Offset(400, 300), 1.0);
      final base = c.scale;
      for (final d in [400.0, 4000.0, 40000.0, 4000.0, 400.0, 200.0]) {
        c.zoomTo(const Offset(400, 300), base * d / 200);
      }
      expect(c.scale, closeTo(1.0, 0.001),
          reason: 'fingers back where they started, zoom back where it was');
    });

    test('it stops at the limits', () {
      c.zoomTo(const Offset(400, 300), 99);
      expect(c.scale, CanvasController.maxScale);
      c.zoomTo(const Offset(400, 300), 0.0001);
      expect(c.scale, CanvasController.minScale);
    });

    test('the point under the fingers stays under them', () {
      c.zoomTo(const Offset(400, 300), 1.0);
      const focal = Offset(300, 250);
      final before = c.screenToPage(focal);
      c.zoomTo(focal, 2.0);
      expect(c.screenToPage(focal).dx, closeTo(before.dx, 0.01));
      expect(c.screenToPage(focal).dy, closeTo(before.dy, 0.01));
    });

    test('NEGATIVE CONTROL: zoomAt still takes a factor', () {
      // Ctrl+wheel and the zoom buttons use it; it is now one line over
      // zoomTo and must behave exactly as it did.
      c.zoomTo(const Offset(400, 300), 1.0);
      c.zoomAt(const Offset(400, 300), 1.5);
      expect(c.scale, closeTo(1.5, 0.001));
      c.zoomAt(const Offset(400, 300), 2.0);
      expect(c.scale, closeTo(3.0, 0.001));
    });
  });

  group('a finger on a box', () {
    late Repository repo;
    late Directory tmp;
    late AppState app;
    late Block box;

    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_touchnav_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('T');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      await app
          .selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
      box = Block(
          type: BlockType.text,
          x: 150,
          y: 150,
          w: 400,
          h: 200,
          content: {'text': 'a paragraph with words in it', 'autoWidth': false});
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
          body: SizedBox(width: 800, height: 600, child: PageCanvas(state: app)),
        ),
      ));
      await t.pump();
      await t.pump();
    }

    /// The middle of the box, on screen.
    Offset onBox() => app.canvas.pageToScreen(Offset(box.x + 60, box.y + 20));

    Future<void> drag(WidgetTester t, Offset by,
        {required PointerDeviceKind kind}) async {
      final g = await t.startGesture(onBox(), kind: kind);
      // Several samples, as a real drag arrives.
      for (var i = 0; i < 4; i++) {
        await g.moveBy(by / 4);
        await t.pump();
      }
      await g.up();
      await t.pump();
    }

    testWidgets('a finger dragged across a box scrolls the page', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pump(t);
      final before = app.canvas.offset;

      await drag(t, const Offset(-100, -60), kind: PointerDeviceKind.touch);

      expect(app.canvas.offset, isNot(before), reason: 'the page moved');
      expect(app.editingBlockId, isNull,
          reason: 'and the box was not opened for typing');
      expect(app.selectedIds, isEmpty);
      app.cancelPendingSave();
    });

    testWidgets('and the box it ends on is not opened by the scroll',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // Flutter's tap slop is 18px and a pan is recognised at 4, so a short
      // scroll used to also count as a tap on the box.
      await pump(t);
      await drag(t, const Offset(-12, 0), kind: PointerDeviceKind.touch);
      expect(app.editingBlockId, isNull);
      expect(app.canvas.offset, isNot(Offset.zero));
      app.cancelPendingSave();
    });

    testWidgets('a TAP on a box still opens it', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pump(t);
      await t.tapAt(onBox());
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(app.editingBlockId, box.id,
          reason: 'the whole point of not standing down for the canvas');
      app.cancelPendingSave();
    });

    testWidgets('NEGATIVE CONTROL: a MOUSE drag still selects its words',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The box is where a mouse drag means "select this text", and that must
      // not change — only a finger is a scroll.
      await pump(t);
      final before = app.canvas.offset;
      await drag(t, const Offset(80, 0), kind: PointerDeviceKind.mouse);
      expect(app.canvas.offset, before, reason: 'the page did not move');
      expect(app.editingBlockId, box.id, reason: 'the box took the caret');
      app.cancelPendingSave();
    });

    testWidgets('a finger IN a box being typed in still selects its words',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // Once the caret is in there, a drag is the gesture for picking out
      // words — on a tablet that is how you select without a keyboard.
      await pump(t);
      await t.tapAt(onBox());
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(app.editingBlockId, box.id, reason: 'precondition');

      final before = app.canvas.offset;
      await drag(t, const Offset(60, 0), kind: PointerDeviceKind.touch);
      expect(app.canvas.offset, before,
          reason: 'the page stays put; the drag belongs to the text');
      app.cancelPendingSave();
    });
  });
}
