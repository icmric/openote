// The two structures that keep the summary surfaces (tags rollup, planner,
// flashcard deck) off the decode-every-page path: the SQL tag prefilter and
// the shared decoded-page cache. See Repository.readPageShared for the
// reasoning; PLANNING.md carries the report that motivated it ("opening the
// tab is very slow").

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:openote/model/models.dart';
import 'package:openote/model/tags.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Future<(Repository, Directory, AppState, String)> notebook(
      String name, int pages,
      {Set<int> taggedAt = const {}}) async {
    final tmp = Directory.systemTemp.createTempSync(name);
    final repo = await Repository.openAt(tmp);
    addTearDown(() async {
      await repo.flushWorkspace();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final nb = await repo.createNotebook('Perf');
    final app = AppState(repo)..notebookId = nb.id;
    app.reloadNodes();
    final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section).id;
    for (var i = 0; i < pages; i++) {
      final node = app.importNode(
          nb.id,
          TreeNode(
              kind: NodeKind.page,
              parentId: section,
              title: 'Page $i',
              position: 'a${i.toString().padLeft(15, '0')}'));
      final b = Block(
          type: BlockType.text,
          x: 0,
          y: 0,
          content: {'text': 'What is thing $i?\n  The answer to thing $i.'});
      if (taggedAt.contains(i)) {
        NoteTag.writeInto(b.content, [
          NoteTag(kind: TagKind.question, line: 0),
        ]);
      }
      app.importPage(nb.id, node.id, [b], PageProps());
    }
    app.reloadNodes();
    return (repo, tmp, app, nb.id);
  }

  group('the tag prefilter', () {
    test('finds exactly the tagged pages', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, _, _, nb) =
          await notebook('onote_prefilter_', 30, taggedAt: {3, 17});
      expect(repo.pageIdsWithTags(nb), hasLength(2));
    });

    test('a page whose TEXT mentions "tags": cannot even false-positive',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, _, app, nb) = await notebook('onote_prefilter_fp_', 1);
      final node = app.nodes.firstWhere((n) => n.title == 'Page 0');
      final data = repo.readPage(nb, node.id);
      data.blocks.first.content['text'] = 'json uses "tags": for lists';
      app.importBatch(
          nb, () => app.importPage(nb, node.id, data.blocks, data.props));
      // Stronger than the design asked for: inside the stored page JSON the
      // text's quotes are escaped (`\"tags\":`), so a prose mention cannot
      // match the pattern at all — only a real JSON key can. The filter is
      // exact in practice, not merely safe.
      expect(repo.pageIdsWithTags(nb), isEmpty);
      expect(app.allTags(), isEmpty);
      expect(app.study.deck(), isEmpty);
    });
  });

  group('the shared decoded-page cache', () {
    test('hands back the same instance until the page is written', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, _, app, nb) = await notebook('onote_cache_', 2);
      final id = app.nodes.firstWhere((n) => n.title == 'Page 0').id;

      final a = repo.readPageShared(nb, id);
      final b = repo.readPageShared(nb, id);
      expect(identical(a, b), isTrue, reason: 'second read must be a cache hit');

      // A write through the single funnel evicts.
      final fresh = repo.readPage(nb, id);
      fresh.blocks.first.content['text'] = 'edited';
      app.importBatch(
          nb, () => app.importPage(nb, id, fresh.blocks, fresh.props));
      final c = repo.readPageShared(nb, id);
      expect(identical(a, c), isFalse);
      expect(c.blocks.first.content['text'], 'edited',
          reason: 'a stale cache here would show pre-edit content in the '
              'rollup and the deck');
    });

    // The write funnel above is one of the two ways a page leaves the cache.
    // The other is a purge, and it was only half wired: `purgeNode` evicted
    // the id it was handed, but `nodes.parent_id` is
    // `REFERENCES nodes(id) ON DELETE CASCADE`, so purging a SECTION deletes
    // its pages' rows without those page ids ever reaching the eviction. The
    // recycle bin purges sections and every import purges the seeded starter
    // section, so that is the common shape rather than the rare one.
    //
    // What the eviction is FOR, in `purgeNode`'s own words: a page recreated
    // later under the same id — a restore, or a `nodeUpsert` from a device
    // that never saw the purge, since `Materializer` handles `nodePurge` with
    // a bare `nodes.remove` and keeps no tombstone — would read as its dead
    // predecessor. Half the tests below are therefore the more important
    // half: that pages OUTSIDE the purged subtree are not evicted, because
    // "clear the whole notebook's cache" would pass every assertion about
    // staleness and quietly undo the structure this file exists to protect.
    group('and the purge cascade', () {
      /// A section with [titles] pages under it, each holding its own title as
      /// text so a stale read is identifiable rather than merely non-identical.
      /// Returns the section id followed by the page ids.
      List<String> section(AppState app, String nb, String name,
          List<String> titles,
          {String? parent}) {
        final s = app.importNode(
            nb,
            TreeNode(
                kind: NodeKind.section,
                parentId: parent,
                title: name,
                position: name));
        final out = <String>[s.id];
        for (final t in titles) {
          final p = app.importNode(
              nb,
              TreeNode(
                  kind: NodeKind.page,
                  parentId: s.id,
                  title: t,
                  position: t));
          app.importPage(
              nb,
              p.id,
              [Block(type: BlockType.text, x: 0, y: 0, content: {'text': t})],
              PageProps());
          out.add(p.id);
        }
        return out;
      }

      test('purging a section evicts the pages inside it', () async {
        if (!haveSqlite) return markTestSkipped('sqlite unavailable');
        final (repo, _, app, nb) = await notebook('onote_purgecache_', 1);
        final ids = section(app, nb, 'doomed', ['inside']);
        final inside = ids[1];

        expect(repo.readPageShared(nb, inside).blocks.first.content['text'],
            'inside');
        repo.purgeNode(nb, ids[0]);

        expect(repo.readPageShared(nb, inside).blocks, isEmpty,
            reason: 'the page row went with the section through the cascade, '
                'so the cache must not still be able to hand it out');
      });

      test('…however deep the subtree goes', () async {
        if (!haveSqlite) return markTestSkipped('sqlite unavailable');
        final (repo, _, app, nb) = await notebook('onote_purgedeep_', 1);
        final group = app.importNode(nb,
            TreeNode(kind: NodeKind.sectionGroup, title: 'grp', position: 'g'));
        final ids = section(app, nb, 'nested', ['deep'], parent: group.id);

        expect(repo.readPageShared(nb, ids[1]).blocks, isNotEmpty);
        repo.purgeNode(nb, group.id);

        expect(repo.readPageShared(nb, ids[1]).blocks, isEmpty,
            reason: 'the walk must follow parent links all the way down, not '
                'one level');
      });

      test('and evicts NOTHING outside it', () async {
        if (!haveSqlite) return markTestSkipped('sqlite unavailable');
        // The negative control. Clearing the whole per-notebook map would make
        // the two tests above pass and would throw away every other page the
        // rollup, the deck and the planner just decoded — the exact cost this
        // cache exists to avoid, paid on every emptying of the recycle bin.
        final (repo, _, app, nb) = await notebook('onote_purgekeep_', 1);
        final doomed = section(app, nb, 'doomed', ['inside']);
        final kept = section(app, nb, 'kept', ['neighbour']);
        final flat = app.nodes.firstWhere((n) => n.title == 'Page 0').id;

        final neighbour = repo.readPageShared(nb, kept[1]);
        final other = repo.readPageShared(nb, flat);
        repo.purgeNode(nb, doomed[0]);

        expect(identical(repo.readPageShared(nb, kept[1]), neighbour), isTrue,
            reason: 'a page in a different section was not purged and must '
                'still be a cache hit');
        expect(identical(repo.readPageShared(nb, flat), other), isTrue);
        expect(repo.readPageShared(nb, kept[1]).blocks.first.content['text'],
            'neighbour');
      });

      test('the retention sweep evicts the pages it expires', () async {
        if (!haveSqlite) return markTestSkipped('sqlite unavailable');
        // `purgeExpiredNodes` is the other place a `nodes` row is hard-deleted,
        // and it evicted nothing whatever — it names no ids, so every page it
        // took stayed cached in full. It runs unattended at startup, so this
        // needed no user action to happen.
        final (repo, _, app, nb) = await notebook('onote_purgeexpiry_', 1);
        final doomed = section(app, nb, 'expiring', ['gone']);
        final kept = section(app, nb, 'staying', ['fresh']);
        expect(repo.readPageShared(nb, doomed[1]).blocks, isNotEmpty);
        final survivor = repo.readPageShared(nb, kept[1]);

        repo.softDeleteNode(nb, doomed[0]);
        repo.softDeleteNode(nb, kept[0]); // trashed, but not yet expired
        final db = sqlite3.open(repo.notebooks.firstWhere((n) => n.id == nb).file);
        db.execute('UPDATE nodes SET deleted_at=? WHERE id IN (?,?)', [
          DateTime.now()
              .subtract(
                  const Duration(days: Repository.recycleRetentionDays + 10))
              .millisecondsSinceEpoch,
          doomed[0],
          doomed[1],
        ]);
        db.dispose();

        repo.purgeExpiredNodes(nb);

        expect(repo.readPageShared(nb, doomed[1]).blocks, isEmpty);
        // The half that matters: a page still inside the thirty-day window
        // keeps its `nodes` row, so it is not expired and must not be evicted.
        expect(identical(repo.readPageShared(nb, kept[1]), survivor), isTrue,
            reason: 'a page in the recycle bin is restorable, not purged');
      });
    });
  });

  group('allBlockIds', () {
    test('covers every block without decoding, tagged or not', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, _, app, nb) =
          await notebook('onote_blockids_', 10, taggedAt: {0});
      final ids = repo.allBlockIds(nb);
      for (final n in app.nodes.where((n) => n.kind == NodeKind.page)) {
        for (final b in repo.readPage(nb, n.id).blocks) {
          expect(ids, contains(b.id),
              reason: 'a missing id here would let card-state pruning delete '
                  'a living card\'s review history');
        }
      }
    });
  });

  group('the deck fast path', () {
    test('builds the same deck as a full walk, reading only tagged pages',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (_, _, app, _) =
          await notebook('onote_deckfast_', 40, taggedAt: {5, 21, 33});
      final deck = app.study.deck();
      expect(deck, hasLength(3));
      expect(deck.map((c) => c.pageTitle).toSet(),
          {'Page 5', 'Page 21', 'Page 33'});
    });

    test('the rollup agrees', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (_, _, app, _) =
          await notebook('onote_rollupfast_', 40, taggedAt: {5, 21});
      expect(app.allTags(), hasLength(2));
    });

    test('unsaved tags on the OPEN page still count', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (_, _, app, _) = await notebook('onote_openpage_', 5);
      final id = app.nodes.firstWhere((n) => n.title == 'Page 2').id;
      await app.selectPage(id);
      // Tag in memory only — no save yet, so the SQL prefilter cannot see it.
      NoteTag.writeInto(app.blocks.first.content, [
        NoteTag(kind: TagKind.question, line: 0),
      ]);
      app.study.noteContentChanged();
      app.docRevision++;
      expect(app.study.deck(), hasLength(1),
          reason: 'the open page bypasses the prefilter — its memory is '
              'fresher than the container');
      expect(app.allTags(), hasLength(1));
    });
  });
}
