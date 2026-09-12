// The wiring, end to end through a real text block.
//
// `inline_table_test.dart` mounts the controller and the table directly, which
// is where the behaviour is. This file asserts the thing that file cannot: that
// the EDITOR actually hands an atom a host — in both of its halves. The read
// view and the editing session build that host in two different places
// (`buildReadOnly` and `openSession`), and a table that draws in one and not
// the other is the shape-change this whole piece of work exists to remove.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
