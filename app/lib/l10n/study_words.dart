/// The study side's small phrases — an interval, a countdown, a date, a
/// grade — in the reader's language.
///
/// `formatDelay`, `formatCountdown` and `formatExamDate` in `lib/study` stay as
/// they are: that layer knows nothing about widgets or languages, its tests
/// read their English, and `study_words_test` checks that the English here
/// says exactly what they say. A screen uses these.
library;

import '../study/flashcards.dart' show Grade;
import 'l10n.dart';

/// A duration as a student would say it: `10m`, `3d`, `2mo` in English.
/// The same cut-offs as `formatDelay`.
String delayIn(L l, int ms) {
  if (ms <= 0) return l.timeNow;
  final mins = ms ~/ 60000;
  if (mins < 60) return l.timeMinutesShort('${mins.clamp(1, 59)}');
  final hours = ms ~/ 3600000;
  if (hours < 36) return l.timeHoursShort('$hours');
  final days = (ms / 86400000).round();
  if (days < 31) return l.timeDaysShort('$days');
  if (days < 365) return l.timeMonthsShort('${(days / 30).round()}');
  final years = days / 365;
  return l.timeYearsShort(
      years < 10 ? years.toStringAsFixed(1) : '${years.round()}');
}

/// The exam countdown as a student would say it out loud. The same cut-offs
/// as `formatCountdown`.
String countdownIn(L l, int daysLeft) {
  if (daysLeft < 0) {
    final ago = -daysLeft;
    if (ago == 1) return l.countdownYesterday;
    return ago < 14 ? l.countdownDaysAgo(ago) : l.countdownPassed;
  }
  return switch (daysLeft) {
    0 => l.countdownToday,
    1 => l.countdownTomorrow,
    _ => l.countdownDays(daysLeft),
  };
}

/// `12 Aug`, or `12 Aug 2027` when it is not the year we are in — in the
/// order and with the month names of the reader's language.
String shortDateIn(L l, DateTime d, DateTime today) {
  final months = l.monthsShort.split(',');
  final month = months.length == 12 ? months[d.month - 1] : '${d.month}';
  return d.year == today.year
      ? l.dateDayMonth('${d.day}', month)
      : l.dateDayMonthYear('${d.day}', month, '${d.year}');
}

extension GradeWords on Grade {
  /// The button's name. [Grade.label] is the English the scheduler's tests
  /// use.
  String labelIn(L l) => switch (this) {
        Grade.again => l.gradeAgain,
        Grade.hard => l.gradeHard,
        Grade.good => l.gradeGood,
        Grade.easy => l.gradeEasy,
      };
}
