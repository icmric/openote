/// Reminders — Openote's own schedule, and the catch-up list that is the whole
/// point of it (v0.5 §1, stage 3).
///
/// **Why this module is the scheduler rather than a wrapper over the OS.** The
/// research in v0.5 §1 inverted the obvious architecture: `flutter_local_
/// notifications` cannot schedule on Linux at all — *"Scheduled/pending
/// notifications is currently not supported due to the lack of a scheduler
/// API"* — and on Windows it needs MSIX package identity, which a portable
/// `.zip` release does not have. Linux is not a nice-to-have here; *"no native
/// Linux client"* is one of the founding complaints. So an OS toast is a
/// **display channel** that some platforms offer, never the thing that decides
/// when a reminder happens. That decision lives here, in ordinary Dart, and
/// therefore behaves identically on all three desktops.
///
/// **The consequence that must not be treated as an edge case.** A desktop app
/// that is not running cannot interrupt you, and pretending otherwise is the
/// worst available outcome: a student who trusts a nudge that never arrives is
/// worse off than one who never set it. So anything that came due while Openote
/// was closed has to be recoverable on next open — [ReminderStore.missedWhileAway]
/// is that list, and it is first-class state rather than a fallback. Every
/// design choice below that looks over-careful (persisting the fired flag,
/// refusing to prune on a guess, reporting overdue items from [ReminderStore.nextDueAt])
/// exists to keep one promise: a reminder is either shown, or still showable.
///
/// **Pure Dart on purpose.** No Flutter, no notification package, no timer, and
/// nothing here reads the clock to make a scheduling decision — `now` is an
/// argument, exactly as in `agenda.dart` and `study_stats.dart`. A module that
/// read `DateTime.now()` internally could only be tested at the moment the
/// suite happens to run, and the interesting cases here are all about a gap of
/// days between two runs of the app. The single exception is the retention
/// sweep, which defaults to the real clock when a caller has no opinion; see
/// [ReminderStore.retentionDays].
///
/// **The store owns no timer.** [ReminderStore.nextDueAt] exists so the layer
/// above can arm exactly ONE timer for the whole workspace instead of one per
/// reminder — a hundred pending `Timer`s is a hundred chances to leak one
/// across a hot reload or a workspace switch.
library;

import 'dart:collection';

import '../core/ids.dart';

/// One scheduled nudge.
///
/// Mutable, because the store edits reminders in place and persists the whole
/// list — but only ever through [ReminderStore], which is what writes the
/// change to settings. A caller that mutates a [Reminder] it got from
/// [ReminderStore.all] changes the running app and loses the change on restart,
/// so treat the objects handed out as read-only in practice.
///
/// [id] is `final` even though the rest is not (a deliberate deviation from the
/// sketch in the plan): removal, dismissal and "did this already fire" all key
/// on it, and re-assigning it in place would strand the row it identifies.
class Reminder {
  Reminder({
    required this.id,
    required this.text,
    required this.at,
    this.notebookId,
    this.pageId,
    this.blockId,
    this.line,
    this.fired = false,
    this.firedAt,
    this.dismissed = false,
    this.dismissedAt,
  });

  final String id;

  /// What the nudge says. May be empty — see [fromJson], which keeps a
  /// reminder whose text could not be read rather than dropping the time the
  /// user chose.
  String text;

  /// When it should surface. **Local wall-clock**, stored as a naive ISO-8601
  /// string rather than an epoch instant.
  ///
  /// That is the same call `study_state.dart` makes for exam dates and for the
  /// same reason: an epoch instant re-read in a different timezone lands at a
  /// different time of day, so "nudge me at 4pm" set in London becomes 8am
  /// after flying to New York. A student means 4pm. The cost is that a reminder
  /// set for a specific *instant* (a lecture starting at 14:00 UTC) drifts if
  /// the machine's zone changes; that is the rarer case and the less alarming
  /// failure. A caller that genuinely means an instant may pass a UTC
  /// [DateTime] — [toJson] preserves the `Z` and [fromJson] reads it back as
  /// UTC, so comparisons stay correct either way.
  DateTime at;

  /// Where it came from, for click-through. **All four may be null**: v0.5 §7
  /// leaves free-standing reminders ("call the tutor at 3") an open decision,
  /// and this store deliberately allows them because refusing them would mean
  /// the user simply loses the reminder. Whether the UI *offers* to create one
  /// with no target is a decision for the layer above, not a constraint the
  /// storage should hard-code — and it can be tightened later without a
  /// migration, whereas data thrown away now is gone.
  String? notebookId;
  String? pageId;
  String? blockId;

  /// 0-based line within the block, matching `NoteTag.line`.
  int? line;

  /// Whether this has already been surfaced to the user.
  ///
  /// **Persisted**, and that is the load-bearing part: if this only lived in
  /// memory then every restart would re-fire everything in the past, so a
  /// student who left a week of reminders behind would be greeted by a week of
  /// popups they had already dealt with.
  bool fired;

  /// When it was surfaced, if known. Never re-stamped once set — the *first*
  /// time something was shown is the fact worth keeping.
  DateTime? firedAt;

  /// Dismissed by the user: gone from the agenda, but still stored until the
  /// retention sweep removes it, so an accidental dismissal is recoverable for
  /// as long as a deleted notebook is.
  bool dismissed;

  /// When it was dismissed, if known. A dismissed reminder with no stamp is
  /// **never** pruned — see [ReminderStore.retentionDays].
  DateTime? dismissedAt;

  /// Still capable of firing: neither surfaced nor dismissed.
  bool get isLive => !fired && !dismissed;

  /// Live and its moment has arrived.
  ///
  /// `at == now` counts as due. That matches `agenda.dart`, where an item due
  /// exactly at [now] is due but *not yet overdue* — so a reminder never shows
  /// up in the "you are late" bucket in the same frame it fires.
  bool isDue(DateTime now) => isLive && !at.isAfter(now);

  /// Sparse on purpose: nulls and false flags are omitted.
  ///
  /// Every reader already has to tolerate missing keys (a settings blob can be
  /// hand-edited or half-written), so absence is the cheapest possible encoding
  /// of "no target" — and a free-standing reminder, which is the common case
  /// for the quick "come back to this" nudge, costs three keys instead of nine.
  Map<String, Object?> toJson() => {
        'id': id,
        'text': text,
        'at': _encodeTime(at),
        if (notebookId != null) 'notebookId': notebookId,
        if (pageId != null) 'pageId': pageId,
        if (blockId != null) 'blockId': blockId,
        if (line != null) 'line': line,
        if (fired) 'fired': true,
        if (firedAt != null) 'firedAt': _encodeTime(firedAt!),
        if (dismissed) 'dismissed': true,
        if (dismissedAt != null) 'dismissedAt': _encodeTime(dismissedAt!),
      };

  /// Read one entry, or null if it cannot be made sense of.
  ///
  /// **Returning null rather than throwing is the contract.** This blob lives
  /// in the workspace settings file alongside session state; if a truncated
  /// write or a hand edit could throw here, the app would fail to start over a
  /// reminder. So: drop what cannot be read, keep what can.
  ///
  /// Exactly one field is mandatory — [at]. A reminder with no time is not a
  /// reminder, and inventing one would either nag immediately or never fire.
  /// Everything else degrades: a missing id is minted (the user keeps the
  /// nudge; the next write persists the new id), unreadable text becomes empty,
  /// and an unreadable target becomes null, which is already a legal state.
  ///
  /// The flags are trusted as written and the stamps are not used to infer
  /// them: a `firedAt` with no `fired` is treated as *not* fired. That errs
  /// towards showing a reminder one extra time, which is the direction to be
  /// wrong in — the opposite error silently swallows one.
  static Reminder? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = _decodeTime(raw['at']);
    if (at == null) return null;
    final id = raw['id'];
    return Reminder(
      id: id is String && id.isNotEmpty ? id : newId(),
      text: raw['text'] is String ? raw['text'] as String : '',
      at: at,
      notebookId: _decodeId(raw['notebookId']),
      pageId: _decodeId(raw['pageId']),
      blockId: _decodeId(raw['blockId']),
      line: _decodeLine(raw['line']),
      fired: raw['fired'] == true,
      firedAt: _decodeTime(raw['firedAt']),
      dismissed: raw['dismissed'] == true,
      dismissedAt: _decodeTime(raw['dismissedAt']),
    );
  }

  @override
  String toString() => 'Reminder($id "$text" ${at.toIso8601String()}'
      '${fired ? ' fired' : ''}${dismissed ? ' dismissed' : ''})';
}

String _encodeTime(DateTime t) => t.toIso8601String();

/// Tolerant time parse: ISO-8601 (the form we write), or epoch milliseconds.
///
/// Milliseconds are accepted even though nothing writes them, because the rest
/// of the codebase stores times that way (`nowMs()`), so a hand-edited or
/// future-migrated blob plausibly contains one and reading it is free.
///
/// The catch is deliberately broad. Every failure mode here — a malformed
/// string, a NaN, a number so large that `DateTime` rejects it — has the same
/// correct answer, "this field is unreadable", and enumerating exception types
/// only creates a chance to miss the one that crashes the app on launch.
DateTime? _decodeTime(Object? raw) {
  try {
    if (raw is num) {
      if (raw.isNaN || raw.isInfinite) return null;
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    }
    if (raw is String && raw.isNotEmpty) return DateTime.parse(raw);
  } catch (_) {
    return null;
  }
  return null;
}

/// An empty string is not a usable target id, and treating it as one would give
/// a row a click-through to a page that cannot exist.
String? _decodeId(Object? raw) =>
    raw is String && raw.isNotEmpty ? raw : null;

/// A line index that cannot address anything is dropped rather than stored — a
/// caller that trusted it would index out of bounds.
///
/// The round-trip check is what makes that guard symmetric. `num.toInt()`
/// truncates a fraction and **saturates** at the int64 range instead of
/// throwing, so without it `2.7` becomes line 2 (a line the blob never named)
/// and `1e300` becomes 9223372036854775807 — an index no block has, written
/// straight back out by [Reminder.toJson] and out of bounds for whatever
/// followed the click-through. Both are the same failure the negative case is
/// rejected for, so both get the same answer: null, which is already a legal
/// state.
///
/// Open question deliberately not guessed at: there is no *upper* bound on a
/// line number here, because this module cannot know how many lines a block
/// has. A value that survives the round trip is taken at face value, and the
/// layer that dereferences it must bounds-check anyway.
int? _decodeLine(Object? raw) {
  if (raw is! num || raw.isNaN || raw.isInfinite) return null;
  final n = raw.toInt();
  if (n.toDouble() != raw.toDouble()) return null;
  return n < 0 ? null : n;
}

/// The reminder store: the workspace's schedule, and the only thing that writes
/// it.
///
/// **Two callbacks rather than a `Repository`**, following `study_state.dart`,
/// `sync_recorder.dart` and `device_identity.dart`. What this needs from the
/// repository is "read a key, write a key" — passing the repository instead
/// would drag SQLite and `dart:io` into a module that is otherwise pure, make
/// every test require a database on disk, and give this class the ability to
/// grow a dependency on notebook state that reminders must not have (they are
/// personal and never synced: pushing them through the op log would make one
/// person's alarm everyone's).
class ReminderStore {
  ReminderStore({
    required Object? Function(String key) readSetting,
    required void Function(String key, Object? value) writeSetting,
    this.onChanged,
  })  : _read = readSetting,
        _write = writeSetting;

  /// The settings key. Public so the layer above can clear or migrate it
  /// without a second copy of the string drifting from this one.
  static const String settingsKey = 'reminders';

  /// How long a dismissed reminder is kept before the sweep removes it.
  ///
  /// The same thirty days as `Repository.recycleRetentionDays`, on purpose:
  /// there should be **one** retention concept for everything the user can get
  /// back, so "how long do I have to change my mind" has a single answer across
  /// the app rather than one per feature.
  ///
  /// Deliberately duplicated rather than imported — importing the repository
  /// would pull SQLite and `dart:io` into this pure module and cost every test
  /// here a database. The duplication is the price; if one number changes the
  /// other must too.
  static const int retentionDays = 30;

  final Object? Function(String) _read;
  final void Function(String, Object?) _write;

  /// Called after any change that was persisted, so the layer above can re-arm
  /// its single timer — [nextDueAt] moves whenever a reminder is added,
  /// snoozed, dismissed or removed, and a stale timer is a missed nudge.
  ///
  /// A callback rather than `ChangeNotifier` so this file stays free of Flutter
  /// and runs in a plain Dart test.
  final void Function()? onChanged;

  final List<Reminder> _items = [];

  /// Restore from settings. Safe to call more than once — the list is cleared
  /// first, so a second `load()` (workspace reopened) cannot double every
  /// reminder in it.
  ///
  /// Does **not** write, and in particular does not run the retention sweep:
  /// startup should not rewrite the settings file, and a stale dismissal costs
  /// a few bytes until the next real change.
  void load() {
    _items.clear();
    final raw = _read(settingsKey);
    // Anything that is not a list — absent, a leftover string, a map from a
    // future format — means "no reminders yet", never a crash.
    if (raw is! List) return;
    final seen = <String>{};
    for (final entry in raw) {
      final r = Reminder.fromJson(entry);
      if (r == null) continue;
      // Duplicate ids are collapsed, keeping the first. Two rows sharing an id
      // would make `dismiss`/`remove` ambiguous — the user would dismiss one
      // popup and watch an identical one stay — and silently doing the wrong
      // one of the two is worse than dropping the copy.
      if (!seen.add(r.id)) continue;
      _items.add(r);
    }
  }

  /// Every reminder, in insertion order, including fired and dismissed ones.
  ///
  /// Unsorted on purpose: `groupAgenda` in `agenda.dart` is what orders things
  /// for display, and a second ordering here would be a second thing to keep in
  /// step with it.
  List<Reminder> get all => UnmodifiableListView(_items);

  /// One reminder by id, or null.
  Reminder? byId(String id) {
    for (final r in _items) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Add a reminder and persist.
  ///
  /// [id] is injectable so a test can assert on a known row and so an importer
  /// can preserve identity; it defaults to a fresh UUIDv7 like everything else
  /// in the model. Honouring it is **best effort** — an id already in the store
  /// is replaced by a fresh one rather than duplicated, see [_freeId]. [now] is
  /// only used for the retention sweep that rides along with the write.
  Reminder add({
    required String text,
    required DateTime at,
    String? notebookId,
    String? pageId,
    String? blockId,
    int? line,
    String? id,
    DateTime? now,
  }) {
    final r = Reminder(
      id: _freeId(id),
      // Trimmed once, here, so that "  " and "" cannot produce two rows that
      // look identical in the planner.
      text: text.trim(),
      at: at,
      notebookId: notebookId,
      pageId: pageId,
      blockId: blockId,
      line: line,
    );
    _items.add(r);
    _persist(now);
    return r;
  }

  /// The requested id, or a fresh one when it is already taken (or empty).
  ///
  /// [load] collapses duplicate ids on read, so a store that *creates* one hands
  /// the user a reminder that disappears at the next launch without ever saying
  /// so — and until then the two rows misbehave in opposite directions: `remove`
  /// deletes every match and so takes both out on one click, while [byId],
  /// [dismiss], [snooze] and [reschedule] all act on the first alone and leave
  /// the second firing after the user has dealt with "it".
  ///
  /// Minting instead loses the caller's chosen identity, which is the lesser
  /// loss: the nudge and its time are what the user set. An empty string is
  /// treated as no id at all, matching [Reminder.fromJson].
  ///
  /// Open question left to the layer above: an importer that re-runs and needs
  /// "same id means the same row" wants an upsert, which is a different verb
  /// from [add] and is not invented here.
  String _freeId(String? wanted) =>
      wanted != null && wanted.isNotEmpty && byId(wanted) == null
          ? wanted
          : newId();

  /// Delete a reminder outright. Unknown ids are ignored — the caller is
  /// usually a click on a row that another surface may already have removed,
  /// and throwing would turn a race into a crash.
  void remove(String id, [DateTime? now]) {
    final before = _items.length;
    _items.removeWhere((r) => r.id == id);
    if (_items.length != before) _persist(now);
  }

  /// Move a reminder to a new time and re-arm it.
  ///
  /// Clearing [Reminder.fired] is the point: re-dating something that has
  /// already been shown must make it shown again, or the planner's "re-date"
  /// action would silently produce a reminder that never fires.
  void reschedule(String id, DateTime at, [DateTime? now]) {
    final r = byId(id);
    if (r == null) return;
    r
      ..at = at
      ..fired = false
      ..firedAt = null;
    _persist(now);
  }

  /// Push a reminder [by] a duration **from [now]**, and re-arm it.
  ///
  /// Measured from `now` rather than from the reminder's own time, and that is
  /// the whole reason `now` is a parameter: snoozing a reminder that came due
  /// three days ago "by ten minutes" relative to its own time lands it in the
  /// past, so it fires again on the very next tick — a popup that reappears
  /// however many times you press Snooze. Relative to now it lands ten minutes
  /// from now, which is what the button says.
  ///
  /// A **dismissed** reminder is not snoozed. There is no UI path to it (you
  /// snooze from a popup, and a dismissed reminder has none), and re-arming
  /// something the user explicitly finished with is the one direction of error
  /// that nags them with a nudge they killed. Open question left deliberately
  /// unresolved: if a future "undismiss" action is wanted, it should be its own
  /// verb rather than a side effect of this one.
  void snooze(String id, Duration by, DateTime now) {
    final r = byId(id);
    if (r == null || r.dismissed) return;
    reschedule(id, now.add(by), now);
  }

  /// Mark as dealt with. Kept, not deleted, for [retentionDays].
  void dismiss(String id, [DateTime? now]) {
    final r = byId(id);
    if (r == null || r.dismissed) return;
    r
      ..dismissed = true
      ..dismissedAt = now ?? DateTime.now();
    _persist(now);
  }

  /// Reminders now due that have not been surfaced yet, oldest first.
  ///
  /// Dismissed and already-fired ones are excluded, which is what stops the
  /// same nudge popping twice; see [markFired] for the contract that keeps that
  /// true across a restart.
  List<Reminder> due(DateTime now) => _sorted(
      [for (final r in _items) if (r.isDue(now)) r]);

  /// Mark reminders as surfaced, so they do not fire again.
  ///
  /// **The caller must call this for everything it actually showed**, and only
  /// for what it showed. Two failure modes sit either side of that:
  ///
  /// * marking something that was never displayed silently swallows it — the
  ///   reminder is gone from [due] and from [missedWhileAway] and the student
  ///   never learns it existed;
  /// * not marking what was displayed leaves it due, so [nextDueAt] keeps
  ///   reporting `now` and the layer above re-ticks immediately, forever.
  ///
  /// The write is a single persist for the whole batch rather than one per id,
  /// because the catch-up list acknowledges a week of reminders at once and the
  /// settings file is rewritten wholesale on every write.
  ///
  /// [Reminder.firedAt] is not overwritten if already set: the first time
  /// something was shown is the fact worth keeping, and re-stamping would make
  /// a reminder look fresher every time a popup was rebuilt.
  void markFired(List<String> ids, DateTime now) {
    if (ids.isEmpty) return;
    final wanted = ids.toSet();
    var changed = false;
    for (final r in _items) {
      if (!wanted.contains(r.id) || r.fired) continue;
      r
        ..fired = true
        ..firedAt ??= now;
      changed = true;
    }
    if (changed) _persist(now);
  }

  /// What came due while Openote was closed: due, not yet surfaced, and at
  /// least [staleAfter] old. Oldest first.
  ///
  /// This is the *"3 reminders while you were away"* list from v0.5 §1, and it
  /// is the reason the whole feature can be trusted on a machine that is not
  /// always running.
  ///
  /// **Recommended wiring:** on open, call this with `staleAfter:
  /// Duration.zero` *before* arming the timer, so everything unfired and due is
  /// in the catch-up list — at that moment nothing can have been missed for any
  /// other reason. The non-zero default is for a call made mid-session, where
  /// the age is the only available proxy for "the app cannot have shown this".
  /// The store cannot know when the process started, and guessing would be
  /// exactly the kind of invented semantics that turns into a bug report about
  /// reminders appearing under the wrong heading; hence the parameter.
  ///
  /// Two minutes as the default is a judgement call, sized to cover a laptop
  /// waking from sleep and a UI that has not repainted yet. Too short and a
  /// nudge that fired thirty seconds ago is announced as missed; too long and a
  /// genuinely missed one is invisible for the first minutes of a session.
  ///
  /// Note that this list **overlaps** [due] by design — a missed reminder is
  /// still due, and both lists will contain it until [markFired] is called. The
  /// caller picks one presentation (catch-up list or popup) and marks what it
  /// showed; the store does not decide which surface wins.
  List<Reminder> missedWhileAway(
    DateTime now, {
    Duration staleAfter = const Duration(minutes: 2),
  }) =>
      _sorted([
        for (final r in _items)
          if (r.isDue(now) && now.difference(r.at) >= staleAfter) r
      ]);

  /// The next instant anything becomes due, or null when nothing can.
  ///
  /// The layer above arms **one** timer from this rather than one per reminder.
  ///
  /// Anything already overdue and unfired reports [now], not its own past
  /// instant. Two bugs are avoided at once:
  ///
  /// * skipping past-due reminders entirely would mean an unfired overdue one
  ///   never gets a timer, so a reminder the app failed to show once is lost
  ///   until the next launch — the exact promise this module exists to keep;
  /// * returning the past instant makes `nextDueAt(now).difference(now)`
  ///   negative, which a `Timer` treats as zero but a countdown label renders
  ///   as "in -3 days".
  ///
  /// Fired and dismissed reminders are ignored: they are finished, and letting
  /// them set the timer would wake the app up for nothing.
  DateTime? nextDueAt(DateTime now) {
    DateTime? next;
    for (final r in _items) {
      if (!r.isLive) continue;
      final at = r.at.isBefore(now) ? now : r.at;
      if (next == null || at.isBefore(next)) next = at;
    }
    return next;
  }

  /// Oldest first, ties broken by id.
  ///
  /// The id tiebreak is not cosmetic: `List.sort` is not stable in Dart, so two
  /// reminders set for the same minute could swap places between two reads of
  /// the same data and make the catch-up list reorder itself under the cursor.
  List<Reminder> _sorted(List<Reminder> rs) {
    rs.sort((a, b) {
      final byWhen = a.at.compareTo(b.at);
      return byWhen != 0 ? byWhen : a.id.compareTo(b.id);
    });
    return rs;
  }

  /// Sweep, write, notify.
  ///
  /// The clock is only consulted here, and only for retention — never to decide
  /// whether something is due. A caller with a `now` in hand passes it so the
  /// sweep is testable; one without (a plain `remove` from a menu) gets the
  /// real clock, which cannot affect anything except which month-old dismissals
  /// disappear.
  void _persist([DateTime? now]) {
    _prune(now ?? DateTime.now());
    _write(settingsKey, [for (final r in _items) r.toJson()]);
    onChanged?.call();
  }

  /// Drop dismissals older than [retentionDays].
  ///
  /// On write rather than on read, matching `_persistCardStates` in
  /// `study_state.dart`: this blob is loaded once per launch and read on every
  /// planner build, so the scan belongs at the point it changes.
  ///
  /// **A dismissed reminder with no `dismissedAt` is never pruned.** That is
  /// data written by an older or hand-edited blob, and "unknown age" must not
  /// resolve to "delete it" — the cost of keeping it is a row in a settings
  /// file, and the cost of guessing wrong is destroying something the user
  /// could still have got back.
  void _prune(DateTime now) {
    final cutoff = now.subtract(const Duration(days: retentionDays));
    _items.removeWhere((r) {
      if (!r.dismissed) return false;
      final at = r.dismissedAt;
      return at != null && at.isBefore(cutoff);
    });
  }
}
