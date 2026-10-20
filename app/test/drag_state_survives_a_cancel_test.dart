// A drag taken away mid-gesture still has to end.
//
// The owner, describing touch navigation: *"zoom is jumpy and in once case
// caused a grid to appear permenantly on all pages in addition to any
// background styling. Disapeared after a restart."*
//
// `AppState.draggingBlock` is what draws the alignment grid, and it is set at
// the start of a drag and cleared at the end of one. The framework cancels a
// pointer when something else wins the arena — a second finger arriving on
// the way to a pinch is the ordinary case — and neither the canvas's select
// `Listener` nor the block's pan recognizer had a cancel, so the flag stayed
// true. A restart was the only thing certain to clear it, which is exactly
// what the report says.
//
// The first test drives a path that really sets the flag and fails with the
// canvas's `onPointerCancel` removed. (The first version of this file drove
// two paths that never set it at all, and passed against the bug.)
//
// The second is a NEGATIVE CONTROL, and it is here because it taught the fix
// what not to include: a block moved by its own bar needs no cancel handler,
// because a `PanGestureRecognizer` that has already been accepted calls
// `onEnd` for a cancelled pointer as well as a lifted one. `onPanCancel`
// fires only for a drag rejected BEFORE it started, where there is nothing to
// clean up — so the handler this file was written to justify was deleted
// again. A raw `Listener` has no such courtesy, which is the whole
// difference and the reason only one of the two needed fixing.
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

  late Directory tmp;
  late Repository repo;
  late AppState app;

  setUp(() {
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_cancel_');
  });

  tearDown(() {
    AppState.syncLogEnabled = true;
    app.cancelPendingSave();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> open(WidgetTester t) async {
    await t.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Pages');
      app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      await app.selectPage(
          app.nodes.where((n) => n.kind == NodeKind.page).first.id);
    });
  }

  Future<void> mount(WidgetTester t) async {
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

  testWidgets('A CANCELLED SELECTION DRAG DOES NOT LEAVE THE GRID ON',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await open(t);
    // Ink, because the Select tool's own move path starts on a stroke —
    // `_selectDown`'s `_hitInk`, which is what puts the canvas into its
    // dragging state.
    final ink = app.addBlock(Block(
      type: BlockType.ink,
      x: 200,
      y: 200,
      w: 60,
      h: 20,
      content: {
        'strokes': [
          Stroke(
            tool: 'pen',
            colorHex: '#211F1B',
            size: 2,
            x: [200, 260],
            y: [200, 220],
          ).toJson()
        ]
      },
    ));
    app.setTool(Tool.select);
    await mount(t);

    final at = app.canvas.pageToScreen(const Offset(230, 210));
    final g = await t.startGesture(at, kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(20, 10));
    await t.pump();
    expect(app.draggingBlock, isTrue,
        reason: 'the drag really started, or this proves nothing');

    // ...and then the gesture is taken away, which is what a second finger
    // on the way to a pinch does.
    await g.cancel();
    await t.pump();

    expect(app.draggingBlock, isFalse,
        reason: 'the grid is drawn while this is true, on every page');
    expect(app.blocks.single.id, ink.id);
    app.cancelPendingSave();
  });

  testWidgets('NEGATIVE CONTROL: the recognizer already ends a cancelled bar drag',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await open(t);
    final box = app.addBlock(Block(
        type: BlockType.text,
        x: 120,
        y: 140,
        w: 300,
        h: 90,
        content: {'text': 'a note', 'autoWidth': false}));
    app.select(box.id);
    app.setTool(Tool.select);
    await mount(t);

    // The bar is the strip reserved ABOVE the content (16px), which is the
    // only place a text box moves from without Alt.
    final bar = app.canvas.pageToScreen(const Offset(200, 140 - 8));
    final g = await t.startGesture(bar, kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(30, 20));
    await t.pump();
    expect(app.draggingBlock, isTrue, reason: 'precondition');

    await g.cancel();
    await t.pump();

    expect(app.draggingBlock, isFalse);
    app.cancelPendingSave();
  });
}
