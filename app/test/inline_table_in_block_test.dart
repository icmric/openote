// The wiring, end to end through a real text block.
//
// `inline_table_test.dart` mounts the controller and the table directly, which
// is where the behaviour is. This file asserts the thing that file cannot: that
// the EDITOR actually hands an atom a host — in both of its halves. The read
// view and the editing session build that host in two different places
// (`buildReadOnly` and `openSession`), and a table that draws in one and not
// the other is the shape-change this whole piece of work exists to remove.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/block_atom_host.dart';
import 'package:openote/editor/inline_table.dart';
import 'package:openote/editor/text_block_view.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/inline_atom.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';

/// Rendering a block never reaches storage, and a real repository would drag
/// SQLite into a pure widget test.
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
      // The editing session debounces a spell check on a Timer, and a pending
      // timer fails the test after the tree is torn down. Nothing here is
      // about spelling.
      ..spellCheckEnabled = false;
    const atom = InlineAtom(id: 't1', type: 'table', content: {
      'cells': [
        ['Element', 'Symbol'],
        ['Sodium', 'Na'],
      ]
    });
    final content = <String, dynamic>{
      'text': 'Results: ${atom.reference('2x2 table')} and it holds.',
    };
    InlineAtom.putIn(content, atom);
    block = Block(type: BlockType.text, x: 0, y: 0, w: 520, content: content);
    app.blocks = [block];
  });

  // A cell write marks the page dirty, which arms the save debounce; a pending
  // timer fails the test once the tree is torn down.
  tearDown(() => app.cancelPendingSave());

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
            child: TextBlockView(block: block, app: app),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
  }

  group('Tab makes a table, the way OneNote does', () {
    /// A paragraph with [text] in it, open for editing, focused.
    Future<Block> typing(WidgetTester t, String text) async {
      final b = Block(
          type: BlockType.text, x: 0, y: 0, w: 520, content: {'text': text});
      app.blocks = [b];
      block = b;
      app.editingBlockId = b.id;
      await pump(t);
      await t.tap(find.byType(TextField).first);
      await t.pumpAndSettle();
      // The caret at the end, which is where it is after typing the line.
      final field = t.widget<TextField>(find.byType(TextField).first);
      field.controller!.selection =
          TextSelection.collapsed(offset: text.length);
      await t.pumpAndSettle();
      return b;
    }

    testWidgets('the line you are on becomes the first cell', (t) async {
      final b = await typing(t, 'Element');
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();

      expect(tablesIn(b.content).single.cells, [
        ['Element', '']
      ], reason: 'what you had typed is the first cell, not lost and not '
          'left sitting above the table');
      expect(b.content['text'], contains('onote://atom/'),
          reason: 'and the line is the reference that stands for it');

      final fields = t.widgetList<TextField>(find.byType(TextField)).toList();
      expect(fields, hasLength(3), reason: 'the paragraph and two cells');
      expect(fields[2].focusNode?.hasFocus, isTrue,
          reason: 'the caret lands in the SECOND cell — the first one is the '
              'word you just finished typing');
      app.cancelPendingSave();
    });

    testWidgets('at the START of a line it still indents, as it always did',
        (t) async {
      // The narrow half of OneNote's rule, and the reason it is narrow: Tab
      // at the start of a line is how an outline is built, and taking that
      // away to gain a table would be a trade nobody asked for.
      final b = await typing(t, 'Element');
      final field = t.widget<TextField>(find.byType(TextField).first);
      field.controller!.selection = const TextSelection.collapsed(offset: 0);
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();

      expect(tablesIn(b.content), isEmpty);
      expect(b.content['text'], '  Element',
          reason: 'indented, which is what Tab at a line start has meant all '
              'along');
      app.cancelPendingSave();
    });

    testWidgets('but Tab still nests a list, which it has always done',
        (t) async {
      final b = await typing(t, '- first\n- second');
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();

      expect(tablesIn(b.content), isEmpty,
          reason: 'Tab inside a list has meant nesting for as long as lists '
              'have, and that wins');
      expect(find.byType(Table), findsNothing);
      app.cancelPendingSave();
    });

    testWidgets('and Insert -> Table puts one in the paragraph you are in',
        (t) async {
      // The ribbon is an explicit request, so it does not care where the
      // caret is — but it goes INLINE while a paragraph is open, the same
      // rule "insert a page link" already follows.
      final b = await typing(t, 'Element');
      final field = t.widget<TextField>(find.byType(TextField).first);
      field.controller!.selection = const TextSelection.collapsed(offset: 0);
      await t.pumpAndSettle();

      expect(app.activeSession!.startInlineTable(), isTrue,
          reason: 'at the very start of the line, where Tab would decline');
      await t.pumpAndSettle();
      expect(tablesIn(b.content).single.cells, [
        ['Element', '']
      ]);
      app.cancelPendingSave();
    });

    testWidgets('and never nests a table inside a table', (t) async {
      // The line already holds a reference. Making it the first cell of a
      // new table would not be a nested table, it would be a lost one.
      await pump(t);
      app.editingBlockId = block.id;
      await pump(t);
      await t.tap(find.byType(TextField).first);
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();

      expect(tablesIn(block.content), hasLength(1));
      expect(find.byType(Table), findsOneWidget);
      app.cancelPendingSave();
    });
  });

  testWidgets('a new table opens with the caret in its first cell', (t) async {
    // You asked for a table because you are about to fill one in. The click
    // that made it says which cell, and the table consumes that once as it
    // opens — so it does not jump back there a quarter of an hour later.
    final made = app.insertTable(at: const Offset(0, 0));
    block = made;
    await pump(t);
    final cells = t.widgetList<TextField>(find.byType(TextField)).toList();
    expect(cells, hasLength(5), reason: 'the paragraph, and four cells');
    expect(cells[1].focusNode?.hasFocus, isTrue,
        reason: 'the first cell, not the paragraph beside it');
    app.cancelPendingSave();
  });

  test('the box is at least as wide as the table inside it', () {
    // The reference is stripped before the paragraph is measured — forty
    // characters of URL would pin the box to its maximum — which leaves the
    // measurement blind to the thing the reference stands for unless it asks.
    // A box too narrow does not overflow; the table quietly scales down, so
    // the failure would have been permanent and silent.
    final wide = Block(
      type: BlockType.text,
      x: 0,
      y: 0,
      w: 200,
      content: block.content,
    );
    final style = TextBlockView.baseStyle(wide, dark: false);
    final want = tableNaturalWidth(tablesIn(wide.content).single,
        style.copyWith(fontWeight: FontWeight.w600));
    expect(TextBlockView.autoWidth(wide, dark: false),
        greaterThanOrEqualTo(want));
  });

  test('a sentence beside a table gets room for BOTH', () {
    // The owner, after the box stopped snapping to its maximum: *"although it
    // pushed text onto the next line which isnt ideal"*. Quite so — the words
    // and the table are drawn one after the other, so the room they need is
    // the two added together. Taking the larger of the two instead is what
    // pushed the sentence onto the line below its own table.
    Block withText(String t) => Block(
        type: BlockType.text,
        x: 0,
        y: 0,
        w: 200,
        content: Map<String, dynamic>.from(block.content)..['text'] = t);

    final ref = InlineAtom.allIn(block.content)['t1']!.reference('2x2 table');
    final alone = TextBlockView.autoWidth(withText(ref), dark: false);
    final beside =
        TextBlockView.autoWidth(withText('Results: $ref and it holds.'), dark: false);

    expect(beside, greaterThan(alone),
        reason: 'the sentence needs room of its own, beside the table rather '
            'than instead of it');
    expect(beside, lessThan(TextBlockView.maxAutoW),
        reason: 'and it is the WORDS being measured, not ninety characters of '
            'the reference they sit next to');
  });

  testWidgets('a table in a paragraph is drawn when the block is read',
      (t) async {
    await pump(t);
    expect(find.byType(Table), findsOneWidget);
    expect(find.text('Sodium', findRichText: true), findsOneWidget);
    expect(find.textContaining('onote://atom', findRichText: true), findsNothing,
        reason: 'the reference stands for the table; it is not shown beside it');
  });

  testWidgets('and when the block is being edited', (t) async {
    await pump(t);
    app.editingBlockId = block.id;
    await pump(t);
    expect(find.byType(Table), findsOneWidget,
        reason: 'the session builds its own host; a table that drew only in '
            'read mode would turn into a URL under the caret');
  });

  testWidgets('the paragraph gives up its keyboard the FRAME a cell takes it',
      (t) async {
    // **The third gate, and why one frame of it matters.**
    //
    // A cell is a real `TextField` nested inside the paragraph's own, and a
    // host `FocusNode` reports `hasFocus` true while any DESCENDANT holds the
    // primary focus. So the paragraph never learns it has stopped being the
    // field being typed into: it keeps drawing its caret and keeps its
    // platform text-input connection open, and which of the two the next
    // character reaches comes down to attach order.
    //
    // The table announces that it has taken the keyboard — but it announces
    // it POST-FRAME, because focus moving from one cell to the next passes
    // through "nobody" and a signal sent mid-move would flap. That leaves a
    // frame in which a cell has the caret and the paragraph still believes it
    // does, and a frame is all a keystroke needs.
    //
    // So the gate is read from the focus tree, which cannot be stale:
    // `hasFocus` without `hasPrimaryFocus` means a descendant has it. This
    // pumps exactly ONE frame after the tap, before any notification could
    // have been delivered.
    app.editingBlockId = block.id;
    await pump(t);
    await t.tap(find.byType(TextField).at(1)); // the first cell
    await t.pump();

    final host = t.widget<TextField>(find.byType(TextField).first);
    expect(host.readOnly, isTrue,
        reason: 'the paragraph must let go of the keyboard in the same frame '
            'the cell takes it, not in the one after');
    expect(host.showCursor, isFalse,
        reason: 'and stop blinking a second caret beside the cell it is in');
  });

  group('a cell answers its own editing keys', () {
    // **A cell is a text field inside a text field**, and `EditableText`
    // publishes most of its editing actions through `Action.overridable` so
    // that a widget above a field can change what a key does inside it. The
    // paragraph IS above the cell, so it was found as the override and
    // answered for it: its action ran against the paragraph's own text and
    // posted the result at the cell. See [_CellsOwnAction] in
    // inline_table.dart. Both of these are the owner's, from real use.

    /// Into the first cell, with [text] typed into it.
    Future<TextEditingController> inCell(WidgetTester t, String text) async {
      app.editingBlockId = block.id;
      await pump(t);
      await t.tap(find.byType(TextField).at(1));
      await t.pumpAndSettle();
      t.testTextInput.updateEditingValue(TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ));
      await t.pumpAndSettle();
      return t.widget<TextField>(find.byType(TextField).at(1)).controller!;
    }

    Future<void> chord(WidgetTester t, LogicalKeyboardKey key,
        {bool shift = false}) async {
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(key);
      if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pumpAndSettle();
    }

    testWidgets('Ctrl+Backspace deletes a word', (t) async {
      final c = await inCell(t, 'hello world');
      await chord(t, LogicalKeyboardKey.backspace);
      expect(c.text, 'hello ',
          reason: 'the owner: "i am unable to backspace words". This resolved '
              'to the PARAGRAPH\'s delete action, which is disabled while a '
              'cell holds the keyboard — so the key did nothing at all');
      expect(tablesIn(block.content).single.cells[0][0], 'hello ',
          reason: 'and it reached the payload, like any other cell edit');
      app.cancelPendingSave();
    });

    testWidgets('Ctrl+Shift+Left selects a word, and only in the cell',
        (t) async {
      final c = await inCell(t, 'hello world');
      await chord(t, LogicalKeyboardKey.arrowLeft, shift: true);

      expect(c.selection.baseOffset, 11);
      expect(c.selection.extentOffset, 6,
          reason: 'one word back, inside the cell');
      expect(c.text, 'hello world',
          reason: 'the owner: this "caused it to bug out and say to update '
              'openote to view the table". The paragraph measured the word '
              'boundary in its OWN text and handed the cell that whole value, '
              'reference and all — and a cell has no atom host, so the only '
              'thing it could draw was the alt text');
      expect(c.text.contains(InlineAtom.scheme), isFalse);
      app.cancelPendingSave();
    });

    testWidgets('and Ctrl+Left moves by a word without disturbing anything',
        (t) async {
      final c = await inCell(t, 'hello world');
      await chord(t, LogicalKeyboardKey.arrowLeft);
      expect(c.selection.isCollapsed, isTrue);
      expect(c.selection.baseOffset, 6);
      expect(c.text, 'hello world');
      app.cancelPendingSave();
    });

    testWidgets('the paragraph keeps its own caret through all of it',
        (t) async {
      await inCell(t, 'hello world');
      final host =
          t.widget<TextField>(find.byType(TextField).first).controller!;
      final was = host.selection;
      await chord(t, LogicalKeyboardKey.arrowLeft, shift: true);
      await chord(t, LogicalKeyboardKey.backspace);
      expect(host.selection, was,
          reason: 'a key pressed in a cell is not the paragraph\'s business');
      expect(host.text, contains(InlineAtom.scheme),
          reason: 'and its reference is untouched');
      app.cancelPendingSave();
    });
  });

  test('a COPIED table pastes with its cells, not as an empty box', () {
    // Cutting leaves a payload behind for the paste to find. Copying does
    // not — the original stays exactly where it was, so nothing was ever
    // orphaned — and the clipboard carries the reference text and nothing
    // else. The paste has to find the payload on the page.
    final pasted = Block(
      type: BlockType.text,
      x: 0,
      y: 200,
      content: {'text': 'a copy: ${block.content['text']}'},
    );
    app.blocks = [block, pasted];

    reconcileBlockAtoms(app, pasted.id, pasted.content['text'] as String);

    expect(tablesIn(pasted.content).single.cells, [
      ['Element', 'Symbol'],
      ['Sodium', 'Na'],
    ]);
    expect(tablesIn(block.content), hasLength(1),
        reason: 'and the one it was copied FROM is untouched');
  });

  test('a reference to nothing at all stays a reference to nothing', () {
    final orphan = Block(
        type: BlockType.text,
        x: 0,
        y: 0,
        content: {'text': '![2x2 table](onote://atom/never-existed)'});
    app.blocks = [orphan];
    reconcileBlockAtoms(app, orphan.id, orphan.content['text'] as String);
    expect(tablesIn(orphan.content), isEmpty);
    expect(orphan.content.containsKey('atoms'), isFalse,
        reason: 'inventing an empty table would be inventing data');
  });

  testWidgets('one click on a cell opens the box AND lands in that cell',
      (t) async {
    // The headline interaction, end to end through the real block view: the
    // click asks the host to open, the host remembers which cell, and the
    // table consumes that as it mounts. Anything less is "click, then click
    // again", which is the thing that was asked not to happen.
    await pump(t);
    expect(app.editingBlockId, isNull, reason: 'precondition: being read');

    // Row 1, column 1 — "Na", the cell furthest from where a default caret
    // would land.
    final cells = find.byType(TextField);
    expect(cells, findsNothing, reason: 'a cell being read is not a field');
    await t.tap(find.text('Na', findRichText: true));
    await t.pumpAndSettle();

    expect(app.editingBlockId, block.id);
    await pump(t);
    final fields = t.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields, hasLength(5));
    expect(fields[4].focusNode?.hasFocus, isTrue,
        reason: 'the LAST cell — the one under the pointer — not the first');
    app.cancelPendingSave();
  });

  testWidgets('Bold belongs to whoever has the keyboard', (t) async {
    // With the caret in a cell, Ctrl+B and the toolbar's B must not reach
    // past it and style the sentence the table is sitting in. A table used to
    // be a block of its own, where `canFormatText` was false on the block
    // type alone; a table inside a paragraph made the paragraph the answer.
    await pump(t);
    app.editingBlockId = block.id;
    await pump(t);
    expect(app.canFormatText, isTrue, reason: 'precondition: a text block');

    await t.tap(find.byType(TextField).at(1));
    await t.pumpAndSettle();
    expect(app.canFormatText, isFalse,
        reason: 'the caret they can see is in the cell; Bold on the '
            'paragraph would be invisible and would fire later on a word '
            'they type somewhere else');

    app.cancelPendingSave();
  });

  testWidgets('typing in a cell writes to the block it is in', (t) async {
    await pump(t);
    app.editingBlockId = block.id;
    await pump(t);

    // Field 0 is the paragraph; the rest are cells.
    final cell = find.byType(TextField).at(1);
    await t.tap(cell);
    await t.pumpAndSettle();
    await t.enterText(cell, 'Hydrogen');
    await t.pumpAndSettle();

    app.cancelPendingSave();
    expect(tablesIn(block.content).single.cells.first.first, 'Hydrogen',
        reason: 'the host resolves the block by id and writes the payload '
            'there — that is the whole of what the wiring has to do');
    expect(block.content['text'], contains('onote://atom/t1'),
        reason: 'and the paragraph itself is untouched');
  });
}
