// An inline editor in a board keeps the keys it is given.
//
// Reported: renaming the second column from "Doing" to "In progress"
// deleted a card out of the FIRST column: *"by default the first column,
// first item was already selected ... and while pressing backspace, it is
// deleting that particular first item. I don't know why it was by default
// selected."*
//
// It was not selected. `_cursor` starts at (0, 0), nothing had moved it,
// and `_onKey` ran anyway: a key event is offered to the focused node and
// then to each ancestor in turn, and the board's `Focus` wraps the inline
// `TextField`, so every keystroke meant for the field was offered to the
// board's card-walking handler first. The ring on card (0, 0) came from
// the same root: `FocusNode.hasFocus` is true for anything in the
// subtree, including that field.
//
// Measured on the shipped build before the fix, cards
// ['Revise osmosis', 'Past paper'] in column one:
//
//   * Backspace while renaming a title       → 'Revise osmosis' deleted
//   * Backspace while editing a CARD         → the same card deleted, and
//                                              not the one being edited
//   * Ctrl+Right while renaming a title      → 'Revise osmosis' carried
//                                              into the next column
//
// The last two tests are the other half: the board's own keyboard, and the
// rename itself, still have to work.

import 'dart:io';

import 'package:flutter/gestures.dart';
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

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_boardkeys_');
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

  /// The whole shell: the focus chain is the thing under test, and a board
  /// mounted on its own does not have one.
  Future<void> pumpShell(WidgetTester t) async {
    final nb = app.notebookId!;
    final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
    app.importPage(
        nb,
        page.id,
        [
          Block(type: BlockType.board, x: 60, y: 160, w: 700, h: 300, content: {
            'columns': [
              {
                'title': 'To do',
                'cards': ['Revise osmosis', 'Past paper']
              },
              {
                'title': 'Doing',
                'cards': ['Essay plan']
              },
            ]
          }),
        ],
        PageProps());
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

  Future<void> click(WidgetTester t, Finder what) async {
    final g = await t.startGesture(t.getCenter(what),
        kind: PointerDeviceKind.mouse, buttons: kPrimaryButton);
    await g.up();
    await t.pumpAndSettle();
    app.cancelPendingSave();
  }

  bool editorOpen(WidgetTester t) => find
      .descendant(
          of: find.byType(BoardBlockView), matching: find.byType(TextField))
      .evaluate()
      .isNotEmpty;

  /// Whether the keyboard ring is drawn on the card showing [text]. It is a
  /// `BorderSide` on the card's `Material.shape`, so that the ring and the
  /// rounded corner can share one outline.
  bool ringOn(WidgetTester t, String text) {
    final m = t.widget<Material>(find
        .ancestor(of: find.text(text), matching: find.byType(Material))
        .first);
    final shape = m.shape;
    return shape is RoundedRectangleBorder &&
        shape.side.style != BorderStyle.none;
  }

  group('renaming a column title', () {
    testWidgets('backspace edits the title and leaves the cards alone',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(t);
      final before = cards();
      await click(t, find.textContaining('Doing'));
      expect(editorOpen(t), isTrue, reason: 'the title editor opened');

      t.testTextInput.enterText('In progres');
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.backspace);
      await t.pumpAndSettle();

      expect(cards(), before,
          reason: "backspace belongs to the title being typed, not to "
              "a card nobody chose");
      app.cancelPendingSave();
    });

    testWidgets('no card wears the keyboard ring while it is open', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(t);
      await click(t, find.textContaining('Doing'));
      expect(ringOn(t, 'Revise osmosis'), isFalse,
          reason: 'hasFocus counts the subtree; hasPrimaryFocus does not');
      app.cancelPendingSave();
    });

    testWidgets('ctrl+arrow does not carry a card off', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(t);
      final before = cards();
      await click(t, find.textContaining('Doing'));
      t.testTextInput.enterText('In progress');
      await t.pumpAndSettle();

      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pumpAndSettle();

      expect(cards(), before);
      app.cancelPendingSave();
    });

    testWidgets('and Enter still commits it', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(t);
      await click(t, find.textContaining('Doing'));
      t.testTextInput.enterText('In progress');
      await t.pumpAndSettle();
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();

      expect(titles(), ['To do', 'In progress']);
      expect(cards(), [
        ['Revise osmosis', 'Past paper'],
        ['Essay plan']
      ]);
      app.cancelPendingSave();
    });
  });

  testWidgets('backspace while editing a card leaves every card alone',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pumpShell(t);
    final before = cards();
    await click(t, find.text('Essay plan'));
    expect(editorOpen(t), isTrue);

    t.testTextInput.enterText('Essay pla');
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.backspace);
    await t.pumpAndSettle();

    expect(cards(), before,
        reason: 'it used to delete a card in the other column entirely');
    app.cancelPendingSave();
  });

  testWidgets('the board keyboard still deletes the card at the cursor',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pumpShell(t);
    // Enter on the selected block is how the board takes the keyboard.
    app.selectMany([board().id]);
    app.editingBlockId = board().id;
    await t.pumpAndSettle();
    expect(ringOn(t, 'Revise osmosis'), isTrue,
        reason: 'the board itself holds the keyboard now');

    await t.sendKeyEvent(LogicalKeyboardKey.backspace);
    await t.pumpAndSettle();

    expect(cards(), [
      ['Past paper'],
      ['Essay plan']
    ]);
    app.cancelPendingSave();
  });
}
