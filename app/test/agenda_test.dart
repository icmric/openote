// The planner's agenda (v0.5 stage 1) — the pure model.
//
// "now" is an argument everywhere, so these tests pin real behaviour instead of
// whatever the calendar says when CI runs. Three rules here are invisible on the
// day you write them and expensive to get wrong, and each has a test that fails
// loudly if it is broken:
//
//   1. An all-day item is overdue only once its DAY has passed. Comparing
//      instants instead marks today's exam overdue from 00:01.
//   2. Day distances are calendar days, not elapsed hours. Anything built on
//      `difference().inDays` reports "tomorrow" as "today" whenever the gap is
//      under 24 hours — every afternoon, and twice a year even at midnight.
//   3. Ties sort stably. Dart's List.sort is not stable, so equal instants with
//      equal titles can swap between rebuilds and flicker under the cursor.
//
// No SQLite and no widgets, so this file runs on a bare checkout.

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/planner/agenda.dart';

/// Terse builder — every test cares about two or three fields at most, and the
/// noise of a full constructor call hides which one is under test.
DatedItem item(
  DateTime when, {
  String id = 'x',
  String title = 'thing',
  DatedKind kind = DatedKind.task,
  bool allDay = true,
  bool done = false,
}) =>
    DatedItem(
      id: id,
      kind: kind,
      title: title,
      when: when,
      allDay: allDay,
      done: done,
    );

void main() {
  // A fixed "now": mid-afternoon, so both "earlier today" and "later today"
  // exist and the all-day rules can be probed on either side of it.
  final now = DateTime(2026, 8, 4, 15, 30);

  group('bucketFor — all-day items', () {
    // The rule this exists for: an exam is today's exam all day. Bucketing on
    // the instant would put a 09:00 exam in OVERDUE by 09:01, and the one
    // heading that means "you are late" would be shouting about an exam the
    // student is sitting.
    test('an exam earlier today is today, not overdue', () {
      expect(bucketFor(item(DateTime(2026, 8, 4, 0, 1)), now), AgendaBucket.today);
      expect(bucketFor(item(DateTime(2026, 8, 4, 9)), now), AgendaBucket.today);
      expect(bucketFor(item(DateTime(2026, 8, 4, 23, 59)), now), AgendaBucket.today);
    });

    test('stays today right up to the last minute of the day', () {
      final lateNow = DateTime(2026, 8, 4, 23, 59, 59);
      expect(bucketFor(item(DateTime(2026, 8, 4)), lateNow), AgendaBucket.today);
    });

    test('is overdue only once the whole day has passed', () {
      final justAfterMidnight = DateTime(2026, 8, 5, 0, 0, 1);
      expect(bucketFor(item(DateTime(2026, 8, 4, 23, 59)), justAfterMidnight),
          AgendaBucket.overdue,
          reason: 'yesterday, by one second');
      expect(bucketFor(item(DateTime(2026, 7, 30)), now), AgendaBucket.overdue);
    });

    // A due date carried as "the tag was written at 09:00 on the 6th" must not
    // bucket differently from one carried as local midnight on the 6th.
    test('ignores the time component entirely', () {
      for (final t in [0, 9, 23]) {
        expect(bucketFor(item(DateTime(2026, 8, 6, t)), now), AgendaBucket.thisWeek,
            reason: 'hour $t is still the 6th');
      }
    });
  });

  group('bucketFor — timed items', () {
    test('is overdue the moment its instant passes', () {
      expect(bucketFor(item(DateTime(2026, 8, 4, 15, 29), allDay: false), now),
          AgendaBucket.overdue);
    });

    test('is today while it is still ahead', () {
      expect(bucketFor(item(DateTime(2026, 8, 4, 15, 31), allDay: false), now),
          AgendaBucket.today);
    });

    // Strictly ahead-of-now, so a reminder does not render as late in the same
    // frame that it fires.
    test('is not yet overdue at exactly now', () {
      expect(bucketFor(item(now, allDay: false), now), AgendaBucket.today);
    });

    test('an early-morning time tomorrow is tomorrow, not overdue', () {
      expect(bucketFor(item(DateTime(2026, 8, 5, 6), allDay: false), now),
          AgendaBucket.tomorrow);
    });
  });

  group('bucketFor — day distances', () {
    // The bug: `item.when.difference(now).inDays` is 0 for anything less than
    // 24 hours away, so every afternoon "tomorrow morning" reads as "today".
    // This fails in any timezone if the day arithmetic is done on durations.
    test('tomorrow is tomorrow even when it is 9 hours away', () {
      expect(bucketFor(item(DateTime(2026, 8, 5)), now), AgendaBucket.tomorrow);
      expect(bucketFor(item(DateTime(2026, 8, 5, 0, 30), allDay: false), now),
          AgendaBucket.tomorrow);
    });

    test('this week is days two to seven, and day eight is later', () {
      expect(bucketFor(item(DateTime(2026, 8, 6)), now), AgendaBucket.thisWeek);
      expect(bucketFor(item(DateTime(2026, 8, 11)), now), AgendaBucket.thisWeek,
          reason: 'seven days out is still within the next seven days');
      expect(bucketFor(item(DateTime(2026, 8, 12)), now), AgendaBucket.later,
          reason: 'eight days out is not');
    });

    // Guards the UTC normalisation in daysBetween. A local-time subtraction
    // makes a spring-forward day 23 hours and an autumn-back day 25, so the
    // day after a transition lands one bucket out for anyone in that timezone
    // on exactly one day a year — a class of bug that never reproduces for the
    // person who wrote it.
    test('survives a daylight-saving transition', () {
      for (final d in [
        DateTime(2026, 3, 8), // US spring forward
        DateTime(2026, 4, 5), // AU autumn back
        DateTime(2026, 10, 4), // AU spring forward
        DateTime(2026, 10, 25), // EU autumn back
      ]) {
        final at = DateTime(d.year, d.month, d.day, 12);
        expect(bucketFor(item(d), at), AgendaBucket.today, reason: 'on $d');
        expect(bucketFor(item(DateTime(d.year, d.month, d.day + 1)), at),
            AgendaBucket.tomorrow,
            reason: 'the day after $d');
      }
    });

    test('crosses month and year boundaries', () {
      expect(bucketFor(item(DateTime(2026, 9, 1)), DateTime(2026, 8, 31, 10)),
          AgendaBucket.tomorrow);
      expect(bucketFor(item(DateTime(2027, 1, 1)), DateTime(2026, 12, 31, 10)),
          AgendaBucket.tomorrow);
    });
  });

  group('bucketFor — done', () {
    // A finished task is history, not a debt. If done items could land in
    // OVERDUE, the one heading that means "act on this" fills with work that is
    // already finished, and a nag list that is mostly noise gets ignored whole.
    test('overrides every date, past and future', () {
      for (final when in [
        DateTime(2026, 1, 1),
        DateTime(2026, 8, 4, 9),
        now,
        DateTime(2026, 8, 5),
        DateTime(2027, 3, 3),
      ]) {
        expect(bucketFor(item(when, done: true), now), AgendaBucket.done,
            reason: '$when');
        expect(bucketFor(item(when, done: true, allDay: false), now),
            AgendaBucket.done,
            reason: '$when, timed');
      }
    });
  });

  group('groupAgenda', () {
    test('is empty for no items, rather than six empty headings', () {
      expect(groupAgenda(const [], now), isEmpty);
    });

    // A panel that always shows six headings tells a student with two tasks
    // that they have four kinds of nothing, and pushes the rows that matter
    // below the fold.
    test('omits empty buckets and keeps display order', () {
      final sections = groupAgenda([
        item(DateTime(2027, 1, 1), id: 'later'),
        item(DateTime(2026, 8, 1), id: 'late'),
        item(DateTime(2026, 8, 4), id: 'now'),
      ], now);
      expect(sections.map((s) => s.bucket),
          [AgendaBucket.overdue, AgendaBucket.today, AgendaBucket.later],
          reason: 'tomorrow and this week had nothing in them');
    });

    test('orders every bucket that is present the way the panel reads', () {
      final sections = groupAgenda([
        item(DateTime(2026, 8, 4, 12), id: 'done', done: true),
        item(DateTime(2027, 1, 1), id: 'later'),
        item(DateTime(2026, 8, 8), id: 'week'),
        item(DateTime(2026, 8, 5), id: 'tomorrow'),
        item(DateTime(2026, 8, 4), id: 'today'),
        item(DateTime(2026, 8, 3), id: 'overdue'),
      ], now);
      expect(sections.map((s) => s.bucket), AgendaBucket.values);
    });

    test('sorts a bucket by when, ascending', () {
      final sections = groupAgenda([
        item(DateTime(2026, 8, 9), id: 'c'),
        item(DateTime(2026, 8, 6), id: 'a'),
        item(DateTime(2026, 8, 7), id: 'b'),
      ], now);
      expect(sections.single.items.map((i) => i.id), ['a', 'b', 'c']);
    });

    test('breaks a tie on when with the title', () {
      final at = DateTime(2026, 8, 6);
      final sections = groupAgenda([
        item(at, id: 'z', title: 'Zoology revision'),
        item(at, id: 'a', title: 'algebra sheet'),
      ], now);
      expect(sections.single.items.map((i) => i.id), ['a', 'z'],
          reason: 'code-unit order would put every capital before every '
              'lowercase, so "Zoology" would sort above "algebra"');
    });

    // Dart's List.sort is not stable. Without an explicit index tiebreak, two
    // rows with the same instant and the same text can swap places between two
    // rebuilds of identical data, so the list flickers under the cursor and a
    // click can land on the wrong note.
    // Forty rows, and that number is load-bearing: Dart's sort falls back to
    // insertion sort under about thirty-three elements, so a five-item version
    // of this test passes even with the tiebreak deleted and proves nothing.
    test('keeps input order for items equal on when and title', () {
      final at = DateTime(2026, 8, 6);
      final input = [
        for (var i = 0; i < 40; i++) item(at, id: 'id$i', title: 'same')
      ];
      final ids = groupAgenda(input, now).single.items.map((i) => i.id).toList();
      expect(ids, [for (var i = 0; i < 40; i++) 'id$i']);
      expect(groupAgenda(input, now).single.items.map((i) => i.id), ids,
          reason: 'and it is the same order every time it is asked');
    });

    test('loses no items and duplicates none', () {
      final input = [
        item(DateTime(2026, 8, 1), id: 'a'),
        item(DateTime(2026, 8, 4), id: 'b'),
        item(DateTime(2026, 8, 4), id: 'c', done: true),
        item(DateTime(2026, 8, 5), id: 'd'),
        item(DateTime(2026, 8, 30), id: 'e'),
      ];
      final flat = [
        for (final s in groupAgenda(input, now)) ...s.items.map((i) => i.id)
      ];
      expect(flat..sort(), ['a', 'b', 'c', 'd', 'e']);
    });

    test('does not reorder or mutate the caller list', () {
      final input = [
        item(DateTime(2026, 8, 9), id: 'c'),
        item(DateTime(2026, 8, 6), id: 'a'),
      ];
      groupAgenda(input, now);
      expect(input.map((i) => i.id), ['c', 'a']);
    });
  });

  group('relativeWhen', () {
    test('says the day the way a student would', () {
      expect(relativeWhen(item(DateTime(2026, 8, 4)), now), 'today');
      expect(relativeWhen(item(DateTime(2026, 8, 5)), now), 'tomorrow');
      expect(relativeWhen(item(DateTime(2026, 8, 7)), now), 'in 3 days');
      expect(relativeWhen(item(DateTime(2026, 8, 3)), now), 'yesterday');
      expect(relativeWhen(item(DateTime(2026, 8, 2)), now), '2 days ago');
    });

    // formatCountdown collapses anything older than a fortnight to "passed",
    // which it can afford because the exam date is printed beside it. An
    // overdue planner row has no date beside it, and "26 days ago" versus
    // "yesterday" is the difference between abandoning a task and doing it
    // tonight.
    test('does not give up on distant dates', () {
      expect(relativeWhen(item(DateTime(2026, 7, 9)), now), '26 days ago');
      expect(relativeWhen(item(DateTime(2026, 11, 4)), now), 'in 92 days');
    });

    test('gives a timed item today its clock time instead of "today"', () {
      expect(relativeWhen(item(DateTime(2026, 8, 4, 16, 30), allDay: false), now),
          '4:30pm');
      expect(relativeWhen(item(DateTime(2026, 8, 4, 9), allDay: false), now), '9am');
    });

    // "4pm" under a LATER heading says nothing about which day; the day is the
    // information there, and a caller that wants both composes it from
    // formatClock.
    test('keeps day phrasing for timed items on other days', () {
      expect(relativeWhen(item(DateTime(2026, 8, 5, 16, 30), allDay: false), now),
          'tomorrow');
      expect(relativeWhen(item(DateTime(2026, 8, 3, 16, 30), allDay: false), now),
          'yesterday');
    });

    // The pairing, not either half: a timed item earlier today is OVERDUE, and
    // its label is still a bare clock time. Both halves are defensible alone
    // and the combination is what the panel actually renders, so pin it — the
    // failure mode is a later change "fixing" the label to "today" or "0 days
    // ago" under a heading that already says OVERDUE, where the clock time is
    // the only thing that identifies which of today's items was missed.
    test('a timed item that has already passed today keeps its clock time '
        'under the overdue heading', () {
      final missed = item(DateTime(2026, 8, 4, 9), allDay: false);
      expect(bucketFor(missed, now), AgendaBucket.overdue);
      expect(relativeWhen(missed, now), '9am');
    });

    test('an all-day item today says today, whatever time it carries', () {
      expect(relativeWhen(item(DateTime(2026, 8, 4, 16, 30)), now), 'today');
    });
  });

  group('formatClock', () {
    test('drops the minutes on the hour and the leading zero from the hour', () {
      expect(formatClock(DateTime(2026, 8, 4, 16)), '4pm');
      expect(formatClock(DateTime(2026, 8, 4, 9, 5)), '9:05am');
    });

    test('gets the two hours that are neither 0 nor 12 right', () {
      expect(formatClock(DateTime(2026, 8, 4, 0, 15)), '12:15am',
          reason: 'midnight is 12am, not 0am');
      expect(formatClock(DateTime(2026, 8, 4, 12)), '12pm',
          reason: 'noon is 12pm, not 12am');
      expect(formatClock(DateTime(2026, 8, 4, 23, 59)), '11:59pm');
    });
  });

  group('DatedItem', () {
    // Value equality so a rebuilt agenda over unchanged data compares equal and
    // a list widget can tell "same row" from "different row".
    test('compares by value, and notices the fields that change a row', () {
      final a = item(DateTime(2026, 8, 6), id: 'a');
      expect(a, item(DateTime(2026, 8, 6), id: 'a'));
      expect(a.hashCode, item(DateTime(2026, 8, 6), id: 'a').hashCode);
      expect(a, isNot(item(DateTime(2026, 8, 6), id: 'a', done: true)));
      expect(a, isNot(item(DateTime(2026, 8, 6), id: 'a', allDay: false)));
      expect(a, isNot(item(DateTime(2026, 8, 7), id: 'a')));
    });
  });
}
