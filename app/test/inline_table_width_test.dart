// Dragging a column of a table that lives INSIDE a paragraph.
//
// `table_column_width_test.dart` covers this through `TableBlockView`, which
// is the legacy shape: a table alone in a block of its own. Every table is
// converted to an atom inside a paragraph on open now, so that is no longer
// the path anybody's hands are on — and the drag handle, the undo grouping and
// the box growing to fit were all rebuilt when the widget was rewritten.
//
// This is the same three properties, asserted where people actually meet them.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/inline_table.dart';
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
    final content = <String, dynamic>{'text': atom.reference('2x2 table')};
    InlineAtom.putIn(content, atom);
    block = Block(type: BlockType.text, x: 0, y: 0, w: 520, content: content);
    app.blocks = [block];
  });

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

  Finder handles() => find.byWidgetPredicate(
      (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn);

  /// Drag column [i]'s right edge by [dx].
  ///
  /// The cancel is inside the helper rather than in `tearDown` because a write
  /// arms the debounced save and the binding checks for pending timers BEFORE
  /// tear-downs run — so a test that only cleaned up afterwards failed on the
  /// timer instead of on what it came to check.
  Future<void> dragCol(WidgetTester t, int i, double dx) async {
    await t.drag(handles().at(i), Offset(dx, 0));
    await t.pumpAndSettle();
    app.cancelPendingSave();
  }

  List<double> widths() => tablesIn(block.content).single.colWidths;

  testWidgets('a table in a paragraph has a handle on every column',
      (t) async {
    await pump(t);
    expect(handles(), findsNWidgets(2),
        reason: 'one per column, without opening anything first');
  });

  testWidgets('dragging one sets that column and leaves the rest', (t) async {
    await pump(t);
    await dragCol(t, 0, 120);

    final w = widths();
    expect(w, isNotEmpty, reason: 'the width reached the payload');
    expect(w.first, greaterThan(kTableColumnMin + 100),
        reason: 'the column follows the pointer');
    if (w.length > 1) {
      expect(w[1], anyOf(0.0, lessThan(kTableColumnCap)),
          reason: 'a column nobody dragged is not given a width');
    }
  });

  testWidgets('a width somebody chose beats the automatic cap', (t) async {
    await pump(t);
    await dragCol(t, 0, 400);
    expect(widths().first, greaterThan(kTableColumnCap),
        reason: 'if you drag it out that far you meant it');
  });

  testWidgets('a whole drag is ONE undo step', (t) async {
    // The freeze-then-crash this had before the flag existed: an undo entry is
    // the encoded page, and a drag samples the pointer a hundred times a
    // second. Asserted through behaviour — one Ctrl+Z puts the column back.
    await pump(t);
    await dragCol(t, 0, 160);
    expect(widths().first, greaterThan(100));

    app.undo();
    await t.pumpAndSettle();
    app.cancelPendingSave(); // undo marks the page dirty too
    final after = tablesIn(app.blocks.single.content).single.colWidths;
    expect(after.isEmpty || after.first == 0, isTrue,
        reason: 'one drag, one undo — it was unset before, so it is unset now');
  });

  testWidgets('the box grows to hold a column dragged past its edge',
      (t) async {
    await pump(t);
    final before = block.w;
    await dragCol(t, 0, 500);

    expect(TextBlockView.autoWidth(block, dark: false),
        greaterThan(before),
        reason: 'a table wider than its box has to make the box wider');
  });
}
