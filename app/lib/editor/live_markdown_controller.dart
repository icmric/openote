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
      if (buf.toString() == full) return root;
    } catch (_) {/* fall through */}
    return TextSpan(text: full, style: base);
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
            fontFamily: 'monospace',
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

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
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
}
