/// How the planner's surfaces phrase a date.
///
/// Separate from `agenda.dart` because that file is pure model and deliberately
/// Flutter-free — and separate from any one widget because three surfaces read
/// these strings (the panel, the month grid, the navigator's Home pane) and two
/// of them disagreeing about how to say "next Tuesday" is exactly the kind of
/// drift that makes an app feel unfinished.
library;

import '../planner/agenda.dart';
import '../study/study_stats.dart' show daysBetween;

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `Thu 5 Aug` — the heading form, where the weekday is the useful part.
String formatDayFull(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

/// `Aug`, `Sep`.
String monthName(int month) => _months[month - 1];

/// `12 Aug`, or `12 Aug 2027` when it isn't the year we're in.
///
/// Matches `formatExamDate` in `study_stats.dart`, so the countdown in the
/// study panel and the row in the planner say the date the same way.
String formatDayCompact(DateTime d, DateTime now) {
  final base = '${d.day} ${_months[d.month - 1]}';
  return d.year == now.year ? base : '$base ${d.year}';
}

/// Same calendar day? By fields rather than by subtracting instants, which is
/// off by one on the two days a year the clocks change.
bool daysEqual(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// How far off a row is, in the fewest words that place it.
///
/// [relativeWhen] from the agenda model for anything inside a fortnight, and a
/// **date** beyond it. That cut-off is where counting stops helping: "in 6
/// days" is instantly meaningful and "in 213 days" is a number you have to do
/// arithmetic on to use, about an exam whose actual date — 12 Mar — is the
/// thing you were trying to find out.
///
/// Past dates keep the relative phrasing much longer, because "3 weeks ago" and
/// "yesterday" are the difference between a task to abandon and one to do this
/// evening, and an overdue row has no date printed beside it.
String plannerWhen(DatedItem it, DateTime now) {
  final days = daysBetween(now, it.when);
  if (days > 14) return formatDayCompact(it.when, now);
  return relativeWhen(it, now);
}
