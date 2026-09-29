// The contract an inline atom is: a reference in the text, a payload beside
// it, and a reading of a table that is the same wherever the table is kept.
//
// v0.19 Step 1. Nothing is visible to a user yet — this is the storage and
// the grammar, and it is where the round-trip and conversion properties are
// pinned, because a conversion that loses a cell is not something a later
// test of the widget would notice.
//
// **The conversion tests are the backwards-compatibility ones.** A table
// block's `cells` really does hold things other than strings: a CSV import
// writes numbers, the OneNote importer writes whatever the source had, a
// hand-edited file has nulls, and jagged rows come from both. The editor has
// always coerced with `toString()` and padded short rows to the widest one,
// so anything else here would silently change somebody's table.
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/markdown/md_syntax.dart';
import 'package:openote/model/inline_atom.dart';

void main() {
  group('the reference grammar', () {
    MdMatch? classify(String text) {
      final m = mdInlineRe.firstMatch(text);
      return m == null ? null : classifyInline(m);
    }

    test('an atom reference is recognised, and carries its id and alt', () {
      final c = classify('see ![3x2 table](onote://atom/0198abcd-7b1e) here')!;
      expect(c.kind, MdInline.atom);
      expect(c.inner, '3x2 table', reason: 'the alt text');
      expect(c.target, '0198abcd-7b1e', reason: 'the id the payload is under');
    });

    test('an empty alt is allowed', () {
      final c = classify('![](onote://atom/abc123)')!;
      expect(c.kind, MdInline.atom);
      expect(c.inner, '');
      expect(c.target, 'abc123');
    });

    test('markers bracket the alt exactly, so coverage holds', () {
      // The live editor re-emits marker + inner + marker as substrings of the
      // source and checks they concatenate back. If openLen/closeLen do not
      // bracket `inner`, that check trips and the whole block silently falls
      // back to unstyled text.
      const src = '![3x2 table](onote://atom/0198abcd-7b1e)';
      final m = mdInlineRe.firstMatch(src)!;
      final c = classifyInline(m);
      final full = src.substring(m.start, m.end);
      expect(full.substring(c.openLen, c.openLen + c.inner.length), c.inner);
    });

    test('an ordinary picture is NOT an atom', () {
      // The two dialects share a shape; only the scheme tells them apart, and
      // a picture must keep going through the image path.
      final c = classify('![](sha256:abc)');
      expect(c?.kind, isNot(MdInline.atom));
    });

    test('a page link is not an atom either', () {
      final c = classify('[Week 3](onote://page/0198abcd)');
      expect(c?.kind, isNot(MdInline.atom),
          reason: 'no leading !, so it is a link — the scheme is shared');
    });

    test('two atoms in one sentence are both found', () {
      const s = 'a ![x](onote://atom/aaa) b ![y](onote://atom/bbb) c';
      expect(InlineAtom.idsIn(s), ['aaa', 'bbb']);
    });

    test('a reference built by the model is one the grammar reads back', () {
      const atom =
          InlineAtom(id: '0198abcd-7b1e', type: 'table', content: {});
      final ref = atom.reference('3x2 table');
      final c = classify(ref)!;
      expect(c.kind, MdInline.atom);
      expect(c.target, atom.id);
      expect(InlineAtom.idsIn(ref), [atom.id]);
    });
  });

  group('the payload rides in the block', () {
    test('put, read back, unchanged', () {
      final content = <String, dynamic>{'text': 'hi'};
      const atom = InlineAtom(
          id: 'a1', type: 'table', content: {'cells': [['x']]});
      InlineAtom.putIn(content, atom);

      final back = InlineAtom.allIn(content);
      expect(back.keys, ['a1']);
      expect(back['a1']!.type, 'table');
      expect(back['a1']!.content['cells'], [['x']]);
    });

    test('an atom of a type this build never heard of survives', () {
      // A newer device's notebook is not a corrupt one. Reading it must not
      // drop the payload, or syncing back would delete their work.
      final content = <String, dynamic>{
        'text': '![?](onote://atom/z9)',
        'atoms': {
          'z9': {'id': 'z9', 'type': 'hologram', 'content': {'spin': 3}}
        }
      };
      final back = InlineAtom.allIn(content);
      expect(back['z9']!.type, 'hologram');
      expect(back['z9']!.content['spin'], 3);
    });

    test('rubbish in the atoms map is ignored, not thrown on', () {
      final content = <String, dynamic>{
        'atoms': {
          'ok': {'id': 'ok', 'type': 'table', 'content': {}},
          'bad1': 'not a map',
          'bad2': {'type': 'table'}, // no id
          'bad3': {'id': '', 'type': 'table'}, // empty id
        }
      };
      expect(InlineAtom.allIn(content).keys, ['ok']);
    });

    test('deleting the reference prunes the payload', () {
      final content = <String, dynamic>{'text': 'gone now'};
      InlineAtom.putIn(
          content, const InlineAtom(id: 'a1', type: 'table', content: {}));
      InlineAtom.pruneTo(content, content['text'] as String);
      expect(content.containsKey('atoms'), isFalse,
          reason: 'an orphan payload would be invisible, exported, synced and '
              'counted against the size of the note for ever');
    });

    test('pruning keeps the ones still referenced', () {
      final content = <String, dynamic>{
        'text': 'keep ![k](onote://atom/keep) only'
      };
      InlineAtom.putIn(
          content, const InlineAtom(id: 'keep', type: 'table', content: {}));
      InlineAtom.putIn(
          content, const InlineAtom(id: 'drop', type: 'table', content: {}));
      InlineAtom.pruneTo(content, content['text'] as String);
      expect(InlineAtom.allIn(content).keys, ['keep']);
    });
  });

  group('reading a table, whatever it was stored as', () {
    test('plain strings come back as they are', () {
      final t = TableData.from({
        'cells': [
          ['a', 'b'],
          ['c', 'd']
        ]
      });
      expect(t.cells, [
        ['a', 'b'],
        ['c', 'd']
      ]);
      expect(t.rows, 2);
      expect(t.cols, 2);
    });

    test('numbers, bools and nulls become the text they always displayed as',
        () {
      // A CSV import writes real numbers; the editor has always shown them
      // through `toString()`. A conversion that wrote `42.0` where the user
      // had been reading `42` would be a visible change to their table.
      final t = TableData.from({
        'cells': [
          [1, 2.5, true],
          [null, 'x', -0]
        ]
      });
      expect(t.cells, [
        ['1', '2.5', 'true'],
        ['', 'x', '0']
      ]);
    });

    test('a jagged grid is padded to a rectangle, never truncated', () {
      final t = TableData.from({
        'cells': [
          ['a'],
          ['b', 'c', 'd'],
          <dynamic>[]
        ]
      });
      expect(t.cells, [
        ['a', '', ''],
        ['b', 'c', 'd'],
        ['', '', '']
      ]);
      expect(t.cols, 3, reason: 'the widest row decides, so nothing is lost');
    });

    test('a row that is not a list at all keeps its content', () {
      // Hand-edited JSON, or an importer that wrote a scalar. Dropping the
      // row would be losing data silently, which a converter may never do.
      final t = TableData.from({
        'cells': [
          'lonely',
          ['a', 'b']
        ]
      });
      expect(t.cells[0], ['lonely', '']);
      expect(t.cells[1], ['a', 'b']);
    });

    test('no cells at all gives the same empty table the editor shows', () {
      expect(TableData.from({}).cells, [
        ['', ''],
        ['', '']
      ]);
      expect(TableData.from({'cells': <dynamic>[]}).cells, hasLength(2));
      expect(TableData.from({'cells': 'nonsense'}).cells, hasLength(2));
    });

    test('dragged column widths survive, and absent ones do not invent', () {
      final t = TableData.from({
        'cells': [
          ['a', 'b']
        ],
        'colWidths': [0, 120.5]
      });
      expect(t.colWidths, [0.0, 120.5]);
      expect(TableData.from({'cells': [['a']]}).colWidths, isEmpty);
    });

    test('integer widths from an older file read as doubles', () {
      final t = TableData.from({
        'cells': [['a']],
        'colWidths': [0, 120] // ints, as JSON gives them
      });
      expect(t.colWidths, [0.0, 120.0]);
    });

    test('the alt text says what the thing is', () {
      final t = TableData.from({
        'cells': [
          ['a', 'b', 'c'],
          ['d', 'e', 'f']
        ]
      });
      expect(t.altText, '2x3 table');
    });
  });

  group('a table survives the round trip', () {
    test('content -> TableData -> content keeps every cell and width', () {
      final original = <String, dynamic>{
        'cells': [
          ['Name', 'Score'],
          ['Ada', 100],
          [null, true]
        ],
        'colWidths': [80, 0]
      };
      final there = TableData.from(original);
      final back = there.toContent();
      final again = TableData.from(back);

      expect(again.cells, there.cells,
          reason: 'a second conversion must be a no-op, or repeated saves '
              'would drift');
      expect(again.colWidths, there.colWidths);
      expect(back['cells'], [
        ['Name', 'Score'],
        ['Ada', '100'],
        ['', 'true']
      ]);
    });

    test('and through an atom payload as well', () {
      final table = TableData.from({
        'cells': [
          ['a', 1],
          ['b', null]
        ]
      });
      final content = <String, dynamic>{'text': ''};
      final atom = InlineAtom(
          id: 'tbl1', type: 'table', content: table.toContent());
      InlineAtom.putIn(content, atom);
      content['text'] = atom.reference(table.altText);

      final read = InlineAtom.allIn(content)['tbl1']!;
      expect(TableData.from(read.content).cells, [
        ['a', '1'],
        ['b', '']
      ]);
      expect(InlineAtom.idsIn(content['text'] as String), ['tbl1']);
    });
  });
}
