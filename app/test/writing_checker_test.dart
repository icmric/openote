// The writing checker behind the editor's underlines: which English it reads,
// what it leaves alone, and that it never touches another language.
//
// The tests that need the native library (`rust/onote_text`) look for it the
// way the app does, and skip with a clear reason when there is none, so a
// machine without Rust still runs everything else here.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/core/onote_text.dart';
import 'package:openote/spell/spell_checker.dart';
import 'package:openote/spell/writing_checker.dart';
import 'package:openote/spell/writing_language.dart';

void main() {
  group('which English', () {
    test('the computer\'s region picks the dialect', () {
      expect(dialectOfLocale(const Locale('en', 'AU')), EnglishDialect.australian);
      expect(dialectOfLocale(const Locale('en', 'GB')), EnglishDialect.british);
      expect(dialectOfLocale(const Locale('en', 'NZ')), EnglishDialect.british);
      expect(dialectOfLocale(const Locale('en', 'CA')), EnglishDialect.canadian);
      expect(dialectOfLocale(const Locale('en', 'IN')), EnglishDialect.indian);
      expect(dialectOfLocale(const Locale('en', 'US')), EnglishDialect.american);
      // A bare `en`, and an English we have no entry for, are American.
      expect(dialectOfLocale(const Locale('en')), EnglishDialect.american);
      expect(dialectOfLocale(const Locale('en', 'SG')), EnglishDialect.american);
    });

    test('a computer set to another language is not English', () {
      for (final l in const [
        Locale('de', 'DE'),
        Locale('fr', 'FR'),
        Locale('es', 'ES'),
        Locale('it', 'IT'),
        Locale('pt', 'BR'),
        Locale('zh', 'CN'),
      ]) {
        expect(dialectOfLocale(l), isNull, reason: '$l');
      }
    });

    test('the setting overrides the computer, and Other turns it all off', () {
      const german = Locale('de', 'DE');
      expect(resolveWritingDialect('system', german), isNull);
      // Someone on a German computer who writes English notes can say so.
      expect(resolveWritingDialect('en-AU', german), EnglishDialect.australian);
      // And someone on an English computer writing German can say that.
      expect(resolveWritingDialect('other', const Locale('en', 'AU')), isNull);
      expect(resolveWritingDialect('system', const Locale('en', 'AU')),
          EnglishDialect.australian);
    });

    test('every stored value resolves without throwing', () {
      for (final s in kSpellLanguages) {
        resolveWritingDialect(s, const Locale('en', 'US'));
      }
      // …including one this version has never heard of (a newer build's).
      expect(resolveWritingDialect('klingon', const Locale('en', 'AU')),
          EnglishDialect.australian);
    });
  });

  group('what the checker is shown', () {
    test('code, links, markers and equations are blanked, length kept', () {
      const t = 'See `a bug` and [[Page]] then {{tag}} and \$x^2\$ plus https://a.b/c ok';
      final p = SpellChecker.proseOnly(t);
      expect(p.length, t.length);
      expect(p, isNot(contains('bug')));
      expect(p, isNot(contains('Page')));
      expect(p, isNot(contains('tag')));
      expect(p, isNot(contains('x^2')));
      expect(p, isNot(contains('https')));
      // …and the prose is exactly where it was.
      expect(p.indexOf('See'), 0);
      expect(p.indexOf('then'), t.indexOf('then'));
      expect(p.indexOf('ok'), t.indexOf('ok'));
    });

    test('line breaks survive a blanked region that spans them', () {
      const t = 'one `code\nmore` two\nthree';
      final p = SpellChecker.proseOnly(t);
      expect(p.length, t.length);
      expect('\n'.allMatches(p).length, '\n'.allMatches(t).length);
    });

    test('an escaped dollar is a dollar sign, not an equation', () {
      const t = r'it cost \$5 and \$6 total';
      expect(SpellChecker.proseOnly(t), t);
    });
  });

  group('another language is left alone', () {
    test('no dialect means nothing is checked, whatever the text', () async {
      final r = await WritingChecker.check('Ich habe einen Hund und ein Haus.',
          dialect: null, spelling: true, grammar: true);
      expect(r.isEmpty, isTrue);
    });

    test('with everything switched off nothing is checked', () async {
      final r = await WritingChecker.check('I recieve it',
          dialect: EnglishDialect.australian, spelling: false, grammar: false);
      expect(r.isEmpty, isTrue);
    });
  });

  group('with the native checker', () {
    final have = OnoteText.available;
    final why = have
        ? null
        : 'rust/onote_text is not built here (set ONOTE_TEXT_LIB or build it)';

    test('Australian accepts colour and American does not', () async {
      const t = 'The colour of the organisation was fine.';
      final au = await WritingChecker.check(t,
          dialect: EnglishDialect.australian, spelling: true, grammar: true);
      final us = await WritingChecker.check(t,
          dialect: EnglishDialect.american, spelling: true, grammar: true);
      expect(au.isEmpty, isTrue, reason: '${au.spelling}');
      final flagged = [for (final r in us.spelling) t.substring(r.start, r.end)];
      expect(flagged, containsAll(['colour', 'organisation']));
    }, skip: why);

    test('everyday words are not underlined', () async {
      const t = 'On Monday in January I emailed the website\'s dataset to Dr Smith.';
      final r = await WritingChecker.check(t,
          dialect: EnglishDialect.australian, spelling: true, grammar: true);
      expect(r.isEmpty, isTrue, reason: '${r.spelling} ${r.grammar}');
    }, skip: why);

    test('offsets line up after an emoji and an accent', () async {
      const t = '😀 café, then recieve it';
      final r = await WritingChecker.check(t,
          dialect: EnglishDialect.australian, spelling: true, grammar: false);
      expect(r.spelling, hasLength(1));
      expect(t.substring(r.spelling[0].start, r.spelling[0].end), 'recieve');
    }, skip: why);

    test('grammar is separate from spelling, and each can be off', () async {
      const t = 'Their going to recieve it, I could of done it.';
      final both = await WritingChecker.check(t,
          dialect: EnglishDialect.australian, spelling: true, grammar: true);
      final spellOnly = await WritingChecker.check(t,
          dialect: EnglishDialect.australian, spelling: true, grammar: false);
      final grammarOnly = await WritingChecker.check(t,
          dialect: EnglishDialect.australian, spelling: false, grammar: true);
      expect(both.spelling, isNotEmpty);
      expect(both.grammar, isNotEmpty);
      expect(spellOnly.grammar, isEmpty);
      expect(spellOnly.spelling, isNotEmpty);
      expect(grammarOnly.spelling, isEmpty);
      expect(grammarOnly.grammar, isNotEmpty);
      // A fix is the text itself, ready to paste into the note.
      final cod = both.grammar.firstWhere((f) => f.word.contains('could of'));
      expect(cod.fixes, contains('could have'));
    }, skip: why);

    test('a word the person added stays unflagged', () async {
      learnedWords.add('zorblax');
      addTearDown(() => learnedWords.remove('zorblax'));
      final r = await WritingChecker.check('We met zorblax today.',
          dialect: EnglishDialect.australian, spelling: true, grammar: false);
      expect(r.spelling, isEmpty);
    }, skip: why);

    test('text that is not prose is not read as words', () async {
      const t = 'Run `recieve()` then see [[Teh Page]] and \$recieve\$ here.';
      final r = await WritingChecker.check(t,
          dialect: EnglishDialect.australian, spelling: true, grammar: true);
      expect(r.isEmpty, isTrue, reason: '${r.spelling} ${r.grammar}');
    }, skip: why);

    test('suggestions match the case of the word', () async {
      final s = await WritingChecker.suggest('RECIEVE',
          dialect: EnglishDialect.australian);
      expect(s, isNotEmpty);
      expect(s.first, 'RECEIVE');
    }, skip: why);
  });
}
