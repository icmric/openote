// The planner at the state layer: what lands on the agenda, where it came
// from, and what happens when you re-date it.
//
// The three cores (`agenda.dart`, `ics.dart`, `reminders.dart`) are pure and
// tested on their own. This is the seam above them — the part that reads four
// different stores and has to keep them straight — and it pins the things that
// are only wrong once they are joined up:
//
//   1. a due date lost when the line above it gains a newline (tag rebasing
//      rebuilds tags field by field, so a new field is silently dropped);
//   2. a re-date from the planner writing to the wrong tag, because a line can
//      carry several and only one of them holds the date;
//   3. an exam row that cannot find its section again, since a DatedItem has
//      no section field and the id is the only carrier;
//   4. the agenda not noticing a change, which is invisible in a unit test of
//      any single core and immediately obvious to a user.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/model/tags.dart';
import 'package:openote/planner/agenda.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/state/planner_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/study/study_stats.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  /// A notebook with one section and one page carrying two to-do lines.
  Future<(Repository, Directory, AppState, String)> fixture(String name) async {
    final tmp = Directory.systemTemp.createTempSync(name);
    final repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Planner');
    final app = AppState(repo)..notebookId = nb.id;
    app.reloadNodes();
    final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section).id;
    final node = app.importNode(
        nb.id,
        TreeNode(
            kind: NodeKind.page,
            parentId: section,
            title: 'Week 3',
            position: 'a000000000000001'));
    final b = Block(
        type: BlockType.text,
        x: 0,
        y: 0,
        content: {'text': 'Finish tutorial 4\nDraft the report'});
    NoteTag.writeInto(b.content, [
      NoteTag(kind: TagKind.todo, line: 0, checked: false),
      NoteTag(kind: TagKind.todo, line: 1, checked: false),
    ]);
    app.importPage(nb.id, node.id, [b], PageProps());
    app.reloadNodes();
    await app.selectPage(node.id);
    return (repo, tmp, app, section);
  }

  void cleanup(Repository repo, Directory tmp) {
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  }

  // ── Due dates on tags ───────────────────────────────────────────────

  group('a due date on a tag', () {
    test('round-trips through the block envelope', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, _) = await fixture('onote_plan_due_');
      addTearDown(() => cleanup(repo, tmp));

      final block = app.blocks.single;
      expect(app.setTagDue(block.id, 0, TagKind.todo, DateTime(2026, 8, 12)),
          isTrue);

      // Through storage, not just memory: `due` is additive to the tag JSON,
      // and a field that survives in RAM but not through the container would
      // lose every deadline at the next launch.
      await app.flushSave();
      final reread =
          NoteTag.listFrom(app.readPage(app.pageId!).blocks.single.content);
      expect(reread.firstWhere((t) => t.line == 0).due, '2026-08-12');
      // The untouched tag stays untouched — a re-date is one tag, not the line.
      expect(reread.firstWhere((t) => t.line == 1).due, isNull);
    });

    test('is cleared by passing null, not merely left alone', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, _) = await fixture('onote_plan_clear_');
      addTearDown(() => cleanup(repo, tmp));

      final block = app.blocks.single;
      app.setTagDue(block.id, 0, TagKind.todo, DateTime(2026, 8, 12));
      expect(app.setTagDue(block.id, 0, TagKind.todo, null), isTrue);
      expect(NoteTag.listFrom(app.blocks.single.content).first.due, isNull);
    });

    test('reports false when the line carries no such tag', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, _) = await fixture('onote_plan_miss_');
      addTearDown(() => cleanup(repo, tmp));

      final block = app.blocks.single;
      expect(app.setTagDue(block.id, 9, TagKind.todo, DateTime(2026, 8, 12)),
          isFalse);
      expect(app.setTagDue(block.id, 0, TagKind.question, DateTime(2026, 8, 12)),
          isFalse);
    });

    // The bug this pins: `NoteTag.rebase` rebuilds each moved tag from named
    // fields, so a field it does not know about vanishes. Pressing Enter above
    // a dated task would clear its deadline — from a keystroke that changed
    // nothing about the task.
    test('survives a line being inserted above it', () {
      final content = <String, dynamic>{};
      NoteTag.writeInto(content, [
        NoteTag(kind: TagKind.todo, line: 1, checked: false, due: '2026-08-12'),
      ]);
      final moved = NoteTag.rebase(content, 'a\nb', 'a\nNEW\nb');
      expect(moved, {1: 2});
      final after = NoteTag.listFrom(content).single;
      expect(after.line, 2);
      expect(after.due, '2026-08-12', reason: 'the deadline moved with it');
      expect(after.checked, isFalse);
    });

    test('a malformed date is dropped rather than made immortal', () {
      final t = NoteTag.fromJson(
          {'kind': 'todo', 'line': 0, 'due': 'next tuesday'});
      expect(t, isNotNull);
      expect(t!.due, isNull);
      expect(NoteTag.fromJson({'kind': 'todo', 'line': 0, 'due': '2026-02-31'})!.due,
          isNull,
          reason: '31 February is not a date Dart should roll into March');
    });

    test('an undated tag writes no key at all', () {
      final json = NoteTag(kind: TagKind.todo, line: 0).toJson();
      expect(json.containsKey('due'), isFalse);
    });
  });

  // ── The agenda ──────────────────────────────────────────────────────

  group('the agenda', () {
    test('collects exams and dated tasks from where they each live', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, section) = await fixture('onote_plan_agenda_');
      addTearDown(() => cleanup(repo, tmp));

      final today = DateTime(2026, 8, 5);
      app.study.setExamDate(section, DateTime(2026, 8, 19));
      app.setTagDue(app.blocks.single.id, 0, TagKind.todo, today);
      app.planner.reminders.add(
          text: 'Re-read the proof of 2.7',
          at: DateTime(2026, 8, 5, 16),
          id: 'r1');

      final items = app.planner.agenda(now: today);
      expect(items.map((i) => i.kind).toSet(),
          {DatedKind.exam, DatedKind.task, DatedKind.reminder});

      final exam = items.firstWhere((i) => i.kind == DatedKind.exam);
      expect(exam.title, isNotEmpty);
      expect(exam.allDay, isTrue);
      // The exam plan rides along as the second line, which is the whole
      // reason the countdown was worth surfacing.
      expect(exam.subtitle, anyOf(isNull, contains('card')));

      final task = items.firstWhere((i) => i.kind == DatedKind.task);
      expect(task.title, 'Finish tutorial 4');
      expect(task.pageId, app.pageId);
      expect(task.blockId, app.blocks.single.id);
      expect(task.line, 0);

      final rem = items.firstWhere((i) => i.kind == DatedKind.reminder);
      expect(rem.allDay, isFalse, reason: 'a reminder is a time, not a day');
    });

    test('buckets them the way the panel renders them', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, section) = await fixture('onote_plan_bucket_');
      addTearDown(() => cleanup(repo, tmp));

      final today = DateTime(2026, 8, 5);
      app.study.setExamDate(section, DateTime(2026, 8, 19)); // later
      app.setTagDue(app.blocks.single.id, 0, TagKind.todo,
          DateTime(2026, 8, 1)); // overdue
      app.setTagDue(app.blocks.single.id, 1, TagKind.todo, today);

      final sections = app.planner.sections(now: today);
      final buckets = [for (final s in sections) s.bucket];
      expect(buckets.first, AgendaBucket.overdue,
          reason: 'a missed deadline is the first thing you should see');
      expect(buckets, contains(AgendaBucket.today));
      expect(buckets, contains(AgendaBucket.later));
    });

    test('a ticked-off task leaves the deadline buckets', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, _) = await fixture('onote_plan_done_');
      addTearDown(() => cleanup(repo, tmp));

      final today = DateTime(2026, 8, 5);
      final block = app.blocks.single;
      app.setTagDue(block.id, 0, TagKind.todo, DateTime(2026, 8, 1));
      expect(
          app.planner
              .sections(now: today)
              .first
              .bucket,
          AgendaBucket.overdue);

      app.setTagChecked(block.id, 0, true);
      final after = app.planner.sections(now: today);
      expect([for (final s in after) s.bucket], isNot(contains(AgendaBucket.overdue)),
          reason: 'finished work is not a debt');
      expect([for (final s in after) s.bucket], contains(AgendaBucket.done));
    });

    // The cache exists because every planner surface rebuilds on every notify,
    // i.e. on every keystroke — but a cache that does not notice a change is
    // worse than none.
    test('is cached, and the cache lets go when something changes', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, _) = await fixture('onote_plan_cache_');
      addTearDown(() => cleanup(repo, tmp));

      final today = DateTime(2026, 8, 5);
      app.setTagDue(app.blocks.single.id, 0, TagKind.todo, today);
      final a = app.planner.agenda(now: today);
      expect(identical(app.planner.agenda(now: today), a), isTrue);

      app.setTagDue(app.blocks.single.id, 1, TagKind.todo, today);
      final b = app.planner.agenda(now: today);
      expect(identical(b, a), isFalse);
      expect(b.length, a.length + 1);
    });

    test('a reminder added or removed moves the agenda', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, _) = await fixture('onote_plan_remcache_');
      addTearDown(() => cleanup(repo, tmp));

      final today = DateTime(2026, 8, 5);
      expect(app.planner.agenda(now: today), isEmpty);
      app.planner.reminders
          .add(text: 'Call the tutor', at: DateTime(2026, 8, 5, 15), id: 'r1');
      expect(app.planner.agenda(now: today).length, 1);
      app.planner.reminders.remove('r1');
      expect(app.planner.agenda(now: today), isEmpty);
    });

    test('a dismissed reminder is gone from the agenda but kept in the store',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, _) = await fixture('onote_plan_dismiss_');
      addTearDown(() => cleanup(repo, tmp));

      final today = DateTime(2026, 8, 5);
      app.planner.reminders
          .add(text: 'Call the tutor', at: DateTime(2026, 8, 5, 15), id: 'r1');
      app.planner.reminders.dismiss('r1', today);
      expect(app.planner.agenda(now: today), isEmpty);
      expect(app.planner.reminders.byId('r1'), isNotNull,
          reason: 'an accidental dismissal stays recoverable');
    });
  });

  // ── Acting on a row ─────────────────────────────────────────────────

  group('re-dating from the planner', () {
    test('moves an exam, and finds its section again through the id', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, section) = await fixture('onote_plan_redate_ex_');
      addTearDown(() => cleanup(repo, tmp));

      final today = DateTime(2026, 8, 5);
      app.study.setExamDate(section, DateTime(2026, 8, 19));
      final exam = app.planner
          .agenda(now: today)
          .firstWhere((i) => i.kind == DatedKind.exam);
      expect(PlannerState.examSectionOf(exam), section);

      expect(app.planner.redate(exam, DateTime(2026, 8, 21)), isTrue);
      expect(dayKey(app.study.examDate(section)!), '2026-08-21');

      expect(app.planner.redate(exam, null), isTrue);
      expect(app.study.examDate(section), isNull);
    });

    // A line can carry a To Do and an Important; only one of them is dated.
    // The id is what carries which, since DatedItem has no tag-kind field.
    test('moves the right tag when a line carries two', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, _) = await fixture('onote_plan_redate_two_');
      addTearDown(() => cleanup(repo, tmp));

      final block = app.blocks.single;
      NoteTag.writeInto(block.content, [
        ...NoteTag.listFrom(block.content),
        NoteTag(kind: TagKind.important, line: 0),
      ]);
      app.updateBlock(block);
      app.docRevision++;
      app.setTagDue(block.id, 0, TagKind.important, DateTime(2026, 8, 10));

      final today = DateTime(2026, 8, 5);
      final item = app.planner
          .agenda(now: today)
          .firstWhere((i) => i.kind == DatedKind.task);
      expect(PlannerState.taskKindOf(item), TagKind.important);

      expect(app.planner.redate(item, DateTime(2026, 8, 14)), isTrue);
      final tags = NoteTag.listFrom(app.blocks.single.content);
      expect(tags.firstWhere((t) => t.kind == TagKind.important).due,
          '2026-08-14');
      expect(tags.firstWhere((t) => t.kind == TagKind.todo).due, isNull);
    });

    test('a reminder keeps the time of day it was given', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, _) = await fixture('onote_plan_redate_rem_');
      addTearDown(() => cleanup(repo, tmp));

      final today = DateTime(2026, 8, 5);
      app.planner.reminders
          .add(text: 'Proof of 2.7', at: DateTime(2026, 8, 5, 16, 30), id: 'r1');
      final item = app.planner
          .agenda(now: today)
          .firstWhere((i) => i.kind == DatedKind.reminder);

      expect(app.planner.redate(item, DateTime(2026, 8, 9)), isTrue);
      expect(app.planner.reminders.byId('r1')!.at, DateTime(2026, 8, 9, 16, 30),
          reason: 'moving the day must not land it at midnight');
    });

    test('a calendar event refuses, because Openote never writes back',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, _) = await fixture('onote_plan_redate_ics_');
      addTearDown(() => cleanup(repo, tmp));

      final today = DateTime(2026, 8, 5);
      final ics = File('${tmp.path}/t.ics')
        ..writeAsStringSync('BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\n'
            'UID:e1\r\nSUMMARY:Lecture\r\nDTSTART:20260807T140000\r\n'
            'END:VEVENT\r\nEND:VCALENDAR\r\n');
      await app.planner.subscribeCalendar(ics.path);

      final event = app.planner
          .agenda(now: today)
          .firstWhere((i) => i.kind == DatedKind.event);
      expect(app.planner.canRedate(event), isFalse,
          reason: 'the UI must not offer a control that cannot work');
      expect(app.planner.redate(event, DateTime(2026, 8, 20)), isFalse);
      // And it really did not move.
      expect(
          app.planner
              .agenda(now: today)
              .firstWhere((i) => i.kind == DatedKind.event)
              .when,
          DateTime(2026, 8, 7, 14));
    });
  });

  group('the reminder scheduler', () {
    test('catches up on what came due while Openote was closed', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, _) = await fixture('onote_plan_catchup_');
      addTearDown(() => cleanup(repo, tmp));

      // `init` is not run here, so the scheduler has not started: this is the
      // state a fresh launch is in with a reminder already in the past.
      app.planner.reminders.add(
          text: 'Hand in the form',
          at: DateTime.now().subtract(const Duration(hours: 5)),
          id: 'r1');
      app.planner.clearAlerts();

      app.planner.startScheduler();
      expect(app.planner.pendingAlerts.map((r) => r.id), ['r1']);
      expect(app.planner.alertsWereMissed, isTrue,
          reason: 'it says "while you were away" because that is what happened');

      // And it does not fire twice: `markFired` is the contract that survives
      // a restart.
      app.planner.clearAlerts();
      app.planner.startScheduler();
      expect(app.planner.pendingAlerts, isEmpty);
    });

    test('leaves the future alone', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, _) = await fixture('onote_plan_future_');
      addTearDown(() => cleanup(repo, tmp));

      app.planner.reminders.add(
          text: 'Later',
          at: DateTime.now().add(const Duration(days: 2)),
          id: 'r1');
      app.planner.clearAlerts();
      app.planner.startScheduler();
      expect(app.planner.pendingAlerts, isEmpty);
      expect(app.planner.reminders.byId('r1')!.fired, isFalse);
    });
  });

  group('the calendar subscription', () {
    test('reads a local .ics file and puts its events on the agenda', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, _) = await fixture('onote_plan_ics_');
      addTearDown(() => cleanup(repo, tmp));

      final today = DateTime(2026, 8, 5);
      final ics = File('${tmp.path}/timetable.ics')
        ..writeAsStringSync('BEGIN:VCALENDAR\r\n'
            'VERSION:2.0\r\n'
            'X-WR-CALNAME:Semester 2\r\n'
            'BEGIN:VEVENT\r\n'
            'UID:lec-1\r\n'
            'SUMMARY:Discrete Maths lecture\r\n'
            'LOCATION:Hall B\r\n'
            'DTSTART:20260806T090000\r\n'
            'DTEND:20260806T100000\r\n'
            'END:VEVENT\r\n'
            'END:VCALENDAR\r\n');

      await app.planner.subscribeCalendar(ics.path);
      expect(app.planner.calendar?.lastError, isNull);
      expect(app.planner.calendar?.name, 'Semester 2');

      final events = [
        for (final i in app.planner.agenda(now: today))
          if (i.kind == DatedKind.event) i
      ];
      expect(events.single.title, 'Discrete Maths lecture');
      expect(events.single.subtitle, contains('Hall B'));
      expect(events.single.when, DateTime(2026, 8, 6, 9));

      // Removing it takes the events with it — the agenda is a lens.
      app.planner.unsubscribeCalendar();
      expect(app.planner.agenda(now: today), isEmpty);
    });

    test('a page of HTML is refused rather than cached as an empty calendar',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, _) = await fixture('onote_plan_ics_html_');
      addTearDown(() => cleanup(repo, tmp));

      final bad = File('${tmp.path}/login.html')
        ..writeAsStringSync('<html><body>Please sign in</body></html>');
      await app.planner.subscribeCalendar(bad.path);
      expect(app.planner.calendar?.lastError, isNotNull,
          reason: 'a login page returns 200 and would show an empty timetable');
    });

    test('a fetch failure keeps the copy already cached', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, _) = await fixture('onote_plan_ics_offline_');
      addTearDown(() => cleanup(repo, tmp));

      final today = DateTime(2026, 8, 5);
      final ics = File('${tmp.path}/t.ics')
        ..writeAsStringSync('BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\n'
            'UID:e1\r\nSUMMARY:Tutorial\r\nDTSTART:20260807T140000\r\n'
            'END:VEVENT\r\nEND:VCALENDAR\r\n');
      await app.planner.subscribeCalendar(ics.path);
      expect(app.planner.agenda(now: today).length, 1);

      ics.deleteSync();
      await app.planner.refreshCalendar();
      expect(app.planner.calendar?.lastError, isNotNull);
      expect(app.planner.agenda(now: today).length, 1,
          reason: 'a student on a train must not lose their timetable');
    });
  });
}
