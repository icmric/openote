// Spell checking (TEXT-11) over the app's Markdown dialect.
//
// The tokenizer is the whole game: the text being checked is Markdown with our
// own extensions, so a naive word split would underline URLs, blob hashes,
// wiki-link targets and code — the content people write most and least want
// flagged. Offsets must be RAW-text offsets, because the live editor styles the
// unmodified buffer including its markers.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/spell/spell_checker.dart';

SpellChecker checkerWith(List<String> words) =>
    SpellChecker(SpellDictionary.fromLines(words));

/// The misspelled substrings of [text], for readable assertions.
List<String> bad(SpellChecker c, String text) =>
    [for (final r in c.check(text)) text.substring(r.start, r.end)];

void main() {
  final c = checkerWith([
    'the', 'quick', 'brown', 'fox', 'hello', 'world', 'note', 'notes',
    'colour', 'don', 'dont', "don't", 'is', 'it', 'and', 'page', 'code',
    'on', 'see', 'at', 'check', 'parts', 'build', 'now', 'here', 'img',
  ]);

  setUp(learnedWords.clear);

  group('finds real misspellings', () {
    test('flags an unknown word and leaves known ones alone', () {
      expect(bad(c, 'the quick brxwn fox'), ['brxwn']);
    });

    test('offsets point at the raw text', () {
      const text = 'hello wrld';
      final r = c.check(text).single;
      expect(text.substring(r.start, r.end), 'wrld');
      expect(r.start, 6);
      expect(r.end, 10);
    });

    test('is case-insensitive for dictionary lookup', () {
      expect(bad(c, 'Hello World'), isEmpty);
    });
  });

  group('does not flag things that are not prose', () {
    test('inline code', () {
      expect(bad(c, 'the `zzzq wrld` code'), isEmpty);
    });

    test('wiki-link targets and {{markers}}', () {
      expect(bad(c, 'see [[Zzzq Page]] and {{#FF0000 zzzq}}'), isEmpty);
    });

    test('URLs and scheme-prefixed tokens', () {
      expect(bad(c, 'at https://exmpl.zz/qqq now'), isEmpty);
      expect(bad(c, 'img sha256:deadbeefzzzz here'), isEmpty);
    });

    test('words containing digits', () {
      expect(bad(c, 'build v2beta and h2x'), isEmpty);
    });

    test('ALL-CAPS acronyms', () {
      // Technical notes are full of these; flagging them all makes the feature
      // unusable rather than helpful.
      expect(bad(c, 'the HTTP and JSON parts'), isEmpty);
    });

    test('single letters', () {
      expect(bad(c, 'a b the'), isEmpty);
    });

    test('markdown emphasis markers adjacent to words', () {
      expect(bad(c, '**hello** *world* ~~note~~'), isEmpty);
    });
  });

  group('apostrophes', () {
    test("an internal apostrophe is part of the word", () {
      expect(bad(c, "don't"), isEmpty);
    });

    test('edge apostrophes are trimmed, not treated as letters', () {
      expect(bad(c, "'hello'"), isEmpty);
    });
  });

  group('learned words', () {
    test('a learned word stops being flagged', () {
      expect(bad(c, 'openote is it'), ['openote']);
      learnedWords.add('openote');
      expect(bad(c, 'openote is it'), isEmpty);
    });
  });

  group('suggestions', () {
    test('offers edit-distance-1 corrections', () {
      expect(c.suggest('wrld'), contains('world')); // insertion
      expect(c.suggest('teh'), contains('the')); // transposition
      expect(c.suggest('quikc'), contains('quick'));
      expect(c.suggest('zzzzqqqq'), isEmpty, reason: 'nothing within one edit');
    });

    test('preserves leading capitalisation', () {
      expect(c.suggest('Wrld'), contains('World'));
    });

    test('a correctly spelled word gets no suggestions', () {
      expect(c.suggest('hello'), isEmpty);
    });
  });

  group('dictionary', () {
    test('binary search finds first, last and middle entries', () {
      final d = SpellDictionary.fromLines(['alpha', 'beta', 'gamma', 'delta']);
      expect(d.contains('alpha'), isTrue);
      expect(d.contains('delta'), isTrue);
      expect(d.contains('gamma'), isTrue);
      expect(d.contains('epsilon'), isFalse);
      expect(d.length, 4);
    });

    test('blank lines are dropped and entries lowercased', () {
      final d = SpellDictionary.fromLines(['Alpha', '', '  ', 'BETA']);
      expect(d.length, 2);
      expect(d.contains('alpha'), isTrue);
      expect(d.contains('beta'), isTrue);
    });
  });

  test('a whole markdown paragraph checks only its prose', () {
    const text = '# Notes on `zzzq`\n\n'
        'The quick brxwn fox — see [[Zzzq]] at https://a.bb/cc\n'
        '- [ ] check v2beta and HTTP\n';
    expect(bad(c, text), ['brxwn']);
  });
}
