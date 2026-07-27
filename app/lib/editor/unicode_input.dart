/// Alt+X: turn a Unicode code point into its character, and back again.
///
/// The behaviour people expect from Word and OneNote, and the reason this exists
/// as a pure function: it is entirely a string-and-selection transform, so it can
/// be specified and tested without a widget tree, and reused by any editor engine
/// behind the `OnoteTextEditor` seam.
///
/// Rules, in the order they're tried:
///
///  1. **Something selected** → convert exactly that, nothing more. Lets you
///     point at an ambiguous run (`cafe` → is it `ca`+`fe`?) and be explicit.
///  2. **Caret after hex digits** → convert the longest run that is a valid
///     scalar value, `U+` prefix optional. Scanning is greedy but *validated*,
///     so `U+1F600` wins over `600` and text like `word2764` still resolves the
///     trailing code rather than refusing.
///  3. **Caret after a character** → convert it back to `U+XXXX`. This makes the
///     key a toggle: press it twice and you're where you started, which is how
///     you inspect a character you didn't type.
///
/// Nothing happens (returns `null`) when no rule applies, so the keystroke can
/// fall through to whatever else wants it rather than silently eating input.
library;

import 'package:flutter/services.dart';

/// A resolved edit: the replacement text and where the caret lands.
class UnicodeEdit {
  const UnicodeEdit(this.text, this.selection);
  final String text;
  final TextSelection selection;

  @override
  String toString() => 'UnicodeEdit(${text.length} chars, $selection)';

  @override
  bool operator ==(Object other) =>
      other is UnicodeEdit && other.text == text && other.selection == selection;

  @override
  int get hashCode => Object.hash(text, selection);
}

/// Longest code point Unicode defines.
const int _maxScalar = 0x10FFFF;

/// Hex digits are at most 6 — `10FFFF`. Scanning further can only produce
/// out-of-range values, and stopping bounds the work on a long line of hex.
const int _maxHexDigits = 6;

bool _isHexDigit(int c) =>
    (c >= 0x30 && c <= 0x39) || // 0-9
    (c >= 0x41 && c <= 0x46) || // A-F
    (c >= 0x61 && c <= 0x66); // a-f

/// A value that `String.fromCharCode` can render as one character. Surrogate
/// halves are excluded: they are not characters on their own, and inserting a
/// lone one would corrupt the string it lands in.
bool _isScalar(int v) => v >= 0 && v <= _maxScalar && !(v >= 0xD800 && v <= 0xDFFF);

/// Parse `"U+1F600"`, `"u+ac"` or `"1f600"` into a scalar value.
int? parseCodePoint(String raw) {
  var s = raw.trim();
  if (s.length > 2 && (s.startsWith('U+') || s.startsWith('u+'))) {
    s = s.substring(2);
  } else if (s.length > 1 && (s.startsWith('U') || s.startsWith('u'))) {
    // Tolerate a bare `U1F600` — the `+` is easy to miss and there is no other
    // meaning for a `U` immediately before hex digits.
    final rest = s.substring(1);
    if (rest.runes.every(_isHexDigit)) s = rest;
  }
  if (s.isEmpty || s.length > _maxHexDigits) return null;
  if (!s.runes.every(_isHexDigit)) return null;
  final v = int.tryParse(s, radix: 16);
  return (v != null && _isScalar(v)) ? v : null;
}

/// Apply Alt+X to [text] at [selection]. Returns `null` when nothing applies.
UnicodeEdit? applyAltX(String text, TextSelection selection) {
  if (!selection.isValid) return null;

  // 1. An explicit selection is a precise instruction — honour it or do nothing.
  if (!selection.isCollapsed) {
    final start = selection.start, end = selection.end;
    final picked = text.substring(start, end);
    final cp = parseCodePoint(picked);
    if (cp != null) {
      return _replace(text, start, end, String.fromCharCode(cp));
    }
    // A selected single character toggles back to its code.
    final runes = picked.runes.toList();
    if (runes.length == 1) {
      return _replace(text, start, end, _format(runes.single));
    }
    return null;
  }

  final at = selection.baseOffset;
  if (at <= 0) return null;

  // 2. Hex run immediately before the caret. Try longest-first so `1F600` beats
  //    `600`, but only accept a candidate that is actually a valid scalar.
  var scanStart = at;
  while (scanStart > 0 &&
      at - scanStart < _maxHexDigits &&
      _isHexDigit(text.codeUnitAt(scanStart - 1))) {
    scanStart--;
  }
  if (scanStart < at) {
    // Absorb a `U+` / `U` prefix so the caret returns to before it.
    var from = scanStart;
    if (from >= 2 &&
        (text[from - 1] == '+') &&
        (text[from - 2] == 'U' || text[from - 2] == 'u')) {
      from -= 2;
    } else if (from >= 1 && (text[from - 1] == 'U' || text[from - 1] == 'u')) {
      from -= 1;
    }
    for (var s = scanStart; s < at; s++) {
      final v = int.tryParse(text.substring(s, at), radix: 16);
      if (v != null && _isScalar(v) && v != 0) {
        // Only claim the prefix if it sits flush against the digits we used.
        final replaceFrom = (s == scanStart) ? from : s;
        return _replace(text, replaceFrom, at, String.fromCharCode(v));
      }
    }
    return null;
  }

  // 3. Otherwise toggle the character before the caret back into its code.
  //    Step over a full code point so an astral character round-trips instead of
  //    being split into a surrogate half.
  final before = text.substring(0, at);
  final runes = before.runes.toList();
  if (runes.isEmpty) return null;
  final last = runes.last;
  final charLen = last > 0xFFFF ? 2 : 1;
  if (last == 0x0A || last == 0x20) return null; // not worth toggling whitespace
  return _replace(text, at - charLen, at, _format(last));
}

String _format(int cp) =>
    'U+${cp.toRadixString(16).toUpperCase().padLeft(4, '0')}';

UnicodeEdit _replace(String text, int start, int end, String with_) {
  final out = text.replaceRange(start, end, with_);
  return UnicodeEdit(
    out,
    TextSelection.collapsed(offset: start + with_.length),
  );
}

/// True for the Alt+X chord, on any platform and either Alt key.
bool isAltXChord(KeyEvent event) =>
    event is KeyDownEvent &&
    event.logicalKey == LogicalKeyboardKey.keyX &&
    (HardwareKeyboard.instance.isAltPressed) &&
    !HardwareKeyboard.instance.isControlPressed &&
    !HardwareKeyboard.instance.isMetaPressed;
