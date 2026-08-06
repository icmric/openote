// The two structures that keep the summary surfaces (tags rollup, planner,
// flashcard deck) off the decode-every-page path: the SQL tag prefilter and
// the shared decoded-page cache. See Repository.readPageShared for the
// reasoning; PLANNING.md carries the report that motivated it ("opening the
// tab is very slow").

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
