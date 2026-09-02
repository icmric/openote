// Pressing DEG or RAD must not take the caret out of the equation.
//
// The owner: *"When im in the equation and click on the Deg or Rad button to
// change it, it kicks me out of the equation and i have to click on it again
// to start editing again, not ideal."*
//
// The cause was not the button. `setAngleMode` bumped `docRevision`, and
// every block on the canvas is keyed by it — so the press tore the page down
// and rebuilt it, disposing the equation editor mid-edit. These tests run the
// REAL command bar against a REAL block being edited, because a harness with
// a stand-in editor cannot see a teardown that happens two widgets away.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/editor/inline_math_editor.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/math/evaluate.dart';
import 'package:openote/math/math_field.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/command_bar.dart';
import 'package:openote/ui/math_bar.dart';
import 'package:openote/ui/object_row.dart';

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
    tmp = Directory.systemTemp.createTempSync('onote_angfocus_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('T');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
  });

  tearDown(() {
    AppState.syncLogEnabled = true;
    mathAngleMode = AngleMode.degrees;
    if (!haveSqlite) return;
    app.cancelPendingSave();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// The whole window: the real bar above the real page, so a press on one
  /// is felt by the other exactly as it is in the app.
  Future<Block> openEquation(WidgetTester tester) async {
    tester.view.physicalSize = const Size(2600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final b = app.insertEquation(at: const Offset(20, 20));
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: Scaffold(
        body: ListenableBuilder(
          listenable: app,
          builder: (_, __) => Column(children: [
            CommandBar(app: app),
            // DEG/RAD lives on the object row now, not on the bar.
            ObjectRow(app: app),
            Expanded(child: PageCanvas(state: app)),
          ]),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return b;
  }

  Future<void> type(WidgetTester tester, String ch) async {
    final key = switch (ch) {
      '+' => LogicalKeyboardKey.equal,
      '(' => LogicalKeyboardKey.digit9,
      ')' => LogicalKeyboardKey.digit0,
      '=' => LogicalKeyboardKey.equal,
      ' ' => LogicalKeyboardKey.space,
      _ => LogicalKeyboardKey(ch.codeUnitAt(0)),
    };
    await tester.sendKeyDownEvent(key, character: ch);
    await tester.sendKeyUpEvent(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
  }

  testWidgets('the caret stays in the equation across a DEG press',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final b = await openEquation(tester);
    await type(tester, '2');
    expect(b.content['latex'], '2', reason: 'the equation has the keyboard');

    expect(find.text('DEG'), findsOneWidget);
    await tester.tap(find.text('DEG'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(app.angleMode, AngleMode.radians, reason: 'the press did its job');
    expect(find.byType(MathField), findsOneWidget,
        reason: 'and did not tear the editor down on the way');

    // The real proof: the very next keystroke still lands in the equation.
    await type(tester, '7');
    expect(b.content['latex'], '27',
        reason: 'pressing a toolbar button is not a request to stop writing');
    app.cancelPendingSave();
  });

  testWidgets('and back again, twice, with the equation still live',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final b = await openEquation(tester);
    await type(tester, '5');
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text(i.isEven ? 'DEG' : 'RAD'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(app.angleMode, AngleMode.degrees);
    await type(tester, '9');
    expect(b.content['latex'], '59');
    app.cancelPendingSave();
  });

  testWidgets('a symbol press keeps the caret too — the rule is bar-wide, '
      'not one button', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final b = await openEquation(tester);
    await type(tester, '3');
    final chips = find.byType(MathChip);
    expect(chips, findsWidgets, reason: 'the Maths row is up');
    await tester.tap(chips.first, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await type(tester, '4');
    expect(b.content['latex'], contains('4'),
        reason: 'the equation kept the keyboard through a palette press — '
            'the 4 may land inside whatever slot the chip opened, but it '
            'lands in the equation');
    app.cancelPendingSave();
  });

  testWidgets('and an equation inside a SENTENCE keeps it too', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    tester.view.physicalSize = const Size(2600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final b = Block(
      id: 'p1',
      type: BlockType.text,
      x: 20,
      y: 20,
      w: 400,
      content: {'text': r'we know $x$ here', 'autoWidth': false},
    );
    app.blocks.add(b);
    app.editingBlockId = 'p1';
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: Scaffold(
        body: ListenableBuilder(
          listenable: app,
          builder: (_, __) => Column(children: [
            CommandBar(app: app),
            // DEG/RAD lives on the object row now, not on the bar.
            ObjectRow(app: app),
            Expanded(child: PageCanvas(state: app)),
          ]),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // The right edge, not dead centre: a click now lands the caret where it
    // fell (math_click_position_test.dart), and a centred click on a
    // one-character equation like `$x$` is genuinely ambiguous between its
    // two ends — this test wants the ordinary "opened, ready to keep
    // typing" state, unrelated to click position.
    final atom = tester.getRect(find.byType(InlineMathAtom));
    await tester.tapAt(Offset(atom.right - 1, atom.center.dy));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(MathField), findsOneWidget);
    await type(tester, '2');

    expect(find.text('DEG'), findsOneWidget, reason: 'the Maths row is up');
    await tester.tap(find.text('DEG'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(MathField), findsOneWidget,
        reason: 'the editor is still mounted — with the page keyed on '
            'docRevision this was 0, the equation torn out mid-word');
    await type(tester, '7');
    expect(b.content['text'], r'we know $x27$ here',
        reason: 'the sentence kept the equation, and the equation kept the '
            'keyboard');
    app.cancelPendingSave();
  });
}
