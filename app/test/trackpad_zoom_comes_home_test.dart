// A trackpad pinch out and back in comes home.
//
// `CanvasController.zoomTo` exists because asking for a FACTOR per sample
// compounds: *"zoom is jumpy"*, and worse, the scale is clamped — so ratio
// pushed past a limit is consumed and never given back, and fingers returned
// to where they started leave the page at a different zoom. The touch pinch
// was converted to an absolute target measured from the gesture's own start.
//
// The trackpad was not. `onPointerPanZoomUpdate` still multiplies
// `e.scale / _pzLastScale` into the scale and re-bases `_pzLastScale` every
// sample — the exact shape that was removed from touch, on the input most
// laptop users have. `PointerPanZoomUpdateEvent.scale` is cumulative from the
// gesture's start, so the absolute target is simply the scale it began at
// times that.
import 'dart:io';

import 'package:flutter/gestures.dart';
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

  late Directory tmp;
  late Repository repo;
  late AppState app;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_pzzoom_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Z');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    await app
        .selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
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

  /// One trackpad pinch: [scales] are CUMULATIVE scale factors, the way the
  /// platform reports them.
  Future<void> pinch(WidgetTester t, List<double> scales,
      {Offset at = const Offset(400, 300)}) async {
    final p = TestPointer(1, PointerDeviceKind.trackpad);
    await t.sendEventToBinding(p.panZoomStart(at));
    await t.pump();
    for (final s in scales) {
      await t.sendEventToBinding(p.panZoomUpdate(at, scale: s));
      await t.pump();
    }
    await t.sendEventToBinding(p.panZoomEnd());
    await t.pump();
  }

  testWidgets('out and back in comes home', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(t);
    final was = app.canvas.scale;
    expect(was, closeTo(1.0, 0.001), reason: 'precondition');

    // Spread to 2.5x in small steps, then pinch all the way back to 1.0 —
    // the same gesture in reverse, which must undo itself exactly.
    final out = [for (var i = 1; i <= 15; i++) 1.0 + 1.5 * i / 15];
    final back = [for (var i = 14; i >= 0; i--) 1.0 + 1.5 * i / 15];
    await pinch(t, [...out, ...back]);

    expect(app.canvas.scale, closeTo(was, 0.001),
        reason: 'fingers back where they started, zoom back where it was');
    app.cancelPendingSave();
  });

  testWidgets('and past the limit and back still comes home', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // The clamp is the sharp half of it: ratio spent past `maxScale` was
    // consumed and never returned.
    await pump(t);
    await pinch(t, [4, 40, 400, 40, 4, 1]);
    expect(app.canvas.scale, closeTo(1.0, 0.001));
    app.cancelPendingSave();
  });

  testWidgets('a pinch is the same however finely it is sampled', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(t);
    await pinch(t, [2.0]);
    final coarse = app.canvas.scale;
    expect(coarse, closeTo(2.0, 0.001), reason: 'the gesture decided it');

    app.canvas.zoomTo(const Offset(400, 300), 1.0);
    await t.pump();
    await pinch(t, [for (var i = 1; i <= 50; i++) 1.0 + i / 50]);
    expect(app.canvas.scale, closeTo(coarse, 0.001));
    app.cancelPendingSave();
  });

  testWidgets('the point under the cursor stays under it', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(t);
    const at = Offset(300, 250);
    final before = app.canvas.screenToPage(at);
    await pinch(t, [1.5, 2.0], at: at);
    expect(app.canvas.screenToPage(at).dx, closeTo(before.dx, 0.5));
    expect(app.canvas.screenToPage(at).dy, closeTo(before.dy, 0.5));
    app.cancelPendingSave();
  });

  testWidgets('NEGATIVE CONTROL: a two-finger trackpad PAN still pans',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(t);
    app.canvas.zoomTo(const Offset(400, 300), 2.0);
    await t.pump();
    final before = app.canvas.offset;
    final p = TestPointer(1, PointerDeviceKind.trackpad);
    await t.sendEventToBinding(p.panZoomStart(const Offset(400, 300)));
    await t.pump();
    for (var i = 1; i <= 4; i++) {
      await t.sendEventToBinding(p.panZoomUpdate(const Offset(400, 300),
          pan: Offset(-20.0 * i, -12.0 * i)));
      await t.pump();
    }
    await t.sendEventToBinding(p.panZoomEnd());
    await t.pump();
    expect(app.canvas.offset, isNot(before));
    expect(app.canvas.scale, closeTo(2.0, 0.001), reason: 'pan, not zoom');
    app.cancelPendingSave();
  });

  testWidgets('NEGATIVE CONTROL: the zoom limits still hold', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(t);
    await pinch(t, [100]);
    expect(app.canvas.scale, CanvasController.maxScale);
    await pinch(t, [0.001]);
    expect(app.canvas.scale, CanvasController.minScale);
    app.cancelPendingSave();
  });
}
