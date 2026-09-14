// **A table made with Tab, in the whole application.**
//
// Every other test in this feature mounts a widget or two. This one mounts
// `AppShell` over a real notebook and types through the platform's own text
// input, because the defect it exists to catch could not be seen from any
// smaller vantage point: the owner pressed Tab, got their table, and then
// found their typing going into the paragraph BESIDE it.
//
// The mechanism is particular to a nested editor. A cell is a real
// `TextField` inside the paragraph's own, and a host `FocusNode` reports
// `hasFocus` true while any DESCENDANT holds the primary focus — so the host
// never learns it has stopped being the field being typed into, and holds its
// platform text-input connection open. Two clients, one keyboard. Standing the
// host's key handler and caret down was not enough; it has to give up the
// connection too, and that is what these tests pin.
//
// Settling is a fixed number of frames rather than `pumpAndSettle`: the shell
// never goes idle (a caret blinks, a status dot turns), so settling it means
// waiting ten minutes for a timeout.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/inline_atom.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/app_shell.dart';

import 'support/app.dart';
import 'support/sqlite.dart';

Future<void> settle(WidgetTester t, {int frames = 6}) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;
  late Block block;

  /// The real shell, over a real notebook, with one empty paragraph open.
  Future<void> shell(WidgetTester t) async {
    AppState.syncLogEnabled = false;
    addTearDown(() => AppState.syncLogEnabled = true);
    // Real disk I/O must run OUTSIDE the fake-async test zone, or the futures
    // it waits on never complete and the test hangs.
    await t.runAsync(() async {
      tmp = Directory.systemTemp.createTempSync('onote_shelltab_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Tab');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
      app.importPage(
          nb.id,
          page.id,
          [
            Block(
                type: BlockType.text,
                x: 40,
                y: 120,
                w: 400,
                content: {'text': ''})
          ],
          PageProps());
      app.reloadNodes();
      await app.selectPage(page.id);
      block = app.blocks.single;
    });
    addTearDown(() {
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(testApp(AppShell(app: app)));
    await settle(t);
    app.select(block.id, edit: true);
    await settle(t);
  }

  String text() => block.content['text'] as String? ?? '';
  List<List<String>> cells() => tablesIn(block.content).single.cells;

  testWidgets('type, Tab, and the next thing typed goes in the table',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(tester);

    tester.testTextInput.enterText('Element');
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await settle(tester);

    expect(cells(), [
      ['Element', '']
    ]);
    // Past the 700ms save, which notifies and rebuilds the whole tree. The
    // keyboard has to survive that: a rebuild is the moment a host field
    // would take its connection back.
    await settle(tester, frames: 20);

    // **Typed at nobody in particular** — this goes to whichever field holds
    // the platform's text-input connection, which is the whole question.
    tester.testTextInput.enterText('Symbol');
    await settle(tester);

    expect(cells(), [
      ['Element', 'Symbol']
    ], reason: 'the caret was left in the second cell, so that is where the '
        'typing belongs');
    expect(text(), contains('onote://atom/'),
        reason: 'and not a character of it reached the paragraph');
    app.cancelPendingSave();
  });

  testWidgets('Tab twice on an empty line indents twice, and makes no table',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await settle(tester);
    expect(text(), '  ');

    // The owner: "if i press tab twice it will open a table with a tab in the
    // first column which i dont really love". The indent the first Tab made
    // was enough to convince the second that something had been typed.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await settle(tester);
    expect(text(), '    ');
    expect(tablesIn(block.content), isEmpty);
    app.cancelPendingSave();
  });

  testWidgets('Escape gives the paragraph its keyboard back', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(tester);

    tester.testTextInput.enterText('Element');
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await settle(tester);
    expect(app.canFormatText, isFalse, reason: 'a cell has the keyboard');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);

    expect(app.canFormatText, isTrue,
        reason: 'and the paragraph has it back — a box that could never be '
            'typed into again would be a far worse bug than the one the gate '
            'exists to fix');
    tester.testTextInput.enterText('${text()} tail');
    await settle(tester);
    expect(text(), endsWith('tail'));
    expect(cells(), [
      ['Element', '']
    ], reason: 'and the table is still there, untouched');
    app.cancelPendingSave();
  });
}
