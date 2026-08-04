/// Study statistics and the exam countdown (P1).
///
/// **Why this file exists separately from `flashcards.dart`.** The study loop
/// was built; the *motivation to open it* was not. A deck that says "12 due"
/// and nothing else gives a student no reason to come back tomorrow, which is
/// the difference between a feature that exists and one that gets used. What
/// closes that gap is small and well understood: show that the work is
/// finite ("128 of 168 seen"), show that yesterday counted ("5-day streak"),
/// and turn the exam on the horizon into a number of cards per day.
///
/// **The correction this work is built on.** The backlog entry for it claimed
/// "everything needed is already in `CardState`". It is not: `CardState` holds
/// `dueAt`, which is when a card comes *back*, and there is no record anywhere
/// of when a card was *reviewed*. `dueAt` cannot be run backwards either — the
/// learning steps mean a card due in ten minutes and a card due in ten minutes
/// tell you nothing about which day their reviews happened on. So a streak
/// needs a ledger of days, and this file defines the smallest honest one: a
/// count of reviews per local calendar day.
///
/// Everything here is a **pure function of its arguments**, including "today".
/// Anything time-dependent that reads the clock internally can only be tested
/// on the day someone happens to run the suite.
library;

/// Reviews-per-day ledger: `'yyyy-mm-dd'` → number of cards graded that day.
typedef StudyDays = Map<String, int>;

/// How many days of history to keep. A semester plus a comfortable margin, so
/// a returning student still sees last term's activity, and the blob stays
/// around 3 KB at its absolute worst (one entry per day, every day).
const int studyDaysKept = 240;

/// A local calendar day as a sortable key.
///
/// **A string, not an epoch, deliberately.** These are calendar days, not
/// instants: "the day I studied" does not change because a device moved
/// timezone or the clocks went back an hour. Storing midnight-as-milliseconds
/// would make yesterday's entry drift into the day before for anyone who flies
/// west, and silently break their streak.
String dayKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Parse a [dayKey] back to local midnight. Null if it isn't one.
DateTime? parseDayKey(String s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  final out = DateTime(y, mo, d);
  // Dart rolls 31 February over into March rather than rejecting it.
  return (out.month == mo && out.day == d) ? out : null;
}

/// Whole calendar days from [from] to [to], ignoring the time of day.
///
/// Computed through UTC on purpose. Subtracting two local `DateTime`s and
/// reading `inDays` is wrong twice a year: a spring-forward day is 23 hours,
/// so "tomorrow" comes out as 0 days away and an exam countdown skips a
/// number. Normalising to UTC midnight first makes every day exactly 24 hours.
int daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

/// The day [n] days before [d], as a key. Built by arithmetic on the date
/// fields rather than `subtract(Duration(days: n))`, which lands on the same
/// calendar day when the clocks change.
String _dayKeyBefore(DateTime d, int n) => dayKey(DateTime(d.year, d.month, d.day - n));

/// Consecutive days of study, ending today or yesterday.
///
/// **Yesterday counts, and that is the whole design.** A streak that resets the
/// instant midnight passes punishes you for not having studied yet on a day
/// that has barely started — so the number a student sees over breakfast is
/// zero, which is exactly when they stop caring about it. The streak is alive
/// while there is still a day to save it in; it only breaks once a whole day
/// has passed with nothing in it.
int studyStreak(StudyDays days, DateTime today) {
  if (days.isEmpty) return 0;
  var start = 0;
  if ((days[dayKey(today)] ?? 0) <= 0) {
    if ((days[_dayKeyBefore(today, 1)] ?? 0) <= 0) return 0;
    start = 1;
  }
  var n = 0;
  for (var i = start;; i++) {
    if ((days[_dayKeyBefore(today, i)] ?? 0) <= 0) break;
    n++;
  }
  return n;
}

/// Reviews on each of the last [n] days, oldest first — the activity strip.
///
/// Always exactly [n] entries, zeros included, so the bars line up with days
/// rather than with "days you happened to study".
List<int> activityBars(StudyDays days, DateTime today, {int n = 14}) => [
      for (var i = n - 1; i >= 0; i--) days[_dayKeyBefore(today, i)] ?? 0,
    ];

/// Drop history older than [keep] days.
///
/// Returns a new map; the caller decides whether the pruning is worth a write.
StudyDays pruneStudyDays(StudyDays days, DateTime today,
    {int keep = studyDaysKept}) {
  final cutoff = DateTime(today.year, today.month, today.day - keep);
  return {
    for (final e in days.entries)
      if (e.value > 0)
        if (_notBefore(e.key, cutoff)) e.key: e.value,
  };
}

/// True when [key] is a valid day on or after [cutoff]. An unparseable key is
/// dropped: it can only have come from a corrupted settings blob, and keeping
/// it would make it immortal.
bool _notBefore(String key, DateTime cutoff) {
  final d = parseDayKey(key);
  return d != null && !d.isBefore(cutoff);
}

// ── The exam countdown ──────────────────────────────────────────────────────

/// What the countdown says, and what it asks of you today.
class ExamPlan {
  const ExamPlan({
    required this.date,
    required this.daysLeft,
    required this.unseen,
    required this.total,
  });

  /// The exam day itself (local midnight).
  final DateTime date;

  /// Whole days from today. `0` is today; negative is in the past.
  final int daysLeft;

  /// Cards in the deck that have never been reviewed — the work that is
  /// genuinely left, as opposed to cards that will simply come round again.
  final int unseen;

  /// Cards in the deck altogether.
  final int total;

  bool get isPast => daysLeft < 0;
  bool get isToday => daysLeft == 0;

  /// New cards a day to have seen every one of them by the exam.
  ///
  /// **Deliberately counts first sightings, not reviews.** Promising "12 cards
  /// a day and you're done" while spaced repetition quietly adds re-reviews on
  /// top would be a target that recedes as you approach it, and a plan a
  /// student stops trusting after two days. Getting through the *unseen* pile
  /// is a claim that stays true.
  ///
  /// Zero when there is nothing left to see, or the exam is today or past —
  /// there is no per-day rate to state.
  int get newPerDay {
    if (unseen <= 0 || daysLeft <= 0) return 0;
    return (unseen / daysLeft).ceil();
  }
}

/// Build a plan, or null when there is no exam set.
ExamPlan? examPlan({
  required DateTime? exam,
  required DateTime today,
  required int unseen,
  required int total,
}) {
  if (exam == null) return null;
  return ExamPlan(
    date: exam,
    daysLeft: daysBetween(today, exam),
    unseen: unseen,
    total: total,
  );
}

/// The countdown as a student would say it out loud.
String formatCountdown(int daysLeft) {
  if (daysLeft < 0) {
    final ago = -daysLeft;
    if (ago == 1) return 'yesterday';
    return ago < 14 ? '$ago days ago' : 'passed';
  }
  return switch (daysLeft) {
    0 => 'today',
    1 => 'tomorrow',
    _ => '$daysLeft days',
  };
}

/// A date the way it appears next to the countdown: `12 Aug`, or `12 Aug 2027`
/// when it isn't the year we're in (an exam eight months out is common enough
/// that dropping the year would be genuinely ambiguous).
String formatExamDate(DateTime d, DateTime today) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final base = '${d.day} ${months[d.month - 1]}';
  return d.year == today.year ? base : '$base ${d.year}';
}
