// v0.16 phase 4 — the task board by keyboard.
//
// Before this the board was reachable but not usable without a mouse: cards
// moved by Draggable/DragTarget and nothing else. Every claim below is made
// by sending real key events at the real shell, because the board's keys sit
// underneath the canvas's own Tab/arrow/Ctrl+arrow bindings and "they don't
// collide" is exactly the sort of thing that reads fine and isn't true.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/board_block_view.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/app_shell.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;
  late Block board;

  /// The live board's columns, read back out of app state — never the seed
  /// map, which is a different object once the page has been decoded.
  List<Map<String, dynamic>> cols() {
    final b = app.blocks.firstWhere((x) => x.id == board.id);
    return [
      for (final c in (b.content['columns'] as List)) (c as Map).cast<String, dynamic>()
    ];
  }

  List<String> cards(int col) =>
      [for (final c in (cols()[col]['cards'] as List)) '$c'];

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_board_keys_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Study');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
    board = Block(type: BlockType.board, x: 40, y: 80, w: 700, h: 320, content: {
      'columns': [
        {
          'cards': ['essay plan', 'read ch. 4'],
          'title': 'To do'
        },
        {'cards': <String>[], 'title': 'Doing'},
        {'cards': <String>[], 'title': 'Done'},
      ],
    });
    app.importPage(nb.id, page.id, [board], PageProps());
    app.reloadNodes();
    await app.selectPage(page.id);
    app.markOnboardingSeen();
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

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      theme: onoteTheme(Brightness.light),
      home: AppShell(app: app),
    ));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k,
      {bool ctrl = false, bool shift = false}) async {
    if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(k);
    await tester.sendKeyUpEvent(k);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  /// Tab to the board, Enter to step into it — the whole keyboard route in.
  Future<void> stepIn(WidgetTester tester) async {
    await key(tester, LogicalKeyboardKey.tab);
    expect(app.selectedBlockId, board.id);
    await key(tester, LogicalKeyboardKey.enter);
    expect(app.editingBlockId, board.id);
    // The board's own node must hold the keyboard now, or every assertion
    // below would really be testing the canvas.
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'board');
  }

  Future<void> flush(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
  }

  testWidgets('Ctrl+Right carries a card into the next column',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pumpShell(tester);
    await stepIn(tester);

    await key(tester, LogicalKeyboardKey.arrowRight, ctrl: true);
    expect(cards(0), ['read ch. 4'], reason: 'it left "To do"');
    expect(cards(1), ['essay plan'], reason: 'and arrived in "Doing"');

    // The cursor follows the card, so a second Ctrl+Right keeps moving THAT
    // card rather than grabbing whatever is now under the old position.
    await key(tester, LogicalKeyboardKey.arrowRight, ctrl: true);
    expect(cards(1), isEmpty);
    expect(cards(2), ['essay plan']);

    // Clamped at the last column instead of vanishing.
    await key(tester, LogicalKeyboardKey.arrowRight, ctrl: true);
    expect(cards(2), ['essay plan']);
    await flush(tester);
  });

  testWidgets('Ctrl+Down reorders inside a column, and Ctrl+Z undoes it',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pumpShell(tester);
    await stepIn(tester);

    await key(tester, LogicalKeyboardKey.arrowDown, ctrl: true);
    expect(cards(0), ['read ch. 4', 'essay plan']);
    await key(tester, LogicalKeyboardKey.arrowUp, ctrl: true);
    expect(cards(0), ['essay plan', 'read ch. 4']);

    await key(tester, LogicalKeyboardKey.arrowDown, ctrl: true);
    expect(cards(0), ['read ch. 4', 'essay plan']);
    // Every board mutation goes through the ordinary undo path.
    app.undo();
    expect(cards(0), ['essay plan', 'read ch. 4']);
    await flush(tester);
  });

  testWidgets('arrows walk cards, Enter edits the one you are on',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pumpShell(tester);
    await stepIn(tester);

    await key(tester, LogicalKeyboardKey.arrowDown); // second card
    await key(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.descendant(
        of: find.byType(BoardBlockView), matching: find.byType(TextField)));
    expect(field.controller!.text, 'read ch. 4',
        reason: 'Enter opened the card the cursor was on, not the first one');
    await flush(tester);
  });

  testWidgets('Enter at the foot of a column writes a new card',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pumpShell(tester);
    await stepIn(tester);

    // Down past the last card lands on "Add a card" — a stop on the walk,
    // not a chord to learn.
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final field = find.descendant(
        of: find.byType(BoardBlockView), matching: find.byType(TextField));
    expect(field, findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);

    await tester.enterText(field, 'past paper');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(cards(0), ['essay plan', 'read ch. 4', 'past paper']);
    await flush(tester);
  });

  testWidgets('Delete removes the card, not the whole board', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pumpShell(tester);
    await stepIn(tester);

    await key(tester, LogicalKeyboardKey.delete);
    expect(cards(0), ['read ch. 4']);
    expect(app.blocks.where((x) => x.id == board.id), hasLength(1),
        reason: 'the shell\'s own Delete must not fire through the board');
    await flush(tester);
  });

  testWidgets('a tool letter does not switch tools while on the board',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pumpShell(tester);
    final before = app.tool;
    await stepIn(tester);

    for (final k in [LogicalKeyboardKey.keyP, LogicalKeyboardKey.keyE]) {
      await key(tester, k);
    }
    expect(app.tool, before);
    await flush(tester);
  });

  testWidgets('Escape leaves the board and hands the page back',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pumpShell(tester);
    await stepIn(tester);

    await key(tester, LogicalKeyboardKey.escape);
    expect(app.editingBlockId, isNull);
    // …and block traversal is live again, which is the half that used to be
    // missed: leaving a block is only useful if the page takes the keys.
    await key(tester, LogicalKeyboardKey.tab);
    expect(app.selectedBlockId, board.id);
    await flush(tester);
  });
}
