/// **A space typed at the edge of a styled run goes outside it.**
///
/// The owner, on bolding a word and pressing space after it: *"it breaks the
/// interpreter and shows the `**`, that is not what i want at all. It should
/// never under any circumstances show the md styling chars after the style has
/// been applied, it should act like a wysiwyg editor but allow for markdown
/// interpretation too as a shortcut."*
///
/// **Why it happened.** Emphasis markers carry CommonMark's flanking rule —
/// `_b` in `md_syntax.dart` is `\*\*(?![\s*])(.+?)(?<![\s*])\*\*`, so a marker
/// may not sit against a space. That rule is not decoration: it is what stops
/// `2 * 3 * 4` italicising and what keeps `snake_case_name` intact. And the
/// caret is deliberately left INSIDE the closing markers after a style is
/// applied ([AppState.applyPendingMarks]), because that is what makes the next
/// keystroke extend the run rather than follow it.
///
/// Those two correct decisions meet on the space bar. The space lands between
/// the word and its closing marker, `**bold**` becomes `**bold **`, the
/// flanking guard refuses it, and what was a bold word is suddenly four
/// asterisks and some text. Nothing is corrupted — but the student sees the
/// markup they were promised they would never see, which is the same thing
/// from where they are sitting.
///
/// **The fix is to move the space, not to loosen the rule.** A trailing space
/// inside emphasis is not expressible in Markdown at all, so there is no
/// reading of `**bold **` that keeps the bold; the only lossless answer is to
/// put the space on the other side of the marker, which is where a word
/// processor puts it too. `**bold** ` is what the student meant and what they
/// see.
///
/// Done as a formatter rather than a key handler because it must catch a space
/// however it arrives — the space bar, a paste, an IME — and because the edit
/// is a relocation of what was already typed rather than a new command.
library;

import 'package:flutter/services.dart';

import '../markdown/md_syntax.dart';

/// How deep to look for a run whose edge the caret is on.
///
/// One level catches every case anybody reports, because `mdInlineRe` walks
/// non-overlapping matches and therefore only ever sees the OUTERMOST run on a
/// line. A space at the inner edge of `*b*` inside `**a *b* c**` is on nobody's
/// edge at the top level, so the inner text is scanned again. Two levels of
/// nesting is already more than prose does; the cap is here so a pathological
/// line cannot turn one keystroke into a long walk.
const int _maxDepth = 3;

/// The relocated edit, or null when there is nothing to move.
///
/// Null is the answer for the overwhelming majority of keystrokes — anything
/// that is not whitespace arriving at the exact inside edge of a run that the
/// whitespace would break. Code spans come back null too, and deliberately:
/// `` `a ` `` has no flanking guard, so a space before its closing backtick is
/// legal Markdown and moving it would change what the student wrote.
TextEditingValue? relocateEdgeWhitespace(
    TextEditingValue oldValue, TextEditingValue newValue) {
  final sel = oldValue.selection;
  if (!sel.isValid || !sel.isCollapsed) return null;
  final at = sel.baseOffset;
  final old = oldValue.text;
  final next = newValue.text;
  if (at < 0 || at > old.length) return null;

  // A pure insertion at the caret, and nothing else. Anything that also
  // removed or replaced text is somebody else's edit and is left alone.
  final grew = next.length - old.length;
  if (grew <= 0) return null;
  final ins = next.substring(at, at + grew);
  if (next.replaceRange(at, at + grew, '') != old) return null;
  // Space and tab only. A newline genuinely ends the paragraph the run is in,
  // and Enter is answered by the list engine before this ever sees it.
  if (!RegExp(r'^[ \t]+$').hasMatch(ins)) return null;
  // The caret must be where the insertion was, or this is a programmatic edit
  // whose caret means something we have no business moving.
  final after = newValue.selection;
  if (!after.isValid || !after.isCollapsed || after.baseOffset != at + grew) {
    return null;
  }

  final lineStart = at == 0 ? 0 : old.lastIndexOf('\n', at - 1) + 1;
  final nl = old.indexOf('\n', at);
  final lineEnd = nl < 0 ? old.length : nl;

  final moved = _edgeOf(old, lineStart, lineEnd, at, ins, 0);
  if (moved == null) return null;
  return TextEditingValue(
    text: old.replaceRange(moved, moved, ins),
    selection: TextSelection.collapsed(offset: moved + ins.length),
    composing: TextRange.empty,
  );
}

/// Where [ins] should have gone, given the caret is at [at] inside
/// `text[from..to)`. Null when the caret is not on a run's inside edge, or
/// when the run survives the insertion anyway.
int? _edgeOf(String text, int from, int to, int at, String ins, int depth) {
  if (depth >= _maxDepth || from >= to) return null;
  final span = text.substring(from, to);
  for (final m in mdInlineRe.allMatches(span)) {
    final c = classifyInline(m);
    // No opening marker means nothing to sit against: an atom reference, a
    // link, an equation. Their own guards are elsewhere.
    if (c.openLen == 0 || c.closeLen == 0) continue;
    final start = from + m.start;
    final end = from + m.end;
    final innerStart = start + c.openLen;
    final innerEnd = end - c.closeLen;
    if (at < innerStart || at > innerEnd) continue;
    if (at != innerStart && at != innerEnd) {
      // Strictly inside, so this run is not the one breaking — but a nested
      // one might be. `**a *b* c**` is one match at this level.
      return _edgeOf(text, innerStart, innerEnd, at, ins, depth + 1);
    }
    // Does it actually break? Asking rather than assuming is what keeps code
    // spans, and anything else without a flanking guard, untouched.
    if (_stillMatches(span, m.start, m.end, c.kind, at - from, ins)) {
      return null;
    }
    return at == innerEnd ? end : start;
  }
  return null;
}

/// True when the same run, in the same place and of the same kind, survives
/// [ins] being put at [at] (both offsets relative to [span]).
bool _stillMatches(
    String span, int start, int end, MdInline kind, int at, String ins) {
  final after = span.replaceRange(at, at, ins);
  for (final m in mdInlineRe.allMatches(after)) {
    if (m.start != start) continue;
    return classifyInline(m).kind == kind && m.end == end + ins.length;
  }
  return false;
}

/// [relocateEdgeWhitespace] as the field sees it.
class EmphasisGuardFormatter extends TextInputFormatter {
  const EmphasisGuardFormatter();

  @override
  TextEditingValue formatEditUpdate(
          TextEditingValue oldValue, TextEditingValue newValue) =>
      relocateEdgeWhitespace(oldValue, newValue) ?? newValue;
}
