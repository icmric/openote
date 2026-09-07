// `auto` ink over a document, checked through the real canvas.
//
// Reported after the first fix shipped: *"Auto pen colour doesnt work on
// images/pdfs either, still coming up as white on a white pdf background,
// auto needs to change to black (this includes imported ink too that is
// imported as auto)."*
//
// `InkPainter.autoFor` was already unit-tested and already right. What was
// never tested is the half that feeds it: the rectangles the canvas hands
// down. A PDF slide is stored with a WIDTH and no height — the height comes
// from whatever the picture turns out to be — so anything that needs a
// slide's rectangle has to cope with `Block.h == null`.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/ink_painter.dart';
import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';

import 'support/app.dart';
import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Future<AppState> page(WidgetTester tester, String name) async {
    late AppState app;
    late Repository repo;
    final tmp = Directory.systemTemp.createTempSync(name);
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
    return app;
  }

  Block stroke(List<double> xs, List<double> ys) => Block(
        type: BlockType.ink,
        x: xs.first,
        y: ys.first,
        w: 300,
        h: 300,
        content: {
          'strokes': [
            {
              'id': 's1',
              'brush': {
                'tool': 'pen',
                'color': 'auto',
                'size': 3.0,
                'opacity': 1.0
              },
              'x': xs,
              'y': ys,
              'p': <double>[],
            }
          ]
        },
      );

  InkPainter painterOf(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((c) => c.painter)
      .whereType<InkPainter>()
      .first;

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 900));
  }

  testWidgets('a slide stored without a height is still a document',
      (tester) async {
    // How `pdf_import.dart` actually writes a slide: width only. Every
    // rectangle in the app has to derive the height, and the ink layer's
    // fallback for a block that has not reported one yet is SIXTY PIXELS —
    // so ink below the first sixty pixels of a full-page slide was reckoned
    // to be over the page, and went white on a dark theme.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await page(tester, 'onote_auto_pdf_');

    app.addBlock(Block(
      type: BlockType.image,
      x: 60,
      y: 80,
      w: 640,
      content: {
        'pdf': 'sha256:none',
        'page': 0,
        'mime': 'application/pdf',
        'naturalW': 1280.0,
        'naturalH': 960.0,
        'locked': true,
      },
    ));
    // Well down the slide: 640 wide at 4:3 is 480 tall, so y=400 is on it.
    app.addBlock(stroke([200, 300, 400], [400, 410, 400]));

    await tester.pumpWidget(testApp(Scaffold(body: PageCanvas(state: app)),
        brightness: Brightness.dark));
    await tester.pump();

    final p = painterOf(tester);
    expect(p.strokes, isNotEmpty);
    expect(p.autoFor(p.strokes.first), OnoteColors.graphite900,
        reason: 'the stroke is on the slide, so it contrasts with the slide');

    await drain(tester);
  });

  testWidgets('ink on the page itself still follows the theme', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await page(tester, 'onote_auto_page_');

    app.addBlock(Block(
      type: BlockType.image,
      x: 60,
      y: 80,
      w: 200,
      h: 200,
      content: {'blob': 'sha256:none'},
    ));
    app.addBlock(stroke([700, 760, 820], [700, 710, 700]));

    await tester.pumpWidget(testApp(Scaffold(body: PageCanvas(state: app)),
        brightness: Brightness.dark));
    await tester.pump();

    final p = painterOf(tester);
    expect(p.autoFor(p.strokes.first), OnoteColors.moon100,
        reason: 'nothing underneath it but a dark page');

    await drain(tester);
  });
}
