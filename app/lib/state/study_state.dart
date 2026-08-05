/// Everything about studying your notes, owned by one object (E3).
///
/// **Why this is its own file.** `AppState` had grown to twenty-seven sections
/// and ~3,200 lines, not because any one of them was badly written but because
/// there was nowhere else for state to land — so every feature added another
/// section, and `notifyListeners` offered a rebuild of all of it to everyone.
/// The 2026-08 review named the three most separable clusters; this is the
/// first, and the one that had just grown again for the exam countdown.
///
/// **The coupling is stated rather than assumed.** A deck is derived from the
/// document — the notebook's pages, the open page's blocks, and the revision
/// counters that say when either changed — so this cannot be a free-standing
/// object. Instead of reaching into `AppState`, it depends on [StudyDocument]:
/// eight members, all of which `AppState` already had. That is the whole
/// surface, it is checked by the compiler, and it makes this class testable
/// against a fake document rather than a whole application.
///
/// Settings arrive as two callbacks for the same reason, and by the same
/// precedent the sync recorder already set: what this needs from the
/// repository is "read a key, write a key", not a database.
library;

import 'package:flutter/foundation.dart';

import '../model/models.dart';
import '../study/flashcards.dart';
import '../study/study_stats.dart';

/// The slice of the open document a deck is derived from.
///
/// Deliberately read-only. Study state observes the document and never edits
/// it: the cards are a *view* of the notes, which is the scope guard the
/// flashcard model was built around, and it is worth having the type system
/// hold that line rather than a comment.
/// Getters throughout, so the read-only intent is enforced rather than
/// described — a field here would let study code assign to the document.
abstract interface class StudyDocument {
  /// The open notebook, or null when none is.
  String? get notebookId;

  /// The open notebook's tree, ordered by position.
  List<TreeNode> get nodes;

  /// The open page, or null.
  String? get pageId;

  /// The focused section — what "this section" means to a study surface.
  String? get activeSectionId;

  /// The open page's blocks, live in memory.
  List<Block> get blocks;

  /// Read a *closed* page from storage.
  PageData readPage(String id);

  /// Bumped when a page's stored content is replaced wholesale (undo, version
  /// restore, sync pull).
  int get docRevision;

  /// Bumped when the tree changes shape or a node's rendered fields change.
  int get nodesRevision;
}

class StudyState extends ChangeNotifier {
  StudyState(
    this._doc, {
    required Object? Function(String key) readSetting,
    required void Function(String key, Object? value) writeSetting,
  })  : _read = readSetting,
        _write = writeSetting;

  final StudyDocument _doc;
  final Object? Function(String) _read;
  final void Function(String, Object?) _write;

  /// Scheduling state per card id. Workspace-scoped and **not synced**: when
  /// you should review is personal, and pushing it through the op log would
  /// make one person's review schedule everyone's on a shared notebook.
  final Map<String, CardState> _cardStates = {};

  /// Reviews per local calendar day (P1). Workspace-wide and **not** per
  /// notebook: a streak is a fact about the student's week, not about one
  /// subject, and splitting it per notebook would mean a diligent week spent
  /// across three modules showed as three broken streaks.
  final StudyDays _studyDays = {};

  /// Exam day per section, keyed `'<notebookId>:<sectionId>'` → `'yyyy-mm-dd'`.
  ///
  /// Workspace settings rather than the node envelope, matching where card
  /// schedules and favourites already live. The node envelope would put the
  /// date in the op log, i.e. push *your* exam date onto everyone sharing a
  /// group notebook — and the format is frozen at v1, so adding a field there
  /// is a format decision rather than a feature. If it should ever be shared,
  /// that is the migration; nothing here forecloses it.
  ///
  /// A `yyyy-mm-dd` string, not an epoch: an exam is a day in a calendar, and
  /// an instant would land on the wrong side of midnight for anyone whose
  /// timezone shifts between setting it and reading it back.
  final Map<String, String> _examDates = {};

  /// Closed-page cards, keyed by scope.
  ///
  /// **This cache is not an optimisation, it is a correctness-of-experience
  /// fix.** Building a deck reads and JSON-decodes *every page in the
  /// notebook* from SQLite. The study button lives in the command bar, which
  /// rebuilds on every notify — i.e. every keystroke — so an uncached deck
  /// meant ~324 database reads per character typed on a real notebook, and the
  /// app crawled. Any widget that shows a count must go through here.
  ///
  /// A **map**, not one slot, because several scopes are asked for in the same
  /// frame: the deck picker shows this-page / this-section / whole-notebook
  /// counts side by side, and `_persistCardStates` prunes against the whole
  /// notebook while the panel is scoped to a section. With one slot those
  /// alternating keys evict each other, so every single call would re-read the
  /// entire notebook — the exact regression the cache exists to prevent, with
  /// the cache still nominally in place. Bounded because scopes are few and a
  /// stale entry costs memory for a deck nobody is looking at.
  final Map<String, List<Flashcard>> _deckCache = {};
  static const _deckCacheMax = 6;

  /// Every block id the last whole-notebook deck build walked past.
  ///
  /// Needed because card scheduling is stored per WORKSPACE while a deck is
  /// per NOTEBOOK: without knowing which ids belong to the notebook in front
  /// of us, pruning "everything not in this deck" deletes every other
  /// notebook's review history. See [_persistCardStates].
  Set<String> _notebookBlockIds = const {};

  /// The OPEN page's cards, held separately from [_deckCache].
  ///
  /// Two caches rather than one, because the two halves go stale for different
  /// reasons and cost wildly different amounts to rebuild. Closed pages come
  /// from SQLite and only change structurally; the open page changes on every
  /// keystroke but is already in memory. Merging them into one key meant either
  /// re-reading the whole notebook per character (the regression) or a tagged
  /// line producing no card until you navigated away (the bug).
  ({String key, List<Flashcard> cards})? _liveDeckCache;

  /// Bumped whenever the open page's content changes, so the live half of the
  /// deck rebuilds — once per edit, not once per widget rebuild.
  int _contentRevision = 0;

  /// Bumped whenever anything this object owns changes — a card's schedule, an
  /// exam date — so surfaces built on it can key a cache off it.
  ///
  /// Exam dates count, and that is not cosmetic: the planner's agenda is cached
  /// on this counter, so a `setExamDate` that only notified would repaint a
  /// panel that then rebuilt the *same cached agenda* and showed no date at
  /// all.
  int studyRevision = 0;

  /// The open page was edited.
  ///
  /// A method rather than a public counter: what `AppState.markDirty` knows is
  /// "the page changed", and how finely this class chooses to rebuild from that
  /// is nobody else's business. Deliberately does **not** notify — it is called
  /// on every keystroke, and `markDirty` is already notifying.
  void noteContentChanged() => _contentRevision++;

  /// Restore persisted state. Called once, from `AppState.init`.
  void load() {
    final cs = _read('cardStates');
    if (cs is Map) {
      cs.forEach((k, v) => _cardStates['$k'] = CardState.fromJson(v));
    }
    final sd = _read('studyDays');
    if (sd is Map) {
      sd.forEach((k, v) {
        final n = (v as num?)?.toInt() ?? 0;
        if (n > 0 && parseDayKey('$k') != null) _studyDays['$k'] = n;
      });
    }
    final ex = _read('examDates');
    if (ex is Map) {
      ex.forEach((k, v) {
        if (v is String && parseDayKey(v) != null) _examDates['$k'] = v;
      });
    }
  }

  // ── The deck ──────────────────────────────────────────────────────────

  /// Every card in a scope, in page order.
  ///
  /// Scope narrows outward-in: [pageId] beats [sectionId] beats the whole
  /// notebook. Pages ARE the deck structure — a lecture page is a deck without
  /// anyone having to build one.
  List<Flashcard> deck({String? sectionId, String? pageId}) {
    if (_doc.notebookId == null) return const [];
    final openId = _doc.pageId;
    bool inScope(TreeNode n) =>
        n.kind == NodeKind.page &&
        (pageId == null || n.id == pageId) &&
        (sectionId == null || n.parentId == sectionId);

    // Closed pages. nodesRevision covers pages added/renamed/removed;
    // docRevision covers a page's stored content being replaced wholesale.
    final key = '${_doc.notebookId}#$sectionId#$pageId'
        '#${_doc.docRevision}#${_doc.nodesRevision}#$openId';
    var stored = _deckCache[key];
    if (stored == null) {
      // A revision bumped: every entry keyed on the old one is dead weight.
      if (_deckCache.length >= _deckCacheMax) _deckCache.clear();
      final out = <Flashcard>[];
      final seen = <String>{};
      for (final n in _doc.nodes.where(inScope)) {
        if (n.id == openId) continue; // the live half, below
        for (final b in _doc.readPage(n.id).blocks) {
          seen.add(b.id);
          out.addAll(cardsFromBlock(b, n.id, n.title));
        }
      }
      // Only the unscoped build sees the whole notebook, so only it may
      // answer "does this block belong to us?".
      if (sectionId == null && pageId == null) {
        _notebookBlockIds = seen..addAll(_doc.blocks.map((b) => b.id));
      }
      _deckCache[key] = stored = out;
    }

    final open =
        _doc.nodes.where((n) => n.id == openId && inScope(n)).firstOrNull;
    if (open == null) return stored;
    // _contentRevision covers edits; docRevision covers the block list being
    // replaced under us — an undo, a version restore, a sync pull.
    final liveKey =
        '${open.id}#${open.title}#$_contentRevision#${_doc.docRevision}';
    var live = _liveDeckCache?.key == liveKey ? _liveDeckCache!.cards : null;
    if (live == null) {
      final out = <Flashcard>[];
      for (final b in _doc.blocks) {
        out.addAll(cardsFromBlock(b, open.id, open.title));
      }
      _liveDeckCache = (key: liveKey, cards: live = out);
    }
    if (live.isEmpty) return stored;
    if (stored.isEmpty) return live;
    return [...stored, ...live];
  }

  /// Scheduling state for a card. **Read-only**: a card that has never been
  /// graded must not be written just because something asked about it, or the
  /// settings blob grows with every card the student merely looked at.
  CardState cardState(String cardId) => _cardStates[cardId] ?? CardState();

  /// Cards for one sitting.
  ///
  /// [StudyMode.due] is the real schedule: what spaced repetition says you
  /// should see, most-overdue first, capped so a session ends — a deck of 400
  /// with no cap is a wall a student bounces off.
  ///
  /// [StudyMode.cram] ignores the schedule entirely and shuffles. It exists
  /// because "I want to go over this again" is the single most common thing a
  /// student wants the night before an exam, and a review app that answers it
  /// with "nothing due" is useless to them.
  List<Flashcard> sessionCards({
    String? sectionId,
    String? pageId,
    StudyMode mode = StudyMode.due,
    int max = 40,
  }) {
    final all = deck(sectionId: sectionId, pageId: pageId);
    if (mode == StudyMode.cram) {
      final shuffled = [...all]..shuffle();
      return shuffled.length <= max ? shuffled : shuffled.sublist(0, max);
    }
    final now = nowMs();
    final due = [
      for (final c in all)
        if (cardState(c.id).isDue(now)) c
    ]..sort((a, b) => cardState(a.id).dueAt.compareTo(cardState(b.id).dueAt));
    return due.length <= max ? due : due.sublist(0, max);
  }

  /// Kept for callers that only want the schedule.
  List<Flashcard> dueCards({String? sectionId, int max = 40}) =>
      sessionCards(sectionId: sectionId, max: max);

  /// Record a grade.
  ///
  /// [schedule] false is cram mode: going over a card early must not push its
  /// real due date out, or a night of cramming silently wipes weeks of
  /// spacing. Getting one WRONG still counts — that is information about the
  /// card regardless of why you were looking at it.
  void gradeCard(String cardId, Grade g, {bool schedule = true}) {
    // Counted BEFORE the cram-mode early return, and that placement is the
    // decision: an hour of practice the night before an exam is the most
    // studying a student will do all term, and a streak that ignored it would
    // punish them for the one session that mattered most. What is recorded
    // here is "you sat down and worked", which is true in both modes; the
    // schedule is what practice leaves alone.
    _recordReview();
    if (!schedule && g != Grade.again) {
      studyRevision++;
      notifyListeners();
      return;
    }
    final s = _cardStates.putIfAbsent(cardId, CardState.new);
    applyGrade(s, g, nowMs());
    _persistCardStates();
    studyRevision++;
    notifyListeners();
  }

  /// Carry review schedules across when a block's tags change line.
  ///
  /// A card's identity is `blockId:line` — chosen because it survives edits to
  /// other lines with no extra bookkeeping — so re-basing a tag *renames its
  /// card*. Without this the schedule is orphaned under the old name and the
  /// next prune deletes it: press Enter above a tagged line and weeks of
  /// spacing are gone, from a keystroke that changed nothing about the card.
  ///
  /// Removed first, then re-added, so a run of tags shifting by one can't
  /// overwrite each other on the way past.
  void remapCardStates(String blockId, Map<int, int> moved) {
    if (moved.isEmpty) return;
    final carried = <String, CardState>{};
    for (final e in moved.entries) {
      if (e.key == e.value) continue;
      final s = _cardStates.remove('$blockId:${e.key}');
      if (s != null) carried['$blockId:${e.value}'] = s;
    }
    if (carried.isEmpty) return;
    _cardStates.addAll(carried);
    _writeCardStates();
    studyRevision++;
  }

  /// Forget a card's schedule — it becomes new again.
  void resetCard(String cardId) {
    if (_cardStates.remove(cardId) == null) return;
    _persistCardStates();
    studyRevision++;
    notifyListeners();
  }

  /// Forget every schedule in a scope. Returns how many were cleared.
  int resetDeck({String? sectionId, String? pageId}) {
    var n = 0;
    for (final c in deck(sectionId: sectionId, pageId: pageId)) {
      if (_cardStates.remove(c.id) != null) n++;
    }
    if (n == 0) return 0;
    _persistCardStates();
    studyRevision++;
    notifyListeners();
    return n;
  }

  void _writeCardStates() => _write('cardStates',
      {for (final e in _cardStates.entries) e.key: e.value.toJson()});

  void _persistCardStates() {
    // Prune as we write: a card id is `blockId:line`, so untagging a line
    // strands its schedule forever otherwise, and this blob is loaded on every
    // start.
    //
    // **Scoped to this notebook, and that is not a detail.** The blob is
    // workspace-wide but a deck is per notebook, so pruning "everything not in
    // this deck" deleted every OTHER notebook's review history the first time
    // you graded a card after switching — a term of spaced repetition gone,
    // silently, with no undo. An entry is only removed when we can see that
    // its block is one of ours and no longer produces that card.
    //
    // The deliberate leak: a card whose block was DELETED is not in
    // `_notebookBlockIds` either, so its state survives. Keeping a few dead
    // rows costs bytes; guessing wrong costs somebody their schedule.
    final alive = {for (final c in deck()) c.id};
    final mine = _notebookBlockIds;
    _cardStates.removeWhere((k, _) {
      if (alive.contains(k)) return false;
      final cut = k.lastIndexOf(':');
      return mine.contains(cut < 0 ? k : k.substring(0, cut));
    });
    _writeCardStates();
  }

  /// Counts for the study surface: (due now, total).
  (int, int) deckCounts({String? sectionId}) {
    final s = deckStats(sectionId: sectionId);
    return (s.due, s.total);
  }

  /// Everything a study surface needs to say something useful.
  ///
  /// [nextDueAt] is what turns "Nothing due" — a dead end that reads like the
  /// feature is broken — into "All caught up, next card in 6h".
  ({int due, int total, int unseen, int? nextDueAt}) deckStats(
      {String? sectionId, String? pageId}) {
    final all = deck(sectionId: sectionId, pageId: pageId);
    final now = nowMs();
    var due = 0, unseen = 0;
    int? next;
    for (final c in all) {
      final s = cardState(c.id);
      if (s.dueAt == 0) unseen++;
      if (s.isDue(now)) {
        due++;
      } else if (next == null || s.dueAt < next) {
        next = s.dueAt;
      }
    }
    return (due: due, total: all.length, unseen: unseen, nextDueAt: next);
  }

  // ── Stats and the exam countdown (P1) ─────────────────────────────────

  /// Add one to today's tally.
  void _recordReview([DateTime? now]) {
    final today = now ?? DateTime.now();
    _studyDays.update(dayKey(today), (n) => n + 1, ifAbsent: () => 1);
    // Pruned on write rather than on read: the map is loaded once per launch
    // and read on every panel build, so paying for the scan at the point it
    // changes keeps it off the surface that repaints.
    final kept = pruneStudyDays(_studyDays, today);
    if (kept.length != _studyDays.length) {
      _studyDays
        ..clear()
        ..addAll(kept);
    }
    _write('studyDays', _studyDays);
  }

  /// Cards graded today, in every notebook.
  int reviewsToday([DateTime? now]) =>
      _studyDays[dayKey(now ?? DateTime.now())] ?? 0;

  /// Consecutive days studied, ending today or yesterday (see [studyStreak]).
  int studyStreakDays([DateTime? now]) =>
      studyStreak(_studyDays, now ?? DateTime.now());

  /// Reviews on each of the last [days] days, oldest first.
  List<int> studyActivity({int days = 14, DateTime? now}) =>
      activityBars(_studyDays, now ?? DateTime.now(), n: days);

  /// True once there is any history at all — the surface stays hidden until
  /// there is something to show, so a first-time user isn't greeted by a row
  /// of zeroes telling them they have done nothing.
  bool get hasStudyHistory => _studyDays.isNotEmpty;

  String _examKey(String sectionId) => '${_doc.notebookId}:$sectionId';

  /// The exam day set for a section, if any.
  DateTime? examDate(String? sectionId) {
    if (sectionId == null || _doc.notebookId == null) return null;
    final s = _examDates[_examKey(sectionId)];
    return s == null ? null : parseDayKey(s);
  }

  /// Set or (with null) clear a section's exam day.
  void setExamDate(String sectionId, DateTime? date) {
    if (_doc.notebookId == null) return;
    final key = _examKey(sectionId);
    if (date == null) {
      if (_examDates.remove(key) == null) return;
    } else {
      final v = dayKey(date);
      if (_examDates[key] == v) return;
      _examDates[key] = v;
    }
    _write('examDates', _examDates);
    studyRevision++;
    notifyListeners();
  }

  /// The countdown for a deck, or null when that section has no exam set.
  ///
  /// Scoped to one section on purpose. A per-day target computed across a
  /// whole notebook would be counting three subjects' cards towards one
  /// subject's exam — see [nextExam] for what the whole-notebook view says
  /// instead, which is context rather than a plan.
  ExamPlan? examPlanFor({String? sectionId, String? pageId, DateTime? now}) {
    final id = sectionId ?? _doc.activeSectionId;
    final exam = examDate(id);
    if (exam == null) return null;
    final s = deckStats(sectionId: sectionId, pageId: pageId);
    return examPlan(
      exam: exam,
      today: now ?? DateTime.now(),
      unseen: s.unseen,
      total: s.total,
    );
  }

  /// The soonest exam still ahead in this notebook, with the section it
  /// belongs to. What the whole-notebook scope shows: still a reason to open
  /// the panel, without pretending a mixed deck has one revision plan.
  ///
  /// **Two passes, and the second one runs once.** Finding the soonest date is
  /// free — it reads a map of strings. Counting a deck is not: it walks every
  /// page of a section out of SQLite, and the deck cache holds six entries
  /// before clearing itself. Costing a deck per exam-dated section would
  /// therefore evict the cache on a panel that rebuilds with every keystroke,
  /// which is precisely the regression the cache was added to stop.
  ({TreeNode section, ExamPlan plan})? nextExam([DateTime? now]) {
    if (_doc.notebookId == null) return null;
    final today = now ?? DateTime.now();
    TreeNode? soonest;
    DateTime? soonestDate;
    var bestLeft = 0;
    for (final n in _doc.nodes) {
      if (n.kind != NodeKind.section) continue;
      final d = examDate(n.id);
      if (d == null) continue;
      final left = daysBetween(today, d);
      if (left < 0) continue;
      if (soonest != null && left >= bestLeft) continue;
      soonest = n;
      soonestDate = d;
      bestLeft = left;
    }
    if (soonest == null) return null;
    final s = deckStats(sectionId: soonest.id);
    return (
      section: soonest,
      plan: ExamPlan(
          date: soonestDate!, daysLeft: bestLeft, unseen: s.unseen, total: s.total),
    );
  }
}
