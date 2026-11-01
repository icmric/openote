// The pure halves of the MCP write tools (docs/specs/14): Markdown → native
// blocks, the height estimate every "below the last box" layout stacks on,
// and the content check that refuses a block nothing would draw.
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/markdown/md_blocks.dart';
import 'package:openote/model/block_metrics.dart';
import 'package:openote/model/block_schema.dart';
import 'package:openote/model/inline_atom.dart';
import 'package:openote/model/models.dart';

void main() {
  group('markdownToBlocks', () {
    const md = '# Notes\n'
        'Intro line.\n'
        '\n'
        '```py\n'
        'def f(x):\n'
        '    return x | 1\n'
        '```\n'
        '\n'
        '| Term | Meaning |\n'
        '|---|---|\n'
        '| ATP | energy |\n'
        '| DNA | code |\n'
        '\n'
        'After the table.';

    test('fences become code blocks, language through the alias table', () {
      final blocks = markdownToBlocks(md, madeIn: 'test');
      expect([for (final b in blocks) b.type],
          [BlockType.text, BlockType.code, BlockType.text]);
      final code = blocks[1];
      expect(code.content['source'], 'def f(x):\n    return x | 1');
      expect(code.content['language'], 'python', reason: '```py is python');
      expect(blocks.first.content['text'], '# Notes\nIntro line.');
    });

    test('a GFM table becomes an inline table atom, not raw pipes', () {
      final text = markdownToBlocks(md, madeIn: 'test').last;
      final t = text.content['text'] as String;
      expect(t, isNot(contains('|---|')));
      expect(t, contains('onote://atom/'));
      expect(t, endsWith('After the table.'));
      final tables = tablesIn(text.content);
      expect(tables, hasLength(1));
      expect(tables.single.cells, [
        ['Term', 'Meaning'],
        ['ATP', 'energy'],
        ['DNA', 'code'],
      ]);
      expect(checkBlockContent(text).errors, isEmpty);
    });

    test('an unknown fence language lands as plain text', () {
      final b = markdownToBlocks('```mermaid\ngraph TD\n```', madeIn: 't');
      expect(b.single.content['language'], 'text');
    });

    test('an unclosed fence runs to the end, as in CommonMark', () {
      final b = markdownToBlocks('para\n```js\nlet a = 1', madeIn: 't');
      expect(b.map((b) => b.type), [BlockType.text, BlockType.code]);
      expect(b.last.content['source'], 'let a = 1');
      expect(b.last.content['language'], 'js');
    });
  });

  test('atomizePipeTables leaves pipes inside fenced code alone', () {
    const text = '```\n| a | b |\n|---|---|\n```\n| x | y |\n|---|---|\n| 1 | 2 |';
    final r = atomizePipeTables(text, madeIn: 't');
    expect(r.atoms, hasLength(1));
    expect(r.text, startsWith('```\n| a | b |\n|---|---|\n```\n'));
    expect(r.atoms.single.content['cells'], [
      ['x', 'y'],
      ['1', '2'],
    ]);
  });

  group('estimateBlockHeight', () {
    test('code grows with its lines — not a flat 60px', () {
      final b = Block(type: BlockType.code, x: 0, y: 0, w: 640, content: {
        'source': List.generate(30, (i) => 'line $i').join('\n'),
      });
      expect(estimateBlockHeight(b), 30 * kCodeLineHeight + kCodeChrome);
    });

    test('an inline table counts its rows, not one line of text', () {
      final rows = [
        for (var i = 0; i < 12; i++) ['row $i', 'value $i']
      ];
      final atom = InlineAtom(
          id: 'a1', type: 'table', content: {'cells': rows});
      final content = <String, dynamic>{
        'text': 'Before\n${atom.reference(TableData.referenceAlt)}\nAfter'
      };
      InlineAtom.putIn(content, atom);
      final withTable =
          Block(type: BlockType.text, x: 0, y: 0, w: 640, content: content);
      final plain = Block(
          type: BlockType.text,
          x: 0,
          y: 0,
          w: 640,
          content: {'text': 'Before\nx\nAfter'});
      expect(estimateBlockHeight(withTable) - estimateBlockHeight(plain),
          greaterThan(12 * 24 - 30),
          reason: '12 rows at the 24px row floor, minus the line it replaced');
    });

    test('headings are taller than body lines', () {
      Block t(String s) =>
          Block(type: BlockType.text, x: 0, y: 0, w: 640, content: {'text': s});
      expect(estimateBlockHeight(t('# A\n# B\n# C')),
          greaterThan(estimateBlockHeight(t('A\nB\nC'))));
    });

    test('a table block counts its rows', () {
      final b = Block(type: BlockType.table, x: 0, y: 0, w: 400, content: {
        'cells': [
          for (var i = 0; i < 10; i++) ['a', 'b']
        ]
      });
      expect(estimateBlockHeight(b), greaterThan(10 * 24));
    });
  });

  group('checkBlockContent', () {
    Block block(String type, Map<String, dynamic> content) =>
        Block.fromJson({'id': 'b', 'type': type, 'content': content});

    test('a code block under the wrong key is an error that names the key',
        () {
      final r = checkBlockContent(block('code', {'code': 'print(1)'}));
      expect(r.errors.single, contains('content.source'));
      expect(r.errors.single, contains('content.code'));
    });

    test('a missing required key is an error', () {
      expect(checkBlockContent(block('flashcard', {'front': 'q'})).errors,
          isNotEmpty);
    });

    test('a wrong-kind value is an error', () {
      expect(checkBlockContent(block('code', {'source': 3})).errors,
          isNotEmpty);
    });

    test('an unknown key is a warning, never an error (forward compat)', () {
      final r = checkBlockContent(
          block('code', {'source': 'x', 'futureField': true}));
      expect(r.errors, isEmpty);
      expect(r.warnings.single, contains('futureField'));
    });

    test('a type with no schema is not checked', () {
      final r = checkBlockContent(block('hologram', {'anything': 1}));
      expect(r.errors, isEmpty);
      expect(r.warnings, isEmpty);
    });

    // The shapes Data Model Spec §4 and the file format changelog (v1.0.2)
    // name, checked against what the app itself writes.
    test('an image is a picture OR a page of a PDF; neither is an error', () {
      expect(
          checkBlockContent(block('image', {'blob': 'sha256:a', 'mime': 'x'}))
              .errors,
          isEmpty);
      final pdf = checkBlockContent(block('image', {
        'pdf': 'sha256:b',
        'page': 0,
        'mime': 'application/pdf',
        'naturalW': 595,
        'naturalH': 842,
        'locked': true,
        'background': true,
      }));
      expect(pdf.errors, isEmpty);
      expect(pdf.warnings, isEmpty, reason: 'pdf_import writes every key');
      expect(checkBlockContent(block('image', {'mime': 'x'})).errors,
          isNotEmpty);
    });

    test('substitute takes v1.0.2 values, and the legacy value beside it', () {
      final r = checkBlockContent(block('substitute', {
        'latex': 'y = 2x + 1',
        'values': {'x': '3'},
        'value': '3',
      }));
      expect(r.errors, isEmpty);
      expect(r.warnings, isEmpty);
    });

    test('a converted table\'s impliedColWidths is a known key', () {
      final r = checkBlockContent(block('table', {
        'cells': [
          ['a']
        ],
        'impliedColWidths': [120],
      }));
      expect(r.warnings, isEmpty);
    });

    test('a text atom reference with no payload is an error', () {
      final r = checkBlockContent(block('text', {
        'text': '![t](onote://atom/0198aaaa-0000-7000-8000-000000000001)'
      }));
      expect(r.errors, isNotEmpty);
    });
  });
}
