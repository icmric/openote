// The study surface at the state layer: what a session contains, and what
// grading it does (and does not) change.
//
// These pin the four bugs that made the panel feel broken:
//   1. a card graded Again vanished until tomorrow — no way to try it again;
//   2. "nothing due" was a dead end, with no way to go over a topic anyway;
//   3. tagging a line on the OPEN page produced no card until you navigated
//      away, because the deck cache only invalidated on structural change;
//   4. reading a card's schedule CREATED one, so the persisted blob grew with
//      every card anyone merely looked at.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/model/tags.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/study/flashcards.dart';
import 'package:openote/study/study_stats.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  /// A notebook of `pages` pages, each with one Question card, with the first
  /// one open.
  Future<(Repository, Directory, AppState)> fixture(String name, int pages) async {
    final tmp = Directory.systemTemp.createTempSync(name);
    final repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Study');
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
    await app.selectPage(app.nodes.firstWhere((n) => n.title == 'Page 0').id);
    return (repo, tmp, app);
  }

  void cleanup(Repository repo, Directory tmp) {
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  }

  test('a card graded Again is reviewable again in the same sitting', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp, app) = await fixture('onote_study_again_', 3);
    addTearDown(() => cleanup(repo, tmp));

    final card = app.study.deck().first;
    app.study.gradeCard(card.id, Grade.again);
    // The old behaviour scheduled it for tomorrow, so it disappeared from the
    // deck entirely and "let me try that one again" was impossible.
    final s = app.study.cardState(card.id);
    expect(s.dueAt - nowMs(), lessThan(3600000));
  });

  test('practice ignores the schedule and does not overwrite it', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp, app) = await fixture('onote_study_cram_', 4);
    addTearDown(() => cleanup(repo, tmp));

    for (final c in app.study.deck()) {
      app.study.gradeCard(c.id, Grade.easy);
    }
    expect(app.study.sessionCards().length, 0, reason: 'everything is scheduled out');

    final practice = app.study.sessionCards(mode: StudyMode.cram);
    expect(practice.length, 4, reason: 'practice ignores the schedule');

    final before = app.study.cardState(practice.first.id).dueAt;
    app.study.gradeCard(practice.first.id, Grade.good, schedule: false);
    expect(app.study.cardState(practice.first.id).dueAt, before,
        reason: 'a night of cramming must not wipe weeks of spacing');

    // Getting one WRONG is information about the card whatever the mode.
    app.study.gradeCard(practice.first.id, Grade.again, schedule: false);
    expect(app.study.cardState(practice.first.id).dueAt, lessThan(before));
  });

  test('deckStats says when the next card is due', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp, app) = await fixture('onote_study_stats_', 3);
    addTearDown(() => cleanup(repo, tmp));

    expect(app.study.deckStats().unseen, 3);
    for (final c in app.study.deck()) {
      app.study.gradeCard(c.id, Grade.easy);
    }
    final s = app.study.deckStats();
    expect(s.due, 0);
    expect(s.total, 3);
    expect(s.nextDueAt, isNotNull,
        reason: '"nothing due" with no next date is a dead end');
    expect(s.nextDueAt! - nowMs(), greaterThan(0));
  });

  test('resetting a deck makes its cards new again', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp, app) = await fixture('onote_study_reset_', 3);
    addTearDown(() => cleanup(repo, tmp));

    for (final c in app.study.deck()) {
      app.study.gradeCard(c.id, Grade.easy);
    }
    expect(app.study.resetDeck(), 3);
    expect(app.study.deckStats().due, 3);
    expect(app.study.deckStats().unseen, 3);
  });

  test('reading a schedule does not create one', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp, app) = await fixture('onote_study_read_', 3);
    addTearDown(() => cleanup(repo, tmp));

    for (final c in app.study.deck()) {
      app.study.cardState(c.id);
    }
    // Grade exactly one card; only that one may be persisted.
    app.study.gradeCard(app.study.deck().first.id, Grade.good);
    final stored = repo.getSetting('cardStates') as Map?;
    expect(stored, isNotNull);
    expect(stored!.length, 1,
        reason: 'merely looking at a card must not persist a schedule');
  });

  test('grading in one notebook keeps the other notebook\'s schedule',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // Card scheduling is stored per WORKSPACE but a deck is per NOTEBOOK, so
    // pruning "everything not in this deck" deleted every OTHER notebook's
    // review history the first time you graded a card after switching — a
    // term of spaced repetition gone, silently, with no undo.
    final (repo, tmp, app) = await fixture('onote_study_cross_', 2);
    addTearDown(() => cleanup(repo, tmp));

    for (final c in app.study.deck()) {
      app.study.gradeCard(c.id, Grade.easy);
    }
    final first = app.notebookId!;
    final firstCards = {for (final c in app.study.deck()) c.id};
    expect(firstCards, isNotEmpty);

    // A second notebook in the same workspace, with its own card.
    final nb2 = await repo.createNotebook('Other');
    app.notebookId = nb2.id;
    app.reloadNodes();
    final section =
        app.nodes.firstWhere((n) => n.kind == NodeKind.section).id;
    final node = app.importNode(
        nb2.id,
        TreeNode(
            kind: NodeKind.page,
            parentId: section,
            title: 'P',
            position: 'a000000000000001'));
    final b = Block(
        type: BlockType.text, x: 0, y: 0, content: {'text': 'Why?\n  Because.'});
    NoteTag.writeInto(b.content, [NoteTag(kind: TagKind.question, line: 0)]);
    app.importPage(nb2.id, node.id, [b], PageProps());
    app.reloadNodes();
    await app.selectPage(node.id);

    app.study.gradeCard(app.study.deck().first.id, Grade.good);

    final stored = repo.getSetting('cardStates') as Map?;
    expect(stored, isNotNull);
    for (final id in firstCards) {
      expect(stored!.containsKey(id), isTrue,
          reason: 'notebook $first lost the schedule for $id');
    }
  });

  test('a card keeps its schedule when its line moves', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // A card is identified by 'blockId:line', so re-basing a tag RENAMES its
    // card. Without carrying the schedule across, it is orphaned under the old
    // name and the next prune deletes it — weeks of spacing gone from pressing
    // Enter above a tagged line.
    final (repo, tmp, app) = await fixture('onote_study_move_', 2);
    addTearDown(() => cleanup(repo, tmp));

    final card = app.study.deck(pageId: app.pageId).single;
    app.study.gradeCard(card.id, Grade.easy);
    final due = app.study.cardState(card.id).dueAt;
    expect(due, greaterThan(0));

    // Exactly what typing a line above it does.
    final b = app.blocks.first;
    final before = b.content['text'] as String;
    final after = 'Lecture 4\n$before';
    app.study.remapCardStates(b.id, NoteTag.rebase(b.content, before, after));
    b.content['text'] = after;
    app.markDirty();

    final moved = app.study.deck(pageId: app.pageId).single;
    expect(moved.id, isNot(card.id), reason: 'the card was renamed');
    expect(moved.front, card.front, reason: 'but it asks the same question');
    expect(app.study.cardState(moved.id).dueAt, due,
        reason: 'and it must still be scheduled for the same day');
  });

  test('a newly tagged line on the OPEN page becomes a card immediately',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp, app) = await fixture('onote_study_live_', 2);
    addTearDown(() => cleanup(repo, tmp));

    final before = app.study.deck().length;
    final b = app.blocks.first;
    b.content['text'] = '${b.content['text']}\nPerf — how fast it feels.';
    NoteTag.writeInto(b.content, [
      ...NoteTag.listFrom(b.content),
      NoteTag(kind: TagKind.definition, line: 2),
    ]);
    // Exactly what an edit does — no docRevision bump, no page reload.
    app.markDirty();

    expect(app.study.deck().length, before + 1,
        reason: 'tagging a line has to produce a card there and then');
  });

  test('the deck can be scoped to one page', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp, app) = await fixture('onote_study_scope_', 5);
    addTearDown(() => cleanup(repo, tmp));

    expect(app.study.deck().length, 5);
    expect(app.study.deck(pageId: app.pageId).length, 1);
    final other = app.nodes.firstWhere((n) => n.title == 'Page 3').id;
    expect(app.study.deck(pageId: other).length, 1);
    expect(app.study.deck(pageId: other).first.pageTitle, 'Page 3');
  });

  test('deck counts stay cached across repeated calls', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp, app) = await fixture('onote_study_perf_', 12);
    addTearDown(() => cleanup(repo, tmp));

    // The split cache must not have reintroduced the per-keystroke full read.
    // Asserted by COUNTING page decodes, not by timing them: the wall-clock
    // form (`200 calls < 50ms`) measured how busy the machine was, and CI
    // runners are busy machines. Zero decodes is the claim, on any hardware.
    app.study.deckStats();
    final before = Repository.debugPageDecodes;
    for (var i = 0; i < 200; i++) {
      app.study.deckStats();
    }
    expect(Repository.debugPageDecodes, before,
        reason: 'a warm deckStats must not re-read any page from SQLite');
  });

  test('several scopes in one frame all stay cached', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp, app) = await fixture('onote_study_scopes_', 12);
    addTearDown(() => cleanup(repo, tmp));

    // The deck picker shows this-page / this-section / whole-notebook counts
    // side by side, and grading prunes against the whole notebook while the
    // panel is scoped. A single-slot cache would have those keys evicting each
    // other, so EVERY call would re-read all twelve pages — the cache still
    // nominally present and doing nothing.
    final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section).id;

    // Asserted by COUNTING page decodes, third time lucky. The first form
    // (`300 calls < 50ms`) measured how loaded the machine was; the second
    // (warm 300 < cold 3, a ratio) still lost the race on a fast Mac where
    // the cold pass was 1.3ms and one descheduling of the warm loop outweighed
    // it — CI was red for two days on exactly that. Decode count is the claim
    // itself: a working cache does ZERO further reads, a single-slot cache
    // does hundreds, and neither depends on the clock.
    app.study.deckStats(pageId: app.pageId);
    app.study.deckStats(sectionId: section);
    app.study.deckStats();

    final warmBefore = Repository.debugPageDecodes;
    for (var i = 0; i < 100; i++) {
      app.study.deckStats(pageId: app.pageId);
      app.study.deckStats(sectionId: section);
      app.study.deckStats();
    }
    expect(Repository.debugPageDecodes, warmBefore,
        reason: '300 scoped calls after the cold pass must re-read nothing — '
            'a single-slot cache would evict on every scope change');
  });

  // ── Study stats and the exam countdown (P1) ────────────────────────────

  test('grading records the day, and a streak starts at one', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp, app) = await fixture('onote_study_today_', 3);
    addTearDown(() => cleanup(repo, tmp));

    expect(app.study.hasStudyHistory, isFalse);
    expect(app.study.reviewsToday(), 0);
    expect(app.study.studyStreakDays(), 0);

    app.study.gradeCard(app.study.deck().first.id, Grade.good);
    expect(app.study.reviewsToday(), 1);
    expect(app.study.studyStreakDays(), 1);
    expect(app.study.hasStudyHistory, isTrue);
    expect(app.study.studyActivity().last, 1, reason: 'today is the last bar');
  });

  // The placement decision in `gradeCard`, pinned: the tally is taken before
  // the cram-mode early return. An hour of practice the night before an exam
  // is the most studying a student does all term, and it used to leave no
  // trace at all — so the streak would break on the one day it mattered.
  test('practice counts towards the streak without touching the schedule',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp, app) = await fixture('onote_study_cramday_', 3);
    addTearDown(() => cleanup(repo, tmp));

    final card = app.study.deck().first;
    app.study.gradeCard(card.id, Grade.easy);
    final scheduled = app.study.cardState(card.id).dueAt;
    final after = app.study.reviewsToday();

    app.study.gradeCard(card.id, Grade.good, schedule: false);
    expect(app.study.reviewsToday(), after + 1, reason: 'you still did the work');
    expect(app.study.cardState(card.id).dueAt, scheduled,
        reason: 'and practice still must not move the schedule');
  });

  // Asserted against the settings blob rather than by reopening an AppState:
  // the load half lives in `init()`, which registers a post-frame callback and
  // so needs a widgets binding these plain tests deliberately don't build.
  test('the day tally is written to workspace settings', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp, app) = await fixture('onote_study_persist_days_', 3);
    addTearDown(() => cleanup(repo, tmp));

    for (final c in app.study.deck()) {
      app.study.gradeCard(c.id, Grade.good);
    }
    expect(app.study.reviewsToday(), 3);

    final stored = repo.getSetting('studyDays');
    expect(stored, isA<Map>());
    expect((stored as Map)[dayKey(DateTime.now())], 3,
        reason: 'a streak that vanishes when the app restarts is worse than '
            'no streak at all');
  });

  test('an exam date is per section, per notebook, and reversible', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp, app) = await fixture('onote_study_exam_', 3);
    addTearDown(() => cleanup(repo, tmp));

    final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section).id;
    expect(app.study.examDate(section), isNull);

    final exam = DateTime(2026, 12, 1);
    app.study.setExamDate(section, exam);
    expect(app.study.examDate(section), exam);

    // Keyed by notebook: a date set in one must not appear in another, or
    // every notebook shares one exam.
    final other = await repo.createNotebook('Another');
    final previous = app.notebookId;
    app.notebookId = other.id;
    expect(app.study.examDate(section), isNull);
    app.notebookId = previous;
    expect(app.study.examDate(section), exam);

    app.study.setExamDate(section, null);
    expect(app.study.examDate(section), isNull);
  });

  test('the exam plan spreads this deck’s unseen cards over the days left',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp, app) = await fixture('onote_study_plan_', 8);
    addTearDown(() => cleanup(repo, tmp));

    final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section).id;
    final today = DateTime(2026, 8, 4);
    app.study.setExamDate(section, DateTime(2026, 8, 8));

    final plan = app.study.examPlanFor(sectionId: section, now: today)!;
    expect(plan.daysLeft, 4);
    expect(plan.unseen, 8);
    expect(plan.newPerDay, 2);

    // Seeing cards shrinks the ask; it does not shrink the deck.
    for (final c in app.study.deck().take(4)) {
      app.study.gradeCard(c.id, Grade.good);
    }
    final later = app.study.examPlanFor(sectionId: section, now: today)!;
    expect(later.unseen, 4);
    expect(later.total, 8);
    expect(later.newPerDay, 1);
  });

  test('the whole-notebook view names the soonest exam still ahead', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp, app) = await fixture('onote_study_next_exam_', 3);
    addTearDown(() => cleanup(repo, tmp));

    final first = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
    await app.addSection();
    app.reloadNodes();
    final second = app.nodes
        .firstWhere((n) => n.kind == NodeKind.section && n.id != first.id);

    final today = DateTime(2026, 8, 4);
    app.study.setExamDate(first.id, DateTime(2026, 9, 1));
    app.study.setExamDate(second.id, DateTime(2026, 8, 20));
    expect(app.study.nextExam(today)?.section.id, second.id);

    // A date in the past is not "next".
    app.study.setExamDate(second.id, DateTime(2026, 7, 1));
    expect(app.study.nextExam(today)?.section.id, first.id);

    app.study.setExamDate(first.id, null);
    app.study.setExamDate(second.id, null);
    expect(app.study.nextExam(today), isNull);
  });
}
