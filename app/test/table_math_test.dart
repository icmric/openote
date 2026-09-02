// Maths (and the rest of the inline grammar) inside TABLE CELLS, read mode —
// open finding since v0.18 §13.6, flagged by two audits: TableBlockView drew
// cell text with a bare `Text`, so a formula table's `$x^2$` showed its
// dollar signs and backslashes literally and `**bold**` kept its asterisks.
// Students build revision/formula tables constantly, so a table was the one
// place on the page where an equation silently stayed raw source.
//
// Pure widget tests — no database. Read mode only *reads*
// `app.editingBlockId`, so a repository stub is enough (same trick as
// undo_redo_test.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/table_block_view.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/math/math_view.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

/// A repository stub: rendering a table never reaches storage, and a real
/// repository would drag SQLite into a pure widget test.
class _NoopRepo implements Repository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late AppState app;
  late Block table;

  setUp(() {
    app = AppState(_NoopRepo())
      ..notebookId = 'nb'
      ..pageId = 'pg';
    table = Block(type: BlockType.table, x: 0, y: 0, content: {
      'cells': [
        ['Speed', r'$x^2$'],
        ['plain text', '**bold**'],
      ],
    });
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 420,
            child: TableBlockView(block: table, app: app),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a cell holding \$x^2\$ draws maths in read mode, not dollars',
      (tester) async {
    await pump(tester);
    expect(find.byType(OnoteMath), findsOneWidget,
        reason: 'the equation must be DRAWN — cells used to skip the inline '
            'renderer entirely, so a formula table showed raw LaTeX');
    expect(find.text(r'$x^2$'), findsNothing,
        reason: 'the dollar signs are delimiters, not content; showing them '
            'is the v0.18 §13.6 defect this pins');
  });

  testWidgets('a plain cell renders its text unchanged', (tester) async {
    await pump(tester);
    // Both the header cell and the body cell: routing every cell through the
    // Markdown grammar must not mangle ordinary words.
    expect(find.text('Speed', findRichText: true), findsOneWidget);
    expect(find.text('plain text', findRichText: true), findsOneWidget);
  });

  testWidgets('the whole grammar applies: **bold** loses its asterisks',
      (tester) async {
    await pump(tester);
    expect(find.text('bold', findRichText: true), findsOneWidget,
        reason: 'inlineSpans carries bold/italic/links too — a cell used to '
            'show the literal ** markers around bold text');
    expect(find.textContaining('**', findRichText: true), findsNothing);
  });

  testWidgets('while a cell is edited, the raw source shows in a TextField',
      (tester) async {
    await pump(tester);
    // Enter editing the way the canvas does: mark this block as the one
    // being edited, then rebuild.
    app.editingBlockId = table.id;
    await pump(tester);

    expect(find.byType(OnoteMath), findsNothing,
        reason: 'editing must expose the raw source — rendering the maths '
            'under the caret would make the delimiters untypeable');
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => f.controller!.text)
        .toList();
    expect(fields, contains(r'$x^2$'),
        reason: 'the editor shows exactly what is stored, dollars included');
    expect(fields, contains('**bold**'));
  });
}
