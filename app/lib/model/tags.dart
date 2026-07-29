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
library;

import 'package:flutter/material.dart';

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

  String get displayLabel => label ?? kind.label;

  NoteTag copyWith({int? line, bool? checked}) => NoteTag(
        kind: kind,
        line: line ?? this.line,
        checked: checked ?? this.checked,
        label: label,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind.key,
        'line': line,
        if (checked != null) 'checked': checked,
        if (label != null) 'label': label,
      };

  static NoteTag? fromJson(Object? j) {
    if (j is! Map) return null;
    final line = (j['line'] as num?)?.toInt();
    if (line == null) return null;
    return NoteTag(
      kind: TagKind.parse(j['kind'] as String?),
      line: line,
      checked: j['checked'] as bool?,
      label: j['label'] as String?,
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
