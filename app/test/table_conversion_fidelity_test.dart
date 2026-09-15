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
}
