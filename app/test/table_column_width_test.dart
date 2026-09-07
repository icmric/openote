// How wide a table column gets, and who decides.
//
// The owner, on imported tables: "the major thing with them which im only just
// noticing now is that there isnt any way for me to manually resize the cells,
// at least by dragging which is how it should be done, i wonder if that is
// part of why they still arent sizing to the content inside (which when we do,
// ensure it still obeys a max width so we dont end up with crazy long cells by
// default, although if i drag the cell out there is no reason it should stop
// at that max width, its like the boxes where they have a default max width
// they will grow to, but it can be overriden manually."
//
// Three rules, and the third is the one that makes the other two safe:
//
//   1. No stored width → as wide as the contents need…
//   2. …but never wider than [kTableColumnCap], or one long sentence turns a
//      table into a ribbon.
//   3. A width somebody SET — dragged, or sent by OneNote — is used exactly,
//      and the cap does not apply to it. If you drag a column out to six
//      hundred pixels you meant it.
//
// Every column used to get an equal flex share, which is why they "all default
// to larger when they should be smaller": a two-character column took the same
// room as a paragraph.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/table_block_view.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/app.dart';

/// The same stand-in `table_math_test.dart` uses: this exercises how a table
/// is laid out, and nothing here touches storage.
class _NoopRepo implements Repository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  final app = AppState(_NoopRepo())
    ..notebookId = 'nb'
    ..pageId = 'pg';

  Block table(List<List<String>> cells, {List<num>? widths}) => Block(
        type: BlockType.table,
        x: 0,
        y: 0,
        w: 600,
        content: {
          'cells': cells,
          if (widths != null) 'colWidths': widths,
        },
      );

  Future<Table> render(WidgetTester tester, Block b) async {
    // On the page, not only in the widget: a column drag pushes an undo step,
    // and an undo step is a snapshot of `app.blocks`.
    app.blocks
      ..clear()
      ..add(b);
    await tester.pumpWidget(testApp(Scaffold(
      body: SizedBox(
        width: 900,
        child: TableBlockView(block: b, app: app),
      ),
    )));
    await tester.pump();
    return tester.widget<Table>(find.byType(Table));
  }

  testWidgets('a column with no stored width fits its contents, up to the cap',
      (tester) async {
    final t = await render(
        tester,
        table([
          ['Yes', 'A rather long sentence that would happily run on and on'],
          ['No', 'short'],
        ]));

    // Measured rather than asked of the framework: `IntrinsicColumnWidth`
    // cannot size a cell holding a rich-text renderer or a TextField, and the
    // table fails to lay out at all. So every column is a FixedColumnWidth,
    // and what is asserted is the NUMBER.
    final narrow = (t.columnWidths![0]! as FixedColumnWidth).value;
    final wide = (t.columnWidths![1]! as FixedColumnWidth).value;
    expect(narrow, lessThan(wide),
        reason: 'a two-character column is not as wide as a sentence');
    expect(wide, lessThanOrEqualTo(kTableColumnCap),
        reason: 'and the long one stops at the cap');
    expect(narrow, greaterThanOrEqualTo(kTableColumnMin));
  });

  testWidgets('a stored width is used exactly, and the cap does not apply',
      (tester) async {
    // The rule that makes dragging worth having. A column dragged past the
    // automatic maximum stays where it was put.
    final beyond = kTableColumnCap + 280;
    final t = await render(
        tester,
        table([
          ['a', 'b'],
          ['c', 'd'],
        ], widths: [beyond, 90]));

    final wide = t.columnWidths![0];
    expect(wide, isA<FixedColumnWidth>());
    expect((wide! as FixedColumnWidth).value, beyond,
        reason: 'a width somebody chose is not clamped by the automatic cap');
    expect((t.columnWidths![1]! as FixedColumnWidth).value, 90);
  });

  testWidgets('columns are no longer forced to share equally', (tester) async {
    // The original complaint: every column took the same room whatever was in
    // it, so a two-character column was as wide as a paragraph.
    final t = await render(
        tester,
        table([
          ['x', 'y'],
          ['1', '2'],
        ]));

    expect(t.columnWidths!.values.whereType<FlexColumnWidth>(), isEmpty,
        reason: 'an equal share each is what made every column the same size');
  });

  testWidgets('a stored list that no longer matches the table is tolerated',
      (tester) async {
    // A column added since the widths were stored has no width of its own,
    // which is right — nobody chose one for a column that did not exist.
    final t = await render(
        tester,
        table([
          ['a', 'b', 'c'],
          ['d', 'e', 'f'],
        ], widths: [120]));

    expect((t.columnWidths![0]! as FixedColumnWidth).value, 120,
        reason: 'the stored one is honoured exactly');
    // The two that were never sized fall back to their measured width, which
    // for one character is the minimum.
    for (final c in [1, 2]) {
      expect((t.columnWidths![c]! as FixedColumnWidth).value,
          lessThan(kTableColumnCap));
    }
  });

  testWidgets('the drag handle is there without going into the table first',
      (tester) async {
    // The owner, after the first version shipped: *"table resizing works
    // which is great, however it only works while editing the table, id love
    // to be able to resize cells without having to go into edit mode."*
    //
    // Quite right, and the original gate was too clever: handles appeared
    // only while the block was edited or selected, on the theory that a table
    // being read should not look like a control panel. But the handle has no
    // appearance — it is six invisible pixels and a cursor — so there was
    // nothing to keep off the page, and the gate cost the one gesture
    // everybody already knows from every spreadsheet they have ever used.
    final b = table([
      ['a', 'b'],
      ['c', 'd'],
    ]);
    await render(tester, b);

    final handles = find.byWidgetPredicate((w) =>
        w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn);
    expect(handles, findsNWidgets(2),
        reason: 'one per column, on a table nobody has selected or opened');
  });

  testWidgets('dragging one sets that column and leaves the rest alone',
      (tester) async {
    final b = table([
      ['a', 'b'],
      ['c', 'd'],
    ]);
    await render(tester, b);

    final handles = find.byWidgetPredicate((w) =>
        w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn);
    await tester.drag(handles.first, const Offset(120, 0));
    await tester.pump();

    final stored = (b.content['colWidths'] as List).cast<num>();
    expect(stored[0], greaterThan(kTableColumnMin + 100),
        reason: 'the column follows the pointer');
    expect(stored[1], 0, reason: 'a column nobody dragged stays unset');

    // Setting a width arms the debounced save; drain it or the test ends
    // holding a timer and fails on that instead.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 900));
  });

  testWidgets('a whole drag is ONE undo step, not one per pixel',
      (tester) async {
    // Reported: *"if the table overflows the box, it doesnt seem to auto
    // expand the box with it, the app will freeze and crash."*
    //
    // The freeze is this, and it has nothing to do with overflowing. Every
    // pointer sample called `pushUndo`, and an undo step is `jsonEncode` of
    // every block on the page — so a drag on a page carrying handwriting was
    // re-encoding megabytes a hundred times a second, and keeping a hundred
    // of them. Freeze, then out of memory.
    //
    // Asserted through behaviour rather than by counting the stack: one
    // Ctrl+Z should put the column back where it started, which is also the
    // thing somebody actually wants.
    final b = table([
      ['a', 'b'],
      ['c', 'd'],
    ], widths: [140, 90]);
    await render(tester, b);

    final handles = find.byWidgetPredicate((w) =>
        w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn);
    await tester.drag(handles.first, const Offset(160, 0));
    await tester.pump();
    expect((b.content['colWidths'] as List)[0], greaterThan(200.0));

    app.undo();
    expect((app.blocks.single.content['colWidths'] as List)[0], 140,
        reason: 'one drag, one undo');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 900));
  });

  testWidgets('the box grows to hold the table it is given', (tester) async {
    // The other half of the report. A table dragged wider than its box used
    // to spill out of it — the box has a stored width and nothing was moving
    // it. It only ever grows: a box somebody made wide by hand must not
    // snap back because a column was narrowed.
    final b = table([
      ['a', 'b'],
      ['c', 'd'],
    ], widths: [200, 200]);
    await render(tester, b);

    final handles = find.byWidgetPredicate((w) =>
        w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn);
    await tester.drag(handles.first, const Offset(400, 0));
    await tester.pump();

    final total = (b.content['colWidths'] as List)
        .cast<num>()
        .fold<double>(0, (a, w) => a + w);
    expect(b.w, greaterThanOrEqualTo(total),
        reason: 'the table has to fit inside the box that holds it');

    final wide = b.w;
    await tester.drag(handles.first, const Offset(-300, 0));
    await tester.pump();
    expect(b.w, wide, reason: 'and the box does not shrink back on its own');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 900));
  });

  testWidgets('a zero or nonsense width reads as unset, not as a zero column',
      (tester) async {
    // Unset columns are stored as 0, because the list has to stay a full list
    // for the exporters that already read it.
    final t = await render(
        tester,
        table([
          ['a', 'b'],
          ['c', 'd'],
        ], widths: [0, -5]));

    for (final c in [0, 1]) {
      final w = (t.columnWidths![c]! as FixedColumnWidth).value;
      expect(w, greaterThanOrEqualTo(kTableColumnMin),
          reason: 'a stored 0 must not produce a column of no width');
    }
  });
}
