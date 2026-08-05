/// What Openote actually interrupts you with (v0.8 §3).
///
/// **Why this type exists at all.** Reminders and calendar events reach the
/// same moment from opposite directions — a reminder *is* a time you chose, an
/// event alert is derived from a lead time applied to somebody else's feed —
/// but by the time either of them is in front of you they are the same object:
/// a line of text, a moment, and two or three things you might do about it. The
/// popup was the forcing function. Two alert types meant two popups, two
/// dismissal rules and two ways to get "Done" wrong; one type means the whole
/// interruption surface is written once.
///
/// **An alert is not stored.** It is derived on every tick from the reminder
/// store and the parsed calendar, exactly as the agenda is derived — the "lens,
/// not a store" rule from v0.5 §6. What *is* stored is much smaller: which
/// alerts have already been shown ([firedEventKey]), so a restart does not
/// replay this morning's lectures at you.
library;

import 'event_kinds.dart';

/// Where an alert came from. Drives the icon, and drives what "Done" means:
/// a reminder is dismissed in the store, an event alert is only marked shown
/// (Openote never writes to anyone's calendar).
enum AlertSource { reminder, event }

/// One thing to interrupt the user about, ready to render.
class PlannerAlert {
  const PlannerAlert({
    required this.id,
    required this.source,
    required this.title,
    required this.at,
    this.subtitle,
    this.kind,
    this.join,
    this.notebookId,
    this.pageId,
    this.blockId,
    this.line,
  });

  /// Unique among live alerts.
  ///
  /// For a reminder this is the reminder's own id — deliberately *not*
  /// prefixed, because every caller that acts on a reminder alert would then
  /// have to strip the prefix back off and one of them would forget. Event keys
  /// are [firedEventKey], which starts `ics:` and so cannot collide with a
  /// UUIDv7.
  final String id;

  final AlertSource source;

  /// The headline. Never empty — callers substitute 'Reminder' or
  /// '(untitled event)' before constructing.
  final String title;

  /// For a reminder, when it was set for. For an event, **when the event
  /// starts** — not when the alert fired. That is what makes "in 10 minutes"
  /// renderable, and it is the number the student is actually asking about.
  final DateTime at;

  /// Room, time range, page name — whatever gives the headline context.
  final String? subtitle;

  /// The event's kind, for the icon and for the "you asked to be told about
  /// lectures" line in the popup. Null for reminders.
  final EventKind? kind;

  /// A meeting link, when the event carries one. This is the whole reason the
  /// popup earns its place: a lecture alert with a Join button removes the
  /// "which tab was the link in" scramble that the alert exists to prevent.
  final JoinLink? join;

  /// Click-through, for reminders attached to a line of a page.
  final String? notebookId;
  final String? pageId;
  final String? blockId;
  final int? line;

  /// True when this can be opened in the notebook.
  bool get hasTarget => pageId != null;

  @override
  String toString() => 'PlannerAlert($source, "$title", $at)';
}

/// The identity an event alert is remembered by once shown.
///
/// Keyed on `(uid, start)` rather than on UID alone because a UID is shared by
/// every occurrence of a weekly lecture — keying on UID would show the alert
/// for the first Monday and never again. The start is an epoch millisecond so
/// the key survives a timezone change as the same string; if the feed moves the
/// lecture, that genuinely is a different occurrence and deserves a new alert.
String firedEventKey(String uid, DateTime start) =>
    'ics:${start.millisecondsSinceEpoch}:$uid';
