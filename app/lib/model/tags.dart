/// Note tags (TEXT-5) — OneNote's signature organising feature, and the one
/// large subsystem Openote lacked entirely.
///
/// **The model is per-paragraph markers, not inline `#hashtags`.** That is
/// OneNote's model, and it is the right one here for a concrete reason: our
/// text is Markdown, where `#` already means heading. A hashtag dialect would
/// collide with the most common line prefix in the app.
///
/// A tag lives in the block envelope's `tags` list as
/// `{"kind": "todo", "line": 0, "checked": false, "label": "…"}` — `line` is
/// the 0-based line index within that block's text, so a tag survives edits to
/// other lines and travels with the block through the op log unchanged (tags
/// ride inside block content, so they need no new op kind).
///
/// A tag may also carry a `"due"` day (v0.5 §2). That key is **additive**: it
/// is written only when set, older readers ignore it, and the frozen v1 block
/// format is untouched. It is on the tag rather than in workspace settings
/// because a deadline is a property of the task — in a shared notebook the
/// group's deadline is the same deadline — which is the opposite of where a
/// *reminder* time belongs.
library;

import 'package:flutter/material.dart';

import '../study/study_stats.dart' show dayKey, parseDayKey;

/// The built-in tag set, mapped from OneNote's own built-ins so an imported
/// notebook keeps its meaning. Anything unrecognised becomes [custom] rather
/// than being dropped.
enum TagKind {
  todo('todo', 'To Do', Icons.check_box_outline_blank, Color(0xFF3B6FD2)),
  important('important', 'Important', Icons.star, Color(0xFFE0A32E)),
  question('question', 'Question', Icons.help_outline, Color(0xFF7A4FD2)),
  remember('remember', 'Remember', Icons.push_pin_outlined, Color(0xFFD23B7A)),
  definition('definition', 'Definition', Icons.menu_book_outlined, Color(0xFF2E8B72)),
  idea('idea', 'Idea', Icons.lightbulb_outline, Color(0xFFE07A2E)),
  critical('critical', 'Critical', Icons.priority_high, Color(0xFFD23B3B)),
  contact('contact', 'Contact', Icons.person_outline, Color(0xFF4F7A8B)),
  custom('custom', 'Tag', Icons.label_outline, Color(0xFF6B7280));

  const TagKind(this.key, this.label, this.icon, this.color);

  final String key;
  final String label;
  final IconData icon;
  final Color color;

  /// Unknown keys become [custom] — an imported tag we don't recognise must
  /// still be visible, never silently discarded.
  static TagKind parse(String? key) => TagKind.values
      .firstWhere((k) => k.key == key, orElse: () => TagKind.custom);

  /// Map one of OneNote's own tag names onto our set.
  ///
  /// Matched on the **label**, because that is what the file actually carries
  /// in a form we can read. OneNote also records an icon index, which would be
  /// locale-independent where this is not — a German notebook says "Aufgabe" —
  /// but there is no verified shape table and inventing one is how working
  /// imports get broken. A label we don't know becomes [custom] **keeping its
  /// name**, so a Dutch notebook's tags arrive intact and legible even though
  /// they aren't mapped; nothing is ever dropped.
  static TagKind fromOneNoteLabel(String label) {
    final l = label.trim().toLowerCase();
    if (l.startsWith('to do')) return TagKind.todo; // incl. "To Do priority 1"
    if (l.startsWith('important')) return TagKind.important;
    if (l.startsWith('question')) return TagKind.question;
    if (l.startsWith('remember')) return TagKind.remember;
    if (l.startsWith('definition')) return TagKind.definition;
    if (l.startsWith('idea')) return TagKind.idea;
    if (l.startsWith('critical')) return TagKind.critical;
    if (l.startsWith('contact')) return TagKind.contact;
    return TagKind.custom;
  }

  /// Tags offered in the picker. [custom] is the fallback for imports, not
  /// something a user picks by name.
  static List<TagKind> get pickable =>
      TagKind.values.where((k) => k != TagKind.custom).toList();
}

/// One tag applied to one line of one block.
class NoteTag {
  NoteTag({
    required this.kind,
    required this.line,
    this.checked,
    this.label,
    this.due,
  });

  final TagKind kind;

  /// 0-based line index within the block's text.
  final int line;

  /// Completion state, for [TagKind.todo]. Null for kinds that aren't
  /// checkable — a distinction worth keeping, because "not a to-do" and
  /// "an unfinished to-do" render very differently.
  final bool? checked;

  /// The tag's own name when it came from an import and isn't a built-in.
  final String? label;

  /// The day this is due, as `'yyyy-mm-dd'`, or null for an undated tag.
  ///
  /// **A day, not an instant, and a string rather than an epoch** — the same
  /// decision `dayKey` records for exam dates and for the same reason. "Due
  /// Friday" does not become "due Thursday" because the device flew west, and
  /// an essay is due on a date rather than at midnight.
  ///
  /// Meaningful on any kind, not just [TagKind.todo]: "revisit this Question
  /// before Tuesday" is a real thing to want, and restricting the field would
  /// buy nothing except a rule to explain. What the planner does with each kind
  /// is the planner's business.
  final String? due;

  String get displayLabel => label ?? kind.label;

  /// [due] parsed, or null when unset or malformed. A garbage date must not
  /// cost the tag — same tolerance as [fromJson].
  DateTime? get dueDate => due == null ? null : parseDayKey(due!);

  NoteTag copyWith({int? line, bool? checked}) => NoteTag(
        kind: kind,
        line: line ?? this.line,
        checked: checked ?? this.checked,
        label: label,
        due: due,
      );

  /// Set or (with null) clear the due day.
  ///
  /// A separate method rather than a `copyWith` parameter because `copyWith`
  /// cannot express "clear this" — `due: null` is indistinguishable from "leave
  /// it alone", and a re-date UI whose Clear button silently did nothing is
  /// exactly the bug that shape invites.
  NoteTag withDue(DateTime? day) => NoteTag(
        kind: kind,
        line: line,
        checked: checked,
        label: label,
        due: day == null ? null : dayKey(day),
      );

  Map<String, dynamic> toJson() => {
        'kind': kind.key,
        'line': line,
        if (checked != null) 'checked': checked,
        if (label != null) 'label': label,
        if (due != null) 'due': due,
      };

  static NoteTag? fromJson(Object? j) {
    if (j is! Map) return null;
    final line = (j['line'] as num?)?.toInt();
    if (line == null) return null;
    // An unparseable due date is dropped rather than carried: it can only have
    // come from a corrupted write or a future format, and a date the planner
    // cannot place would otherwise be invisible but permanent.
    final rawDue = j['due'];
    final due =
        rawDue is String && parseDayKey(rawDue) != null ? rawDue : null;
    return NoteTag(
      kind: TagKind.parse(j['kind'] as String?),
      line: line,
      checked: j['checked'] as bool?,
      label: j['label'] as String?,
      due: due,
    );
  }

  /// Read a block's tag list. Tolerates absent/garbage entries — a malformed
  /// tag must not cost the block.
  static List<NoteTag> listFrom(Map<String, dynamic> content) {
    final raw = content['tags'];
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (fromJson(e) case final t?) t
    ];
  }

  /// A block's tags grouped by line, which is how the renderer needs them.
  static Map<int, List<NoteTag>> byLine(Map<String, dynamic> content) {
    final out = <int, List<NoteTag>>{};
    for (final t in listFrom(content)) {
      out.putIfAbsent(t.line, () => []).add(t);
    }
    return out;
  }

  /// Follow the tags when the text around them gains or loses lines.
  ///
  /// **A tag records a line INDEX**, which is what makes it survive edits to
  /// other lines and travel through the op log with no new op kind — but it
  /// also means pressing Enter above a tagged line silently moves the marker
  /// onto the wrong sentence. That is not cosmetic: `cardsFromBlock` reads
  /// `lines[tag.line]`, so a flashcard's question and answer quietly change
  /// while its id — `blockId:line` — stays the same, and the review schedule
  /// stays attached to a card that is now about something else.
  ///
  /// Rebasing off a common prefix/suffix of the two texts, so it is exact for
  /// the ordinary cases (typing a new line, deleting one, pasting a block of
  /// them) and a no-op for an edit that changes no line count. A tag on a line
  /// that was deleted outright goes with it.
  ///
  /// Returns the old-line → new-line moves, so the caller can carry anything
  /// keyed on the line number across with them. That is not optional: a
  /// flashcard's identity is `blockId:line`, so a tag that moves without its
  /// schedule moving too *is* a lost schedule.
  static Map<int, int> rebase(
      Map<String, dynamic> content, String before, String after) {
    if (before == after) return const {};
    final oldLines = before.split('\n');
    final newLines = after.split('\n');
    final delta = newLines.length - oldLines.length;
    if (delta == 0) return const {}; // same shape: indices still point at themselves

    final tags = listFrom(content);
    if (tags.isEmpty) return const {};

    // Unchanged lines at the top, then at the bottom. Everything between them
    // is the edit.
    var head = 0;
    while (head < oldLines.length &&
        head < newLines.length &&
        oldLines[head] == newLines[head]) {
      head++;
    }
    var tail = 0;
    while (tail < oldLines.length - head &&
        tail < newLines.length - head &&
        oldLines[oldLines.length - 1 - tail] ==
            newLines[newLines.length - 1 - tail]) {
      tail++;
    }
    final changedEnd = oldLines.length - tail; // exclusive, in OLD coordinates

    // A PURE insertion leaves every old line intact — nothing was removed, so
    // a tag inside the region still marks real text and simply moves down.
    // Any other edit rewrote those lines, and a tag inside it no longer marks
    // anything the user wrote: shifting it by `delta` would silently relocate
    // the marker onto a line it never marked, which is worse than losing it.
    final pureInsertion = changedEnd == head;

    final moved = <int, int>{};
    final out = <NoteTag>[];
    for (final t in tags) {
      if (t.line < head) {
        out.add(t); // above the edit: untouched
      } else if (t.line >= changedEnd || pureInsertion) {
        final to = t.line + delta;
        moved[t.line] = to;
        // Every field is carried, not just the ones rebasing cares about. This
        // reconstruction is the one place a new tag field is silently lost —
        // pressing Enter above a dated task would clear its deadline, from a
        // keystroke that changed nothing about it.
        out.add(NoteTag(
            kind: t.kind,
            line: to,
            checked: t.checked,
            label: t.label,
            due: t.due));
      }
      // Inside a rewritten region: the line it marked is gone, and so is it.
    }
    writeInto(content, out);
    return moved;
  }

  /// Write a tag list back, removing the key entirely when empty so untagged
  /// blocks don't carry a dead field into every save and every op.
  static void writeInto(Map<String, dynamic> content, List<NoteTag> tags) {
    if (tags.isEmpty) {
      content.remove('tags');
    } else {
      content['tags'] = [for (final t in tags) t.toJson()];
    }
  }
}
