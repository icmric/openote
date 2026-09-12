// **Everything that enumerates tables can still find one inside a paragraph.**
//
// Six surfaces used to ask the same question — `blocks.where(type == table)` —
// and a table that moved into a text block would have vanished from every one
// of them: out of the Markdown export, out of the open-folder export, out of
// the JSON Canvas, off the printed page, out of the word count, out of the
// list a SQL cell can query. Not drawn wrong; GONE, quietly, from a file
// somebody had already trusted.
//
// So this file tests the loss, not the feature. Each test puts one table in a
// paragraph and asserts its CELLS come out the far end. They all go through
// `tablesIn` / `expandAtoms`, which is the point of those existing at all:
// one answer to "what tables are in here", so that a seventh surface is one
// call rather than a seventh copy of the question.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/export/markdown_export.dart';
import 'package:openote/export/md_common.dart';
import 'package:openote/model/inline_atom.dart';
import 'package:openote/model/models.dart';
import 'package:openote/model/page_stats.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

/// A paragraph with a table in the middle of it.
Map<String, dynamic> paragraphWithTable({
  String before = 'Results: ',
  String after = ' and it holds.',
  List<List<String>> cells = const [
    ['Element', 'Symbol'],
    ['Sodium', 'Na'],
  ],
}) {
  const atom = InlineAtom(id: 'tbl1', type: 'table', content: {});
  final content = <String, dynamic>{
    'text': '$before${atom.reference('2x2 table')}$after',
  };
  InlineAtom.putIn(
      content,
      InlineAtom(
          id: 'tbl1',
          type: 'table',
          content: TableData(cells: [
            for (final r in cells) [...r]
          ], colWidths: const []).toContent()));
  return content;
}

void main() {
  group('the model answers once, for everybody', () {
    test('tablesIn finds the table in a paragraph', () {
      final tables = tablesIn(paragraphWithTable());
      expect(tables, hasLength(1));
      expect(tables.single.cells, [
        ['Element', 'Symbol'],
        ['Sodium', 'Na'],
      ]);
    });

    test('and finds two, in the order they appear', () {
      final content = <String, dynamic>{
        'text': 'a ![](onote://atom/t2) b ![](onote://atom/t1) c'
      };
      InlineAtom.putIn(
          content,
          const InlineAtom(id: 't1', type: 'table', content: {
            'cells': [
              ['one']
            ]
          }));
      InlineAtom.putIn(
          content,
          const InlineAtom(id: 't2', type: 'table', content: {
            'cells': [
              ['two']
            ]
          }));
      expect([for (final t in tablesIn(content)) t.cells.first.first],
          ['two', 'one'],
          reason: 'reading order, not storage order — t1…tn in a SQL cell '
              'must mean what it looks like it means');
    });

    test('a paragraph with no atoms costs one substring test', () {
      expect(tablesIn({'text': 'just words'}), isEmpty);
      expect(tablesIn(const {}), isEmpty);
    });

    test('an atom of another type is not a table', () {
      final content = <String, dynamic>{'text': '![](onote://atom/h1)'};
      InlineAtom.putIn(content,
          const InlineAtom(id: 'h1', type: 'hologram', content: {}));
      expect(tablesIn(content), isEmpty);
    });
  });

  group('the Markdown projection', () {
    test('a table in a paragraph exports as a GFM table', () {
      final content = paragraphWithTable();
      final md = expandAtoms(content['text'] as String, content);
      expect(md, contains('| Element | Symbol |'));
      expect(md, contains('| Sodium | Na |'));
      expect(md, isNot(contains('onote://atom')),
          reason: 'a reader of the .md has no idea what an atom is');
    });

    test('the words around it survive, on their own lines', () {
      final content = paragraphWithTable();
      final md = expandAtoms(content['text'] as String, content);
      expect(md, startsWith('Results: '));
      expect(md, endsWith(' and it holds.'));
      // A GFM table is a block construct: written into the middle of a
      // sentence it is not a table at all, just pipes.
      expect(md, contains('\n\n| Element'));
    });

    test('an atom this build cannot project keeps its reference', () {
      final content = <String, dynamic>{'text': 'see ![a hologram](onote://atom/h1)'};
      InlineAtom.putIn(content,
          const InlineAtom(id: 'h1', type: 'hologram', content: {}));
      final md = expandAtoms(content['text'] as String, content);
      expect(md, contains('![a hologram](onote://atom/h1)'),
          reason: 'valid CommonMark, so a foreign reader shows the alt text '
              'rather than a syntax error — and a re-import still has the id');
    });

    test('text with no atoms is returned unchanged, identically', () {
      const plain = 'nothing to see here';
      expect(expandAtoms(plain, const {}), same(plain));
    });
  });

  group('the word count', () {
    test('counts the words in the cells', () {
      final withTable = pageStats([
        Block(type: BlockType.text, x: 0, y: 0, content: paragraphWithTable())
      ]);
      final without = pageStats([
        Block(
            type: BlockType.text,
            x: 0,
            y: 0,
            content: {'text': 'Results:  and it holds.'})
      ]);
      expect(withTable.words, greaterThan(without.words),
          reason: 'four words of table are four words on the page; they used '
              'to disappear from the count the moment the table stopped '
              'being a block of its own');
    });

    test('but the paragraph is still ONE block', () {
      final stats = pageStats([
        Block(type: BlockType.text, x: 0, y: 0, content: paragraphWithTable())
      ]);
      expect(stats.blocks, 1,
          reason: 'a paragraph with a table in it is one thing you wrote');
    });

    test('and the alt text is not counted as words somebody typed', () {
      // "2x2 table" is a description this build wrote, not writing.
      final stats = pageStats([
        Block(type: BlockType.text, x: 0, y: 0, content: {
          'text': 'x ![2x2 table](onote://atom/none)',
        })
      ]);
      expect(stats.words, 1);
    });
  });

  group('the exported page', () {
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());

    late Directory tmp;
    late Repository repo;
    late AppState app;

    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_atomexport_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('T');
      app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
    });

    tearDown(() {
      AppState.syncLogEnabled = true;
      if (!haveSqlite) return;
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('carries the table, not the URL that stands for it', () {
      if (!haveSqlite) return;
      final md = pageMarkdownOf(app, 'Chemistry', [
        Block(
            type: BlockType.text,
            x: 0,
            y: 0,
            w: 400,
            content: paragraphWithTable()),
      ]);
      expect(md, contains('| Element | Symbol |'));
      expect(md, contains('| Sodium | Na |'));
      expect(md, isNot(contains('onote://atom')));
    });

    test('a table block still exports exactly as it always did', () {
      if (!haveSqlite) return;
      // The other half of backwards compatibility: converting is a choice,
      // and a notebook that has not been converted must be untouched.
      final md = pageMarkdownOf(app, 'Chemistry', [
        Block(type: BlockType.table, x: 0, y: 0, w: 400, content: {
          'cells': [
            ['Element', 'Symbol'],
            ['Sodium', 'Na'],
          ]
        }),
      ]);
      expect(md, contains('| Element | Symbol |'));
      expect(md, contains('| Sodium | Na |'));
    });
  });
}
