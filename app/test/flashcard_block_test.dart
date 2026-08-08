// A flashcard you can put on the page, flip, and revise where it sits.
//
// The ask: "rather than using the tags, maybe we instead create a new thing in
// insert, so it inserts a flashcard element onto the page. This can be edited
// and used in place on the page without having to use the seperate tab, but
// still maintaing the option to see them all in the one place."
//
// The last clause is the one worth testing hardest. A card on the page that
// did NOT reach the study panel would be a second, parallel flashcard system —
// exactly the thing the feature is meant to remove. It reaches it because both
// routes go through `cardsFromBlock`, so these tests check the deck, not just
// the widget.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/block_view.dart';
import 'package:openote/editor/flashcard_block_view.dart';
import 'package:openote/editor/live_markdown_controller.dart';
import 'package:openote/model/models.dart';
import 'package:openote/model/tags.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/study/flashcards.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Block card({String front = 'Capital of France?', String back = 'Paris'}) =>
      Block(
          id: 'card-1',
          type: BlockType.flashcard,
          x: 0,
          y: 0,
          w: 340,
          h: 180,
          content: {'front': front, 'back': back});

  group('a card block is a real card', () {
    test('it becomes exactly one flashcard', () {
      final cards = cardsFromBlock(card(), 'p1', 'Geography');
      expect(cards.length, 1);
      expect(cards.single.front, 'Capital of France?');
      expect(cards.single.back, 'Paris');
      expect(cards.single.pageId, 'p1');
      expect(cards.single.pageTitle, 'Geography');
    });

    test('its id is stable, because a block card has no line to move', () {
      // Tag-derived cards are `blockId:line` and their line shifts as the note
      // is edited around them — the reason `NoteTag.rebase` exists. A block
      // card has one card and no lines, so its id is fixed for the block's
      // life and its review schedule can never be orphaned by an edit.
      expect(cardsFromBlock(card(), 'p1', 'G').single.id, 'card-1:0');
      expect(
          cardsFromBlock(card(front: 'Changed', back: 'Also changed'), 'p1', 'G')
              .single
              .id,
          'card-1:0',
          reason: 'rewriting both sides keeps the schedule');
    });

    test('a half-written card is not dealt into the deck', () {
      // Reviewing a blank front teaches nothing and cannot be graded honestly,
      // and a card is blank for as long as it takes to type the second half.
      expect(cardsFromBlock(card(front: '', back: 'Paris'), 'p', 't'), isEmpty);
      expect(cardsFromBlock(card(front: 'Q', back: ''), 'p', 't'), isEmpty);
      expect(cardsFromBlock(card(front: '   ', back: ' '), 'p', 't'), isEmpty);
    });

    test('tag-derived cards still work, unchanged', () {
      // The new door must not close the old one.
      final text = Block(type: BlockType.text, x: 0, y: 0, content: {
        'text': 'Mitochondria — the powerhouse of the cell',
        'tags': [
          {'kind': TagKind.definition.name, 'line': 0}
        ],
      });
      final cards = cardsFromBlock(text, 'p1', 'Biology');
      expect(cards, isNotEmpty);
      expect(cards.single.front, 'Mitochondria');
    });
  });

  group('a card written into a paragraph', () {
    // "would be nice if i could have them in the same box with text and other
    // stuff. Ideally id like to be able to have everything in a single box at
    // once." `?[front](back)` on its own line, mirroring the in-flow image
    // form — and reaching the deck through the same function, so the study
    // panel needed nothing.
    Block prose(String text) =>
        Block(id: 'b1', type: BlockType.text, x: 0, y: 0, content: {'text': text});

    test('it becomes a card, sharing the block with the writing', () {
      final cards = cardsFromBlock(
          prose('''
Some notes about the war.
?[When did it start?](1914)
And some more notes.'''),
          'p1',
          'History');
      expect(cards, hasLength(1));
      expect(cards.single.front, 'When did it start?');
      expect(cards.single.back, '1914');
      expect(cards.single.line, 1, reason: 'its id tracks the line it is on');
      expect(cards.single.id, 'b1:1');
    });

    test('several in one block all count', () {
      final cards = cardsFromBlock(
          prose('''
?[A](1)
prose in between
?[B](2)'''), 'p', 't');
      expect(cards.map((c) => c.front), ['A', 'B']);
    });

    test('a half-written one is not dealt into the deck', () {
      expect(cardsFromBlock(prose('?[Only a question]()'), 'p', 't'), isEmpty);
      expect(cardsFromBlock(prose('?[](Only an answer)'), 'p', 't'), isEmpty);
    });

    test('it does not need a tag, and does not disturb tags that are there',
        () {
      // A block used to be skipped outright when it had no tags. An in-flow
      // card carries no tag — writing it IS the marking — so that early return
      // had to learn about this shape.
      final both = Block(id: 'b2', type: BlockType.text, x: 0, y: 0, content: {
        'text': 'Osmosis — movement of water across a membrane\n'
            '?[Symbol for sodium?](Na)',
        'tags': [
          {'kind': TagKind.definition.name, 'line': 0}
        ],
      });
      final cards = cardsFromBlock(both, 'p', 't');
      expect(cards.map((c) => c.front), containsAll(['Osmosis', 'Symbol for sodium?']));
    });

    test('editing it rewrites the line, and only that line', () {
      // The edit path an in-flow card actually has. It cannot be a caret: the
      // card handles the tap (it flips), so no click ever puts a caret on its
      // line, and the raw text is laid out at a hairline size behind it. A
      // card you could see and not change was the regression.
      final c = LiveMarkdownController(
          text: 'before\n?[Old Q](Old A)\nafter', dark: false);
      addTearDown(c.dispose);
      var told = 0;
      c.onSelfEdit = () => told++;

      const line = '?[Old Q](Old A)';
      final at = c.text.indexOf(line);
      c.replaceCardLine(at, at + line.length, line, 'New Q', 'New A');

      expect(c.text, 'before\n?[New Q](New A)\nafter');
      expect(told, 1, reason: 'a programmatic edit must tell the host once');
    });

    test('brackets typed into a card do not break the line', () {
      // The delimiters are what make the line a card, so they cannot survive
      // inside it. Losing a bracket beats losing the card.
      final c = LiveMarkdownController(text: '?[a](b)', dark: false);
      addTearDown(c.dispose);
      c.replaceCardLine(0, 7, '?[a](b)', 'f(x) [sic]', 'y = f(x)');
      expect(inlineCardRe.hasMatch(c.text), isTrue,
          reason: 'still a card: \${c.text}');
      final m = inlineCardRe.firstMatch(c.text)!;
      expect(m.group(1), 'f x sic');
      expect(m.group(2), 'y = f x');
    });

    test('a stale edit is dropped rather than applied to other text', () {
      final c = LiveMarkdownController(text: '?[a](b)', dark: false);
      addTearDown(c.dispose);
      c.text = 'entirely different';
      c.replaceCardLine(0, 7, '?[a](b)', 'x', 'y');
      expect(c.text, 'entirely different');
    });

    test('it is not confused with a picture or a wiki link', () {
      expect(cardsFromBlock(prose('![alt](sha256:abc)'), 'p', 't'), isEmpty);
      expect(cardsFromBlock(prose('[[Some page]]'), 'p', 't'), isEmpty);
      expect(cardsFromBlock(prose('a ?[mid](line) card'), 'p', 't'), isEmpty,
          reason: 'line-anchored, exactly like the image form');
    });
  });

  group('it survives a build that has never heard of it', () {
    test('the type name round-trips through an unknown block', () {
      // The format-freeze promise, and the reason adding a BlockType value was
      // safe at all. An older Openote reads `flashcard` as `unknown`, keeps
      // the literal string in `rawType`, and writes it back out — so a page
      // with a card on it opened in an old build and saved does not lose the
      // card.
      final json = card().toJson();
      expect(json['type'], 'flashcard');

      // What an old build's parser does: it has no `flashcard` value.
      final asOldBuild = Block.fromJson({...json, 'type': 'flashcard'});
      expect(asOldBuild.rawType, 'flashcard');
      expect(asOldBuild.toJson()['type'], 'flashcard',
          reason: 'written back verbatim');
      expect(asOldBuild.toJson()['content'], json['content'],
          reason: 'and the question and answer come with it');
    });
  });

  group('on the page', () {
    late Repository repo;
    late Directory tmp;
    late AppState app;

    setUp(() async {
      if (!haveSqlite) return;
      tmp = Directory.systemTemp.createTempSync('onote_card_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Cards');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
    });

    tearDown(() {
      if (!haveSqlite) return;
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<void> show(WidgetTester t, Block b) async {
      app.blocks = [b];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
              width: 340,
              height: 260,
              child: FlashcardBlockView(block: b, app: app)),
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('a filled card shows its question, not its answer',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await show(t, card());
      expect(find.text('Capital of France?'), findsOneWidget);
      expect(find.text('Paris'), findsNothing);
      expect(find.text('QUESTION'), findsOneWidget);
    });

    testWidgets('tapping it turns it over', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await show(t, card());
      await t.tap(find.text('Capital of France?'));
      await t.pumpAndSettle();
      expect(find.text('Paris'), findsOneWidget);
      expect(find.text('ANSWER'), findsOneWidget);
      // And back again — it is a card, not a one-way reveal.
      await t.tap(find.text('Paris'));
      await t.pumpAndSettle();
      expect(find.text('Capital of France?'), findsOneWidget);
    });

    testWidgets('the flip is animated rather than a swap', (t) async {
      // The ask was explicitly for nice animation. Half way through, neither
      // face is square to the viewer — which is only true if something is
      // actually rotating.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await show(t, card());
      await t.tap(find.text('Capital of France?'));
      // Two pumps: the first starts the ticker (its epoch is its first tick),
      // the second advances into the flip. One pump alone leaves elapsed at
      // zero and the card still square on.
      await t.pump();
      await t.pump(const Duration(milliseconds: 90));
      final mid = t.widget<Transform>(
          find.byKey(const ValueKey('flashcard-flip')));
      expect(mid.transform.entry(0, 0), lessThan(0.99),
          reason: 'mid-flip the card is turned, not flat');
      await t.pumpAndSettle();
    });

    testWidgets('a fresh card opens ready to be written', (t) async {
      // Dropped from the Insert menu it has nothing on it; showing an empty
      // rectangle you have to work out how to fill is how a feature goes
      // unused, which is the whole complaint this replaces.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await show(t, card(front: '', back: ''));
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('editing it writes through to the block, once, undoably',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final b = card(front: '', back: '');
      await show(t, b);
      await t.enterText(find.byType(TextField).first, 'What is 7 x 8?');
      await t.enterText(find.byType(TextField).last, '56');
      await t.ensureVisible(find.text('Done'));
      await t.pumpAndSettle();
      await t.tap(find.text('Done'));
      await t.pumpAndSettle();
      // Saving is debounced; the pending timer outlives the widget tree and
      // trips the binding's "a Timer is still pending" invariant otherwise.
      app.cancelPendingSave();

      expect(b.content['front'], 'What is 7 x 8?');
      expect(b.content['back'], '56');
      expect(find.text('What is 7 x 8?'), findsOneWidget,
          reason: 'and it is showing the card again, not the editor');

      // Against app.blocks, not the local reference: undo restores a snapshot
      // of fresh Block objects, so `b` is detached from the page afterwards.
      app.undo();
      app.cancelPendingSave(); // undo saves too
      expect(app.blocks.single.content['front'], anyOf('', isNull),
          reason: 'one Ctrl+Z takes the card back to blank');
    });

    testWidgets('an existing card can be edited without losing the other half',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final b = card();
      await show(t, b);
      await t.tap(find.byIcon(Icons.edit_outlined));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, 'Capital of Japan?');
      await t.ensureVisible(find.text('Done'));
      await t.pumpAndSettle();
      await t.tap(find.text('Done'));
      await t.pumpAndSettle();
      app.cancelPendingSave();
      expect(b.content['front'], 'Capital of Japan?');
      expect(b.content['back'], 'Paris', reason: 'the answer was not touched');
    });

    testWidgets('the canvas knows how to draw one', (t) async {
      // Without the dispatch entry it renders "Unsupported block: flashcard",
      // which is what every OTHER build will show and this one must not.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final b = card();
      app.blocks = [b];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(
              children: [BlockView(block: b, app: app, controller: app.canvas)]),
        ),
      ));
      await t.pump();
      expect(find.byType(FlashcardBlockView), findsOneWidget);
      expect(find.textContaining('Unsupported'), findsNothing);
    });
  });
}
