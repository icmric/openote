// Alt+X code-point conversion.
//
// Specified as a pure string+selection transform so the rules are checkable
// without a widget tree — including the ambiguous cases, which are the whole
// difficulty: hex digits are also ordinary letters, so "which run did you mean"
// has to be answered deterministically.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/unicode_input.dart';

void main() {
  UnicodeEdit? at(String text, int offset) =>
      applyAltX(text, TextSelection.collapsed(offset: offset));

  UnicodeEdit? over(String text, int start, int end) =>
      applyAltX(text, TextSelection(baseOffset: start, extentOffset: end));

  group('code point → character', () {
    test('bare hex at the caret', () {
      expect(at('ac', 2)!.text, '¬');
      expect(at('2200', 4)!.text, '∀');
    });

    test('U+ prefix is optional but consumed when present', () {
      expect(at('U+ac', 4)!.text, '¬');
      expect(at('u+2227', 6)!.text, '∧');
      // The prefix is removed too, not left behind.
      expect(at('x U+00AC', 8)!.text, 'x ¬');
    });

    test('astral code points survive as one character', () {
      final e = at('1F600', 5)!;
      expect(e.text, '\u{1F600}');
      expect(e.text.runes.length, 1);
    });

    test('converts mid-text, leaving the rest alone', () {
      final e = at('let p = 2227 and more', 12)!;
      expect(e.text, 'let p = ∧ and more');
      expect(e.selection.baseOffset, 9, reason: 'caret lands after the glyph');
    });

    test('scanning is greedy, because a longer code is usually the intent', () {
      // Matches Word/OneNote: take the longest run that is a valid scalar, so
      // `1F600` beats `600`. The cost is that hex letters glued to a preceding
      // word get absorbed — "word2764" reads as `d2764`, not `2764` — because
      // there is no way to tell those apart from text alone. Rule 1 (convert
      // exactly the selection) is the escape hatch, asserted just below.
      expect(at('word2764', 8)!.text, 'wor\u{D2764}');
      expect(over('word2764', 4, 8)!.text, 'word❤');
    });
  });

  group('selection', () {
    test('converts exactly what is selected', () {
      expect(over('cafe', 2, 4)!.text, 'caþ');
    });

    test('a selected character toggles back to its code', () {
      expect(over('x ¬ y', 2, 3)!.text, 'x U+00AC y');
    });

    test('a selection that is not a code point does nothing', () {
      expect(over('hello world', 0, 5), isNull);
    });
  });

  group('character → code point (the toggle)', () {
    test('a non-hex character before the caret becomes its code', () {
      expect(at('∀', 1)!.text, 'U+2200');
    });

    test('round-trips', () {
      final once = at('2200', 4)!;
      expect(once.text, '∀');
      final back = at(once.text, once.selection.baseOffset)!;
      expect(back.text, 'U+2200');
    });

    test('an astral character round-trips without splitting a surrogate', () {
      const emoji = '\u{1F600}';
      final e = at(emoji, emoji.length)!;
      expect(e.text, 'U+1F600');
    });
  });

  group('declines rather than corrupting', () {
    test('nothing before the caret', () => expect(at('abc', 0), isNull));

    test('whitespace is not toggled', () {
      expect(at('hello ', 6), isNull);
      expect(at('a\n', 2), isNull);
    });

    test('a surrogate half is never inserted', () {
      // D800 is a lone surrogate — not a character.
      expect(at('D800', 4)!.text, isNot(contains('\uD800')));
      expect(parseCodePoint('D800'), isNull);
    });

    test('out of range is rejected', () {
      expect(parseCodePoint('110000'), isNull);
      expect(parseCodePoint('FFFFFFF'), isNull);
    });

    test('parses the accepted spellings', () {
      expect(parseCodePoint('U+1F600'), 0x1F600);
      expect(parseCodePoint('u+ac'), 0xAC);
      expect(parseCodePoint('2200'), 0x2200);
      expect(parseCodePoint('U2200'), 0x2200);
      expect(parseCodePoint('nope'), isNull);
      expect(parseCodePoint(''), isNull);
    });
  });
}
