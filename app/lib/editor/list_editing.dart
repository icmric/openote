/// **The** definition of a list line, and the keystrokes that maintain one.
///
/// Before this file, five places each had their own idea of what a bullet is
/// (`md_render._reBullet` took only `-`, the live controller's `_prefixRe`
/// took `[-*]`, `toggleLinePrefix` matched a third set, the importer emitted
/// a fourth), which is why `* item` greyed out like a real marker while you
/// typed it and then reappeared as literal text the moment you clicked away.
/// Everything that needs to know what a list line is now asks here.
///
/// It is deliberately pure — `(text, selection) → (text, selection)` — so the
/// behaviour every note-taker has muscle memory for (Enter continues, Enter on
/// an empty item exits, Tab nests, Backspace unwraps) is testable without a
/// widget, a canvas or a notebook.
library;

import 'package:flutter/services.dart';

/// Two spaces per level, matching the importer, `indentPx()` and Markdown
/// convention. One constant so nesting cannot drift between them.
const int kListIndentSpaces = 2;

enum ListKind { bullet, numbered, checkbox }

/// A parsed list line. `indent + marker + gap + body` reassembles the source
/// exactly, which the round-trip test relies on.
class ListLine {
  const ListLine({
    required this.indent,
    required this.kind,
    required this.marker,
    required this.gap,
    required this.body,
    this.number = 0,
    this.checked = false,
    this.numberDelim = '.',
  });

  /// Leading whitespace, verbatim.
  final String indent;
  final ListKind kind;

  /// The marker as written: `-`, `*`, `+`, `12.`, `- [ ]`, `* [x]`.
  final String marker;

  /// The whitespace between marker and body.
  final String gap;
  final String body;
  final int number;
  final bool checked;
  final String numberDelim;

  /// Nesting depth, counting a tab as one full level.
  int get level => indentWidth ~/ kListIndentSpaces;

  /// Indent measured in spaces, with tabs expanded — so a list indented with
  /// tabs (what a lot of pasted text uses) nests the same as one indented
  /// with spaces instead of being treated as a single deep level.
  int get indentWidth {
    var w = 0;
    for (final c in indent.codeUnits) {
      w += c == 0x09 ? kListIndentSpaces : 1;
    }
    return w;
  }

  /// Where the body starts within the line.
  int get bodyStart => indent.length + marker.length + gap.length;

  /// The bullet/number character(s) only — `-`, `*`, `+`, or `1`.
  String get bulletChar =>
      kind == ListKind.checkbox ? marker.substring(0, 1) : marker;

  bool get isEmpty => body.trim().isEmpty;

  String get prefix => '$indent$marker$gap';

  /// This line's prefix at a different indent, optionally renumbered and
  /// always unchecked — what the NEXT item looks like.
  String prefixFor({String? indentOverride, int? number, bool? checked}) {
    final ind = indentOverride ?? indent;
    switch (kind) {
      case ListKind.bullet:
        return '$ind$marker$gap';
      case ListKind.numbered:
        return '$ind${number ?? this.number}$numberDelim$gap';
      case ListKind.checkbox:
        final box = (checked ?? false) ? 'x' : ' ';
        return '$ind$bulletChar [$box]$gap';
    }
  }
}

// A checkbox is a bullet with a box, so it MUST be tried first or `- [ ] x`
// parses as a bullet whose body is `[ ] x`.
final _reCheckbox = RegExp(r'^([ \t]*)([-*+]) \[([ xX])\]([ \t]+)(.*)$');
final _reNumbered = RegExp(r'^([ \t]*)(\d{1,9})([.)])([ \t]+)(.*)$');
final _reBullet = RegExp(r'^([ \t]*)([-*+])([ \t]+)(.*)$');

/// An empty item — `- ` with nothing after it — still has to parse, or
/// pressing Enter on one could not exit the list.
final _reCheckboxBare = RegExp(r'^([ \t]*)([-*+]) \[([ xX])\]([ \t]*)$');
final _reNumberedBare = RegExp(r'^([ \t]*)(\d{1,9})([.)])([ \t]*)$');
final _reBulletBare = RegExp(r'^([ \t]*)([-*+])([ \t]*)$');

/// A horizontal rule (`---`, `***`) is not a list item, however much it looks
/// like one. Checked before bullets so typing a divider does not start a list.
final _reDivider = RegExp(r'^[ \t]*([-*_])([ \t]*\1){2,}[ \t]*$');

/// Parse [line] as a list item, or null when it is not one.
ListLine? parseListLine(String line) {
  if (_reDivider.hasMatch(line)) return null;

  final cb = _reCheckbox.firstMatch(line) ?? _reCheckboxBare.firstMatch(line);
  if (cb != null) {
    final bare = cb.groupCount == 4;
    return ListLine(
      indent: cb.group(1)!,
      kind: ListKind.checkbox,
      marker: '${cb.group(2)!} [${cb.group(3)!}]',
      gap: bare ? (cb.group(4)!.isEmpty ? ' ' : cb.group(4)!) : cb.group(4)!,
      body: bare ? '' : cb.group(5)!,
      checked: cb.group(3)!.toLowerCase() == 'x',
    );
  }

  final num = _reNumbered.firstMatch(line) ?? _reNumberedBare.firstMatch(line);
  if (num != null) {
    final bare = num.groupCount == 4;
    return ListLine(
      indent: num.group(1)!,
      kind: ListKind.numbered,
      marker: '${num.group(2)!}${num.group(3)!}',
      gap: bare ? (num.group(4)!.isEmpty ? ' ' : num.group(4)!) : num.group(4)!,
      body: bare ? '' : num.group(5)!,
      number: int.tryParse(num.group(2)!) ?? 1,
      numberDelim: num.group(3)!,
    );
  }

  final b = _reBullet.firstMatch(line) ?? _reBulletBare.firstMatch(line);
  if (b != null) {
    final bare = b.groupCount == 3;
    return ListLine(
      indent: b.group(1)!,
      kind: ListKind.bullet,
      marker: b.group(2)!,
      gap: bare ? (b.group(3)!.isEmpty ? ' ' : b.group(3)!) : b.group(3)!,
      body: bare ? '' : b.group(4)!,
    );
  }
  return null;
}

// ── Line/offset helpers ───────────────────────────────────────────────────

int lineStartOf(String text, int offset) {
  // Offset 0 is the start of the first line, always. Searching backwards
  // from 0 in text that BEGINS with a newline found that newline and
  // reported a line start of 1 — after the caret — and the substring that
  // followed threw a RangeError inside the toolbar's heading command.
  if (offset <= 0) return 0;
  return text.lastIndexOf('\n', offset - 1) + 1;
}

int lineEndOf(String text, int offset) {
  final i = text.indexOf('\n', offset);
  return i < 0 ? text.length : i;
}

TextEditingValue _replace(
    TextEditingValue v, int start, int end, String with_, int caret) {
  return TextEditingValue(
    text: v.text.replaceRange(start, end, with_),
    selection: TextSelection.collapsed(offset: caret),
    composing: TextRange.empty,
  );
}

// ── The keystrokes ────────────────────────────────────────────────────────

/// Enter on a list line. Null when the caret is not in a list, so the field
/// keeps its ordinary newline.
///
/// Three cases, and they are the ones every editor agrees on:
/// * a NON-empty item continues — same kind, same indent, next number;
/// * an EMPTY item at depth 0 ends the list, leaving a plain empty line;
/// * an EMPTY item that is nested OUTDENTS one level first, so a train of
///   Enters walks back out of a deep outline instead of trapping you in it.
TextEditingValue? handleListEnter(TextEditingValue v) {
  final sel = v.selection;
  if (!sel.isValid) return null;
  final start = sel.start, end = sel.end;
  final ls = lineStartOf(v.text, start);
  final line = v.text.substring(ls, lineEndOf(v.text, start));
  final p = parseListLine(line);
  if (p == null) return null;

  // The caret has to be in or after the body for Enter to mean "next item";
  // inside the marker it means an ordinary line break.
  if (start - ls < p.bodyStart) return null;

  if (p.isEmpty && start == end) {
    if (p.indentWidth > 0) {
      final outdent = _dropOneLevel(p.indent);
      final next = p.prefixFor(indentOverride: outdent);
      return renumberValue(
          _replace(v, ls, ls + line.length, next, ls + next.length));
    }
    // End the list: the empty marker goes, the line stays.
    return renumberValue(_replace(v, ls, ls + line.length, '', ls));
  }

  final nextNumber = p.kind == ListKind.numbered ? p.number + 1 : null;
  final prefix = p.prefixFor(number: nextNumber);
  final insert = '\n$prefix';
  return renumberValue(
      _replace(v, start, end, insert, start + insert.length));
}

/// Shift+Enter — a soft break that keeps you inside the same item, indented
/// under its text. Multi-line bullets are how people actually take notes.
TextEditingValue? handleListShiftEnter(TextEditingValue v) {
  final sel = v.selection;
  if (!sel.isValid) return null;
  final ls = lineStartOf(v.text, sel.start);
  final line = v.text.substring(ls, lineEndOf(v.text, sel.start));
  final p = parseListLine(line);
  if (p == null) return null;
  // The item's OWN indent, not its body offset. Leading spaces are a nesting
  // encoding — two spaces is one level — so padding to the body (`- [ ] `
  // is six characters) declared three levels of nesting and threw the
  // continuation 87px right of the text it belongs to. Matching the item's
  // indent keeps it at the item's level; true alignment under the body is a
  // hanging indent, which a run of spaces cannot express.
  final insert = '\n${p.indent}';
  return _replace(v, sel.start, sel.end, insert, sel.start + insert.length);
}

/// Tab / Shift+Tab.
///
/// On a list line it nests or un-nests the item — the single most-used key in
/// outlining. On any other line it is a plain two-space indent, so Tab always
/// means "indent" inside a text box and never means "leave the text box",
/// which is what it used to do.
TextEditingValue? handleListTab(TextEditingValue v, {required bool outdent}) {
  final sel = v.selection;
  if (!sel.isValid) return null;
  final firstLs = lineStartOf(v.text, sel.start);
  final lastLe = lineEndOf(v.text, _lastLineOffset(v.text, sel));
  final region = v.text.substring(firstLs, lastLe);
  final lines = region.split('\n');

  // Indenting the FIRST item of a list would make it a child of nothing, so
  // Markdown (and every outliner) refuses. Only refuse when there is no
  // possible parent above it.
  if (!outdent && lines.length == 1) {
    final p = parseListLine(lines.first);
    if (p != null && !_hasParentAbove(v.text, firstLs, p)) return null;
  }

  var changed = false;
  final out = <String>[];
  for (final l in lines) {
    if (outdent) {
      final p = parseListLine(l);
      final ind = p?.indent ?? RegExp(r'^[ \t]*').stringMatch(l) ?? '';
      if (ind.isEmpty) {
        out.add(l);
        continue;
      }
      changed = true;
      out.add(_dropOneLevel(ind) + l.substring(ind.length));
    } else {
      if (l.trim().isEmpty && lines.length > 1) {
        out.add(l);
        continue;
      }
      changed = true;
      out.add('${' ' * kListIndentSpaces}$l');
    }
  }
  if (!changed) return null;

  final next = out.join('\n');
  final firstDelta = out.first.length - lines.first.length;
  return renumberValue(TextEditingValue(
    text: v.text.replaceRange(firstLs, lastLe, next),
    // Shift the START of the selection by what happened to its OWN line and
    // the end by the whole change — then map back through base/extent, which
    // may be the other way round. Assuming base is the earlier offset broke
    // every backwards selection (Shift+Up, or dragging right to left), and
    // assuming the first line always moved broke the case where it did not.
    selection: _selectionAfter(sel,
        regionStart: firstLs, regionLength: next.length, caretDelta: firstDelta),
    composing: TextRange.empty,
  ));
}

/// The offset of the LAST line a selection really touches.
///
/// A selection that ends exactly at a line start does not include that line —
/// which is precisely what Shift+Down and a triple-click produce, so Tab used
/// to silently indent one line more than was highlighted.
int _lastLineOffset(String text, TextSelection sel) {
  if (sel.end > sel.start && sel.end > 0 && lineStartOf(text, sel.end) == sel.end) {
    return sel.end - 1;
  }
  return sel.end;
}

/// Where the selection goes after a line-level edit.
///
/// A CARET moves with its own line's change, so it stays next to the words it
/// was next to. A RANGE covers the whole rewritten region instead: shifting
/// its start by the first line's delta pushed it PAST the marker that was
/// just inserted, so selecting two lines and pressing Bullet came back with
/// only the second line's marker and a stray letter highlighted.
/// Direction is preserved either way — a backwards drag that comes back
/// inverted is its own bug.
TextSelection _selectionAfter(
  TextSelection sel, {
  required int regionStart,
  required int regionLength,
  required int caretDelta,
}) {
  if (sel.isCollapsed) {
    return TextSelection.collapsed(
        offset: (sel.start + caretDelta).clamp(regionStart, regionStart + regionLength));
  }
  final a = regionStart, b = regionStart + regionLength;
  return sel.baseOffset <= sel.extentOffset
      ? TextSelection(baseOffset: a, extentOffset: b)
      : TextSelection(baseOffset: b, extentOffset: a);
}

/// Backspace at the very start of an item's text.
///
/// Nested → outdent (so backspace walks a deep item back out); top level →
/// drop the marker and keep the words. Never eats the line break, which is
/// what made deleting a bullet feel like it deleted the line.
TextEditingValue? handleListBackspace(TextEditingValue v) {
  final sel = v.selection;
  if (!sel.isValid || !sel.isCollapsed) return null;
  final ls = lineStartOf(v.text, sel.start);
  final line = v.text.substring(ls, lineEndOf(v.text, sel.start));
  final p = parseListLine(line);
  if (p == null || sel.start - ls != p.bodyStart) return null;

  if (p.indentWidth > 0) {
    final next = _dropOneLevel(p.indent) + line.substring(p.indent.length);
    final shift = next.length - line.length;
    return renumberValue(
        _replace(v, ls, ls + line.length, next, sel.start + shift));
  }
  // The caret stays with the first word: it was at the start of the body
  // before the marker went, so it is at the start of the line after.
  return renumberValue(_replace(v, ls, ls + line.length, p.body, ls));
}

/// One indent level off a leading-whitespace run, tab-aware.
String _dropOneLevel(String indent) {
  if (indent.isEmpty) return indent;
  if (indent.endsWith('\t')) return indent.substring(0, indent.length - 1);
  var drop = 0;
  while (drop < kListIndentSpaces &&
      drop < indent.length &&
      indent[indent.length - 1 - drop] == ' ') {
    drop++;
  }
  return indent.substring(0, indent.length - drop);
}

/// Is there a list item ABOVE this one that could be its parent? Used to stop
/// Tab creating an orphan first item.
bool _hasParentAbove(String text, int lineStart, ListLine self) {
  var at = lineStart;
  while (at > 0) {
    final prevEnd = at - 1;
    final prevStart = lineStartOf(text, prevEnd);
    final prev = text.substring(prevStart, prevEnd);
    if (prev.trim().isEmpty) return false;
    final p = parseListLine(prev);
    if (p == null) return false;
    if (p.indentWidth <= self.indentWidth) return true;
    at = prevStart;
  }
  return false;
}

// ── Renumbering ───────────────────────────────────────────────────────────

/// Rewrite every ordered list so it counts 1, 2, 3 … per level.
///
/// Without this the renderer prints whatever digit is in the source, so the
/// toolbar's `1. ` on five lines rendered "1. 1. 1. 1. 1." and deleting an
/// item left a hole in the numbering. Runs are broken by a blank line or a
/// non-list line, which is what Markdown means by a separate list.
String renumberOrderedLists(String text) => _renumber(text, null).text;

/// Renumber and carry the caret, for the keystroke handlers.
TextEditingValue renumberValue(TextEditingValue v) {
  final r = _renumber(v.text, v.selection.isValid ? v.selection : null);
  if (r.text == v.text) return v;
  return TextEditingValue(
    text: r.text,
    selection: r.selection ?? v.selection,
    composing: TextRange.empty,
  );
}

class _Renumbered {
  const _Renumbered(this.text, this.selection);
  final String text;
  final TextSelection? selection;
}

_Renumbered _renumber(String text, TextSelection? sel) {
  final lines = text.split('\n');
  final counters = <int, int>{};
  var prevWasItem = false;
  var prevIndentWidth = 0;
  var base = 0; // offset of the current line in the ORIGINAL text
  var baseShift = 0, extentShift = 0;
  final out = <String>[];
  var touched = false;

  for (final line in lines) {
    final p = parseListLine(line);
    if (p == null) {
      // An INDENTED non-list line is the second line of the item above it —
      // what Shift+Enter produces — so it must not end the run. Treating it
      // as prose reset the numbering, and every item below a multi-line one
      // silently started counting from 1 again.
      final isContinuation = prevWasItem &&
          line.trim().isNotEmpty &&
          RegExp(r'^[ \t]').hasMatch(line);
      if (!isContinuation) {
        counters.clear();
        prevWasItem = false;
      }
      out.add(line);
      base += line.length + 1;
      continue;
    }
    if (p.kind != ListKind.numbered) {
      // A bullet at this depth interrupts an ordered run at the same depth,
      // but leaves shallower runs alone.
      counters.removeWhere((k, _) => k >= p.indentWidth);
      prevWasItem = true;
      prevIndentWidth = p.indentWidth;
      out.add(line);
      base += line.length + 1;
      continue;
    }
    counters.removeWhere((k, _) => k > p.indentWidth);
    // The FIRST item of a run keeps the number the user typed — a list that
    // deliberately starts at 7 counts 7, 8, 9 (CommonMark agrees), and
    // pressing Enter on `3)` must not silently renumber the line under you.
    // The one exception is an item that has just become somebody's first
    // CHILD: a fresh sublist starts at 1, because the number it carried down
    // belonged to the list it left. Everything after the first item is
    // corrected, which is what turns the toolbar's `1. ` on every line into
    // 1, 2, 3 without ever overriding an intent.
    final started = counters.containsKey(p.indentWidth);
    final freshChild = !started && prevWasItem && prevIndentWidth < p.indentWidth;
    final n = started
        ? counters[p.indentWidth]! + 1
        : (freshChild ? 1 : p.number);
    counters[p.indentWidth] = n;
    prevWasItem = true;
    prevIndentWidth = p.indentWidth;
    if (n == p.number) {
      out.add(line);
      base += line.length + 1;
      continue;
    }
    touched = true;
    final next = '${p.indent}$n${p.numberDelim}${p.gap}${p.body}';
    final d = next.length - line.length;
    // Offsets after the marker on this line, and every offset on later
    // lines, move by the digit-count change.
    final markerEnd = base + p.indent.length + p.marker.length;
    if (sel != null) {
      if (sel.baseOffset >= markerEnd) baseShift += d;
      if (sel.extentOffset >= markerEnd) extentShift += d;
    }
    out.add(next);
    base += line.length + 1;
  }
  if (!touched) return _Renumbered(text, sel);
  final next = out.join('\n');
  return _Renumbered(
    next,
    sel == null
        ? null
        : TextSelection(
            baseOffset: (sel.baseOffset + baseShift).clamp(0, next.length),
            extentOffset: (sel.extentOffset + extentShift).clamp(0, next.length),
          ),
  );
}

// ── Toolbar / command support ─────────────────────────────────────────────

/// Toggle a list kind over the lines the selection touches.
///
/// Indentation-aware, unlike the string-prefix toggle it replaces: a nested
/// item keeps its level instead of becoming `-   - item`, a checkbox is not
/// destroyed by the bullet button, and converting between kinds swaps the
/// marker rather than stacking a second one.
TextEditingValue toggleListOverSelection(TextEditingValue v, ListKind kind) {
  final sel = v.selection.isValid
      ? v.selection
      : TextSelection.collapsed(offset: v.text.length);
  final firstLs = lineStartOf(v.text, sel.start);
  final lastLe = lineEndOf(v.text, _lastLineOffset(v.text, sel));
  final region = v.text.substring(firstLs, lastLe);
  final lines = region.split('\n');

  final parsed = [for (final l in lines) parseListLine(l)];
  // "Already this kind" means every non-blank line is — so a mixed selection
  // becomes uniform on the first press rather than toggling half of it off.
  final relevant = [
    for (var i = 0; i < lines.length; i++)
      if (lines[i].trim().isNotEmpty) i
  ];
  final allSame = relevant.isNotEmpty &&
      relevant.every((i) => parsed[i]?.kind == kind);

  final out = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final p = parsed[i];
    if (line.trim().isEmpty) {
      out.add(line);
      continue;
    }
    if (allSame) {
      out.add((p?.indent ?? '') + (p?.body ?? line));
      continue;
    }
    final indent = p?.indent ?? RegExp(r'^[ \t]*').stringMatch(line) ?? '';
    final body = p?.body ?? line.substring(indent.length);
    out.add(switch (kind) {
      ListKind.bullet => '$indent- $body',
      ListKind.numbered => '${indent}1. $body',
      ListKind.checkbox => '$indent- [ ] $body',
    });
  }

  final next = out.join('\n');
  // Keep the caret with its words instead of teleporting it to the end of
  // the region, which is what the old toggle did — and preserve the
  // selection's DIRECTION, or a backwards drag came back inverted and
  // covering the wrong characters.
  final firstDelta = out.first.length - lines.first.length;
  return renumberValue(TextEditingValue(
    text: v.text.replaceRange(firstLs, lastLe, next),
    selection: _selectionAfter(sel,
        regionStart: firstLs, regionLength: next.length, caretDelta: firstDelta),
    composing: TextRange.empty,
  ));
}

/// Tick or untick the checkbox on the line at [offset]. Returns null when
/// that line is not a checkbox.
TextEditingValue? toggleCheckboxAt(TextEditingValue v, int offset) {
  final ls = lineStartOf(v.text, offset);
  final le = lineEndOf(v.text, offset);
  final p = parseListLine(v.text.substring(ls, le));
  if (p == null || p.kind != ListKind.checkbox) return null;
  final next = '${p.prefixFor(checked: !p.checked)}${p.body}';
  return TextEditingValue(
    text: v.text.replaceRange(ls, le, next),
    selection: v.selection,
    composing: TextRange.empty,
  );
}
