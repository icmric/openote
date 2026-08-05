/// The planner's agenda — the pure model behind the Planner panel (v0.5 §3).
///
/// **Why an agenda model exists at all.** The exam countdown shipped and the
/// report back was that it is awkward: an exam date is set from two context
/// menus and is then visible only inside the study panel, on whichever section
/// you happen to be looking at. There is no way to ask *"what dates do I have
/// at all"*. That is a surfacing problem, so this file is the surfacing: one
/// shape ([DatedItem]) that an exam date, a dated to-do tag, a reminder and a
/// subscribed calendar event all collapse into, and one grouping over it.
///
/// **This is a lens, not a store.** Nothing here owns data. Callers build
/// [DatedItem]s from state they already hold — exam dates from workspace
/// settings, tasks from `TagKind.todo` lines, events from a subscription — and
/// throw them away again. Deleting the note deletes the task, because they were
/// never two things (v0.5 §6). Keeping that property is what stops the planner
/// growing into a second system to maintain, so nothing in this file may gain a
/// mutator, an id allocator or a persistence hook.
///
/// **Everything is a pure function of its arguments, "now" included.** This is
/// the same rule as `study_stats.dart` and for the same reason: an agenda is
/// entirely about day boundaries, and code that reads the clock internally can
/// only be tested on the day someone happens to run the suite. Every day-length
/// calculation goes through [daysBetween], which normalises through UTC — a
/// spring-forward day is 23 hours long, and `to.difference(from).inDays` on
/// local times truncates it to 0, so "tomorrow" would silently bucket as
/// "today" for everyone in a DST timezone on exactly one day a year.
///
/// No Flutter, no storage, no I/O — so this runs on a bare checkout, and the
/// widget layer above it can be replaced without touching any of these rules.
library;

import '../study/study_stats.dart' show daysBetween;

/// What kind of thing a date hangs off.
///
/// The set is deliberately closed. Each value already corresponds to something
/// the app stores or reads; there is no "other", because a free-standing dated
/// thing belonging to no note is exactly the drift v0.5 §6 forbids.
enum DatedKind {
  /// A section's exam day, from workspace settings. Personal, never synced.
  exam,

  /// A `TagKind.todo` line that has been given a due date. The date rides on
  /// the tag inside block content, so it syncs — a shared notebook's deadline
  /// is the same deadline for everyone reading it.
  task,

  /// A personal nudge at a time. Lives in workspace settings and does *not*
  /// sync: when you want to be interrupted is yours, not the notebook's.
  reminder,

  /// Something from a subscribed calendar (ICS, stage 4). **Read-only** in
  /// every sense — Openote never writes back to anyone's calendar, so the UI
  /// must not offer to re-date or complete one of these.
  event,
}

/// One dated thing, flattened out of whatever it came from.
///
/// Immutable, and built fresh on every read rather than cached. That is
/// affordable because an agenda is tens of rows, and it is what keeps the
/// "lens, not a store" rule honest: there is no stale copy to reconcile when
/// the underlying tag is edited or the note is deleted.
class DatedItem {
  const DatedItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.when,
    required this.allDay,
    this.notebookId,
    this.pageId,
    this.blockId,
    this.line,
    this.done = false,
    this.subtitle,
  });

  /// Stable identity for this row, chosen by whoever built it (e.g.
  /// `'exam:<notebookId>:<sectionId>'`, `'task:<blockId>:<line>'`).
  ///
  /// Not interpreted here. It exists so a list widget can key rows and so a
  /// caller can match a row back to its source; the agenda itself never
  /// deduplicates on it, because two genuinely different items sharing an id
  /// is a bug in the builder that silent deduplication would hide.
  final String id;

  final DatedKind kind;

  /// What the row says. Usually the tagged line's text, or the section name
  /// for an exam.
  final String title;

  /// **Local** time. For [allDay] items only the calendar date is meaningful;
  /// the time-of-day component is ignored by every function here, so a caller
  /// that has only a `yyyy-mm-dd` may pass local midnight without inventing a
  /// time it does not know.
  final DateTime when;

  /// True when only the date matters (exams, due dates), false when a time
  /// does (reminders, lectures).
  ///
  /// Required rather than defaulted on purpose: the two answers put an item in
  /// different buckets for most of a day, and a default would let a caller be
  /// wrong without ever deciding.
  final bool allDay;

  /// Where the row came from, for click-through. All null is legal — an event
  /// from a subscribed calendar belongs to no page — but a [DatedKind.task]
  /// with no [blockId] cannot be navigated to and should not be built.
  final String? notebookId;
  final String? pageId;
  final String? blockId;

  /// 0-based line index within the block, matching `NoteTag.line`.
  final int? line;

  /// Completion, for the kinds that can be completed. An exam or an event is
  /// never done — it happens or it does not — so this stays false for them and
  /// the UI shows no checkbox.
  final bool done;

  /// Optional second line: the section a task lives in, a room number, the
  /// exam plan's "3 a day covers it". Never used for sorting or bucketing.
  final String? subtitle;

  /// Value equality, so tests can compare whole agendas and a list widget can
  /// tell "same row, rebuilt" from "different row". Cheap here because the
  /// class is small and immutable.
  @override
  bool operator ==(Object other) =>
      other is DatedItem &&
      other.id == id &&
      other.kind == kind &&
      other.title == title &&
      other.when == when &&
      other.allDay == allDay &&
      other.notebookId == notebookId &&
      other.pageId == pageId &&
      other.blockId == blockId &&
      other.line == line &&
      other.done == done &&
      other.subtitle == subtitle;

  @override
  int get hashCode => Object.hash(
      id, kind, title, when, allDay, notebookId, pageId, blockId, line, done, subtitle);

  @override
  String toString() =>
      'DatedItem(${kind.name} $id "$title" ${when.toIso8601String()}'
      '${allDay ? ' all-day' : ''}${done ? ' done' : ''})';
}

/// The sections of the agenda, **in display order**.
///
/// Declaration order *is* the order the panel renders, because [groupAgenda]
/// walks `AgendaBucket.values`. Reordering this enum silently reorders the UI,
/// which is the intended way to change it — there is no second list to keep in
/// step, and therefore no way for the two to disagree.
enum AgendaBucket {
  /// Late, and the only bucket that is a complaint. Sorted oldest first like
  /// every other bucket, so the thing you have been ignoring longest is top.
  overdue('Overdue'),
  today('Today'),
  tomorrow('Tomorrow'),

  /// The next seven days, *excluding* today and tomorrow — those have their
  /// own headings and repeating them here would double-count every row.
  thisWeek('This week'),
  later('Later'),

  /// Completed, regardless of when it was due. A finished task is not a
  /// deadline any more, so it never appears under [overdue].
  done('Done');

  const AgendaBucket(this.title);

  /// The heading the panel shows. Here rather than in the widget so that two
  /// call sites cannot drift into "This week" and "This Week".
  final String title;
}

/// Which section of the agenda [item] belongs in, as of [now].
///
/// The rules, and what each one prevents:
///
/// * **Done wins over every date.** A task ticked off last month is history,
///   not a debt; bucketing it as overdue would make the one bucket that is
///   supposed to mean "act on this" fill up with work already finished, and a
///   nag list that is mostly noise gets ignored wholesale.
/// * **An all-day item is overdue only once its whole DAY has passed.** An exam
///   at 09:00 is still today's exam at 09:05, and a due date is a date, not a
///   deadline of midnight. The comparison is therefore in whole calendar days
///   and the time-of-day component of [DatedItem.when] is ignored entirely —
///   comparing instants would mark today's exam overdue from 00:01, which is
///   the single most alarming thing this panel could get wrong.
/// * **A timed item is overdue once its instant has passed**, strictly: an item
///   due exactly at [now] is not yet late, so a reminder does not appear in the
///   overdue list in the same frame it fires.
/// * **`thisWeek` is days 2–7 inclusive.** Day 7 is still "within the next
///   seven days"; day 8 is [later].
AgendaBucket bucketFor(DatedItem item, DateTime now) {
  if (item.done) return AgendaBucket.done;

  // Whole calendar days from today, DST-safe. Negative is in the past.
  final days = daysBetween(now, item.when);
  if (days < 0) return AgendaBucket.overdue;
  if (!item.allDay && item.when.isBefore(now)) return AgendaBucket.overdue;

  return switch (days) {
    0 => AgendaBucket.today,
    1 => AgendaBucket.tomorrow,
    <= 7 => AgendaBucket.thisWeek,
    _ => AgendaBucket.later,
  };
}

/// One rendered section: a heading and the rows under it.
///
/// A record rather than a class because it carries no behaviour and the panel
/// destructures it immediately. Records are structural, so this typedef and the
/// literal `({AgendaBucket bucket, List<DatedItem> items})` are the same type —
/// callers may spell it either way.
typedef AgendaSection = ({AgendaBucket bucket, List<DatedItem> items});

/// Group [items] into the agenda's sections as of [now].
///
/// **Empty buckets are omitted.** A panel that always shows six headings tells
/// a student with two tasks that they have four kinds of nothing, and pushes
/// the rows that matter below the fold. The headings that survive are therefore
/// meaningful on their own — "Overdue" appearing at all is the signal.
///
/// Within a bucket: [DatedItem.when] ascending, then title, then input order.
/// The last tiebreak is what makes this a *stable* sort — Dart's [List.sort] is
/// not stable, so two items with the same instant and the same title could
/// otherwise swap places between two rebuilds of the same data and make the
/// list flicker under the cursor.
///
/// The input list is never mutated; callers commonly pass a list they hold.
List<AgendaSection> groupAgenda(List<DatedItem> items, DateTime now) {
  final byBucket = <AgendaBucket, List<_Ranked>>{};
  for (var i = 0; i < items.length; i++) {
    byBucket
        .putIfAbsent(bucketFor(items[i], now), () => <_Ranked>[])
        .add(_Ranked(items[i], i));
  }

  final out = <AgendaSection>[];
  for (final bucket in AgendaBucket.values) {
    final rows = byBucket[bucket];
    if (rows == null || rows.isEmpty) continue;
    rows.sort(_compare);
    out.add((bucket: bucket, items: [for (final r in rows) r.item]));
  }
  return out;
}

/// An item plus where it came from in the input, so ties can fall back to the
/// caller's order instead of to whatever the sort implementation does.
class _Ranked {
  const _Ranked(this.item, this.index);
  final DatedItem item;
  final int index;
}

int _compare(_Ranked a, _Ranked b) {
  final byWhen = a.item.when.compareTo(b.item.when);
  if (byWhen != 0) return byWhen;
  final byTitle = _compareTitles(a.item.title, b.item.title);
  if (byTitle != 0) return byTitle;
  return a.index.compareTo(b.index);
}

/// Case-folded first, exact second.
///
/// A raw `compareTo` orders by code unit, which puts every capital before every
/// lowercase — "Zoology" above "algebra" in a list of subject names, which
/// reads as broken rather than as a sort. Folding case fixes that; the exact
/// comparison behind it only breaks the resulting ties, so ordering stays
/// deterministic when two titles differ solely in case.
///
/// Open question, deliberately not guessed at: this is not real collation, so
/// "Ångström" sorts after "Zebra" and "élan" after "zebra". Dart's core has no
/// locale-aware collation and pulling in `intl` to order two rows that a
/// student is unlikely to have both of is not a trade worth making yet.
int _compareTitles(String a, String b) {
  final folded = a.toLowerCase().compareTo(b.toLowerCase());
  return folded != 0 ? folded : a.compareTo(b);
}

/// How far away [item] is, phrased the way a student would say it out loud —
/// 'today', 'tomorrow', 'in 3 days', '2 days ago', or the clock time for
/// something timed today ('4:30pm').
///
/// Same tone as `formatCountdown`, with two deliberate differences:
///
/// * **A timed item today shows its time instead of the word "today".** Under a
///   heading that already says TODAY, "today" is the one thing the row does not
///   need to repeat; the time is the information. Items on other days keep the
///   day phrasing, because "4pm" under LATER says nothing — a caller that wants
///   "tomorrow · 4pm" can compose it from [formatClock].
///
///   "Today" here means the calendar day, *not* the bucket: a timed item whose
///   instant has already passed is filed under [AgendaBucket.overdue] by
///   [bucketFor] and still reads "9am", not "today". That is deliberate and the
///   day is never ambiguous, because only same-day items reach this branch —
///   under OVERDUE the clock time is precisely what says *which* of today's
///   items was missed, where "today" would say nothing at all.
/// * **Nothing is clamped to "passed".** `formatCountdown` gives up past a
///   fortnight, which it can afford because the exam date is printed beside it.
///   An overdue row has no such date, and "3 weeks ago" versus "yesterday" is
///   the difference between a task to abandon and one to do this evening.
String relativeWhen(DatedItem item, DateTime now) {
  final days = daysBetween(now, item.when);
  if (days == 0 && !item.allDay) return formatClock(item.when);
  return switch (days) {
    0 => 'today',
    1 => 'tomorrow',
    -1 => 'yesterday',
    < 0 => '${-days} days ago',
    _ => 'in $days days',
  };
}

/// A time of day as a student writes it: `4pm`, `4:30pm`, `12am`.
///
/// 12-hour with no space and no leading zero, and the `:00` dropped on the
/// hour, because that is the form in the design's mock ("🔔 Re-read the proof
/// of 2.7 — 4pm") and because a planner row is scanned, not read.
///
/// Not locale-aware: a 24-hour locale gets 12-hour clock times. That is a known
/// gap rather than an oversight — honouring the system's clock preference means
/// `intl` and a locale, neither of which this pure layer has, so the caller
/// closest to a `BuildContext` is where that belongs if it is ever wanted.
String formatClock(DateTime t) {
  final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final suffix = t.hour < 12 ? 'am' : 'pm';
  return t.minute == 0
      ? '$h12$suffix'
      : '$h12:${t.minute.toString().padLeft(2, '0')}$suffix';
}
