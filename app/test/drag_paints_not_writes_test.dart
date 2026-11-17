// v1.0.2 bug 31: "dragging a selection stutters", measured as one full rebuild
// of the page per pointer sample — every block on the page, whatever was
// selected, because each sample wrote the new position into the blocks and
// notified. A drag now only accumulates `AppState.dragOffset`; what is being
// dragged follows it at paint time, and the blocks are written once, on
// release.
//
// Counted, not timed (see CONTRIBUTING): the number of times the app tells its
// listeners something changed during the drag, which is what rebuilt the page.
import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';
import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;
  late Block box;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_dragpaint_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('D');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    await app
        .selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
    app.snapToGrid = false;
    // A page with other things on it, which is what made a drag expensive.
    for (var i = 0; i < 12; i++) {
      app.addBlock(
          Block(
              type: BlockType.text,
              x: 40,
              y: 40.0 + i * 60,
              w: 160,
              h: 44,
              content: {'text': 'other $i', 'autoWidth': false}),
          recordUndo: false);
    }
    box = Block(
        type: BlockType.text,
        x: 300,
        y: 300,
        w: 300,
        h: 160,
        content: {'text': 'drag me', 'autoWidth': false});
    app.addBlock(box, recordUndo: false);
    app.select(box.id);
  });

  tearDown(() {
    AppState.syncLogEnabled = true;
    if (!haveSqlite) return;
    app.cancelPendingSave();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pump(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      // Rebuilt when the app notifies, as the shell does: the canvas itself
      // listens only to its view.
      home: Scaffold(
        body: SizedBox(
            width: 900,
            height: 700,
            child: ListenableBuilder(
                listenable: app,
                builder: (_, __) => PageCanvas(state: app))),
      ),
    ));
    await t.pump();
    await t.pump();
  }

  /// The move bar, just above the box.
  Offset bar() => app.canvas
      .pageToScreen(Offset(box.x + box.w / 2, box.y - 8));

  /// Down on the bar and past the recognizer's slop, back where it started.
  Future<TestGesture> grab(WidgetTester t) async {
    final g = await t.startGesture(bar(), kind: PointerDeviceKind.mouse);
    for (final d in const [Offset(60, 60), Offset(-60, -60)]) {
      await g.moveBy(d);
      await t.pump();
    }
    return g;
  }

  testWidgets('a drag tells the app nothing until it is let go',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(t);
    final g = await grab(t);
    var notified = 0;
    void count() => notified++;
    app.addListener(count);
    for (var i = 0; i < 30; i++) {
      await g.moveBy(const Offset(4, 2));
      await t.pump();
    }
    app.removeListener(count);
    expect(notified, 0,
        reason: 'each notification rebuilt every block on the page; there '
            'used to be one per sample');
    await g.up();
    await t.pump();
    app.cancelPendingSave();
  });

  testWidgets('the box is drawn where the drag has carried it',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(t);
    final g = await grab(t);
    // Measured from after the grab: the recognizer swallows its slop.
    final before = t.getTopLeft(find.text('drag me'));
    final startLive = app.livePosition(box);
    for (var i = 0; i < 5; i++) {
      await g.moveBy(const Offset(20, 10));
      await t.pump();
    }
    expect(box.x, 300, reason: 'nothing is written mid-drag');
    final mid = t.getTopLeft(find.text('drag me'));
    expect(mid - before, const Offset(100, 50),
        reason: 'and yet it is on screen where the pointer took it');
    final live = app.livePosition(box);
    expect(live - startLive, const Offset(100, 50));
    await g.up();
    await t.pump();
    expect(app.dragOffset.value, Offset.zero);
    final landed = Offset(box.x, box.y);
    // Written once, on release, where it was drawn — give or take the tuck
    // into line an alignment guide promises (7 px at this zoom), which is
    // applied on release by design.
    expect((landed - live).distance, lessThanOrEqualTo(7.0 * 1.5));
    expect(t.getTopLeft(find.text('drag me')) - mid, landed - live,
        reason: 'drawn exactly where the model now says, with no stale shift '
            'left over and nothing applied twice');
    app.cancelPendingSave();
  });

  testWidgets('handwriting is moved once, on release, by the whole drag',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final ink = Block(type: BlockType.ink, x: 500, y: 500, w: 130, h: 55,
        content: {
          'strokes': [
            Stroke(
              tool: 'pen',
              colorHex: '#000000',
              size: 3,
              x: const [520, 580, 630],
              y: const [520, 545, 555],
              p: const [1, 1, 1],
              t: const [0, 1, 2],
            ).toJson(),
          ]
        });
    app.addBlock(ink, recordUndo: false);
    app.select(null);
    await pump(t);
    double firstX() =>
        ((ink.content['strokes'] as List).first as Map)['x'][0] as double;
    final from = app.canvas.pageToScreen(const Offset(580, 545));
    final g = await t.startGesture(from);
    await g.moveBy(const Offset(10, 0));
    await t.pump();
    for (var i = 0; i < 4; i++) {
      await g.moveBy(const Offset(10, 0));
      await t.pump();
    }
    expect(firstX(), 520, reason: 'not rewritten per sample');
    await g.up();
    await t.pump();
    expect(firstX(), closeTo(570, 0.01),
        reason: 'moved by the whole drag, once');
    expect(ink.x, closeTo(550, 0.01));
    app.cancelPendingSave();
  });

  testWidgets('a drag that is cancelled keeps where it got to', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(t);
    final g = await grab(t);
    await g.moveBy(const Offset(40, 0));
    await t.pump();
    final there = app.livePosition(box);
    expect(there.dx, isNot(300), reason: 'precondition: it was carried');
    await g.cancel();
    await t.pump();
    expect(app.draggingBlock, isFalse);
    expect(Offset(box.x, box.y), there,
        reason: 'as when every sample was written straight away');
    expect(app.dragOffset.value, Offset.zero);
    app.cancelPendingSave();
  });

  testWidgets('a keyboard nudge is written straight away', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(t);
    app.moveSelectedBy(5, 0); // no drag in progress
    expect(box.x, 305);
    expect(app.dragOffset.value, Offset.zero);
    app.cancelPendingSave();
  });
}
