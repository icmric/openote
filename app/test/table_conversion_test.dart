// **Moving every table into the paragraph it belongs to, without losing one.**
//
// The owner asked for this to happen on its own — "lets just automatically
// update them all on open … so that we dont end up with a staggered mess of
// mix and match table types" — and then set the bar it has to clear:
// "ensure that no data will ever be lost or corupted permenantly by this
// process".
//
// That bar is what this file tests, and it is tested from the pessimistic
// side. A conversion that works on a tidy table proves very little; the tables
// in a real notebook came out of a OneNote import, a CSV, a hand-edited file
// and three years of use, so they hold numbers where strings are expected,
// nulls, ragged rows, dragged column widths and keys this build has never
// heard of. Every one of those is a case below, and the rule they all check is
// the same one: what comes out is exactly what went in, or nothing happens at
// all.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/inline_atom.dart';
import 'package:openote/model/models.dart';
import 'package:openote/model/table_conversion.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

Block tableBlock(Object? cells, {Map<String, dynamic> extra = const {}}) =>
    Block(
      id: 'tbl-block',
      type: BlockType.table,
      x: 12,
      y: 34,
      w: 480,
      h: 90,
      z: 3,
      content: {'cells': cells, ...extra},
    );

void main() {
  group('one table block, converted', () {
    test('becomes a paragraph carrying the same table', () {
      final out = tableBlockAsText(
          tableBlock([
            ['Element', 'Symbol'],
            ['Sodium', 'Na'],
          ]),
          madeIn: '1.1.0')!;

      expect(out.type, BlockType.text);
      expect(tablesIn(out.content).single.cells, [
        ['Element', 'Symbol'],
        ['Sodium', 'Na'],
      ]);
      expect(InlineAtom.idsIn(out.content['text'] as String), hasLength(1),
          reason: 'one reference, standing where the table is drawn');
    });

    test('keeps the block it was', () {
      final before = tableBlock([
        ['a']
      ]);
      final out = tableBlockAsText(before, madeIn: '1.1.0')!;
      // The id above all: selection, tags, links, the op log and page history
      // all key on it, and a new one would read as a delete and an insert to
      // every one of them.
      expect(out.id, before.id);
      expect([out.x, out.y, out.w, out.h, out.z],
          [before.x, before.y, before.w, before.h, before.z]);
      expect(out.createdAt, before.createdAt);
    });

    test('says which version made it', () {
      final out = tableBlockAsText(
          tableBlock([
            ['a']
          ]),
          madeIn: '1.1.0')!;
      final atom = InlineAtom.allIn(out.content).values.single;
      expect(atom.content['madeIn'], '1.1.0',
          reason: 'so a build too old to draw it can say so, instead of '
              'showing a hole');
    });

    test('and tells an older build what to do about it', () {
      // The one channel to the owner's other machines. A build that has never
      // heard of an inline atom draws the reference as plain text, and
      // nothing here can change that — so the alt text has to carry the
      // instruction, not just the description.
      final out = tableBlockAsText(
          tableBlock([
            ['a', 'b']
          ]),
          madeIn: '1.1.0')!;
      expect(out.content['text'], contains('update Openote'));
      expect(out.content['text'], contains('1x2 table'),
          reason: 'and still says what the thing IS, for a screen reader and '
              'for any Markdown viewer that is not Openote at all');
    });

    test('a block that is not a table is not touched', () {
      final text = Block(
          type: BlockType.text, x: 0, y: 0, content: {'text': 'hello'});
      expect(tableBlockAsText(text, madeIn: '1.1.0'), isNull);
    });

    test('and converting is not something that can happen twice', () {
      final once = tableBlockAsText(
          tableBlock([
            ['a']
          ]),
          madeIn: '1.1.0')!;
      expect(tableBlockAsText(once, madeIn: '1.1.0'), isNull,
          reason: 'it is a text block now — a second pass must be a no-op, or '
              'a re-run would nest tables inside tables');
    });
  });

  group('everything a real table turns out to hold', () {
    ({List<List<String>> before, List<List<String>> after}) roundTrip(
        Object? cells) {
      final b = tableBlock(cells);
      final before = TableData.from(b.content).cells;
      final out = tableBlockAsText(b, madeIn: '1.1.0');
      return (before: before, after: out == null ? [] : tablesIn(out.content).single.cells);
    }

    test('numbers stay the text they were displayed as', () {
      // A CSV import writes real numbers and the editor has always shown them
      // through toString(). A conversion that wrote 42.0 where the user had
      // been reading 42 would be a visible change to their table.
      final r = roundTrip([
        [1, 2.5, true],
        [null, 'x', -0]
      ]);
      expect(r.after, r.before);
      expect(r.after, [
        ['1', '2.5', 'true'],
        ['', 'x', '0']
      ]);
    });

    test('a ragged grid is padded, never truncated', () {
      final r = roundTrip([
        ['a'],
        ['b', 'c', 'd'],
        <dynamic>[]
      ]);
      expect(r.after, r.before);
      expect(r.after.every((row) => row.length == 3), isTrue);
      expect(r.after[1], ['b', 'c', 'd'], reason: 'nothing dropped');
    });

    test('a row that is not a list at all keeps its content', () {
      final r = roundTrip([
        'lonely',
        ['a', 'b']
      ]);
      expect(r.after, r.before);
      expect(r.after.first.first, 'lonely');
    });

    test('cells nobody ever typed in survive as empty cells', () {
      final r = roundTrip([
        ['', ''],
        ['', '']
      ]);
      expect(r.after, r.before);
    });

    test('dragged column widths come across', () {
      final out = tableBlockAsText(
          tableBlock([
            ['a', 'b']
          ], extra: {
            'colWidths': [0, 260]
          }),
          madeIn: '1.1.0')!;
      expect(tablesIn(out.content).single.colWidths, [0.0, 260.0],
          reason: 'somebody dragged that column out; it is a choice, not a '
              'default');
    });

    test('a key this build does not understand is carried over, not dropped',
        () {
      // A newer build, a hand edit, a foreign writer. Dropping what we do not
      // understand is the one thing a converter may never do.
      final out = tableBlockAsText(
          tableBlock([
            ['a']
          ], extra: {'locked': true, 'someFutureThing': 42}),
          madeIn: '1.1.0')!;
      expect(out.content['locked'], isTrue);
      expect(out.content['someFutureThing'], 42);
    });

    test('a table block that somehow has text keeps the text ABOVE the table',
        () {
      final out = tableBlockAsText(
          tableBlock([
            ['a']
          ], extra: {'text': 'a note somebody left here'}),
          madeIn: '1.1.0')!;
      final text = out.content['text'] as String;
      expect(text, startsWith('a note somebody left here'),
          reason: 'overwriting it would be losing writing, silently');
      expect(tablesIn(out.content), hasLength(1));
    });

    test('a table with nothing in it converts to the empty table it drew', () {
      final out = tableBlockAsText(tableBlock(null), madeIn: '1.1.0')!;
      expect(tablesIn(out.content).single.cells, [
        ['', ''],
        ['', '']
      ]);
    });
  });

  group('in a real notebook', () {
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());

    late Directory tmp;
    late Repository repo;
    late AppState app;
    late String nb;

    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_tblconv_');
      repo = await Repository.openAt(tmp);
      final ref = await repo.createNotebook('T');
      nb = ref.id;
      app = AppState(repo)..notebookId = nb;
      app.reloadNodes();
      await app.selectPage(
          app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
    });

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

    test('the open page converts in memory, and is undoable', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.blocks = [
        tableBlock([
          ['Element', 'Symbol'],
          ['Sodium', 'Na'],
        ])
      ];
      final moved = app.convertOpenPageTables();

      expect(moved, 1);
      expect(app.blocks.single.type, BlockType.text);
      expect(tablesIn(app.blocks.single.content).single.cells.last,
          ['Sodium', 'Na']);

      // The way back. This is the one automatic path that rewrites something
      // the user already owns, so there has to be one.
      app.undo();
      expect(app.blocks.single.type, BlockType.table);
      expect(app.blocks.single.content['cells'], [
        ['Element', 'Symbol'],
        ['Sodium', 'Na'],
      ]);
    });

    test('a page with no tables is not rewritten at all', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.blocks = [
        Block(type: BlockType.text, x: 0, y: 0, content: {'text': 'words'})
      ];
      app.markDirty();
      await app.flushSave();
      expect(app.convertOpenPageTables(), 0);
      expect(app.hasUnsavedChanges, isFalse,
          reason: 'merely opening pages must not mark a notebook dirty');
    });

    test('nothing happens to a notebook this build may only read', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.blocks = [
        tableBlock([
          ['a']
        ])
      ];
      app.debugMarkReadOnly(nb);
      expect(app.convertOpenPageTables(), 0);
      expect(app.blocks.single.type, BlockType.table,
          reason: 'a notebook whose log is ahead of this build is shown, not '
              'changed — every op we appended would be a diff against a '
              'replay we cannot do');
    });

    test('the rest of the notebook converts in the background', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // A second page, with a table on it, that nobody is looking at.
      final had = {for (final n in app.nodes) n.id};
      await app.addPage();
      app.reloadNodes();
      final other =
          app.nodes.firstWhere((n) => !had.contains(n.id) && n.kind == NodeKind.page).id;
      await app.selectPage(other);
      app.blocks = [
        tableBlock([
          ['Unit', 'Mark'],
          ['Maths', '82'],
        ])
      ];
      app.markDirty();
      await app.flushSave();
      // Go back, so `other` is NOT the open page.
      await app.selectPage(
          app.nodes.firstWhere((n) => n.kind == NodeKind.page && n.id != other).id);

      final r = await app.convertTablesToInline(nb);
      expect(r.pages, 1);
      expect(r.tables, 1);
      expect(r.refused, 0);

      final data = repo.readPage(nb, other);
      expect(data.blocks.single.type, BlockType.text);
      expect(tablesIn(data.blocks.single.content).single.cells, [
        ['Unit', 'Mark'],
        ['Maths', '82'],
      ], reason: 'every cell, off the disk it was written to');
    });

    test('and running it again does nothing, however many times', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final had = {for (final n in app.nodes) n.id};
      await app.addPage();
      app.reloadNodes();
      final other = app.nodes
          .firstWhere((n) => !had.contains(n.id) && n.kind == NodeKind.page)
          .id;
      await app.selectPage(other);
      app.blocks = [
        tableBlock([
          ['a']
        ])
      ];
      app.markDirty();
      await app.flushSave();
      await app.selectPage(app.nodes
          .firstWhere((n) => n.kind == NodeKind.page && n.id != other)
          .id);

      await app.convertTablesToInline(nb);
      final again = await app.convertTablesToInline(nb);
      expect(again.didNothing, isTrue,
          reason: 'an interrupted run is resumed by simply running again, so '
              'it has to be safe to run at any time');
    });

    test('the page being looked at is left to the in-memory path', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.blocks = [
        tableBlock([
          ['a']
        ])
      ];
      app.markDirty();
      await app.flushSave();
      final r = await app.convertTablesToInline(nb);
      expect(r.didNothing, isTrue,
          reason: 'its editor is live and its blocks are held in memory; the '
              'walk must not rewrite the file underneath them');
    });
  });
}
