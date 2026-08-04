// Study statistics and the exam countdown (P1) — the pure half.
//
// Every function here takes "today" as an argument, so these tests pin real
// behaviour instead of whatever the calendar happens to say when CI runs. That
// matters more than usual for this feature: a streak is entirely about day
// boundaries, and the two ways to get day arithmetic wrong (DST, and treating
// "no study yet today" as a broken streak) are both invisible on the day you
// write the code.
//
// No SQLite and no widgets, so this file runs on a bare checkout.

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/study/study_stats.dart';

void main() {
  group('day keys', () {
    test('are zero-padded and sort lexicographically', () {
      expect(dayKey(DateTime(2026, 8, 4)), '2026-08-04');
      expect(dayKey(DateTime(2026, 12, 25)), '2026-12-25');
      final keys = [
        dayKey(DateTime(2026, 9, 1)),
        dayKey(DateTime(2026, 8, 31)),
        dayKey(DateTime(2026, 10, 1)),
      ]..sort();
      expect(keys, ['2026-08-31', '2026-09-01', '2026-10-01']);
    });

    test('round-trip, and reject what is not a day', () {
      expect(parseDayKey('2026-08-04'), DateTime(2026, 8, 4));
      expect(parseDayKey('2026-8-4'), isNull, reason: 'unpadded');
      expect(parseDayKey('not a date'), isNull);
      expect(parseDayKey('2026-13-01'), isNull, reason: 'no thirteenth month');
      // Dart would happily roll this into March; a settings blob containing it
      // is corrupt, and silently accepting it invents a day that never was.
      expect(parseDayKey('2026-02-31'), isNull);
    });
  });

  group('daysBetween', () {
    test('counts calendar days, not elapsed hours', () {
      expect(daysBetween(DateTime(2026, 8, 4), DateTime(2026, 8, 4)), 0);
      expect(daysBetween(DateTime(2026, 8, 4), DateTime(2026, 8, 5)), 1);
      expect(daysBetween(DateTime(2026, 8, 4, 23, 59), DateTime(2026, 8, 5, 0, 1)),
          1,
          reason: 'two minutes apart, but a day apart');
      expect(daysBetween(DateTime(2026, 8, 5), DateTime(2026, 8, 4)), -1);
    });

    test('crosses a month and a year boundary', () {
      expect(daysBetween(DateTime(2026, 8, 31), DateTime(2026, 9, 1)), 1);
      expect(daysBetween(DateTime(2026, 12, 31), DateTime(2027, 1, 1)), 1);
      expect(daysBetween(DateTime(2028, 2, 28), DateTime(2028, 3, 1)), 2,
          reason: '2028 is a leap year');
    });

    // The bug this rules out: `to.difference(from).inDays` on local times
    // truncates a 23-hour spring-forward day to 0, so an exam "tomorrow" reads
    // as "today" for everyone in a DST timezone on exactly one day a year.
    test('survives a daylight-saving transition', () {
      for (final d in [
        DateTime(2026, 3, 8), // US spring forward
        DateTime(2026, 4, 5), // AU autumn back
        DateTime(2026, 10, 4), // AU spring forward
        DateTime(2026, 10, 25), // EU autumn back
      ]) {
        expect(daysBetween(d, DateTime(d.year, d.month, d.day + 1)), 1,
            reason: 'the day after $d is one day away');
      }
    });
  });

  group('streak', () {
    final today = DateTime(2026, 8, 4);
    String k(int daysAgo) => dayKey(DateTime(2026, 8, 4 - daysAgo));

    test('is zero with no history', () {
      expect(studyStreak({}, today), 0);
    });

    test('counts consecutive days ending today', () {
      final days = {k(0): 12, k(1): 4, k(2): 30};
      expect(studyStreak(days, today), 3);
    });

    // The whole reason the rule is "today or yesterday": a streak that resets
    // at midnight shows a student zero over breakfast, which is precisely when
    // the number was supposed to get them to sit down.
    test('stays alive on a day you have not studied yet', () {
      final days = {k(1): 4, k(2): 30, k(3): 7};
      expect(studyStreak(days, today), 3);
    });

    test('breaks once a whole day has been missed', () {
      final days = {k(2): 30, k(3): 7};
      expect(studyStreak(days, today), 0,
          reason: 'yesterday is empty, so the streak is already gone');
    });

    test('stops at the first gap', () {
      final days = {k(0): 1, k(1): 1, k(3): 99, k(4): 99};
      expect(studyStreak(days, today), 2);
    });

    test('ignores a day recorded as zero', () {
      expect(studyStreak({k(0): 1, k(1): 0, k(2): 5}, today), 1);
    });

    test('counts across a month boundary', () {
      final t = DateTime(2026, 9, 2);
      final days = {'2026-09-02': 1, '2026-09-01': 1, '2026-08-31': 1};
      expect(studyStreak(days, t), 3);
    });
  });

  group('activity strip', () {
    final today = DateTime(2026, 8, 4);

    test('always returns one entry per day, oldest first', () {
      final bars = activityBars({dayKey(today): 9}, today, n: 7);
      expect(bars.length, 7);
      expect(bars.last, 9, reason: 'today is the right-hand bar');
      expect(bars.take(6), everyElement(0));
    });

    test('places each day in its own slot', () {
      final days = {
        dayKey(DateTime(2026, 8, 4)): 1,
        dayKey(DateTime(2026, 8, 2)): 5,
        dayKey(DateTime(2026, 7, 31)): 2,
      };
      expect(activityBars(days, today, n: 5), [2, 0, 5, 0, 1]);
    });
  });

  group('pruning', () {
    final today = DateTime(2026, 8, 4);

    test('keeps recent days and drops ancient ones', () {
      final days = {
        dayKey(DateTime(2026, 8, 4)): 3,
        dayKey(DateTime(2026, 8, 4 - studyDaysKept + 1)): 1,
        dayKey(DateTime(2026, 8, 4 - studyDaysKept - 1)): 1,
      };
      final kept = pruneStudyDays(days, today);
      expect(kept.length, 2);
      expect(kept.containsKey(dayKey(DateTime(2026, 8, 4))), isTrue);
    });

    test('drops zero counts and unparseable keys', () {
      final kept = pruneStudyDays(
          {dayKey(today): 1, dayKey(DateTime(2026, 8, 3)): 0, 'rubbish': 4},
          today);
      expect(kept.keys, [dayKey(today)]);
    });
  });

  group('exam plan', () {
    final today = DateTime(2026, 8, 4);

    test('is null without a date', () {
      expect(examPlan(exam: null, today: today, unseen: 10, total: 10), isNull);
    });

    test('spreads the unseen cards over the days left', () {
      final p = examPlan(
          exam: DateTime(2026, 8, 18), today: today, unseen: 40, total: 168)!;
      expect(p.daysLeft, 14);
      expect(p.newPerDay, 3, reason: '40 over 14 days, rounded up');
      expect(p.isPast, isFalse);
      expect(p.isToday, isFalse);
    });

    test('rounds up so the plan actually finishes', () {
      final p = examPlan(
          exam: DateTime(2026, 8, 7), today: today, unseen: 10, total: 10)!;
      expect(p.daysLeft, 3);
      expect(p.newPerDay, 4, reason: '3 a day leaves one card unseen');
    });

    test('asks for nothing when there is nothing unseen', () {
      final p = examPlan(
          exam: DateTime(2026, 8, 18), today: today, unseen: 0, total: 168)!;
      expect(p.newPerDay, 0);
    });

    test('asks for nothing on the day itself', () {
      final p = examPlan(
          exam: today, today: today, unseen: 40, total: 168)!;
      expect(p.isToday, isTrue);
      expect(p.isPast, isFalse);
      expect(p.newPerDay, 0, reason: 'no days left to spread over');
    });

    test('knows an exam that has been and gone', () {
      final p = examPlan(
          exam: DateTime(2026, 8, 1), today: today, unseen: 5, total: 20)!;
      expect(p.isPast, isTrue);
      expect(p.daysLeft, -3);
      expect(p.newPerDay, 0);
    });
  });

  group('wording', () {
    test('counts down the way a student would say it', () {
      expect(formatCountdown(0), 'today');
      expect(formatCountdown(1), 'tomorrow');
      expect(formatCountdown(14), '14 days');
      expect(formatCountdown(-1), 'yesterday');
      expect(formatCountdown(-3), '3 days ago');
      expect(formatCountdown(-90), 'passed');
    });

    test('shows the year only when it is not this one', () {
      final today = DateTime(2026, 8, 4);
      expect(formatExamDate(DateTime(2026, 8, 12), today), '12 Aug');
      expect(formatExamDate(DateTime(2027, 2, 3), today), '3 Feb 2027');
    });
  });
}
