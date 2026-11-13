// Automatic fixes as a word is finished: a sure typo, the capital that starts a
// sentence, and a lone `i`. And, as much as any of that, everything it must
// leave alone.
//
// Unit tests on the rule, like emphasis_guard_test: it is a pure function of the
// value before a keystroke and the value after, and that is its honest size.
// The checker that supplies "the sure correction" is a fake here; the real one
// is exercised at the end, and skips when its library is not built.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/core/onote_text.dart';
import 'package:openote/editor/auto_writing.dart';

TextEditingValue at(String text, [int? offset]) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset ?? text.length),
    );

/// [what] typed at the caret of [before], as the field reports it before any
/// formatter has seen it.
TextEditingValue typed(TextEditingValue before, String what) {
  final o = before.selection.baseOffset;
  return at(before.text.replaceRange(o, o, what), o + what.length);
}

const _typos = {'teh': 'the', 'adn': 'and', 'recieve': 'receive'};
String? _fake(String w) => _typos[w.toLowerCase()];

/// What the editor would hold after [before] + [what], or null for "unchanged".
String? fixed(
  String before,
  String what, {
  bool correct = true,
  bool capitalize = true,
  int? caret,
  Set<String> keep = const {},
}) {
  final b = at(before, caret);
  final r = computeAutoFix(
    old: b,
    next: typed(b, what),
    autoCorrect: correct,
    autoCapitalize: capitalize,
    correct: _fake,
    keep: keep,
  );
  return r?.value.text;
}

void main() {
  group('a sure typo is fixed when the word is finished', () {
    test('at the end of a word, whatever finishes it', () {
      expect(fixed('say teh', ' '), 'say the ');
      expect(fixed('say adn', ','), 'say and,');
      expect(fixed('please recieve', '.'), 'please receive.');
      expect(fixed('say teh', '\n'), 'say the\n');
    });

    test('the caret follows the word, even when the word is longer', () {
      final b = at('I will recieve');
      final r = computeAutoFix(
          old: b,
          next: typed(b, ' '),
          autoCorrect: true,
          autoCapitalize: false,
          correct: _fake)!;
      expect(r.value.text, 'I will receive ');
      expect(r.value.selection.baseOffset, r.value.text.length);
    });

    test('in the middle of a line, not only at the end', () {
      expect(fixed('say teh cat', ' ', caret: 7), 'say the  cat');
    });

    test('a word that is not in the list of sure fixes is left alone', () {
      expect(fixed('say wibble', ' '), isNull);
    });

    test('a word the person put back as typed is not fixed again', () {
      expect(fixed('say teh', ' ', keep: {'teh'}), isNull);
    });

    test('with the switch off, nothing is fixed (the capital too)', () {
      expect(fixed('say teh', ' ', correct: false), isNull);
      expect(fixed('hello', ' ', capitalize: false, correct: false), isNull);
    });

    test('a name in the middle of a sentence is never "corrected"', () {
      expect(fixed('met Teh', ' '), isNull);
      // …but at the start of a sentence a capital is expected.
      expect(fixed('Teh', ' '), 'The ');
    });
  });

  group('the first word of a sentence gets its capital', () {
    test('at the start of the block, and after a new line', () {
      expect(fixed('hello', ' '), 'Hello ');
      expect(fixed('one\nhello', ' '), 'one\nHello ');
    });

    test('after a full stop, a question mark or an exclamation mark', () {
      expect(fixed('Done. next', ' '), 'Done. Next ');
      expect(fixed('Really? next', ' '), 'Really? Next ');
      expect(fixed('Stop! next', ' '), 'Stop! Next ');
      expect(fixed('She said "go." then', ' '), 'She said "go." Then ');
    });

    test('after a list, quote, heading or checkbox marker', () {
      expect(fixed('- buy', ' '), '- Buy ');
      expect(fixed('1. buy', ' '), '1. Buy ');
      expect(fixed('> note', ' '), '> Note ');
      expect(fixed('## plan', ' '), '## Plan ');
      expect(fixed('- [ ] buy', ' '), '- [ ] Buy ');
    });

    test('but not after an abbreviation, an initial or a number', () {
      expect(fixed('See e.g. this', ' '), isNull);
      expect(fixed('Ask Dr. smith', ' '), isNull);
      expect(fixed('Bring pens, etc. and', ' '), isNull);
      expect(fixed('By J. smith', ' '), isNull);
      expect(fixed('Version 3. next', ' '), isNull);
      expect(fixed('Wait... then', ' '), isNull);
    });

    test('not in the middle of a sentence', () {
      expect(fixed('and then we', ' '), isNull);
      expect(fixed('Hello world', ' '), isNull);
    });

    test('a word that already has a capital, or one inside it, is left', () {
      expect(fixed('Done. Next', ' '), isNull);
      expect(fixed('Done. iPhone', ' '), isNull);
      expect(fixed('Done. eBay', ' '), isNull);
    });

    test('one letter is capitalised only if it is "a"', () {
      expect(fixed('Done. a', ' '), 'Done. A ');
      // A line starting "x = 5" is an equation; "e.g." is an abbreviation.
      expect(fixed('x', ' '), isNull);
      expect(fixed('e', '.'), isNull);
    });

    test('with the switch off, no capital', () {
      expect(fixed('hello', ' ', capitalize: false), isNull);
    });
  });

  group('a lone i is the pronoun', () {
    test('mid-sentence, and in its contractions', () {
      expect(fixed('then i', ' '), 'then I ');
      expect(fixed('then i', ','), 'then I,');
      expect(fixed("then i'm", ' '), "then I'm ");
      expect(fixed('then i’ll', ' '), 'then I’ll ');
    });

    test('but not "i.e." and not a letter in a word', () {
      expect(fixed('that is, i', '.'), isNull);
      expect(fixed('then it', ' '), isNull);
      expect(fixed('then hi', ' '), isNull);
    });
  });

  group('what is never touched', () {
    test('anything that is not one typed character', () {
      final b = at('say teh');
      // A paste of several characters.
      expect(
          computeAutoFix(
              old: b,
              next: typed(b, ' now'),
              autoCorrect: true,
              autoCapitalize: true,
              correct: _fake),
          isNull);
      // A deletion.
      expect(
          computeAutoFix(
              old: at('say teh '),
              next: at('say teh'),
              autoCorrect: true,
              autoCapitalize: true,
              correct: _fake),
          isNull);
    });

    test('a character that is not the end of a word', () {
      expect(fixed('say teh', 'x'), isNull);
      expect(fixed('say teh', '-'), isNull);
    });

    test('an input method that is still composing', () {
      final b = at('say teh');
      final n = typed(b, ' ')
          .copyWith(composing: const TextRange(start: 4, end: 7));
      expect(
          computeAutoFix(
              old: b,
              next: n,
              autoCorrect: true,
              autoCapitalize: true,
              correct: _fake),
          isNull);
    });

    test('a selection rather than a caret', () {
      final b = at('say teh');
      final n = typed(b, ' ').copyWith(
          selection: const TextSelection(baseOffset: 0, extentOffset: 3));
      expect(
          computeAutoFix(
              old: b,
              next: n,
              autoCorrect: true,
              autoCapitalize: true,
              correct: _fake),
          isNull);
    });

    test('a word that is part of something else', () {
      expect(fixed('see http://teh', ' '), isNull);
      expect(fixed('mail me@teh', ' '), isNull);
      expect(fixed('the path/teh', ' '), isNull);
      expect(fixed('tag #teh', ' '), isNull);
      expect(fixed('a-teh', ' '), isNull);
      expect(fixed('abc1teh', ' '), isNull);
      expect(fixed('abcTeh', ' '), isNull);
    });

    test('code, links, equations and addresses', () {
      expect(fixed('run `teh', ' '), isNull);
      expect(fixed('see [[teh', ' '), isNull);
      expect(fixed(r'then $teh', ' '), isNull);
      expect(fixed('a {{teh', ' '), isNull);
      expect(fixed('go to https://x.y/teh', ' '), isNull);
    });
  });

  group('putting a fix back', () {
    test('a fix carries what Backspace needs to reverse it', () {
      final b = at('say teh');
      final r = computeAutoFix(
          old: b,
          next: typed(b, ' '),
          autoCorrect: true,
          autoCapitalize: true,
          correct: _fake)!;
      expect(r.original, 'teh');
      expect(r.replacement, 'the');
      expect(r.before.text, 'say teh ');
      expect(r.before.selection.baseOffset, 8);
    });
  });

  group('the formatter, which is what the editor uses', () {
    AutoWritingFormatter make({bool english = true}) => AutoWritingFormatter(
          enabled: () => english,
          autoCorrect: () => true,
          autoCapitalize: () => true,
          correct: _fake,
          keep: <String>{},
          onFix: (_) {},
        );

    test('fixes when English', () {
      final b = at('say teh');
      expect(make().formatEditUpdate(b, typed(b, ' ')).text, 'say the ');
    });

    test('and does nothing at all when the language is not English', () {
      // The guarantee: German, French, Spanish, Italian, Portuguese, Chinese.
      for (final t in const [
        'das haus',
        'le chat',
        'el perro',
        'il gatto',
        'o cão',
        '你好 世界',
        'i teh',
      ]) {
        final b = at(t);
        final n = typed(b, ' ');
        expect(make(english: false).formatEditUpdate(b, n), n,
            reason: 'for "$t"');
      }
    });
  });

  group('with the real checker', () {
    final have = OnoteText.available;
    final why = have ? null : 'rust/onote_text is not built here';

    test('a sure typo is corrected, and a real word is not', () async {
      await OnoteText.warmUp(EnglishDialect.australian);
      String? real(String w) =>
          OnoteText.autocorrectNow(w, EnglishDialect.australian);
      final b = at('say teh');
      final r = computeAutoFix(
          old: b,
          next: typed(b, ' '),
          autoCorrect: true,
          autoCapitalize: true,
          correct: real);
      expect(r?.value.text, 'say the ');
      final c = at('say colour');
      expect(
          computeAutoFix(
              old: c,
              next: typed(c, ' '),
              autoCorrect: true,
              autoCapitalize: true,
              correct: real),
          isNull,
          reason: 'colour is a word in Australian English');
    }, skip: why);

    test('before the engine is warm it answers nothing rather than waiting',
        () {
      // A fresh isolate state is not available here, so this only documents
      // the contract: autocorrectNow never throws and never blocks.
      expect(OnoteText.autocorrectNow('', EnglishDialect.australian), isNull);
    }, skip: why);
  });

  group('the word before is put right once the next one shows what was meant',
      () {
    test('its a, its not, its been', () {
      expect(fixed('i think its a', ' '), "i think it's a ");
      expect(fixed('well its not', ' '), "well it's not ");
      expect(fixed('so its been', ','), "so it's been,");
      expect(fixed('Its a', ' '), "It's a ");
    });

    test('your a, their is', () {
      expect(fixed('i hope your a', ' '), "i hope you're a ");
      expect(fixed('your not', ' '), "you're not ");
      expect(fixed('their is', ' '), 'there is ');
    });

    test('the caret stays after what was typed', () {
      final b = at('i think its a');
      final r = computeAutoFix(
          old: b,
          next: typed(b, ' '),
          autoCorrect: true,
          autoCapitalize: false,
          correct: _fake)!;
      expect(r.value.text, "i think it's a ");
      expect(r.value.selection.baseOffset, r.value.text.length);
    });

    test('never when the pair could be right', () {
      // "its going rate", "your welcome pack", "its very existence".
      expect(fixed('the its going', ' '), isNull);
      expect(fixed('your welcome', ' '), isNull);
      expect(fixed('its very', ' '), isNull);
      // A possessive in front of an ordinary noun is just English.
      expect(fixed('the dog and its bone', ' '), isNull);
      expect(fixed('check your answer', ' '), isNull);
      expect(fixed('their house', ' '), isNull);
    });

    test('not across a sentence, a line or other punctuation', () {
      // (Capitals off: a new sentence's "a" would otherwise be capitalised.)
      expect(fixed('what its. a', ' ', capitalize: false), isNull);
      expect(fixed('what its\na', ' ', capitalize: false), isNull);
      expect(fixed('ITS a', ' '), isNull);
      expect(fixed('https://its a', ' '), isNull);
    });

    test('off with autocorrect, and not in code', () {
      expect(fixed('its a', ' ', correct: false), isNull);
      expect(fixed('use `its a', ' '), isNull);
    });

    test('put back as typed once, it is not done again', () {
      expect(fixed('its a', ' ', keep: {'its a'}), isNull);
    });
  });
}
