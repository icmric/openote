// Drawing a shape on the real canvas, with the real pen.
//
// `ink_shapes_test.dart` pins the arithmetic. This pins the part that arithmetic
// cannot: that a shape drawn on the page arrives as an ordinary stroke in an
// ordinary ink block — which is the whole design. If it does, then the colour,
// the pen size, the highlighter, both eraser modes, the lasso, undo, the ink
// blob store, sync and the InkML and PDF exporters all work on a shape already,
// because none of them can tell it apart from handwriting.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/ink_shapes.dart';
import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/app.dart';
import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;

  Future<void> openPage(WidgetTester t) async {
    await t.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Shapes');
      app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      await app.selectPage(
          app.nodes.where((n) => n.kind == NodeKind.page).first.id);
    });
    // **Under a listener, the way the shell mounts it.** `PageCanvas` does not
    // listen to `AppState` itself — the shell around it does — and WHICH
    // pointer handler wraps the canvas is decided at build time from
    // `app.tool`. Mounted bare, choosing the pen changes nothing in the tree
    // and every drag lands on the selection handler instead.
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
    await t.pump(); // the post-frame view restore
    await t.pump();
  }

  setUp(() {
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_shapedraw_');
  });

  tearDown(() {
    AppState.syncLogEnabled = true;
    app.cancelPendingSave();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Drag on the canvas the way a mouse does.
  Future<void> drag(WidgetTester t, Offset from, Offset to,
      {int steps = 8}) async {
    // **Pumped before the gesture, not after.** Which `Listener` wraps the
    // canvas is decided at BUILD time from `app.tool`, so a tool or shape
    // chosen since the last frame is not in the tree yet and the drag lands on
    // the selection handler instead of the pen.
    await t.pump();
    final g = await t.startGesture(from, kind: PointerDeviceKind.mouse);
    for (var i = 1; i <= steps; i++) {
      await g.moveTo(Offset.lerp(from, to, i / steps)!);
      await t.pump();
    }
    await g.up();
    await t.pump();
    app.cancelPendingSave();
  }

  /// Every stroke the page holds, in the stored form.
  List<Map<String, dynamic>> strokes() => [
        for (final b in app.blocks)
          if (b.type == BlockType.ink)
            for (final s in (b.content['strokes'] as List))
              (s as Map).cast<String, dynamic>(),
      ];

  testWidgets('a rectangle arrives as an ordinary stroke in an ink block',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await openPage(t);
    app.setInkShape(InkShape.rectangle);
    expect(app.tool, Tool.pen,
        reason: 'choosing a shape picks the pen up, as choosing a colour does');

    await drag(t, const Offset(200, 200), const Offset(360, 320));

    final all = strokes();
    expect(all.length, 1, reason: 'one drag, one stroke');
    final xs = (all.single['x'] as List).cast<double>();
    final ys = (all.single['y'] as List).cast<double>();
    // Not five. The outline has four corners, but it is stored resampled —
    // see `kShapeMaxGap`: the eraser and the lasso both work on points and
    // neither looks at the line between two of them, so a four-point rectangle
    // is one you cannot rub the middle out of.
    expect(xs.length, greaterThan(4));
    for (var i = 1; i < xs.length; i++) {
      final gap = Offset(xs[i] - xs[i - 1], ys[i] - ys[i - 1]).distance;
      expect(gap, lessThanOrEqualTo(kShapeMaxGap + 0.001),
          reason: 'a gap the eraser could step over at full zoom');
    }
    expect(xs.first, closeTo(xs.last, 0.001));
    expect(ys.first, closeTo(ys.last, 0.001));
    // The corners themselves survive resampling, or it would be a rounded box.
    expect(xs.where((v) => (v - xs.reduce(math.max)).abs() < 0.001), isNotEmpty);
    // The stored form is exactly what a hand-drawn stroke stores: nothing
    // anywhere records that this was a shape, which is the point.
    expect((all.single['brush'] as Map)['tool'], 'pen');
    expect(all.single.containsKey('shape'), isFalse);
  });

  testWidgets('its pressure is flat, so the sides are the same weight',
      (t) async {
    // A rectangle carrying real pen pressure has four sides of four different
    // weights, which reads as a wobbly hand rather than as a rectangle. The
    // freehand pen keeps all of its pressure; this is the one place it is
    // deliberately dropped.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await openPage(t);
    app.setInkShape(InkShape.rectangle);
    await drag(t, const Offset(200, 200), const Offset(360, 320));

    final p = (strokes().single['p'] as List).cast<double>();
    expect(p, isNotEmpty);
    expect(p.toSet().length, 1, reason: 'one pressure for the whole outline');
  });

  testWidgets('an ellipse is smooth, not a box', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await openPage(t);
    app.setInkShape(InkShape.ellipse);
    await drag(t, const Offset(200, 200), const Offset(360, 320));

    // Resampled past its 48 segments, and every gap small enough to erase.
    expect((strokes().single['x'] as List).length,
        greaterThanOrEqualTo(kEllipseSegments + 1));
  });

  testWidgets('a stray click leaves nothing behind', (t) async {
    // Every shape has two points even dragged nowhere, so the "too few points"
    // guard cannot catch this: without a separate one, a stray click drops a
    // speck of a rectangle on the page that is hard to see and hard to erase.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await openPage(t);
    app.setInkShape(InkShape.rectangle);

    await drag(t, const Offset(200, 200), const Offset(202, 201), steps: 2);

    expect(strokes(), isEmpty);
  });

  testWidgets('and freehand still follows the hand, point for point',
      (t) async {
    // The negative control. Shapes replace the wet stroke's points on every
    // move; freehand must still ADD to them, or the pen would draw a two-point
    // line from wherever it started.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await openPage(t);
    expect(app.inkShape, isNull, reason: 'freehand is the default');
    app.setTool(Tool.pen);

    await drag(t, const Offset(200, 200), const Offset(360, 320), steps: 10);

    final xs = (strokes().single['x'] as List).cast<double>();
    expect(xs.length, greaterThan(5),
        reason: 'a sampled stroke keeps every point the hand passed through');
  });

  testWidgets('a shape can be rubbed out like any other ink', (t) async {
    // Not a new object with its own delete path — the eraser already reaches
    // it, because it is a stroke.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await openPage(t);
    app.setInkShape(InkShape.line);
    await drag(t, const Offset(200, 200), const Offset(360, 200));
    expect(strokes(), hasLength(1));

    app.setInkShape(null);
    app.setTool(Tool.eraser);
    app.eraserMode = EraserMode.stroke;
    await drag(t, const Offset(260, 195), const Offset(300, 205));

    expect(strokes(), isEmpty, reason: 'the eraser did not need telling');
  });

}
