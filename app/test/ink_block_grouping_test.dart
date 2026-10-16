// Which ink block a new stroke joins.
//
// A stroke lands in the block it was written beside. The test used to be time
// alone — anything drawn within two seconds joined the last block touched,
// wherever on the page it was — so annotating two corners of a slide in quick
// succession produced one ink block the size of the slide. From issue #20:
// *"handwritten strokes sometimes get grouped into one large object, and
// there's no way to separate them."*
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

  testWidgets('WRITING ON IN THE SAME PLACE STAYS ONE BLOCK', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await openPage(t);
    app.setTool(Tool.pen);

    await stroke(t, const Offset(200, 200), const Offset(240, 210));
    await stroke(t, const Offset(246, 202), const Offset(280, 212));

    expect(inkBlocks(), 1, reason: 'the next word is part of the same note');
  });

  testWidgets('THE NEXT LINE DOWN IS STILL THE SAME NOTE', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await openPage(t);
    app.setTool(Tool.pen);

    await stroke(t, const Offset(200, 200), const Offset(280, 205));
    await stroke(t, const Offset(200, 228), const Offset(280, 233));

    expect(inkBlocks(), 1);
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
}
