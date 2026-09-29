// Making a row, inside the real shell.
//
// Reported: *"press enter or tab … and it will create the new row, move my
// cursor into the box very briefly, then move it out of the box so if i tried
// to type it would be next to the table."*
//
// Every table test that could have caught this passes, which is the whole
// reason this file exists. They mount `TextBlockView` — bare, or under a
// listener — and at that level the caret stays in the cell. The running app
// puts a great deal more around the block: a canvas that keys every block
// widget on `docRevision`, a global keyboard handler that sees every keystroke
// before focus dispatch, and a focus scope with somewhere else for the
// keyboard to go. One of those is doing it, and only a test that mounts
// `AppShell` can see which.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/inline_atom.dart';
import 'package:openote/model/models.dart';
import 'package:openote/editor/text_block_view.dart';
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
  late Block block;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_tablefocus_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('T');
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

  Future<void> pumpShell(WidgetTester t, Map<String, dynamic> content) async {
    final nb = app.notebookId!;
    final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
    block = Block(type: BlockType.text, x: 60, y: 140, w: 480, content: content);
    app.importPage(nb, page.id, [block], PageProps());
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
    // `selectPage` reloads the page, so work with the block the app holds.
    block = app.blocks.single;
  }

  bool caretInACell() =>
      FocusManager.instance.primaryFocus?.debugLabel == 'tableCell';

  /// Open the block for editing. A paragraph being READ has no `TextField` at
  /// all — it draws as markdown — so there is nothing to tap by type; the tap
  /// has to land on the view itself.
  Future<void> openBlock(WidgetTester t) async {
    await t.tapAt(t.getTopLeft(find.byType(TextBlockView)) + const Offset(24, 14));
    await t.pumpAndSettle();
    app.cancelPendingSave();
  }

  Future<void> key(WidgetTester t, LogicalKeyboardKey k) async {
    await t.sendKeyEvent(k);
    await t.pumpAndSettle();
    app.cancelPendingSave();
  }

  testWidgets('THE REPORTED JOURNEY: type, Tab, type, Tab — in the shell',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pumpShell(t, {'text': 'Element'});

    await openBlock(t);
    expect(app.editingBlockId, block.id, reason: 'the block is open');
    final host = t.widget<TextField>(find.descendant(
        of: find.byType(TextBlockView), matching: find.byType(TextField)).first);
    host.controller!.selection = const TextSelection.collapsed(offset: 7);
    await t.pumpAndSettle();

    await key(t, LogicalKeyboardKey.tab); // the line becomes a table
    expect(tablesIn(app.blocks.single.content).single.cells, [
      ['Element', '']
    ]);
    expect(caretInACell(), isTrue, reason: 'the caret goes into cell 2');

    t.testTextInput.enterText('Symbol');
    await t.pumpAndSettle();
    app.cancelPendingSave();

    // …and this extends the heading row sideways (see the first-row rule
    // below). What this test is about is the CARET, either way.
    await key(t, LogicalKeyboardKey.tab);
    final table = tablesIn(app.blocks.single.content).single;
    expect(table.cols, 3, reason: 'the table grew');
    expect(caretInACell(), isTrue,
        reason: 'THE BUG: the caret is handed to the paragraph instead');
  });

  testWidgets('Enter making a row keeps the keyboard, in the shell', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    const atom = InlineAtom(id: 't1', type: 'table', content: {
      'cells': [
        ['Element', 'Symbol'],
        ['Sodium', 'Na'],
      ]
    });
    final content = <String, dynamic>{
      'text': atom.reference(TableData.referenceAlt)
    };
    InlineAtom.putIn(content, atom);
    await pumpShell(t, content);

    // Open the block first: a paragraph being READ draws its cells as text,
    // and they only become fields once there is an editing session.
    await openBlock(t);
    expect(app.editingBlockId, block.id, reason: 'the block is open');

    // Into the last cell.
    final cells = find.byWidgetPredicate(
        (w) => w is TextField && w.focusNode?.debugLabel == 'tableCell');
    expect(cells, findsNWidgets(4), reason: 'a 2x2 table is four cells');
    await t.tap(cells.at(3));
    await t.pumpAndSettle();
    app.cancelPendingSave();
    expect(caretInACell(), isTrue, reason: 'precondition');

    await key(t, LogicalKeyboardKey.enter);
    expect(tablesIn(app.blocks.single.content).single.rows, 3);
    expect(caretInACell(), isTrue);
  });

  testWidgets('Tab off the end of the FIRST row adds a column', (t) async {
    // The owner: *"on the first row pressing tab should add a new column
    // rather than return me"*. The top row is where the shape is decided.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pumpShell(t, {'text': 'Element'});
    await openBlock(t);
    final host = t.widget<TextField>(find.descendant(
        of: find.byType(TextBlockView), matching: find.byType(TextField)).first);
    host.controller!.selection = const TextSelection.collapsed(offset: 7);
    await t.pumpAndSettle();

    await key(t, LogicalKeyboardKey.tab); // 'Element' becomes a 1x2 table
    t.testTextInput.enterText('Symbol');
    await t.pumpAndSettle();
    app.cancelPendingSave();

    await key(t, LogicalKeyboardKey.tab);
    final table = tablesIn(app.blocks.single.content).single;
    expect(table.rows, 1, reason: 'still one row — it grew sideways');
    expect(table.cols, 3, reason: 'a third heading to type into');
    expect(caretInACell(), isTrue, reason: 'and the caret is in it');

    t.testTextInput.enterText('Mass');
    await t.pumpAndSettle();
    app.cancelPendingSave();
    expect(tablesIn(app.blocks.single.content).single.cells.first,
        ['Element', 'Symbol', 'Mass']);
  });

  testWidgets('but Enter on the first row still starts the body', (t) async {
    // The way OUT of the heading row, now that Tab no longer leaves it.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pumpShell(t, {'text': 'Element'});
    await openBlock(t);
    final host = t.widget<TextField>(find.descendant(
        of: find.byType(TextBlockView), matching: find.byType(TextField)).first);
    host.controller!.selection = const TextSelection.collapsed(offset: 7);
    await t.pumpAndSettle();
    await key(t, LogicalKeyboardKey.tab);

    await key(t, LogicalKeyboardKey.enter);
    final table = tablesIn(app.blocks.single.content).single;
    expect(table.rows, 2, reason: 'Enter is how the body begins');
    expect(table.cols, 2);
    expect(caretInACell(), isTrue);
  });

  testWidgets('and Tab on a LATER row still makes a row', (t) async {
    // Unchanged from Word and every spreadsheet; only the top row is special.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    const atom = InlineAtom(id: 't1', type: 'table', content: {
      'cells': [
        ['Element', 'Symbol'],
        ['Sodium', 'Na'],
      ]
    });
    final content = <String, dynamic>{
      'text': atom.reference(TableData.referenceAlt)
    };
    InlineAtom.putIn(content, atom);
    await pumpShell(t, content);
    await openBlock(t);

    final cells = find.byWidgetPredicate(
        (w) => w is TextField && w.focusNode?.debugLabel == 'tableCell');
    await t.tap(cells.at(3)); // last cell of row 2
    await t.pumpAndSettle();
    app.cancelPendingSave();

    await key(t, LogicalKeyboardKey.tab);
    final table = tablesIn(app.blocks.single.content).single;
    expect(table.rows, 3, reason: 'a row, as it always has');
    expect(table.cols, 2, reason: 'and NOT a column');
    expect(caretInACell(), isTrue);
  });

  testWidgets('the caret survives the debounced save firing under it',
      (t) async {
    // Every other test in this file cancels the debounced save after each
    // keystroke, because the binding fails a test that leaves a timer armed.
    // That silently suppressed a suspect: `markDirty` arms a 700 ms timer,
    // and "into the box very briefly, then out of the box" is about that
    // long. This one lets it fire. It is not the culprit — but the next
    // person to read this file should not have to re-derive that.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    const atom = InlineAtom(id: 't1', type: 'table', content: {
      'cells': [
        ['Element', 'Symbol'],
        ['Sodium', 'Na'],
      ]
    });
    final content = <String, dynamic>{
      'text': atom.reference(TableData.referenceAlt)
    };
    InlineAtom.putIn(content, atom);
    await pumpShell(t, content);
    await openBlock(t);

    final cells = find.byWidgetPredicate(
        (w) => w is TextField && w.focusNode?.debugLabel == 'tableCell');
    await t.tap(cells.at(3));
    await t.pumpAndSettle();
    app.cancelPendingSave();

    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(caretInACell(), isTrue, reason: 'the caret ARRIVES — never in doubt');

    // NOT cancelled: let the 700 ms debounce run all the way through a save.
    await t.pump(const Duration(milliseconds: 900));
    await t.pumpAndSettle();
    app.cancelPendingSave();

    expect(caretInACell(), isTrue, reason: 'and the save must not take it back');
  });

  testWidgets('the caret survives a table that outgrows its box', (t) async {
    // A table wider than its box takes a branch no small table reaches
    // (`inline_table.dart`, `total > room`): it scales the columns down AND
    // asks the block for more room in a post-frame callback, which latches
    // `autoWidth = false`, rewrites `b.w` and calls `updateBlock` +
    // `markDirty`. Three block mutations a frame after Enter, none of which
    // any other table test provokes.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    const atom = InlineAtom(id: 't1', type: 'table', content: {
      'cells': [
        ['Element name in full', 'Chemical symbol', 'Relative atomic mass'],
        ['Sodium', 'Na', '22.99'],
      ],
      'colWidths': [320.0, 320.0, 320.0], // 960 against a 480 box
    });
    final content = <String, dynamic>{
      'text': atom.reference(TableData.referenceAlt)
    };
    InlineAtom.putIn(content, atom);
    await pumpShell(t, content);
    await openBlock(t);

    final cells = find.byWidgetPredicate(
        (w) => w is TextField && w.focusNode?.debugLabel == 'tableCell');
    await t.tap(cells.at(5));
    await t.pumpAndSettle();
    app.cancelPendingSave();
    expect(caretInACell(), isTrue, reason: 'precondition');

    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    app.cancelPendingSave();
    expect(tablesIn(app.blocks.single.content).single.rows, 3);
    expect(caretInACell(), isTrue,
        reason: 'the width request must not take the caret with it');
  });
}
