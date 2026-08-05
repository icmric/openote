// THROWAWAY probe: resizing a SMALL ink block scales the strokes.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/block_view.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  testWidgets('a 1px drag of the width handle on a small scribble', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final tmp = Directory.systemTemp.createTempSync('onote_inkres_');
    late Repository repo;
    late AppState app;
    late Block ink;
    await t.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('R');
      app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      await app
          .selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
    });
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    // A small scribble: 30 page-units wide, 20 tall, at (100,100) —
    // i.e. what _refitInkBounds writes after drawing a short squiggle.
    final s = Stroke(tool: 'pen', colorHex: '#111111', size: 2.5);
    for (var i = 0; i <= 10; i++) {
      s.x.add(100 + i * 12.0);
      s.y.add(100 + (i.isEven ? 0.0 : 20.0));
      s.p.add(0.5);
      s.t.add(i);
    }
    ink = Block(
      type: BlockType.ink,
      x: 100,
      y: 100,
      w: 120,
      h: 20,
      content: {
        'strokes': [s.toJson()]
      },
    );
    app.blocks.add(ink);
    app.select(ink.id);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: app,
          builder: (_, __) => Stack(children: [
            BlockView(block: ink, app: app, controller: app.canvas),
          ]),
        ),
      ),
    ));
    await t.pump();

    List<double> xs() =>
        [for (final v in (ink.content['strokes'][0]['y'] as List)) v as double];
    double span(List<double> v) =>
        v.reduce((a, b) => a > b ? a : b) - v.reduce((a, b) => a < b ? a : b);
    final before = xs();
    // ignore: avoid_print
    print('before: h=${ink.h} span=${span(before)}');

    // The right-edge handle sits at the right of the reserved chrome.
    // Grab it and nudge 2px right — the smallest deliberate resize there is.
    final box = t.getRect(find.byType(BlockView));
    final handle = box;
    final right = Offset(box.center.dx, box.bottom - 5);
    final g = await t.startGesture(right);
    for (var i = 0; i < 3; i++) {
      await g.moveBy(const Offset(0, 1));
      await t.pump();
    }
    await g.up();
    await t.pump();
    app.cancelPendingSave();

    final after = xs();
    // ignore: avoid_print
    print('rendered box=$handle');
    // ignore: avoid_print
    print('after:  h=${ink.h} span=${span(after)}');
    // ignore: avoid_print

    expect(span(after), closeTo(span(before), 6),
        reason: 'a 3px vertical resize must not rescale the ink by a large factor');
  });
}
