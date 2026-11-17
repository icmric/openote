/// The planner's dates and times in the reader's language.
///
/// `relativeWhen`, `formatClock` (`lib/planner/agenda.dart`) and the helpers in
/// `ui/planner_format.dart` stay as the English the agenda's tests read; these
/// are what a screen says, and `planner_words_test` checks the English here
/// matches them.
library;

import '../planner/agenda.dart';
import '../study/study_stats.dart' show daysBetween;
import 'l10n.dart';
import 'study_words.dart' show shortDateIn;

/// A clock time: `4pm`, `4:30pm` in English, as the planner always wrote it;
/// the 24-hour `16:30` everywhere else, which is how each of the other
/// languages writes a time.
String clockIn(L l, DateTime t) => l.localeName == 'en'
    ? formatClock(t)
    : '${t.hour}:${t.minute.toString().padLeft(2, '0')}';

/// [relativeWhen], said in [l]: `today`, `tomorrow`, `in 3 days`, `2 days
/// ago`, or the clock time for something timed today.
String relativeWhenIn(L l, DatedItem item, DateTime now) {
  final days = daysBetween(now, item.when);
  if (days == 0 && !item.allDay) return clockIn(l, item.when);
  return switch (days) {
    0 => l.countdownToday,
    1 => l.countdownTomorrow,
    -1 => l.countdownYesterday,
    < 0 => l.countdownDaysAgo(-days),
    _ => l.whenInDays(days),
  };
}

/// `plannerWhen`, said in [l]: relative inside a fortnight, a date beyond.
String plannerWhenIn(L l, DatedItem it, DateTime now) {
  final days = daysBetween(now, it.when);
  if (days > 14) return shortDateIn(l, it.when, now);
  return relativeWhenIn(l, it, now);
}

/// `Thu 5 Aug` — the heading form, where the weekday is the useful part.
String dayFullIn(L l, DateTime d) {
  final days = l.weekdaysShort.split(',');
  final months = l.monthsShort.split(',');
  return l.dateDayFull(
    days.length == 7 ? days[d.weekday - 1] : '',
    '${d.day}',
    months.length == 12 ? months[d.month - 1] : '${d.month}',
  );
}

/// The month grid's heading: `Aug 2026`.
String monthYearIn(L l, int month, int year) {
  final months = l.monthsShort.split(',');
  return l.planMonthYear(
      months.length == 12 ? months[month - 1] : '$month', '$year');
}

/// One letter a day, Monday first, for the grid's column heads.
List<String> weekdayInitialsIn(L l) {
  final d = l.weekdayInitials.split(',');
  return d.length == 7 ? d : const ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
}

extension AgendaBucketWords on AgendaBucket {
  /// The heading. [AgendaBucket.title] is the English the agenda's tests use.
  String titleIn(L l) => switch (this) {
        AgendaBucket.overdue => l.agendaOverdue,
        AgendaBucket.today => l.agendaToday,
        AgendaBucket.tomorrow => l.agendaTomorrow,
        AgendaBucket.thisWeek => l.agendaThisWeek,
        AgendaBucket.later => l.agendaLater,
        AgendaBucket.done => l.agendaDone,
      };
}
