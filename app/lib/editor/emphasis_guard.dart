/// **Markers and the text they style are never separated.**
///
/// The owner asked for one thing, twice: *"It should never under any
/// circumstances show the md styling chars after the style has been applied,
/// it should act like a wysiwyg editor but allow for markdown interpretation
/// too as a shortcut. It does not have to functionally be designed that way,
/// however it must behave like that to a user."*
///
/// Markdown emphasis is fragile in exactly two places, and both are reachable
/// with one keystroke:
///
///  1. **A marker may not sit against a space.** `_b` in `md_syntax.dart` is
///     `\*\*(?![\s*])(.+?)(?<![\s*])\*\*`, which is CommonMark's flanking rule
///     and is load-bearing — it is what stops `2 * 3 * 4` italicising and what
///     keeps `snake_case_name` whole. Meanwhile the caret is parked INSIDE the
///     closing markers after a style is applied ([AppState.applyPendingMarks]),
///     because that is what makes the next keystroke extend the run. So the
///     space bar aims straight at the one offset a marker may not occupy, and
///     `**big**` became `**big **` — four asterisks in a sentence.
///
///  2. **A marker is nothing without its partner.** The markers cannot be
///     seen, so a selection dragged over a bold word is really a selection
///     over some of `**big**`, and deleting it left `**` behind — *"if i back
///     select a bold word it will remove it but leave ** at the start, so it
///     doesnt remove it all"*. [LiveMarkdownController.markerAwareDelete]
///     already answers this for a Backspace at a marker edge, but it takes a
///     collapsed caret only and returns null for a selection, which then falls
///     through to the field's own delete.
///
/// Three rules, in the order they are asked:
///
///  * [healOrphanedMarkers] — a selection edit never leaves half a run. If
///    nothing of the styled text survives, both markers go with it; if some
///    of it survives, the missing marker is put back around what is left.
///  * [relocateEdgeWhitespace] — whitespace typed at a run's inside edge goes
///    outside the marker instead, because `**big **` is not expressible as
///    bold at all and `**big** ` is what was meant.
///  * [mergeRunAtCaret] — and two runs of the same kind with only whitespace
///    between them ARE one run, which is what carries a style across the space
///    that rule two just stepped over.
///
/// Together those last two are how bolding survives the space bar: the space
/// moves out, the queue is re-armed so the next word is wrapped too, and the
/// two runs are then folded back into one. The buffer ends up holding
/// `**big more**`, which is what somebody would have typed by hand.
///
/// Done as a formatter because it must catch every route in — the space bar, a
/// paste, an IME, a selection typed over — and because each rule relocates or
/// repairs what was already typed rather than adding a command of its own.
library;

import 'package:flutter/services.dart';

import '../markdown/md_syntax.dart';
import '../state/app_state.dart';

/// How deep to look for a run whose edge the caret is on.
///
/// `mdInlineRe` walks non-overlapping matches, so it only ever sees the
/// OUTERMOST run on a line: a space at the inner edge of `*b*` inside
/// `**a *b* c**` is on nobody's edge at the top level. The inner text is
/// scanned again for that. Two levels of nesting is already more than prose
/// does; the cap is here so a pathological line cannot turn one keystroke into
/// a long walk.
const int _maxDepth = 3;

/// A relocated edit, and the marker whose run it just stepped out of.
///
/// [carryOn] is non-null only at a CLOSING edge, and it is what lets the
/// caller keep the style going: the student was writing in bold and pressed
/// space, so they are still writing in bold.
typedef EdgeMove = ({TextEditingValue value, String? carryOn});

// ─── Rule one: never half a run ────────────────────────────────────────────

/// The repaired edit, or null when this edit leaves no marker orphaned.
///
/// Only a selection edit can do this — a collapsed caret deletes one character
/// through [LiveMarkdownController.markerAwareDelete], which already knows
/// about marker edges.
TextEditingValue? healOrphanedMarkers(
    TextEditingValue oldValue, TextEditingValue newValue) {
  final sel = oldValue.selection;
  if (!sel.isValid || sel.isCollapsed) return null;
  final t = oldValue.text;
  final a = sel.start;
  final b = sel.end;
  if (a < 0 || b > t.length) return null;

  // What replaced the selection, and a check that this really is that edit
  // and not something else that happened to arrive with a selection set.
  final tail = t.length - b;
  if (newValue.text.length < a + tail) return null;
  final ins = newValue.text.substring(a, newValue.text.length - tail);
  if (t.replaceRange(a, b, ins) != newValue.text) return null;
  if (ins.contains('\n')) return null;

  final lineStart = a == 0 ? 0 : t.lastIndexOf('\n', a - 1) + 1;
  final nl = t.indexOf('\n', a);
  final lineEnd = nl < 0 ? t.length : nl;
  // A selection across a line break is somebody deleting paragraphs, not
  // somebody deleting a word. The grammar is line-based; leave it alone.
  if (b > lineEnd) return null;

  final span = t.substring(lineStart, lineEnd);
  for (final m in mdInlineRe.allMatches(span)) {
    final c = classifyInline(m);
    if (c.openLen == 0 || c.closeLen == 0) continue;
    final s = lineStart + m.start;
    final e = lineStart + m.end;
    final innerStart = s + c.openLen;
    final innerEnd = e - c.closeLen;
    if (b <= s || a >= e) continue; // this run was not touched

    final openGone = a <= s && b >= innerStart;
    final closeGone = a <= innerEnd && b >= e;
    final touchesInner = b > innerStart && a < innerEnd;
    if (!openGone && !closeGone && !touchesInner) continue;

    // How much of the styled text is left standing, counting anything typed
    // over the selection as text that belongs inside the run.
    final kept = _clamp((a < innerEnd ? a : innerEnd) - innerStart) +
        _clamp(innerEnd - (b > innerStart ? b : innerStart)) +
        ins.length;
    if (kept == 0) {
      // Nothing styled survives, so the markers have nothing left to mark.
      // Widen to the whole run rather than leaving any of it behind.
      //
      // This is the case where BOTH markers are still standing, too: select
      // exactly the word you can see and `**big**` becomes `****`, which no
      // grammar matches, so all four asterisks appear. Same defect, and the
      // most natural selection of the three.
      final from = a < s ? a : s;
      final to = b > e ? b : e;
      return _at(t.replaceRange(from, to, ins), from + ins.length);
    }
    // Styled text survives. If both markers survived with it there is nothing
    // to repair — that is an ordinary edit inside a run.
    if (!openGone && !closeGone) continue;
    // Some of it survives and exactly one marker went with the selection.
    // Put the missing one back around what is left — on the OUTSIDE of
    // anything typed over the selection, so the new text joins the run.
    final marker =
        closeGone ? t.substring(innerEnd, e) : t.substring(s, innerStart);
    return closeGone
        ? _at(t.replaceRange(a, b, ins + marker), a + ins.length)
        : _at(t.replaceRange(a, b, marker + ins),
            a + marker.length + ins.length);
  }
  return null;
}

int _clamp(int v) => v < 0 ? 0 : v;

TextEditingValue _at(String text, int caret) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret),
      composing: TextRange.empty,
    );

// ─── Rule two: whitespace steps outside the marker ─────────────────────────

/// The relocated edit, or null when there is nothing to move.
///
/// Null is the answer for the overwhelming majority of keystrokes — anything
/// that is not whitespace arriving at the exact inside edge of a run that the
/// whitespace would break. Code spans come back null too, and deliberately:
/// `` `a ` `` has no flanking guard, so a space before its closing backtick is
/// legal Markdown and moving it would change what was written.
EdgeMove? relocateEdgeWhitespace(
    TextEditingValue oldValue, TextEditingValue newValue) {
  final sel = oldValue.selection;
  if (!sel.isValid || !sel.isCollapsed) return null;
  final at = sel.baseOffset;
  final old = oldValue.text;
  final next = newValue.text;
  if (at < 0 || at > old.length) return null;

  // A pure insertion at the caret, and nothing else. Anything that also
  // removed or replaced text is somebody else's edit.
  final grew = next.length - old.length;
  if (grew <= 0) return null;
  final ins = next.substring(at, at + grew);
  if (next.replaceRange(at, at + grew, '') != old) return null;
  // Space and tab only. A newline genuinely ends the paragraph the run is in,
  // and Enter is answered by the list engine before this ever sees it.
  if (!RegExp(r'^[ \t]+$').hasMatch(ins)) return null;
  final after = newValue.selection;
  if (!after.isValid || !after.isCollapsed || after.baseOffset != at + grew) {
    return null;
  }

  final lineStart = at == 0 ? 0 : old.lastIndexOf('\n', at - 1) + 1;
  final nl = old.indexOf('\n', at);
  final lineEnd = nl < 0 ? old.length : nl;

  final edge = _edgeOf(old, lineStart, lineEnd, at, ins, 0);
  if (edge == null) return null;
  return (
    value: _at(old.replaceRange(edge.to, edge.to, ins), edge.to + ins.length),
    carryOn: edge.carryOn,
  );
}

/// Where [ins] should have gone, and the marker to carry on with.
({int to, String? carryOn})? _edgeOf(
    String text, int from, int to, int at, String ins, int depth) {
  if (depth >= _maxDepth || from >= to) return null;
  final span = text.substring(from, to);
  for (final m in mdInlineRe.allMatches(span)) {
    final c = classifyInline(m);
    // No markers of its own means nothing to sit against: an atom reference,
    // a link, an equation. Their guards are elsewhere.
    if (c.openLen == 0 || c.closeLen == 0) continue;
    final start = from + m.start;
    final end = from + m.end;
    final innerStart = start + c.openLen;
    final innerEnd = end - c.closeLen;
    if (at < innerStart || at > innerEnd) continue;
    if (at != innerStart && at != innerEnd) {
      // Strictly inside, so this run is not the one breaking — but a nested
      // one might be. `**a *b* c**` is a single match at this level.
      return _edgeOf(text, innerStart, innerEnd, at, ins, depth + 1);
    }
    // Does it actually break? Asking rather than assuming is what keeps this
    // off code spans and off `~~`, `==` and `++`, none of which carry a
    // flanking guard and all of which hold a trailing space perfectly well.
    if (_survives(span, m.start, m.end, c.kind, at - from, ins)) return null;
    return at == innerEnd
        // Out of the back of the run, and the style carries on.
        ? (to: end, carryOn: text.substring(start, innerStart))
        // Out of the front. Nothing to carry: there is no run yet to continue.
        : (to: start, carryOn: null);
  }
  return null;
}

/// True when the same run, in the same place and of the same kind, survives
/// [ins] being put at [at] (both offsets relative to [span]).
bool _survives(
    String span, int start, int end, MdInline kind, int at, String ins) {
  final after = span.replaceRange(at, at, ins);
  for (final m in mdInlineRe.allMatches(after)) {
    if (m.start != start) continue;
    return classifyInline(m).kind == kind && m.end == end + ins.length;
  }
  return false;
}

// ─── Rule three: two runs with a space between them are one run ────────────

/// Fold the run holding the caret into an identical run just before it,
/// separated by nothing but whitespace. Null when there is no such pair.
///
/// This is what makes a style survive the space bar. Rule two steps the space
/// out of `**big**`, the re-armed queue wraps the next word as `**more**`, and
/// this folds `**big** **more**` into `**big more**` — one run, caret still
/// inside it, so everything after that is plain typing again.
///
/// It is also simply true: the two spellings render identically, so keeping
/// the tidier one costs nothing and stops a sentence accumulating a marker
/// pair per word.
TextEditingValue? mergeRunAtCaret(TextEditingValue v) {
  final sel = v.selection;
  if (!sel.isValid || !sel.isCollapsed) return null;
  final t = v.text;
  final at = sel.baseOffset;
  if (at < 0 || at > t.length) return null;

  final lineStart = at == 0 ? 0 : t.lastIndexOf('\n', at - 1) + 1;
  final nl = t.indexOf('\n', at);
  final lineEnd = nl < 0 ? t.length : nl;
  final span = t.substring(lineStart, lineEnd);

  final runs = [
    for (final m in mdInlineRe.allMatches(span))
      if (classifyInline(m) case final c when c.openLen > 0 && c.closeLen > 0)
        (m: m, c: c)
  ];
  for (var i = 1; i < runs.length; i++) {
    final second = runs[i];
    final first = runs[i - 1];
    if (second.c.kind != first.c.kind) continue;
    final s2 = lineStart + second.m.start;
    final e2 = lineStart + second.m.end;
    if (at < s2 + second.c.openLen || at > e2 - second.c.closeLen) continue;
    final e1 = lineStart + first.m.end;
    final gap = t.substring(e1, s2);
    if (gap.isEmpty || !RegExp(r'^[ \t]+$').hasMatch(gap)) continue;
    final open = t.substring(lineStart + first.m.start,
        lineStart + first.m.start + first.c.openLen);
    // Same kind is not the same spelling: `**a** __b__ ` are both bold and
    // folding them would rewrite one of them into the other's marks.
    if (t.substring(s2, s2 + second.c.openLen) != open) continue;
    final close1 = e1 - first.c.closeLen;
    final merged = t.substring(0, close1) +
        gap +
        t.substring(s2 + second.c.openLen, t.length);
    // Both removed markers sit before the caret, which is inside the second
    // run's text by the test above.
    return _at(merged, at - first.c.closeLen - second.c.openLen);
  }
  return null;
}

// ─── The three of them, as the field sees them ─────────────────────────────

class EmphasisGuardFormatter extends TextInputFormatter {
  const EmphasisGuardFormatter(this.app, this.blockId);

  /// Only for re-arming the style queue when whitespace steps out of the back
  /// of a run — see [AppState.carryStyleOn].
  final AppState app;
  final String blockId;

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final healed = healOrphanedMarkers(oldValue, newValue);
    if (healed != null) return healed;

    final moved = relocateEdgeWhitespace(oldValue, newValue);
    if (moved != null) {
      final carry = moved.carryOn;
      if (carry != null) {
        app.carryStyleOn({carry},
            blockId: blockId, at: moved.value.selection.baseOffset);
      }
      return moved.value;
    }

    return mergeRunAtCaret(newValue) ?? newValue;
  }
}
