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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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

  testWidgets('A LINK IN A CELL: the caret stays put while typing beside it',
      (t) async {
    // Reported after v1.0.1: *"the caret now jumps around like crazy in and
    // out of the table, making it unuseable."* The owner's tables have links
    // in them — which no test had — so that is the shape this reproduces.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    const atom = InlineAtom(id: 'tl', type: 'table', content: {
      'cells': [
        ['See', '[[Kinematics|pg-2]]'],
        ['Also', 'plain'],
      ]
    });
    final content = <String, dynamic>{
      'text': 'Before ${atom.reference('2x2 table')} after.',
    };
    InlineAtom.putIn(content, atom);
    await pumpShell(t, content);

    await openBlock(t);
    expect(app.editingBlockId, block.id, reason: 'the block is open');

    // Into the cell that holds the link.
    final cells = find.descendant(
        of: find.byType(TextBlockView), matching: find.byType(TextField));
    await t.tap(cells.at(2));
    await t.pumpAndSettle();
    app.cancelPendingSave();
    expect(caretInACell(), isTrue, reason: 'the click landed in a cell');

    // Type a few characters, checking after each that the caret has not been
    // thrown out of the table.
    for (final ch in ['a', 'b', 'c']) {
      t.testTextInput.enterText('[[Kinematics|pg-2]]$ch');
      await t.pumpAndSettle();
      app.cancelPendingSave();
      expect(caretInACell(), isTrue, reason: 'still in the cell after "$ch"');
    }
  });

  testWidgets('THE VIEW DOES NOT CHASE ANYTHING while a cell is typed into',
      (t) async {
    // Reported after v1.0.1: *"the caret now jumps around like crazy in and
    // out of the table, making it unuseable."*
    //
    // `ensureCaretVisible` asks the SESSION where the caret is, and the
    // session answers from the paragraph's own `renderEditable` and the
    // paragraph's own selection. While a cell holds the keyboard the
    // paragraph is read-only and its selection is wherever it was last left —
    // so every keystroke in a cell scrolled the page to a point that has
    // nothing to do with where anybody is typing.
    //
    // Both halves of this shipped in the same release: tables moved into the
    // paragraph, and the view learned to follow the caret. Neither test knew
    // about the other.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    const atom = InlineAtom(id: 'tv', type: 'table', content: {
      'cells': [
        ['Element', 'Symbol'],
        ['Sodium', 'Na'],
      ]
    });
    final content = <String, dynamic>{
      'text': 'A sentence long enough to have a caret of its own '
          '${atom.reference('2x2 table')}',
    };
    InlineAtom.putIn(content, atom);
    await pumpShell(t, content);
    await openBlock(t);

    // Put the paragraph's own caret at the very start, then go into the LAST
    // cell — as far from that as the block gets.
    final fields = find.descendant(
        of: find.byType(TextBlockView), matching: find.byType(TextField));
    t.widget<TextField>(fields.first).controller!.selection =
        const TextSelection.collapsed(offset: 0);
    await t.pumpAndSettle();
    await t.tap(fields.last);
    await t.pumpAndSettle();
    app.cancelPendingSave();
    expect(caretInACell(), isTrue, reason: 'the caret is in a cell');

    // **Nothing to reveal while a cell has the keyboard.**
    //
    // It used to answer with the PARAGRAPH's caret, which is stale while a
    // cell is being typed into — so the page chased a point nobody was
    // writing at. Answering with the cell's own caret aimed it correctly and
    // made things worse: a canvas that really does scroll under a table takes
    // the caret out of it. So the follower stands down here instead, and this
    // is the assertion that keeps it standing down.
    expect(app.activeSession!.caretRectGlobal(), isNull,
        reason: 'a cell holds the keyboard, so there is nothing for the view '
            "to chase — least of all the paragraph's own caret, which is "
            'where this started');
  });

  testWidgets('GETTING BACK INTO A ROW YOU JUST MADE, low on a tall page',
      (t) async {
    // Reported after the caret-follow fix: *"when i added a new row it did it
    // and kicked the carret out, however then if i tried to navigate back into
    // that bottom row either by arrows or clicking into it, it would just kick
    // me out again… it seemed to happen in all the new cells."*
    //
    // The missing ingredient in every earlier test is a page tall enough for
    // revealing the caret to actually SCROLL. A table near the top is already
    // comfortable, `revealGlobalRect` returns without doing anything, and the
    // interaction cannot happen.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    const atom = InlineAtom(id: 'tb', type: 'table', content: {
      'cells': [
        ['Element', 'Symbol'],
        ['Sodium', 'Na'],
      ]
    });
    final content = <String, dynamic>{
      'text': 'Low down ${atom.reference('2x2 table')}',
    };
    InlineAtom.putIn(content, atom);

    // Low enough that a new row lands past the bottom of the comfortable
    // band, so the reveal really does scroll.
    final nb = app.notebookId!;
    final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
    block = Block(type: BlockType.text, x: 60, y: 620, w: 480, content: content);
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
    block = app.blocks.single;

    await t.tapAt(
        t.getTopLeft(find.byType(TextBlockView)) + const Offset(24, 14));
    await t.pumpAndSettle();
    app.cancelPendingSave();
    expect(app.editingBlockId, block.id, reason: 'the block is open');

    final fields = () => find.descendant(
        of: find.byType(TextBlockView), matching: find.byType(TextField));

    // Into the last cell, then make a row.
    await t.tap(fields().last);
    await t.pumpAndSettle();
    app.cancelPendingSave();
    expect(caretInACell(), isTrue, reason: 'in the last cell');

    await key(t, LogicalKeyboardKey.enter);
    expect(tablesIn(app.blocks.single.content).single.rows, 3,
        reason: 'the row was made');
    expect(caretInACell(), isTrue,
        reason: 'THE FIRST HALF: making the row kicked the caret out');

    // And now the half that made it unusable: go back into the new row.
    await t.tap(fields().last);
    await t.pumpAndSettle();
    app.cancelPendingSave();
    expect(caretInACell(), isTrue,
        reason: 'THE SECOND HALF: clicking into the row you just made kicked '
            'you out again, every time');
  });

  testWidgets('THE OWNERS PATH: a narrow box the app made, word, Tab',
      (t) async {
    // The owner's trace, from exactly this: *"I typed a word and pressed tab,
    // i did not attempt to navigate or do anything other after presseing
    // tab."* The pursuit SUCCEEDED — the caret reached the cell — and then
    // the focus fell all the way out to the route's own scope, past the
    // table's scope, which is what detaching a focused node looks like.
    //
    // The difference from the journey test above is the BOX: 320 wide and
    // auto-sizing, which is what clicking the page makes. A table needs more
    // width than that, so the box must grow on the very frame the caret is
    // landing.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pumpShell(t, {'text': ''});
    // The width `PageCanvas._createTextAt` gives a box, and auto-width on,
    // which is the default for one nobody has resized.
    app.blocks.single.w = 320;
    await t.pumpAndSettle();

    await openBlock(t);
    final host = t.widget<TextField>(find
        .descendant(
            of: find.byType(TextBlockView), matching: find.byType(TextField))
        .first);
    t.testTextInput.enterText('Element');
    await t.pumpAndSettle();
    app.cancelPendingSave();
    host.controller!.selection = const TextSelection.collapsed(offset: 7);
    await t.pumpAndSettle();

    await key(t, LogicalKeyboardKey.tab);
    expect(tablesIn(app.blocks.single.content), hasLength(1),
        reason: 'the table was made');
    // Several frames, because the loss happened AFTER the caret had landed.
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    expect(caretInACell(), isTrue,
        reason: 'the caret reached the cell and then fell out to the route '
            "scope — the node under it was detached");
  });

  /// **THE ACTUAL CAUSE, reproduced.**
  ///
  /// The stack trace from the running app, caught by overriding `unfocus` on
  /// the paragraph's node:
  ///
  /// ```text
  /// #0  _ParagraphFocusNode.unfocus         (live_markdown_engine.dart)
  /// #1  _TextFieldState.build.<anonymous>   (material/text_field.dart:1680)
  /// #2  SemanticsAnnotationsMixin._performDidLoseAccessibilityFocus
  /// #4  SemanticsOwner.performAction
  /// #8  PlatformDispatcher._dispatchSemanticsAction
  /// #13 RenderView.updateSemantics
  /// #16 PipelineOwner.flushSemantics
  /// #18 RendererBinding.drawFrame
  /// ```
  ///
  /// The platform's accessibility bridge sends `didLoseAccessibilityFocus`
  /// for the paragraph, and `TextField` answers it on every desktop platform
  /// with exactly one line:
  ///
  /// ```dart
  /// handleDidLoseAccessibilityFocus = () { _effectiveFocusNode.unfocus(); };
  /// ```
  ///
  /// That line is written for a LEAF field. A paragraph here contains fields,
  /// so accessibility focus moving from the paragraph INTO its own table cell
  /// is an ordinary, correct thing for the bridge to report — and answering
  /// it by unfocusing the paragraph throws the cell's caret out of the
  /// document. The action is not the bug; the assumption underneath it is.
  ///
  /// So this test does not simulate the symptom. It dispatches the real
  /// semantics action through the real `SemanticsOwner`, which is the same
  /// entry point frame #4 of that stack went through.
  testWidgets('losing ACCESSIBILITY focus leaves the cell caret alone',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // **Windows, explicitly.** `TextField.build` wires
    // `handleDidLoseAccessibilityFocus` only under the macOS/linux/windows
    // arm of its platform switch, and a widget test is Android unless told
    // otherwise — so without this the action is not wired at all, and the
    // test passes whether the fix is present or not. It did, until this line.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final semantics = t.ensureSemantics();
    await pumpShell(t, {'text': 'Element'});

    await openBlock(t);
    final host = t.widget<TextField>(find
        .descendant(
            of: find.byType(TextBlockView), matching: find.byType(TextField))
        .first);
    host.controller!.selection = const TextSelection.collapsed(offset: 7);
    await t.pumpAndSettle();

    await key(t, LogicalKeyboardKey.tab);
    expect(caretInACell(), isTrue, reason: 'the caret is in a cell to begin');

    // The paragraph's own field is the OUTERMOST EditableText in the block;
    // the cell's is nested inside its spans.
    final paragraph = t.getSemantics(find
        .descendant(
            of: find.byType(TextBlockView), matching: find.byType(EditableText))
        .first);
    t.binding.pipelineOwner.semanticsOwner!
        .performAction(paragraph.id, SemanticsAction.didLoseAccessibilityFocus);
    await t.pumpAndSettle();

    expect(caretInACell(), isTrue,
        reason: 'THE BUG: a screen reader moving off the paragraph — or a '
            'bridge that merely thinks it did — empties the table cell');
    // Not `addTearDown`: the handle is checked before tear-downs run.
    semantics.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  /// **The event `debugFocusChanges` actually recorded.**
  ///
  /// Six reproductions in this file guessed at a CAUSE and all six missed,
  /// because the cause is in the framework and does not fire under
  /// `TestTextInput`. Flutter's own focus log named the event instead:
  ///
  /// ```text
  /// FOCUS: Unfocused node:
  ///     primary focus was FocusNode#5b072([IN FOCUS PATH])
  ///     next focus will be FocusScopeNode#723b0(_ModalScopeState Focus Scope)
  /// ```
  ///
  /// `#5b072` is the paragraph's node — the tree dump put it directly above
  /// `FocusScopeNode(inlineTable)` — and it is IN the focus path rather than
  /// holding the focus, so a cell had the caret at the time. Several
  /// framework paths spell "done editing this field" as
  /// `widget.focusNode.unfocus()`, and each of them lands here.
  ///
  /// So this test does not reproduce a cause. It performs the event, on the
  /// real tree, and asserts the caret survives it. That is the whole of what
  /// the fix claims, and it fails without it.
  testWidgets('unfocusing the paragraph does not take the cell caret',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pumpShell(t, {'text': 'Element'});

    await openBlock(t);
    final host = t.widget<TextField>(find
        .descendant(
            of: find.byType(TextBlockView), matching: find.byType(TextField))
        .first);
    host.controller!.selection = const TextSelection.collapsed(offset: 7);
    await t.pumpAndSettle();

    await key(t, LogicalKeyboardKey.tab);
    expect(caretInACell(), isTrue, reason: 'the caret is in a cell to begin');

    // The paragraph is an ANCESTOR of the cell, so walk the focus path up to
    // it rather than trusting a Finder — the trace identified it by position
    // in exactly this way.
    FocusNode? node = FocusManager.instance.primaryFocus;
    while (node != null && node.debugLabel != 'paragraph') {
      node = node.parent;
    }
    expect(node, isNotNull,
        reason: 'the cell sits inside the paragraph that owns the table');

    node!.unfocus();
    await t.pumpAndSettle();

    expect(caretInACell(), isTrue,
        reason: 'THE BUG: unfocusing the paragraph drags its own cell out to '
            'the route scope, and typing lands beside the table');
  });
}
