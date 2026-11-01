// A pinch takes the gesture over, and whatever had it ENDS.
//
// The owner's original touch note: *"zoom is jumpy and in one case caused a
// grid to appear permenantly on all pages in addition to any background
// styling. Disapeared after a restart."*
//
// `_selectCancel` was written for that and closed one door: a pointer the
// framework cancels never reached `_selectUp`, so `AppState.draggingBlock`
// stayed true and that flag is what draws the alignment grid — on every page,
// because it is one flag on the app, and until a restart, because nothing
// else was certain to clear it.
//
// This is the second door, still open. A finger landing on handwriting sets
// `_DragMode.moveSelection` and `setDragging(true)`. A second finger starts
// the pinch and clears `_mode` — so when the fingers come up normally, with
// no cancel at all, `_selectUp` takes its `default` branch and never puts the
// flag down. One ordinary pinch that began on a stroke, and the grid is on
// every page for the rest of the session.
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
  late Block ink;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_pinchdrag_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('G');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    await app
        .selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
    // Snapping on, because the grid only draws when it is — that is the
    // symptom being chased.
    app.snapToGrid = true;
    ink = Block(
        type: BlockType.ink,
        x: 150,
        y: 200,
        w: 260,
        h: 120,
        content: {
          'strokes': [
            Stroke(
              tool: 'pen',
              colorHex: '#211F1B',
              size: 3,
              x: const [160, 260, 380],
              y: const [220, 260, 300],
              p: const [1, 1, 1],
              t: const [0, 1, 2],
            ).toJson(),
          ]
        });
    app.addBlock(ink, recordUndo: false);
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

  /// A point on the stroke, on screen.
  Offset onStroke() => app.canvas.pageToScreen(const Offset(260, 260));

  testWidgets('a pinch that began on a stroke puts the drag flag down',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(t);

    // One finger on the handwriting: the canvas picks the selection up.
    final g1 = await t.startGesture(onStroke(), kind: PointerDeviceKind.touch);
    await t.pump();
    expect(app.draggingBlock, isTrue, reason: 'precondition: it was picked up');

    // A second finger, and the pinch takes the gesture over.
    final g2 = await t.startGesture(
        onStroke() + const Offset(120, 0), kind: PointerDeviceKind.touch);
    for (var i = 0; i < 5; i++) {
      await g1.moveBy(const Offset(-8, 0));
      await g2.moveBy(const Offset(8, 0));
      await t.pump();
    }
    // Both fingers lifted normally. Nothing is cancelled, so `_selectCancel`
    // — which is where this used to be put right — never runs.
    await g1.up();
    await g2.up();
    await t.pump();

    expect(app.draggingBlock, isFalse,
        reason: 'otherwise the alignment grid is drawn over every page for '
            'the rest of the session');
    app.cancelPendingSave();
  });

  testWidgets('and the selection it had picked up is settled, not abandoned',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(t);
    final g1 = await t.startGesture(onStroke(), kind: PointerDeviceKind.touch);
    await t.pump();
    await g1.moveBy(const Offset(20, 10));
    await t.pump();

    final g2 = await t.startGesture(
        onStroke() + const Offset(140, 0), kind: PointerDeviceKind.touch);
    await t.pump();
    // The pinch has it now, so the block stops moving with the finger.
    final parked = (app.blocks.first.x, app.blocks.first.y);
    for (var i = 0; i < 4; i++) {
      await g1.moveBy(const Offset(-10, -10));
      await g2.moveBy(const Offset(10, 10));
      await t.pump();
    }
    expect((app.blocks.first.x, app.blocks.first.y), parked,
        reason: 'two fingers are navigating, not moving a block');
    await g1.up();
    await g2.up();
    await t.pump();
    expect(app.draggingBlock, isFalse);
    app.cancelPendingSave();
  });

  testWidgets('NEGATIVE CONTROL: one finger still drags the handwriting',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(t);
    final was = (ink.x, ink.y);
    final g = await t.startGesture(onStroke(), kind: PointerDeviceKind.touch);
    for (var i = 0; i < 4; i++) {
      await g.moveBy(const Offset(12, 8));
      await t.pump();
    }
    await g.up();
    await t.pump();
    expect((app.blocks.first.x, app.blocks.first.y), isNot(was));
    expect(app.draggingBlock, isFalse, reason: 'and it is put down on release');
    app.cancelPendingSave();
  });
}
