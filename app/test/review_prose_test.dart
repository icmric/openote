// Review writing checks what the page shows (owner, 17 November).
//
// *"It checks the raw text, so table source … and other syntax are checked as
// if they were prose, and Openote is flagged as misspelt"*, and *"the
// reviewed-word highlight does not show for punctuation findings."*
//
// The first was text the page never shows being handed to the checker: every
// box holding a table carries `![update Openote to see the table](…)` for older
// builds, which is where "Openote" came from. The other direction was wrong
// too — a coloured run was skipped whole, so its words were never checked.
// The second was a punctuation finding covering no letters (`" ,"`), which the
// whole-word search for the highlight could never find again.
import 'dart:ui' show TextRange;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/core/onote_text.dart';
import 'package:openote/markdown/md_render.dart';
import 'package:openote/markdown/word_mark.dart';
import 'package:openote/model/inline_atom.dart';
import 'package:openote/spell/spell_checker.dart';
import 'package:openote/spell/writing_checker.dart';

void main() {
  group('the prose a check is given', () {
    String prose(String s) {
      final p = SpellChecker.proseOnly(s);
      expect(p.length, s.length, reason: 'offsets must survive');
      return p;
    }

    test("an inline table's alt is not prose", () {
      final s =
          'Results: ![${TableData.referenceAlt}](onote://atom/0198abc) hold.';
      final p = prose(s);
      expect(p, isNot(contains('Openote')));
      expect(p.trimLeft(), startsWith('Results:'));
      expect(p.trimRight(), endsWith('hold.'));
    });

    test("a picture's alt is not prose", () {
      expect(prose('See ![a diagarm](sha256:abcd) here.'),
          isNot(contains('diagarm')));
    });

    test('a link keeps its words and loses its brackets and target', () {
      final p = prose('Read [the chaptre](notes/ch1.md) now.');
      expect(p, contains('the chaptre'));
      expect(p, isNot(contains('[')));
      expect(p, isNot(contains('notes/ch1')));
    });

    test('coloured and highlighted words are checked, not skipped', () {
      final p = prose('A {{#e53935 recieve}} and {{=F7E27A seperate}} word.');
      expect(p, contains('recieve'));
      expect(p, contains('seperate'));
      expect(p, isNot(contains('e53935')));
      expect(p, isNot(contains('{')));
      expect(p, isNot(contains('}')));
    });

    test('the words stay where they were', () {
      const s = 'A {{#e53935 recieve}} word.';
      final p = prose(s);
      expect(p.indexOf('recieve'), s.indexOf('recieve'));
    });

    test('a task box is not a link', () {
      expect(prose('- [ ] buy milk'), contains('buy milk'));
    });
  });

  test('Openote is a word every copy knows', () {
    expect(isKnownWord('Openote'), isTrue);
    expect(isKnownWord('openote'), isTrue);
    expect(isKnownWord('Openot'), isFalse);
  });

  group('what the page marks for a finding', () {
    TextRange r(int s, int e) => TextRange(start: s, end: e);

    test('a word is itself', () {
      expect(markTarget('Its a test.', r(0, 3), 'Its'),
          (start: 0, word: 'Its'));
    });

    test('a space before a comma takes in the word it is glued to', () {
      const t = 'Done ,really.';
      expect(markTarget(t, r(4, 6), ' ,'), (start: 0, word: 'Done ,'));
    });

    test('a lone space takes in the word before and the mark after', () {
      const t = 'I went there , then left.';
      expect(markTarget(t, r(12, 13), ' '), (start: 7, word: 'there ,'));
    });

    test('with no word before, the word glued after', () {
      expect(markTarget('(,then)', r(1, 2), ','), (start: 1, word: ',then'));
    });

    test('and with no word touching it, the mark itself', () {
      expect(markTarget('(, then)', r(1, 2), ','), (start: 1, word: ','));
    });

    test('a word before a colon is a word, not a link', () {
      expect(SpellChecker.proseOnly('Resluts: fine'), 'Resluts: fine');
      expect(SpellChecker.proseOnly('see http://x.y now'),
          'see            now');
    });

    test('a finding the note has moved past marks nothing', () {
      expect(markTarget('Its a test.', r(0, 3), 'Was'), isNull);
      expect(markTarget('short', r(2, 40), 'x'), isNull);
    });

    test('and the widened mark is found again in the line', () {
      expect(wholeWordCount('Done ,really. Done ,again.', 'Done ,'), 2);
      expect(wholeWordCount('Itself. Its.', 'Its'), 1,
          reason: 'a word still needs its own edges');
    });

    testWidgets('the highlight is drawn for a punctuation finding',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: MarkdownView(
            text: 'Done ,really.',
            baseStyle: const TextStyle(fontSize: 14),
            mark: (
              range: const TextRange(start: 4, end: 6),
              word: ' ,',
              color: Colors.orange
            ),
          ),
        ),
      ));
      final mark = tester.widget<WordMark>(find.byType(WordMark));
      expect(mark.word, 'Done ,');
      expect(mark.occurrence, 0);
    });
  });

  group('with the real checker', () {
    Future<WritingResult> check(String s) => WritingChecker.check(s,
        dialect: EnglishDialect.australian, spelling: true, grammar: true);

    test('a box holding a table does not flag the app name', () async {
      final r = await check('Results below. '
          '![${TableData.referenceAlt}](onote://atom/0198abc)');
      expect(r.spellingFindings.map((f) => f.word), isNot(contains('Openote')));
    }, skip: !OnoteText.available);

    test('nor does writing about the app', () async {
      final r = await check('Openote is the app I use.');
      expect(r.spellingFindings, isEmpty);
    }, skip: !OnoteText.available);

    test('a misspelling in colour is found, where it is', () async {
      const s = 'I {{#e53935 recieve}} mail.';
      final r = await check(s);
      final f = r.spellingFindings.single;
      expect(s.substring(f.start, f.end), 'recieve');
    }, skip: !OnoteText.available);
  });
}
