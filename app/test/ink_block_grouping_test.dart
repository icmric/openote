// Which ink block a new stroke lands in: its own.
//
// Two guesses have been tried and both swept separate marks into one object —
// time alone (anything within two seconds joined the last block touched,
// wherever it was), then time and distance. From issue #20: *"i just drew a
// bit where i had several seperate strokes and they all got grouped into one
// large thing. It should be split stroke by stroke, if they are visibly not
// connected they shouldnt be connected as an object (unless they are grouped
// together)."*
//
// Grouping is the lasso's job (INK-7) and is tested here beside the splitting,
// because "one stroke per block" is only the right default if saying otherwise
// actually works.
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
    tmp = Directory.systemTemp.createTempSync('onote_inkgroup_');
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
    // Under a listener, the way the shell mounts it: which pointer handler
    // wraps the canvas is decided at build time from `app.tool`.
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

  Future<void> stroke(WidgetTester t, Offset from, Offset to) async {
    await t.pump();
    final g = await t.startGesture(from, kind: PointerDeviceKind.mouse);
    for (var i = 1; i <= 4; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 4)!);
      await t.pump();
    }
    await g.up();
    await t.pump();
    app.cancelPendingSave();
  }

  int inkBlocks() => app.blocks.where((b) => b.type == BlockType.ink).length;

  testWidgets('TWO STROKES IN THE SAME PLACE ARE TWO BLOCKS', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await openPage(t);
    app.setTool(Tool.pen);

    await stroke(t, const Offset(200, 200), const Offset(240, 210));
    await stroke(t, const Offset(246, 202), const Offset(280, 212));

    expect(inkBlocks(), 2, reason: 'nothing decided they were one mark');
  });

  testWidgets('AND EACH BLOCK IS ONLY AS BIG AS ITS OWN STROKE', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await openPage(t);
    app.setTool(Tool.pen);

    await stroke(t, const Offset(200, 200), const Offset(240, 210));
    await stroke(t, const Offset(500, 400), const Offset(540, 410));

    // The symptom of a block that grew: its rectangle covers ground it has no
    // ink on, so a marquee anywhere inside catches it and a click on empty
    // page picks it up.
    for (final b in app.blocks.where((b) => b.type == BlockType.ink)) {
      expect(b.w, lessThan(120), reason: 'no block spans the gap');
      expect(b.h, lessThan(120));
    }
  });

  testWidgets('A NOTE SOMEWHERE ELSE ON THE PAGE IS ITS OWN BLOCK', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await openPage(t);
    app.setTool(Tool.pen);

    // Both inside the two-second window, which is all that used to be asked.
    await stroke(t, const Offset(120, 120), const Offset(180, 130));
    await stroke(t, const Offset(560, 480), const Offset(620, 490));

    expect(inkBlocks(), 2,
        reason: 'two marks at opposite corners are two things, and a marquee '
            'over one of them must not pick up the other');
  });

  testWidgets('THE LOOP IS DRAWN WHILE IT IS BEING DRAWN', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await openPage(t);
    app.setTool(Tool.lasso);
    await t.pump();

    final before = OverlayPainter.debugPaints;
    final g = await t.startGesture(const Offset(180, 180),
        kind: PointerDeviceKind.mouse);
    for (final p in const [
      Offset(240, 180),
      Offset(300, 220),
      Offset(240, 260),
    ]) {
      await g.moveTo(p);
      await t.pump();
    }
    final during = OverlayPainter.debugPaints - before;
    await g.up();
    await t.pump();

    // *"The lasso works however doesnt show the outline as it gets drawn."*
    // The canvas handed the painter the very list it was adding points to, so
    // `shouldRepaint` compared it with itself: nothing had changed, nothing
    // repainted, and the loop appeared only once the gesture ended and
    // something else rebuilt the canvas.
    expect(during, greaterThanOrEqualTo(3),
        reason: 'one repaint per point of the loop, not one at the end');
    app.cancelPendingSave();
  });

  testWidgets('THE LASSO SELECTS WHAT IT CAUGHT, AND CHANGES NOTHING ELSE',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await openPage(t);
    app.setTool(Tool.pen);

    await stroke(t, const Offset(200, 200), const Offset(240, 210));
    await stroke(t, const Offset(246, 202), const Offset(280, 212));
    await stroke(t, const Offset(600, 500), const Offset(640, 510));
    expect(inkBlocks(), 3);
    final before = [for (final b in app.blocks) b.id];

    app.setTool(Tool.lasso);
    await t.pump();
    final g = await t.startGesture(const Offset(180, 180),
        kind: PointerDeviceKind.mouse);
    for (final p in const [
      Offset(300, 180),
      Offset(300, 240),
      Offset(180, 240),
      Offset(180, 182),
    ]) {
      await g.moveTo(p);
      await t.pump();
    }
    await g.up();
    await t.pump();
    app.cancelPendingSave();

    // *"Id like to make it so that after the selection has been changed … they
    // go back to being their individual strokes or however they were before."*
    // They never stop being: the loop selects, and that is all it does.
    expect(app.selectedIds, hasLength(2),
        reason: 'the two it went round, not the one across the page');
    expect(inkBlocks(), 3, reason: 'nothing was re-homed into a new block');
    expect([for (final b in app.blocks) b.id], before,
        reason: 'and no block was created or destroyed');
    expect(app.tool, Tool.select,
        reason: 'so what was caught can be dragged at once');

    // And letting go of the selection leaves three separate strokes behind.
    app.select(null);
    expect(inkBlocks(), 3);
    expect(app.selectedIds, isEmpty);
  });

  testWidgets('and a loop that catches nothing just clears the selection',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await openPage(t);
    app.setTool(Tool.pen);
    await stroke(t, const Offset(200, 200), const Offset(240, 210));
    app.select(app.blocks.first.id);

    app.setTool(Tool.lasso);
    await t.pump();
    final g = await t.startGesture(const Offset(600, 500),
        kind: PointerDeviceKind.mouse);
    for (final p in const [
      Offset(660, 500),
      Offset(660, 560),
      Offset(600, 560),
      Offset(600, 502),
    ]) {
      await g.moveTo(p);
      await t.pump();
    }
    await g.up();
    await t.pump();
    app.cancelPendingSave();

    expect(app.selectedIds, isEmpty);
    expect(inkBlocks(), 1);
  });
}
