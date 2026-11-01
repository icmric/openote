// INK-1 / INK-4: when a finger draws, and when it must not.
//
// The regression pinned here is C-8: every touch used to be routed to pan
// unconditionally, so ink was simply unreachable on a touch-only tablet. Palm
// rejection is meant to be stylus-CONDITIONAL — a resting palm is only a hazard
// while a pen is in use.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';
import 'package:openote/l10n/labels.dart';

import 'support/app.dart';
import 'support/sqlite.dart';

import 'package:openote/canvas/ink_ops.dart';
import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

bool draws(TouchDrawing mode,
        {int touches = 1, bool stylus = false, bool penEver = false}) =>
    touchShouldDraw(
        mode: mode,
        activeTouches: touches,
        stylusActive: stylus,
        penEverSeen: penEver);

void main() {
  group('auto — the default', () {
    test('a finger draws when no stylus is around (C-8)', () {
      // The whole point: on a touch-only tablet this used to be false, which
      // made the pen tools dead controls.
      expect(draws(TouchDrawing.auto), isTrue);
    });

    test('a finger pans while a stylus is in use, so a palm cannot mark', () {
      expect(draws(TouchDrawing.auto, stylus: true), isFalse);
    });

    test('AND GOES ON PANNING LONG AFTER THE PEN WAS PUT DOWN', () {
      // *"It sometimes will still use finger input when im drawing with the
      // pen as drawing, it should never use regular touch to draw when a pen
      // has been used."* The stylus grace window is two seconds, which is
      // shorter than the pause between two written words — so a hand resting
      // on the page drew. The question is whether a pen has ever been used
      // here, not whether one moved a moment ago.
      expect(draws(TouchDrawing.auto, stylus: false, penEver: true), isFalse);
    });

    test('two fingers always pan, so the canvas stays navigable', () {
      expect(draws(TouchDrawing.auto, touches: 2), isFalse);
    });
  });

  group('explicit overrides', () {
    test('always draws even with a stylus present', () {
      expect(draws(TouchDrawing.always, stylus: true), isTrue);
    });

    test('always still means always on a machine that has a pen', () {
      // "Unless explicitly set" — this is the explicit setting.
      expect(draws(TouchDrawing.always, penEver: true), isTrue);
    });

    test('always still yields to a second finger', () {
      // A pinch must never be interpreted as a stroke, whatever the setting —
      // otherwise zooming leaves a mark.
      expect(draws(TouchDrawing.always, touches: 2), isFalse);
    });

    test('never keeps the old strict behaviour', () {
      expect(draws(TouchDrawing.never), isFalse);
      expect(draws(TouchDrawing.never, stylus: false, touches: 1), isFalse);
    });
  });

  group('on a real canvas', () {
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());

    late Directory tmp;
    late Repository repo;
    late AppState app;
    var now = DateTime(2026, 10, 17, 9);

    setUp(() {
      AppState.syncLogEnabled = false;
      now = DateTime(2026, 10, 17, 9);
      PageCanvas.clock = () => now;
      tmp = Directory.systemTemp.createTempSync('onote_touchdraw_');
    });

    tearDown(() {
      PageCanvas.clock = DateTime.now;
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

    Future<void> drag(WidgetTester t, PointerDeviceKind kind, Offset from,
        Offset to) async {
      // Which pointer handler wraps the canvas is decided at build time from
      // `app.tool`, so the tool has to have been built before the gesture.
      await t.pump();
      final g = await t.startGesture(from, kind: kind);
      for (var i = 1; i <= 4; i++) {
        await g.moveTo(Offset.lerp(from, to, i / 4)!);
        await t.pump();
      }
      await g.up();
      await t.pump();
      app.cancelPendingSave();
    }

    int inkBlocks() => app.blocks.where((b) => b.type == BlockType.ink).length;

    testWidgets('A FINGER STOPS DRAWING ONCE A PEN HAS BEEN USED', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await openPage(t);
      app.setTool(Tool.pen);
      expect(app.penSeenHere, isFalse, reason: 'nothing has been used yet');

      await drag(t, PointerDeviceKind.stylus, const Offset(120, 120),
          const Offset(200, 160));
      expect(inkBlocks(), 1, reason: 'the pen drew');
      expect(app.penSeenHere, isTrue, reason: 'and the canvas said so');

      // **Half a minute later**, which is the whole point: the stylus grace
      // window is two seconds, and a hand rests on the page for longer than
      // that between two words.
      now = now.add(const Duration(seconds: 30));
      final before = app.canvas.offset;

      // Up and to the left, which scrolls DOWN the page: the other direction
      // is clamped at the top of the page, and an offset that cannot move is
      // not evidence of anything.
      await drag(t, PointerDeviceKind.touch, const Offset(380, 340),
          const Offset(300, 300));

      expect(inkBlocks(), 1, reason: 'the finger drew nothing');
      expect(app.canvas.offset, isNot(before),
          reason: 'it panned the page, which is what touch is for here');
    });

    testWidgets('and a finger draws on a machine that has never seen one',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await openPage(t);
      app.setTool(Tool.pen);

      await drag(t, PointerDeviceKind.touch, const Offset(120, 120),
          const Offset(200, 160));

      expect(inkBlocks(), 1,
          reason: 'INK-1: on a touch-only tablet a finger is all there is');
    });
  });

  testWidgets('every mode has a translated label for the Draw tab',
      (tester) async {
    // Through `L`, not a const getter: the names moved into the .arb so the
    // Draw row is not three English words inside an otherwise translated app.
    // The loop is the point — a mode added without a message turns this red at
    // the switch, which is where it should be caught.
    late L l;
    await tester.pumpWidget(testApp(Builder(builder: (context) {
      l = L.of(context);
      return const SizedBox();
    })));
    for (final m in TouchDrawing.values) {
      expect(m.label(l), isNotEmpty);
    }
  });
}
