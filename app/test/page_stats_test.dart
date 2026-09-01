// Words, characters and reading time (PLANNING: "Page info/tools").
//
// The number has to be the number a MARKER would count, or it is worse than
// no number at all: a student trims an essay to 1,500 by a count that is
// really counting asterisks and hands in 1,430.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/model/page_stats.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/object_row.dart';

import 'support/sqlite.dart';

Block text(String s) => Block(
    id: 't', type: BlockType.text, x: 0, y: 0, w: 300, content: {'text': s});

int words(String s) => pageStats([text(s)]).words;

void main() {
  group('what a word is', () {
    test('plain prose', () {
      expect(words('the quick brown fox'), 4);
      expect(words('  spaced   out   words  '), 3);
      expect(words(''), 0);
      expect(words('   \n  \n '), 0);
    });

    test('a hyphenated or apostrophed word is one word', () {
      expect(words("don't"), 1);
      expect(words('year-10 maths'), 2);
      expect(words('3.14 is pi'), 3);
    });

    test('punctuation on its own is not a word', () {
      // Splitting on whitespace alone counts the dash between two clauses.
      expect(words('this — that'), 2);
      expect(words('...'), 0);
      expect(words('a , b'), 2);
    });
  });

  group('markdown counts as it READS', () {
    test('styling is not words', () {
      expect(words('**bold** and *italic*'), 3);
      expect(words('==highlight== ~~strike~~ ++under++'), 3);
      expect(words('***bold italic***'), 2);
    });

    test('nested styling still counts once', () {
      expect(words('**==both at once==**'), 3);
    });

    test('a link is its label, never its target', () {
      expect(words('see [the notes](https://example.com/a/b/c)'), 3);
      expect(words('see [[Chapter 3|node-abc123]]'), 3);
    });

    test('bullets, numbers, quotes, checkboxes and hashes are not words', () {
      expect(words('- one\n- two\n- three'), 3);
      expect(words('1. one\n2. two'), 2);
      expect(words('# A heading'), 2);
      expect(words('> quoted words here'), 3);
      expect(words('[ ] a task\n[x] a done task'), 5);
      expect(words('---'), 0, reason: 'a rule is a line, not a word');
    });

    test('an equation is one word, wherever it is', () {
      expect(words(r'the answer is $y=3x+10$ exactly'), 5);
      expect(words(r'$$\frac{1}{2}$$'), 1,
          reason: 'not two or three, depending on the spacing');
      expect(words(r'$\sqrt{2}$ and $\pi$'), 3);
    });

    test('an equation started and never written in is nothing', () {
      expect(words(r'nothing here $$ yet'), 3);
    });

    test('every kind of markup the app writes is stripped', () {
      // The counter skips the classifier entirely for a line with none of the
      // characters an inline construct can start with — which is most lines,
      // and most of the saving. If a new construct is ever added with an
      // opener outside that set, THIS is where it shows up: the markup would
      // survive into the count as extra words.
      expect(words('a `code span` here'), 4);
      expect(words('H~2~O and x^2^'), 3);
      expect(words('{{#ff0000 red words}} here'), 3);
      expect(words('see https://example.com/a/b now'), 3);
      expect(words(r'padded $ lpha $ here'), 3);
      expect(words('__under__ and _em_'), 3);
    });

    test('an equation does not glue the words either side together', () {
      // Deleting it outright would make this four words rather than five.
      expect(words(r'the answer is $x$ exactly'), 5);
    });
  });

  group('what a page adds up to', () {
    test('characters, with and without spaces', () {
      final s = pageStats([text('ab cd')]);
      expect(s.characters, greaterThanOrEqualTo(5));
      expect(s.charactersNoSpaces, 4);
    });

    test('reading time rounds up and is never a bare zero', () {
      expect(const PageStats(
              words: 0, characters: 0, charactersNoSpaces: 0, blocks: 0)
          .readingMinutes, 0);
      expect(const PageStats(
              words: 1, characters: 1, charactersNoSpaces: 1, blocks: 1)
          .readingMinutes, 1);
      expect(const PageStats(
              words: 200, characters: 0, charactersNoSpaces: 0, blocks: 1)
          .readingMinutes, 1);
      expect(const PageStats(
              words: 201, characters: 0, charactersNoSpaces: 0, blocks: 1)
          .readingMinutes, 2);
    });

    test('a table counts, as one block of however many cells', () {
      final t = Block(id: 'x', type: BlockType.table, x: 0, y: 0, w: 300,
          content: {
            'cells': [
              ['Name', 'Result'],
              ['first sample', 'twelve grams'],
            ]
          });
      final s = pageStats([t]);
      expect(s.words, 6);
      expect(s.blocks, 1);
    });

    test('a maths block is one word, like an inline equation', () {
      // So moving an equation out of a sentence and into a box of its own
      // does not change what the page adds up to.
      final m = Block(id: 'm', type: BlockType.math, x: 0, y: 0, w: 300,
          content: {'latex': r'\frac{1}{2}'});
      expect(pageStats([m]).words, 1);
    });

    test('a listing, a picture and a drawing are not writing', () {
      for (final type in [
        BlockType.code,
        BlockType.image,
        BlockType.file,
        BlockType.ink,
        BlockType.graph,
        BlockType.substitute,
        BlockType.board,
      ]) {
        final b = Block(id: 'b', type: type, x: 0, y: 0, w: 300, content: {
          'text': 'one two three four five',
          'code': 'one two three four five',
        });
        expect(pageStats([b]).words, 0, reason: type.name);
      }
    });

    test('an empty page is zero, not an error', () {
      expect(pageStats(const []).words, 0);
      expect(pageStats([text('')]).blocks, 0);
    });

    test('a whole page adds up', () {
      final s = pageStats([
        text('# Photosynthesis'),
        text('Plants use **light** to make [sugar](https://x.example/y).'),
        Block(id: 'm', type: BlockType.math, x: 0, y: 0, w: 300,
            content: {'latex': '6CO_2'}),
        Block(id: 'c', type: BlockType.code, x: 0, y: 0, w: 300,
            content: {'text': 'print("not counted")'}),
      ]);
      expect(s.words, 1 + 6 + 1,
          reason: "Photosynthesis; Plants use light to make sugar; the maths");
      expect(s.blocks, 3);
    });
  });

  group('the readout on the page row', () {
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());

    late Directory tmp;
    late Repository repo;
    late AppState app;

    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_stats_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('T');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
    });

    tearDown(() {
      AppState.syncLogEnabled = true;
      if (!haveSqlite) return;
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<void> pump(WidgetTester tester, String body) async {
      tester.view.physicalSize = const Size(2600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      app.blocks
        ..clear()
        ..add(text(body));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Align(
                alignment: Alignment.topLeft, child: PageFace(app: app))),
      ));
      await tester.pump();
    }

    testWidgets('says the number, and says "word" when there is one',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pump(tester, 'one two three');
      expect(find.text('3 words'), findsOneWidget);

      await pump(tester, 'alone');
      expect(find.text('1 word'), findsOneWidget,
          reason: '"1 words" is how a student learns to distrust the app');
    });

    testWidgets('separates thousands, because that is the number you squint at',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pump(tester, List.filled(1248, 'w').join(' '));
      expect(find.text('1,248 words'), findsOneWidget);
    });

    testWidgets('and one click gives characters and reading time',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pump(tester, List.filled(250, 'word').join(' '));
      await tester.tap(find.text('250 words'));
      await tester.pumpAndSettle();
      expect(find.text('Words'), findsOneWidget);
      expect(find.text('Characters'), findsOneWidget);
      expect(find.text('Without spaces'), findsOneWidget);
      expect(find.text('2 min'), findsOneWidget,
          reason: '250 words at 200 a minute, rounded up');
    });
  });

  group('counting again, only where the page changed', () {
    // The readout sits on a row that rebuilds on every keystroke, and
    // recounting the whole page took 68 ms on eight hundred blocks — four
    // dropped frames per character, on exactly the pages long enough to have
    // a word limit worth watching. Measured after: 0.5 ms.
    Block at(String id, String body) => Block(
        id: id,
        type: BlockType.text,
        x: 0,
        y: 0,
        w: 300,
        content: {'text': body});

    test('gives the same answer as counting the lot', () {
      final blocks = [at('a', 'one two'), at('b', '**three** four five')];
      expect(PageStatsCache().of(blocks).words, pageStats(blocks).words);
    });

    test('and still does after an edit, an add and a delete', () {
      final cache = PageStatsCache();
      var blocks = [at('a', 'one two'), at('b', 'three')];
      expect(cache.of(blocks).words, 3);

      blocks = [at('a', 'one two three four'), at('b', 'three')];
      expect(cache.of(blocks).words, 5, reason: 'a is longer now');

      blocks = [...blocks, at('c', 'five six')];
      expect(cache.of(blocks).words, 7);

      blocks = [blocks.first];
      expect(cache.of(blocks).words, 4, reason: 'b and c are gone');
    });

    test('a block that only MOVED has not changed a word', () {
      final cache = PageStatsCache();
      final b = at('a', 'one two three');
      expect(cache.of([b]).words, 3);
      b
        ..x = 400
        ..y = 900
        ..w = 120;
      expect(cache.of([b]).words, 3);
    });

    test('a table recounts when one cell changes', () {
      final cache = PageStatsCache();
      Block table(String second) => Block(
          id: 't', type: BlockType.table, x: 0, y: 0, w: 300,
          content: {
            'cells': [
              ['one two', second],
            ]
          });
      expect(cache.of([table('three')]).words, 3);
      expect(cache.of([table('three four five')]).words, 5);
    });

    test('it does not accumulate the blocks a page used to have', () {
      // A page open all afternoon must not carry the wreckage of every block
      // it ever held.
      final cache = PageStatsCache();
      for (var i = 0; i < 50; i++) {
        expect(cache.of([at('b$i', 'one two')]).words, 2, reason: 'round $i');
      }
    });
  });

}
