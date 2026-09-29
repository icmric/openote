// Adding a column must not shrink the ones already there.
//
// Reported: *"when i add a new column, it makes the existing ones smaller,
// compressing the text (and keeping the new one just a bit too small so typed
// text gets wrapped)"*.
//
// Two faults, one symptom each.
//
// The compression was the box refusing to grow. `TextBlockView.autoWidth`
// clamped every box to `maxAutoW`, 640px — which is a READING measure, the
// width past which a line of prose is tiring to follow. A paragraph that wide
// wraps and is fine. A table cannot wrap: `InlineTable` scales its columns
// down to fit whatever box it is handed, so the ceiling meant for comfortable
// prose was silently compressing somebody's data instead.
//
// The too-small new column was `_measuredColumn` clamping an empty column to
// `kTableColumnMin` — the DRAG floor, 36px, about three characters. That is
// the right floor for "how narrow may somebody drag this" and the wrong one
// for "how wide should the app make a column nobody has sized".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/inline_table.dart';
import 'package:openote/editor/text_block_view.dart';
import 'package:openote/model/inline_atom.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';

class _NoopRepo implements Repository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  // The same weight the widget measures at: a bold header measured as body
  // text clips its own last word, so the measurement uses the header style.
  final head = onoteTheme(Brightness.light)
      .textTheme
      .bodyMedium!
      .copyWith(fontWeight: FontWeight.w600);

  TableData grid(List<List<String>> cells) =>
      TableData(cells: cells, colWidths: const []);

  /// A text block holding nothing but [d], as the editor stores one.
  Block blockWith(TableData d) {
    const id = 't1';
    final atom = InlineAtom(id: id, type: 'table', content: d.toContent());
    final content = <String, dynamic>{
      'text': atom.reference(TableData.referenceAlt)
    };
    InlineAtom.putIn(content, atom);
    return Block(type: BlockType.text, x: 0, y: 0, w: 200, content: content);
  }

  group('a column nobody has sized', () {
    test('an empty one is wide enough to type a word into', () {
      final widths = tableColumnWidths(grid([
        ['Element', '']
      ]), head);
      expect(widths[1], kTableColumnAuto,
          reason: 'the drag floor is not a sensible default width');
      expect(kTableColumnAuto, greaterThan(kTableColumnMin),
          reason: 'and the two are different questions');
    });

    test('a short one is not squeezed to the drag floor either', () {
      final widths = tableColumnWidths(grid([
        ['Symbol'],
        ['Na'],
      ]), head);
      expect(widths.single, greaterThanOrEqualTo(kTableColumnAuto));
    });

    test('a long one still measures its contents, up to the cap', () {
      final widths = tableColumnWidths(grid([
        ['A rather long heading that would happily run on and on and on']
      ]), head);
      expect(widths.single, kTableColumnCap);
    });
  });

  group('adding a column', () {
    test('leaves every existing column exactly the width it had', () {
      final before = grid([
        ['Element name in full', 'Chemical symbol'],
        ['Sodium', 'Na'],
      ]);
      final was = tableColumnWidths(before, head);
      final now = tableColumnWidths(before.insertColumn(2), head);

      expect(now.length, was.length + 1);
      // `insertColumn` does not redistribute stored widths. The compression
      // the owner saw happened a layer up, in the widget — see the rendered
      // test below, which is the one that fails without the fix.
      expect(now.take(2).toList(), was,
          reason: 'a new column must not be taken out of its neighbours');
    });

    test('makes the table want more room, not the same room shared out', () {
      final before = grid([
        ['Element name in full', 'Chemical symbol'],
        ['Sodium', 'Na'],
      ]);
      expect(tableNaturalWidth(before.insertColumn(2), head),
          greaterThan(tableNaturalWidth(before, head)));
    });
  });

  group('the box a table lives in', () {
    test('grows past the reading measure to hold a wide table', () {
      // Three columns of real headings want well over 640px between them.
      final wide = grid([
        ['Element name in full', 'Chemical symbol', 'Relative atomic mass'],
        ['Sodium', 'Na', '22.99'],
      ]);
      final need = tableNaturalWidth(wide, head);
      expect(need, greaterThan(TextBlockView.maxAutoW),
          reason: 'precondition: this table does not fit a prose box');

      final w = TextBlockView.autoWidth(blockWith(wide), dark: false);
      expect(w, greaterThanOrEqualTo(need),
          reason: 'THE BUG: the box stopped at 640 and the table was squeezed');
      expect(w, lessThanOrEqualTo(TextBlockView.maxObjectW),
          reason: 'large, but not unbounded');
    });

    test('but a paragraph of prose still stops at the reading measure', () {
      final b = Block(
        type: BlockType.text,
        x: 0,
        y: 0,
        w: 200,
        content: {
          'text': List.filled(60, 'the quick brown fox jumps over').join(' ')
        },
      );
      expect(TextBlockView.autoWidth(b, dark: false), TextBlockView.maxAutoW,
          reason: 'prose wraps, so widening it past 640 only hurts reading');
    });

    testWidgets('DRAWN: a wide table keeps its columns, it is not squeezed',
        (t) async {
      // The property as the owner meets it, through the real widget and the
      // real box. `tableColumnWidths` above is what a column WANTS; this is
      // what it GETS, and the two came apart exactly when the table wanted
      // more than the box was allowed to be.
      final app = AppState(_NoopRepo())
        ..notebookId = 'nb'
        ..pageId = 'pg'
        ..spellCheckEnabled = false;
      addTearDown(app.cancelPendingSave);

      Future<List<double>> draw(TableData d) async {
        final b = blockWith(d);
        // The width the canvas would give it, which is the whole question.
        b.w = TextBlockView.autoWidth(b, dark: false);
        app.blocks = [b];
        await t.pumpWidget(MaterialApp(
          localizationsDelegates: kOnoteLocalizations,
          supportedLocales: kOnoteLocales,
          theme: onoteTheme(Brightness.light),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                  width: b.w, child: TextBlockView(block: b, app: app)),
            ),
          ),
        ));
        await t.pumpAndSettle();
        final table = t.widget<Table>(find.byType(Table));
        return [
          for (var c = 0; c < d.cols; c++)
            (table.columnWidths![c]! as FixedColumnWidth).value
        ];
      }

      final wide = grid([
        ['Element name in full', 'Chemical symbol', 'Relative atomic mass'],
        ['Sodium', 'Na', '22.99'],
      ]);
      final drawn = await draw(wide);
      final wanted = tableColumnWidths(wide, head);

      expect(tableNaturalWidth(wide, head),
          greaterThan(TextBlockView.maxAutoW),
          reason: 'precondition: this table does not fit a prose box');
      // Not equality: a box with room to spare grows its columns to fill it
      // (`_growToFit`), so drawn is a little WIDER than wanted. The property
      // is one-sided on purpose — no column may be narrower than the content
      // it was measured to hold, which is what compression means.
      for (var c = 0; c < drawn.length; c++) {
        expect(drawn[c], greaterThanOrEqualTo(wanted[c] - 0.5),
            reason: 'THE BUG: column $c was scaled down to fit a 640px box');
      }
    });

    test('a narrow table does not drag its box wider than it needs', () {
      final w = TextBlockView.autoWidth(
          blockWith(grid([
            ['a', 'b']
          ])),
          dark: false);
      expect(w, lessThanOrEqualTo(TextBlockView.maxAutoW));
    });
  });
}
