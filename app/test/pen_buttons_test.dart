// The pen's buttons, from the runner, since the engine will not say.
//
// *"The buttons on the pen still dont work for erasing and selecting, which is
// what they are set to as a computer level on my device … Really want this
// working as its currently one of the most significant downaides when compared
// to onenote."*
//
// The reason it never worked is not in this app: Flutter's Windows embedder
// reads a pen's pressure and rotation out of `POINTER_PEN_INFO`, never looks
// at `penFlags`, and reports every pen contact as the left mouse button. No
// arrangement of button bits on this side could have found a barrel press.
// `windows/runner/pen_buttons.cpp` reads the flags off the window messages and
// sends them over a channel; this is the half of that which can be tested
// without a digitiser.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/core/pen_buttons.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/app.dart';
import 'support/sqlite.dart';

/// Hand the app a message exactly as the runner's channel would.
Future<void> send(int bits) =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      PenButtons.channel.name,
      PenButtons.channel.codec.encodeMethodCall(MethodCall('buttons', bits)),
      (_) {},
    );

void main() {
  group('what a held button means', () {
    test('THE TAIL IS AN ERASER WHATEVER THE SIDE BUTTON IS FOR', () {
      for (final side in PenButtonAction.values) {
        expect(PenButtons.erases(PenButton.eraser, side), isTrue);
        expect(PenButtons.erases(PenButton.inverted, side), isTrue);
      }
    });

    test('WHAT THE DRIVER CALLS THE ERASER ERASES, WHATEVER THE SETTING', () {
      // Measured on the owner's machine: the button their pen driver maps to
      // "eraser" reports PEN_FLAG_INVERTED while hovering. Windows models an
      // eraser as the pen turned round, so that bit IS the system-level
      // meaning they chose — *"id ideally like them to be what they are
      // defined at a system level to be"* — and no setting has anything to
      // add to it.
      for (final side in PenButtonAction.values) {
        expect(PenButtons.erases(PenButton.inverted, side), isTrue);
        expect(PenButtons.toolFor(PenButton.inverted, side), isNull,
            reason: 'and it never borrows a tool instead');
      }
    });

    test('THE BARREL BORROWS THE TOOL IT IS SET TO, LASSO BY DEFAULT', () {
      // "Barrel button" is not an action — it is Windows' name for a generic
      // secondary press — so this is the configurable one. OneNote lassoes
      // with it, which is why that is the default.
      expect(PenButtons.toolFor(PenButton.barrel, PenButtonAction.lasso),
          Tool.lasso);
      expect(PenButtons.toolFor(PenButton.barrel, PenButtonAction.select),
          Tool.select);
      expect(PenButtons.toolFor(PenButton.barrel, PenButtonAction.eraser),
          isNull, reason: 'that one erases rather than borrowing');
      expect(PenButtons.toolFor(PenButton.barrel, PenButtonAction.nothing),
          isNull);
    });

    test('and nothing means nothing, which is the honest fourth option', () {
      expect(PenButtons.erases(PenButton.barrel, PenButtonAction.nothing),
          isFalse);
      expect(PenButtons.toolFor(PenButton.barrel, PenButtonAction.nothing),
          isNull);
    });

    test('and no buttons held is neither', () {
      expect(PenButtons.erases(0, PenButtonAction.eraser), isFalse);
      for (final side in PenButtonAction.values) {
        expect(PenButtons.toolFor(0, side), isNull);
      }
    });
  });

  group('on a canvas', () {
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());

    late Directory tmp;
    late Repository repo;
    late AppState app;

    setUp(() {
      AppState.syncLogEnabled = false;
      PenButtons.listen();
      PenButtons.bits.value = 0;
      tmp = Directory.systemTemp.createTempSync('onote_penbtn_');
    });

    tearDown(() {
      PenButtons.bits.value = 0;
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

    /// Let the workspace-settings debounce fire. `notePenSeen` writes a
    /// setting, and a test that ends with its timer still pending fails on
    /// the pending timer rather than on anything it was asking about.
    Future<void> settleSettings(WidgetTester t) =>
        t.pump(const Duration(milliseconds: 500));

    testWidgets('A BARREL PRESS ARRIVES, AND ERASES WHERE SET TO', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await openPage(t);
      app.setPenButton(PenButtonAction.eraser);
      app.setTool(Tool.pen);
      await t.pump();
      expect(app.penErasing, isFalse);

      await send(PenButton.barrel);
      await t.pump();

      expect(app.penErasing, isTrue,
          reason: 'which is what draws the eraser cursor and lights the '
              'tool indicator before any ink is touched');
      expect(app.penSeenHere, isTrue,
          reason: 'a pen flag can only have come from a pen');

      await send(0);
      await t.pump();
      expect(app.penErasing, isFalse, reason: 'and letting go gives it back');
      await settleSettings(t);
    });

    testWidgets('OR BORROWS THE LASSO, WHICH IS THE DEFAULT', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await openPage(t);
      app.setTool(Tool.pen);
      await t.pump();
      expect(app.penButton, PenButtonAction.lasso,
          reason: 'out of the box, as in OneNote');

      await send(PenButton.barrel);
      await t.pump();
      expect(app.tool, Tool.lasso, reason: 'held means lassoing');
      expect(app.penErasing, isFalse, reason: 'and not erasing');

      await send(0);
      await t.pump();
      expect(app.tool, Tool.pen,
          reason: 'and the pen comes back when it is let go, because a mode '
              'you have to leave by hand is a mode');
      await settleSettings(t);
    });

    testWidgets('A HELD BARREL DOES NOT ALSO OPEN A CONTEXT MENU', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // With Windows Ink off, a driver synthesises the mouse itself and the
      // barrel arrives as a real right-click, so the button is reported AND a
      // menu gesture is delivered. The menu gives way, because the student
      // has said what that button is for.
      await openPage(t);
      app.setTool(Tool.select);
      await t.pump();

      await send(PenButton.barrel);
      await t.pump();
      final g = await t.startGesture(const Offset(400, 300),
          kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await g.up();
      await t.pumpAndSettle();

      expect(find.text('Paste'), findsNothing,
          reason: 'the canvas menu would have opened on top of the erase');

      // ...and with the button set to do nothing, the menu is the most useful
      // thing a barrel press can do, which is what Windows itself does.
      await send(0);
      app.setPenButton(PenButtonAction.nothing);
      await t.pump();
      await send(PenButton.barrel);
      await t.pump();
      final g2 = await t.startGesture(const Offset(400, 300),
          kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await g2.up();
      await t.pumpAndSettle();

      expect(find.text('Paste'), findsOneWidget);
      await t.tapAt(const Offset(10, 10)); // dismiss it
      await t.pumpAndSettle();
      await settleSettings(t);
    });

    testWidgets('A HOVER WITH NO BUTTONS DOES NOT UNDO THE CHANNEL',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The one that made the feature look broken from the outside. Windows'
      // engine reports every pen event with no buttons at all, and hover
      // arrives at stylus rate — so a hover a millisecond after the channel
      // said "barrel down" said "nothing is held" and took it back. *"The
      // lasso doesnt seem to work, when set it just draws every time."*
      await openPage(t);
      app.setTool(Tool.pen);
      await t.pump();

      await send(PenButton.barrel);
      await t.pump();
      expect(app.tool, Tool.lasso);

      // Exactly what the engine sends for a hovering pen on Windows.
      await t.sendEventToBinding(const PointerHoverEvent(
        kind: PointerDeviceKind.stylus,
        pointer: 11,
        position: Offset(400, 300),
      ));
      await t.pump();

      expect(app.tool, Tool.lasso,
          reason: 'an event that cannot carry a button is not evidence that '
              'none is held');

      // And the eraser half of the same race.
      await send(0);
      app.setPenButton(PenButtonAction.eraser);
      await send(PenButton.barrel);
      await t.pump();
      expect(app.penErasing, isTrue);
      await t.sendEventToBinding(const PointerHoverEvent(
        kind: PointerDeviceKind.stylus,
        pointer: 11,
        position: Offset(401, 300),
      ));
      await t.pump();
      expect(app.penErasing, isTrue,
          reason: '"rubs it out most times but not every time" was this');
      await settleSettings(t);
    });

    testWidgets('A PEN CARRIED OFF MID-PRESS DOES NOT STAY LASSOING',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The runner reports a button only while the pen is in range, so a pen
      // lifted away mid-press sends nothing to say it was let go. The erase
      // half of this was found by review; this half was found by that
      // review's own test going red when the default became the lasso.
      await openPage(t);
      // Time held still rather than shortened, and set BEFORE the press: the
      // press is what records "a pen was here", so a clock installed after it
      // records the moment on the real timeline and then reads it on the fake
      // one, which runs backwards.
      var now = DateTime(2026);
      PageCanvas.clock = () => now;
      addTearDown(() => PageCanvas.clock = DateTime.now);
      app.setTool(Tool.pen);
      await t.pump();

      await send(PenButton.barrel);
      await t.pump();
      expect(app.tool, Tool.lasso);

      // The pen goes away without ever letting the button go, and a mouse
      // arrives. Exactly past the grace, because the clock does what it is
      // told.
      now = now.add(PageCanvas.stylusGrace * 2);
      await t.sendEventToBinding(const PointerHoverEvent(
          kind: PointerDeviceKind.mouse,
          pointer: 9,
          position: Offset(400, 300)));
      await t.pump();

      // A mouse arriving with no pen in range puts the pen down on its own,
      // so the tool is Select here whether or not the borrow was given back.
      // What the borrow costs if it is NOT given back is a latch left
      // pointing at the pen: the next release restores it and takes away
      // whatever was chosen in between. That is the observable.
      expect(app.tool, Tool.select);
      app.setTool(Tool.text); // deliberately, with no pen anywhere near
      await t.pump();

      await send(0); // the button finally reported as let go
      await t.pump();

      expect(app.tool, Tool.text,
          reason: 'a stale latch would have restored the pen over the top of '
              'a tool the student had just chosen');
      await settleSettings(t);
    });

    testWidgets('the eraser button erases even while the barrel lassoes',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await openPage(t);
      app.setTool(Tool.pen);
      await t.pump();

      // 0x2 — what the owner's eraser-mapped button actually sends.
      await send(PenButton.inverted);
      await t.pump();

      expect(app.penErasing, isTrue);
      expect(app.tool, Tool.pen, reason: 'the tool did not change hands');
      await settleSettings(t);
    });
  });
}
