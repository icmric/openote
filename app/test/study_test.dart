// Flashcards from tagged lines, and the SM-2 schedule behind review.
//
// The property that carries the feature: ordinary note-taking should produce
// good cards without the student thinking about card design. So the rules are
// tested against text that looks like real notes, not like card definitions.
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/model/tags.dart';
import 'package:openote/study/flashcards.dart';

Block tagged(String text, List<NoteTag> tags) {
  final b = Block(type: BlockType.text, x: 0, y: 0, content: {'text': text});
  NoteTag.writeInto(b.content, tags);
  return b;
}

List<Flashcard> cards(Block b) => cardsFromBlock(b, 'page1', 'Lecture 3');

void main() {
  group('question cards', () {
    test('indented lines under the question become the answer', () {
      final b = tagged(
        'What is a monad?\n  A monoid in the category of endofunctors\n  Also: bind and return',
        [NoteTag(kind: TagKind.question, line: 0)],
      );
      final c = cards(b).single;
      expect(c.front, 'What is a monad?');
      expect(c.back, contains('monoid in the category'));
      expect(c.back, contains('bind and return'),
          reason: 'the whole indented block is the answer, not just line one');
    });

    test('falls back to the next line when nothing is indented', () {
      final b = tagged('Define entropy\nA measure of disorder',
          [NoteTag(kind: TagKind.question, line: 0)]);
      expect(cards(b).single.back, 'A measure of disorder');
    });

    test('a question with no answer below produces no card', () {
      // Half a card is worse than none — it would just waste a review.
      final b = tagged(
          'What is the halting problem?', [NoteTag(kind: TagKind.question, line: 0)]);
      expect(cards(b), isEmpty);
    });
  });

  group('definition cards', () {
    test('splits on an em dash', () {
      final b = tagged('Ohm — resistance of one volt per ampere',
          [NoteTag(kind: TagKind.definition, line: 0)]);
      final c = cards(b).single;
      expect(c.front, 'Ohm');
      expect(c.back, 'resistance of one volt per ampere');
    });

    test('splits on a colon', () {
      final b = tagged('Mitosis: division producing two identical nuclei',
          [NoteTag(kind: TagKind.definition, line: 0)]);
      expect(cards(b).single.front, 'Mitosis');
    });

    test('a hyphenated word is not a separator', () {
      // "well-being" must not split; only a spaced hyphen separates.
      final b = tagged('Well-being: a state of health',
          [NoteTag(kind: TagKind.definition, line: 0)]);
      expect(cards(b).single.front, 'Well-being');
    });

    test('an unsplittable definition line produces no card', () {
      final b = tagged(
          'Just some words', [NoteTag(kind: TagKind.definition, line: 0)]);
      expect(cards(b), isEmpty);
    });
  });

  group('cloze', () {
    test('a highlight inside a tagged line becomes the blank', () {
      final b = tagged('The mitochondria is the ==powerhouse== of the cell',
          [NoteTag(kind: TagKind.question, line: 0)]);
      final c = cards(b).single;
      expect(c.front, 'The mitochondria is the […] of the cell');
      expect(c.back, 'powerhouse');
      expect(c.isCloze, isTrue);
    });

    test('cloze wins over the definition split', () {
      // A highlighted fact inside a definition is the more precise recall.
      final b = tagged('Ohm — resistance of ==one volt per ampere==',
          [NoteTag(kind: TagKind.definition, line: 0)]);
      expect(cards(b).single.back, 'one volt per ampere');
    });
  });

  group('markers are stripped', () {
    test('bold, code, wiki-links and list prefixes never reach the card', () {
      final b = tagged(
        '- **What** is `git rebase`?\n  See [[Version control|abc]] notes',
        [NoteTag(kind: TagKind.question, line: 0)],
      );
      final c = cards(b).single;
      expect(c.front, 'What is git rebase?');
      expect(c.back, 'See Version control notes');
    });
  });

  group('other tags are not cards', () {
    test('to-do and important produce nothing', () {
      final b = tagged('buy milk\nread chapter 4', [
        NoteTag(kind: TagKind.todo, line: 0, checked: false),
        NoteTag(kind: TagKind.important, line: 1),
      ]);
      expect(cards(b), isEmpty);
    });
  });

  group('card identity', () {
    test('is stable across edits elsewhere in the block', () {
      final a = tagged('Q?\n  A', [NoteTag(kind: TagKind.question, line: 0)]);
      final id = cards(a).single.id;
      // Edit a different line; the card's id must not move, or the schedule
      // resets every time the note is touched.
      a.content['text'] = 'Q?\n  A revised and expanded';
      expect(cards(a).single.id, id);
    });
  });

  group('SM-2 scheduling', () {
    const day = 86400000;
    const now = 1000000000000;

    test('a new card graded Good comes back in minutes, then days', () {
      // Textbook SM-2 jumps a brand-new card straight to a day. Learning steps
      // are what let you actually learn it in the sitting you met it in.
      final s = CardState();
      applyGrade(s, Grade.good, now);
      expect(s.intervalDays, 0, reason: 'still in learning');
      expect(s.dueAt, lessThan(now + day));
      applyGrade(s, Grade.good, now + 600000);
      expect(s.intervalDays, 1);
      applyGrade(s, Grade.good, now + day);
      expect(s.intervalDays, 6);
    });

    test('Easy skips the learning step', () {
      final s = CardState();
      applyGrade(s, Grade.easy, now);
      expect(s.intervalDays, greaterThanOrEqualTo(1));
      expect(s.dueAt, greaterThanOrEqualTo(now + day));
    });

    test('intervals grow by ease after the second review', () {
      final s = CardState(repetitions: 2, intervalDays: 6, ease: 2.5);
      applyGrade(s, Grade.good, now);
      expect(s.intervalDays, 15); // 6 * 2.5
    });

    test('Again brings the card back inside the same sitting', () {
      // The bug this pins: a lapse used to schedule the card for TOMORROW, so
      // "let me try that one again" was impossible and the card looked like it
      // had vanished.
      final s = CardState(repetitions: 5, intervalDays: 40, ease: 2.5);
      applyGrade(s, Grade.again, now);
      expect(s.repetitions, 0);
      expect(s.lapses, 1);
      expect(s.dueAt, lessThan(now + 3600000), reason: 'minutes, not a day');
      expect(s.isDue(now + 601000), isTrue);
    });

    test('the button preview matches what the button then does', () {
      // A preview that drifts from the algorithm is worse than none: the
      // student plans around it.
      final s = CardState(repetitions: 2, intervalDays: 6, ease: 2.5);
      for (final g in Grade.values) {
        final shown = previewInterval(s, g, now);
        final actual = formatDelay(applyGrade(s.copy(), g, now).dueAt - now);
        expect(shown, actual, reason: '${g.label} preview');
      }
      expect(s.intervalDays, 6, reason: 'preview must not mutate the card');
    });

    test('delays read the way a student would say them', () {
      expect(formatDelay(600000), '10m');
      expect(formatDelay(day * 3), '3d');
      expect(formatDelay(day * 60), '2mo');
      expect(formatDelay(-5), 'now');
    });

    test('ease has a floor, so a hard card never becomes daily forever', () {
      // Classic SM-2 lets ease decay without bound; that is how students come
      // to hate their own deck.
      final s = CardState(ease: 1.35);
      for (var i = 0; i < 10; i++) {
        applyGrade(s, Grade.again, now);
      }
      expect(s.ease, greaterThanOrEqualTo(1.3));
    });

    test('a never-reviewed card is due immediately', () {
      expect(CardState().isDue(now), isTrue);
    });

    test('state round-trips through JSON', () {
      final s = CardState(repetitions: 3, intervalDays: 15, ease: 2.36, dueAt: now, lapses: 1);
      final back = CardState.fromJson(s.toJson());
      expect(back.repetitions, 3);
      expect(back.intervalDays, 15);
      expect(back.ease, closeTo(2.36, 1e-9));
      expect(back.dueAt, now);
      expect(back.lapses, 1);
    });
  });

  group('tags follow the lines they mark', () {
    // A tag records a line INDEX. That is what lets it survive edits to other
    // lines and travel through the op log with no new op kind — but nothing
    // shifted it when the text gained or lost a line, so pressing Enter above
    // a tagged line moved the marker onto the wrong sentence. The flashcard
    // followed it (cardsFromBlock reads lines[tag.line]) while its id stayed
    // 'blockId:line', so the review schedule stayed attached to a card that
    // was now about something else.

    Map<String, dynamic> marked(String text, List<int> lines) {
      final c = <String, dynamic>{'text': text};
      NoteTag.writeInto(
          c, [for (final l in lines) NoteTag(kind: TagKind.question, line: l)]);
      return c;
    }

    List<int> linesOf(Map<String, dynamic> c) =>
        [for (final t in NoteTag.listFrom(c)) t.line];

    const abc = 'alpha\nbeta\ngamma';

    test('a line inserted above pushes the tag down', () {
      final c = marked(abc, [2]);
      NoteTag.rebase(c, abc, 'alpha\nNEW\nbeta\ngamma');
      expect(linesOf(c), [3]);
    });

    test('a line removed above pulls the tag up', () {
      final c = marked(abc, [2]);
      NoteTag.rebase(c, abc, 'alpha\ngamma');
      expect(linesOf(c), [1]);
    });

    test('a tag above the edit does not move', () {
      final c = marked(abc, [0]);
      NoteTag.rebase(c, abc, 'alpha\nbeta\nNEW\ngamma');
      expect(linesOf(c), [0]);
    });

    test('editing within a line moves nothing', () {
      final c = marked(abc, [1, 2]);
      NoteTag.rebase(c, abc, 'alpha\nbetaX\ngamma');
      expect(linesOf(c), [1, 2]);
    });

    test('deleting the tagged line takes its tag with it', () {
      final c = marked(abc, [1]);
      NoteTag.rebase(c, abc, 'alpha\ngamma');
      expect(linesOf(c), isEmpty);
    });

    test('a rewritten region drops its tags rather than relocating them', () {
      // Select three lines and type two different ones. The old lines are
      // gone, so a tag inside that region marks nothing the user wrote —
      // shifting it by the line delta would silently move the marker (and the
      // flashcard behind it) onto a sentence it never marked.
      final c = marked('A\nB\nC\nD', [1]);
      NoteTag.rebase(c, 'A\nB\nC\nD', 'A\nW\nX\nY\nZ\nD');
      expect(linesOf(c), isEmpty);
    });

    test('it reports where each tag moved to', () {
      // Load-bearing: a flashcard is identified by 'blockId:line', so a tag
      // that moves without its schedule moving too IS a lost schedule.
      final c = marked(abc, [1, 2]);
      final moved = NoteTag.rebase(c, abc, 'NEW\nalpha\nbeta\ngamma');
      expect(moved, {1: 2, 2: 3});
    });

    test('the card keeps asking the same question', () {
      // The consequence that actually matters.
      const before = 'What is a truth table?\n  A grid of every case.';
      const after =
          'Lecture 3\nWhat is a truth table?\n  A grid of every case.';
      final c = marked(before, [0]);
      final was = cardsFromBlock(
              Block(type: BlockType.text, x: 0, y: 0, content: c), 'p', 'Page')
          .single;
      expect(was.front, 'What is a truth table?');

      NoteTag.rebase(c, before, after);
      c['text'] = after;
      final now = cardsFromBlock(
              Block(type: BlockType.text, x: 0, y: 0, content: c), 'p', 'Page')
          .single;
      expect(now.front, was.front,
          reason: 'the card must still ask the same question');
      expect(now.back, was.back);
    });
  });

  group('Anki export', () {
    test('emits tab-separated fields with headers', () {
      final b = tagged('Ohm — one volt per ampere',
          [NoteTag(kind: TagKind.definition, line: 0)]);
      final tsv = cardsToAnkiTsv(cards(b));
      expect(tsv, contains('#separator:tab'));
      final row = tsv.split('\n').firstWhere((l) => l.startsWith('Ohm'));
      final fields = row.split('\t');
      expect(fields[0], 'Ohm');
      expect(fields[1], 'one volt per ampere');
      expect(fields[2], contains('definition'));
      expect(fields[2], contains('Lecture-3'),
          reason: 'Anki tags cannot contain spaces');
    });

    test('newlines become <br> so a multi-line answer stays one record', () {
      final b = tagged('Q?\n  line one\n  line two',
          [NoteTag(kind: TagKind.question, line: 0)]);
      final tsv = cardsToAnkiTsv(cards(b));
      final rows = tsv.split('\n').where((l) => l.startsWith('Q?')).toList();
      expect(rows, hasLength(1));
      expect(rows.single, contains('<br>'));
    });
  });
}
