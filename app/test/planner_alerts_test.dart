// Alerts: dismissal, event alerts, and the classifier behind them (v0.8).
//
// Two of these cover reported bugs and were written to fail against the code as
// it shipped:
//
//   1. "Done" did not dismiss. `clearAlerts` emptied the on-screen list and
//      left every reminder live, so the badge stayed lit and the row stayed in
//      the agenda. These assert the *store* state, not the banner, because the
//      banner was never the thing that was wrong.
//   2. There was no way to be finished with a reminder — covered by asserting
//      the reminder leaves the agenda afterwards.
//
// The pure halves (classification, join links, rule round-tripping) need no
// database and are grouped first so they still run where sqlite is missing.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/planner/alerts.dart';
import 'package:openote/planner/event_kinds.dart';
import 'package:openote/planner/ics.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

IcsEvent ev(
  String summary, {
  String location = '',
  String description = '',
  String url = '',
}) =>
    IcsEvent(
      uid: 'u',
      summary: summary,
      location: location,
      description: description,
      url: url,
      start: DateTime(2026, 8, 5, 9),
    );

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Future<(Repository, Directory, AppState)> fixture(String name) async {
    final tmp = Directory.systemTemp.createTempSync(name);
    final repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Planner');
    final app = AppState(repo)..notebookId = nb.id;
    app.reloadNodes();
    return (repo, tmp, app);
  }

  void cleanup(Repository repo, Directory tmp) {
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  }

  /// A one-event feed starting [minutes] from now, written to a temp file.
  String feedFile(Directory tmp, String summary, int minutes, {String? url}) {
    final start = DateTime.now().add(Duration(minutes: minutes));
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${start.year}${two(start.month)}${two(start.day)}'
        'T${two(start.hour)}${two(start.minute)}00';
    final path = '${tmp.path}/feed${summary.hashCode}.ics';
    File(path).writeAsStringSync('BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:e1\r\n'
        'SUMMARY:$summary\r\nDTSTART:$stamp\r\n'
        '${url == null ? '' : 'URL:$url\r\n'}'
        'END:VEVENT\r\nEND:VCALENDAR\r\n');
    return path;
  }

  // ── Pure: classification ─────────────────────────────────────────────

  group('classifying an event', () {
    test('reads the activity type out of a timetable summary', () {
      expect(classifyEvent(ev('31251 Programming Fundamentals - Lecture')),
          EventKind.lecture);
      expect(
          classifyEvent(ev('41039 Networking, Tutorial')), EventKind.tutorial);
      expect(classifyEvent(ev('Chemistry 1A Lab (Bldg 4)')), EventKind.lab);
      expect(classifyEvent(ev('Design Studio 2')), EventKind.workshop);
    });

    test('an exam beats the room it is held in', () {
      // The whole reason the keyword list is ordered rather than a map.
      expect(
          classifyEvent(ev('Final Exam — Lecture Theatre 2')), EventKind.exam);
    });

    test('matches whole words, so it does not see types that are not there',
        () {
      // Substring matching found 'lab' in Syllabus and 'lec' in Electronics.
      expect(classifyEvent(ev('Syllabus review')), isNot(EventKind.lab));
      expect(classifyEvent(ev('Electronics I')), isNot(EventKind.lecture));
      expect(classifyEvent(ev('Institute open day')), isNot(EventKind.tutorial));
    });

    test('falls back to the description, then to other', () {
      expect(classifyEvent(ev('COMP1000', description: 'Weekly lecture')),
          EventKind.lecture);
      expect(classifyEvent(ev('Coffee with Sam')), EventKind.other);
    });

    test('the location is not searched — a tutorial can be in a theatre', () {
      expect(classifyEvent(ev('COMP1000 Tut', location: 'Lecture Theatre 1')),
          EventKind.tutorial);
    });
  });

  group('finding the join link', () {
    test('recognises the usual providers wherever they are', () {
      expect(
          joinLink(ev('L', url: 'https://uts.zoom.us/j/123'))?.provider, 'Zoom');
      expect(
          joinLink(ev('L', location: 'https://teams.microsoft.com/l/x'))
              ?.provider,
          'Teams');
      expect(
          joinLink(ev('L', description: 'Join at https://meet.google.com/abc-d'))
              ?.provider,
          'Meet');
    });

    test('a known provider beats an unknown link found earlier', () {
      final link = joinLink(ev('L',
          url: 'https://canvas.uts.edu.au/courses/1',
          description: 'Zoom: https://uts.zoom.us/j/9'));
      expect(link?.provider, 'Zoom');
    });

    test('a bare link in a description is not offered as "join"', () {
      // It is overwhelmingly the unit outline or a reading list, and a Join
      // button that opens the reading list is worse than no button at all.
      expect(joinLink(ev('L', description: 'Readings: https://example.com/x')),
          isNull);
    });

    test('trailing punctuation is not part of the URL', () {
      expect(joinLink(ev('L', description: 'see https://zoom.us/j/12.'))?.url,
          'https://zoom.us/j/12');
    });

    test('no link at all is null, not an empty string', () {
      expect(joinLink(ev('L', location: 'Building 11, Room 4.02')), isNull);
    });
  });

  group('alert rules', () {
    test('unknown kinds are dropped, not fatal', () {
      final rules = EventAlertRules.fromJson(
          {'lecture': 10, 'holodeck': 5, 'lab': 'nonsense'});
      expect(rules.leadFor(EventKind.lecture), 10);
      expect(rules.leadFor(EventKind.lab), isNull);
      expect(rules.maxLead, 10);
    });

    test('the default is silence', () {
      expect(EventAlertRules.fromJson(null).isEmpty, isTrue);
    });

    test('the "before classes" preset leaves exams alone', () {
      // A ten-minute warning for an exam is not a useful thing to be told.
      expect(EventAlertRules.beforeClasses.leadFor(EventKind.exam), isNull);
      expect(EventAlertRules.beforeClasses.leadFor(EventKind.lecture), 10);
    });
  });

  // ── Stateful: dismissal ──────────────────────────────────────────────

  group('dismissing an alert', () {
    test('Done dismisses the reminder, it does not merely hide the banner',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app) = await fixture('onote_alert_done_');
      addTearDown(() => cleanup(repo, tmp));

      final r = app.planner.reminders.add(
          text: 'Email the tutor',
          at: DateTime.now().subtract(const Duration(minutes: 5)));
      app.planner.startScheduler();
      expect(app.planner.pendingAlerts.map((a) => a.id), [r.id]);

      app.planner.dismissAlert(r.id);

      expect(app.planner.pendingAlerts, isEmpty);
      // The half that was broken: the reminder itself.
      expect(app.planner.reminders.byId(r.id)!.dismissed, isTrue,
          reason: 'Done must resolve the reminder, not just clear the list');
      // And so it leaves the agenda, which is where the user saw it linger.
      expect(app.planner.agenda().where((i) => i.title == 'Email the tutor'),
          isEmpty);
    });

    test('dismiss all resolves every reminder it was showing', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app) = await fixture('onote_alert_all_');
      addTearDown(() => cleanup(repo, tmp));
      final past = DateTime.now().subtract(const Duration(minutes: 5));
      final a = app.planner.reminders.add(text: 'One', at: past);
      final b = app.planner.reminders.add(text: 'Two', at: past);
      app.planner.startScheduler();
      expect(app.planner.pendingAlerts, hasLength(2));

      app.planner.dismissAllAlerts();

      expect(app.planner.reminders.byId(a.id)!.dismissed, isTrue);
      expect(app.planner.reminders.byId(b.id)!.dismissed, isTrue);
      expect(app.planner.pendingAlerts, isEmpty);
    });

    test('clearAlerts still only hides — the two are different promises',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app) = await fixture('onote_alert_clear_');
      addTearDown(() => cleanup(repo, tmp));
      final r = app.planner.reminders.add(
          text: 'Still mine',
          at: DateTime.now().subtract(const Duration(minutes: 5)));
      app.planner.startScheduler();

      app.planner.clearAlerts();

      expect(app.planner.pendingAlerts, isEmpty);
      expect(app.planner.reminders.byId(r.id)!.dismissed, isFalse);
    });

    test('snoozing moves the reminder rather than dropping it', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app) = await fixture('onote_alert_snooze_');
      addTearDown(() => cleanup(repo, tmp));
      final now = DateTime.now();
      final r = app.planner.reminders
          .add(text: 'Later', at: now.subtract(const Duration(minutes: 5)));
      app.planner.startScheduler();

      app.planner.snoozeAlert(r.id, const Duration(minutes: 10), now);

      expect(app.planner.pendingAlerts, isEmpty);
      final after = app.planner.reminders.byId(r.id)!;
      expect(after.dismissed, isFalse);
      // Measured from now, not from when it was originally due.
      expect(after.at.isAfter(now.add(const Duration(minutes: 9))), isTrue);
    });
  });

  // ── Stateful: event alerts ───────────────────────────────────────────
  //
  // Rules are set BEFORE the calendar is subscribed throughout. The setter
  // marks everything already inside its alert window as seen, so setting them
  // after would (correctly) suppress the very thing under test.

  group('event alerts', () {
    test('nothing fires while the rules are empty', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app) = await fixture('onote_ev_off_');
      addTearDown(() => cleanup(repo, tmp));
      await app.planner
          .subscribeCalendar(feedFile(tmp, 'COMP1 Lecture', 5));
      expect(app.planner.dueEventAlerts(DateTime.now()), isEmpty);
    });

    test('a lecture inside its lead time is due, with the join link on it',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app) = await fixture('onote_ev_due_');
      addTearDown(() => cleanup(repo, tmp));
      app.planner.eventAlerts = EventAlertRules.beforeClasses;
      await app.planner.subscribeCalendar(
          feedFile(tmp, 'COMP1 Lecture', 5, url: 'https://uts.zoom.us/j/1'));

      final due = app.planner.dueEventAlerts(DateTime.now());
      expect(due, hasLength(1));
      expect(due.single.source, AlertSource.event);
      expect(due.single.kind, EventKind.lecture);
      expect(due.single.join?.provider, 'Zoom');
    });

    test('a kind with no rule stays quiet', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app) = await fixture('onote_ev_exam_');
      addTearDown(() => cleanup(repo, tmp));
      app.planner.eventAlerts = EventAlertRules.beforeClasses;
      await app.planner.subscribeCalendar(feedFile(tmp, 'Final Exam', 5));
      expect(app.planner.dueEventAlerts(DateTime.now()), isEmpty);
    });

    test('an event further out than its lead time is not due yet', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app) = await fixture('onote_ev_far_');
      addTearDown(() => cleanup(repo, tmp));
      app.planner.eventAlerts = EventAlertRules.beforeClasses;
      await app.planner.subscribeCalendar(feedFile(tmp, 'COMP1 Lecture', 45));
      expect(app.planner.dueEventAlerts(DateTime.now()), isEmpty);
    });

    test('turning the rules on does not itself fire a burst', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app) = await fixture('onote_ev_burst_');
      addTearDown(() => cleanup(repo, tmp));
      await app.planner.subscribeCalendar(feedFile(tmp, 'COMP1 Lecture', 5));

      // Rules set AFTER the feed is loaded: "from now on" must not mean "and
      // also everything already in progress".
      app.planner.eventAlerts = EventAlertRules.beforeClasses;

      expect(app.planner.dueEventAlerts(DateTime.now()), isEmpty);
    });

    test('asking what is due has no side effects', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app) = await fixture('onote_ev_pure_');
      addTearDown(() => cleanup(repo, tmp));
      app.planner.eventAlerts = EventAlertRules.beforeClasses;
      await app.planner.subscribeCalendar(feedFile(tmp, 'COMP1 Lecture', 5));

      expect(app.planner.dueEventAlerts(DateTime.now()), hasLength(1));
      expect(app.planner.dueEventAlerts(DateTime.now()), hasLength(1));
    });

    test('an all-day row never produces a "starts in ten minutes"', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app) = await fixture('onote_ev_allday_');
      addTearDown(() => cleanup(repo, tmp));
      app.planner.eventAlerts = EventAlertRules.beforeClasses;
      final d = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final path = '${tmp.path}/allday.ics';
      File(path).writeAsStringSync(
          'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:a1\r\n'
          'SUMMARY:Lecture week begins\r\n'
          'DTSTART;VALUE=DATE:${d.year}${two(d.month)}${two(d.day)}\r\n'
          'END:VEVENT\r\nEND:VCALENDAR\r\n');
      await app.planner.subscribeCalendar(path);
      expect(app.planner.dueEventAlerts(DateTime.now()), isEmpty);
    });

    test('up next names the next timed event', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app) = await fixture('onote_ev_next_');
      addTearDown(() => cleanup(repo, tmp));
      await app.planner.subscribeCalendar(feedFile(tmp, 'COMP1 Lecture', 90));
      expect(app.planner.nextEvent()?.summary, 'COMP1 Lecture');
      expect(app.planner.currentEvent(), isNull);
    });
  });

  // ── Exam times ───────────────────────────────────────────────────────

  group('an exam can carry a time', () {
    test('the agenda row becomes timed rather than all-day', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app) = await fixture('onote_exam_time_');
      addTearDown(() => cleanup(repo, tmp));
      final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section).id;
      final day = DateTime.now().add(const Duration(days: 10));

      app.study.setExamDate(section, day);
      expect(app.planner.agenda().singleWhere((i) => i.id.startsWith('exam:'))
          .allDay, isTrue);

      app.study.setExamTime(section, 9 * 60 + 30);
      final row =
          app.planner.agenda().singleWhere((i) => i.id.startsWith('exam:'));
      expect(row.allDay, isFalse);
      expect(row.when.hour, 9);
      expect(row.when.minute, 30);
    });

    test('the countdown still works in whole days', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app) = await fixture('onote_exam_days_');
      addTearDown(() => cleanup(repo, tmp));
      final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section).id;
      final day = DateTime.now().add(const Duration(days: 10));
      app.study.setExamDate(section, day);
      app.study.setExamTime(section, 9 * 60);

      // `examDate` is the day-arithmetic accessor and must stay at midnight.
      expect(app.study.examDate(section)!.hour, 0);
      expect(app.study.examAt(section)!.hour, 9);
    });

    test('clearing the date takes the time with it', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app) = await fixture('onote_exam_clear_');
      addTearDown(() => cleanup(repo, tmp));
      final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section).id;
      app.study.setExamDate(section, DateTime.now().add(const Duration(days: 3)));
      app.study.setExamTime(section, 14 * 60);

      app.study.setExamDate(section, null);
      app.study.setExamDate(section, DateTime.now().add(const Duration(days: 3)));

      expect(app.study.examMinuteOfDay(section), isNull,
          reason: 'a stale time must not reappear on a freshly set date');
    });

    test('a time cannot be set on a section with no exam date', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app) = await fixture('onote_exam_orphan_');
      addTearDown(() => cleanup(repo, tmp));
      final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section).id;
      app.study.setExamTime(section, 10 * 60);
      expect(app.study.examMinuteOfDay(section), isNull);
    });
  });
}
