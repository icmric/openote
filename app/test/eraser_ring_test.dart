// You can see how far the eraser reaches.
//
// The owner: *"id like to have a faint outline of the eraser when its being
// used so that people can see the AoE."* It follows a hovering pointer as
// well as a pressing one, because an eraser whose reach you can see *before*
// it touches is the point of drawing one at all.
//
// Counted rather than looked at: whether a circle is on the screen is not
// something a widget test can see, but whether the overlay repainted under
// the pointer is — the same `debugPaints` the lasso's outline is pinned by.
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
    tmp = Directory.systemTemp.createTempSync('onote_eraser_');
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
      final nb = await repo.createNotebook('Ink');
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

  Future<void> hover(WidgetTester t, Offset at) async {
    await t.sendEventToBinding(PointerHoverEvent(
      kind: PointerDeviceKind.mouse,
      pointer: 21,
      position: at,
    ));
    await t.pump();
  }

  testWidgets('THE RING FOLLOWS A HOVERING ERASER', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await openPage(t);
    app.setTool(Tool.eraser);
    await t.pump();

    final before = OverlayPainter.debugPaints;
    await hover(t, const Offset(300, 300));
    final moved = OverlayPainter.debugPaints;
    expect(moved, greaterThan(before),
        reason: 'the overlay repainted where the pointer went');

    await hover(t, const Offset(340, 320));
    expect(OverlayPainter.debugPaints, greaterThan(moved),
        reason: 'and again, once per sample, without rebuilding the canvas');
    app.cancelPendingSave();
  });

  testWidgets('AND NOT A TOOL THAT CANNOT RUB ANYTHING OUT', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await openPage(t);
    app.setTool(Tool.pen);
    await t.pump();

    final before = OverlayPainter.debugPaints;
    await hover(t, const Offset(300, 300));
    await hover(t, const Offset(340, 320));

    expect(OverlayPainter.debugPaints, before,
        reason: 'a pen hovering is not an eraser hovering, and a ring that '
            'appeared under the pen would be a lie about what the next '
            'press does');
    app.cancelPendingSave();
  });

  testWidgets('a pen button that means erase brings the ring with it',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await openPage(t);
    app.setTool(Tool.pen);
    await t.pump();
    await hover(t, const Offset(300, 300));
    final before = OverlayPainter.debugPaints;

    // What `_penErasing` looks like from outside: the tool is still the pen.
    app.setPenErasing(true);
    await t.pump();
    await hover(t, const Offset(310, 300));

    expect(OverlayPainter.debugPaints, greaterThan(before));
    expect(app.tool, Tool.pen, reason: 'the tool did not change hands');
    app.cancelPendingSave();
  });
}
