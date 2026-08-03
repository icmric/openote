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

    final card = app.deck().first;
    app.gradeCard(card.id, Grade.again);
    // The old behaviour scheduled it for tomorrow, so it disappeared from the
    // deck entirely and "let me try that one again" was impossible.
    final s = app.cardState(card.id);
    expect(s.dueAt - nowMs(), lessThan(3600000));
  });

  test('practice ignores the schedule and does not overwrite it', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp, app) = await fixture('onote_study_cram_', 4);
    addTearDown(() => cleanup(repo, tmp));

    for (final c in app.deck()) {
      app.gradeCard(c.id, Grade.easy);
    }
    expect(app.sessionCards().length, 0, reason: 'everything is scheduled out');

    final practice = app.sessionCards(mode: StudyMode.cram);
    expect(practice.length, 4, reason: 'practice ignores the schedule');

    final before = app.cardState(practice.first.id).dueAt;
    app.gradeCard(practice.first.id, Grade.good, schedule: false);
    expect(app.cardState(practice.first.id).dueAt, before,
        reason: 'a night of cramming must not wipe weeks of spacing');

    // Getting one WRONG is information about the card whatever the mode.
    app.gradeCard(practice.first.id, Grade.again, schedule: false);
    expect(app.cardState(practice.first.id).dueAt, lessThan(before));
  });

  test('deckStats says when the next card is due', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp, app) = await fixture('onote_study_stats_', 3);
    addTearDown(() => cleanup(repo, tmp));

    expect(app.deckStats().unseen, 3);
    for (final c in app.deck()) {
      app.gradeCard(c.id, Grade.easy);
    }
    final s = app.deckStats();
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

    for (final c in app.deck()) {
      app.gradeCard(c.id, Grade.easy);
    }
    expect(app.resetDeck(), 3);
    expect(app.deckStats().due, 3);
    expect(app.deckStats().unseen, 3);
  });

  test('reading a schedule does not create one', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp, app) = await fixture('onote_study_read_', 3);
    addTearDown(() => cleanup(repo, tmp));

    for (final c in app.deck()) {
      app.cardState(c.id);
    }
    // Grade exactly one card; only that one may be persisted.
    app.gradeCard(app.deck().first.id, Grade.good);
    final stored = repo.getSetting('cardStates') as Map?;
    expect(stored, isNotNull);
    expect(stored!.length, 1,
        reason: 'merely looking at a card must not persist a schedule');
  });

  test('a newly tagged line on the OPEN page becomes a card immediately',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp, app) = await fixture('onote_study_live_', 2);
    addTearDown(() => cleanup(repo, tmp));

    final before = app.deck().length;
    final b = app.blocks.first;
    b.content['text'] = '${b.content['text']}\nPerf — how fast it feels.';
    NoteTag.writeInto(b.content, [
      ...NoteTag.listFrom(b.content),
      NoteTag(kind: TagKind.definition, line: 2),
    ]);
    // Exactly what an edit does — no docRevision bump, no page reload.
    app.markDirty();

    expect(app.deck().length, before + 1,
        reason: 'tagging a line has to produce a card there and then');
  });

  test('the deck can be scoped to one page', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp, app) = await fixture('onote_study_scope_', 5);
    addTearDown(() => cleanup(repo, tmp));

    expect(app.deck().length, 5);
    expect(app.deck(pageId: app.pageId).length, 1);
    final other = app.nodes.firstWhere((n) => n.title == 'Page 3').id;
    expect(app.deck(pageId: other).length, 1);
    expect(app.deck(pageId: other).first.pageTitle, 'Page 3');
  });

  test('deck counts stay cached across repeated calls', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp, app) = await fixture('onote_study_perf_', 12);
    addTearDown(() => cleanup(repo, tmp));

    // The split cache must not have reintroduced the per-keystroke full read.
    app.deckStats();
    final sw = Stopwatch()..start();
    for (var i = 0; i < 200; i++) {
      app.deckStats();
    }
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(50),
        reason: '200 deckStats calls took ${sw.elapsedMilliseconds}ms');
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
    for (var i = 0; i < 3; i++) {
      app.deckStats(pageId: app.pageId);
      app.deckStats(sectionId: section);
      app.deckStats();
    }
    final sw = Stopwatch()..start();
    for (var i = 0; i < 100; i++) {
      app.deckStats(pageId: app.pageId);
      app.deckStats(sectionId: section);
      app.deckStats();
    }
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(50),
        reason: '300 mixed-scope calls took ${sw.elapsedMilliseconds}ms');
  });
}
