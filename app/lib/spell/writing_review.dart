/// **Review writing**: every spelling, grammar and punctuation suggestion on the
/// page, in one place, with a way to take them one at a time or all at once.
///
/// The editor underlines what is wrong in the box being written in. This looks
/// at the WHOLE page (every text box, not just the one with the caret) and keeps
/// the answers so a person can sit down at the end and clear them: accept or
/// ignore each, or press one **Fix all** per kind of mistake.
///
/// **English only, like everything that checks.** [available] is false whenever
/// the person is not writing English (`AppState.writingDialect` is null), and
/// then nothing is checked, nothing is counted and the panel does not exist.
///
/// **What is edited.** A fix is a replacement inside a text box's Markdown, in
/// place, through the same path Find and Replace uses: one undo step for a
/// batch, `markDirty`, and a bump of `docRevision` so open editors reload. The
/// text is compared with what was checked before anything is written, and a box
/// that has changed since is skipped rather than patched at the wrong place.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/onote_text.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import 'spell_checker.dart';
import 'writing_checker.dart';

/// The three kinds of mistake the panel keeps apart, each with its own **Fix
/// all**: so "fix every spelling mistake" and "fix every grammar one" are
/// separate choices.
enum ReviewCategory {
  spelling,
  grammar,
  punctuation;

  /// Which one the checker's finding belongs to. Capitals, repeated words and
  /// wording are all grammar here; punctuation is its own.
  static ReviewCategory of(TextFinding f) => switch (f.kind) {
        'spelling' => spelling,
        'punctuation' => punctuation,
        _ => grammar,
      };
}

/// One suggestion on the page.
class ReviewItem {
  const ReviewItem(
      {required this.blockId, required this.finding, required this.text});

  /// The text box it is in.
  final String blockId;
  final TextFinding finding;

  /// The box's whole text when it was checked, so the card can show the words
  /// around the mistake without asking again.
  final String text;

  ReviewCategory get category => ReviewCategory.of(finding);

  /// What it could become, best first. For spelling these are matched to the
  /// word's capitals; for the rest, as the checker gave them.
  List<String> get choices => category == ReviewCategory.spelling
      ? WritingChecker.suggestionsFor(finding.word, fixes: finding.fixes)
      : finding.fixes;

  /// Whether it can be accepted at all. Some findings are advice with nothing
  /// to put in the text, and those can only be ignored.
  bool get canFix => choices.isNotEmpty;

  String? get firstChoice => choices.isEmpty ? null : choices.first;

  /// Unique on the page and stable while the text is untouched.
  String get key =>
      '$blockId:${finding.start}:${finding.end}:${finding.word}';

  /// A few words before and after, for the card.
  ({String before, String after}) get around {
    final s = finding.start.clamp(0, text.length);
    final e = finding.end.clamp(s, text.length);
    var b = text.substring(s - 40 < 0 ? 0 : s - 40, s);
    var a = text.substring(e, e + 40 > text.length ? text.length : e + 40);
    b = b.contains('\n') ? b.substring(b.lastIndexOf('\n') + 1) : b;
    a = a.contains('\n') ? a.substring(0, a.indexOf('\n')) : a;
    return (before: b, after: a);
  }
}

typedef WritingCheck = Future<WritingResult> Function(
  String text, {
  required EnglishDialect? dialect,
  required bool spelling,
  required bool grammar,
});

class WritingReview extends ChangeNotifier {
  WritingReview(this.app, {WritingCheck? check})
      : _check = check ?? WritingChecker.check {
    // Where things stand now, so only a CHANGE from here is a new page.
    _seenPage = app.pageId;
    _seenRevision = app.docRevision;
    _seenSignature = _signature();
    app.addListener(_onApp);
    // Made when the status bar first needs it, which is after the page is
    // already open: nothing would otherwise ask for the first look until the
    // next edit, and the chip would wait for it.
    noteChanged(soon: true);
  }

  final AppState app;
  final WritingCheck _check;

  /// How long to wait after the last edit before looking again. Long enough
  /// that typing is not interrupted, short enough that the count is current by
  /// the time anyone looks at it.
  static const Duration quiet = Duration(milliseconds: 800);

  List<ReviewItem> _items = const [];
  bool _checked = false;
  bool _disposed = false;
  Timer? _timer;
  int _generation = 0;

  /// Where the last look was taken, so a change of page, of language or of
  /// settings is noticed.
  String? _seenPage;
  int _seenRevision = -1;
  String? _seenSignature;

  /// The last answer for each text box, by id, so a look at a page costs one
  /// check per box that has changed rather than one per box.
  final Map<String, ({String text, List<TextFinding> found})> _cache = {};

  /// The item the card is open on.
  String? _currentKey;

  // ── What the rest of the app asks ─────────────────────────────────────────

  /// Whether this exists for the person at all: they write English, and a
  /// check is switched on, and the page is one that may be read.
  bool get available {
    if (app.writingDialect == null) return false;
    if (!app.spellCheckEnabled && !app.grammarCheckEnabled) return false;
    final page = app.pageId;
    return page != null && !app.isLocked(page);
  }

  /// A look at this page has finished at least once.
  bool get checked => available && _checked;

  List<ReviewItem> get items => available ? _items : const [];
  int get count => items.length;

  List<ReviewItem> itemsOf(ReviewCategory c) =>
      [for (final i in items) if (i.category == c) i];

  /// The kind the panel is showing on its own, when it shows one at a time (the
  /// sheet's tabs). The side panel lists all three and leaves this null.
  ReviewCategory? focusCategory;

  /// The item whose card is open. **Always one**: with nothing chosen it is the
  /// top of the list (or of the tab on show), so the first suggestion arrives
  /// opened and it is plain that every one can be. Clicking another row moves
  /// it there.
  ReviewItem? get current {
    final list = items;
    if (list.isEmpty) return null;
    final cat = focusCategory;
    final k = _currentKey;
    final hit = k == null ? null : list.where((i) => i.key == k).firstOrNull;
    if (hit != null && (cat == null || hit.category == cat)) return hit;
    final pool =
        cat == null ? list : [for (final i in list) if (i.category == cat) i];
    return pool.isEmpty ? list.first : pool.first;
  }

  // ── Looking ───────────────────────────────────────────────────────────────

  String _signature() =>
      '${app.writingDialect?.code}:${app.spellCheckEnabled}:${app.grammarCheckEnabled}';

  void _onApp() {
    if (_disposed) return;
    final sig = _signature();
    if (app.pageId != _seenPage ||
        app.docRevision != _seenRevision ||
        sig != _seenSignature) {
      final newPage = app.pageId != _seenPage;
      _seenPage = app.pageId;
      _seenRevision = app.docRevision;
      if (sig != _seenSignature) _cache.clear();
      _seenSignature = sig;
      if (newPage) {
        _items = const [];
        _checked = false;
        _currentKey = null;
        _cache.clear();
        notifyListeners();
      }
      noteChanged(soon: true);
    }
  }

  /// The page's text changed (or has just been shown): look again once things
  /// have gone quiet.
  void noteChanged({bool soon = false}) {
    if (_disposed) return;
    _timer?.cancel();
    if (!available) {
      if (_items.isNotEmpty || _checked) {
        _items = const [];
        _checked = false;
        notifyListeners();
      }
      return;
    }
    // The ROOT zone's timer, on purpose: this runs behind the person's back, and
    // a timer in the zone a widget test runs in is one the test must wait out
    // before it may end. Nothing here is the test's business, and in the app the
    // root zone is simply the real clock.
    _timer = Zone.root.createTimer(
        soon ? const Duration(milliseconds: 50) : quiet, () {
      if (!_disposed) unawaited(refresh());
    });
  }

  /// Stops a pending look. For tests, which must not end with a timer running.
  void cancelPending() {
    _timer?.cancel();
    _generation++;
  }

  /// Check every text box on the page now.
  Future<void> refresh() async {
    if (_disposed || !available) return;
    final gen = ++_generation;
    final dialect = app.writingDialect;
    final spelling = app.spellCheckEnabled;
    final grammar = app.grammarCheckEnabled;
    final boxes = [
      for (final b in app.blocks)
        if (b.type == BlockType.text &&
            (b.content['text'] as String? ?? '').trim().isNotEmpty)
          b
    ]..sort((a, b) {
        final dy = a.y.compareTo(b.y);
        return dy != 0 ? dy : a.x.compareTo(b.x);
      });
    final live = {for (final b in boxes) b.id};
    _cache.removeWhere((id, _) => !live.contains(id));

    final out = <ReviewItem>[];
    for (final b in boxes) {
      final text = b.content['text'] as String? ?? '';
      var hit = _cache[b.id];
      if (hit == null || hit.text != text) {
        // A checker that fails is a box with nothing found, not a panel that
        // stops working.
        final r = await _check(text,
                dialect: dialect, spelling: spelling, grammar: grammar)
            .catchError((Object _) => WritingResult.empty);
        if (_disposed || gen != _generation) return;
        final found = <TextFinding>[
          ...r.spellingFindings,
          ...r.grammar,
          // The old word list answers with ranges only: keep them, with no
          // suggestion attached.
          if (r.spellingFindings.isEmpty)
            for (final t in r.spelling)
              TextFinding(
                  start: t.start,
                  end: t.end,
                  kind: 'spelling',
                  message: '',
                  word: text.substring(t.start, t.end),
                  fixes: const []),
        ]..sort((a, c) => a.start.compareTo(c.start));
        hit = (text: text, found: found);
        _cache[b.id] = hit;
      }
      for (final f in hit.found) {
        if (app.isWritingIgnored(b.id, text, f)) continue;
        if (f.isSpelling && learnedWords.contains(f.word.toLowerCase())) {
          continue;
        }
        out.add(ReviewItem(blockId: b.id, finding: f, text: text));
      }
    }
    if (_disposed || gen != _generation) return;
    _items = out;
    _checked = true;
    if (_currentKey != null && current == null) _currentKey = null;
    notifyListeners();
  }

  // ── The open card ─────────────────────────────────────────────────────────

  /// Open [item]'s card and take the page to it.
  void open(ReviewItem item) {
    _currentKey = item.key;
    app.jumpToBlock(item.blockId, smooth: true);
    notifyListeners();
  }

  /// Take the page to the open item. The card is open from the start, but the
  /// page is only moved when someone chooses.
  void openFirst() {
    final cur = current;
    if (cur != null) open(cur);
  }

  /// Up or down the list, wrapping at the ends.
  void step(int delta) {
    final cat = focusCategory;
    final list =
        cat == null ? items : [for (final i in items) if (i.category == cat) i];
    if (list.isEmpty) return;
    final k = current?.key;
    final i = list.indexWhere((x) => x.key == k);
    final next = i < 0
        ? (delta > 0 ? 0 : list.length - 1)
        : (i + delta + list.length) % list.length;
    open(list[next]);
  }

  /// After [gone] is dealt with, the card moves on to what came after it.
  void _advanceFrom(ReviewItem gone, List<ReviewItem> before) {
    final i = before.indexWhere((x) => x.key == gone.key);
    final rest = items;
    if (rest.isEmpty) {
      _currentKey = null;
      return;
    }
    // What was just below it is now at its place in the list.
    _currentKey = rest[(i < 0 ? 0 : i).clamp(0, rest.length - 1)].key;
  }

  // ── Doing ─────────────────────────────────────────────────────────────────

  /// Put [choice] (or the first suggestion) in place of [item]'s words.
  /// Returns false when it could not be done (nothing to put there, or the box
  /// has changed since it was checked).
  bool accept(ReviewItem item, {String? choice}) {
    final pick = choice ?? item.firstChoice;
    if (pick == null) return false;
    final before = items;
    final n = _apply([(item, pick)], undoStep: true);
    if (n == 0) return false;
    _advanceFrom(item, before);
    notifyListeners();
    return true;
  }

  /// Fix everything of one kind that has a suggestion. One undo step for the
  /// lot. Returns how many were fixed.
  int fixAll(ReviewCategory c) {
    final edits = [
      for (final i in itemsOf(c))
        if (i.firstChoice != null) (i, i.firstChoice!)
    ];
    if (edits.isEmpty) return 0;
    final n = _apply(edits, undoStep: true);
    _currentKey = items.firstOrNull?.key;
    notifyListeners();
    return n;
  }

  /// Leave this one as it is, and do not offer it again in this place.
  void ignore(ReviewItem item) {
    final before = items;
    app.ignoreWriting(item.blockId, item.text, item.finding);
    _items = [for (final i in _items) if (i.key != item.key) i];
    _advanceFrom(item, before);
    notifyListeners();
  }

  /// A word that is right and not in the dictionary (a name, jargon). Teaches
  /// the dictionary and drops every other place that word was flagged.
  void addToDictionary(ReviewItem item) {
    if (!item.finding.isSpelling) return;
    final before = items;
    final w = item.finding.word.toLowerCase();
    learnWord(item.finding.word);
    _items = [
      for (final i in _items)
        if (!(i.finding.isSpelling && i.finding.word.toLowerCase() == w)) i
    ];
    _advanceFrom(item, before);
    // Open editors underline from their own check: have them look again.
    app.docRevision++;
    app.refresh();
    notifyListeners();
  }

  /// Write [edits] into their boxes. Within one box they are applied from the
  /// end backwards so each one's offsets are still right, then everything else
  /// still listed for that box is moved by what was added or taken away.
  int _apply(List<(ReviewItem, String)> edits, {required bool undoStep}) {
    var applied = 0;
    final byBlock = <String, List<(ReviewItem, String)>>{};
    for (final e in edits) {
      byBlock.putIfAbsent(e.$1.blockId, () => []).add(e);
    }
    var pushed = false;
    final done = <String>{};
    final moved = <String, List<({int at, int from, int delta})>>{};
    for (final entry in byBlock.entries) {
      final b = app.blockById(entry.key);
      if (b == null || b.type != BlockType.text) continue;
      var text = b.content['text'] as String? ?? '';
      final list = entry.value
        ..sort((a, c) => c.$1.finding.start.compareTo(a.$1.finding.start));
      var changed = false;
      var floor = text.length + 1;
      for (final (item, pick) in list) {
        final f = item.finding;
        // Stale (the text moved on) or overlapping one already done: skip.
        if (f.end > text.length ||
            f.end > floor ||
            text.substring(f.start, f.end) != f.word) {
          continue;
        }
        if (!pushed && undoStep) {
          app.pushUndo();
          pushed = true;
        }
        text = text.replaceRange(f.start, f.end, pick);
        floor = f.start;
        changed = true;
        applied++;
        done.add(item.key);
        moved.putIfAbsent(entry.key, () => []).add((
          at: f.start,
          from: f.end,
          delta: pick.length - (f.end - f.start)
        ));
      }
      if (changed) {
        b.content['text'] = text;
        _cache.remove(b.id);
      }
    }
    if (applied == 0) return 0;

    // What is left for those boxes: shifted if it lies after an edit, dropped
    // if it overlapped one (a fresh look will find it again if it still holds).
    final next = <ReviewItem>[];
    for (final i in _items) {
      if (done.contains(i.key)) continue;
      final shifts = moved[i.blockId];
      if (shifts == null) {
        next.add(i);
        continue;
      }
      final b = app.blockById(i.blockId);
      // In the coordinates the text had BEFORE the edits: wholly after one
      // moves by what it added or took away; wholly before it stays; anything
      // between is an overlap and is dropped.
      final os = i.finding.start, oe = i.finding.end;
      var shift = 0;
      var drop = false;
      for (final s in shifts) {
        if (os >= s.from) {
          shift += s.delta;
        } else if (oe > s.at) {
          drop = true;
        }
      }
      final start = os + shift, end = oe + shift;
      if (drop || b == null) continue;
      final f = i.finding;
      next.add(ReviewItem(
          blockId: i.blockId,
          text: b.content['text'] as String? ?? '',
          finding: TextFinding(
              start: start,
              end: end,
              kind: f.kind,
              message: f.message,
              word: f.word,
              fixes: f.fixes)));
    }
    _items = next;
    app.markDirty();
    app.docRevision++;
    return applied;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    app.removeListener(_onApp);
    super.dispose();
  }
}
