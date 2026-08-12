// Guards the per-keystroke hot paths.
//
// The regression these pin was severe and entirely invisible to the existing
// tests: widgets in the command bar and status bar called methods that read
// EVERY page in the notebook from SQLite, and those widgets rebuild on every
// notify — i.e. every character typed. On a 324-page notebook that was
// hundreds of database reads per keystroke, and the app crawled.
//
// The rule these encode: anything a per-frame widget calls must be O(1) after
// the first call, until something that changes the answer happens.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/model/tags.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/sync/op_log.dart';

import 'support/sqlite.dart';

// Measured by COUNTING the work, not by timing it.
//
// These were wall-clock bars ("200 calls in under 50 ms"), on the reasoning
// that latency per keystroke was what hurt users. True, but untestable: a
// `flutter test` run executes files in parallel, so on a loaded machine — and
// always on a two-core CI runner — the bar measured how much CPU was going
// spare. It was red on all four app platforms while the caches worked
// perfectly.
//
// What each cache actually promises is that the expensive call happens ONCE.
// `Repository.debugSharedPageReads` and `OpLogStore.debugDirectoryListings` count
// exactly those, on the one code path each cache exists to avoid: a working
// cache adds zero, a broken one adds hundreds, and neither answer moves with
// the weather.

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Future<(Repository, Directory, AppState, String)> notebookWithPages(
      String prefix, int pageCount) async {
    final tmp = Directory.systemTemp.createTempSync(prefix);
    final repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Perf');
    final app = AppState(repo)..notebookId = nb.id;
    app.reloadNodes();
    final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section).id;

    for (var i = 0; i < pageCount; i++) {
      final node = app.importNode(
          nb.id,
          TreeNode(
            kind: NodeKind.page,
            parentId: section,
            title: 'Page $i',
            position: 'a${(1000 + i).toString().padLeft(15, '0')}',
          ));
      final b = Block(
          type: BlockType.text,
          x: 0,
          y: 0,
          content: {'text': 'What is $i?\n  Because $i.'});
      NoteTag.writeInto(b.content, [NoteTag(kind: TagKind.question, line: 0)]);
      app.importPage(nb.id, node.id, [b], PageProps());
    }
    app.reloadNodes();
    // selectPage, not a bare pageId assignment: only the former loads blocks.
    // And one of OUR pages — a new notebook ships with an empty starter page
    // that sorts first and would give an empty block list.
    await app.selectPage(
        app.nodes.firstWhere((n) => n.title == 'Page 0').id);
    return (repo, tmp, app, section);
  }

  group('deck counts are cached', () {
    test('repeated calls do not re-read the notebook', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, _) = await notebookWithPages('onote_perf_deck_', 12);
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      // First call populates the cache.
      final first = app.study.deckCounts();
      expect(first.$2, greaterThan(0), reason: 'the fixture has cards');

      // Simulate what the command bar does: many rebuilds with no edit.
      final before = Repository.debugSharedPageReads;
      for (var i = 0; i < 200; i++) {
        app.study.deckCounts();
      }
      final reads = Repository.debugSharedPageReads - before;

      // 200 uncached calls would be 200 × 12 page reads = 2400 reads.
      // Cached, this is 200 map lookups and not one read.
      expect(reads, 0,
          reason: '200 deck-count calls re-read $reads page(s) — the cache '
              'is not holding, and this runs per keystroke');
    });

    test('the cache still invalidates when content changes', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, _) = await notebookWithPages('onote_perf_inval_', 3);
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final beforeCount = app.study.deckCounts().$2;
      // Tag another line on the open page — docRevision bumps, so the deck
      // must be rebuilt. A cache that never invalidates is worse than none.
      final b = app.blocks.first;
      b.content['text'] = '${b.content['text']}\nDefine perf — speed.';
      NoteTag.writeInto(b.content, [
        ...NoteTag.listFrom(b.content),
        NoteTag(kind: TagKind.definition, line: 2),
      ]);
      app.docRevision++;

      // COUNTED as well as observed, so the sibling test's `expect(reads, 0)`
      // cannot pass vacuously. If the counter were dead — never incremented, or
      // reading a path these calls do not take — zero would be trivially true
      // and the cache guard would be worthless. Here the same counter must
      // MOVE, on the same call, for the same fixture.
      final before = Repository.debugSharedPageReads;
      expect(app.study.deckCounts().$2, greaterThan(beforeCount),
          reason: 'a new tagged line must produce a new card');
      expect(Repository.debugSharedPageReads, greaterThan(before),
          reason: 'an invalidated deck must actually re-read the notebook — '
              'if this does not move, the counter is not watching this path '
              'and the cached-case assertion proves nothing');
    });
  });

  group('tag rollup is cached', () {
    test('repeated calls do not re-read the notebook', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, _) = await notebookWithPages('onote_perf_tags_', 12);
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      expect(app.allTags(), isNotEmpty);
      final before = Repository.debugSharedPageReads;
      for (var i = 0; i < 200; i++) {
        app.allTags();
      }
      final reads = Repository.debugSharedPageReads - before;
      expect(reads, 0,
          reason: '200 allTags calls re-read $reads page(s)');
    });
  });

  group('the planner agenda is cached', () {
    // The planner panel, the command bar's badge and the navigator's Home pane
    // all read the agenda, and all three rebuild on every notify. Building it
    // walks the tag rollup and — for the soonest exam — a whole section's deck
    // out of SQLite, so this is squarely on the hot path the group above
    // exists for.
    test('repeated calls do not re-read the notebook', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, section) =
          await notebookWithPages('onote_perf_plan_', 12);
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final now = DateTime.now();
      // An exam date is the expensive case: it is what pulls a deck build into
      // the agenda at all.
      app.study.setExamDate(section, now.add(const Duration(days: 10)));
      expect(app.planner.agenda(now: now), isNotEmpty);

      final before = Repository.debugSharedPageReads;
      for (var i = 0; i < 200; i++) {
        app.planner.sections(now: now);
      }
      final reads = Repository.debugSharedPageReads - before;
      expect(reads, 0,
          reason: '200 agenda builds re-read $reads page(s) — an agenda '
              'pulls a deck build in, so this is the expensive one');
    });

    test('but it notices when a date changes', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, section) =
          await notebookWithPages('onote_perf_planinv_', 4);
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final now = DateTime.now();
      expect(app.planner.agenda(now: now), isEmpty);
      // A cache that never invalidates is worse than none: this exact case
      // shipped broken once, because `setExamDate` notified without moving any
      // revision the agenda's key was built from.
      app.study.setExamDate(section, now.add(const Duration(days: 10)));
      expect(app.planner.agenda(now: now), hasLength(1));
    });
  });

  group('sync status is cached', () {
    test('repeated calls do not re-list the ops directory', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, _) = await notebookWithPages('onote_perf_sync_', 2);
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      // This one is a synchronous DIRECTORY LISTING, and once the notebook is
      // in a cloud folder that path is sync-client-backed — so uncached it was
      // filesystem I/O per character typed.
      app.syncDeviceCount(app.notebookId!);
      final before = OpLogStore.debugDirectoryListings;
      for (var i = 0; i < 500; i++) {
        app.syncDeviceCount(app.notebookId!);
      }
      final listings = OpLogStore.debugDirectoryListings - before;
      expect(listings, 0,
          reason: '500 device-count calls listed the ops directory $listings '
              'time(s) — that is filesystem I/O per keystroke');
    });
  });
}
