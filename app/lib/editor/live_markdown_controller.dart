import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../markdown/md_render.dart' show indentPx, kBulletGutter, subSupStyle;
import '../markdown/md_syntax.dart';
import 'inline_math_editor.dart';
import '../theme/onote_theme.dart';
import '../study/flashcards.dart' show inlineCardRe;
import '../theme/tokens.dart';
import 'flashcard_view.dart';

export 'wrap_selection.dart' show WrapSelectionFormatter;

/// The horizontal room `RenderEditable` keeps for the caret and takes off the
/// width it lays the paragraph out at (`_kCaretGap` 1.0 + the default
/// `cursorWidth` 2.0). Anyone predicting where the field will wrap has to
/// subtract it: laying out at the field's full width predicted the wrong line
/// breaks for this block — `- alpha bravo charlie …` in a 200px box breaks at
/// offsets 14/22/33/46 in the field and 14/28/41 at 200px flat.
const double kEditorCaretMargin = 3.0;

/// A [TextEditingController] that renders Markdown **as you type** (TEXT-2/4):
/// the moment a construct closes (e.g. the second `*` of `**bold**`) the text
/// styles and its markers collapse away — **and stay away**. The caret moving
/// back into a styled run no longer reveals its markers.
///
/// That is a deliberate change of character, from "live Markdown" towards
/// "rich text that happens to save as Markdown", and it is what the product
/// owner asked for: "if they click on a bold word and suddenly **** appears
/// around it, this will be quite offputting" — most people taking notes have
/// never heard of Markdown. Three things carry the consequences:
///
/// * **Removing formatting** is `AppState.wrapSelection` (Ctrl+B and the
///   toolbar), which already toggles a run off from a bare caret inside it.
///   That is the word-processor model and it is now the only route, because
///   there are no markers left to delete by hand.
/// * **Caret arithmetic is untouched**, and that is the whole reason this is
///   safe: a hidden marker is still laid out, at 0.01px, so every character of
///   the buffer still occupies exactly one position in the paragraph. Visible
///   and source offsets have never diverged and still do not. What hiding
///   *does* cost is dead keystrokes — arrowing across an invisible `**` looked
///   like the caret had stopped — so [_snapOutOfHiddenMarkers] steps the caret
///   over a marker run in whichever direction it was already travelling.
/// * **Editing at the edges** would otherwise leave half a marker behind
///   (Backspace after `**bold**` used to produce `**bold*`, which un-bolds the
///   word and prints two asterisks). [markerAwareDelete] answers that.
///
/// The raw text buffer is unchanged — only the *rendering* transforms — so the
/// stored Markdown stays exactly what the user typed. Every code path is
/// guarded by a coverage check: if span-building ever fails to reproduce the
/// text verbatim, it falls back to an unstyled span, so editing can never
/// corrupt or desync.
class LiveMarkdownController extends TextEditingController {
  LiveMarkdownController({super.text, required this.dark});
  bool dark;

  /// Resolves an in-flow image reference (`sha256:<hash>`) to bytes, so the
  /// picture is shown WHILE the block is being edited and not only after the
  /// caret leaves it. Null, or a reference this cannot resolve, falls back to
  /// the dimmed source text — which is all this editor used to do.
  Uint8List? Function(String src)? imageResolver;

  /// Called after the controller has rewritten its own text, which an image
  /// resize and an inline-equation edit both do. A programmatic edit never
  /// fires `TextField.onChanged`, so without this the change would draw
  /// correctly and then never be saved.
  VoidCallback? onSelfEdit;

  /// A student clicked an equation sitting in a sentence. Offsets are into the
  /// buffer and cover the whole `$…$`; the rect is in global coordinates, for
  /// anchoring the editor. Null leaves inline equations as plain drawings,
  /// which is what a read-only surface wants.
  void Function(int start, int end, String latex, Rect anchor)? onMathTap;

  /// The buffer offset of the opening dollar of the equation being edited IN
  /// PLACE, or null when none is. While set, the math branch of
  /// [buildTextSpan] mounts [mathEditorBuilder] instead of the read-only atom,
  /// so the equation is edited exactly where it sits in the sentence
  /// (v0.20 §B.2).
  int? editingMathAt;

  /// Builds the live equation editor for the span at [editingMathAt]. Owned
  /// by the session — the SPAN is rebuilt on every keystroke, so nothing that
  /// must survive one may live in the widget this returns.
  Widget Function(String latex, TextStyle base)? mathEditorBuilder;

  /// Rebuild the span tree without a text change. Entering and leaving
  /// in-place equation editing changes what the span SHOWS, not what the
  /// buffer HOLDS, and nothing else tells the field to re-ask for spans.
  void refreshSpans() => notifyListeners();

  /// The `\$…\$` (or bare `\$\$`) whose SOURCE range contains [offset],
  /// edges included — or null. `start` is the opening dollar, `end` one past
  /// the closing one, `inner` the LaTeX between. The session's caret-crossing
  /// and Backspace-at-the-edge rules are built on this.
  ({int start, int end, String inner})? mathRunNear(int offset) {
    for (final r in _runs()) {
      if (r.kind != MdRunKind.math) continue;
      final s = r.start - 1; // the run records the HIDDEN remainder
      if (offset >= s && offset <= r.end) {
        // The inner sheds however many dollars wrap it — one for $x$, two
        // for the display form — so what reaches MathEditor.open is LaTeX,
        // never delimiters. An inner cannot itself contain a dollar (the
        // grammar forbids it), so trimming is exact.
        final full = text.substring(s, r.end);
        var a = 0, b = full.length;
        while (a < b && full.codeUnitAt(a) == 0x24) {
          a++;
        }
        while (b > a && full.codeUnitAt(b - 1) == 0x24) {
          b--;
        }
        return (start: s, end: r.end, inner: full.substring(a, b).trim());
      }
    }
    return null;
  }

  /// Replace the `$…$` at [start]..[end] with [latex], or remove it when
  /// [latex] is empty. Used by the inline equation editor, which cannot go
  /// through the field: the field never sees a keystroke aimed at a
  /// `WidgetSpan`.
  void replaceMathAt(int start, int end, String latex,
      {bool keepEmptyPair = false, int? caretAt, int dollars = 1}) {
    // `start == end` is LEGITIMATE: it means the equation is currently
    // zero-length, which is exactly what happens the moment a student clears
    // the card to retype. Rejecting it left the caller's idea of where the
    // equation was running ahead of the buffer, so the next keystroke wrote
    // over the words AFTER the equation instead of replacing it — reported as
    // "emptying an inline equation then typing again eats the words after it".
    // Only a genuinely inverted or out-of-range span is refused.
    if (start < 0 || end > text.length || start > end) return;
    final tidy = latex.trim();
    // [keepEmptyPair]: while the equation is being edited IN PLACE, an
    // emptied one must stay `$$` — removing the dollars would unmount the
    // very editor the student is typing into. The pair is swept on close.
    final wrap = r'$' * dollars;
    final next = tidy.isEmpty
        ? (keepEmptyPair ? '\$\$' : '')
        : '${wrap}${tidy}${wrap}';
    value = TextEditingValue(
      text: text.replaceRange(start, end, next),
      selection: TextSelection.collapsed(offset: caretAt ?? (start + next.length)),
      composing: TextRange.empty,
    );
    onSelfEdit?.call();
  }

  /// Ask the host to widen the block by [extra] logical pixels — see
  /// `OnoteEditSession.requestExtraWidth`. Null means the box cannot grow, and
  /// a picture then clamps to it exactly as it did before.
  void Function(double extra)? requestExtraWidth;

  /// Resolved blobs, so a repaint per keystroke is not a SQLite read per
  /// keystroke. A miss is never cached: the bytes may still be arriving from a
  /// sync, and a notebook the user never leaves would remember the gap forever.
  final Map<String, Uint8List> _blobCache = {};

  Uint8List? _resolveImage(String src) {
    final hit = _blobCache[src];
    if (hit != null) return hit;
    final bytes = imageResolver?.call(src);
    if (bytes != null) _blobCache[src] = bytes;
    return bytes;
  }

  /// Rewrite the ` =WxH` suffix of the image reference occupying
  /// [lineStart]..[lineEnd]. [was] is the line as it read when the drag began.
  ///
  /// The offsets are captured at span-build time and used at drag-end, so they
  /// can be stale — another block's save, an undo, a paste. Rather than trust
  /// them, this re-reads the range and does nothing at all unless it still
  /// holds the same line. A resize that quietly lands on the wrong text would
  /// be a corruption; a resize that quietly does nothing is a lost drag.
  void resizeImageLine(
      int lineStart, int lineEnd, String was, double w, double h) {
    if (lineStart < 0 || lineEnd > text.length || lineStart > lineEnd) return;
    if (text.substring(lineStart, lineEnd) != was) return;
    final m = _imageLineRe.firstMatch(was);
    if (m == null) return;
    final next = '${m.group(1)}![${m.group(2)}](${m.group(3)} '
        '=${w.round()}x${h.round()})';
    if (next == was) return;

    final delta = next.length - was.length;
    int adj(int o) => o <= lineStart
        ? o
        : (o >= lineEnd ? o + delta : lineStart + next.length);
    final sel = selection;
    value = TextEditingValue(
      text: text.replaceRange(lineStart, lineEnd, next),
      selection: sel.isValid
          ? TextSelection(
              baseOffset: adj(sel.baseOffset), extentOffset: adj(sel.extentOffset))
          : sel,
      composing: TextRange.empty,
    );
    onSelfEdit?.call();
  }

  /// Rewrite the card occupying [lineStart]..[lineEnd] with a new front and
  /// back.
  ///
  /// The same shape as [resizeImageLine], and for the same reason: the offsets
  /// are captured when the span is built and used when the dialog closes, so
  /// they can be stale. The range is re-read and nothing happens at all unless
  /// it still holds the line we started from — an edit that quietly lands on
  /// the wrong text would be a corruption.
  void replaceCardLine(
      int lineStart, int lineEnd, String was, String front, String back) {
    if (lineStart < 0 || lineEnd > text.length || lineStart > lineEnd) return;
    if (text.substring(lineStart, lineEnd) != was) return;
    // The delimiters are what make the line a card, so they cannot appear
    // inside it. Stripping beats refusing: the user typed a bracket, not a
    // syntax error, and losing one character is better than losing the card.
    String clean(String v) => v
        .replaceAll(RegExp(r'[\[\]()\r\n]'), ' ')
        // Collapse the gaps the stripping leaves, or `f(x) [sic]` comes back
        // as `f x   sic` — technically intact and visibly mangled.
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final next = '?[${clean(front)}](${clean(back)})';
    if (next == was) return;

    final delta = next.length - was.length;
    int adj(int o) => o <= lineStart
        ? o
        : (o >= lineEnd ? o + delta : lineStart + next.length);
    final sel = selection;
    value = TextEditingValue(
      text: text.replaceRange(lineStart, lineEnd, next),
      selection: sel.isValid
          ? TextSelection(
              baseOffset: adj(sel.baseOffset),
              extentOffset: adj(sel.extentOffset))
          : sel,
      composing: TextRange.empty,
    );
    onSelfEdit?.call();
  }

  // The inline grammar lives in markdown/md_syntax.dart, shared with the read
  // renderer. `#{1,3}`, not `#{1,6}`: the reader draws three levels, so a
  // fourth hash used to look like a heading while typing and print its hashes
  // when read.
  static final _inlineRe = mdInlineRe;
  static final _headingRe = mdHeadingRe;

  /// The same line shapes md_render gives extra vertical room to — kept
  /// textually in step with `_reCheckbox` / `_reQuote` there.
  static final _checkboxLineRe = RegExp(r'^([ 	]*)[-*+] \[( |x|X)\]');
  static final _quoteLineRe = RegExp(r'^>\s?');

  /// A whole line that is nothing but an image reference — the in-flow form
  /// (Data Model §5.1). Line-anchored to match the renderer exactly, so what
  /// the editor draws is precisely what read mode turns into a picture.
  /// Groups: 1 indent, 2 alt, 3 src, 4 width, 5 height.
  static final _imageLineRe =
      RegExp(r'^(\s*)!\[([^\]]*)\]\(([^)\s]+)(?:\s+=(\d+)x(\d+))?\)\s*$');
  // Every marker the reader honours — `+` and `1)` were missing, so those
  // lines were styled as prose while typing and as lists when read.
  // The gap is `[ \t]+`, matching the shared line grammar. Demanding exactly
  // ONE space made a tab-gapped or double-spaced list line prose to the
  // editor and a list to the reader and to the key engine — so it still
  // jumped sideways on click-in, and Enter continued a list the editor did
  // not believe existed.
  static final _prefixRe = RegExp(
      r'^([ \t]*)([-*+] \[[ xX]\][ \t]+|[-*+][ \t]+|\d{1,9}[.)][ \t]+|>[ \t]?)');

  /// The width the field lays its paragraph out at, or null while it is not
  /// known. Set by the engine from the field's own constraints, less
  /// [kEditorCaretMargin]; null simply turns the hanging indent off, which is
  /// exactly how this file behaved before it existed.
  double? layoutWidth;

  // ── Inline runs, scanned once per text ───────────────────────────────────
  //
  // The same scan [_inline] performs, hoisted so the caret logic and the
  // deletion helper agree with the renderer by construction rather than by
  // inspection. `live_hidden_markers_test.dart` cross-checks the ranges this
  // returns against the spans `buildTextSpan` actually draws at a hairline, so
  // the two cannot drift apart unnoticed.
  String? _runsFor;
  List<_MdRun>? _runsCache;

  /// Every inline construct whose markers this controller HIDES, in source
  /// offsets. Links, bare URLs and `$math$` are excluded because [_inline]
  /// deliberately leaves those legible (`openLen = closeLen = 0`).
  List<_MdRun> _runs([String? of]) {
    final t = of ?? text;
    if (_runsFor == t) return _runsCache!;
    final out = <_MdRun>[];
    var pos = 0;
    for (final line in t.split('\n')) {
      _lineRuns(line, pos, out);
      pos += line.length + 1;
    }
    _runsFor = t;
    return _runsCache = out;
  }

  /// The source ranges the user cannot see: the marker characters of every
  /// styled run. Public so `live_hidden_markers_test.dart` can hold it against
  /// the spans [buildTextSpan] actually draws at a hairline — the caret logic
  /// and the renderer have to agree about what is invisible, and the only way
  /// to keep two scans of the same grammar honest is to compare them.
  List<TextRange> hiddenMarkerRanges([String? of]) => [
        for (final r in _runs(of)) ...[
          if (r.openLen > 0)
            TextRange(start: r.start, end: r.start + r.openLen),
          if (r.closeLen > 0) TextRange(start: r.end - r.closeLen, end: r.end),
        ]
      ];

  static void _lineRuns(String line, int lineStart, List<_MdRun> out) {
    if (line.isEmpty) return;
    // Whole-line constructs are drawn as one object with the rest of the
    // source trailing hidden; they have no inline runs of their own.
    if (inlineCardRe.hasMatch(line)) return;
    if (_imageLineRe.hasMatch(line)) return;
    var from = 0;
    final h = _headingRe.firstMatch(line);
    if (h != null) {
      from = h.end;
    } else if (!mdDividerRe.hasMatch(line)) {
      final p = _prefixRe.firstMatch(line);
      if (p != null) from = p.end;
    }
    final sub = line.substring(from);
    final regionStart = lineStart + from;
    for (final m in _inlineRe.allMatches(sub)) {
      final c = classifyInline(m);
      // An inline equation is drawn as ONE object, so everything after the
      // code unit it stands on — `frac{1}{2}$` and all — is invisible. The
      // caret has to cross the whole of it in one step, or a student pressing
      // Left inside their own sentence gets twelve dead keystrokes. Recorded
      // as a single hidden span from just after the object to the end.
      if (c.kind == MdInline.math ||
          c.kind == MdInline.mathDisplay ||
          c.kind == MdInline.mathPadded ||
          c.kind == MdInline.mathEmpty) {
        out.add((
          start: regionStart + m.start + 1,
          end: regionStart + m.end,
          openLen: m.end - m.start - 1,
          closeLen: 0,
          kind: MdRunKind.math,
        ));
        continue;
      }
      // Exactly the kinds [_inline] zeroes: their source stays legible, so
      // there is nothing hidden for the caret to trip over.
      switch (c.kind) {
        case MdInline.wikiLink:
        case MdInline.extLink:
        case MdInline.bareUrl:
          continue;
        default:
      }
      if (c.openLen <= 0 && c.closeLen <= 0) continue;
      out.add((
        start: regionStart + m.start,
        end: regionStart + m.end,
        openLen: c.openLen,
        closeLen: c.closeLen,
        kind: MdRunKind.marker,
      ));
    }
  }

  @override
  set value(TextEditingValue newValue) {
    super.value = _snapOutOfHiddenMarkers(newValue);
  }

  /// Step a caret that has landed *between* the characters of an invisible
  /// marker out to the near edge, in the direction it was already moving.
  ///
  /// Without this, hiding the markers turned arrow keys into dead keystrokes:
  /// Left from the end of `**bold**` moved the caret from 8 to 7 to 6 with no
  /// visible change, because those two `*` are laid out at 0.01px. Two presses
  /// that appear to do nothing is exactly the kind of thing the owner's
  /// complaint was about.
  ///
  /// Only a MOVE is snapped, never an edit: after a keystroke the caret has to
  /// stay precisely where the edit put it, or a half-typed `**bold*` would
  /// have its caret yanked somewhere the next character does not belong.
  TextEditingValue _snapOutOfHiddenMarkers(TextEditingValue next) {
    final sel = next.selection;
    final old = value;
    if (!sel.isValid || !old.selection.isValid) return next;
    if (old.text != next.text) return next;
    final rs = _runs(next.text);
    if (rs.isEmpty) return next;

    int fix(int off, int from) {
      if (from == off) return off;
      for (final r in rs) {
        for (final edge in [
          (r.start, r.start + r.openLen),
          (r.end - r.closeLen, r.end),
        ]) {
          if (off > edge.$1 && off < edge.$2) {
            return from < off ? edge.$2 : edge.$1;
          }
        }
      }
      return off;
    }

    final base = fix(sel.baseOffset, old.selection.baseOffset);
    final extent = fix(sel.extentOffset, old.selection.extentOffset);
    if (base == sel.baseOffset && extent == sel.extentOffset) return next;
    return next.copyWith(
        selection: TextSelection(
            baseOffset: base,
            extentOffset: extent,
            affinity: sel.affinity,
            isDirectional: sel.isDirectional));
  }

  /// Backspace or Delete at the edge of a run whose markers cannot be seen.
  /// Returns null when the platform's own behaviour is already right.
  ///
  /// With the markers visible this needed no help — you could see the `*` you
  /// were about to delete. With them hidden, the default is actively wrong in
  /// three ways, and each one is a reported-class bug waiting to happen:
  ///
  /// * Backspace with the caret just past `**bold**` deleted the last `*`,
  ///   leaving `**bold*`: the word silently un-bolds AND two asterisks appear.
  ///   It deletes the last *visible* character instead — the `d`.
  /// * Backspace with the caret at the start of the word (just inside the
  ///   invisible `**`) ate the second `*`, same damage. It deletes the
  ///   character before the whole run instead, which is what "backspace at the
  ///   start of a word" means in every word processor.
  /// * Emptying a run left `****` behind — four visible asterisks that no
  ///   renderer matches. Deleting the last character of the inner text now
  ///   takes the markers with it.
  ///
  /// Delete (forward) is the mirror of all three.
  TextEditingValue? markerAwareDelete(TextEditingValue v,
      {required bool forward}) {
    final sel = v.selection;
    if (!sel.isValid || !sel.isCollapsed) return null;
    final at = sel.baseOffset;
    final t = v.text;
    for (final r in _runs(t)) {
      final innerStart = r.start + r.openLen;
      final innerEnd = r.end - r.closeLen;
      if (innerEnd <= innerStart) continue;
      // A one-character inner run cannot survive the deletion, so the markers
      // go with it rather than being left as literal asterisks.
      final lastOne = _prevBoundary(t, innerEnd) <= innerStart;
      if (!forward) {
        if (at == r.end) {
          return lastOne
              ? _spliced(v, r.start, r.end)
              : _spliced(v, _prevBoundary(t, innerEnd), innerEnd);
        }
        if (at == innerEnd && lastOne) return _spliced(v, r.start, r.end);
        if (at == innerStart) {
          if (r.start == 0) return null;
          return _spliced(v, _prevBoundary(t, r.start), r.start);
        }
      } else {
        if (at == r.start) {
          return lastOne
              ? _spliced(v, r.start, r.end)
              : _spliced(v, innerStart, _nextBoundary(t, innerStart), keep: at);
        }
        if (at == innerStart && lastOne) return _spliced(v, r.start, r.end);
        if (at == innerEnd) {
          if (r.end >= t.length) return null;
          return _spliced(v, r.end, _nextBoundary(t, r.end), keep: at);
        }
      }
    }
    return null;
  }

  /// Surrogate-pair-safe neighbours: `**bold🙂**` must not lose half an emoji.
  static int _prevBoundary(String t, int at) {
    if (at <= 0) return 0;
    final i = at - 1;
    if (i > 0 && t.codeUnitAt(i) >= 0xDC00 && t.codeUnitAt(i) <= 0xDFFF) {
      return i - 1;
    }
    return i;
  }

  static int _nextBoundary(String t, int at) {
    if (at >= t.length) return t.length;
    final i = at + 1;
    final c = t.codeUnitAt(at);
    if (c >= 0xD800 && c <= 0xDBFF && i < t.length) return i + 1;
    return i;
  }

  static TextEditingValue _spliced(TextEditingValue v, int from, int to,
          {int? keep}) =>
      TextEditingValue(
        text: v.text.replaceRange(from, to, ''),
        selection: TextSelection.collapsed(offset: keep ?? from),
        composing: TextRange.empty,
      );

  @override
  TextSpan buildTextSpan(
      {required BuildContext context,
      TextStyle? style,
      required bool withComposing}) {
    final base = style ?? const TextStyle();
    final full = text;

    // Don't interfere with IME composition — render raw while composing.
    if (withComposing && value.composing.isValid && !value.composing.isCollapsed) {
      return TextSpan(text: full, style: base);
    }

    final lo = selection.isValid ? math.min(selection.baseOffset, selection.extentOffset) : -1;
    final hi = selection.isValid ? math.max(selection.baseOffset, selection.extentOffset) : -1;

    try {
      final children = <InlineSpan>[];
      var pos = 0;
      final lines = full.split('\n');
      for (var i = 0; i < lines.length; i++) {
        _buildLine(lines[i], pos, base, lo, hi, children);
        pos += lines[i].length;
        if (i < lines.length - 1) {
          children.add(const TextSpan(text: '\n'));
          pos += 1;
        }
      }
      final root = TextSpan(style: base, children: children);
      // Safety net: verify exact text coverage.
      final buf = StringBuffer();
      void collect(InlineSpan s) {
        // A placeholder is asked what source text it stands for, so a picture
        // drawn in place of its reference is still proven — character for
        // character — to be the reference and nothing else.
        if (s is _SourceSpan) {
          buf.write(s.source);
        } else if (s is TextSpan) {
          if (s.text != null) buf.write(s.text);
          final ch = s.children;
          if (ch != null) ch.forEach(collect);
        }
      }

      collect(root);
      if (buf.toString() == full) {
        final done =
            misspellings.isEmpty ? root : _underlineMisspellings(root, lo, hi);
        return _hangWrappedListLines(done, full, base);
      }
    } catch (_) {/* fall through */}
    return TextSpan(text: full, style: base);
  }

  /// Misspelled ranges, in raw-text offsets. Set by the editing session; see
  /// `spell/spell_checker.dart` for why the underlines are merged here rather
  /// than through Flutter's own spell-check pipeline.
  List<TextRange> _misspellings = const [];
  List<TextRange> get misspellings => _misspellings;
  set misspellings(List<TextRange> v) {
    if (identical(v, _misspellings)) return;
    _misspellings = v;
    notifyListeners();
  }

  static const _misspellingStyle = TextStyle(
    decoration: TextDecoration.underline,
    decorationStyle: TextDecorationStyle.wavy,
    decorationColor: Color(0xFFD23B3B),
  );

  /// Re-split the finished span tree at misspelling boundaries and merge the
  /// wavy underline in.
  ///
  /// Deliberately a post-pass over the completed tree rather than a change to
  /// the line builder: it consumes and re-emits exactly the same characters in
  /// the same order, so the coverage invariant checked above cannot be broken
  /// by a boundary bug — the worst case is a wrongly-placed underline, never
  /// corrupted text.
  TextSpan _underlineMisspellings(TextSpan root, int caretLo, int caretHi) {
    // A word being typed must not flash red mid-word, so the range under the
    // caret is left alone until the caret leaves it.
    final ranges = [
      for (final r in _misspellings)
        if (!(caretLo >= r.start && caretHi <= r.end)) r
    ];
    if (ranges.isEmpty) return root;

    var offset = 0;
    InlineSpan walk(InlineSpan span) {
      // Placeholders pass through untouched — but their SOURCE length still
      // has to be counted, or every misspelling after a picture would be
      // underlined some characters to the left of the word it belongs to.
      // (Filtering these out instead, which is what this did, deleted the
      // picture from the tree the moment the block contained a typo.)
      if (span is _SourceSpan) {
        offset += span.source.length;
        return span;
      }
      if (span is! TextSpan) return span;
      final text = span.text;
      final children = span.children;
      if (text == null) {
        return TextSpan(
          style: span.style,
          children: children?.map(walk).toList(),
        );
      }
      final start = offset;
      offset += text.length;
      // Hidden marker spans render at 0.1px — an underline there is noise.
      final hidden = (span.style?.fontSize ?? 99) <= 1;
      final overlapping = hidden
          ? const <TextRange>[]
          : [
              for (final r in ranges)
                if (r.start < start + text.length && r.end > start) r
            ];
      if (overlapping.isEmpty) {
        return TextSpan(
            text: text,
            style: span.style,
            children: children?.map(walk).toList());
      }
      // Cut points inside this span, in order.
      final cuts = <int>{0, text.length};
      for (final r in overlapping) {
        cuts.add((r.start - start).clamp(0, text.length));
        cuts.add((r.end - start).clamp(0, text.length));
      }
      final points = cuts.toList()..sort();
      final pieces = <InlineSpan>[];
      for (var i = 0; i < points.length - 1; i++) {
        final a = points[i], b = points[i + 1];
        if (a == b) continue;
        final bad = overlapping
            .any((r) => r.start <= start + a && r.end >= start + b);
        pieces.add(TextSpan(
          text: text.substring(a, b),
          style: bad
              ? (span.style ?? const TextStyle()).merge(_misspellingStyle)
              : span.style,
        ));
      }
      return TextSpan(
        style: span.style,
        children: [...pieces, ...?children?.map(walk)],
      );
    }

    return walk(root) as TextSpan;
  }

  // ── Hanging indent for WRAPPED list lines ────────────────────────────────
  //
  // "if i have a dotpoint that goes over multiple lines when its in view mode
  // it renders properly where both lines start at the same indent, however
  // when editing the second (and further) lines push all the way left to the
  // edge of the box, this shouldnt happen."
  //
  // The read renderer gets this free: a list line there is a Row of
  // [gutter, Expanded(Text)], so every wrapped line lands on the body indent.
  // The editor is ONE paragraph inside one TextField, and Flutter has no
  // per-paragraph hanging indent — `dart:ui`'s ParagraphStyle carries no
  // text-indent at all, and a leading span per wrapped line is impossible
  // because nobody knows where the wraps are until after layout.
  //
  // So the wraps are worked out first, and then made to hang with two moves
  // per wrapped line. Both matter, and the first one alone does NOT work:
  //
  //  1. The SPACE the line wrapped on becomes a `hang`-wide empty box. A
  //     WidgetSpan is exactly one code unit — the same trick the bullet gutter
  //     and the in-flow picture already use — so the paragraph keeps precisely
  //     as many code units as the buffer and not one caret offset moves.
  //  2. The last character of the PREVIOUS line gets extra trailing letter
  //     spacing, sized so that box can no longer fit at the end of that line.
  //
  // Without (2) the box simply sits in the slack at the end of the previous
  // line and nothing is indented. That was measured, not guessed: standing the
  // wrapped line's first CHARACTER in a `hang + charWidth` box — the obvious
  // approach — produced line starts of 14/23/34/46 where the true wraps were
  // 14/22/33/46, i.e. every box but the first was dragged back onto the line
  // above, taking one letter of the following word with it and leaving a 22px
  // hole before it. An object is a break opportunity like any other; the only
  // way to keep it off the previous line is to leave it no room there.
  //
  // The padding in (2) is invisible: it is trailing advance on the last
  // character of a line, with nothing drawn after it, and it is sized to leave
  // the line exactly `hang - 0.5` px short of full, so it can never push that
  // line's last word onto the next one.
  //
  // Everything is verified against a real layout before it is drawn — an
  // indent in the middle of a sentence is far worse than no indent — and any
  // item that cannot be made to hang cleanly (a word longer than the whole
  // line, so it wraps mid-word with no space to stand a box on) is left
  // exactly as it was rather than being half-done.

  /// One item's plan: which spaces become gutters, and which characters carry
  /// the trailing padding that keeps those gutters off the line above.
  static const double _kHangEpsilon = 0.5;

  TextSpan _hangWrappedListLines(TextSpan root, String full, TextStyle base) {
    final width = layoutWidth;
    if (width == null || width <= 0) return root;

    final bodies = <_ListBody>[];
    var pos = 0;
    for (final line in full.split('\n')) {
      final p = mdDividerRe.hasMatch(line) ? null : _prefixRe.firstMatch(line);
      if (p != null && _markerGlyph(p.group(2)!) != null) {
        final hang = math.max(
            indentPx(p.group(1)!.length, base.fontSize), kBulletGutter);
        // A gutter that leaves no room for words would wrap one character per
        // line. Better to leave a very narrow box flush than unreadable.
        if (width - hang >= 48) {
          bodies.add((from: pos + p.end, to: pos + line.length, hang: hang));
        }
      }
      pos += line.length + 1;
    }
    if (bodies.isEmpty) return root;

    // One layout to find out whether anything wraps at all. The overwhelmingly
    // common block has no wrapped list line, and this is the only measurement
    // it pays for.
    final plain = _dimensioned(root, base);
    final firstPass = _visualLineStarts(root, plain, width).toSet();

    final gutters = <int, double>{};
    final pads = <int, double>{};
    for (final b in bodies) {
      if (!firstPass.any((s) => s > b.from && s <= b.to)) continue;
      _planItem(root, full, b, width, base, gutters, pads);
    }
    if (gutters.isEmpty) return root;

    // Verify against a real layout, and keep only what actually hangs. An
    // item whose gutter did not land at the start of a visual line is dropped
    // whole, so a bullet is never half-indented.
    for (var pass = 0; pass < 3 && gutters.isNotEmpty; pass++) {
      final built = _applyHangs(root, gutters, pads, base);
      final starts = _visualLineStarts(built.tree, built.dims, width).toSet();
      final bad = gutters.keys.where((g) => !starts.contains(g)).toSet();
      if (bad.isEmpty) return built.tree;
      for (final b in bodies) {
        if (bad.any((g) => g > b.from && g <= b.to)) {
          gutters.removeWhere((g, _) => g > b.from && g <= b.to);
          pads.removeWhere((k, _) => k >= b.from && k <= b.to);
        }
      }
    }
    return root;
  }

  /// Work out one list item's gutters and padding, or leave [gutters] and
  /// [pads] untouched if it cannot hang cleanly.
  void _planItem(TextSpan root, String full, _ListBody b, double width,
      TextStyle base, Map<int, double> gutters, Map<int, double> pads) {
    final avail = width - b.hang;
    final part = _slice(root, b.from, b.to, base);
    final tp = TextPainter(
        text: part.tree, textDirection: TextDirection.ltr, maxLines: null)
      ..setPlaceholderDimensions(part.dims)
      ..layout(maxWidth: avail);
    final starts = <int>[];
    for (final m in tp.computeLineMetrics()) {
      final y = math.max(0.0, m.baseline - 1);
      starts.add(tp.getLineBoundary(tp.getPositionForOffset(Offset(0, y))).start);
    }

    final myGutters = <int, double>{};
    final myPads = <int, double>{};
    for (var i = 1; i < starts.length; i++) {
      final at = b.from + starts[i]; // source offset of the wrapped line
      // The line has to have wrapped ON a space, or there is nothing to stand
      // the gutter box on. A word longer than the line breaks mid-word; that
      // item keeps today's flush-left behaviour rather than half of one.
      if (at - 1 < b.from || full[at - 1] != ' ') {
        tp.dispose();
        return;
      }
      // The last character with ink on the line above, and where it ends.
      var q = at - 2;
      while (q >= b.from && full[q] == ' ') {
        q--;
      }
      if (q < b.from) {
        tp.dispose();
        return;
      }
      final boxes = tp.getBoxesForSelection(
          TextSelection(baseOffset: q - b.from, extentOffset: q - b.from + 1));
      if (boxes.isEmpty) {
        tp.dispose();
        return;
      }
      final endX = boxes.last.right;
      // Leave the line too full for a `hang`-wide box, and no fuller: the
      // padding is trailing advance, so a line padded to `avail - hang + ε`
      // still holds every word it held before.
      final pad = avail - b.hang - endX + _kHangEpsilon;
      if (pad > 0) myPads[q] = pad;
      myGutters[at - 1] = b.hang;
    }
    tp.dispose();
    gutters.addAll(myGutters);
    pads.addAll(myPads);
  }

  /// Placeholder sizes for a tree with nothing injected.
  List<PlaceholderDimensions> _dimensioned(TextSpan root, TextStyle base) {
    final dims = <PlaceholderDimensions>[];
    final fs = base.fontSize ?? 14;
    void walk(InlineSpan s) {
      if (s is _SourceSpan) {
        dims.add(_dimOf(s, fs));
        return;
      }
      if (s is TextSpan) s.children?.forEach(walk);
    }

    walk(root);
    return dims;
  }

  static PlaceholderDimensions _dimOf(_SourceSpan s, double fs) =>
      PlaceholderDimensions(
        // Only the WIDTH steers line breaking; height and baseline move a line
        // box up and down and cannot change where it breaks, so a nominal
        // height here costs the prediction nothing.
        size: Size(s.width ?? 0, fs),
        alignment: s.alignment,
        baseline: s.baseline,
        baselineOffset: fs * 0.8,
      );

  /// Rebuild [root] with a gutter box at each offset in [gutters] and extra
  /// trailing advance on each character in [pads].
  ///
  /// Deliberately a post-pass over the finished tree, exactly like
  /// [_underlineMisspellings] and for the same reason: it consumes and re-emits
  /// the same characters in the same order, so the coverage invariant cannot be
  /// broken by a boundary bug here.
  ({TextSpan tree, List<PlaceholderDimensions> dims}) _applyHangs(
      TextSpan root,
      Map<int, double> gutters,
      Map<int, double> pads,
      TextStyle base) {
    final dims = <PlaceholderDimensions>[];
    final fs = base.fontSize ?? 14;
    var off = 0;

    InlineSpan walk(InlineSpan span) {
      if (span is _SourceSpan) {
        dims.add(_dimOf(span, fs));
        off += span.source.length;
        return span;
      }
      if (span is! TextSpan) return span;
      final t = span.text;
      final kids = span.children;
      if (t == null) {
        return TextSpan(style: span.style, children: kids?.map(walk).toList());
      }
      final start = off;
      off += t.length;
      final hits = <int>{
        for (final g in gutters.keys)
          if (g >= start && g < start + t.length) g,
        for (final p in pads.keys)
          if (p >= start && p < start + t.length) p,
      }.toList()
        ..sort();
      if (hits.isEmpty) {
        return TextSpan(
            text: t, style: span.style, children: kids?.map(walk).toList());
      }
      final pieces = <InlineSpan>[];
      var cut = 0;
      for (final a in hits) {
        final i = a - start;
        if (i > cut) {
          pieces.add(TextSpan(text: t.substring(cut, i), style: span.style));
        }
        final st = span.style ?? base;
        if (gutters.containsKey(a)) {
          final sp = _SourceSpan(
            source: t.substring(i, i + 1),
            width: gutters[a],
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: SizedBox(width: gutters[a], height: fs),
          );
          dims.add(_dimOf(sp, fs));
          pieces.add(sp);
        } else {
          pieces.add(TextSpan(
              text: t.substring(i, i + 1),
              style: st.copyWith(
                  letterSpacing: (st.letterSpacing ?? 0) + pads[a]!)));
        }
        cut = i + 1;
      }
      if (cut < t.length) {
        pieces.add(TextSpan(text: t.substring(cut), style: span.style));
      }
      return TextSpan(
          style: span.style, children: [...pieces, ...?kids?.map(walk)]);
    }

    return (tree: walk(root) as TextSpan, dims: dims);
  }

  /// The spans covering source offsets [from]..[to], flattened.
  ///
  /// Used to measure ONE list item's body on its own, at the width its every
  /// visual line will really have. Flattening is safe here because every leaf
  /// this controller emits already carries a complete style — nothing relies on
  /// inheriting from a parent span.
  ({TextSpan tree, List<PlaceholderDimensions> dims}) _slice(
      TextSpan root, int from, int to, TextStyle base) {
    final dims = <PlaceholderDimensions>[];
    final out = <InlineSpan>[];
    final fs = base.fontSize ?? 14;
    var off = 0;

    void walk(InlineSpan span) {
      if (span is _SourceSpan) {
        final at = off;
        off += span.source.length;
        if (at >= from && at < to) {
          out.add(span);
          dims.add(_dimOf(span, fs));
        }
        return;
      }
      if (span is! TextSpan) return;
      final t = span.text;
      if (t != null) {
        final at = off;
        off += t.length;
        final a = math.max(at, from), b = math.min(at + t.length, to);
        if (b > a) {
          out.add(
              TextSpan(text: t.substring(a - at, b - at), style: span.style));
        }
      }
      span.children?.forEach(walk);
    }

    walk(root);
    return (tree: TextSpan(style: base, children: out), dims: dims);
  }

  /// Which source offset starts each visual line, at [width].
  List<int> _visualLineStarts(
      TextSpan tree, List<PlaceholderDimensions> dims, double width) {
    final tp = TextPainter(
        text: tree, textDirection: TextDirection.ltr, maxLines: null)
      ..setPlaceholderDimensions(dims)
      ..layout(maxWidth: width);
    final out = <int>[];
    for (final m in tp.computeLineMetrics()) {
      final y = math.max(0.0, m.baseline - 1);
      out.add(tp.getLineBoundary(tp.getPositionForOffset(Offset(0, y))).start);
    }
    tp.dispose();
    return out;
  }


  /// Text that is laid out but must occupy no space.
  ///
  /// `letterSpacing` and `wordSpacing` are added PER CHARACTER in logical
  /// pixels and are not scaled by `fontSize`, so shrinking the font alone left
  /// the base style's 0.25px per character intact — which over the ~25
  /// characters of an image reference is about one character of visible gap.
  /// That was the picture "sitting about 1 char width from the left edge", and
  /// the same phantom width is what pushed a full-width picture onto the next
  /// line. Both have to be zeroed, not just the size.
  TextStyle _hidden(TextStyle base) => base.copyWith(
        color: const Color(0x00000000),
        fontSize: 0.01,
        letterSpacing: 0,
        wordSpacing: 0,
      );
  TextStyle _dim(TextStyle base) =>
      base.copyWith(color: OnoteColors.graphite400);

  /// What the read renderer draws in the gutter for this marker, or null for
  /// a shape that keeps its literal prefix (a quote, which has its own rail).
  ///
  /// A checkbox shows its state as a box, so a task looks the same whether or
  /// not the caret is in it — the completed-task strikethrough used to vanish
  /// the moment you clicked in.
  static String? _markerGlyph(String marker) {
    if (marker.startsWith('>')) return null;
    final m = marker.trimRight();
    if (m.endsWith(']')) return m.contains(RegExp('[xX]')) ? '☑' : '☐';
    if (RegExp(r'^\d').hasMatch(m)) return m; // `12.` keeps its number
    return '•';
  }

  void _buildLine(String line, int lineStart, TextStyle base, int lo, int hi,
      List<InlineSpan> out) {
    final lineEnd = lineStart + line.length;
    final onLine = lo >= 0 && hi >= lineStart && lo <= lineEnd;

    // A flashcard written into the prose: `?[front](back)` on its own line.
    // Same placeholder arithmetic as the picture below — the card stands for
    // the line's FIRST character and the rest trails hidden, so the paragraph
    // has exactly as many code units as the raw text and not one caret offset
    // moves. See the long note on the image branch; it is the same trick and
    // the same invariant.
    if (line.isNotEmpty) {
      final card = inlineCardRe.firstMatch(line);
      if (card != null) {
        out.add(_SourceSpan(
          source: line.substring(0, 1),
          alignment: PlaceholderAlignment.top,
          child: _InlineCard(
            key: ValueKey('card@$lineStart'),
            front: card.group(1) ?? '',
            back: card.group(2) ?? '',
            selected: onLine,
            onEdit: (f, b) => replaceCardLine(
                lineStart, lineStart + line.length, line, f, b),
          ),
        ));
        out.add(TextSpan(text: line.substring(1), style: _hidden(base)));
        return;
      }
    }

    // An in-flow image reference, drawn as the picture itself.
    //
    // The obvious way to do this — swap the line for a WidgetSpan — desyncs
    // every selection offset, because N characters of raw text become the one
    // U+FFFC code unit a placeholder occupies. So the line keeps its length:
    // its first N-1 characters are emitted at a hairline size and the last one
    // is what the placeholder stands for. N code units of source, N code units
    // laid out, and the coverage check above proves it on every keystroke.
    //
    // What this costs: the reference is no longer legible or comfortably
    // selectable while editing. That was the complaint — a hash where a
    // picture should be — and the caret still walks the line, so backspacing
    // into it breaks the reference and the source reappears, which is its own
    // explanation of what just happened.
    final img = _imageLineRe.firstMatch(line);
    if (img != null) {
      // Dim and monospace, so a reference standing in for a picture reads as a
      // placeholder rather than as writing. Used both when there are no bytes
      // and when the bytes turn out not to be an image.
      final refStyle = _dim(base).copyWith(
          fontFamily: 'JetBrains Mono',
          fontFamilyFallback: onoteFontFallback,
          fontSize: (base.fontSize ?? 14) * 0.85);
      final bytes = _resolveImage(img.group(3)!);
      if (bytes != null && line.isNotEmpty) {
        // The placeholder goes FIRST and stands for the line's first
        // character; the rest of the reference trails behind it, hidden. The
        // other way round — hidden run first — put every one of those
        // characters between the left edge and the picture, and no amount of
        // shrinking makes N characters occupy exactly nothing. Leading with
        // the picture makes flush-left exact rather than merely close, and
        // leaves the unavoidable remainder somewhere it cannot be seen.
        out.add(_SourceSpan(
          source: line.substring(0, 1),
          alignment: PlaceholderAlignment.top,
          child: _EditImage(
            // Keyed by line so the drag state belongs to THIS picture, and is
            // dropped if the text above it moves and the offsets go stale.
            key: ValueKey('${img.group(3)}@$lineStart'),
            bytes: bytes,
            width: double.tryParse(img.group(4) ?? ''),
            height: double.tryParse(img.group(5) ?? ''),
            indent: indentPx(img.group(1)!.length, base.fontSize),
            selected: onLine,
            onNeedWidth: requestExtraWidth,
            label: line,
            labelStyle: refStyle,
            onResize: (w, h) => resizeImageLine(lineStart, lineEnd, line, w, h),
          ),
        ));
        out.add(TextSpan(text: line.substring(1), style: _hidden(base)));
        return;
      }
      // No bytes — a blob still syncing, or one that never arrived. The
      // reference stays as text so it can be read, fixed or cut out.
      out.add(TextSpan(text: line, style: refStyle));
      return;
    }

    // ── Vertical parity with the read renderer (md_render.dart) ──
    //
    // The two renderers are one text box to the user, so their line boxes must
    // agree or the text visibly shifts on every edit-mode entry and exit. The
    // read side expresses extra room as per-line *padding*, which a TextField
    // cannot have — but a line's box is fontSize × height, so the same pixels
    // can be bought with a height multiplier. Each adjustment below mirrors a
    // specific padding in md_render._renderLine; change one only with the
    // other, and edit_view_metrics_test.dart holds the two within 1px.
    final baseFs = base.fontSize ?? 14;
    final baseH = base.height ?? 1.5;
    if (_checkboxLineRe.hasMatch(line)) {
      // Read draws a 17px checkbox icon with 3px top padding, so its row is
      // at least 20px however small the font.
      final minH = 20.0 / baseFs;
      if (minH > baseH) base = base.copyWith(height: minH);
    } else if (_quoteLineRe.hasMatch(line)) {
      // Read gives a quote a 2px margin above and below.
      base = base.copyWith(height: baseH + 4.0 / baseFs);
    }

    // Heading: markers collapse when the caret isn't on the line.
    final h = _headingRe.firstMatch(line);
    if (h != null) {
      final level = math.min(h.group(1)!.length, 3);
      // Same sizes and weight as the read renderer — it used to be 23/19/16.5
      // at w700 against read's 22/18.5/16 at w600, so the glyphs themselves
      // changed shape on entering edit.
      const sizes = [22.0, 18.5, 16.0];
      final size = sizes[level - 1];
      // Read pads a heading with top 6 + bottom 2 (top 0 on the first line).
      final extra = lineStart == 0 ? 2.0 : 8.0;
      final cStyle = base.copyWith(
          fontSize: size,
          fontWeight: FontWeight.w600,
          height: (size * baseH + extra) / size,
          color: dark ? OnoteColors.moon0 : OnoteColors.graphite900);
      final prefix = line.substring(0, h.end);
      out.add(TextSpan(text: prefix, style: onLine ? _dim(base) : _hidden(base)));
      _inline(line.substring(h.end), lineStart + h.end, cStyle, out);
      return;
    }

    // ── List lines: the marker HANGS, exactly as it does when reading ──
    //
    // The read renderer indents a list line by `indentPx(spaces)` and then
    // hangs its bullet in a 22px gutter, so the body starts at
    // `max(indent, 22)`. This used to emit the raw prefix as dimmed literal
    // text — about 9px for `- ` — so every bulleted line jumped ~13px
    // sideways on click-in, and every nesting level added 36.75px when
    // reading against 8.94px (two literal spaces) when writing: 27.81px of
    // drift per level. That was the reported "large amount of content
    // movement with dot points".
    //
    // The fix uses the placeholder trick this file already relies on for
    // pictures and cards: a WidgetSpan occupies ONE code unit, so it stands
    // for the prefix's FIRST character and the rest trails hidden. The line
    // keeps exactly as many code units as the source, so not one caret
    // offset moves — the coverage check above proves it on every keystroke.
    // A divider is not a list, however much `- - -` looks like one to a
    // bullet regex. It drew a bullet while editing and a horizontal rule
    // when read.
    final p = mdDividerRe.hasMatch(line) ? null : _prefixRe.firstMatch(line);
    if (p != null) {
      final prefix = line.substring(0, p.end);
      final indent = indentPx(p.group(1)!.length, base.fontSize);
      final marker = p.group(2)!;
      // A quote keeps its own rail in the read renderer, so only the three
      // list shapes hang. Anything else falls back to the literal prefix.
      final glyph = _markerGlyph(marker);
      if (glyph != null) {
        final bodyStart = math.max(indent, kBulletGutter);
        // BASELINE alignment, not `top`: a top-aligned placeholder is laid
        // out against the top of the font and the line's half-leading sits
        // above it, which grew every list line by 5-12px and broke the
        // vertical parity these renderers already had. Sitting the glyph on
        // the text baseline keeps the line box exactly the height the text
        // alone would have made it.
        out.add(_SourceSpan(
          source: prefix.substring(0, 1),
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          // Declared, so the wrap predictor above knows this gutter's width
          // without laying the widget out.
          width: bodyStart,
          child: SizedBox(
            width: bodyStart,
            child: Padding(
              padding: EdgeInsets.only(
                  left: (bodyStart - kBulletGutter).clamp(0.0, double.infinity)),
              child: Text(glyph,
                  maxLines: 1,
                  style: base.copyWith(color: OnoteColors.graphite500)),
            ),
          ),
        ));
        out.add(TextSpan(text: prefix.substring(1), style: _hidden(base)));
        // A DONE task keeps its strikethrough and its grey while the caret is
        // in it. Drawing only the ticked box meant a completed task lost both
        // the moment you clicked on the line — the comment above claimed the
        // parity that this line actually provides.
        final done = glyph == '☑';
        _inline(
            line.substring(p.end),
            lineStart + p.end,
            done
                ? base.copyWith(
                    decoration: TextDecoration.lineThrough,
                    color: OnoteColors.graphite400)
                : base,
            out);
        return;
      }
      out.add(TextSpan(text: prefix, style: _dim(base)));
      _inline(line.substring(p.end), lineStart + p.end, base, out);
      return;
    }

    _inline(line, lineStart, base, out);
  }

  void _inline(
      String sub, int regionStart, TextStyle cBase, List<InlineSpan> out) {
    var last = 0;
    for (final m in _inlineRe.allMatches(sub)) {
      if (m.start > last) {
        out.add(TextSpan(text: sub.substring(last, m.start), style: cBase));
      }
      // One classifier, shared with the read renderer (markdown/md_syntax.dart)
      // — the two used to carry hand-numbered copies of the alternation and
      // disagreed about `***both***`, `_italic_` and `snake_case`.
      final c = classifyInline(m);

      // Maths stays MATHS while the sentence around it is being edited.
      //
      // It used to drop back to `$\frac{1}{2}$` the moment the caret entered
      // the box — the same defect as `**` appearing around a bold word, and
      // worse, because a fraction is unrecognisable as source. The equation is
      // drawn as ONE object standing in for the opening `$`; the rest of the
      // source trails at a hairline behind it, so the paragraph keeps exactly
      // as many code units as the buffer and not one caret offset moves. The
      // same placeholder trick as the pictures, the cards and the list gutter.
      if (c.kind == MdInline.math ||
          c.kind == MdInline.mathDisplay ||
          c.kind == MdInline.mathPadded ||
          c.kind == MdInline.mathEmpty) {
        final full = sub.substring(m.start, m.end);
        final from = regionStart + m.start, to = regionStart + m.end;
        final tap = onMathTap;
        // In-place editing: THIS equation is the one being written, so the
        // span carries the live editor instead of the drawing. Same source
        // accounting, same baseline — the paragraph cannot tell the
        // difference, which is the whole invariant (v0.20 §B.2).
        final editingHere = from == editingMathAt && mathEditorBuilder != null;
        out.add(_SourceSpan(
          source: full.substring(0, 1),
          // BASELINE: an equation mid-sentence sits on the sentence's
          // baseline like a word, and the line — only that line — grows to
          // fit it. Measured and argued at length in md_render.dart, which
          // draws the read-mode half the same way; the two have to agree or
          // the text jumps on click-in.
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: editingHere
              ? mathEditorBuilder!(c.inner, cBase)
              : InlineMathAtom(
                  latex: c.kind == MdInline.mathDisplay
                      ? '\\displaystyle ${c.inner}'
                      : c.inner,
                  style: cBase,
                  onTap: tap == null
                      ? null
                      : (rect) => tap(from, to, c.inner, rect),
                ),
        ));
        out.add(TextSpan(text: full.substring(1), style: _hidden(cBase)));
        last = m.end;
        continue;
      }

      var openLen = c.openLen, closeLen = c.closeLen;
      final TextStyle inner;
      switch (c.kind) {
        case MdInline.mathEmpty:
        case MdInline.mathDisplay:
        case MdInline.mathPadded:
          // Handled above with the filled form; listed to keep the switch
          // total.
          openLen = closeLen = 0;
          inner = cBase;
        case MdInline.boldItalic:
          inner = cBase.copyWith(
              fontWeight: FontWeight.w600, fontStyle: FontStyle.italic);
        case MdInline.bold:
          // w600 — the read renderer's weight. It used to be w700 here, so
          // bold text physically changed shape on entering edit mode.
          inner = cBase.copyWith(fontWeight: FontWeight.w600);
        case MdInline.italic:
          inner = cBase.copyWith(fontStyle: FontStyle.italic);
        case MdInline.code:
          inner = cBase.copyWith(
              fontFamily: 'JetBrains Mono',
              fontFamilyFallback: onoteFontFallback,
              fontSize: (cBase.fontSize ?? 14) * 0.9,
              color: dark ? OnoteColors.ink300 : OnoteColors.ink700,
              backgroundColor:
                  dark ? OnoteColors.night100 : OnoteColors.paper100);
        case MdInline.strike:
          inner = cBase.copyWith(decoration: TextDecoration.lineThrough);
        case MdInline.subscript:
          // Same helper the read renderer uses, so `H~2~O` does not change
          // shape when the caret leaves the block. It shifts the ink with a
          // shadow rather than a placeholder precisely so the character count
          // — and therefore every caret offset — is untouched.
          inner = subSupStyle(cBase, sup: false, dark: dark);
        case MdInline.superscript:
          inner = subSupStyle(cBase, sup: true, dark: dark);
        case MdInline.highlight:
          inner = cBase.copyWith(
              backgroundColor: dark
                  ? OnoteColors.brass700.withValues(alpha: .45)
                  : const Color(0xFFF7E27A));
        case MdInline.underline:
          inner = cBase.copyWith(decoration: TextDecoration.underline);
        case MdInline.colour:
          final hex = c.target!;
          final v = int.parse(hex, radix: 16);
          inner = cBase.copyWith(
              color: hex.length == 8
                  ? Color(((v & 0xFF) << 24) | (v >> 8))
                  : Color(0xFF000000 | v));
        case MdInline.wikiLink:
        case MdInline.extLink:
        case MdInline.bareUrl:
        case MdInline.math: // handled above; listed to keep the switch total
          // The editor has no live form for these yet, so they stay legible
          // source. Zero-width markers would hide half a URL and leave the
          // caret walking through characters nobody can see.
          openLen = closeLen = 0;
          inner = cBase.copyWith(
              color: dark ? OnoteColors.ink300 : OnoteColors.ink600);
      }

      // ALWAYS hidden. This used to be `reveal ? _dim : _hidden`, where
      // `reveal` meant "the caret touches this run" — so clicking on a bold
      // word made `**` appear around it, which is the second defect this file
      // was rewritten for. See the class comment for what carries the
      // consequences (Ctrl+B to un-format, caret snapping, marker-aware
      // Backspace).
      final markStyle = _hidden(cBase);
      final full = sub.substring(m.start, m.end);
      // open marker + inner + close marker — substrings guarantee coverage.
      out.add(TextSpan(text: full.substring(0, openLen), style: markStyle));
      out.add(TextSpan(
          text: full.substring(openLen, full.length - closeLen), style: inner));
      out.add(TextSpan(
          text: full.substring(full.length - closeLen), style: markStyle));
      last = m.end;
    }
    if (last < sub.length) {
      out.add(TextSpan(text: sub.substring(last), style: cBase));
    }
  }
}

/// A card inside a paragraph, in the live editor.
///
/// Deliberately NOT editable in place: you change it by editing the line, the
/// same way you change a link or a picture reference. Backspacing into it
/// breaks the `?[…](…)` shape and the raw text reappears, which is its own
/// explanation of what just happened.
class _InlineCard extends StatelessWidget {
  const _InlineCard({
    super.key,
    required this.front,
    required this.back,
    required this.selected,
    required this.onEdit,
  });

  final String front;
  final String back;
  final bool selected;

  /// Write a new front and back back into the source line.
  final void Function(String front, String back) onEdit;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Container(
          width: 420,
          height: 132,
          // A foreground decoration, so the caret outline costs no layout and
          // the card cannot shift a pixel when the caret enters its line.
          foregroundDecoration: selected
              ? BoxDecoration(
                  borderRadius: OnoteRadius.xlAll,
                  border: Border.all(
                      color: OnoteColors.brass400.withValues(alpha: .85)))
              : null,
          child: FlipCard(
            front: front,
            back: back,
            compact: true,
            trailing: Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.edit_outlined, size: 14),
                color: OnoteColors.graphite400,
                tooltip: 'Edit this card',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: () async {
                  final r = await editCardDialog(ctx, front, back);
                  if (r != null) onEdit(r.front, r.back);
                },
              ),
            ),
          ),
        ),
      );
}

/// A [WidgetSpan] that remembers the source text it stands in for.
///
/// The whole reason a picture can appear inside a live-editing TextField at
/// all: the coverage check and the misspelling pass both need to know how many
/// characters of the raw buffer this one placeholder accounts for, and a plain
/// WidgetSpan cannot tell them.
class _SourceSpan extends WidgetSpan {
  const _SourceSpan({
    required this.source,
    required super.child,
    this.width,
    super.alignment,
    super.baseline,
  });

  /// The raw text this placeholder was emitted in place of.
  final String source;

  /// How wide this placeholder will lay out, when that is knowable without a
  /// layout pass — the list gutter and the hanging-indent stand-ins both are.
  /// Null for a picture or a card, whose size depends on bytes we would have
  /// to decode; the wrap predictor treats those as zero-width, which is
  /// harmless because `\n` is a HARD break, so no line's wrapping can be
  /// affected by a placeholder on a different line.
  final double? width;
}

/// What a hidden-marker run stands for. Backspace at a marker edge and
/// Backspace at an equation's edge are different operations — one splices
/// text, the other steps INSIDE the equation (v0.20 §B.5) — and telling them
/// apart by the shape of the offsets was one refactor away from wrong.
enum MdRunKind { marker, math }

/// One inline construct with hidden markers, in source offsets.
typedef _MdRun = ({int start, int end, int openLen, int closeLen, MdRunKind kind});

/// A list line's body region and the x its text should start on.
typedef _ListBody = ({int from, int to, double hang});

/// The smallest a picture may be dragged. Below this the handle is most of the
/// image and there is no way back out.
const double _kMinImageWidth = 48;

/// An in-flow image as it appears WHILE the block is being edited: the picture,
/// a corner handle to resize it, and an outline when the caret is on its line.
///
/// Sizing deliberately mirrors `md_render._renderLine` exactly — the same
/// `BoxFit.contain`, the same top-left anchor, the same 4px of vertical room
/// only when there is no explicit size, the same 640px cap only when there is
/// not. The two renderers are one text box to the user, so a picture that
/// moved or resized on entering edit mode would be the bug this feature was
/// meant to remove.
///
/// One gap survives, knowingly: `PlaceholderAlignment.top` aligns the picture
/// with the top of the FONT, and the line's half-leading sits above that, so
/// edit mode is a few pixels taller than read mode per image line. The only
/// lever that removes it is the field-wide strut, and flattening that would
/// break the parity of every other line shape. Pinned in
/// inline_image_edit_test.dart so it cannot quietly grow.
class _EditImage extends StatefulWidget {
  const _EditImage({
    super.key,
    required this.bytes,
    required this.width,
    required this.height,
    required this.indent,
    required this.selected,
    required this.label,
    required this.labelStyle,
    required this.onResize,
    required this.onNeedWidth,
  });

  final Uint8List bytes;

  /// The ` =WxH` suffix, if the reference carries one.
  final double? width, height;
  final double indent;
  final bool selected;

  /// The raw reference, shown if the bytes turn out not to be an image.
  final String label;
  final TextStyle labelStyle;
  final void Function(double w, double h) onResize;

  /// Ask the host for more room. Null when the box cannot grow.
  final void Function(double extra)? onNeedWidth;

  @override
  State<_EditImage> createState() => _EditImageState();
}

class _EditImageState extends State<_EditImage> {
  final _imgKey = GlobalKey();

  /// Live size during a drag. Held here rather than written to the buffer on
  /// every pointer move so the drag is one edit, not a hundred — a hundred
  /// would be a hundred undo entries and a hundred saves.
  double? _dragW, _dragH;
  double _aspect = 1;

  /// The widest this picture may be dragged: the text box itself, minus any
  /// indent. Read from our own incoming constraints rather than through a
  /// LayoutBuilder, because a placeholder inside an editable paragraph is also
  /// laid out during intrinsic-size passes, where a LayoutBuilder cannot go.
  double _maxWidth() {
    final box = context.findRenderObject() as RenderBox?;
    final c = box?.constraints;
    if (c == null || !c.maxWidth.isFinite) return 640;
    final avail = c.maxWidth - widget.indent;
    return avail > _kMinImageWidth ? avail : 640;
  }

  void _startDrag() {
    // The current size is read off the render tree rather than computed from
    // the image's natural dimensions, which would need an async decode. What
    // is on screen is what the user grabbed.
    final box = _imgKey.currentContext?.findRenderObject() as RenderBox?;
    final size = (box != null && box.hasSize) ? box.size : null;
    if (size == null || size.width <= 0 || size.height <= 0) return;
    final w = widget.width, h = widget.height;
    _aspect = (w != null && h != null && h > 0) ? w / h : size.width / size.height;
    // The drag starts from the STORED width when there is one, not from the
    // size on screen: a picture whose `=WxH` is wider than its box is drawn
    // clamped, and starting from the clamped size would shrink it the moment
    // it was touched.
    final from = (w != null && w > 0) ? w : size.width;
    _wanted = from;
    setState(() {
      _dragW = from;
      _dragH = from / _aspect;
    });
  }

  /// Where the pointer has asked the picture to be, ignoring what will fit.
  ///
  /// Tracked separately from [_dragW] because the two diverge whenever the box
  /// is the limit: the pointer keeps going, the picture cannot, and the box is
  /// asked to catch up. Accumulating deltas into the CLAMPED width instead
  /// would silently swallow every pixel of overshoot, so dragging out and back
  /// would not return to where it started.
  double? _wanted;

  void _updateDrag(Offset delta) {
    if (_dragW == null) return;
    final wanted = (_wanted ?? _dragW!) + delta.dx;
    _wanted = wanted;
    final avail = _maxWidth();
    // Push past the edge and the BOX grows, rather than the picture stopping.
    // The request is for the shortfall only; the host owns Block.w and the
    // chrome between it and this placeholder's constraints.
    if (wanted > avail) widget.onNeedWidth?.call(wanted - avail);
    // Still clamped to what is available THIS frame. The growth lands on the
    // next one, and until it does, drawing wider than the box would mean
    // writing a `=WxH` the picture is not actually rendered at — the text and
    // the picture would disagree about a number the user can see.
    final next =
        wanted.clamp(_kMinImageWidth, math.max(_kMinImageWidth, avail)) as double;
    setState(() {
      _dragW = next;
      _dragH = next / _aspect;
    });
  }


  void _endDrag() {
    final w = _dragW, h = _dragH;
    // Cleared and committed in the same frame: the rebuild the commit causes
    // carries the new size, so the picture never flashes back to the old one.
    setState(() {
      _dragW = _dragH = null;
      _wanted = null;
    });
    if (w != null && h != null && h > 0) widget.onResize(w, h);
  }

  /// Set when the bytes are not a picture at all — a truncated sync, a bad
  /// import, a reference to something that was never an image.
  bool _undecodable = false;

  @override
  Widget build(BuildContext context) {
    if (_undecodable) {
      // Same answer as a blob that is missing entirely: show the reference, so
      // there is something to see, fix or cut out rather than a blank gap.
      return Padding(
        padding: EdgeInsets.only(left: widget.indent),
        child: Text(widget.label, style: widget.labelStyle),
      );
    }
    final w = _dragW ?? widget.width;
    final h = _dragH ?? widget.height;
    final sized = w != null || h != null;
    final image = Image.memory(widget.bytes,
        key: _imgKey,
        width: w,
        height: h,
        fit: BoxFit.contain,
        alignment: Alignment.topLeft,
        gaplessPlayback: true,
        // The decode fails asynchronously, so the swap has to wait for the
        // frame that is already building.
        errorBuilder: (_, __, ___) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _undecodable = true);
          });
          return const SizedBox.shrink();
        });
    return Padding(
      padding: EdgeInsets.only(
          left: widget.indent, top: sized ? 0 : 4, bottom: sized ? 0 : 4),
      child: Stack(
        children: [
          Container(
            // A foreground decoration, so the outline costs no layout: with a
            // real border the picture would shift a pixel every time the caret
            // entered its line.
            foregroundDecoration: widget.selected
                ? BoxDecoration(
                    border: Border.all(
                        color: OnoteColors.brass400.withValues(alpha: .85)))
                : null,
            child: sized
                ? image
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: image,
                  ),
          ),
          Positioned(right: 0, bottom: 0, child: _handle()),
        ],
      ),
    );
  }

  /// The corner grip.
  ///
  /// It claims the pointer on the FIRST movement rather than after a pan's
  /// 36px slop, because the field's own selection drag settles at 18px and
  /// would otherwise win the arena on every slow drag — the handle worked when
  /// yanked and did nothing when eased, which is the worst of both. A grip that
  /// exists for one purpose and is 18px across can afford to be certain.
  Widget _handle() => MouseRegion(
        cursor: SystemMouseCursors.resizeUpLeftDownRight,
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            ImmediateMultiDragGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                    ImmediateMultiDragGestureRecognizer>(
              ImmediateMultiDragGestureRecognizer.new,
              (r) => r.onStart = (_) {
                _startDrag();
                return _ResizeDrag(onMove: _updateDrag, onDone: _endDrag);
              },
            ),
          },
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: OnoteColors.brass400.withValues(alpha: .92),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(6)),
            ),
            child: const Icon(Icons.south_east, size: 12, color: Colors.white),
          ),
        ),
      );
}

class _ResizeDrag extends Drag {
  _ResizeDrag({required this.onMove, required this.onDone});
  final ValueChanged<Offset> onMove;
  final VoidCallback onDone;

  @override
  void update(DragUpdateDetails details) => onMove(details.delta);

  @override
  void end(DragEndDetails details) => onDone();

  /// A cancelled drag still commits what was dragged so far. The alternative —
  /// snapping back — loses work for no reason the user can see.
  @override
  void cancel() => onDone();
}

// WrapSelectionFormatter moved to wrap_selection.dart, where every content
// editor can reach it without importing this whole controller — the export
// keeps existing importers compiling.
