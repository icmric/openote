// A way to get rid of what is selected that is not a key on a keyboard.
//
// The owner: *"With selected ink, there should be a button that comes up to
// delete the selected ink/text/items, currently it only lets us move them and
// it feels like a no brainer to have this as an option."*
//
// Lassoed ink was the worst case. Gathering it, moving it, scaling it and
// recolouring it all worked; the only way to remove it was the Delete key,
// which is not on a tablet somebody is holding in one hand with a pen in the
// other — the exact person the lasso is for.

import 'dart:io';

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

  Future<AppState> canvas(WidgetTester tester, String name) async {
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

  Block ink() => Block(
        type: BlockType.ink,
        x: 120,
        y: 140,
        w: 200,
        h: 100,
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
              'x': [120.0, 200.0, 300.0],
              'y': [150.0, 170.0, 150.0],
              'p': <double>[],
            }
          ]
        },
      );

  Future<void> pump(WidgetTester tester, AppState app) async {
    await tester.pumpWidget(testApp(Scaffold(
      body: ListenableBuilder(
        listenable: app,
        builder: (_, __) => PageCanvas(state: app),
      ),
    )));
    await tester.pump();
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 900));
  }

  testWidgets('nothing selected offers no button', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await canvas(tester, 'onote_del_none_');
    app.addBlock(ink());
    await pump(tester, app);

    expect(find.byIcon(Icons.delete_outline), findsNothing,
        reason: 'a page being read is a page, not a control panel');
    await drain(tester);
  });

  testWidgets('selected ink can be deleted without a keyboard', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await canvas(tester, 'onote_del_ink_');
    final b = app.addBlock(ink());
    app.select(b.id);
    await pump(tester, app);

    final button = find.byIcon(Icons.delete_outline);
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pump();

    expect(app.blocks.any((x) => x.id == b.id), isFalse);
    expect(find.byIcon(Icons.delete_outline), findsNothing,
        reason: 'and it goes away with the thing it was about');
    await drain(tester);
  });

  testWidgets('it steps out of the way of the eyedropper', (tester) async {
    // While the eyedropper is armed the next click belongs to it. A button
    // sitting over the page would eat the click that was meant for a colour.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await canvas(tester, 'onote_del_dropper_');
    final b = app.addBlock(ink());
    app.select(b.id);
    app.setPickingInkColor(true);
    await pump(tester, app);

    expect(find.byIcon(Icons.delete_outline), findsNothing);
    await drain(tester);
  });
}
