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

    test('and the side button does what it has been set to', () {
      expect(PenButtons.erases(PenButton.barrel, PenButtonAction.eraser),
          isTrue);
      expect(PenButtons.erases(PenButton.barrel, PenButtonAction.select),
          isFalse);
      expect(PenButtons.selects(PenButton.barrel, PenButtonAction.select),
          isTrue);
      expect(PenButtons.selects(PenButton.barrel, PenButtonAction.eraser),
          isFalse);
    });

    test('nothing means nothing, which is the honest third option', () {
      expect(PenButtons.erases(PenButton.barrel, PenButtonAction.nothing),
          isFalse);
      expect(PenButtons.selects(PenButton.barrel, PenButtonAction.nothing),
          isFalse);
    });

    test('and no buttons held is neither', () {
      expect(PenButtons.erases(0, PenButtonAction.eraser), isFalse);
      expect(PenButtons.selects(0, PenButtonAction.select), isFalse);
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

    testWidgets('A BARREL PRESS ARRIVES, AND ERASES', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await openPage(t);
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

    testWidgets('OR SELECTS, WHEN THAT IS WHAT IT IS SET TO', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await openPage(t);
      app.setPenButton(PenButtonAction.select);
      app.setTool(Tool.pen);
      await t.pump();

      await send(PenButton.barrel);
      await t.pump();
      expect(app.tool, Tool.select, reason: 'held means selecting');
      expect(app.penErasing, isFalse, reason: 'and not erasing');

      await send(0);
      await t.pump();
      expect(app.tool, Tool.pen,
          reason: 'and the pen comes back when it is let go, because a mode '
              'you have to leave by hand is a mode');
      await settleSettings(t);
    });

    testWidgets('the tail erases even when the side button selects',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await openPage(t);
      app.setPenButton(PenButtonAction.select);
      app.setTool(Tool.pen);
      await t.pump();

      await send(PenButton.eraser);
      await t.pump();

      expect(app.penErasing, isTrue);
      expect(app.tool, Tool.pen, reason: 'the tool did not change hands');
      await settleSettings(t);
    });
  });
}
