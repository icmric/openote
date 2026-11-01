// Editing and deleting a board card with a mouse.
//
// v1.0.2 #6: *"Board cards cannot be deleted or edited."* Two separate
// faults, both measured in the whole shell before anything was changed:
//
//   * a click on a card OPENED its editor and then dropped every keystroke.
//     It asked for the keyboard with `autofocus`, which Flutter ignores while
//     anything in the scope holds focus — and the canvas takes focus on every
//     pointer-down while no block is being edited, which is exactly the state
//     of somebody clicking a board on a page;
//   * there was no way to delete a card with a mouse except emptying its
//     text, and the obvious one, right-click, opened the BLOCK's menu — whose
//     Delete removes the whole board.
//
// **Typing here goes through `testTextInput.enterText`, never
// `tester.enterText(field)`.** The second focuses the field itself, which is
// how the existing tests passed while the app did not: it does for the test
// the one thing the app was failing to do.

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/board_block_view.dart';
import 'package:openote/editor/text_block_view.dart';
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

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_boardmouse_');
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

  /// The whole shell — the focus that defeated the card editor belongs to the
  /// canvas, so a board mounted on its own has nobody to lose it to.
  Future<void> pumpShell(WidgetTester t) async {
    final nb = app.notebookId!;
    final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
    app.importPage(nb, page.id, [
      Block(
          type: BlockType.text,
          x: 60,
          y: 600,
          w: 480,
          content: {'text': 'A paragraph.'}),
      Block(type: BlockType.board, x: 60, y: 160, w: 700, h: 300, content: {
        'columns': [
          {
            'title': 'To do',
            'cards': ['Revise osmosis', 'Past paper']
          },
          {'title': 'Done', 'cards': <String>[]},
        ]
      }),
    ], PageProps());
    app.reloadNodes();
    await app.selectPage(page.id);
    app.markOnboardingSeen();
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      theme: onoteTheme(Brightness.light),
      home: AppShell(app: app),
    ));
    await t.pump(const Duration(milliseconds: 900));
    await t.pumpAndSettle();
  }

  Block board() => app.blocks.firstWhere((b) => b.type == BlockType.board);

  List<List<String>> cards() => [
        for (final c in board().content['columns'] as List)
          [for (final x in ((c as Map)['cards'] as List)) '$x']
      ];

  List<String> titles() => [
        for (final c in board().content['columns'] as List)
          '${(c as Map)['title']}'
      ];

  /// A real mouse click — the pointer kind matters to focus on desktop.
  Future<void> click(WidgetTester t, Offset at,
      {int buttons = kPrimaryButton}) async {
    final g = await t.startGesture(at,
        kind: PointerDeviceKind.mouse, buttons: buttons);
    await g.up();
    await t.pumpAndSettle();
    app.cancelPendingSave();
  }

  /// Type at whatever holds the keyboard — see the note at the top.
  Future<void> type(WidgetTester t, String text) async {
    t.testTextInput.enterText(text);
    await t.pumpAndSettle();
    app.cancelPendingSave();
  }

  bool editorHasKeyboard(WidgetTester t) {
    final f = find.descendant(
        of: find.byType(BoardBlockView), matching: find.byType(TextField));
    if (f.evaluate().isEmpty) return false;
    return t.widget<TextField>(f).focusNode?.hasPrimaryFocus ?? false;
  }

  /// Somewhere on the page that is neither the board nor the paragraph.
  Future<void> clickAway(WidgetTester t) async {
    await click(t, const Offset(1300, 850));
    app.cancelPendingSave();
  }

  group('editing', () {
    testWidgets('THE REPORTED ONE: click a card, type, and the card changes',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(t);
      await click(t, t.getCenter(find.text('Revise osmosis')));
      expect(editorHasKeyboard(t), isTrue,
          reason: 'the editor that opened is the one the keys go to');

      await type(t, 'Revise osmosis and diffusion');
      await clickAway(t);
      expect(cards()[0], ['Revise osmosis and diffusion', 'Past paper']);
    });

    testWidgets('and it still works coming from an open paragraph', (t) async {
      // The route that always worked, kept working.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(t);
      await click(t,
          t.getTopLeft(find.byType(TextBlockView).first) + const Offset(24, 12));
      expect(app.editingBlockId, isNotNull, reason: 'precondition');

      await click(t, t.getCenter(find.text('Past paper')));
      expect(editorHasKeyboard(t), isTrue);
      await type(t, 'Past paper, 2023');
      await clickAway(t);
      expect(cards()[0], ['Revise osmosis', 'Past paper, 2023']);
    });

    testWidgets('a column title takes the keyboard the same way', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(t);
      await click(t, t.getCenter(find.textContaining('Done')));
      expect(editorHasKeyboard(t), isTrue);
      await type(t, 'Finished');
      await clickAway(t);
      expect(titles(), ['To do', 'Finished']);
    });

    testWidgets('and so does "Add a card"', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(t);
      await click(t, t.getCenter(find.text('Add a card').first));
      expect(editorHasKeyboard(t), isTrue);
      await type(t, 'Flashcards for chapter 2');
      await clickAway(t);
      expect(cards()[0],
          ['Revise osmosis', 'Past paper', 'Flashcards for chapter 2']);
    });

    testWidgets('Enter from the keyboard gives the editor the keyboard too',
        (t) async {
      // The keyboard route opened its editor through the same `autofocus`,
      // while the board's own key node held focus — so it was the same bug.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(t);
      app.select(board().id, edit: true);
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(editorHasKeyboard(t), isTrue);
      await type(t, 'Revise osmosis properly');
      await clickAway(t);
      expect(cards()[0].first, 'Revise osmosis properly');
    });
  });

  group('deleting', () {
    testWidgets('right-click on a card is the CARD\'s menu, not the board\'s',
        (t) async {
      // The board's menu offers a Delete that removes the whole board — one
      // slip from losing every card on it.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(t);
      await click(t, t.getCenter(find.text('Past paper')),
          buttons: kSecondaryButton);
      expect(find.text('Edit card'), findsOneWidget);
      expect(find.text('Delete card'), findsOneWidget);
      expect(find.text('Delete'), findsNothing,
          reason: "the block's Delete, which takes the whole board");

      await t.tap(find.text('Delete card'));
      await t.pumpAndSettle();
      app.cancelPendingSave();
      expect(cards()[0], ['Revise osmosis'], reason: 'that card, only');
      expect(app.blocks.where((b) => b.type == BlockType.board), hasLength(1),
          reason: 'and the board is still there');
    });

    testWidgets('"Edit card" from the menu opens it with the keyboard',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(t);
      await click(t, t.getCenter(find.text('Past paper')),
          buttons: kSecondaryButton);
      await t.tap(find.text('Edit card'));
      await t.pumpAndSettle();
      expect(editorHasKeyboard(t), isTrue);
      await type(t, 'Past paper (timed)');
      await clickAway(t);
      expect(cards()[0], ['Revise osmosis', 'Past paper (timed)']);
    });

    testWidgets('hovering a card shows a delete button, and undo brings it '
        'back', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(t);
      expect(find.byTooltip('Delete card'), findsNothing,
          reason: 'a board at rest is a list of cards, not of buttons');

      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(t.getCenter(find.text('Revise osmosis')));
      await t.pumpAndSettle();
      expect(find.byTooltip('Delete card'), findsOneWidget,
          reason: 'on the card under the mouse, and only that one');

      await t.tap(find.byTooltip('Delete card'));
      await t.pumpAndSettle();
      app.cancelPendingSave();
      expect(cards()[0], ['Past paper']);

      app.undo();
      await t.pumpAndSettle();
      app.cancelPendingSave();
      expect(cards()[0], ['Revise osmosis', 'Past paper'],
          reason: 'one click is safe because Ctrl+Z takes it back');
    });
  });
}
