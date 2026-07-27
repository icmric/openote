// Table import (MEDIA-3 on the import side), driven through the real import
// pipeline with a synthesised parser payload — no binary fixture needed.
//
// Tables were not parsed at all before: OneNote stores them as
// table → row → cell containers, and because nothing recognised them their cell
// text was either flattened into loose paragraphs or, when the table hung off a
// container the outline walk never reached, lost entirely.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/export/onenote_import.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

/// One section containing one page whose only content is [boxes].
List<dynamic> _sections(List<Map<String, dynamic>> boxes) => [
      {
        'name': 'Logic',
        'section': {
          'pages': [
            {'title': 'Truth Tables', 'level': 0, 'boxes': boxes}
          ]
        }
      }
    ];

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Future<List<Block>> importAndRead(List<Map<String, dynamic>> boxes) async {
    final tmp = Directory.systemTemp.createTempSync('onote_tbl_');
    final repo = await Repository.openAt(tmp);
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final nb = await repo.createNotebook('Tables');
    final app = AppState(repo);
    await buildNotebookFromPackage(app, nb.id, _sections(boxes));
    final page = repo
        .loadNodes(nb.id)
        .firstWhere((n) => n.kind == NodeKind.page && n.title == 'Truth Tables');
    return repo.readPage(nb.id, page.id).blocks;
  }

  test('a parsed table becomes a table block with its cells intact', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final blocks = await importAndRead([
      {
        'kind': 'table',
        'x': 120.0,
        'y': 240.0,
        'cells': [
          ['P', 'Q', r'P $\land$ Q'],
          ['1', '1', '1'],
          ['1', '0', '0'],
        ],
      }
    ]);
    final table = blocks.singleWhere((b) => b.type == BlockType.table);
    expect(table.x, 120.0);
    expect(table.y, 240.0);
    final cells = table.content['cells'] as List;
    expect(cells.length, 3);
    expect((cells.first as List), ['P', 'Q', r'P $\land$ Q'],
        reason: 'cell markdown (including inline maths) is preserved verbatim');
    expect((cells[2] as List)[2], '0');
    // Width is seeded from the column count so culling and hit-testing have a
    // sane footprint even though the view lays out from content.
    expect(table.w, greaterThan(240.0));
  });

  test('a table sits alongside text on the same page, in order', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final blocks = await importAndRead([
      {
        'kind': 'text',
        'x': 60.0,
        'y': 136.0,
        'markdown': 'Truth table for conjunction:',
        'font_size_pt': 11.0,
      },
      {
        'kind': 'table',
        'x': 60.0,
        'y': 200.0,
        'cells': [
          ['P', 'Q'],
          ['1', '0'],
        ],
      },
    ]);
    expect(blocks.where((b) => b.type == BlockType.text).length, 1);
    expect(blocks.where((b) => b.type == BlockType.table).length, 1);
    final text = blocks.firstWhere((b) => b.type == BlockType.text);
    final table = blocks.firstWhere((b) => b.type == BlockType.table);
    expect(text.y, lessThan(table.y), reason: 'the table follows its intro');
    // The text box carries OneNote metrics and is pinned to its origin.
    expect(text.content['lineHeight'], oneNoteLineHeight);
    expect(text.content['inset'], 0);
  });

  test('OneNote column widths are preserved, not equalised', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // Real measured values: three equal narrow columns plus a wider one.
    final blocks = await importAndRead([
      {
        'kind': 'table',
        'x': 82.4,
        'y': 270.2,
        'col_w': [61.9, 61.9, 61.9, 64.5],
        'cells': [
          ['P', 'Q', 'R', 'result'],
          ['1', '1', '1', '1'],
        ],
      }
    ]);
    final t = blocks.singleWhere((b) => b.type == BlockType.table);
    expect(t.content['colWidths'], [61.9, 61.9, 61.9, 64.5]);
    expect(t.w, closeTo(250.2, 0.01),
        reason: 'the block footprint is the sum of the real columns — a guessed '
            'width is what made side-by-side tables overlap');
  });

  test('a column-width array that does not match the grid is ignored',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final blocks = await importAndRead([
      {
        'kind': 'table',
        'x': 0.0,
        'y': 0.0,
        'col_w': [61.9], // one width, three columns
        'cells': [
          ['a', 'b', 'c']
        ],
      }
    ]);
    final t = blocks.singleWhere((b) => b.type == BlockType.table);
    expect(t.content.containsKey('colWidths'), isFalse,
        reason: 'a partial array would stretch the wrong columns');
  });

  test('a degenerate table is skipped rather than creating an empty block',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final blocks = await importAndRead([
      {'kind': 'table', 'x': 0.0, 'y': 0.0, 'cells': <dynamic>[]},
    ]);
    expect(blocks.where((b) => b.type == BlockType.table), isEmpty);
  });
}
