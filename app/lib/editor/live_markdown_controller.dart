import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/onote_theme.dart';

/// A [TextEditingController] that renders Markdown **as you type** (TEXT-2/4):
/// the moment a construct closes (e.g. the second `*` of `**bold**`) the text
/// styles and its markers collapse away; move the caret back into it and the
/// markers reveal so you can edit them (the Obsidian "live preview" model).
///
/// The raw text buffer is unchanged — only the *rendering* transforms — so the
/// stored Markdown stays exactly what the user typed. Every code path is
/// guarded by a coverage check: if span-building ever fails to reproduce the
/// text verbatim, it falls back to an unstyled span, so editing can never
/// corrupt or desync.
class LiveMarkdownController extends TextEditingController {
  LiveMarkdownController({super.text, required this.dark});
  bool dark;

  // Inline: **b** __b__ *i* _i_ `c` ~~s~~ ==h== ++u++ {{#hex text}}
  // `++u++` is appended LAST so the group numbers the dispatch below relies on
  // are unchanged.
  static final _inlineRe = RegExp(
      r'(\*\*(.+?)\*\*)|(__(.+?)__)|(\*(.+?)\*)|(_(.+?)_)|(`(.+?)`)|(~~(.+?)~~)|(==(.+?)==)|(\{\{#([0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?) (.+?)\}\})'
      r'|(\+\+(.+?)\+\+)');
  static final _headingRe = RegExp(r'^(#{1,6})( +)');
  static final _prefixRe = RegExp(r'^(\s*)(- \[[ xX]\] |[-*] |\d+\. |> )');

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
        if (s is TextSpan) {
          if (s.text != null) buf.write(s.text);
          final ch = s.children;
          if (ch != null) ch.forEach(collect);
        }
      }

      collect(root);
      if (buf.toString() == full) {
        return misspellings.isEmpty ? root : _underlineMisspellings(root, lo, hi);
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
    TextSpan walk(TextSpan span) {
      final text = span.text;
      final children = span.children;
      if (text == null) {
        return TextSpan(
          style: span.style,
          children: children?.whereType<TextSpan>().map(walk).toList(),
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
            children: children?.whereType<TextSpan>().map(walk).toList());
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
        children: [...pieces, ...?children?.whereType<TextSpan>().map(walk)],
      );
    }

    return walk(root);
  }

  bool _touches(int a, int b, int lo, int hi) =>
      lo >= 0 && hi >= a && lo <= b;

  TextStyle _hidden(TextStyle base) =>
      base.copyWith(color: const Color(0x00000000), fontSize: 0.1);
  TextStyle _dim(TextStyle base) =>
      base.copyWith(color: OnoteColors.graphite400);

  void _buildLine(String line, int lineStart, TextStyle base, int lo, int hi,
      List<InlineSpan> out) {
    final lineEnd = lineStart + line.length;
    final onLine = lo >= 0 && hi >= lineStart && lo <= lineEnd;

    // Heading: markers collapse when the caret isn't on the line.
    final h = _headingRe.firstMatch(line);
    if (h != null) {
      final level = math.min(h.group(1)!.length, 3);
      const sizes = [23.0, 19.0, 16.5];
      final cStyle = base.copyWith(
          fontSize: sizes[level - 1],
          fontWeight: FontWeight.w700,
          height: 1.3,
          color: dark ? OnoteColors.moon0 : OnoteColors.graphite900);
      final prefix = line.substring(0, h.end);
      out.add(TextSpan(text: prefix, style: onLine ? _dim(base) : _hidden(base)));
      _inline(line.substring(h.end), lineStart + h.end, cStyle, lo, hi, out);
      return;
    }

    // List / quote / checkbox: keep the prefix (dimmed) so items stay aligned.
    final p = _prefixRe.firstMatch(line);
    if (p != null) {
      out.add(TextSpan(text: line.substring(0, p.end), style: _dim(base)));
      _inline(line.substring(p.end), lineStart + p.end, base, lo, hi, out);
      return;
    }

    _inline(line, lineStart, base, lo, hi, out);
  }

  void _inline(String sub, int regionStart, TextStyle cBase, int lo, int hi,
      List<InlineSpan> out) {
    var last = 0;
    for (final m in _inlineRe.allMatches(sub)) {
      if (m.start > last) {
        out.add(TextSpan(text: sub.substring(last, m.start), style: cBase));
      }
      final absStart = regionStart + m.start;
      final absEnd = regionStart + m.end;
      final reveal = _touches(absStart, absEnd, lo, hi);

      var openLen = 2, closeLen = 2;
      TextStyle inner;
      if (m.group(1) != null) {
        inner = cBase.copyWith(fontWeight: FontWeight.w700);
      } else if (m.group(3) != null) {
        inner = cBase.copyWith(fontWeight: FontWeight.w700);
      } else if (m.group(5) != null) {
        openLen = closeLen = 1;
        inner = cBase.copyWith(fontStyle: FontStyle.italic);
      } else if (m.group(7) != null) {
        openLen = closeLen = 1;
        inner = cBase.copyWith(fontStyle: FontStyle.italic);
      } else if (m.group(9) != null) {
        openLen = closeLen = 1;
        inner = cBase.copyWith(
            fontFamily: 'JetBrains Mono', fontFamilyFallback: onoteFontFallback,
            color: dark ? OnoteColors.ink300 : OnoteColors.ink700,
            backgroundColor:
                dark ? OnoteColors.night100 : OnoteColors.paper100);
      } else if (m.group(11) != null) {
        inner = cBase.copyWith(decoration: TextDecoration.lineThrough);
      } else if (m.group(13) != null) {
        inner = cBase.copyWith(
            backgroundColor: dark
                ? OnoteColors.brass700.withValues(alpha: .45)
                : const Color(0xFFF7E27A));
      } else if (m.group(18) != null) {
        inner = cBase.copyWith(decoration: TextDecoration.underline);
      } else {
        // {{#RRGGBB[AA] text}} — asymmetric markers ('{{#'+hex+' ' … '}}')
        final hex = m.group(16)!;
        openLen = hex.length + 4;
        closeLen = 2;
        final v = int.parse(hex, radix: 16);
        inner = cBase.copyWith(
            color: hex.length == 8
                ? Color(((v & 0xFF) << 24) | (v >> 8))
                : Color(0xFF000000 | v));
      }

      final markStyle = reveal ? _dim(cBase) : _hidden(cBase);
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

/// Wraps the current selection with a matching pair when a wrapping character
/// is typed over a non-empty selection — VS Code style. `foo` + `(` → `(foo)`
/// with `foo` re-selected, instead of replacing the text.
class WrapSelectionFormatter extends TextInputFormatter {
  static const _pairs = {
    '(': ')',
    '[': ']',
    '{': '}',
    '"': '"',
    "'": "'",
    '`': '`',
    '*': '*',
    '_': '_',
    '~': '~',
    '=': '=',
    '<': '>',
  };

  /// A line that is exactly an opening fence, so Enter should close it.
  static final _openFenceRe = RegExp(r'^\s*```[A-Za-z0-9+#-]*$');

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final fenced = _autoCloseFence(oldValue, newValue);
    if (fenced != null) return fenced;

    final sel = oldValue.selection;
    if (!sel.isValid || sel.isCollapsed) return newValue;
    final selText = oldValue.text.substring(sel.start, sel.end);
    final tailLen = oldValue.text.length - sel.end;
    // The new text must be old-with-selection-replaced-by-one-char.
    if (newValue.text.length != oldValue.text.length - selText.length + 1) {
      return newValue;
    }
    final insertedEnd = newValue.text.length - tailLen;
    if (insertedEnd <= sel.start || insertedEnd > newValue.text.length) {
      return newValue;
    }
    final inserted = newValue.text.substring(sel.start, insertedEnd);
    final close = _pairs[inserted];
    if (inserted.length != 1 || close == null) return newValue;

    final wrapped =
        oldValue.text.replaceRange(sel.start, sel.end, '$inserted$selText$close');
    return TextEditingValue(
      text: wrapped,
      selection: TextSelection(
          baseOffset: sel.start + 1, extentOffset: sel.start + 1 + selText.length),
    );
  }

  /// Pressing Enter on a bare ``` line opens a fence: insert the closing line
  /// and leave the caret between them (TEXT-2).
  ///
  /// Without this, typing a code fence means typing the closing ``` yourself
  /// and remembering to sit above it — the one Markdown construct where the
  /// editor asking "did you mean a code block?" is unambiguously right.
  TextEditingValue? _autoCloseFence(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final sel = oldValue.selection;
    if (!sel.isValid || !sel.isCollapsed) return null;
    // Exactly one newline inserted at the caret.
    if (newValue.text.length != oldValue.text.length + 1) return null;
    final at = sel.baseOffset;
    if (at < 0 || at > oldValue.text.length) return null;
    if (newValue.text.length <= at || newValue.text[at] != '\n') return null;

    final lineStart = oldValue.text.lastIndexOf('\n', at - 1) + 1;
    final line = oldValue.text.substring(lineStart, at);
    if (!_openFenceRe.hasMatch(line)) return null;
    // Already inside a fence (odd number of fence lines above)? Then this line
    // is a CLOSING fence and must not spawn another.
    final before = oldValue.text.substring(0, lineStart);
    final fencesAbove =
        '\n$before'.split('\n').where((l) => l.trimLeft().startsWith('```')).length;
    if (fencesAbove.isOdd) return null;

    final indent = RegExp(r'^\s*').firstMatch(line)!.group(0)!;
    final insert = '\n$indent```';
    final text = oldValue.text.replaceRange(at, at, '\n$insert');
    return TextEditingValue(
      text: text,
      // Caret on the blank line between the fences.
      selection: TextSelection.collapsed(offset: at + 1),
    );
  }
}
