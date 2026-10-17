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

  testWidgets('THE LASSO IS HOW STROKES BECOME ONE OBJECT', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await openPage(t);
    app.setTool(Tool.pen);

    await stroke(t, const Offset(200, 200), const Offset(240, 210));
    await stroke(t, const Offset(246, 202), const Offset(280, 212));
    expect(inkBlocks(), 2);

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

    expect(inkBlocks(), 1, reason: 'the loop said these two are one thing');
    expect(app.selectedIds, hasLength(1),
        reason: 'and handed it over selected, ready to be moved at once');
    expect(app.tool, Tool.select);
  });
}
