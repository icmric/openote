/// Making a subscribed timetable *useful* rather than merely visible (v0.8 §2).
///
/// **The problem this solves.** A university feed is a wall of near-identical
/// rows — `31251 Programming Fundamentals, Lecture (Online)` forty times over —
/// and Openote was showing them as forty undifferentiated bullets. The student's
/// actual question is never "list my events"; it is *"what is next, do I have to
/// physically go, and where is the link"*. Answering that needs two derived
/// facts the feed does not state outright:
///
/// - **What kind of thing is this** — a lecture you might join from bed, a lab
///   you must be in a room for, an exam. This is what makes a per-kind alert
///   setting possible, which is the difference between "notify me about all 34
///   things this week" (useless, switched off within a day) and "tell me ten
///   minutes before a lecture" (the thing that was asked for).
/// - **Is there a link to join**, and to what.
///
/// **Both are heuristics, and the code treats them as such.** Nothing here is
/// allowed to *hide* an event, change its time, or open anything by itself; the
/// worst a wrong guess can do is put an event under the wrong heading or fail to
/// offer a Join button that would have worked. That asymmetry is deliberate —
/// see [classifyEvent] for why the matching is conservative rather than clever.
///
/// Pure Dart, no Flutter: the icon and colour for a kind belong to the UI, and
/// keeping them out means this whole file is testable against strings.
library;

import 'ics.dart';

/// What sort of commitment an event is.
///
/// Deliberately a small, closed set. Every extra kind is another row in the
/// alert settings, and a settings screen with fourteen switches is one nobody
/// configures — the [other] bucket is doing useful work by existing.
enum EventKind {
  lecture('lecture', 'Lecture'),
  tutorial('tutorial', 'Tutorial'),
  lab('lab', 'Lab / practical'),
  workshop('workshop', 'Workshop'),
  seminar('seminar', 'Seminar'),
  exam('exam', 'Exam / test'),
  meeting('meeting', 'Meeting'),
  other('other', 'Everything else');

  const EventKind(this.key, this.label);

  /// Stable across releases — it is a settings key. Never rename one of these
  /// without a migration; a renamed key silently resets the user's alerts.
  final String key;

  /// What the settings row says.
  final String label;

  static EventKind? parse(String? key) {
    for (final k in values) {
      if (k.key == key) return k;
    }
    return null;
  }
}

/// The words that identify each kind, most specific first.
///
/// Ordering matters: `'lab'` must be tested after `'collaborate'` cannot match
/// it (see the word-boundary rule in [classifyEvent]), and `exam` is checked
/// before everything so that "Exam — Lecture Theatre 2" is an exam rather than
/// a lecture. That single case is why this is an ordered list and not a map.
const List<(EventKind, List<String>)> _kindWords = [
  (EventKind.exam, ['exam', 'final', 'midterm', 'quiz', 'test', 'assessment']),
  (EventKind.lab, ['lab', 'laboratory', 'practical', 'prac', 'clinic']),
  (EventKind.tutorial, ['tutorial', 'tut', 'tute', 'recitation', 'discussion']),
  (EventKind.workshop, ['workshop', 'studio', 'wshop']),
  (EventKind.seminar, ['seminar', 'colloquium', 'symposium']),
  (EventKind.lecture, ['lecture', 'lec', 'lect', 'class']),
  (EventKind.meeting, ['meeting', 'standup', 'stand-up', 'sync', '1:1', 'catch-up']),
];

/// Guess what kind of event this is.
///
/// **Matches whole words only.** Substring matching was the first attempt and
/// it was wrong within one real feed: `'lab'` matches *Collaborative Practice*
/// and *Syllabus*, `'tut'` matches *Institute* and *Tutankhamun*, `'lec'`
/// matches *Electronics* and *Molecular*. A word-boundary regex costs nothing
/// and removes the whole class of embarrassment.
///
/// **Searches the summary first, then the description**, and stops at the first
/// hit in each. Timetable systems put the activity type in one or the other and
/// there is no way to know which in advance; UTS puts it in the summary
/// (`… - Lecture`), Canvas exports put it in the description. The location is
/// deliberately *not* searched — "Lecture Theatre 3" is where the tutorial is.
EventKind classifyEvent(IcsEvent e) {
  final fromSummary = _classifyText(e.summary);
  if (fromSummary != null) return fromSummary;
  final fromDescription = _classifyText(e.description);
  if (fromDescription != null) return fromDescription;
  return EventKind.other;
}

EventKind? _classifyText(String text) {
  if (text.isEmpty) return null;
  final lower = text.toLowerCase();
  for (final (kind, words) in _kindWords) {
    for (final w in words) {
      if (_containsWord(lower, w)) return kind;
    }
  }
  return null;
}

/// True when [word] appears in [lower] delimited by anything that is not a
/// letter or digit. [lower] must already be lower-case.
///
/// Hand-rolled rather than a `RegExp` per call: this runs once per event per
/// agenda rebuild, and the agenda rebuilds on the keystroke path.
bool _containsWord(String lower, String word) {
  var from = 0;
  while (true) {
    final i = lower.indexOf(word, from);
    if (i < 0) return false;
    final before = i == 0 ? null : lower.codeUnitAt(i - 1);
    final afterIndex = i + word.length;
    final after =
        afterIndex >= lower.length ? null : lower.codeUnitAt(afterIndex);
    if (!_isWordChar(before) && !_isWordChar(after)) return true;
    from = i + 1;
  }
}

bool _isWordChar(int? c) {
  if (c == null) return false;
  return (c >= 0x30 && c <= 0x39) || // 0-9
      (c >= 0x41 && c <= 0x5A) || // A-Z
      (c >= 0x61 && c <= 0x7A); // a-z
}

// ---------------------------------------------------------------------------
// Join links
// ---------------------------------------------------------------------------

/// A meeting link found on an event.
class JoinLink {
  const JoinLink(this.url, this.provider);

  final String url;

  /// A display name — 'Zoom', 'Teams', 'Meet' — or 'Online' when the link is
  /// clearly a meeting but from a system we do not have a name for.
  final String provider;
}

/// Hosts that mean "this is a meeting link", and what to call them.
///
/// Matched against the URL's **host** rather than the whole string, so a
/// lecture whose description happens to mention zoom.us in prose does not
/// produce a Join button that goes to the wrong place.
const Map<String, String> _providers = {
  'zoom.us': 'Zoom',
  'zoom.com': 'Zoom',
  'teams.microsoft.com': 'Teams',
  'teams.live.com': 'Teams',
  'meet.google.com': 'Meet',
  'webex.com': 'Webex',
  'bbcollab.com': 'Collaborate',
  'blackboard.com': 'Blackboard',
  'echo360.net': 'Echo360',
  'echo360.org': 'Echo360',
  'echo360.org.au': 'Echo360',
  'whereby.com': 'Whereby',
  'gather.town': 'Gather',
  'discord.gg': 'Discord',
};

/// The URL to hand a "Join" button, or null when there isn't one.
///
/// **Search order is `URL`, then `LOCATION`, then `DESCRIPTION`**, and a
/// recognised provider always beats an unrecognised link found earlier. The
/// order matters because descriptions are full of *other* links — the unit
/// outline, the reading list, an unsubscribe footer — and offering "Join" on a
/// reading list is worse than offering nothing.
///
/// A bare `http(s)` link with an unknown host is returned **only** from the
/// `URL` property or a `LOCATION` that is nothing but a URL. In a description
/// it is far more likely to be the unit page than the meeting.
JoinLink? joinLink(IcsEvent e) {
  JoinLink? fallback;

  for (final (text, trustBareLinks) in <(String, bool)>[
    (e.url, true),
    (e.location, false),
    (e.description, false),
  ]) {
    if (text.isEmpty) continue;
    final locationIsOnlyAUrl =
        identical(text, e.location) && _looksLikeBareUrl(text);
    for (final url in _urlsIn(text)) {
      final provider = _providerFor(url);
      if (provider != null) return JoinLink(url, provider);
      if (fallback == null && (trustBareLinks || locationIsOnlyAUrl)) {
        fallback = JoinLink(url, 'Online');
      }
    }
  }
  return fallback;
}

bool _looksLikeBareUrl(String s) {
  final t = s.trim();
  return (t.startsWith('http://') || t.startsWith('https://')) &&
      !t.contains(RegExp(r'\s'));
}

String? _providerFor(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase();
  if (host == null || host.isEmpty) return null;
  for (final entry in _providers.entries) {
    if (host == entry.key || host.endsWith('.${entry.key}')) return entry.value;
  }
  return null;
}

/// Every `http(s)` URL in [text], in order.
///
/// Trailing punctuation is trimmed because a link at the end of a sentence in a
/// DESCRIPTION arrives as `https://zoom.us/j/123.` and that trailing full stop
/// is not part of the URL. Closing brackets get the same treatment for
/// `(see https://…)`.
Iterable<String> _urlsIn(String text) sync* {
  final re = RegExp(r'https?://[^\s<>"]+');
  for (final m in re.allMatches(text)) {
    var url = m.group(0)!;
    while (url.isNotEmpty && _isTrailingJunk(url.codeUnitAt(url.length - 1))) {
      url = url.substring(0, url.length - 1);
    }
    if (url.length > 'https://'.length) yield url;
  }
}

bool _isTrailingJunk(int c) =>
    c == 0x2E || // .
    c == 0x2C || // ,
    c == 0x3B || // ;
    c == 0x3A || // :
    c == 0x29 || // )
    c == 0x5D || // ]
    c == 0x3E; // >

// ---------------------------------------------------------------------------
// Alert rules
// ---------------------------------------------------------------------------

/// The lead times offered in the UI, in minutes.
///
/// A short, opinionated list rather than a free-text field: the useful answers
/// are "as it starts", "time to open a laptop" and "time to walk there", and a
/// spinner that can produce 7 minutes invites fiddling instead of deciding.
const List<int> eventAlertLeadChoices = [0, 5, 10, 15, 30, 60];

/// How long before each kind of event Openote should interrupt you, if at all.
///
/// **Everything is off by default, and that is not timidity.** An app that
/// starts popping up thirty-four times a week gets its notifications switched
/// off wholesale in the first week, and then the one alert that mattered is
/// gone too. Off-by-default plus a one-click "remind me before classes" in the
/// planner means the student turns on exactly what they asked for — which is
/// also the only configuration we can be confident they want.
class EventAlertRules {
  const EventAlertRules(this._lead);

  /// Kind → minutes before the start. An absent key means no alert.
  final Map<EventKind, int> _lead;

  static const EventAlertRules none = EventAlertRules({});

  /// The setting most people mean by "remind me before class": the three
  /// teaching kinds, ten minutes out. Exams are deliberately excluded — a
  /// ten-minute warning for an exam is not a useful thing to be told.
  static const EventAlertRules beforeClasses = EventAlertRules({
    EventKind.lecture: 10,
    EventKind.tutorial: 10,
    EventKind.lab: 10,
    EventKind.workshop: 10,
  });

  bool get isEmpty => _lead.isEmpty;

  /// Minutes of warning for [kind], or null when it is off.
  int? leadFor(EventKind kind) => _lead[kind];

  EventAlertRules withLead(EventKind kind, int? minutes) {
    final next = Map<EventKind, int>.from(_lead);
    if (minutes == null) {
      next.remove(kind);
    } else {
      next[kind] = minutes;
    }
    return EventAlertRules(next);
  }

  /// The longest lead time set for anything, or null when nothing is on.
  /// The scheduler uses it to know how far ahead it needs to look.
  int? get maxLead =>
      _lead.isEmpty ? null : _lead.values.reduce((a, b) => a > b ? a : b);

  Map<String, Object?> toJson() => {
        for (final e in _lead.entries) e.key.key: e.value,
      };

  /// Tolerant on purpose: an unknown kind key from a newer release, or a
  /// nonsense value, drops that one row rather than resetting every rule.
  static EventAlertRules fromJson(Object? raw) {
    if (raw is! Map) return none;
    final out = <EventKind, int>{};
    raw.forEach((k, v) {
      final kind = EventKind.parse('$k');
      if (kind == null) return;
      final n = v is num ? v.toInt() : int.tryParse('$v');
      if (n == null || n < 0 || n > 24 * 60) return;
      out[kind] = n;
    });
    return EventAlertRules(out);
  }
}
