// GFM pipe-table parsing — the read side of `tableToMarkdown`.
//
// Table interop was one-way: Openote wrote GFM tables and could not read one
// back, so a table pasted in as Markdown rendered as rows of raw pipes.
// The round-trip case at the bottom is the one that matters most: anything the
// app writes, it must be able to read.
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/export/md_common.dart';
import 'package:openote/markdown/md_table.dart';

void main() {
  group('detection', () {
    test('needs a delimiter row, so prose containing a pipe is not a table', () {
      // Without the two-line signature, "a | b" in ordinary text would be
      // swallowed as a one-row table.
      expect(parsePipeTable(['costs | benefits', 'and then some'], 0), isNull);
      expect(parsePipeTable(['| a | b |', 'not a delimiter'], 0), isNull);
    });

    test('a header plus delimiter is enough, even with no body rows', () {
      final m = parsePipeTable(['| a | b |', '| --- | --- |'], 0)!;
      expect(m.table.header, ['a', 'b']);
      expect(m.table.rows, isEmpty);
      expect(m.consumed, 2);
    });

    test('stops at the first non-table line', () {
      final m = parsePipeTable([
        '| a |',
        '| --- |',
        '| 1 |',
        '',
        'after the table',
      ], 0)!;
      expect(m.consumed, 3);
      expect(m.table.rows, [
        ['1']
      ]);
    });
  });

  group('cells', () {
    test('honours escaped pipes, or a round-trip would split a cell', () {
      expect(splitRow(r'| a \| b | c |'), ['a | b', 'c']);
    });

    test('tolerates missing outer pipes', () {
      expect(splitRow('a | b'), ['a', 'b']);
    });

    test('pads ragged rows and trims overlong ones to the header width', () {
      final m = parsePipeTable([
        '| a | b | c |',
        '| --- | --- | --- |',
        '| 1 |',
        '| 1 | 2 | 3 | 4 |',
      ], 0)!;
      expect(m.table.rows[0], ['1', '', '']);
      expect(m.table.rows[1], ['1', '2', '3']);
    });
  });

  group('alignment', () {
    test('reads the colon markers', () {
      final m = parsePipeTable([
        '| l | c | r | d |',
        '| :--- | :---: | ---: | --- |',
      ], 0)!;
      expect(m.table.align,
          [MdAlign.left, MdAlign.center, MdAlign.right, MdAlign.left]);
    });
  });

  test('round-trips a table written by tableToMarkdown', () {
    // The property that makes this worth having: our own exporter's output must
    // parse back to the same grid, escaped pipes and all.
    const cells = [
      ['Name', 'Note'],
      ['a | b', 'has a pipe'],
      ['x', ''],
    ];
    final md = tableToMarkdown(cells);
    final m = parsePipeTable(md.split('\n'), 0)!;
    expect(m.table.header, ['Name', 'Note']);
    expect(m.table.rows, [
      ['a | b', 'has a pipe'],
      ['x', ''],
    ]);
  });
}
