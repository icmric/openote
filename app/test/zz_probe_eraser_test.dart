// THROWAWAY probe: does the area eraser preserve ink it never touched?
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  /// A horizontal stroke of [n] points at height [y], x from [x0] to [x1].
  Map<String, dynamic> line(double y, double x0, double x1, int n) {
    final s = Stroke(tool: 'pen', colorHex: '#111111', size: 2.5);
    for (var i = 0; i < n; i++) {
      s.x.add(x0 + (x1 - x0) * i / (n - 1));
      s.y.add(y);
      s.p.add(0.5);
      s.t.add(i);
    }
    return s.toJson();
  }

  testWidgets('area erase leaves distant ink alone', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final tmp = Directory.systemTemp.createTempSync('onote_erase_');
    late Repository repo;
    late AppState app;
    await t.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('E');
      app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      await app.selectPage(
          app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
    });
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    final strokes = [
      line(100, 100, 300, 40),
      line(140, 100, 300, 40),
      line(400, 100, 300, 40), // far from the eraser, must be untouched
    ];
    final ink = Block(
      type: BlockType.ink,
      x: 100,
      y: 90,
      w: 200,
      h: 330,
      content: {'strokes': strokes},
    );
    // Snapshot the originals BEFORE the widget can touch them.
    final original = [
      for (final s in strokes)
        [
          for (var i = 0; i < (s['x'] as List).length; i++)
            ((s['x'] as List)[i] as num, (s['y'] as List)[i] as num)
        ]
    ];
    app.blocks.add(ink);
    app.tool = Tool.eraser;
    app.eraserMode = EraserMode.area;

    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 700,
          child: PageCanvas(state: app),
        ),
      ),
    ));
    await t.pump();

    // Sweep the eraser straight down through both upper strokes at x = 200.
    final samples = <Offset>[];
    final g = await t.startGesture(const Offset(200, 80));
    samples.add(const Offset(200, 80));
    for (var i = 1; i <= 80; i++) {
      final at = Offset(200, 80 + i * 1.0);
      samples.add(at);
      await g.moveTo(at);
    }
    await g.up();
    await t.pump();
    app.cancelPendingSave();

    final after = app.blocks.where((b) => b.type == BlockType.ink).toList();
    final out = <List<(num, num)>>[];
    for (final b in after) {
      for (final sj in b.content['strokes'] as List) {
        final m = (sj as Map);
        out.add([
          for (var i = 0; i < (m['x'] as List).length; i++)
            ((m['x'] as List)[i] as num, (m['y'] as List)[i] as num)
        ]);
      }
    }

    final inPts = original.fold<int>(0, (a, s) => a + s.length);
    final outPts = out.fold<int>(0, (a, s) => a + s.length);
    // ignore: avoid_print
    print('strokes in=${original.length} out=${out.length}  '
        'points in=$inPts out=$outPts');
    for (var i = 0; i < out.length; i++) {
      final ys = out[i].map((p) => p.$2).toSet();
      // ignore: avoid_print
      print('  out[$i] n=${out[i].length} y=$ys '
          'x=${out[i].first.$1.toStringAsFixed(1)}..${out[i].last.$1.toStringAsFixed(1)}');
    }

    // 1. Nothing survives inside the eraser.
    const r = 12.0;
    for (final s in out) {
      for (final p in s) {
        for (final e in samples) {
          final d = math.sqrt(math.pow(p.$1 - e.dx, 2) + math.pow(p.$2 - e.dy, 2));
          expect(d, greaterThanOrEqualTo(r - 0.001),
              reason: 'point ($p) survived inside eraser sample $e');
        }
      }
    }
    // 2. The far stroke is intact: all 40 of its points still present.
    final farPts = out
        .expand((s) => s)
        .where((p) => p.$2 == 400)
        .length;
    expect(farPts, 40,
        reason: 'the stroke at y=400 was never touched by the eraser');
    // 3. Nothing was invented or duplicated.
    expect(outPts, lessThanOrEqualTo(inPts),
        reason: 'erasing produced MORE ink than it started with');
  });
}
