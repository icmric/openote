// **A table in a paragraph, through everything that will happen to it.**
//
// `inline_table_test.dart` proves the widget behaves. This file asks the next
// question, which is the one that decides whether the feature is safe to ship:
// does a table survive being SAVED, being SYNCED, being undone, being copied,
// being one of two in the same paragraph, and being converted by a background
// pass nobody watched?
//
// Every one of those is a path where a table could quietly become an empty box
// on somebody's second device and nothing would say so until they looked.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/inline_atom.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/sync/materializer.dart';
import 'package:openote/sync/op_log.dart';
import 'package:openote/sync/op.dart';

import 'support/sqlite.dart';

/// A paragraph carrying one table, with prose either side of it.
Block paragraphWithTable({
  String id = 'blk1',
  String atomId = 'tbl1',
  List<List<String>> cells = const [
    ['Element', 'Symbol'],
    ['Sodium', 'Na'],
  ],
}) {
  final atom = InlineAtom(
      id: atomId,
      type: 'table',
      content: TableData(cells: [
        for (final r in cells) [...r]
      ], colWidths: const []).toContent());
  final content = <String, dynamic>{
    'text': 'Results: ${atom.reference('2x2 table')} and it holds.',
  };
  InlineAtom.putIn(content, atom);
  return Block(id: id, type: BlockType.text, x: 10, y: 20, w: 480,
      content: content);
}

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;
  late String nb;
  late String pageId;

  Future<void> open({bool syncLog = false}) async {
    AppState.syncLogEnabled = syncLog;
    tmp = Directory.systemTemp.createTempSync('onote_tbllife_');
    repo = await Repository.openAt(tmp);
    final ref = await repo.createNotebook('T');
    nb = ref.id;
    app = AppState(repo)
      ..notebookId = nb
      ..spellCheckEnabled = false;
    app.reloadNodes();
    pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
    await app.selectPage(pageId);
  }

  tearDown(() async {
    AppState.syncLogEnabled = true;
    if (!haveSqlite) return;
    app.cancelPendingSave();
    await app.settleBackgroundWork();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('it survives being saved', () {
    test('and read back out of the container, cell for cell', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await open();
      app.blocks = [paragraphWithTable()];
      app.markDirty();
      await app.flushSave();

      final back = repo.readPage(nb, pageId).blocks.single;
      expect(back.type, BlockType.text);
      expect(tablesIn(back.content).single.cells, [
        ['Element', 'Symbol'],
        ['Sodium', 'Na'],
      ]);
      expect(back.content['text'], contains('onote://atom/tbl1'),
          reason: 'the reference and the payload are saved together or not '
              'at all — either alone is a table nobody can see');
    });

    test('and a cell edited afterwards is what comes back', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await open();
      final b = paragraphWithTable();
      app.blocks = [b];
      app.markDirty();
      await app.flushSave();

      // Exactly what the table widget's write path does.
      final table = tablesIn(b.content).single.withCell(1, 1, 'Na⁺');
      InlineAtom.putIn(
          b.content,
          InlineAtom(
              id: 'tbl1', type: 'table', content: table.toContent()));
      b.updatedAt = nowMs() + 1;
      app.markDirty();
      await app.flushSave();

      expect(tablesIn(repo.readPage(nb, pageId).blocks.single.content)
          .single.cells[1][1], 'Na⁺');
    });
  });

  group('it survives being synced', () {
    /// The page as the operation log ALONE says it is — which is what every
    /// other device will rebuild from.
    Map<String, dynamic> fromLog() {
      final ref = repo.notebooks.firstWhere((n) => n.id == nb);
      final m = Materializer()
        ..applyAll(OpLogStore.forNotebook(ref.file).readAll());
      expect(m.unsupported, isEmpty,
          reason: 'this build writes only envelopes it can read back');
      return m.pageMirror(pageId);
    }

    List<Op> ops() {
      final ref = repo.notebooks.firstWhere((n) => n.id == nb);
      return OpLogStore.forNotebook(ref.file).readAll().toList();
    }

    test('the log alone rebuilds the whole table', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await open(syncLog: true);
      app.blocks = [paragraphWithTable()];
      app.markDirty();
      await app.flushSave();

      final page = fromLog();
      final blocks = (page['blocks'] as List).cast<Map<String, dynamic>>();
      final content = (blocks.single['content'] as Map).cast<String, dynamic>();
      expect(tablesIn(content).single.cells, [
        ['Element', 'Symbol'],
        ['Sodium', 'Na'],
      ]);
    });

    test('a CELL edit is recorded as a whole block, never as a text patch',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The sharp edge. A paragraph edited at one point is recorded as a
      // splice into `content.text`, which is most of what made v1.0.0's
      // history stop repeating itself — and a cell edit does not touch
      // `text` at all. If the diff ever decided a cell edit was a text patch,
      // the change would reach other devices as a no-op and the table would
      // silently revert on every one of them.
      await open(syncLog: true);
      final b = paragraphWithTable();
      app.blocks = [b];
      app.markDirty();
      await app.flushSave();
      final before = ops().length;

      final table = tablesIn(b.content).single.withCell(0, 0, 'Symbol!');
      InlineAtom.putIn(b.content,
          InlineAtom(id: 'tbl1', type: 'table', content: table.toContent()));
      b.updatedAt = nowMs() + 1;
      app.markDirty();
      await app.flushSave();

      final added = ops().skip(before).toList();
      expect(added, isNotEmpty, reason: 'the edit has to be recorded at all');
      expect(added.map((o) => o.kind), everyElement(isNot(OpKind.blockPatch)));
      final page = fromLog();
      final blocks = (page['blocks'] as List).cast<Map<String, dynamic>>();
      expect(
          tablesIn((blocks.single['content'] as Map).cast<String, dynamic>())
              .single
              .cells
              .first
              .first,
          'Symbol!',
          reason: 'and the other device rebuilds the edit, not the old cell');
    });

    test('the conversion itself reaches the log', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await open(syncLog: true);
      app.blocks = [
        Block(id: 'old', type: BlockType.table, x: 0, y: 0, content: {
          'cells': [
            ['a', 'b']
          ]
        })
      ];
      app.markDirty();
      await app.flushSave();

      expect(app.convertOpenPageTables(), 1);
      await app.flushSave();

      final page = fromLog();
      final blocks = (page['blocks'] as List).cast<Map<String, dynamic>>();
      expect(blocks.single['type'], 'text',
          reason: 'a conversion another device never hears about is exactly '
              'the staggered mess this was meant to avoid');
      expect(
          tablesIn((blocks.single['content'] as Map).cast<String, dynamic>()),
          hasLength(1));
    });
  });

  group('undo', () {
    test('puts a cell back', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await open();
      final b = paragraphWithTable();
      app.blocks = [b];

      // The write path: one undo step, then the edit.
      app.pushUndo();
      InlineAtom.putIn(
          b.content,
          InlineAtom(
              id: 'tbl1',
              type: 'table',
              content: tablesIn(b.content)
                  .single
                  .withCell(1, 0, 'Potassium')
                  .toContent()));
      app.markDirty();
      expect(tablesIn(app.blocks.single.content).single.cells[1][0],
          'Potassium');

      app.undo();
      expect(tablesIn(app.blocks.single.content).single.cells[1][0], 'Sodium');
      app.redo();
      expect(tablesIn(app.blocks.single.content).single.cells[1][0],
          'Potassium');
    });

    test('puts a whole row back', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await open();
      final b = paragraphWithTable();
      app.blocks = [b];
      app.pushUndo();
      InlineAtom.putIn(
          b.content,
          InlineAtom(
              id: 'tbl1',
              type: 'table',
              content:
                  tablesIn(b.content).single.insertRow(1).toContent()));
      app.markDirty();
      expect(tablesIn(app.blocks.single.content).single.rows, 3);

      app.undo();
      expect(tablesIn(app.blocks.single.content).single.rows, 2);
    });
  });

  group('living on a page', () {
    test('a copied block brings its table with it', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await open();
      app.blocks = [paragraphWithTable()];
      app.select('blk1');
      app.copySelectedBlocks();

      // The clipboard is the block's own JSON — the payload rides in it.
      final copied = (jsonDecode(app.debugBlockClipboard!) as List)
          .cast<Map<String, dynamic>>();
      final content = (copied.single['content'] as Map).cast<String, dynamic>();
      expect(tablesIn(content).single.cells, [
        ['Element', 'Symbol'],
        ['Sodium', 'Na'],
      ]);
    });

    test('two tables in one paragraph stay two tables', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await open();
      final a = InlineAtom(id: 'one', type: 'table', content: {
        'cells': [
          ['first']
        ]
      });
      final b = InlineAtom(id: 'two', type: 'table', content: {
        'cells': [
          ['second']
        ]
      });
      final content = <String, dynamic>{
        'text': '${a.reference('1x1 table')}\nand\n${b.reference('1x1 table')}'
      };
      InlineAtom.putIn(content, a);
      InlineAtom.putIn(content, b);
      app.blocks = [
        Block(id: 'two-tables', type: BlockType.text, x: 0, y: 0,
            content: content)
      ];
      app.markDirty();
      await app.flushSave();

      final back = repo.readPage(nb, pageId).blocks.single;
      expect([for (final t in tablesIn(back.content)) t.cells.first.first],
          ['first', 'second'],
          reason: 'in the order they appear, each with its own payload');
    });

    test('deleting the paragraph takes the payload with it', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await open();
      app.blocks = [paragraphWithTable()];
      app.markDirty();
      await app.flushSave();
      app.removeBlock('blk1');
      await app.flushSave();
      expect(repo.readPage(nb, pageId).blocks, isEmpty,
          reason: 'no orphan payload left in the page, and nothing to sync');
    });
  });

  group('find and replace', () {
    // **The page-wide, one-click, undo-once operation** — which makes it the
    // shape of thing that must not be able to break a reference. Replacing
    // "o" with "0" across a page would otherwise rewrite `onote://atom/<id>`
    // in every paragraph carrying a table and strand every payload behind it.
    //
    // There was no test for find or replace at all before this; the table
    // work is what made one necessary, because a table used to be a block
    // type both of them skipped.

    test('finds a word in a cell, which it never could before', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await open();
      app.blocks = [paragraphWithTable()];
      app.setFindQuery('sodium');
      expect(app.findMatches, ['blk1']);
    });

    test('and does not match the machinery that holds the table', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await open();
      app.blocks = [paragraphWithTable()];
      for (final noise in ['onote', 'atom', 'tbl1']) {
        app.setFindQuery(noise);
        expect(app.findMatches, isEmpty,
            reason: 'nobody typed "$noise"; it is a reference, not writing');
      }
    });

    test('Replace All cannot break a reference', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await open();
      app.blocks = [paragraphWithTable()];
      app.setFindQuery('o');
      final n = app.replaceAll('o', '0');

      expect(n, greaterThan(0), reason: 'it did do the replacement');
      expect(tablesIn(app.blocks.single.content), hasLength(1),
          reason: 'and the table is still there afterwards — the reference '
              'and its payload still agree');
      expect(app.blocks.single.content['text'],
          contains('onote://atom/tbl1'),
          reason: 'the reference is left exactly as it was, letter for '
              'letter, however many o-shaped characters are in it');
      app.cancelPendingSave();
    });

    test('Replace All does reach the cells', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await open();
      app.blocks = [paragraphWithTable()];
      app.setFindQuery('Sodium');
      expect(app.replaceAll('Sodium', 'Potassium'), 1);
      expect(tablesIn(app.blocks.single.content).single.cells[1][0],
          'Potassium',
          reason: 'a table was a block type replace skipped entirely; in a '
              'paragraph it is part of what the paragraph says');
      app.cancelPendingSave();
    });

    test('and still replaces ordinary prose', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await open();
      app.blocks = [
        Block(id: 'p', type: BlockType.text, x: 0, y: 0,
            content: {'text': 'one two one two'})
      ];
      app.setFindQuery('one');
      expect(app.replaceAll('one', 'three'), 2);
      expect(app.blocks.single.content['text'], 'three two three two');
      app.cancelPendingSave();
    });

    test('and undo puts the whole page back', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await open();
      app.blocks = [paragraphWithTable()];
      app.setFindQuery('Sodium');
      app.replaceAll('Sodium', 'Potassium');
      app.undo();
      expect(tablesIn(app.blocks.single.content).single.cells[1][0], 'Sodium');
      app.cancelPendingSave();
    });
  });

  group('the background pass', () {
    test('housekeeping converts the tables it finds', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await open();
      // A second page, holding a table, that nobody is looking at.
      final had = {for (final n in app.nodes) n.id};
      await app.addPage();
      app.reloadNodes();
      final other = app.nodes
          .firstWhere((n) => !had.contains(n.id) && n.kind == NodeKind.page)
          .id;
      await app.selectPage(other);
      app.blocks = [
        Block(type: BlockType.table, x: 0, y: 0, content: {
          'cells': [
            ['Unit', 'Mark']
          ]
        })
      ];
      app.markDirty();
      await app.flushSave();
      await app.selectPage(pageId);

      await app.runHousekeepingForTest(nb);

      final data = repo.readPage(nb, other);
      expect(data.blocks.single.type, BlockType.text,
          reason: 'the pass that nobody has to know about is the one that '
              'gets the whole notebook converted');
      expect(tablesIn(data.blocks.single.content).single.cells, [
        ['Unit', 'Mark']
      ]);
    });

    test('and stands aside while there are unsaved edits', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await open();
      final had = {for (final n in app.nodes) n.id};
      await app.addPage();
      app.reloadNodes();
      final other = app.nodes
          .firstWhere((n) => !had.contains(n.id) && n.kind == NodeKind.page)
          .id;
      await app.selectPage(other);
      app.blocks = [
        Block(type: BlockType.table, x: 0, y: 0, content: {
          'cells': [
            ['a']
          ]
        })
      ];
      app.markDirty();
      await app.flushSave();
      await app.selectPage(pageId);

      // Somebody is mid-sentence.
      app.blocks = [
        Block(type: BlockType.text, x: 0, y: 0, content: {'text': 'typing'})
      ];
      app.markDirty();
      await app.runHousekeepingForTest(nb);

      expect(repo.readPage(nb, other).blocks.single.type, BlockType.table,
          reason: 'busy is a deferral, not a verdict — it comes back when the '
              'typing stops');
      app.cancelPendingSave();
    });
  });
}
