// Making a row must not hand the keyboard back to the paragraph.
//
// Reported, after the first fix for this: *"i create the table, write some
// text in the second column …, press enter or tab … and it will create the new
// row, move my cursor into the box very briefly, then move it out of the box
// so if i tried to type it would be next to the table."*
//
// `inline_table_in_block_test.dart` already asserts that Enter lands in the
// row it just made, and it passes — so whatever is wrong is in the gap between
// that test and the running app. The gap is this: those tests mount
// `TextBlockView` on its own, so nothing rebuilds it. In the app the block
// lives under a listener on `AppState`, and a structural table write calls
// `markDirty()`, which notifies, which rebuilds the whole block — every time a
// row is added and never when a cell is merely typed into.
//
// So these mount it the way the shell does.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/text_block_view.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/inline_atom.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';

class _NoopRepo implements Repository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late AppState app;
  late Block block;

  setUp(() {
    app = AppState(_NoopRepo())
      ..notebookId = 'nb'
      ..pageId = 'pg'
      ..spellCheckEnabled = false;
    const atom = InlineAtom(id: 't1', type: 'table', content: {
      'cells': [
        ['Element', 'Symbol'],
        ['Sodium', 'Na'],
      ]
    });
    final content = <String, dynamic>{
      'text': 'Results: ${atom.reference(TableData.referenceAlt)}',
    };
    InlineAtom.putIn(content, atom);
    block = Block(type: BlockType.text, x: 0, y: 0, w: 520, content: content);
    app.blocks = [block];
    app.editingBlockId = block.id;
  });

  tearDown(() => app.cancelPendingSave());

  /// The block as the SHELL mounts it: under a listener, so every
  /// `notifyListeners` rebuilds it — which is what a structural table write
  /// causes and what the other table tests never see.
  Future<void> pump(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      theme: onoteTheme(Brightness.light),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 520,
            child: ListenableBuilder(
              listenable: app,
              builder: (_, __) => TextBlockView(block: block, app: app),
            ),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
  }

  /// Is the caret in a table cell, or has it been handed to the paragraph?
  bool caretInACell() =>
      FocusManager.instance.primaryFocus?.debugLabel == 'tableCell';

  int rowsNow() => tablesIn(block.content).single.rows;

  /// Click into the cell at [r],[c] of the only table on screen.
  Future<void> clickCell(WidgetTester t, int r, int c) async {
    final cells = find.byType(TextField);
    // The host paragraph is one of them; the cells follow it in the tree.
    await t.tap(cells.at(1 + r * 2 + c));
    await t.pumpAndSettle();
    app.cancelPendingSave();
  }

  /// A key, then the debounced save cancelled: the binding checks for pending
  /// timers BEFORE tear-downs run, so cleaning up afterwards is too late.
  Future<void> key(WidgetTester t, LogicalKeyboardKey k) async {
    await t.sendKeyEvent(k);
    await t.pumpAndSettle();
    app.cancelPendingSave();
  }

  testWidgets('Enter in the last row leaves the caret IN the new row',
      (t) async {
    await pump(t);
    await clickCell(t, 1, 1);
    expect(caretInACell(), isTrue, reason: 'precondition: clicking in works');

    await key(t, LogicalKeyboardKey.enter);

    expect(rowsNow(), 3, reason: 'the row was made');
    expect(caretInACell(), isTrue,
        reason: 'the caret must still be in the table, not beside it');
  });

  testWidgets('Tab out of the last cell leaves the caret IN the new row',
      (t) async {
    await pump(t);
    await clickCell(t, 1, 1);
    await key(t, LogicalKeyboardKey.tab);

    expect(rowsNow(), 3);
    expect(caretInACell(), isTrue);
  });

  testWidgets('and it survives the frames after, not just the first',
      (t) async {
    // "move my cursor into the box very briefly, then move it out" — the
    // caret arriving is not the property; the caret STAYING is.
    await pump(t);
    await clickCell(t, 1, 1);
    await key(t, LogicalKeyboardKey.enter);
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 40));
    }
    expect(caretInACell(), isTrue,
        reason: 'something took it back a few frames later');
  });

  testWidgets('typing into the new row reaches the TABLE, not the paragraph',
      (t) async {
    // The symptom as the owner meets it: they type, and the letters land in
    // the sentence beside the table.
    await pump(t);
    await clickCell(t, 1, 1);
    await key(t, LogicalKeyboardKey.enter);
    // Typed at whatever holds the keyboard, which is the whole question —
    // naming a field would assume the answer.
    t.testTextInput.enterText('Potassium');
    await t.pumpAndSettle();
    app.cancelPendingSave();

    expect(tablesIn(block.content).single.cells.last, contains('Potassium'));
    expect(block.content['text'], isNot(contains('Potassium')),
        reason: 'not one character of it belongs in the sentence');
  });

  testWidgets('THE REPORTED JOURNEY: type, Tab to make the table, type, Tab',
      (t) async {
    // Exactly as described: a line of text becomes a table, the caret lands in
    // the second cell, you type, and you press Tab again. The table is ONE row
    // old at that point — freshly made by the keystroke before — which is the
    // state none of the passing tests put it in under a listener.
    final b = Block(
        type: BlockType.text, x: 0, y: 0, w: 520, content: {'text': 'Element'});
    app.blocks = [b];
    block = b;
    app.editingBlockId = b.id;
    await pump(t);
    await t.tap(find.byType(TextField).first);
    await t.pumpAndSettle();
    final host = t.widget<TextField>(find.byType(TextField).first);
    host.controller!.selection = const TextSelection.collapsed(offset: 7);
    await t.pumpAndSettle();

    await key(t, LogicalKeyboardKey.tab); // the line becomes a table
    expect(tablesIn(b.content).single.cells, [
      ['Element', '']
    ]);
    expect(caretInACell(), isTrue, reason: 'the caret goes into cell 2');

    t.testTextInput.enterText('Symbol');
    await t.pumpAndSettle();
    app.cancelPendingSave();

    // …and this extends the heading row sideways: the first row adds a
    // COLUMN, which is the rule the owner asked for. What this test is about
    // is the caret, either way.
    await key(t, LogicalKeyboardKey.tab);
    expect(tablesIn(b.content).single.cols, 3, reason: 'the table grew');
    expect(caretInACell(), isTrue,
        reason: 'THE BUG: the caret is put beside the table instead');
  });
}
