// A dragged box keeps up with the cursor, at every zoom level.
//
// The owner: *"If i am zoomed out the boxes will move considerably faster
// than my mouse when dragging them, and move slower than my mouse when zoomed
// in on them. My guess is that we somewhere tried to account for dragging at
// different zoom levels but just messed up with it ... Ideally it should be
// tied to the cursor position."*
//
// Exactly that. A `BlockView` is built inside the canvas's
// `Transform(transform: controller.matrix)`, and a gesture recognizer reports
// `DragUpdateDetails.delta` in the detector's LOCAL coordinates — which
// inside that transform is PAGE space, already divided by the zoom by the
// framework's own hit-test transform. Dividing it by the zoom again
// double-counts. Measured before the fix, dragging the move bar 120 screen
// pixels across:
//
//   zoom 0.4 → 600 page units travelled, where 300 keeps up with the cursor
//   zoom 2.0 →  24 page units travelled, where  60 does
//
// The division is not wrong everywhere, which is what made it look right:
// `PageCanvas`'s own `Listener` sits OUTSIDE the transform and measures in
// screen pixels, and the long-press path fed `_drag` a cumulative GLOBAL
// offset. Three paths, two coordinate systems, one shared `/ scale`. The rule
// now is that `_drag` is given PAGE space, and each caller hands it page
// space.
import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/l10n/l10n.dart';
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
  late Block box;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_dragzoom_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('D');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    await app
        .selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
    // Snapping off: the question here is how far the box travelled, and a
    // grid would round the answer.
    app.snapToGrid = false;
    box = Block(
        type: BlockType.text,
        x: 300,
        y: 300,
        w: 300,
        h: 160,
        content: {'text': 'drag me', 'autoWidth': false});
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
        body: SizedBox(width: 900, height: 700, child: PageCanvas(state: app)),
      ),
    ));
    await t.pump();
    await t.pump();
  }

  /// The box as it is now.
  Block at() => app.blocks.firstWhere((b) => b.id == box.id);

  /// The move bar — the strip just above the box, which is where a box is
  /// dragged from (inside a text box a drag means "select this text", so the
  /// container needs somewhere else to be grabbed).
  Offset bar({double along = 0.5}) =>
      app.canvas.pageToScreen(Offset(at().x + at().w * along, at().y - 8));

  /// The box has to be selected for its chrome — the bar included — to exist.
  Future<void> show(WidgetTester t) async {
    app.select(box.id);
    await t.pump();
    await t.pump();
  }

  /// Start a drag at [from] and get it PAST the recognizer's slop, which it
  /// does not replay — measuring across acceptance would measure the slop as
  /// well as the drag. Returns to where it started, so the caller's own
  /// measurement begins from a known place.
  Future<TestGesture> grab(WidgetTester t, Offset from,
      {PointerDeviceKind kind = PointerDeviceKind.mouse}) async {
    final g = await t.startGesture(from, kind: kind);
    for (final d in const [Offset(60, 60), Offset(-60, -60)]) {
      await g.moveBy(d);
      await t.pump();
    }
    return g;
  }

  /// Move [g] by [by] SCREEN pixels, in several samples as a real drag does.
  Future<void> moveBy(WidgetTester t, TestGesture g, Offset by) async {
    for (var i = 0; i < 5; i++) {
      await g.moveBy(by / 5);
      await t.pump();
    }
  }

  for (final zoom in [0.4, 0.5, 1.0, 2.0, 3.0]) {
    testWidgets('at ${zoom}x a drag moves the box exactly with the pointer',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pump(t);
      await show(t);
      app.canvas.zoomTo(const Offset(450, 350), zoom);
      await t.pump();
      expect(app.canvas.scale, closeTo(zoom, 0.001), reason: 'precondition');

      final g = await grab(t, bar());
      final startPage = Offset(at().x, at().y);
      const byScreen = Offset(120, 80);
      await moveBy(t, g, byScreen);

      // The box moved by the pointer's SCREEN distance, so the grab point is
      // still under the cursor. In page units that is the screen distance
      // divided by the zoom — exactly once.
      final movedPage = Offset(at().x, at().y) - startPage;
      expect(movedPage.dx, closeTo(byScreen.dx / zoom, 1.0),
          reason: 'x: moved ${movedPage.dx} page units');
      expect(movedPage.dy, closeTo(byScreen.dy / zoom, 1.0),
          reason: 'y: moved ${movedPage.dy} page units');
      await g.up();
      await t.pump();
      app.cancelPendingSave();
    });
  }

  testWidgets('the point you grabbed stays under the cursor', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // The owner's own framing: *"ensure that you tie the original click point
    // of the box to the cursor position rather than just assume left or
    // whatever."* A box moved BY the pointer's travel satisfies that for
    // every grab point at once, which is why there is nothing to remember.
    await pump(t);
    await show(t);
    app.canvas.zoomTo(const Offset(450, 350), 0.5);
    await t.pump();

    // Grabbed well off the box's own origin, so a path that moved the box's
    // corner TO the cursor rather than BY its travel would show up here.
    final grabScreen = bar(along: 0.85);
    final g = await grab(t, grabScreen);
    final grabInBox =
        app.canvas.screenToPage(grabScreen) - Offset(at().x, at().y);

    const by = Offset(-90, 140);
    await moveBy(t, g, by);

    final underCursor = app.canvas.screenToPage(grabScreen + by);
    expect(underCursor.dx - at().x, closeTo(grabInBox.dx, 1.0));
    expect(underCursor.dy - at().y, closeTo(grabInBox.dy, 1.0));
    await g.up();
    await t.pump();
    app.cancelPendingSave();
  });

  testWidgets('a finger long-press drag moves it with the finger too',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // The touch path reports a cumulative GLOBAL offset rather than a local
    // delta, so it needs the opposite treatment — and got the same one.
    await pump(t);
    await show(t);
    app.canvas.zoomTo(const Offset(450, 350), 0.5);
    await t.pump();

    final g = await t.startGesture(bar(), kind: PointerDeviceKind.touch);
    await t.pump(const Duration(milliseconds: 600)); // the long press
    await g.moveBy(const Offset(40, 40)); // past its own slop
    await t.pump();
    final startPage = Offset(at().x, at().y);
    await moveBy(t, g, const Offset(100, 60));

    final moved = Offset(at().x, at().y) - startPage;
    expect(moved.dx, closeTo(100 / 0.5, 2.0), reason: 'x: ${moved.dx}');
    expect(moved.dy, closeTo(60 / 0.5, 2.0), reason: 'y: ${moved.dy}');
    await g.up();
    await t.pump();
    app.cancelPendingSave();
  });

  testWidgets('and a resize grip tracks the cursor at a zoom level too',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // Same transform, same local delta, same double division.
    await pump(t);
    await show(t);
    app.canvas.zoomTo(const Offset(450, 350), 0.5);
    await t.pump();

    // The right-edge grip sits on the box's right side, vertically centred.
    final grip = app.canvas
        .pageToScreen(Offset(at().x + at().w, at().y + (at().h ?? 160) / 2));
    final g = await grab(t, grip);
    final w0 = at().w;
    await moveBy(t, g, const Offset(60, 0));

    expect(at().w - w0, closeTo(60 / 0.5, 2.0),
        reason: 'the edge followed the cursor; it grew by ${at().w - w0}');
    await g.up();
    await t.pump();
    app.cancelPendingSave();
  });

  testWidgets('NEGATIVE CONTROL: moving a selection from the CANVAS is in '
      'screen pixels and still divides', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // `PageCanvas`'s own Listener is outside the transform, so its deltas are
    // screen pixels and the division there is right. Dragging handwriting —
    // which has no move bar — goes down that path.
    await pump(t);
    final ink = Block(type: BlockType.ink, x: 100, y: 500, w: 200, h: 100,
        content: {
          'strokes': [
            Stroke(
              tool: 'pen',
              colorHex: '#211F1B',
              size: 2,
              x: const [120, 180, 250],
              y: const [520, 545, 575],
              p: const [1, 1, 1],
              t: const [0, 1, 2],
            ).toJson(),
          ]
        });
    app.addBlock(ink, recordUndo: false);
    await t.pump();
    app.canvas.zoomTo(const Offset(450, 350), 0.5);
    await t.pump();

    final from = app.canvas.pageToScreen(const Offset(180, 545));
    final g = await t.startGesture(from);
    await g.moveBy(const Offset(10, 10)); // past the canvas's own 5px
    await t.pump();
    final startPage = Offset(ink.x, ink.y);
    await moveBy(t, g, const Offset(50, 30));
    await g.up();
    await t.pump();

    final moved = Offset(ink.x, ink.y) - startPage;
    expect(moved.dx, closeTo(50 / 0.5, 2.0), reason: 'x: ${moved.dx}');
    app.cancelPendingSave();
  });
}
