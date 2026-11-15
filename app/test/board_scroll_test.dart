// Scrolling inside a board stays inside the board.
//
// Reported: *"scrolling inside the board is making the main page also
// scroll."* Measured on the shipped build before anything was changed, with
// a six-column board 700px wide on a page:
//
//   * a wheel notch over the board moved the PAGE 120px and the board 0,
//     while 654px of columns sat off the right-hand edge unreachable;
//   * a two-finger vertical pan over the board did the same;
//   * a column of thirty cards overflowed its own block by 859px, cards
//     that could not be reached at all.
//
// Graphs hit the same thing first (`graph_block_test.dart`), and the two
// mechanisms that fixed it are the two used here: a wheel notch goes
// through `GestureBinding.pointerSignalResolver`, and a trackpad's
// `PointerPanZoom` family (dispatched to every `Listener` on the chain
// rather than resolved) goes through `AppState.claimedPointers`, which
// `PageCanvas` checks before it pans.
//
// The last test is the one that keeps the fix honest: a board with nothing
// to scroll must NOT hold the gesture, or the page could not be scrolled
// past a board at all.

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/editor/board_block_view.dart';
import 'package:openote/l10n/l10n.dart';
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

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_boardscroll_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('F');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
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

  /// A board on a page, under a canvas big enough that the page itself has
  /// somewhere to scroll; otherwise "the page did not move" proves nothing.
  Future<Offset> pumpBoard(WidgetTester t,
      {int columns = 6, int cards = 2}) async {
    final nb = app.notebookId!;
    final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
    app.importPage(
        nb,
        page.id,
        [
          Block(
              type: BlockType.text,
              x: 60,
              y: 1600,
              w: 480,
              content: {'text': 'A paragraph well below the board.'}),
          Block(type: BlockType.board, x: 60, y: 160, w: 700, h: 300, content: {
            'columns': [
              for (var i = 0; i < columns; i++)
                {
                  'title': 'Col $i',
                  'cards': [for (var j = 0; j < cards; j++) 'card $i-$j']
                },
            ]
          }),
        ],
        PageProps());
    app.reloadNodes();
    await app.selectPage(page.id);
    app.markOnboardingSeen();
    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: Scaffold(
        body: ListenableBuilder(
          listenable: app,
          builder: (_, __) => PageCanvas(state: app),
        ),
      ),
    ));
    await t.pump();
    return t.getCenter(find.byType(BoardBlockView).first);
  }

  /// The board's own sideways scroller: the outermost one inside the board.
  ScrollableState boardScroller(WidgetTester t) => t.state<ScrollableState>(find
      .descendant(
          of: find.byType(BoardBlockView), matching: find.byType(Scrollable))
      .first);

  /// The card scroller of the column at [index].
  ScrollableState columnScroller(WidgetTester t, int index) =>
      t.state<ScrollableState>(find
          .descendant(
              of: find.byType(BoardBlockView),
              matching: find.byType(Scrollable))
          .at(index + 1));

  Future<void> trackpadPan(WidgetTester t, Offset where, Offset by) async {
    final p = TestPointer(1, PointerDeviceKind.trackpad);
    await t.sendEventToBinding(p.panZoomStart(where));
    await t.sendEventToBinding(p.panZoomUpdate(where, pan: by / 2));
    await t.sendEventToBinding(p.panZoomUpdate(where, pan: by));
    await t.sendEventToBinding(p.panZoomEnd());
    await t.pump();
  }

  group('the wheel over a board', () {
    testWidgets('scrolls the board and leaves the page where it is',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final where = await pumpBoard(t);
      final wasPage = app.canvas.offset;
      expect(boardScroller(t).position.maxScrollExtent, greaterThan(0),
          reason: 'the fixture has columns off the right-hand edge');

      final p = TestPointer(1, PointerDeviceKind.mouse);
      p.hover(where);
      await t.sendEventToBinding(p.scroll(const Offset(0, 120)));
      await t.pump();

      expect(boardScroller(t).position.pixels, 120,
          reason: 'a board is a sideways thing: the notch went sideways');
      expect(app.canvas.offset, wasPage,
          reason: 'and the page did not move an inch');
      app.cancelPendingSave();
    });

    testWidgets('scrolls the cards when the column under it has some',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final where = await pumpBoard(t, columns: 2, cards: 30);
      final wasPage = app.canvas.offset;
      final column = columnScroller(t, 0);
      expect(column.position.maxScrollExtent, greaterThan(0));

      final p = TestPointer(1, PointerDeviceKind.mouse);
      p.hover(t.getCenter(find.text('card 0-3')));
      await t.sendEventToBinding(p.scroll(const Offset(0, 120)));
      await t.pump();

      expect(column.position.pixels, 120, reason: 'the cards scrolled');
      expect(app.canvas.offset, wasPage, reason: 'the page did not');
      app.cancelPendingSave();
    });
  });

  group('a trackpad over a board', () {
    testWidgets('a sideways pan scrolls the board, not the page', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final where = await pumpBoard(t);
      final wasPage = app.canvas.offset;

      await trackpadPan(t, where, const Offset(-120, 0));

      expect(boardScroller(t).position.pixels, 120);
      expect(app.canvas.offset, wasPage);
      app.cancelPendingSave();
    });

    testWidgets('a vertical pan over cardless columns still moves the board, '
        'not the page', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final where = await pumpBoard(t, cards: 0);
      final wasPage = app.canvas.offset;

      await trackpadPan(t, where, const Offset(0, -120));

      expect(boardScroller(t).position.pixels, 120,
          reason: 'nothing to scroll downwards, so it is spent sideways, '
              'the same answer the wheel gives');
      expect(app.canvas.offset, wasPage, reason: 'the page stayed put');
      app.cancelPendingSave();
    });

    testWidgets('a vertical pan scrolls the cards, not the page', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpBoard(t, columns: 2, cards: 30);
      final wasPage = app.canvas.offset;
      final column = columnScroller(t, 0);

      await trackpadPan(t, t.getCenter(find.text('card 0-3')),
          const Offset(0, -120));

      expect(column.position.pixels, greaterThan(0));
      expect(app.canvas.offset, wasPage);
      app.cancelPendingSave();
    });
  });

  testWidgets('a board with nothing to scroll does not hold the page still',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // The default board: three columns, no cards, well inside its block. If
    // this one claimed the gesture there would be no way to scroll the page
    // past a board, which is a worse bug than the one being fixed.
    final where = await pumpBoard(t, columns: 3, cards: 0);
    expect(boardScroller(t).position.maxScrollExtent, 0,
        reason: 'the fixture fits its block');
    final wasPage = app.canvas.offset;

    await trackpadPan(t, where, const Offset(0, -120));
    expect(app.canvas.offset.dy, lessThan(wasPage.dy),
        reason: 'the page scrolled, as it always did');

    final p = TestPointer(1, PointerDeviceKind.mouse);
    p.hover(where);
    final beforeWheel = app.canvas.offset;
    await t.sendEventToBinding(p.scroll(const Offset(0, 120)));
    await t.pump();
    expect(app.canvas.offset.dy, lessThan(beforeWheel.dy),
        reason: 'and so did the wheel');
    app.cancelPendingSave();
  });

  testWidgets('a tall column no longer overflows its block', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pumpBoard(t, columns: 2, cards: 30);
    expect(t.takeException(), isNull,
        reason: 'thirty cards used to overflow the board by 859px');
    app.cancelPendingSave();
  });

  testWidgets('a column that fits is still only as tall as its cards',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // `Flexible`, not `Expanded`: short columns must not grow to fill the
    // block now that their cards live in a scroller.
    await pumpBoard(t, columns: 3, cards: 1);
    final column = t.getSize(find
        .descendant(
            of: find.byType(BoardBlockView), matching: find.byType(Container))
        .first);
    expect(column.height, lessThan(200),
        reason: 'a one-card column is short, as it has always looked');
    app.cancelPendingSave();
  });
}
