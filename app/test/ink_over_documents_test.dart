// Handwriting has to be on top of what it is written on.
//
// From issue #7: "I can't reliably write over imported images/PDFs. They
// should stay fixed while drawing, with handwriting appearing above them."
//
// Two claims, and only one of them was a bug.
//
// **Staying fixed** already worked: while a pen, highlighter or eraser is
// held, every block is wrapped in an `IgnorePointer`, so the picture cannot be
// dragged by a stroke that starts on it.
//
// **Appearing above them** did not, and the cause was paint order rather than
// anything to do with ink. The ink layer was the FIRST child of the page's
// Stack and the blocks came after it, so every block painted over the
// handwriting. Against a text box — which is transparent — nothing showed;
// against a picture or a PDF page, which are not, the ink vanished entirely.
// Writing on a photo looked exactly like a pen that had not worked.
//
// This test reads the widget tree rather than pixels: the property is "ink is
// painted after the blocks", and that is a structural fact a golden image
// would only tell you about indirectly.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/ink_painter.dart';
import 'package:openote/canvas/block_view.dart';
import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'dart:io';

import 'support/app.dart';
import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  testWidgets('ink is painted after the blocks, so it lands on top of a picture',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');

    late AppState app;
    late Repository repo;
    final tmp = Directory.systemTemp.createTempSync('onote_ink_over_');
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await tester.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Ink');
      app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      await app.selectPage(
          app.nodes.where((n) => n.kind == NodeKind.page).first.id);
    });

    // A picture on the page, and a stroke drawn across it.
    app.addBlock(Block(
      type: BlockType.image,
      x: 100,
      y: 100,
      w: 200,
      h: 200,
      content: {'blob': 'sha256:none'},
    ));
    app.addBlock(Block(
      type: BlockType.ink,
      x: 100,
      y: 100,
      w: 200,
      h: 200,
      content: {
        'strokes': [
          {
            'id': 'stroke-1',
            // The brush is a nested map, not flat fields — the shape the
            // stored format actually uses.
            'brush': {
              'tool': 'pen',
              'color': 'auto',
              'size': 3.0,
              'opacity': 1.0,
            },
            'x': [120.0, 180.0, 240.0],
            'y': [150.0, 160.0, 150.0],
            'p': <double>[],
          }
        ]
      },
    ));

    await tester.pumpWidget(testApp(Scaffold(body: PageCanvas(state: app))));
    await tester.pump();

    // Depth-first order through the tree IS paint order for a Stack's
    // children, so the ink layer appearing later than the blocks is the
    // property under test.
    // `tester.allElements` walks the tree depth-first, and for a Stack that
    // walk IS paint order. (`find.byType(Widget)` matches an exact runtime
    // type, so it finds nothing — worth saying, because it silently passes
    // a `findsNothing` and fails everything else confusingly.)
    final all = tester.allElements.toList();
    final inkAt = all.indexWhere((e) =>
        e.widget is CustomPaint &&
        (e.widget as CustomPaint).painter is InkPainter);
    final blockAt = all.indexWhere((e) => e.widget is BlockView);

    expect(inkAt, isNonNegative, reason: 'the ink layer should be mounted');
    expect(blockAt, isNonNegative, reason: 'the picture should be mounted');
    expect(inkAt, greaterThan(blockAt),
        reason: 'ink painted BEFORE the blocks is ink hidden behind them — '
            'invisible against a text box, gone entirely against a picture');

    // Adding a block arms a debounced save, and the image view arms a loader;
    // nothing here pumps them out, so drain them or the test ends holding
    // timers and fails on that instead of on what it came to check.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 900));
  });
}
