// The view keeps the caret in sight while you write.
//
// Reported: "when im typing and reach the bottom of the page, the text will
// continue to expand downwards as expected, however the viewport does not
// follow, meaning often times when typing larger things i have to manually
// scroll down mid paragraph. Please ensure that it will automatically scroll
// down with it. It needs to be gentle and non-jarring, however also needs to
// keep up with typing. Only scroll basically when needed."
//
// Three claims, and each one is a test below: it moves when the caret drops
// out of the comfortable band, it does NOT move while the caret is inside it,
// and it gets there over several frames rather than in one jump. The
// follower is driven by frame callbacks, so everything here pumps real
// frames rather than asserting on a tween's end state.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/block_view.dart';
import 'package:openote/canvas/canvas_controller.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';

import 'support/sqlite.dart';

void main() {
  late CanvasController c;

  setUp(() {
    c = CanvasController()
      ..viewport = const Size(800, 600)
      ..pageSize = const Size(800, 5000)
      ..viewportOrigin = (() => Offset.zero);
  });

  tearDown(() => c.dispose());

  /// A caret-shaped rect with its top at [top] on screen.
  Rect caretAt(double top) => Rect.fromLTWH(100, top, 2, 20);

  /// Run frames until the follower stops, or give up — a follower that never
  /// stops is itself the bug (it would keep a widget test from ever settling).
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 200 && c.isFollowingCaret; i++) {
      await t.pump(const Duration(milliseconds: 16));
    }
    expect(c.isFollowingCaret, isFalse, reason: 'the chase never ended');
  }

  group('only when needed', () {
    test('a caret in the middle of the viewport moves nothing', () {
      c.revealGlobalRect(caretAt(300));
      expect(c.offset, Offset.zero);
      expect(c.isFollowingCaret, isFalse);
    });

    test('a caret comfortably above the bottom moves nothing', () {
      // The band keeps a line and a half of room under the caret; 500 + 20 is
      // well clear of 600 - 30.
      c.revealGlobalRect(caretAt(500));
      expect(c.offset, Offset.zero);
      expect(c.isFollowingCaret, isFalse);
    });

    test('with no viewport origin installed it does nothing at all', () {
      c.viewportOrigin = null;
      c.revealGlobalRect(caretAt(9999));
      expect(c.offset, Offset.zero);
      expect(c.isFollowingCaret, isFalse);
    });
  });

  group('when the caret runs off the bottom', () {
    testWidgets('the view follows it down', (t) async {
      c.revealGlobalRect(caretAt(595)); // past the bottom of an 600px viewport
      expect(c.isFollowingCaret, isTrue, reason: 'it should want to move');
      await settle(t);
      expect(c.offset.dy, lessThan(0),
          reason: 'the page moved up, which is the view moving down');
    });

    testWidgets('and stops with the caret inside the band, not at the edge',
        (t) async {
      c.revealGlobalRect(caretAt(595));
      await settle(t);
      // Where the caret ended up on screen once the page had moved.
      final caretTop = 595 + c.offset.dy;
      expect(caretTop + 20, lessThanOrEqualTo(600 - 24),
          reason: 'it must clear the bottom margin, or the next keystroke '
              'starts the whole chase again');
      expect(caretTop, greaterThan(400),
          reason: 'the least that does it — this is not a recentre');
    });

    testWidgets('it takes several frames, so it reads as a glide', (t) async {
      c.revealGlobalRect(caretAt(700));
      var frames = 0;
      final first = c.offset.dy;
      while (c.isFollowingCaret && frames < 200) {
        await t.pump(const Duration(milliseconds: 16));
        frames++;
      }
      expect(frames, greaterThan(3),
          reason: 'one frame would be a jump, which is what "non-jarring" '
              'rules out');
      expect(frames, lessThan(40),
          reason: 'and it still has to keep up with a typist');
      expect(c.offset.dy, lessThan(first));
    });
  });

  group('when the caret goes off the top', () {
    testWidgets('the view follows it up', (t) async {
      c.offset = const Offset(0, -400); // scrolled down the page
      c.revealGlobalRect(caretAt(-5));
      expect(c.isFollowingCaret, isTrue);
      await settle(t);
      expect(c.offset.dy, greaterThan(-400));
    });
  });

  group('it does not fight the reader', () {
    testWidgets('a pan mid-chase ends the chase', (t) async {
      c.revealGlobalRect(caretAt(700));
      expect(c.isFollowingCaret, isTrue);
      await t.pump(const Duration(milliseconds: 16));

      c.panBy(const Offset(0, -50));
      expect(c.isFollowingCaret, isFalse,
          reason: 'a hand on the wheel wins; the caret can ask again');
      final parked = c.offset.dy;
      await t.pump(const Duration(milliseconds: 32));
      expect(c.offset.dy, parked, reason: 'and nothing moved after it');
    });

    testWidgets('a zoom mid-chase ends it too', (t) async {
      c.revealGlobalRect(caretAt(700));
      await t.pump(const Duration(milliseconds: 16));
      c.zoomAt(const Offset(400, 300), 1.2);
      expect(c.isFollowingCaret, isFalse);
    });
  });

  group('keeping up with typing', () {
    testWidgets('a moving target is chased, not restarted', (t) async {
      // Each keystroke pushes the caret further down while the view is still
      // on its way. A tween would restart and fall behind; the follower just
      // moves its target.
      c.revealGlobalRect(caretAt(700));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 16));
        c.revealGlobalRect(caretAt(700 + i * 20.0));
      }
      await settle(t);
      final caretTop = 700 + 5 * 20.0 + c.offset.dy;
      expect(caretTop + 20, lessThanOrEqualTo(600 - 24),
          reason: 'the last caret position is the one that has to end up '
              'visible');
    });

    testWidgets('asking again for a caret already in the band is free',
        (t) async {
      c.revealGlobalRect(caretAt(595));
      await settle(t);
      final settled = c.offset.dy;
      // The caret has not moved; this is what every keystroke elsewhere in a
      // paragraph looks like.
      c.revealGlobalRect(caretAt(595 + settled));
      expect(c.isFollowingCaret, isFalse);
      expect(c.offset.dy, settled);
    });
  });

  group('the bottom of the page', () {
    testWidgets('a caret below a page that cannot scroll further settles',
        (t) async {
      // The clamp refuses the move. The follower has to notice and stop, or
      // it schedules a frame callback for ever and no test ever settles.
      c.pageSize = const Size(800, 600); // exactly the viewport: no room
      c.revealGlobalRect(caretAt(900));
      await settle(t);
      expect(c.offset.dy, 0);
    });
  });

  // ── The wiring, through a real editing session ──────────────────────────
  //
  // Everything above tests the follower in isolation. This half asks the one
  // question that isolation cannot: does a real text field, mid-edit, report
  // where its caret is in coordinates the canvas can use?
  group('a real editor reports where its caret is', () {
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());

    testWidgets('and typing moves the view when the caret runs low',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      AppState.syncLogEnabled = false;
      late Directory tmp;
      late Repository repo;
      late AppState app;
      late Block block;
      await t.runAsync(() async {
        tmp = Directory.systemTemp.createTempSync('onote_caret_');
        repo = await Repository.openAt(tmp);
        final nb = await repo.createNotebook('C');
        app = AppState(repo)
          ..notebookId = nb.id
          ..spellCheckEnabled = false;
        app.reloadNodes();
        await app.selectPage(
            app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
        block = app.addBlock(Block(
          type: BlockType.text,
          x: 0,
          y: 0,
          w: 300,
          content: {'text': 'note', 'autoWidth': false},
        ));
        app.select(null);
      });
      addTearDown(() {
        AppState.syncLogEnabled = true;
        app.cancelPendingSave();
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      await t.pumpWidget(MaterialApp(
        localizationsDelegates: kOnoteLocalizations,
        supportedLocales: kOnoteLocales,
        theme: onoteTheme(Brightness.light),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: app,
            builder: (_, __) => Stack(children: [
              BlockView(block: block, app: app, controller: app.canvas),
            ]),
          ),
        ),
      ));
      await t.pump();
      app.select(block.id, edit: true);
      await t.pump();
      await t.pump();

      final rect = app.activeSession!.caretRectGlobal();
      expect(rect, isNotNull,
          reason: 'a live field must be able to say where its caret is — '
              'without this the canvas has nothing to follow');
      expect(rect!.height, greaterThan(0));

      // A viewport whose bottom edge sits just above the caret, so the very
      // next keystroke is the one that runs out of room.
      app.canvas
        ..viewport = Size(800, rect.bottom - 4)
        ..pageSize = const Size(800, 5000)
        ..viewportOrigin = (() => Offset.zero);
      expect(app.canvas.offset.dy, 0);

      final c = app.activeEditor!.controller;
      c.value = TextEditingValue(
        text: '${c.text} more',
        selection: TextSelection.collapsed(offset: c.text.length + 5),
      );
      // One frame for the field to lay the new text out, then the deferred
      // check runs and the follower starts.
      await t.pump();
      await t.pump();
      for (var i = 0; i < 200 && app.canvas.isFollowingCaret; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
      expect(app.canvas.offset.dy, lessThan(0),
          reason: 'typing at the bottom edge should have brought the view '
              'down with it');
      app.cancelPendingSave();
    });
  });
}
