/// A pure, dependency-free parser for the slice of RFC 5545 (iCalendar) that a
/// university timetable actually uses.
///
/// **Why this is in-tree and why it takes a String.** ADR-0006 §8 rejected
/// cloud APIs so that Openote never becomes an OAuth client, and the v0.5 plan
/// §4 leans on exactly that: an ICS feed is a plain GET of a text file, so
/// subscribing to a timetable costs the user no account and Openote no stored
/// credentials. This file therefore contains no network code at all — fetching
/// (or reading a local `.ics`) belongs to the caller, which keeps the parser
/// trivially testable and keeps the "no account, ever" promise structural
/// rather than aspirational.
///
/// **What it deliberately does not do.** Dart's core library ships no IANA
/// timezone database, so `DTSTART;TZID=Australia/Sydney:20260805T093000` is
/// read as a *floating* wall-clock time and materialised in the device's local
/// zone. On a device in the feed's own zone that is exactly right, which is the
/// overwhelmingly common case for a student's own timetable. On a device
/// elsewhere every time is wrong by the offset difference. Inventing a
/// conversion from a zone name we cannot resolve would produce confidently
/// wrong lecture times, which is worse than a documented limitation, so the
/// parser reports the TZID it saw (both as [IcsEvent.tzid] and as a warning)
/// and lets the UI say so out loud.
///
/// **Contract.** [parseIcs] never throws and never hangs: every loop is bounded,
/// every recurrence rule is capped, and a malformed feed yields whatever events
/// could be recovered plus warnings explaining what was skipped. A feed that
/// half-parses is the normal case in the wild — an exception would lose the
/// nine hundred good events along with the one bad one.
library;

// ---------------------------------------------------------------------------
// Public surface
// ---------------------------------------------------------------------------

/// One *occurrence* of a calendar event, already flattened out of any
/// recurrence rule and already materialised into a `DateTime` the UI can format
/// directly.
///
/// Every [start] and [end] is a **local** `DateTime` (`isUtc == false`) except
/// where noted below, so `DateFormat.jm().format(e.start)` shows the right
/// thing without the caller remembering to convert. A `DTSTART` in UTC form
/// (`…T093000Z`) is converted to local, which is lossless because the instant
/// is unambiguous; a floating or `TZID` time is taken as local per the library
/// note above.
///
/// [uid] is **not unique across the returned list**: every occurrence of a
/// weekly lecture carries the series' UID, because that is what the UID means
/// in RFC 5545. Callers that need an identity per row must key on
/// `(uid, start)`. A feed that omits UID entirely yields `''` plus a warning —
/// the parser will not invent an identifier, because a synthesised UID would
/// change the moment the summary is edited upstream and would silently break
/// any de-duplication built on top of it.
class IcsEvent {
  /// The series identifier from the feed, or `''` if the producer omitted it.
  /// Shared by every occurrence of a recurring event — see the class note.
  final String uid;

  /// Unescaped `SUMMARY`. Empty rather than null when absent, so the UI never
  /// has to null-check the one field it always renders.
  final String summary;

  /// Unescaped `LOCATION` — the lecture theatre. Empty when absent.
  final String location;

  /// Unescaped `DESCRIPTION`. Empty when absent. May contain newlines: RFC
  /// 5545 encodes them as the two characters `\n`, which this parser decodes.
  final String description;

  /// Local start of this occurrence. See the class note on time zones.
  final DateTime start;

  /// Local end of this occurrence, or null when the feed gave neither `DTEND`
  /// nor `DURATION` (a point-in-time event).
  ///
  /// For an all-day event this is the RFC's **exclusive** end, exactly as the
  /// feed stated it: a one-day event on the 5th has `DTEND;VALUE=DATE:20260806`
  /// and so `end` is midnight on the 6th. Treat it as inclusive and a one-day
  /// event renders as two. It is left exclusive rather than "helpfully"
  /// decremented because the decrement is only correct for the all-day case and
  /// a caller that knows [allDay] can do it in one line.
  final DateTime? end;

  /// True when the feed used `VALUE=DATE` (a whole-day event with no clock
  /// time). [start] is local midnight; see [end] for the exclusive-end trap.
  final bool allDay;

  /// True when the event carried an `RRULE` this parser refused to expand —
  /// anything that is not `FREQ=WEEKLY` with only `COUNT`/`UNTIL`/`INTERVAL`/
  /// `BYDAY`. In that case exactly one occurrence (the `DTSTART` one) is
  /// returned, if it falls in the window.
  ///
  /// The event is never dropped and later occurrences are never guessed at:
  /// a monthly seminar showing once with a "repeats — not shown" marker is
  /// recoverable by the reader, whereas twelve invented dates are not.
  final bool recurrenceUnsupported;

  /// The raw `TZID` parameter as written by the producer, when there was one.
  /// Purely informational — no conversion is performed (see the library note).
  /// Useful for a one-line UI caveat: "times shown in your device's zone".
  final String? tzid;

  const IcsEvent({
    required this.uid,
    required this.summary,
    required this.location,
    required this.description,
    required this.start,
    this.end,
    this.allDay = false,
    this.recurrenceUnsupported = false,
    this.tzid,
  });

  @override
  String toString() => 'IcsEvent(${uid.isEmpty ? '<no uid>' : uid}, '
      '"$summary", $start${end == null ? '' : ' .. $end'}'
      '${allDay ? ', all-day' : ''}'
      '${recurrenceUnsupported ? ', recurrence-not-expanded' : ''})';
}

/// Parse [text] as an iCalendar stream and return every occurrence that
/// overlaps `[windowStart, windowEnd)`, in chronological order, plus warnings
/// describing everything that was skipped or degraded.
///
/// The window is half-open — an occurrence starting exactly at [windowEnd] is
/// excluded, one starting exactly at [windowStart] is included — so consecutive
/// windows (a "next 7 days" refreshed daily) neither duplicate nor drop rows.
/// A zero-length occurrence is included when it falls inside; a timed one is
/// included when it is still running at [windowStart], so the lecture you are
/// currently sitting in does not vanish from the agenda at the top of the hour.
///
/// Bounding the result by a window is not an optimisation, it is what makes the
/// function total: `RRULE:FREQ=WEEKLY` with neither `COUNT` nor `UNTIL` is an
/// infinite set, and a university feed publishes those by the hundred.
///
/// Never throws. If [windowEnd] is not after [windowStart] the result is empty
/// with a warning, rather than a silently empty agenda the user cannot explain.
({List<IcsEvent> events, List<String> warnings}) parseIcs(
  String text, {
  required DateTime windowStart,
  required DateTime windowEnd,
}) {
  final warn = _Warnings();
  final out = <IcsEvent>[];
  try {
    if (!windowEnd.isAfter(windowStart)) {
      warn.add('Requested window ends at or before it starts '
          '($windowStart .. $windowEnd); no events can fall inside it.');
      return (events: out, warnings: warn.list);
    }
    final raws = _scan(text, warn);
    // Two passes: overrides must be known before expansion, or a lecture that
    // was moved would appear twice — once at its old slot from the series and
    // once at its new slot from the override VEVENT.
    final overrides = _collectOverrides(raws);
    for (final raw in raws) {
      try {
        _buildOccurrences(raw, overrides, windowStart, windowEnd, warn, out);
      } catch (e) {
        // Per-event, deliberately. With this catch only around the whole loop,
        // one hostile VEVENT — `RRULE:FREQ=WEEKLY;INTERVAL=999999999999999999`
        // was the case that found this — aborted the run and returned *nothing*,
        // discarding every good event in the file. That is the exact failure the
        // library note above promises not to have: "an exception would lose the
        // nine hundred good events along with the one bad one."
        warn.add('An event in this feed could not be read and was skipped ($e).');
      }
      if (out.length >= _maxOccurrences) {
        warn.add('Stopped after $_maxOccurrences occurrences; the feed or the '
            'requested window is larger than this parser will materialise.');
        break;
      }
    }
  } catch (e) {
    // A backstop, not a licence to be sloppy: every known failure above is
    // handled by warning and skipping. If something still escapes, the caller
    // gets the events recovered so far rather than an exception that would take
    // the whole planner panel down with it.
    warn.add('Unexpected parse failure; results may be incomplete ($e).');
  }
  // Outside the try on purpose: callers are told the list is chronological and
  // render it without sorting, so a partial result reached via the backstop must
  // still be ordered. Sorting inside the try meant any escape returned events in
  // file order — a subtly scrambled agenda rather than an obviously short one.
  //
  // Chronological, with UID then summary as tie-breakers so a rebuild of the
  // same feed produces the same list order and the agenda does not reshuffle
  // under the reader on every refresh.
  out.sort((a, b) {
    final t = a.start.compareTo(b.start);
    if (t != 0) return t;
    final u = a.uid.compareTo(b.uid);
    return u != 0 ? u : a.summary.compareTo(b.summary);
  });
  return (events: out, warnings: warn.list);
}

// ---------------------------------------------------------------------------
// Bounds. Every one of these exists to make a hostile or broken feed finite.
// ---------------------------------------------------------------------------

/// Most VEVENTs read from one feed. A year of a full timetable is a few
/// hundred; ten thousand means the file is not a timetable.
const int _maxEvents = 10000;

/// Most occurrences materialised in total, across all events.
const int _maxOccurrences = 20000;

/// Most occurrences one recurrence rule may contribute.
const int _maxOccurrencesPerRule = 2000;

/// Most interval-weeks one rule's expansion loop may step through. With the
/// fast-forward below this is only reached by a pathological window.
const int _maxWeeksScanned = 5000;

/// Distinct warning strings kept. Identical warnings are collapsed, so this is
/// only hit by a feed with many *different* problems.
const int _maxWarnings = 100;

/// Depth of `BEGIN:` nesting tracked. Real files reach 2 (VCALENDAR > VEVENT >
/// VALARM); the cap stops a file of nothing but `BEGIN:X` eating memory.
const int _maxComponentDepth = 32;

// ---------------------------------------------------------------------------
// Warnings
// ---------------------------------------------------------------------------

class _Warnings {
  final List<String> _out = <String>[];
  final Set<String> _seen = <String>{};
  int _suppressed = 0;

  /// Identical messages are recorded once: a feed with four hundred events all
  /// carrying the same TZID should produce one line the user can act on, not
  /// four hundred identical ones that bury everything else.
  void add(String message) {
    if (!_seen.add(message)) return;
    if (_out.length >= _maxWarnings) {
      _suppressed++;
      return;
    }
    _out.add(message);
  }

  List<String> get list => _suppressed == 0
      ? List<String>.unmodifiable(_out)
      : List<String>.unmodifiable(
          [..._out, '$_suppressed further warning(s) suppressed.']);
}

// ---------------------------------------------------------------------------
// Step 1 — unfolding. This must happen before anything else.
// ---------------------------------------------------------------------------

/// Split [text] into logical lines, undoing RFC 5545 §3.1 line folding.
///
/// A producer may break any line by inserting CRLF followed by a single space
/// or tab; the break and that one whitespace character are not data. Doing this
/// after tokenising instead of before truncates every summary longer than 75
/// octets — which is most lecture titles — so it is the first thing that
/// happens and it is tested directly.
///
/// Exactly one whitespace character is removed. A continuation beginning with
/// two spaces contributes one space to the value, and dropping both would
/// silently join words in a wrapped description.
List<String> _unfoldLines(String text) {
  // Feeds arrive with CRLF (the spec), bare LF (most Unix-side generators) and
  // occasionally bare CR. Normalising first means the folding rule below has
  // one shape to match instead of three.
  var s = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  // A UTF-8 BOM survives decoding as U+FEFF and would make the first line read
  // as the property "\uFEFFBEGIN", so BEGIN:VCALENDAR would be missed and the
  // first VEVENT with it. Dart's `String.trim()` happens to strip U+FEFF too,
  // so the name-parsing step currently absorbs this as well; the strip is kept
  // because relying on that quirk means the whole calendar disappears the day
  // someone removes a `trim()` for looking redundant.
  if (s.startsWith('\uFEFF')) s = s.substring(1);

  final out = <String>[];
  for (final line in s.split('\n')) {
    final isContinuation =
        line.isNotEmpty && (line.startsWith(' ') || line.startsWith('\t'));
    if (isContinuation && out.isNotEmpty) {
      out[out.length - 1] = out[out.length - 1] + line.substring(1);
    } else {
      out.add(line);
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Step 2 — content lines
// ---------------------------------------------------------------------------

class _ContentLine {
  final String name; // upper-cased; RFC 5545 names are case-insensitive
  final Map<String, String> params; // upper-cased keys, unquoted values
  final String value; // raw, still escaped

  const _ContentLine(this.name, this.params, this.value);
}

/// Split `NAME;PARAM=value;OTHER="quoted:value":VALUE` into its three parts.
///
/// The value separator is the first colon *outside* a quoted parameter value.
/// Naively splitting on the first colon corrupts every
/// `TZID="Europe/Berlin"`-style quoted parameter that contains one, and more
/// importantly mis-parses `ATTENDEE;MEMBER="mailto:x@y":mailto:z@y`.
///
/// Returns null for a line that is blank or carries no value colon at all;
/// the caller decides whether that deserves a warning.
_ContentLine? _splitContentLine(String line) {
  final n = line.length;
  if (n == 0) return null;

  var i = 0;
  while (i < n && line[i] != ';' && line[i] != ':') {
    i++;
  }
  final name = line.substring(0, i).trim().toUpperCase();
  if (i >= n || name.isEmpty) return null;

  final params = <String, String>{};
  while (i < n && line[i] == ';') {
    i++; // consume ';'
    final nameStart = i;
    while (i < n && line[i] != '=' && line[i] != ';' && line[i] != ':') {
      i++;
    }
    final pName = line.substring(nameStart, i).trim().toUpperCase();
    var pValue = '';
    if (i < n && line[i] == '=') {
      i++; // consume '='
      final buf = StringBuffer();
      var quoted = false;
      while (i < n) {
        final c = line[i];
        if (c == '"') {
          quoted = !quoted;
          i++;
          continue;
        }
        if (!quoted && (c == ';' || c == ':')) break;
        buf.write(c);
        i++;
      }
      pValue = buf.toString();
    }
    if (pName.isNotEmpty) params[pName] = pValue;
  }

  if (i >= n || line[i] != ':') return null; // ran out before the value
  return _ContentLine(name, params, line.substring(i + 1));
}

/// Decode RFC 5545 §3.3.11 TEXT escaping.
///
/// An escape this parser does not recognise is left **exactly as written**,
/// backslash included. Feeds in the wild carry unescaped Windows paths in
/// DESCRIPTION (`C:\temp\notes`), and eating the backslash there would quietly
/// corrupt data we were only asked to pass through.
String _unescapeText(String s) {
  if (!s.contains('\\')) return s;
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c != '\\' || i + 1 >= s.length) {
      b.write(c);
      continue;
    }
    final next = s[i + 1];
    switch (next) {
      case 'n':
      case 'N':
        b.write('\n');
        i++;
      case ',':
        b.write(',');
        i++;
      case ';':
        b.write(';');
        i++;
      case '\\':
        b.write('\\');
        i++;
      default:
        b.write(c); // unknown escape — keep the backslash and re-read `next`
    }
  }
  return b.toString();
}

// ---------------------------------------------------------------------------
// Step 3 — date/time values
// ---------------------------------------------------------------------------

/// Which clock a parsed value is expressed in. This is kept separate from
/// `DateTime` because recurrence must advance in the *rule's* clock: a weekly
/// lecture pinned to UTC keeps its UTC wall time across a DST change, whereas a
/// floating one keeps its local wall time. Collapsing both to one representation
/// at parse time makes one of those cases wrong by an hour for half the year.
enum _DtKind { utc, floating, date }

class _IcsDate {
  final int year, month, day, hour, minute, second;
  final _DtKind kind;

  const _IcsDate(this.year, this.month, this.day, this.hour, this.minute,
      this.second, this.kind);

  /// The value on its own clock — UTC values stay UTC so that adding seven days
  /// to them adds seven UTC days.
  DateTime get ruleClock => kind == _DtKind.utc
      ? DateTime.utc(year, month, day, hour, minute, second)
      : DateTime(year, month, day, hour, minute, second);
}

/// Materialise a rule-clock instant into the local `DateTime` callers see.
DateTime _toLocal(DateTime ruleClock) =>
    ruleClock.isUtc ? ruleClock.toLocal() : ruleClock;

/// Read `YYYYMMDD`, `YYYYMMDDTHHMMSS` or `YYYYMMDDTHHMMSSZ`.
///
/// Every field is range-checked and the result is verified against the real
/// calendar, because `DateTime(2026, 2, 30)` silently normalises to 2 March —
/// so a typo'd feed would place a lecture on a day the producer never named,
/// which is precisely the "silently invent wrong dates" failure this parser
/// must not have.
_IcsDate? _parseIcsDate(String raw) {
  final v = raw.trim();
  if (v.length != 8 && v.length != 15 && v.length != 16) return null;

  final y = _digits(v, 0, 4);
  final mo = _digits(v, 4, 2);
  final d = _digits(v, 6, 2);
  if (y == null || mo == null || d == null) return null;
  if (y < 1 || mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  // Real-calendar check (rejects 31 April, 30 February, non-leap 29 February).
  final probe = DateTime(y, mo, d);
  if (probe.year != y || probe.month != mo || probe.day != d) return null;

  if (v.length == 8) return _IcsDate(y, mo, d, 0, 0, 0, _DtKind.date);

  final t = v[8];
  if (t != 'T' && t != 't') return null;
  final h = _digits(v, 9, 2);
  final mi = _digits(v, 11, 2);
  var se = _digits(v, 13, 2);
  if (h == null || mi == null || se == null) return null;
  if (h > 23 || mi > 59 || se > 60) return null;
  // A positive leap second is a real ICS value and no `DateTime` can hold it;
  // clamping keeps the event rather than discarding an otherwise fine lecture.
  if (se == 60) se = 59;

  var utc = false;
  if (v.length == 16) {
    final z = v[15];
    if (z != 'Z' && z != 'z') return null;
    utc = true;
  }

  // Note that a contradictory VALUE=DATE parameter is deliberately not consulted
  // here: the value's own shape is trusted, so the clock time the producer
  // actually wrote survives. The caller warns about the contradiction.
  return _IcsDate(y, mo, d, h, mi, se, utc ? _DtKind.utc : _DtKind.floating);
}

int? _digits(String s, int start, int len) {
  if (start + len > s.length) return null;
  var acc = 0;
  for (var i = start; i < start + len; i++) {
    final c = s.codeUnitAt(i);
    if (c < 0x30 || c > 0x39) return null;
    acc = acc * 10 + (c - 0x30);
  }
  return acc;
}

/// `P1DT2H30M` and friends (RFC 5545 §3.3.6), used when a feed gives `DURATION`
/// instead of `DTEND`. Outlook-published feeds do this routinely, and without
/// it every one of those lectures would render with no end time.
final RegExp _durationPattern = RegExp(
  r'^([+-])?P(?:(\d+)W|(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?)$',
  caseSensitive: false,
);

Duration? _parseDuration(String raw) {
  final m = _durationPattern.firstMatch(raw.trim());
  if (m == null) return null;
  final weeks = m.group(2), days = m.group(3);
  final hours = m.group(4), minutes = m.group(5), seconds = m.group(6);
  if (weeks == null &&
      days == null &&
      hours == null &&
      minutes == null &&
      seconds == null) {
    return null; // a bare "P" carries no information
  }
  final d = Duration(
    days: (int.tryParse(weeks ?? '0') ?? 0) * 7 + (int.tryParse(days ?? '0') ?? 0),
    hours: int.tryParse(hours ?? '0') ?? 0,
    minutes: int.tryParse(minutes ?? '0') ?? 0,
    seconds: int.tryParse(seconds ?? '0') ?? 0,
  );
  return m.group(1) == '-' ? -d : d;
}

// ---------------------------------------------------------------------------
// Step 4 — component scan
// ---------------------------------------------------------------------------

/// The properties this parser actually reads *and* that RFC 5545 §3.6.1 caps at
/// one per VEVENT. Only a repeat of one of these is worth telling the reader
/// about.
///
/// Warning about *every* repeated name instead is how a perfectly conformant
/// feed ends up shouting at the student: `ATTENDEE`, `CATEGORIES`, `COMMENT`,
/// `RELATED-TO`, `ATTACH`, `RDATE` and friends may legally occur many times,
/// and any invitation-style feed has one `ATTENDEE` line per person. Four false
/// "the feed is broken" lines — each of them asserting something untrue about
/// RFC 5545 — is worse than silence, because it teaches the reader to ignore
/// the warnings that do matter.
const Set<String> _singleValuedProps = <String>{
  'UID',
  'DTSTART',
  'DTEND',
  'DURATION',
  'SUMMARY',
  'LOCATION',
  'DESCRIPTION',
  'RRULE',
  'RECURRENCE-ID',
};

class _RawEvent {
  final Map<String, _ContentLine> props = <String, _ContentLine>{};
  final List<_ContentLine> exdates = <_ContentLine>[];
  bool truncated = false;

  /// First value wins for a repeated property. For the single-valued ones RFC
  /// 5545 forbids the repetition outright, so there is no defensible rule for
  /// choosing between them; taking the first is at least deterministic across
  /// refreshes, which "last wins" is not if the producer reorders its output.
  /// Repeats of a legally multi-valued property are kept silently — this parser
  /// reads none of them, so there is nothing for the reader to act on.
  void put(_ContentLine line, _Warnings warn) {
    if (line.name == 'EXDATE') {
      exdates.add(line);
      return;
    }
    if (props.containsKey(line.name)) {
      if (_singleValuedProps.contains(line.name)) {
        warn.add('Duplicate ${line.name} inside one VEVENT; kept the first '
            'value (RFC 5545 allows only one).');
      }
      return;
    }
    props[line.name] = line;
  }
}

/// Walk the unfolded lines and collect VEVENT bodies.
///
/// The component stack is what keeps VALARM and VTIMEZONE from poisoning the
/// result: a VALARM carries its own DESCRIPTION and a VTIMEZONE's STANDARD /
/// DAYLIGHT sub-components carry their own DTSTART *and RRULE*. A parser that
/// merely scans for property names would give every event the alarm's text and
/// would expand the timezone's transition rule as if it were a lecture.
List<_RawEvent> _scan(String text, _Warnings warn) {
  final events = <_RawEvent>[];
  final stack = <String>[];
  _RawEvent? current;
  var sawCalendar = false;
  var sawEvent = false;

  for (final line in _unfoldLines(text)) {
    if (line.trim().isEmpty) continue;
    final cl = _splitContentLine(line);
    if (cl == null) {
      warn.add('Skipped a line that is not a "NAME:value" content line.');
      continue;
    }

    if (cl.name == 'BEGIN') {
      final component = cl.value.trim().toUpperCase();
      if (component == 'VCALENDAR') sawCalendar = true;
      if (stack.length < _maxComponentDepth) {
        stack.add(component);
      } else {
        warn.add('Component nesting deeper than $_maxComponentDepth; ignored.');
        continue;
      }
      if (component == 'VEVENT' && current == null) {
        if (events.length >= _maxEvents) {
          warn.add('Stopped after $_maxEvents VEVENTs; the rest of the feed '
              'was not read.');
          break;
        }
        current = _RawEvent();
        sawEvent = true;
      }
      continue;
    }

    if (cl.name == 'END') {
      final component = cl.value.trim().toUpperCase();
      if (stack.isEmpty) {
        warn.add('END:$component with no matching BEGIN; ignored.');
        continue;
      }
      final opened = stack.removeLast();
      if (opened != component) {
        warn.add('END:$component closes BEGIN:$opened; the feed\'s component '
            'nesting is malformed.');
      }
      if (component == 'VEVENT' && current != null) {
        events.add(current);
        current = null;
      }
      continue;
    }

    // Properties count only when they sit directly in the VEVENT body.
    if (current != null && stack.isNotEmpty && stack.last == 'VEVENT') {
      current.put(cl, warn);
    }
  }

  if (current != null) {
    // A feed cut off mid-VEVENT (a truncated download is the usual cause) still
    // has a usable DTSTART more often than not. Keeping it is the difference
    // between "today's lectures, one may be missing" and a blank agenda.
    current.truncated = true;
    events.add(current);
    warn.add('The feed ended in the middle of a VEVENT; that event was kept '
        'from what had been read, so it may be incomplete.');
  }
  if (!sawCalendar) {
    warn.add('No BEGIN:VCALENDAR found — this may not be an iCalendar file.');
  }
  if (!sawEvent) {
    warn.add('No VEVENT found in the feed; there is nothing to show.');
  }
  return events;
}

// ---------------------------------------------------------------------------
// Step 5 — recurrence rules
// ---------------------------------------------------------------------------

const Map<String, int> _weekdayCodes = <String, int>{
  'MO': DateTime.monday,
  'TU': DateTime.tuesday,
  'WE': DateTime.wednesday,
  'TH': DateTime.thursday,
  'FR': DateTime.friday,
  'SA': DateTime.saturday,
  'SU': DateTime.sunday,
};

/// Parameters this parser knows how to honour. Anything else that can narrow or
/// widen the recurrence set — BYMONTH, BYSETPOS, BYMONTHDAY … — makes the
/// expansion wrong, so its presence downgrades the rule to "not expanded"
/// rather than producing dates the producer did not mean.
const Set<String> _handledRuleParts = <String>{
  'FREQ',
  'INTERVAL',
  'COUNT',
  'UNTIL',
  'BYDAY',
  'WKST',
};

class _Rrule {
  int interval = 1;
  int? count;
  _IcsDate? until;
  List<int> byDay = const <int>[];
  int wkst = DateTime.monday;
  bool expandable = false;
}

_Rrule _parseRrule(String value, _Warnings warn) {
  final r = _Rrule();
  var freq = '';
  var blocked = false;

  for (final part in value.split(';')) {
    if (part.trim().isEmpty) continue;
    final eq = part.indexOf('=');
    if (eq < 0) {
      warn.add('Ignored malformed RRULE part "${part.trim()}".');
      continue;
    }
    final key = part.substring(0, eq).trim().toUpperCase();
    final val = part.substring(eq + 1).trim();

    if (!_handledRuleParts.contains(key)) {
      if (key.startsWith('BY') || key == 'BYSETPOS') {
        warn.add('RRULE uses $key, which this parser does not expand; the '
            'event is shown once at its start date instead of at guessed '
            'dates.');
        blocked = true;
      } else if (!key.startsWith('X-')) {
        warn.add('Ignored unrecognised RRULE part "$key".');
      }
      continue;
    }

    switch (key) {
      case 'FREQ':
        freq = val.toUpperCase();
      case 'INTERVAL':
        final n = int.tryParse(val);
        if (n == null || n < 1) {
          // INTERVAL=0 would step zero weeks forward for ever. RFC 5545 says
          // the value must be a positive integer, so 1 is the only reading.
          warn.add('RRULE INTERVAL="$val" is not a positive integer; used 1.');
          r.interval = 1;
        } else {
          r.interval = n;
        }
      case 'COUNT':
        final n = int.tryParse(val);
        if (n == null || n < 1) {
          warn.add('RRULE COUNT="$val" is not a positive integer; the event is '
              'shown once at its start date rather than an invented number of '
              'times.');
          blocked = true;
        } else {
          r.count = n;
        }
      case 'UNTIL':
        final u = _parseIcsDate(val);
        if (u == null) {
          warn.add('RRULE UNTIL="$val" is not a valid date; the event is shown '
              'once at its start date rather than repeating without an end.');
          blocked = true;
        } else {
          r.until = u;
        }
      case 'BYDAY':
        final days = <int>[];
        for (final tokenRaw in val.split(',')) {
          final token = tokenRaw.trim().toUpperCase();
          if (token.isEmpty) continue;
          final code = _weekdayCodes[token];
          if (code != null) {
            days.add(code);
            continue;
          }
          // "2MO" means "the second Monday" — forbidden with FREQ=WEEKLY, so a
          // producer emitting it means something we cannot know. Expanding it
          // as plain "every Monday" would put four lectures where one belongs.
          warn.add('RRULE BYDAY="$token" carries an ordinal or is unreadable; '
              'the event is shown once at its start date rather than on '
              'guessed weekdays.');
          blocked = true;
        }
        r.byDay = days;
      case 'WKST':
        final code = _weekdayCodes[val.toUpperCase()];
        if (code == null) {
          warn.add('RRULE WKST="$val" is not a weekday; used MO.');
        } else {
          r.wkst = code;
        }
    }
  }

  if (freq.isEmpty) {
    warn.add('RRULE has no FREQ; the event is shown once at its start date.');
  } else if (freq != 'WEEKLY') {
    warn.add('RRULE FREQ=$freq is not expanded by this parser (only WEEKLY '
        'is); the event is shown once at its start date.');
  } else if (r.count != null && r.until != null) {
    // RFC 5545 forbids both. Honouring whichever ends the series first cannot
    // invent an occurrence, which is the property that matters here.
    warn.add('RRULE sets both COUNT and UNTIL, which RFC 5545 forbids; both '
        'were applied, so the series ends at whichever comes first.');
  }

  r.expandable = !blocked && freq == 'WEEKLY';
  return r;
}

/// Add whole days while preserving the wall-clock time on the value's own
/// clock. `DateTime.add(Duration(days: 7))` adds absolute time instead, which
/// walks a weekly lecture an hour off its slot the week the clocks change.
DateTime _addDays(DateTime d, int days) => d.isUtc
    ? DateTime.utc(d.year, d.month, d.day + days, d.hour, d.minute, d.second)
    : DateTime(d.year, d.month, d.day + days, d.hour, d.minute, d.second);

int _offsetFromWeekStart(int weekday, int wkst) => (weekday - wkst + 7) % 7;

/// The end of an occurrence that starts at [start] and lasts [span].
///
/// The whole-day part of the span is added on the *wall clock* and only the
/// remainder as absolute time, for the same reason [_addDays] exists. `span` is
/// measured once, at DTSTART; adding it absolutely to a later occurrence that
/// sits the other side of a DST change lands an hour out. For an all-day event
/// that hour crosses a *date*: a two-day block on the American fall-back weekend
/// came back as `31 Oct 00:00 .. 1 Nov 23:00`, and a UI turning that exclusive
/// end into an inclusive one by subtracting a day renders 31 October — a
/// two-day block shown as one.
///
/// A same-day event has no whole-day part, so the common case is untouched.
DateTime _wallClockEnd(DateTime start, Duration span) {
  final wholeDays = span.inDays;
  if (wholeDays == 0) return start.add(span);
  return _addDays(start, wholeDays).add(span - Duration(days: wholeDays));
}

// ---------------------------------------------------------------------------
// Step 6 — turn raw events into occurrences
// ---------------------------------------------------------------------------

/// Key for "this occurrence of this series has been rescheduled elsewhere".
String _overrideKey(String uid, DateTime ruleClockStart) =>
    '$uid@${ruleClockStart.toUtc().microsecondsSinceEpoch}';

/// Instants a series must skip because a later VEVENT overrides them.
Set<String> _collectOverrides(List<_RawEvent> raws) {
  final keys = <String>{};
  for (final raw in raws) {
    final rid = raw.props['RECURRENCE-ID'];
    if (rid == null) continue;
    final uid = raw.props['UID'];
    if (uid == null) continue;
    final parsed = _parseIcsDate(rid.value);
    if (parsed == null) continue;
    keys.add(_overrideKey(_unescapeText(uid.value).trim(), parsed.ruleClock));
  }
  return keys;
}

void _buildOccurrences(
  _RawEvent raw,
  Set<String> overrides,
  DateTime windowStart,
  DateTime windowEnd,
  _Warnings warn,
  List<IcsEvent> out,
) {
  final dtstartLine = raw.props['DTSTART'];
  if (dtstartLine == null) {
    warn.add('Skipped a VEVENT with no DTSTART; there is nowhere to put an '
        'event with no start.');
    return;
  }
  final dtstart = _parseIcsDate(dtstartLine.value);
  if (dtstart == null) {
    warn.add('Skipped a VEVENT whose DTSTART value '
        '"${dtstartLine.value.trim()}" is not a valid date-time.');
    return;
  }

  final uidLine = raw.props['UID'];
  final uid = uidLine == null ? '' : _unescapeText(uidLine.value).trim();
  if (uid.isEmpty) {
    warn.add('A VEVENT has no UID; it is still shown, but it cannot be matched '
        'against the same event on a later refresh.');
  }

  String textProp(String name) {
    final line = raw.props[name];
    return line == null ? '' : _unescapeText(line.value);
  }

  var tzid = dtstartLine.params['TZID'];
  if (tzid != null && tzid.trim().isEmpty) tzid = null;
  if (tzid != null && dtstart.kind == _DtKind.utc) {
    // TZID with a "Z" value is self-contradictory; the Z is unambiguous, so it
    // wins and the parameter is reported rather than acted on.
    warn.add('DTSTART carries TZID=$tzid but its value ends in "Z"; the UTC '
        'value was used.');
  } else if (tzid != null) {
    warn.add('Times with TZID=$tzid are shown in this device\'s local time '
        'zone — this parser carries no timezone database, so they are wrong by '
        'the offset difference if your device is in another zone.');
  }

  final allDay = dtstart.kind == _DtKind.date;
  if (!allDay && dtstartLine.params['VALUE']?.toUpperCase() == 'DATE') {
    warn.add('DTSTART is marked VALUE=DATE but carries a clock time; the time '
        'was kept.');
  }

  final startRule = dtstart.ruleClock;

  // End: DTEND wins, DURATION is the documented fallback, otherwise none.
  Duration? span;
  final dtendLine = raw.props['DTEND'];
  if (dtendLine != null) {
    final dtend = _parseIcsDate(dtendLine.value);
    if (dtend == null) {
      warn.add('DTEND value "${dtendLine.value.trim()}" is not a valid '
          'date-time; the event is shown with no end time.');
    } else {
      final candidate = dtend.ruleClock.difference(startRule);
      if (candidate.isNegative) {
        // A negative-length event would render as a bar going backwards, or
        // sort before its own start. Dropping the end keeps the start usable.
        warn.add('DTEND is before DTSTART; the event is shown with no end '
            'time rather than a negative duration.');
      } else {
        span = candidate;
      }
    }
  } else {
    final durationLine = raw.props['DURATION'];
    if (durationLine != null) {
      final parsed = _parseDuration(durationLine.value);
      if (parsed == null || parsed.isNegative) {
        warn.add('DURATION value "${durationLine.value.trim()}" is not a '
            'usable positive duration; the event is shown with no end time.');
      } else {
        span = parsed;
      }
    }
  }

  // RFC 5545 §3.6.1: a VEVENT whose DTSTART is a DATE and which gives neither
  // DTEND nor DURATION lasts one day. Treating it as a zero-length point
  // instead deleted it from every window that does not begin at midnight —
  // "the next seven days from now" dropped today's census date, silently and
  // with no warning, which is the worst shape a bug can have here.
  //
  // Only the *windowing* span is defaulted. [IcsEvent.end] stays null so the
  // documented contract ("null when the feed gave neither DTEND nor DURATION")
  // still holds and the UI can tell a stated end from an implied one. Open
  // question deliberately left alone: whether `end` should carry the implied
  // midnight instead. Callers with `allDay == true` and `end == null` can add
  // the day themselves, so the conservative reading loses nothing.
  final windowSpan = span ?? (allDay ? const Duration(days: 1) : null);

  // Excluded instants (cancelled lectures). EXDATE may repeat and may carry a
  // comma-separated list.
  final excluded = <String>{};
  for (final line in raw.exdates) {
    for (final piece in line.value.split(',')) {
      if (piece.trim().isEmpty) continue;
      final parsed = _parseIcsDate(piece);
      if (parsed == null) {
        warn.add('Ignored an EXDATE value "${piece.trim()}" that is not a '
            'valid date-time; an occurrence that should be hidden may show.');
        continue;
      }
      excluded.add(_overrideKey(uid, parsed.ruleClock));
    }
  }

  // RDATE names extra instants that belong to the series — the one-off catch-up
  // tutorial, the moved exam. This parser does not expand them, and an extra
  // session that simply never appears is exactly the silent loss the rest of
  // this file refuses, so it is said out loud instead. (EXDATE, its mirror, *is*
  // applied; the asymmetry is that ignoring an EXDATE shows something spurious
  // while ignoring an RDATE hides something real.)
  if (raw.props['RDATE'] != null) {
    warn.add('This event carries RDATE — extra dates added to the series — '
        'which this parser does not expand; those occurrences are not shown.');
  }

  final rruleLine = raw.props['RRULE'];
  final rule = rruleLine == null ? null : _parseRrule(rruleLine.value, warn);
  final unexpanded = rule != null && !rule.expandable;

  final List<DateTime> starts;
  if (rule != null && rule.expandable) {
    starts = _expandWeekly(
      dtstart: startRule,
      rule: rule,
      span: windowSpan,
      windowStart: windowStart,
      windowEnd: windowEnd,
      warn: warn,
    );
  } else {
    starts = _overlapsWindow(startRule, windowSpan, windowStart, windowEnd)
        ? <DateTime>[startRule]
        : const <DateTime>[];
  }

  for (final s in starts) {
    final key = _overrideKey(uid, s);
    if (excluded.contains(key)) continue;
    // A rescheduled instance arrives as its own VEVENT with RECURRENCE-ID; the
    // series must not also emit the original slot or the lecture shows twice.
    if (raw.props['RECURRENCE-ID'] == null && overrides.contains(key)) continue;
    out.add(IcsEvent(
      uid: uid,
      summary: textProp('SUMMARY'),
      location: textProp('LOCATION'),
      description: textProp('DESCRIPTION'),
      start: _toLocal(s),
      end: span == null ? null : _toLocal(_wallClockEnd(s, span)),
      allDay: allDay,
      recurrenceUnsupported: unexpanded,
      tzid: tzid,
    ));
    if (out.length >= _maxOccurrences) return;
  }
}

/// True when an occurrence starting at [s] overlaps `[windowStart, windowEnd)`.
///
/// Comparisons are by instant, so a UTC rule clock and a local window compare
/// correctly without either side being converted first.
bool _overlapsWindow(
    DateTime s, Duration? span, DateTime windowStart, DateTime windowEnd) {
  if (!s.isBefore(windowEnd)) return false;
  if (span == null || span <= Duration.zero) {
    // A point event is in the window when it is at or after its start; using
    // "ends after windowStart" instead would drop an event landing exactly on
    // the boundary, which is the one a "starting now" agenda most wants.
    return !s.isBefore(windowStart);
  }
  // The same wall-clock end the caller will be shown, so a DST week cannot make
  // the agenda disagree with the row it is filtering on.
  return _wallClockEnd(s, span).isAfter(windowStart);
}

/// Expand `FREQ=WEEKLY` into the occurrences that touch the window.
///
/// Weeks are built from the week containing DTSTART, aligned to WKST, because
/// `INTERVAL=2;BYDAY=TU` means "every other WKST-week, on Tuesday" — computing
/// it as "DTSTART plus fourteen days" puts a fortnightly lab in the wrong week
/// whenever the rule lists a day earlier in the week than DTSTART's own.
List<DateTime> _expandWeekly({
  required DateTime dtstart,
  required _Rrule rule,
  required Duration? span,
  required DateTime windowStart,
  required DateTime windowEnd,
  required _Warnings warn,
}) {
  // Deliberately redundant with the clamp in [_parseRrule]: a zero step means
  // the loop below never advances, and a hang is the one failure mode worth
  // guarding twice.
  final interval = rule.interval < 1 ? 1 : rule.interval;
  final days =
      rule.byDay.isEmpty ? <int>[dtstart.weekday] : rule.byDay.toSet().toList();
  final offsets = days
      .map((d) => _offsetFromWeekStart(d, rule.wkst))
      .toSet()
      .toList()
    ..sort();

  final weekStart =
      _addDays(dtstart, -_offsetFromWeekStart(dtstart.weekday, rule.wkst));

  // UNTIL is inclusive. A date-only UNTIL covers the whole of that day, so the
  // bound is the day's end — treating it as midnight drops the last lecture.
  DateTime? untilLimit;
  final until = rule.until;
  if (until != null) {
    untilLimit = until.kind == _DtKind.date
        ? DateTime(until.year, until.month, until.day, 23, 59, 59)
        : until.ruleClock;
  }

  // Weeks past this one begin at or after [windowEnd], so no occurrence in them
  // can be in the window. Bounding k here rather than letting `consider`
  // discover it is what keeps `7 * interval * k` inside a 64-bit int: a
  // producer's `INTERVAL=999999999999999999` otherwise overflows to a *negative*
  // day count, `DateTime` throws on it, and the parse is lost. The bound is
  // exact, not a heuristic — when one interval-week already clears the window
  // only week zero can contribute, so nothing is given up by not walking there.
  final daysToWindowEnd = windowEnd.difference(weekStart).inDays;
  final int maxWeekSteps;
  if (daysToWindowEnd <= 0 || interval > daysToWindowEnd) {
    maxWeekSteps = 0;
  } else {
    maxWeekSteps = daysToWindowEnd ~/ (7 * interval) + 1;
  }

  // An UNTIL earlier than DTSTART makes the rule's set empty, so the event
  // vanished outright — no row, no warning, nothing to explain it. That breaks
  // this file's one standing rule (never drop the event) on input a producer
  // does emit. RFC 5545 §3.8.5.3 calls DTSTART the first instance of the
  // recurrence set, so the start is kept and the contradiction is reported —
  // the same reading already applied when DTSTART does not match its own BYDAY.
  if (untilLimit != null && untilLimit.isBefore(dtstart)) {
    warn.add('An RRULE\'s UNTIL is before its own DTSTART; the event is shown '
        'once at its start date rather than disappearing entirely.');
    return _overlapsWindow(dtstart, span, windowStart, windowEnd)
        ? <DateTime>[dtstart]
        : <DateTime>[];
  }

  final out = <DateTime>[];
  var counted = 0; // toward COUNT, which counts from DTSTART, not from the window
  var stop = false;

  void consider(DateTime occ) {
    if (stop) return;
    if (occ.isBefore(dtstart)) return; // days earlier in DTSTART's own week
    if (untilLimit != null && occ.isAfter(untilLimit)) {
      stop = true;
      return;
    }
    if (!occ.isBefore(windowEnd)) {
      // Occurrences are generated in ascending order, so nothing later can be
      // in the window either.
      stop = true;
      return;
    }
    counted++;
    if (rule.count != null && counted > rule.count!) {
      stop = true;
      return;
    }
    if (_overlapsWindow(occ, span, windowStart, windowEnd)) out.add(occ);
    if (out.length >= _maxOccurrencesPerRule) {
      warn.add('A weekly RRULE produced more than $_maxOccurrencesPerRule '
          'occurrences in the requested window; the rest were not expanded.');
      stop = true;
    }
  }

  // RFC 5545 leaves a DTSTART that does not match its own BYDAY undefined.
  // Emitting it anyway is the only reading that cannot lose an event the
  // producer explicitly wrote down.
  final startMatches =
      offsets.contains(_offsetFromWeekStart(dtstart.weekday, rule.wkst));
  if (!startMatches) {
    warn.add('An RRULE\'s BYDAY does not include its own DTSTART weekday; the '
        'start date is shown as well as the listed weekdays.');
    consider(dtstart);
  }

  // Fast-forward when COUNT is absent. With COUNT set we must count from
  // DTSTART, so the walk has to begin there; COUNT bounds it anyway.
  var k = 0;
  if (rule.count == null) {
    // Back off by a whole interval-week plus the event's own length so an
    // occurrence that began before the window but is still running is not
    // skipped. `inDays` is close enough across DST precisely because of that
    // slack.
    final slackDays = 7 * interval + (span?.inDays ?? 0);
    final reach = windowStart.difference(weekStart).inDays - slackDays;
    if (reach > 0) k = reach ~/ (7 * interval);
  }

  var scanned = 0;
  while (!stop) {
    if (k > maxWeekSteps) break;
    if (scanned++ >= _maxWeeksScanned) {
      warn.add('Gave up expanding a weekly RRULE after $_maxWeeksScanned '
          'weeks; later occurrences were not produced.');
      break;
    }
    final weekBase = _addDays(weekStart, 7 * interval * k);
    for (final off in offsets) {
      consider(_addDays(weekBase, off));
      if (stop) break;
    }
    k++;
  }

  out.sort();
  return out;
}
