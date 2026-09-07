// The pen picks the tool up, and the mouse puts it back down.
//
// The owner, on the "Done" chip that used to be the only way back out of
// inking: *"when i click that the colour options disapear and it gets
// replaced with some text, this makes no sense to me, we shouldnt have
// defined drawing and other modes that the user has to manually switch
// between, always take all inputs other than pen as they already are, but
// automatically switch to inking when a pen comes close to the screen (which
// it does do), but then switch back for other inputs and whatnot."*
//
// The pen half already worked. What was missing was the other half, so the
// switch was one-way and needed a button to undo — which is exactly what a
// mode is.
//
// The flag that makes the second half safe is `toolWasAutomatic`: a tool the
// app reached for is the app's to put back, and a tool somebody CHOSE is
// theirs. Without it, reaching for the mouse would take the pen off anybody
// drawing with a mouse — which is everybody without a pen.

import 'dart:io';

import 'package:flutter/gestures.dart';
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
    await tester.pumpWidget(testApp(Scaffold(body: PageCanvas(state: app))));
    await tester.pump();
    return app;
  }

  /// A pointer of [kind] floating over the page without touching it — which
  /// is how a pen announces itself, and how a mouse announces that it is back.
  Future<void> hover(WidgetTester tester, PointerDeviceKind kind,
      {int pointer = 1}) async {
    final g = await tester.createGesture(kind: kind, pointer: pointer);
    await g.addPointer(location: const Offset(400, 300));
    addTearDown(() => g.removePointer());
    await g.moveTo(const Offset(410, 305));
    await tester.pump();
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 900));
  }

  testWidgets('a pen coming close means ink, with no toolbar trip',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await canvas(tester, 'onote_tool_pen_');
    expect(app.tool, Tool.select);

    await hover(tester, PointerDeviceKind.stylus);

    expect(app.tool, Tool.pen);
    expect(app.toolWasAutomatic, isTrue,
        reason: 'the app reached for this one, so it is the app to put back');
    await drain(tester);
  });

  testWidgets('and a mouse coming back puts it down again', (tester) async {
    // Straight to the state a pen leaves behind, rather than through a real
    // stylus hover: a pen counts as "in range" for a couple of seconds after
    // its last signal — on purpose, so a hand moving between pen and mouse
    // does not make the toolbar flicker — and that window is wall-clock, not
    // the test's clock.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await canvas(tester, 'onote_tool_mouse_');
    app.setTool(Tool.pen, automatic: true);
    await tester.pump();

    await hover(tester, PointerDeviceKind.mouse, pointer: 2);

    expect(app.tool, Tool.select,
        reason: 'the mouse is not a drawing instrument by default');
    await drain(tester);
  });

  testWidgets('a tool somebody chose is not taken off them', (tester) async {
    // The whole reason the flag exists. Everybody without a pen draws with a
    // mouse, and a mouse that cancelled the pen would make that impossible.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await canvas(tester, 'onote_tool_chosen_');
    app.setTool(Tool.pen);
    await tester.pump();

    await hover(tester, PointerDeviceKind.mouse, pointer: 3);

    expect(app.tool, Tool.pen);
    await drain(tester);
  });

  test('picking Select clears the claim, so nothing is put back twice', () {
    // `setTool(Tool.select, automatic: true)` would otherwise leave the app
    // believing it still had a tool out on loan.
    final app = AppState(_NoopRepo());
    app.setTool(Tool.pen, automatic: true);
    app.setTool(Tool.select, automatic: true);
    expect(app.toolWasAutomatic, isFalse);
  });
}

class _NoopRepo implements Repository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
