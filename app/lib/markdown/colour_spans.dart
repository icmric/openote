/// **Setting the colour of a selection, by rewriting the colour runs on its
/// lines.**
///
/// The colour command used to work by cases: swap the hex when the selection
/// is exactly the inside of a `{{#hex …}}` wrapper, rewrite when it is
/// exactly the whole wrapper, and otherwise wrap whatever was selected. The
/// third case is reached by every ordinary gesture — select one word of a
/// coloured sentence and colour it — and it nests, which the grammar cannot
/// express: `_colour`'s inner is lazy, so the outer run ends at the FIRST
/// `}}` and the rest of it appears on the page as characters. Reported:
///
/// > *"trying to change the colour of text after it has already been assigned
/// > a colour will not remove the old colour tag but just insert it inside the
/// > old one which makes it visible and coloured in the old colour."*
///
/// So this does not patch cases. It reads the line as *a colour per
/// character*, sets the colour of the characters the person selected, and
/// writes the line back out as the runs that implies. Replacing is then the
/// only thing it can do, splitting a run is free, and clearing a colour is
/// the same operation with no colour — which is what the "Automatic" entry in
/// the picker asks for.
///
/// One line at a time, because a colour run cannot span a newline (the
/// grammar's inner excludes it) and a wrapper around two lines would show its
/// own markers — the same rule `wrapSelection` follows for `**`.
library;

import '../markdown/md_syntax.dart';

/// A rewritten source and where the selection ended up in it.
class ColourEdit {
  const ColourEdit(this.text, this.base, this.extent);
  final String text;
  final int base;
  final int extent;
}

/// One line, read as the colour of each visible character.
///
/// [plain] is the line with every colour marker removed, [colour] holds one
/// entry per character of it, and [sourceAt] says where that character came
/// from — which is what maps a selection made in the source onto the
/// characters it actually covers, markers excluded.
class _Painted {
  _Painted(this.plain, this.colour, this.sourceAt);
  final String plain;
  final List<String?> colour;
  final List<int> sourceAt;

  static _Painted of(String line) {
    final plain = StringBuffer();
    final colour = <String?>[];
    final sourceAt = <int>[];
    void take(int from, int to, String? hex) {
      for (var i = from; i < to; i++) {
        plain.writeCharCode(line.codeUnitAt(i));
        colour.add(hex);
        sourceAt.add(i);
      }
    }

    var at = 0;
    for (final m in mdColourSpanRe.allMatches(line)) {
      take(at, m.start, null);
      final hex = m.group(2)!;
      take(m.start + hex.length + 4, m.end - 2, hex); // '{{#' + hex + ' ' … '}}'
      at = m.end;
    }
    take(at, line.length, null);
    return _Painted(plain.toString(), colour, sourceAt);
  }

  /// The line written back out: one wrapper per run of equal colour.
  ///
  /// [newAt] is filled with the emitted offset of each character, so a caller
  /// can follow a selection through the rewrite.
  String emit(List<int> newAt) {
    final out = StringBuffer();
    var i = 0;
    while (i < colour.length) {
      final hex = colour[i];
      var j = i;
      while (j < colour.length && colour[j] == hex) {
        j++;
      }
      if (hex != null) out.write('{{#$hex ');
      for (var k = i; k < j; k++) {
        newAt.add(out.length);
        out.writeCharCode(plain.codeUnitAt(k));
      }
      if (hex != null) out.write('}}');
      i = j;
    }
    return out.toString();
  }
}

/// Which characters of [line] a source selection of [from]..[to] covers, as
/// indices into a [_Painted]. Markers are not characters anybody selected.
List<int> _covered(_Painted p, int from, int to) => [
      for (var i = 0; i < p.sourceAt.length; i++)
        if (p.sourceAt[i] >= from && p.sourceAt[i] < to) i
    ];

/// Give every selected character the colour [hex], or no colour when it is
/// null, and return the rewritten source. Null when there is nothing to do.
///
/// [hex] is the picker's own convention — `RRGGBB` or `RRGGBBAA`, no `#`.
ColourEdit? recolourSelection(String text, int start, int end, String? hex) {
  if (start >= end || start < 0 || end > text.length) return null;
  final out = StringBuffer();
  int? base, extent;
  var lineStart = 0;
  var changed = false;
  final lines = text.split('\n');
  for (var li = 0; li < lines.length; li++) {
    final line = lines[li];
    final lineEnd = lineStart + line.length;
    final from = start.clamp(lineStart, lineEnd) - lineStart;
    final to = end.clamp(lineStart, lineEnd) - lineStart;
    if (to > from) {
      final p = _Painted.of(line);
      final hit = _covered(p, from, to);
      if (hit.isNotEmpty) {
        for (final i in hit) {
          if (p.colour[i] != hex) changed = true;
          p.colour[i] = hex;
        }
        final newAt = <int>[];
        final rebuilt = p.emit(newAt);
        base ??= out.length + newAt[hit.first];
        extent = out.length + newAt[hit.last] + 1;
        out.write(rebuilt);
        if (li < lines.length - 1) out.write('\n');
        lineStart = lineEnd + 1;
        continue;
      }
    }
    out.write(line);
    if (li < lines.length - 1) out.write('\n');
    lineStart = lineEnd + 1;
  }
  if (!changed || base == null || extent == null) return null;
  return ColourEdit(out.toString(), base, extent);
}

/// The one colour every selected character already carries, or null if they
/// disagree or carry none.
///
/// What the toggle hotkey asks before deciding whether it is colouring or
/// clearing, and what the toolbar would ask to show the colour of the caret.
String? colourOfSelection(String text, int start, int end) {
  if (start >= end || start < 0 || end > text.length) return null;
  String? seen;
  var any = false;
  var lineStart = 0;
  for (final line in text.split('\n')) {
    final lineEnd = lineStart + line.length;
    final from = start.clamp(lineStart, lineEnd) - lineStart;
    final to = end.clamp(lineStart, lineEnd) - lineStart;
    if (to > from) {
      final p = _Painted.of(line);
      for (final i in _covered(p, from, to)) {
        final c = p.colour[i];
        if (c == null) return null;
        if (any && c != seen) return null;
        seen = c;
        any = true;
      }
    }
    lineStart = lineEnd + 1;
  }
  return any ? seen : null;
}
