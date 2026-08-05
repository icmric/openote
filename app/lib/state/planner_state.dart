/// The planner: every date you have, in one place (v0.5).
///
/// **Why this exists.** The exam countdown shipped and the report back was that
/// managing it is awkward — a date is set from two different context menus and
/// is then visible only inside the study panel, on whichever section you happen
/// to have open. There was no way to ask *"what have I got on"*. That is a
/// surfacing problem, and this file is the surfacing: four streams that already
/// exist collapse into one timeline.
///
/// | Stream | Lives in | Synced? |
/// |---|---|---|
/// | Exam dates | workspace settings (`StudyState`) | no — an exam date is personal |
/// | Dated tasks | the `due` on a tag, inside block content | **yes** — a group's deadline is one deadline |
/// | Reminders | workspace settings ([ReminderStore]) | no — when you want interrupting is yours |
/// | Calendar events | a subscribed `.ics`, cached here | n/a — read-only, never ours |
///
/// **This class owns no dated data except reminders and the calendar cache.**
/// Exam dates stay in `StudyState`; a task's due date stays on the tag. The
/// agenda is built fresh from them on every read and thrown away — that is the
/// "lens, not a store" rule from the v0.5 plan §6, and it is what makes
/// deleting the note delete the task with no reconciliation anywhere.
///
/// **Time is always an argument.** Same rule as `study_stats.dart` and
/// `agenda.dart`: a planner is made of day boundaries, and code that reads the
/// clock internally can only be tested on the day the suite happens to run.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../model/models.dart';
import '../model/tags.dart';
import '../planner/agenda.dart';
import '../planner/alerts.dart';
import '../planner/calendar_fetch.dart';
import '../planner/event_kinds.dart';
import '../planner/ics.dart';
import '../planner/reminders.dart';
import '../study/study_stats.dart';
import 'study_state.dart';

/// The slice of the open document the planner reads.
///
/// Narrow and read-only-plus-one-mutator, following the precedent
/// [StudyDocument] set: the coupling is stated, checked by the compiler, and
/// small enough that this class can be tested against a fake rather than a
/// whole application.
abstract interface class PlannerDocument {
  String? get notebookId;

  /// The open notebook's tree, ordered by position.
  List<TreeNode> get nodes;

  /// Bumped when a page's stored content changes.
  int get docRevision;

  /// Bumped when the tree changes shape.
  int get nodesRevision;

  /// Every tagged line in the notebook — already cached by the document, which
  /// is why the planner may call it on every build.
  List<TaggedLineRef> allTags();

  /// Give a tag a due day, or clear it. Returns whether anything changed.
  ///
  /// The one mutator, and it is here rather than in this class because the
  /// date lives inside a block: writing it means an undo entry, a block update
  /// and an op. That is the document's job, not the planner's.
  ///
  /// [pageId] is required in spirit even though it is named: the planner lists
  /// tasks from the whole notebook, so "the open page" is the wrong default for
  /// every row except the ones you happen to be looking at.
  bool setTagDue(String blockId, int line, TagKind kind, DateTime? day,
      {String? pageId});
}

/// What [PlannerDocument.allTags] returns. Structurally identical to
/// `AppState.TaggedLine`; named separately so this file does not import the
/// application state it is a component of.
typedef TaggedLineRef = ({
  String pageId,
  String pageTitle,
  String blockId,
  NoteTag tag,
  String text,
});

/// How far back and forward the agenda materialises calendar occurrences.
///
/// A recurring lecture is an infinite set, so a window is not an optimisation
/// — it is what makes the expansion terminate. Back far enough that last
/// week's missed deadline is still visible, forward far enough that next
/// semester's exam date shows the day it is published.
const int plannerPastDays = 60;
const int plannerFutureDays = 400;

/// Largest `.ics` body kept in workspace settings.
///
/// The cache is what makes the timetable appear instantly on open and survive
/// being offline, but settings are read whole at startup, so an unbounded
/// cache would put an arbitrary download on the launch path. A full-year
/// university timetable is 100–400 KB; 4 MB is far beyond any real feed and
/// still small enough to read in one go.
const int plannerCalendarCacheMax = 4 * 1024 * 1024;

/// A subscribed calendar, as the settings remember it.
class CalendarSubscription {
  const CalendarSubscription({
    required this.url,
    this.name = '',
    this.fetchedAt,
    this.lastError,
  });

  /// An `https://`/`http://` URL, or an absolute path to a local `.ics`.
  final String url;

  /// What to call it in the UI — the feed's own `X-WR-CALNAME` when it has
  /// one, else a shortened URL.
  final String name;

  /// When the body currently cached was fetched. Null when it never has been.
  final DateTime? fetchedAt;

  /// Why the last refresh failed, if it did. Kept beside a working cache on
  /// purpose: "showing Tuesday's copy, couldn't reach the server" is useful,
  /// and blanking the timetable on a flaky connection is not.
  final String? lastError;

  bool get isLocalFile => !url.startsWith('http://') && !url.startsWith('https://');

  CalendarSubscription copyWith({
    String? name,
    DateTime? fetchedAt,
    String? lastError,
    bool clearError = false,
  }) =>
      CalendarSubscription(
        url: url,
        name: name ?? this.name,
        fetchedAt: fetchedAt ?? this.fetchedAt,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        if (name.isNotEmpty) 'name': name,
        if (fetchedAt != null) 'fetchedAt': fetchedAt!.millisecondsSinceEpoch,
        if (lastError != null) 'lastError': lastError,
      };

  static CalendarSubscription? fromJson(Object? j) {
    if (j is! Map) return null;
    final url = j['url'];
    if (url is! String || url.trim().isEmpty) return null;
    final at = (j['fetchedAt'] as num?)?.toInt();
    return CalendarSubscription(
      url: url.trim(),
      name: j['name'] as String? ?? '',
      fetchedAt: at == null ? null : DateTime.fromMillisecondsSinceEpoch(at),
      lastError: j['lastError'] as String?,
    );
  }
}

class PlannerState extends ChangeNotifier {
  PlannerState(
    this._doc,
    this._study, {
    required Object? Function(String key) readSetting,
    required void Function(String key, Object? value) writeSetting,
  })  : _read = readSetting,
        _write = writeSetting {
    reminders = ReminderStore(
      readSetting: readSetting,
      writeSetting: writeSetting,
      onChanged: _onRemindersChanged,
    );
  }

  final PlannerDocument _doc;
  final StudyState _study;
  final Object? Function(String) _read;
  final void Function(String, Object?) _write;

  /// Personal nudges. Openote's own store and Openote's own schedule — the OS
  /// is a display channel, never the scheduler (v0.5 §1), because Linux has no
  /// scheduling API at all and Windows needs an MSIX identity Openote does not
  /// ship.
  late final ReminderStore reminders;

  /// Bumped whenever the reminder store changes, so the agenda cache key moves.
  ///
  /// Kept here rather than in the store because `reminders.dart` is
  /// deliberately Flutter-free and change *notification* is this layer's job —
  /// the store reports a change through its `onChanged` callback and this is
  /// what that becomes.
  int _reminderRevision = 0;

  // ── The calendar subscription (stage 4) ──────────────────────────────

  CalendarSubscription? _calendar;
  CalendarSubscription? get calendar => _calendar;

  /// The raw body of the last successful fetch. Parsed lazily and cached by
  /// window, because parsing a year of a timetable on every panel rebuild
  /// would be the `allTags` regression all over again.
  String _calendarBody = '';

  /// Bumped whenever [_calendarBody] is replaced.
  ///
  /// A counter rather than the body's length, which was the first attempt and
  /// is wrong in the one case that matters: a refreshed timetable with the same
  /// byte count as yesterday's — a lecture moved room, a title edited — would
  /// leave every cache key unchanged and show the stale copy for ever.
  int _calendarRevision = 0;

  /// Warnings from the last parse — an unsupported `RRULE`, a `TZID` we cannot
  /// resolve. Surfaced rather than swallowed: a monthly seminar that silently
  /// shows once is a bug report, and the same thing with a note beside it is a
  /// documented limitation.
  List<String> _calendarWarnings = const [];
  List<String> get calendarWarnings => _calendarWarnings;

  bool _refreshing = false;
  bool get isRefreshingCalendar => _refreshing;

  /// Restore persisted state. Called once, from `AppState.init`.
  void load() {
    reminders.load();
    final raw = _read('plannerCalendar');
    _calendar = CalendarSubscription.fromJson(raw is String
        ? (jsonDecode(raw) as Object?)
        : raw);
    final body = _read('plannerCalendarBody');
    if (body is String && body.length <= plannerCalendarCacheMax) {
      _calendarBody = body;
      _calendarRevision++;
    }
    _eventAlerts = EventAlertRules.fromJson(_read('plannerEventAlerts'));
    final fired = _read('plannerFiredEvents');
    if (fired is List) {
      for (final k in fired) {
        if (k is String && k.isNotEmpty) _firedEvents.add(k);
      }
    }
  }

  /// Subscribe to a calendar, replacing any current one, and fetch it.
  ///
  /// One subscription, not a list. Two feeds is a manager — add, remove,
  /// rename, colour, enable — and the v0.5 brakes say anything needing a schema
  /// of its own is out of scope. A student has one timetable; when someone has
  /// two, that is the trigger to revisit.
  Future<void> subscribeCalendar(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    _calendar = CalendarSubscription(url: trimmed);
    _calendarBody = '';
    _calendarRevision++;
    _icsCache = null;
    _persistCalendar();
    notifyListeners();
    await refreshCalendar();
  }

  /// Drop the subscription and everything cached from it.
  void unsubscribeCalendar() {
    if (_calendar == null) return;
    _calendar = null;
    _calendarBody = '';
    _calendarRevision++;
    _icsCache = null;
    _calendarWarnings = const [];
    _write('plannerCalendar', null);
    _write('plannerCalendarBody', null);
    notifyListeners();
  }

  /// Re-fetch the subscribed calendar. Safe to call on every app open.
  ///
  /// **A failure never blanks the timetable.** The cached body stays, the
  /// error is recorded beside it, and the UI can say "showing Tuesday's copy".
  /// A student on a train whose planner emptied itself would reasonably
  /// conclude the feature had lost their timetable.
  Future<void> refreshCalendar() async {
    final sub = _calendar;
    if (sub == null || _refreshing) return;
    _refreshing = true;
    notifyListeners();
    try {
      final body = await fetchCalendar(sub.url);
      if (body.length > plannerCalendarCacheMax) {
        throw Exception('Calendar is larger than '
            '${plannerCalendarCacheMax ~/ (1024 * 1024)} MB');
      }
      if (!_looksLikeIcs(body)) {
        throw Exception('That URL did not return a calendar file');
      }
      _calendarBody = body;
      _calendarRevision++;
      _icsCache = null;
      _calendar = sub.copyWith(
        name: _calendarName(body) ?? sub.name,
        fetchedAt: DateTime.now(),
        clearError: true,
      );
      _write('plannerCalendarBody', body);
    } catch (e) {
      _calendar = sub.copyWith(lastError: _readableError(e));
    } finally {
      _refreshing = false;
      _persistCalendar();
      // A new or refreshed timetable moves the next event alert, so the timer
      // has to be re-armed. Without this, subscribing to a calendar armed
      // nothing until the *next* unrelated change — so the first day's alerts
      // simply did not happen.
      _arm(DateTime.now());
      notifyListeners();
    }
  }

  void _persistCalendar() =>
      _write('plannerCalendar', _calendar?.toJson());

  /// Cheap sanity check before a download is trusted enough to cache. A login
  /// page returns 200 and HTML, and caching that would show an empty timetable
  /// with no explanation.
  static bool _looksLikeIcs(String body) =>
      body.contains('BEGIN:VCALENDAR') || body.contains('BEGIN:VEVENT');

  /// The feed's own name, so the panel says "Semester 2 timetable" rather than
  /// a 200-character URL.
  static String? _calendarName(String body) {
    for (final line in const LineSplitter().convert(body)) {
      final t = line.trimRight();
      if (t.startsWith('X-WR-CALNAME:')) {
        final v = t.substring('X-WR-CALNAME:'.length).trim();
        if (v.isNotEmpty) return v;
      }
      if (t.startsWith('BEGIN:VEVENT')) break; // header is over
    }
    return null;
  }

  /// Network errors stringify as things like
  /// `SocketException: Failed host lookup: 'x' (OS Error: …, errno = -2)`.
  /// A student reading that learns nothing they can act on.
  static String _readableError(Object e) {
    // `fetchCalendar` has already done this work, and done it with more
    // context than is available here — it knows which rung of the retry ladder
    // failed and whether the server answered at all.
    if (e is CalendarFetchException) return e.message;
    if (e is SocketException) return 'Could not reach that address';
    if (e is TimeoutException) return 'The server took too long to answer';
    if (e is FormatException) return 'That address is not a valid URL';
    if (e is FileSystemException) return 'Could not read that file';
    final s = e.toString();
    return s.startsWith('Exception: ') ? s.substring(11) : s;
  }

  // ── The agenda ───────────────────────────────────────────────────────

  ({String key, List<DatedItem> items})? _agendaCache;
  ({String key, List<IcsEvent> events})? _icsCache;

  /// Everything dated, unsorted and unbucketed — feed it to [groupAgenda].
  ///
  /// **Cached on the same revisions `allTags` and `deck` use.** Every planner
  /// surface rebuilds on every notify, i.e. on every keystroke, and building
  /// this walks the tag rollup and the exam map. An uncached agenda behind the
  /// panel is the cache regression those two already had to fix.
  ///
  /// The cache key includes the day, so an agenda built before midnight is not
  /// still being shown after it.
  List<DatedItem> agenda({DateTime? now}) {
    final today = now ?? DateTime.now();
    final key = '${_doc.notebookId}#${_doc.docRevision}#${_doc.nodesRevision}'
        '#${_study.studyRevision}#$_reminderRevision'
        '#$_calendarRevision#${dayKey(today)}';
    final cached = _agendaCache;
    if (cached != null && cached.key == key) return cached.items;

    final out = <DatedItem>[
      ..._examItems(today),
      ..._taskItems(),
      ..._reminderItems(),
      ..._eventItems(today),
    ];
    _agendaCache = (key: key, items: out);
    return out;
  }

  /// The agenda, bucketed and sorted — what the panel renders.
  List<AgendaSection> sections({DateTime? now}) =>
      groupAgenda(agenda(now: now), now ?? DateTime.now());

  /// Dated items falling on one day, for a month-grid cell.
  List<DatedItem> itemsOn(DateTime day, {DateTime? now}) {
    final items = agenda(now: now);
    return [
      for (final it in items)
        if (daysBetween(it.when, day) == 0) it
    ]..sort((a, b) => a.when.compareTo(b.when));
  }

  /// True when there is nothing dated at all — the empty state, which is a
  /// different thing to say than "nothing today".
  bool get isEmpty => agenda().isEmpty;

  // ── Building each stream ─────────────────────────────────────────────

  /// **The revision plan is costed for the soonest exam only, and that is a
  /// performance decision as much as an editorial one.**
  ///
  /// `examPlanFor` walks a whole section's deck out of SQLite, and the deck
  /// cache holds six entries before clearing itself — so building a plan per
  /// exam-dated section would evict the cache that exists to keep the study
  /// button off the keystroke path. `StudyState.nextExam` already solves
  /// exactly this: find the soonest by reading the cheap date map, then cost
  /// one deck. It is also the right row to put it on — "3 a day covers it" is
  /// only actionable for the exam you are actually revising for.
  List<DatedItem> _examItems(DateTime today) {
    final soonest = _study.nextExam(today);
    final out = <DatedItem>[];
    for (final n in _doc.nodes) {
      if (n.kind != NodeKind.section) continue;
      final date = _study.examDate(n.id);
      if (date == null) continue;
      String? subtitle;
      if (soonest != null && soonest.section.id == n.id) {
        final plan = soonest.plan;
        if (plan.total > 0) {
          final rate = plan.newPerDay;
          subtitle = rate > 0
              ? '${plan.unseen} to learn · $rate a day covers it'
              : '${plan.total} cards · all seen';
        }
      }
      // An exam with a stated start time is not an all-day row: "9am" is the
      // single most useful thing to know on the morning of it, and bucketing
      // it as all-day would also sort it before every timed thing that day.
      final at = _study.examAt(n.id) ?? date;
      final timed = _study.examMinuteOfDay(n.id) != null;
      out.add(DatedItem(
        id: examItemId(n.id),
        kind: DatedKind.exam,
        title: n.title.isEmpty ? 'Untitled section' : n.title,
        when: at,
        allDay: !timed,
        notebookId: _doc.notebookId,
        subtitle: subtitle,
      ));
    }
    return out;
  }

  List<DatedItem> _taskItems() {
    final out = <DatedItem>[];
    for (final e in _doc.allTags()) {
      final day = e.tag.dueDate;
      if (day == null) continue;
      out.add(DatedItem(
        id: taskItemId(e.blockId, e.tag.line, e.tag.kind),
        kind: DatedKind.task,
        title: e.text.isEmpty ? '(empty line)' : e.text,
        when: day,
        allDay: true,
        notebookId: _doc.notebookId,
        pageId: e.pageId,
        blockId: e.blockId,
        line: e.tag.line,
        done: e.tag.checked ?? false,
        subtitle: e.pageTitle.isEmpty ? null : e.pageTitle,
      ));
    }
    return out;
  }

  /// **Dismissed reminders are skipped**, not shown as done. The store keeps
  /// them for thirty days so an accidental dismissal is recoverable, but a
  /// month of nudges you have already dealt with piling up under a Done
  /// heading is the clutter that makes a list stop being read.
  ///
  /// A *fired* reminder does stay: it happened today, and having it vanish the
  /// instant it popped would make the day's record incomplete.
  List<DatedItem> _reminderItems() => [
        for (final r in reminders.all)
          if (!r.dismissed)
            DatedItem(
              id: reminderItemId(r.id),
              kind: DatedKind.reminder,
              title: r.text.isEmpty ? 'Reminder' : r.text,
              when: r.at,
              allDay: false,
              notebookId: r.notebookId,
              pageId: r.pageId,
              blockId: r.blockId,
              line: r.line,
              subtitle: _pageTitle(r.pageId),
            ),
      ];

  /// A page's title, for the row's second line. Resolved at read time rather
  /// than stored on the reminder: a renamed page must not leave a reminder
  /// pointing at a name that no longer exists anywhere.
  String? _pageTitle(String? pageId) {
    if (pageId == null) return null;
    final n = _doc.nodes.where((n) => n.id == pageId).firstOrNull;
    if (n == null) return null;
    return n.title.isEmpty ? 'Untitled' : n.title;
  }

  /// The subscribed calendar, parsed and cached for the current window.
  ///
  /// One place, because three callers now need it — the agenda, the alert
  /// scheduler and "what's next" — and three copies of the cache key is three
  /// chances for one of them to parse a year of a timetable per rebuild.
  List<IcsEvent> _parsedEvents(DateTime today) {
    if (_calendarBody.isEmpty) return const [];
    final from = DateTime(today.year, today.month, today.day - plannerPastDays);
    final to = DateTime(today.year, today.month, today.day + plannerFutureDays);
    final key = '$_calendarRevision#${dayKey(today)}';
    final cached = _icsCache;
    if (cached != null && cached.key == key) return cached.events;
    final r = parseIcs(_calendarBody, windowStart: from, windowEnd: to);
    _calendarWarnings = r.warnings;
    _icsCache = (key: key, events: r.events);
    return r.events;
  }

  /// The next timed event that has not started yet, for the "up next" strip.
  ///
  /// Null when there is no subscription, or nothing left today-and-onwards
  /// inside the parsed window. All-day rows are skipped: "up next: Week 6" is
  /// not an answer to "what have I got on".
  IcsEvent? nextEvent({DateTime? now}) {
    final at = now ?? DateTime.now();
    for (final e in _parsedEvents(at)) {
      if (e.allDay || !e.start.isAfter(at)) continue;
      return e; // parseIcs returns chronological order
    }
    return null;
  }

  /// The event happening right now, if one is. Shown beside [nextEvent] so the
  /// strip says "in this until 11" rather than jumping to the next thing while
  /// you are still sitting in a lecture.
  IcsEvent? currentEvent({DateTime? now}) {
    final at = now ?? DateTime.now();
    for (final e in _parsedEvents(at)) {
      if (e.allDay || e.end == null) continue;
      if (!e.start.isAfter(at) && e.end!.isAfter(at)) return e;
    }
    return null;
  }

  List<DatedItem> _eventItems(DateTime today) {
    final events = _parsedEvents(today);
    if (events.isEmpty) return const [];
    return [
      for (final e in events)
        DatedItem(
          id: eventItemId(e.uid, e.start),
          kind: DatedKind.event,
          title: e.summary.isEmpty ? '(untitled event)' : e.summary,
          when: e.start,
          allDay: e.allDay,
          subtitle: _eventSubtitle(e),
        ),
    ];
  }

  static String? _eventSubtitle(IcsEvent e) {
    final parts = <String>[];
    if (!e.allDay && e.end != null && e.end!.isAfter(e.start)) {
      parts.add('${formatClock(e.start)}–${formatClock(e.end!)}');
    }
    if (e.location.isNotEmpty) parts.add(e.location);
    if (e.recurrenceUnsupported) parts.add('repeats — later dates not shown');
    return parts.isEmpty ? null : parts.join(' · ');
  }

  // ── Acting on a row ──────────────────────────────────────────────────
  //
  // A [DatedItem] is a flattened view, so acting on one means finding its
  // source again. The id carries what the item's own fields cannot — the
  // section behind an exam, the tag kind behind a task — under a scheme that
  // is private to this file and decoded only here.

  static String examItemId(String sectionId) => 'exam:$sectionId';
  static String taskItemId(String blockId, int line, TagKind kind) =>
      'task:${kind.key}:$line:$blockId';
  static String reminderItemId(String id) => 'rem:$id';
  static String eventItemId(String uid, DateTime start) =>
      'ics:${start.millisecondsSinceEpoch}:$uid';

  /// The section an exam row belongs to, or null for anything else.
  static String? examSectionOf(DatedItem it) =>
      it.kind == DatedKind.exam && it.id.startsWith('exam:')
          ? it.id.substring(5)
          : null;

  /// The reminder a reminder row belongs to.
  static String? reminderIdOf(DatedItem it) =>
      it.kind == DatedKind.reminder && it.id.startsWith('rem:')
          ? it.id.substring(4)
          : null;

  /// The tag kind behind a task row. Needed because one line can carry several
  /// tags and only one of them holds the date.
  static TagKind? taskKindOf(DatedItem it) {
    if (it.kind != DatedKind.task) return null;
    final parts = it.id.split(':');
    return parts.length >= 2 && parts[0] == 'task'
        ? TagKind.parse(parts[1])
        : null;
  }

  /// Can this row's date be changed from the planner?
  ///
  /// Calendar events cannot: Openote never writes to anyone's calendar, and a
  /// re-date control that silently did nothing (or worse, appeared to work
  /// until the next refresh) is the wrong answer to "read-only".
  bool canRedate(DatedItem it) => it.kind != DatedKind.event;

  /// Move a row to [day], or clear its date with null. Returns whether it
  /// changed. The point of the planner: **every date is editable from here**,
  /// which is the actual fix for "the exam countdown is not easy to manage".
  bool redate(DatedItem it, DateTime? day) {
    switch (it.kind) {
      case DatedKind.exam:
        final section = examSectionOf(it);
        if (section == null) return false;
        _study.setExamDate(section, day);
        _agendaCache = null;
        return true;
      case DatedKind.task:
        final kind = taskKindOf(it);
        if (kind == null || it.blockId == null || it.line == null) return false;
        final ok = _doc.setTagDue(it.blockId!, it.line!, kind, day,
            pageId: it.pageId);
        if (ok) _agendaCache = null;
        return ok;
      case DatedKind.reminder:
        final id = reminderIdOf(it);
        if (id == null || reminders.byId(id) == null) return false;
        if (day == null) {
          reminders.remove(id);
          return true;
        }
        // A reminder is a time, not a day: moving it to another date keeps the
        // hour you chose. Landing every re-dated nudge on midnight would be a
        // guess, and a wrong one.
        reminders.reschedule(
            id,
            DateTime(
                day.year, day.month, day.day, it.when.hour, it.when.minute));
        return true;
      case DatedKind.event:
        return false;
    }
  }

  /// Tick a task off (or back on) from the planner.
  ///
  /// Only tasks: an exam or a lecture is not something you complete, and a
  /// checkbox on one would be a promise the model cannot keep.
  bool canComplete(DatedItem it) => it.kind == DatedKind.task;

  // ── The reminder timer ───────────────────────────────────────────────
  //
  // Openote owns the schedule (v0.5 §1). One timer, re-armed from the store's
  // next due time — not a one-second tick, which would wake the app 86,400
  // times a day to answer "no" 86,399 of them.

  Timer? _timer;

  /// Alerts that have come due and not yet been dealt with. The popup and the
  /// panel banner both read this; nothing else may mutate it.
  final List<PlannerAlert> pendingAlerts = [];

  /// True when [pendingAlerts] built up while the app was closed, so the UI can
  /// say "3 while you were away" rather than pretending they just fired.
  bool alertsWereMissed = false;

  /// Event occurrences already alerted on, as [firedEventKey] strings.
  ///
  /// Persisted, for the same reason `Reminder.fired` is: without it, every
  /// restart during a lecture pops the same alert again. Pruned in [_pruneFired]
  /// rather than allowed to grow — a year of a timetable is ~1500 keys, which is
  /// not enormous but is unbounded, and unbounded state in a settings file is
  /// how settings files become slow.
  final Set<String> _firedEvents = <String>{};

  /// Which kinds of event get an alert, and how far ahead. Off by default; see
  /// [EventAlertRules].
  EventAlertRules _eventAlerts = EventAlertRules.none;
  EventAlertRules get eventAlerts => _eventAlerts;

  set eventAlerts(EventAlertRules rules) {
    _eventAlerts = rules;
    _write('plannerEventAlerts', rules.toJson());
    // Turning a rule ON must not immediately fire for everything already in
    // progress this morning — those moments have passed, and a burst of six
    // popups is exactly the experience that gets alerts switched off again.
    // Marking the current window as already-seen is the honest reading of
    // "from now on".
    _markCurrentWindowSeen(DateTime.now());
    _arm(DateTime.now());
    notifyListeners();
  }

  /// Start the scheduler. Called once the app is up, from `AppState.init`.
  ///
  /// The first thing it does is catch up: a desktop app that was closed cannot
  /// have interrupted you, and the honest answer is to say so on next open
  /// rather than to drop the reminder on the floor.
  ///
  /// `staleAfter: Duration.zero` is the wiring the store documents for this
  /// exact call. At this moment the timer has not run once, so anything due and
  /// unfired *cannot* have been shown by this session — the age heuristic the
  /// default exists for has nothing to add, and using it would file a reminder
  /// that came due ninety seconds before launch under the wrong heading.
  ///
  /// **Missed *event* alerts are not replayed.** A reminder you set for 2pm is
  /// still worth telling you about at 4pm; "your lecture was starting soon,
  /// four hours ago" is noise, and worse, it is noise on every single launch
  /// for the rest of the day. Anything already started is marked seen instead.
  void startScheduler({DateTime? now}) {
    final at = now ?? DateTime.now();
    final missed = reminders.missedWhileAway(at, staleAfter: Duration.zero);
    if (missed.isNotEmpty) {
      pendingAlerts.addAll(missed.map(_alertForReminder));
      alertsWereMissed = true;
      reminders.markFired([for (final r in missed) r.id], at);
    }
    _markPastEventsSeen(at);
    _arm(at);
    if (missed.isNotEmpty) notifyListeners();
  }

  /// The store changed under us — a reminder was added, snoozed, dismissed or
  /// removed. [nextDueAt] has almost certainly moved, and a stale timer is a
  /// missed nudge.
  void _onRemindersChanged() {
    _reminderRevision++;
    _agendaCache = null;
    _arm(DateTime.now());
    notifyListeners();
  }

  /// Re-arm the timer for the next thing that needs saying, whenever that is.
  void _arm(DateTime now) {
    _timer?.cancel();
    _timer = null;
    var next = reminders.nextDueAt(now);
    final event = _nextEventAlertAt(now);
    if (event != null && (next == null || event.isBefore(next))) next = event;
    if (next == null) return;
    // Clamped: a `Timer` with a multi-week duration is a long time to trust a
    // suspended laptop's clock, and re-checking hourly costs nothing. The
    // lower bound stops a reminder one millisecond away spinning the timer.
    var wait = next.difference(now);
    if (wait < const Duration(seconds: 1)) wait = const Duration(seconds: 1);
    if (wait > const Duration(hours: 1)) wait = const Duration(hours: 1);
    _timer = Timer(wait, _tick);
  }

  void _tick() {
    final now = DateTime.now();
    var fired = false;

    final due = reminders.due(now);
    if (due.isNotEmpty) {
      pendingAlerts.addAll(due.map(_alertForReminder));
      // Fired while we were watching, so it is a nudge and not a catch-up —
      // even if an older one is still sitting in the list beside it.
      alertsWereMissed = false;
      // Marked because it IS being shown: `pendingAlerts` is what the panel and
      // the command-bar badge both read. Marking anything not shown would
      // swallow it silently; not marking what was shown would leave `nextDueAt`
      // pinned at `now` and re-tick forever.
      reminders.markFired([for (final r in due) r.id], now);
      fired = true;
    }

    for (final a in dueEventAlerts(now)) {
      pendingAlerts.add(a);
      _firedEvents.add(a.id);
      alertsWereMissed = false;
      fired = true;
    }
    if (fired) _persistFired(now);

    _arm(now);
    if (fired) notifyListeners();
  }

  // ── Event alerts ─────────────────────────────────────────────────────

  /// Event alerts that should be showing right now and have not been shown.
  ///
  /// Public because the test suite drives it directly: the alternative is a
  /// test that waits for a real `Timer`, which is a test that is either slow or
  /// flaky and usually both.
  List<PlannerAlert> dueEventAlerts(DateTime now) {
    if (_eventAlerts.isEmpty || _calendarBody.isEmpty) return const [];
    final out = <PlannerAlert>[];
    for (final e in _alertableEvents(now)) {
      final lead = _eventAlerts.leadFor(classifyEvent(e));
      if (lead == null) continue;
      final at = e.start.subtract(Duration(minutes: lead));
      // Only the window between "the alert is due" and "the event has started".
      // Past the start it is not a warning any more, and firing one is the
      // "your 9am was starting soon" nonsense that made this feature annoying
      // in the first place.
      if (at.isAfter(now) || !e.start.isAfter(now)) continue;
      final key = firedEventKey(e.uid, e.start);
      if (_firedEvents.contains(key)) continue;
      out.add(_alertForEvent(e, key));
    }
    return out;
  }

  /// When the next event alert is due, or null if none is.
  DateTime? _nextEventAlertAt(DateTime now) {
    if (_eventAlerts.isEmpty || _calendarBody.isEmpty) return null;
    DateTime? soonest;
    for (final e in _alertableEvents(now)) {
      final lead = _eventAlerts.leadFor(classifyEvent(e));
      if (lead == null) continue;
      if (_firedEvents.contains(firedEventKey(e.uid, e.start))) continue;
      final at = e.start.subtract(Duration(minutes: lead));
      if (!at.isAfter(now)) {
        // Already due — the tick will pick it up; ask for it immediately.
        return now;
      }
      if (soonest == null || at.isBefore(soonest)) soonest = at;
    }
    return soonest;
  }

  /// Timed events near enough to now to be worth considering.
  ///
  /// All-day events are excluded outright: "your all-day event starts in ten
  /// minutes" is meaningless, and an all-day row is exactly the kind of thing
  /// that would fire a 00:00 alert every single night.
  Iterable<IcsEvent> _alertableEvents(DateTime now) sync* {
    final horizon = now.add(Duration(minutes: (_eventAlerts.maxLead ?? 0) + 1));
    for (final e in _parsedEvents(now)) {
      if (e.allDay) continue;
      if (e.start.isBefore(now)) continue;
      if (e.start.isAfter(horizon)) continue;
      yield e;
    }
  }

  PlannerAlert _alertForEvent(IcsEvent e, String key) => PlannerAlert(
        id: key,
        source: AlertSource.event,
        title: e.summary.isEmpty ? '(untitled event)' : e.summary,
        at: e.start,
        subtitle: _eventSubtitle(e),
        kind: classifyEvent(e),
        join: joinLink(e),
      );

  PlannerAlert _alertForReminder(Reminder r) => PlannerAlert(
        id: r.id,
        source: AlertSource.reminder,
        title: r.text.isEmpty ? 'Reminder' : r.text,
        at: r.at,
        subtitle: _pageTitle(r.pageId),
        notebookId: r.notebookId,
        pageId: r.pageId,
        blockId: r.blockId,
        line: r.line,
      );

  /// Mark everything that has already started as seen, without showing it.
  void _markPastEventsSeen(DateTime now) {
    if (_eventAlerts.isEmpty || _calendarBody.isEmpty) return;
    var changed = false;
    for (final e in _parsedEvents(now)) {
      if (e.allDay || !e.start.isBefore(now)) continue;
      changed |= _firedEvents.add(firedEventKey(e.uid, e.start));
    }
    if (_pruneFired(now) || changed) _persistFired(now);
  }

  /// Mark everything currently inside its alert window as seen. Used when a
  /// rule is switched on, so enabling alerts is not itself an interruption.
  void _markCurrentWindowSeen(DateTime now) {
    if (_eventAlerts.isEmpty || _calendarBody.isEmpty) return;
    var changed = false;
    for (final e in _alertableEvents(now)) {
      final lead = _eventAlerts.leadFor(classifyEvent(e));
      if (lead == null) continue;
      if (e.start.subtract(Duration(minutes: lead)).isAfter(now)) continue;
      changed |= _firedEvents.add(firedEventKey(e.uid, e.start));
    }
    if (changed) _persistFired(now);
  }

  /// Forget keys for occurrences that are comfortably in the past.
  ///
  /// Two days rather than one: a laptop shut on Friday and opened on Monday
  /// must not replay Friday afternoon, and the key is cheap to keep.
  bool _pruneFired(DateTime now) {
    final cutoff =
        now.subtract(const Duration(days: 2)).millisecondsSinceEpoch;
    final gone = <String>[];
    for (final k in _firedEvents) {
      final parts = k.split(':');
      if (parts.length < 3) continue;
      final ms = int.tryParse(parts[1]);
      if (ms != null && ms < cutoff) gone.add(k);
    }
    _firedEvents.removeAll(gone);
    return gone.isNotEmpty;
  }

  void _persistFired(DateTime now) {
    _pruneFired(now);
    _write('plannerFiredEvents', _firedEvents.toList());
  }

  // ── Acting on an alert ───────────────────────────────────────────────

  /// Deal with one alert: it stops being shown, for good.
  ///
  /// For a reminder that means dismissing it in the store — which is the bug
  /// this replaced. "Done" used to clear the on-screen list only, so the badge
  /// stayed lit, the row stayed in the agenda, and the button read as broken.
  /// For an event it means only "shown"; Openote never writes to a calendar.
  void dismissAlert(String id) {
    final i = pendingAlerts.indexWhere((a) => a.id == id);
    if (i < 0) return;
    final alert = pendingAlerts.removeAt(i);
    if (alert.source == AlertSource.reminder) {
      // Dismisses AND persists, and notifies through `_onRemindersChanged`.
      reminders.dismiss(alert.id);
    }
    if (pendingAlerts.isEmpty) alertsWereMissed = false;
    notifyListeners();
  }

  /// Deal with every showing alert at once.
  void dismissAllAlerts() {
    if (pendingAlerts.isEmpty) return;
    for (final a in pendingAlerts.toList()) {
      if (a.source == AlertSource.reminder) reminders.dismiss(a.id);
    }
    pendingAlerts.clear();
    alertsWereMissed = false;
    notifyListeners();
  }

  /// Put an alert off. Reminders only — an event's time is not ours to move,
  /// so snoozing one just takes it off the screen.
  void snoozeAlert(String id, Duration by, [DateTime? now]) {
    final at = now ?? DateTime.now();
    final i = pendingAlerts.indexWhere((a) => a.id == id);
    if (i < 0) return;
    final alert = pendingAlerts.removeAt(i);
    if (alert.source == AlertSource.reminder) {
      // Measured from now, not from the reminder's own time — snoozing
      // something that came due yesterday "by ten minutes" must land ten
      // minutes from now, or it fires again on the next tick and Snooze
      // appears broken.
      reminders.snooze(alert.id, by, at);
    }
    if (pendingAlerts.isEmpty) alertsWereMissed = false;
    notifyListeners();
  }

  /// Stop showing the alerts without resolving them.
  ///
  /// Kept separate from [dismissAllAlerts] because they are genuinely different
  /// promises: this one is "not now, I am reading it in the panel", and the
  /// reminder stays live in the agenda.
  void clearAlerts() {
    if (pendingAlerts.isEmpty) return;
    pendingAlerts.clear();
    alertsWereMissed = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
