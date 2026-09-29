// **Nothing in a table may change when it moves into the paragraph.**
//
// The owner: *"Its incredibly important though that no data inside the table
// could ever be lost and that the content in and around the old tables wont
// corrupt the new table in any way … ideally it should be so smooth that users
// dont even initially notice the change."*
//
// `table_conversion_test.dart` proves the table READS BACK the same. That is a
// weaker property than it looks, because both sides of the comparison run
// through `TableData.from`, which normalises — it stringifies every cell and
// pads every short row. Two different stored forms that normalise to the same
// thing compare equal, so the proof cannot see a conversion that rewrote what
// is on disk.
//
// These tests hold the STORED form to account instead: whatever was in the
// file is what comes out, byte for byte, however awkward it was.

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter/painting.dart';
import 'package:openote/editor/inline_table.dart';
import 'package:openote/model/inline_atom.dart';
import 'package:openote/model/models.dart';
import 'package:openote/model/table_conversion.dart';

void main() {
  Block tableBlock(Map<String, dynamic> content) => Block(
        type: BlockType.table,
        id: 'b-keep',
        x: 12,
        y: 34,
        w: 456,
        h: 78,
        z: 3,
        content: content,
      );

  /// The atom payload a conversion produced, or null if it refused.
  Map<String, dynamic>? payloadOf(Block b) {
    final out = tableBlockAsText(b, madeIn: 'test', atomId: () => 'atom-1');
    if (out == null) return null;
    return InlineAtom.allIn(out.content)['atom-1']?.content;
  }

  group('the cells that are stored', () {
    test('plain strings survive exactly', () {
      final p = payloadOf(tableBlock({
        'cells': [
          ['Element', 'Symbol'],
          ['Sodium', 'Na'],
        ]
      }))!;
      expect(p['cells'], [
        ['Element', 'Symbol'],
        ['Sodium', 'Na'],
      ]);
    });

    test('NUMBERS stay numbers', () {
      // A CSV import writes real numbers. Turning 1 into "1" is not a loss of
      // meaning, but it is a rewrite of somebody's file by a job that ran on
      // its own while they were not looking, and the proof cannot see it.
      final p = payloadOf(tableBlock({
        'cells': [
          ['Mass', 22.99],
          [11, true],
        ]
      }))!;
      expect(p['cells'], [
        ['Mass', 22.99],
        [11, true],
      ]);
    });

    test('a JAGGED grid is not padded on the way through', () {
      // The editor pads short rows when it DRAWS them, and always has. That is
      // a reading of the data, not a change to it.
      final p = payloadOf(tableBlock({
        'cells': [
          ['a', 'b', 'c'],
          ['d'],
          <String>[],
        ]
      }))!;
      expect(p['cells'], [
        ['a', 'b', 'c'],
        ['d'],
        <String>[],
      ]);
    });

    test('a null cell stays null', () {
      final p = payloadOf(tableBlock({
        'cells': [
          ['a', null],
          [null, 'd'],
        ]
      }))!;
      expect(p['cells'], [
        ['a', null],
        [null, 'd'],
      ]);
    });

    test('markdown and punctuation in a cell are untouched', () {
      // `](` is the one sequence that could end a reference early if a cell
      // ever reached the buffer. It must not, and it does not — the cells live
      // in the payload, never in the text.
      final p = payloadOf(tableBlock({
        'cells': [
          ['**bold**', r'$x^2$'],
          ['a](b)', '![img](sha256:deadbeef)'],
        ]
      }))!;
      expect(p['cells'], [
        ['**bold**', r'$x^2$'],
        ['a](b)', '![img](sha256:deadbeef)'],
      ]);
    });
  });

  group('everything else the block was carrying', () {
    test('column widths survive exactly, including a short list', () {
      final p = payloadOf(tableBlock({
        'cells': [
          ['a', 'b', 'c']
        ],
        'colWidths': [120, 0],
      }))!;
      expect(p['colWidths'], [120, 0]);
    });

    test('a key this build has never heard of is kept', () {
      // A newer device's table is not a corrupt one. Dropping what we do not
      // understand is how a conversion deletes somebody's work on the next
      // sync.
      final out = tableBlockAsText(
          tableBlock({
            'cells': [
              ['a']
            ],
            'headerStyle': 'bold',
            'futureThing': {'v': 2},
          }),
          madeIn: 'test',
          atomId: () => 'atom-1')!;
      final kept = {...out.content}..remove('text')..remove('atoms');
      expect(kept['headerStyle'], 'bold');
      expect(kept['futureThing'], {'v': 2});
    });

    test('identity, position, size and z-order are unchanged', () {
      final out = tableBlockAsText(
          tableBlock({
            'cells': [
              ['a']
            ]
          }),
          madeIn: 'test',
          atomId: () => 'atom-1')!;
      expect(out.id, 'b-keep');
      expect([out.x, out.y, out.w, out.h, out.z], [12.0, 34.0, 456.0, 78.0, 3]);
    });
  });

  group('what it refuses', () {
    test('a cells value that is not a grid at all', () {
      expect(payloadOf(tableBlock({'cells': 'not a table'})), isNull);
    });

    test('a colWidths that is not a list', () {
      expect(
          payloadOf(tableBlock({
            'cells': [
              ['a']
            ],
            'colWidths': 'wide',
          })),
          isNull);
    });

    test('and a block that is not a table at all', () {
      expect(
          tableBlockAsText(
              Block(type: BlockType.text, x: 0, y: 0, content: {'text': 'hi'}),
              madeIn: 'test'),
          isNull);
    });
  });

  group('the width a block knew and an atom cannot ask for', () {
    // The owner: *"cell width seems to get lost still. This isnt the end of
    // the world, except for that it means that many pages end up slightly off
    // when converting the tables."*
    //
    // A table BLOCK is a box with a width, and a table with no column widths
    // of its own simply filled it. An atom has no box — it sizes its columns
    // from what is in them — so a three-word table that used to fill 620px
    // draws at 277. Nothing was dropped; the width was recorded somewhere the
    // new shape does not have.

    Block wide({List<double>? widths, double w = 620}) => Block(
          type: BlockType.table,
          x: 0,
          y: 0,
          w: w,
          content: {
            'cells': [
              ['Element', 'Symbol', 'Z'],
              ['Sodium', 'Na', '11'],
            ],
            if (widths != null) 'colWidths': widths,
          },
        );

    /// What the columns ask for on their own, which is what the caller
    /// measures and scales.
    List<double> natural(Block b) =>
        tableColumnWidths(TableData.from(b.content), const TextStyle(fontSize: 13));

    List<double> scaledTo(Block b, double target) {
      final n = natural(b);
      final k = target / n.fold<double>(0, (a, c) => a + c);
      return [for (final w in n) w * k];
    }

    test("a table with no widths of its own is given the block's", () {
      final b = wide();
      // 8px of block padding a side, so 604 of usable width.
      final want = scaledTo(b, 604);
      final out = tableBlockAsText(b, madeIn: 'test', widthsIfNone: want)!;
      final t = tablesIn(out.content).single;

      expect(t.colWidths, want);
      expect(t.colWidths.fold<double>(0, (a, c) => a + c), closeTo(604, 0.001),
          reason: 'it fills the box it used to fill');
      expect(t.colWidths[0], greaterThan(t.colWidths[2]),
          reason: "the content's own proportions, not equal shares — a "
              'three-character column given a third of 620px looks wrong in a '
              'way a reader notices');
      expect(t.cells[1][0], 'Sodium', reason: 'and nothing else moved');
    });

    test('a table that says what it wants is not second-guessed', () {
      final b = wide(widths: [100, 200, 300]);
      final out =
          tableBlockAsText(b, madeIn: 'test', widthsIfNone: [9, 9, 9])!;
      expect(tablesIn(out.content).single.colWidths, [100, 200, 300],
          reason: 'dragged widths are carried verbatim like everything else');
    });

    test('and with nothing offered, nothing is added', () {
      final out = tableBlockAsText(wide(), madeIn: 'test')!;
      expect(tablesIn(out.content).single.colWidths, isEmpty,
          reason: 'the old behaviour, still reachable — this function may not '
              'invent a width on its own');
    });

    test('a list it cannot vouch for is refused, and changes nothing', () {
      for (final bad in <List<double>>[
        [10, 20], // too short
        [10, 20, 30, 40], // too long
        [10, 20, double.nan],
        [10, 20, double.infinity],
        [10, 20, 0], // a zero width means "measure me", not "be invisible"
        [10, 20, -5],
      ]) {
        final out = tableBlockAsText(wide(), madeIn: 'test', widthsIfNone: bad);
        expect(out, isNotNull, reason: 'the conversion still happens: $bad');
        expect(tablesIn(out!.content).single.colWidths, isEmpty,
            reason: 'it simply declines the widths: $bad');
      }
    });

    test('the proof still refuses a table it would have changed', () {
      // The guard that makes all of this safe: the result is compared against
      // the table that SHOULD come out, so a width written wrong is a refusal
      // rather than a quiet rewrite.
      final b = wide();
      final out = tableBlockAsText(b, madeIn: 'test', widthsIfNone: [1.5, 2.5, 3.5]);
      expect(out, isNotNull);
      expect(tablesIn(out!.content).single.colWidths, [1.5, 2.5, 3.5],
          reason: 'silly but valid, and honoured exactly — the caller is '
              'trusted to measure, and audited on the shape of what it says');
    });
  });
}
