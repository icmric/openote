// A table inside a paragraph, on its way out of the app.
//
// The exporters all learned about atoms when tables moved into the text, and
// none of the export tests mention one — so the surface with the most ways to
// be subtly wrong is the one nothing was holding to account. What a reader
// outside Openote gets is the whole point of `page.md`: an atom that arrives
// as `![3x2 table](onote://atom/0198…)` is not a table, it is a broken image.

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/export/markdown_export.dart';
import 'package:openote/export/md_common.dart';
import 'package:openote/model/inline_atom.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

class _NoopRepo implements Repository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  const atom = InlineAtom(id: 't1', type: 'table', content: {
    'cells': [
      ['Element', 'Symbol'],
      ['Sodium', 'Na'],
    ]
  });

  Map<String, dynamic> paragraph(String text) {
    final c = <String, dynamic>{'text': text};
    InlineAtom.putIn(c, atom);
    return c;
  }

  group('page.md', () {
    test('a table in a sentence comes out as a real GFM table', () {
      final md = expandAtoms(
          'Results: ${atom.reference('2x2 table')} and it holds.',
          paragraph(''));

      expect(md, contains('| Element | Symbol |'),
          reason: 'a reader outside Openote has to get a table');
      expect(md, contains('| Sodium | Na |'));
      expect(md, isNot(contains('onote://atom/')),
          reason: 'the reference is machinery, not content');
      expect(md, contains('Results:'), reason: 'and the prose is still there');
      expect(md, contains('and it holds.'));
    });

    test('the table is on its own lines, or it is just pipes', () {
      // A GFM table is a block construct. Written into the middle of a
      // sentence it does not render as a table in ANY reader.
      final md = expandAtoms(
          'Before ${atom.reference('2x2 table')} after', paragraph(''));
      final lines = md.split('\n');
      final header = lines.indexWhere((l) => l.startsWith('| Element'));
      expect(header, greaterThan(0));
      expect(lines[header - 1].trim(), isEmpty,
          reason: 'a blank line above, or the paragraph swallows it');
    });

    test('an atom this build cannot draw keeps its reference verbatim', () {
      // Valid CommonMark, so a foreign reader shows the alt text instead of a
      // syntax error — and a re-import still has the id to match against.
      const future =
          InlineAtom(id: 'z9', type: 'sankey-diagram', content: {'v': 1});
      final c = <String, dynamic>{'text': ''};
      InlineAtom.putIn(c, future);
      final ref = future.reference('a diagram');
      expect(expandAtoms('See $ref.', c), 'See $ref.');
    });

    test('a reference whose payload is gone is left alone, not dropped', () {
      // Dropping it would silently delete the only record that something was
      // there; leaving it shows the alt text.
      final ref = atom.reference('2x2 table');
      expect(expandAtoms('Here: $ref', <String, dynamic>{'text': ''}),
          'Here: $ref');
    });

    test('a paragraph with no atoms is returned untouched', () {
      const plain = 'Nothing to see, not even a bracket.';
      expect(expandAtoms(plain, const {}), same(plain),
          reason: 'the fast path is one substring test');
    });
  });

  group('the whole page', () {
    test('exports the table, not the reference', () {
      final app = AppState(_NoopRepo())
        ..notebookId = 'nb'
        ..pageId = 'pg';
      final b = Block(
        type: BlockType.text,
        x: 0,
        y: 0,
        w: 400,
        content: paragraph('Results: ${atom.reference('2x2 table')}'),
      );
      app.blocks = [b];

      final md = pageMarkdownOf(app, 'Chemistry', [b]);
      expect(md, contains('| Element | Symbol |'));
      expect(md, isNot(contains('onote://atom/')));
    });

    test('and a table that is alone in its paragraph still exports', () {
      // What every converted table block looks like: the reference is the
      // whole of the text.
      final app = AppState(_NoopRepo())
        ..notebookId = 'nb'
        ..pageId = 'pg';
      final b = Block(
        type: BlockType.text,
        x: 0,
        y: 0,
        w: 400,
        content: paragraph(atom.reference('2x2 table')),
      );
      app.blocks = [b];

      final md = pageMarkdownOf(app, 'Chemistry', [b]);
      expect(md, contains('| Element | Symbol |'));
      expect(md, contains('| Sodium | Na |'));
    });
  });
}
