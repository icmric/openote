// v0.17 plan, Step 8a — "Who changed this, and what was deleted".
//
// The owner asked for something smaller and different from the 30-deep page
// snapshot table: *"Could we do a simplified version history? Dont need full
// complete edit history, but keeping track of who made what edits (that are
// currently visible and maybe recent deletions, like the last 10 noteable
// deletions)"*.
//
// The design's whole claim is that this is nearly free, because the log already
// carries it: every `Op` stamps `dev` and `ts`, `Op.compare` gives a
// deterministic total order, and each op names its target. **That claim is
// asserted here rather than argued** (matrix row B8): an index rebuilt from the
// log alone must equal the one maintained incrementally on save, or the premise
// is wrong and the feature is a store rather than a view.
//
// Every test names the mutation that turns it red, because a cell that cannot
// fail is not a cell (plan §5.1 rule 3).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:openote/model/history.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/sync/device_label.dart';
import 'package:openote/sync/op.dart';
import 'package:openote/sync/op_log.dart';
import 'package:openote/ui/page_history_dialog.dart';

import 'support/sqlite.dart';

/// Mints ops the way a device does: Lamport and seq both climbing, one writer
/// per log.
class _Writer {
  _Writer(this.device);
  final String device;
  int lamport = 0;
  int seq = 0;

  Op op(OpKind kind, Map<String, dynamic> data, {int? at}) {
    lamport = at ?? (lamport + 1);
    return Op(
      device: device,
      seq: ++seq,
      lamport: lamport,
      timestamp: 1700000000000 + lamport,
      kind: kind,
      data: data,
    );
  }

  Op setBlock(String page, String id, String type, Map<String, dynamic> content,
          {int? at}) =>
      op(
          OpKind.blockSet,
          {
            'pageId': page,
            'block': {'id': id, 'type': type, 'content': content},
          },
          at: at);

  Op removeBlock(String page, String id, {int? at}) =>
      op(OpKind.blockRemove, {'pageId': page, 'blockId': id}, at: at);

  Op node(String id, String kind, {String? parent, String title = ''}) =>
      op(OpKind.nodeUpsert,
          {'id': id, 'kind': kind, 'parentId': parent, 'title': title});
}

/// 280 characters of ordinary prose — the bar a text block has to clear.
final String _longText = 'x' * kNotableTextChars;

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  // ── The rules, folded in isolation ──────────────────────────────────

  group('what counts as notable', () {
    test('a picture, a file and a drawing are notable however small they are',
        () {
      final w = _Writer('dev-a');
      final h = NotebookHistory()
        ..apply(w.node('p1', 'page', title: 'Lecture'))
        ..apply(w.setBlock('p1', 'img', 'image', {'blob': 'sha256:aa'}))
        ..apply(w.setBlock('p1', 'doc', 'file', {'media': 'notes.pdf'}))
        ..apply(w.setBlock('p1', 'draw', 'ink', {
          'ink': {'n': 3, 'base': 'sha256:bb'}
        }))
        ..apply(w.removeBlock('p1', 'img'))
        ..apply(w.removeBlock('p1', 'doc'))
        ..apply(w.removeBlock('p1', 'draw'));
      // MUTATION: drop `pins.isNotEmpty ||` from `BlockAuthor.notableIfRemoved`
      // and the picture (content far under 280 characters) stops being listed —
      // which is the thing that cannot be retyped.
      expect(h.deletions.map((d) => d.targetId), ['draw', 'doc', 'img']);
      expect(h.deletions.map((d) => d.what),
          containsAll(<String>['Picture', 'File', 'Drawing']));
      // The GC root: every stored name those three reached is held.
      expect(h.pinnedNames, containsAll(<String>['aa', 'bb', 'notes.pdf']));
    });

    test('a short piece of writing is an edit; 280 characters is a deletion',
        () {
      final w = _Writer('dev-a');
      final h = NotebookHistory()
        ..apply(w.node('p1', 'page'))
        ..apply(w.setBlock('p1', 'small', 'text', {'text': 'a note'}))
        ..apply(w.setBlock('p1', 'big', 'text', {'text': _longText}))
        ..apply(w.removeBlock('p1', 'small'))
        ..apply(w.removeBlock('p1', 'big'));
      // MUTATION: change `chars >= kNotableTextChars` to `chars >= 0` and the
      // short one appears too — which is the "every keystroke" list the owner
      // ruled out.
      expect(h.deletions.map((d) => d.targetId), ['big']);
    });

    test('an eraser gesture is NOT a deletion, however much it erases', () {
      final w = _Writer('dev-a');
      final h = NotebookHistory()
        ..apply(w.node('p1', 'page'))
        ..apply(w.setBlock('p1', 'draw', 'ink', {
          'ink': {'n': 400, 'base': 'sha256:aa'}
        }))
        ..apply(w.op(OpKind.inkStrokes, {
          'pageId': 'p1',
          'blockId': 'draw',
          'del': [for (var i = 0; i < 400; i++) 's$i'],
          'put': const [],
        }));
      // One cleanup session would fill all ten slots by itself, and undo
      // already holds a hundred page snapshots. MUTATION: make `ink.strokes`
      // with a non-empty `del` call `_remember` and this list is no longer
      // empty.
      expect(h.deletions, isEmpty);
      // It still counts as a change, though: somebody touched that drawing.
      expect(h.authorOf('p1', 'draw')!.device, 'dev-a');
      expect(h.authorOf('p1', 'draw')!.lamport, greaterThan(2));
    });

    test('deleting a section is ONE entry, not one per page inside it', () {
      final w = _Writer('dev-a');
      final h = NotebookHistory()
        ..apply(w.node('s1', 'section', title: 'Week 3'))
        ..apply(w.node('p1', 'page', parent: 's1', title: 'Monday'))
        ..apply(w.node('p2', 'page', parent: 's1', title: 'Tuesday'))
        ..apply(w.setBlock('p1', 'i1', 'image', {'blob': 'sha256:aa'}))
        ..apply(w.setBlock('p2', 'i2', 'image', {'blob': 'sha256:bb'}))
        // A device that walks the subtree and deletes each node in turn —
        // which is what the container's cascade does on the other side.
        ..apply(w.op(OpKind.nodeDelete, {'id': 's1'}))
        ..apply(w.op(OpKind.nodeDelete, {'id': 'p1'}))
        ..apply(w.op(OpKind.nodeDelete, {'id': 'p2'}));
      // MUTATION: remove the `_hasDeletedAncestor` guard in `_deleteNode` and
      // this is 3 — so one section deletion spends three of the ten slots and
      // pushes out everything else.
      expect(h.deletions, hasLength(1));
      expect(h.deletions.single.kind, DeletionKind.section);
      expect(h.deletions.single.what, 'Week 3');
      // The whole subtree's media is pinned by that one entry.
      expect(h.pinnedNames, containsAll(<String>['aa', 'bb']));
    });

    test('an eleventh deletion evicts the oldest, and unpins what it held', () {
      final w = _Writer('dev-a');
      final h = NotebookHistory()..apply(w.node('p1', 'page'));
      for (var i = 0; i < 11; i++) {
        h
          ..apply(w.setBlock('p1', 'b$i', 'image', {'blob': 'sha256:h$i'}))
          ..apply(w.removeBlock('p1', 'b$i'));
      }
      // MUTATION: raise `kRecentDeletionsKept`, or drop the `removeRange` in
      // `_remember`, and this is 11. The cap IS the prune — there is no other
      // one, and ten rows cannot leak.
      expect(h.deletions, hasLength(kRecentDeletionsKept));
      expect(h.deletions.map((d) => d.targetId), isNot(contains('b0')));
      expect(h.deletions.first.targetId, 'b10');
      // And the evicted entry stops being a garbage-collection root, which is
      // the honest cost of a bounded list.
      expect(h.pinnedNames, isNot(contains('h0')));
      expect(h.pinnedNames, contains('h10'));
    });

    test('a page put back is no longer a deletion', () {
      final w = _Writer('dev-a');
      final h = NotebookHistory()
        ..apply(w.node('p1', 'page', title: 'Monday'))
        ..apply(w.op(OpKind.nodeDelete, {'id': 'p1'}));
      expect(h.deletions, hasLength(1));
      h.apply(w.op(OpKind.nodeRestore, {'id': 'p1'}));
      // MUTATION: drop the `_forget` call from the `nodeRestore` branch and a
      // page sitting in the sidebar goes on being advertised as deleted — and
      // goes on pinning its blobs.
      expect(h.deletions, isEmpty);
    });

    test('a deletion this build has no digest for is left alone, not guessed',
        () {
      // The safe direction is wrong-by-omission. With no row for the block we
      // cannot tell a lecture recording from a comma, and guessing "notable"
      // would let ordinary editing evict the real entries.
      final w = _Writer('dev-a');
      final h = NotebookHistory()
        ..apply(w.node('p1', 'page'))
        ..apply(w.removeBlock('p1', 'never-seen'));
      expect(h.deletions, isEmpty);
    });
  });

  // ── Attribution is a view, not a store ───────────────────────────────

  group('who changed what', () {
    test('the later op in TOTAL ORDER wins, not the later arrival', () {
      // Two devices. `dev-b` writes at Lamport 5; `dev-a`'s op at Lamport 9 is
      // written afterwards and sorts after it. Now `dev-b`'s log turns up late
      // — a cloud client that was offline — carrying an op at Lamport 7, which
      // arrives LAST and belongs in the MIDDLE.
      final a = _Writer('dev-a');
      final b = _Writer('dev-b');
      final first = b.setBlock('p1', 'x', 'text', {'text': 'b at 5'}, at: 5);
      final mine = a.setBlock('p1', 'x', 'text', {'text': 'a at 9'}, at: 9);
      final late = b.setBlock('p1', 'x', 'text', {'text': 'b at 7'}, at: 7);

      final incremental = NotebookHistory()
        ..apply(first)
        ..apply(mine)
        ..apply(late);
      final rebuilt = NotebookHistory()
        ..applyAll([first, mine, late]..sort(Op.compare));

      // MUTATION: delete the `if (prev != null && !_isAfter(op, prev)) return;`
      // guard in `_record` and the incremental answer becomes `dev-b`, while
      // the rebuild still says `dev-a` — two devices disagreeing for ever about
      // who wrote a block, with nothing to notice it.
      expect(incremental.authorOf('p1', 'x')!.device, 'dev-a');
      expect(rebuilt.authorOf('p1', 'x')!.device, 'dev-a');
    });

    test('an op this build cannot read is attributed to nobody', () {
      final h = NotebookHistory()
        ..apply(Op(
          device: 'dev-a',
          seq: 1,
          lamport: 1,
          timestamp: 1,
          version: opFormatVersion + 1,
          kind: OpKind.blockSet,
          data: {
            'pageId': 'p1',
            'block': {'id': 'x', 'type': 'text', 'content': {}}
          },
        ));
      // Same gate, same reasoning, as `Materializer.apply`: a v2 envelope may
      // not even be a map, so claiming to know who wrote it is a lie.
      expect(h.authorOf('p1', 'x'), isNull);
    });
  });

  // ── Nobody ever sees a device id ─────────────────────────────────────

  group('names, never ids', () {
    test('an unnamed device reads as "another computer"', () {
      expect(deviceDisplayName(null), 'another computer');
      expect(deviceDisplayName('   '), 'another computer');
      expect(deviceDisplayName(null, isThisComputer: true), 'this computer');
      expect(deviceDisplayName('Eric laptop'), 'Eric laptop');
    });

    test('the default name is not a hostname and not a uuid', () {
      final d = DeviceLabels.defaultLabel();
      expect(d, isNot(contains('DESKTOP-')));
      expect(d, isNot(matches(RegExp(r'[0-9a-f]{8}-[0-9a-f]{4}'))));
      expect(d.split(' ').length, lessThanOrEqualTo(3));
    });
  });

  // ── The container half ───────────────────────────────────────────────

  group('in a real notebook', () {
    late Directory tmp;
    late Repository repo;
    late AppState app;
    late String nb;
    late String file;
    late String page;

    Future<void> boot() async {
      tmp = Directory.systemTemp.createTempSync('onote_history_');
      repo = await Repository.openAt(tmp);
      final created = await repo.createNotebook('History');
      nb = created.id;
      file = created.file;
      app = AppState(repo)..notebookId = nb;
      app.reloadNodes();
      page = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
      await app.selectPage(page);
    }

    void shutdown() {
      app.dispose();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    }

    int countRows(String table) {
      final db = sqlite3.open(file);
      try {
        return db.select('SELECT COUNT(*) AS c FROM $table').first['c'] as int;
      } finally {
        db.dispose();
      }
    }

    test('editing ONE block five hundred times adds no rows and no re-scan',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await boot();
      addTearDown(shutdown);
      await app.refreshHistory(nb);

      final foldedBefore = NotebookHistory.debugOpsFolded;
      final rowsBefore = NotebookHistory.debugRowWrites;
      for (var i = 0; i < 500; i++) {
        app.importPage(
            nb,
            page,
            [
              Block(
                  id: 'b1',
                  type: BlockType.text,
                  x: 0,
                  y: 0,
                  content: {'text': 'draft $i'})
            ],
            PageProps());
        await app.refreshHistory(nb);
      }
      final folded = NotebookHistory.debugOpsFolded - foldedBefore;
      final rows = NotebookHistory.debugRowWrites - rowsBefore;

      // **The boundedness claim.** `page_versions` would be 30 rows by now and
      // capped only per page; this is one row, for ever, because it is keyed on
      // the block rather than on the edit.
      // MUTATION: key `block_authors` on (page_id, block_id, lamport) and this
      // is 500.
      expect(countRows('block_authors'), 1);

      // **The "it is free" measurement.** One op folded and one row written per
      // save. A maintenance pass that re-derived from the whole log would be
      // quadratic — ~125,000 folds for these 500 saves — so the ceiling below
      // is three orders of magnitude away from the failure it guards.
      // MUTATION: replace `HistoryCatchUp`'s `readDeviceFrom(dev, offsetOf(dev))`
      // with `readDeviceFrom(dev, 0)` and `folded` goes to ~125,000.
      expect(folded, lessThan(700),
          reason: '$folded ops folded for 500 saves — linear, not a re-scan');
      expect(rows, lessThan(700),
          reason: '$rows rows written for 500 saves');
      expect(folded, greaterThanOrEqualTo(500),
          reason: 'every save really did record something');
    });

    test('ATTRIBUTION REBUILT FROM THE LOG ALONE EQUALS THE ONE KEPT ON SAVE',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await boot();
      addTearDown(shutdown);

      // Device A: ordinary editing through the save funnel.
      app.blocks = [
        Block(id: 'b1', type: BlockType.text, x: 0, y: 0, content: {'text': 'one'}),
        Block(id: 'b2', type: BlockType.image, x: 0, y: 0, content: {'blob': 'sha256:aa'}),
      ];
      app.markDirty();
      await app.flushSave();
      app.blocks.removeWhere((b) => b.id == 'b2');
      app.markDirty();
      await app.flushSave();
      await app.refreshHistory(nb);

      // Device B's log turns up late, and one of its ops belongs BEFORE
      // something this device has already folded. A second device with no
      // label, deliberately — see the negative control below.
      final store = OpLogStore.forNotebook(file);
      final mine = store.readAll();
      final highest = mine.map((o) => o.lamport).reduce((a, b) => a > b ? a : b);
      final b = _Writer('dev-b');
      store.append('dev-b', [
        b.setBlock(page, 'b1', 'text', {'text': 'from the other laptop'},
            at: highest - 1),
        b.setBlock(page, 'b3', 'text', {'text': 'brand new'}, at: highest + 4),
      ]);
      await app.refreshHistory(nb);

      final incremental = app.historyOf(nb)!;
      final rebuilt = NotebookHistory()..applyAll(store.readAll());

      String describe(NotebookHistory h) => ([
            for (final e in h.authors.entries)
              '${e.key} -> ${e.value.device}#${e.value.seq}@${e.value.lamport}'
                  ' ${e.value.blockKind}/${e.value.chars}'
          ]..sort())
              .join('\n');
      String describeDeletions(NotebookHistory h) => [
            for (final d in h.deletions)
              '${d.kind.name} ${d.targetId} ${d.device}#${d.seq}@${d.lamport}'
          ].join('\n');

      // **THE LOAD-BEARING CELL (matrix row B8).** If these disagree,
      // attribution is not derivable from the log and Step 8a's premise is
      // wrong — the feature would have to become a store, which is what every
      // other version-history design in the plan died of.
      // MUTATION: any of the three named above (drop `_isAfter`, sort the
      // batch after applying instead of before, or fold arrival-ordered)
      // splits these two strings.
      expect(describe(incremental), describe(rebuilt));
      expect(describeDeletions(incremental), describeDeletions(rebuilt));
      // And it is not vacuously equal: there is real content on both sides.
      expect(incremental.authors, hasLength(2));
      expect(incremental.authorOf(page, 'b1')!.device, 'dev-b');
      expect(incremental.deletions.map((d) => d.targetId), contains('b2'));

      // The container round-trips it: what was flushed reads back identical.
      expect(describe(repo.loadHistory(nb)), describe(incremental));
    });

    test('purging a page takes its attribution with it — the cascade this '
        'table declares and page_versions never did', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await boot();
      addTearDown(shutdown);
      app.blocks = [
        Block(id: 'b1', type: BlockType.text, x: 0, y: 0, content: {'text': 'hi'})
      ];
      app.markDirty();
      await app.flushSave();
      expect(countRows('block_authors'), 1);

      app.purgeDeleted(page);
      // MUTATION: drop `REFERENCES nodes(id) ON DELETE CASCADE` from
      // `block_authors` in `database.dart` and this is 1 — the exact orphan
      // class commit 1be2d28 had to write a sweep for, back again.
      expect(countRows('block_authors'), 0);
    });

    test('a deleted picture comes back from the log alone, with its hash',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await boot();
      addTearDown(shutdown);
      app.blocks = [
        Block(
            id: 'pic',
            type: BlockType.image,
            x: 0,
            y: 0,
            content: {'blob': 'sha256:deadbeef'}),
      ];
      app.markDirty();
      await app.flushSave();
      app.blocks.clear();
      app.markDirty();
      await app.flushSave();
      await app.refreshHistory(nb);

      final gone = app.recentDeletions().single;
      expect(gone.what, 'Picture');
      expect(gone.pins, contains('deadbeef'));

      // Nothing was copied anywhere when it was deleted. §4.1's promise that
      // no log line is ever rewritten is what makes this work: the last
      // `block.set` naming that block is still in the log, exactly where it
      // was written.
      // MUTATION: make `_restoreRemovedBlock` search ops AFTER the removal
      // (drop `_beforeDeletion`) and nothing is found.
      expect(await app.restoreDeletion(gone), isTrue);
      expect(app.blocks.single.id, 'pic');
      expect(app.blocks.single.content['blob'], 'sha256:deadbeef');
      // Put back means put back: it stops being advertised as deleted.
      expect(app.recentDeletions(), isEmpty);
    });

    test('a purged page is rebuilt from the log, blocks and all', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await boot();
      addTearDown(shutdown);
      final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section).id;
      await app.addPage(sectionId: section);
      final victim = app.pageId!;
      app.blocks = [
        Block(id: 'v1', type: BlockType.image, x: 0, y: 0, content: {
          'blob': 'sha256:cafe'
        })
      ];
      app.markDirty();
      await app.flushSave();

      app.purgeDeleted(victim);
      await app.refreshHistory(nb);
      app.reloadNodes();
      expect(app.nodes.any((n) => n.id == victim), isFalse);

      final gone =
          app.recentDeletions().firstWhere((d) => d.targetId == victim);
      expect(gone.kind, DeletionKind.page);
      // MUTATION: have `_restoreDeletedNode` skip the `importPage` call and the
      // page comes back empty — which is the difference between restoring a
      // page and restoring its name.
      expect(await app.restoreDeletion(gone), isTrue);
      app.reloadNodes();
      expect(app.nodes.any((n) => n.id == victim), isTrue);
      await app.selectPage(victim);
      expect(app.blocks.single.content['blob'], 'sha256:cafe');
    });
  });

  // ── The negative control ─────────────────────────────────────────────

  testWidgets('NEGATIVE CONTROL: an unnamed device shows a friendly fallback '
      'and no uuid reaches the screen', (tester) async {
    if (!initSqliteForTests()) return markTestSkipped('sqlite unavailable');
    late Repository repo;
    late AppState app;
    late String nb;
    late String file;
    late String page;
    final tmp = Directory.systemTemp.createTempSync('onote_history_ui_');
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    await tester.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final created = await repo.createNotebook('Shared');
      nb = created.id;
      file = created.file;
      app = AppState(repo)..notebookId = nb;
      app.reloadNodes();
      page = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
      await app.selectPage(page);
      app.blocks = [
        Block(id: 'b1', type: BlockType.text, x: 0, y: 0, content: {'text': 'mine'})
      ];
      app.markDirty();
      await app.flushSave();

      // A second computer that never set a name — the case the fallback exists
      // for. It writes the newest op, so it is what the page attributes to.
      final store = OpLogStore.forNotebook(file);
      final highest =
          store.readAll().map((o) => o.lamport).reduce((a, b) => a > b ? a : b);
      final other = _Writer('019fdff4-8c31-7a2e-b0c1-5566778899aa');
      store.append(other.device, [
        other.setBlock(page, 'b1', 'text', {'text': 'theirs'}, at: highest + 3),
        other.setBlock(page, 'b2', 'image', {'blob': 'sha256:aa'},
            at: highest + 4),
        other.removeBlock(page, 'b2', at: highest + 5),
      ]);
      await app.refreshHistory(nb);
      app.blocks = [
        Block(id: 'b1', type: BlockType.text, x: 0, y: 0, content: {'text': 'theirs'})
      ];
    });

    expect(app.recentDeletions(), isNotEmpty,
        reason: 'the fixture really did produce something to show');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showPageHistory(context, app),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    final shown = <String>[
      for (final w in tester.widgetList<Text>(find.byType(Text)))
        w.data ?? '',
    ];
    // MUTATION: render `a.device` instead of `deviceDisplayName(...)` in
    // `_changeLine`, or drop the fallback from `deviceDisplayName`, and the
    // uuid is on the screen.
    expect(shown.join(' | '), contains('another computer'));
    for (final line in shown) {
      expect(line, isNot(contains('019fdff4')),
          reason: 'no raw device id may reach a student: "$line"');
      expect(line, isNot(matches(RegExp(r'[0-9a-f]{8}-[0-9a-f]{4}-'))),
          reason: 'no uuid may reach a student: "$line"');
      expect(line.toLowerCase(), isNot(contains('lamport')));
      expect(line.toLowerCase(), isNot(contains('.oplog')));
    }
    // The technical detail exists — it is simply folded away, matching
    // `open_notice_dialog.dart` and `save_problem_dialog.dart`.
    expect(find.text('Details (advanced)'), findsOneWidget);
  });
}
