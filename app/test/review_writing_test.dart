// Review writing: every spelling, grammar and punctuation suggestion on the
// page, in one place.
//
// The model is tested with a scripted checker, so none of it depends on the
// native library; one test at the end uses the real one and is skipped where it
// is absent. The panel is driven through the real shell with real pointer and
// key events.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/core/onote_text.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/spell/spell_checker.dart';
import 'package:openote/spell/writing_checker.dart';
import 'package:openote/spell/writing_review.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/app_shell.dart';
import 'package:openote/ui/review_panel.dart';

import 'support/sqlite.dart';

/// A checker that knows a handful of mistakes, in the shape the real one
/// answers in.
Future<WritingResult> scripted(String text,
    {required EnglishDialect? dialect,
    required bool spelling,
    required bool grammar}) async {
  final sp = <TextFinding>[];
  final gr = <TextFinding>[];
  void find(String w, List<TextFinding> into, String kind, List<String> fixes) {
    var i = 0;
    while ((i = text.indexOf(w, i)) >= 0) {
      into.add(TextFinding(
          start: i,
          end: i + w.length,
          kind: kind,
          message: 'Because of $w',
          word: w,
          fixes: fixes));
      i += w.length;
    }
  }

  if (spelling) {
    find('recieve', sp, 'spelling', ['receive', 'relieve']);
    find('seperated', sp, 'spelling', ['separated']);
  }
  if (grammar) {
    find('their are', gr, 'grammar', ['there are']);
    find('could of', gr, 'grammar', ['could have']);
    find(' ,', gr, 'punctuation', [',']);
  }
  return WritingResult(
      spelling: [for (final f in sp) TextRange(start: f.start, end: f.end)],
      spellingFindings: sp,
      grammar: gr);
}

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());
  tearDown(learnedWords.clear);

  late Directory tmp;
  late Repository repo;
  late AppState app;
  AppState? live;

  /// A test, then the app's own debounced save and sync timers cancelled: an
  /// edit arms them, and a fake-clock test may not end with one pending.
  void tw(String name, Future<void> Function(WidgetTester t) body,
          {bool skip = false}) =>
      testWidgets(name, (t) async {
        await body(t);
        live?.cancelPendingSave();
      }, skip: skip);

  Block box(String id, double y, String text) => Block(
      id: id,
      type: BlockType.text,
      x: 40,
      y: y,
      w: 400,
      content: {'text': text, 'autoWidth': false});

  Future<void> start(
    WidgetTester t,
    List<Block> blocks, {
    Locale locale = const Locale('en', 'AU'),
    bool mount = false,
    Size window = const Size(1400, 900),
  }) async {
    AppState.syncLogEnabled = false;
    await t.runAsync(() async {
      tmp = Directory.systemTemp.createTempSync('onote_review_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Review');
      app = AppState(repo)
        ..notebookId = nb.id
        ..reviewChecker = scripted;
      app.systemLocale = () => locale;
      app.reloadNodes();
      final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
      app.importPage(nb.id, page.id, blocks, PageProps());
      app.reloadNodes();
      await app.selectPage(page.id);
    });
    live = app;
    addTearDown(() {
      live = null;
      AppState.syncLogEnabled = true;
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    if (!mount) return;
    app.markOnboardingSeen();
    t.view.physicalSize = window;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      theme: onoteTheme(Brightness.light),
      home: AppShell(app: app),
    ));
    await t.pump(const Duration(milliseconds: 900));
    await t.pumpAndSettle();
  }

  Future<void> look(WidgetTester t) => t.runAsync(() => app.review.refresh());

  String textOf(String id) => app.blockById(id)!.content['text'] as String;

  // ── The model ─────────────────────────────────────────────────────────────

  group('what is found', () {
    tw('every text box on the page, sorted into three kinds',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await start(t, [
        box('b', 300, 'Remember to check seperated samples.'),
        box('a', 100, 'Cells recieve signals, their are three types.'),
        box('c', 500, 'Could of been avoided , but fine.'),
      ]);
      await look(t);
      final r = app.review;
      expect(r.checked, isTrue);
      expect(r.count, 4);
      expect(r.itemsOf(ReviewCategory.spelling).map((i) => i.finding.word),
          ['recieve', 'seperated'],
          reason: 'in reading order down the page');
      expect(r.itemsOf(ReviewCategory.grammar).map((i) => i.finding.word),
          ['their are'],
          reason: '"Could of" starts with a capital so the scripted checker '
              'does not know it: only what it recognises is reported');
      expect(r.itemsOf(ReviewCategory.punctuation).map((i) => i.finding.word),
          [' ,']);
    });

    tw('not for someone who is not writing English', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await start(t, [box('a', 100, 'Cells recieve signals.')],
          locale: const Locale('de', 'DE'));
      await look(t);
      expect(app.review.available, isFalse);
      expect(app.review.count, 0);
      expect(app.review.checked, isFalse);
      app.toggleReview();
      expect(app.openPanel, isNull,
          reason: 'there is no such panel for them');
    });

    tw('and not when both checks are off', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await start(t, [box('a', 100, 'Cells recieve signals.')]);
      app.spellCheckEnabled = false;
      app.grammarCheckEnabled = false;
      expect(app.review.available, isFalse);
    });

    tw('grammar off leaves only spelling', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await start(t, [box('a', 100, 'Cells recieve signals, their are three.')]);
      app.grammarCheckEnabled = false;
      await look(t);
      expect(app.review.count, 1);
      expect(app.review.items.single.category, ReviewCategory.spelling);
    });
  });

  group('doing something about it', () {
    tw('accepting puts the words in and takes one undo to reverse',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await start(t, [box('a', 100, 'We recieve signals and seperated them.')]);
      await look(t);
      final first = app.review.items.first;
      expect(app.review.accept(first), isTrue);
      expect(textOf('a'), 'We receive signals and seperated them.');
      expect(app.review.count, 1, reason: 'the other one is still listed');
      expect(app.review.items.single.finding.word, 'seperated');

      app.undo();
      expect(textOf('a'), 'We recieve signals and seperated them.');
    });

    tw('a suggestion other than the first can be chosen', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await start(t, [box('a', 100, 'We recieve signals.')]);
      await look(t);
      app.review.accept(app.review.items.single, choice: 'relieve');
      expect(textOf('a'), 'We relieve signals.');
    });

    tw(
        'Fix all does one kind, in every box, in one undo step',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await start(t, [
        box('a', 100, 'We recieve and recieve, their are two.'),
        box('b', 300, 'They seperated it.'),
      ]);
      await look(t);
      expect(app.review.count, 4);
      final n = app.review.fixAll(ReviewCategory.spelling);
      expect(n, 3);
      expect(textOf('a'), 'We receive and receive, their are two.');
      expect(textOf('b'), 'They separated it.');
      expect(app.review.itemsOf(ReviewCategory.grammar).length, 1,
          reason: 'the grammar one was not touched, and is still listed where '
              'it now is');
      final g = app.review.itemsOf(ReviewCategory.grammar).single.finding;
      expect(textOf('a').substring(g.start, g.end), 'their are',
          reason: 'its place moved with the text before it');

      app.undo();
      expect(textOf('a'), 'We recieve and recieve, their are two.');
      expect(textOf('b'), 'They seperated it.',
          reason: 'one Ctrl+Z took back the lot, in both boxes');
    });

    tw('fixes that change the length keep the later ones in place',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // Two grammar fixes that change the length (+2, then -1), BEFORE a
      // spelling mistake that should not be found at its old offsets any more.
      await start(t, [box('a', 100, 'Maybe could of been , then recieve it.')]);
      await look(t);
      final before = app.review.itemsOf(ReviewCategory.spelling).single.finding;
      app.review.fixAll(ReviewCategory.grammar);
      expect(textOf('a'), 'Maybe could have been , then recieve it.');
      app.review.fixAll(ReviewCategory.punctuation);
      expect(textOf('a'), 'Maybe could have been, then recieve it.');
      final s = app.review.itemsOf(ReviewCategory.spelling).single.finding;
      expect(s.start, before.start + 1, reason: '+2 and -1');
      expect(textOf('a').substring(s.start, s.end), 'recieve',
          reason: 'still points at the word, not at the letters next to it');
    });

    tw('a box that changed since it was checked is not patched',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await start(t, [box('a', 100, 'We recieve signals.')]);
      await look(t);
      final item = app.review.items.single;
      // Someone types before it, after the look.
      app.blockById('a')!.content['text'] = 'Today we recieve signals.';
      expect(app.review.accept(item), isFalse);
      expect(textOf('a'), 'Today we recieve signals.');
    });

    tw('ignoring is remembered for that place, and no other',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await start(t, [
        box('a', 100, 'First we recieve it.'),
        box('b', 300, 'Then we recieve it again.'),
      ]);
      await look(t);
      expect(app.review.count, 2);
      app.review.ignore(app.review.items.first);
      expect(app.review.count, 1);
      expect(app.writingIgnored, hasLength(1));

      await look(t);
      expect(app.review.count, 1, reason: 'it does not come back');
      expect(app.review.items.single.blockId, 'b',
          reason: 'the same word in another place is still a suggestion');
      // It is kept: a fresh run of the app has it too.
      expect(repo.getSetting('writingIgnored'), isA<List>());
    });

    tw('adding to the dictionary clears every place the word is',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await start(t, [
        box('a', 100, 'We recieve it.'),
        box('b', 300, 'And recieve that, and seperated this.'),
      ]);
      await look(t);
      expect(app.review.count, 3);
      app.review.addToDictionary(app.review.items.first);
      expect(learnedWords, contains('recieve'));
      expect(app.review.items.map((i) => i.finding.word), ['seperated']);
    });

    tw('only spelling can be added to the dictionary', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await start(t, [box('a', 100, 'So their are three.')]);
      await look(t);
      expect(app.review.items.single.category, ReviewCategory.grammar);
      app.review.addToDictionary(app.review.items.single);
      expect(learnedWords, isEmpty);
      expect(app.review.count, 1);
    });

    tw('stepping with the arrows wraps, and opens the page to it',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await start(t, [
        box('a', 100, 'We recieve it.'),
        box('b', 300, 'They seperated it.'),
      ]);
      await look(t);
      expect(app.review.current!.blockId, 'a',
          reason: 'the top one is open from the start');
      expect(app.selectedBlockId, isNot('a'),
          reason: 'but the page is not moved until someone chooses');
      app.review.step(1);
      expect(app.review.current!.blockId, 'b');
      expect(app.selectedBlockId, 'b', reason: 'the page is taken to it');
      app.review.step(1);
      expect(app.review.current!.blockId, 'a');
      app.review.step(-1);
      expect(app.review.current!.blockId, 'b');
    });
  });

  // ── The panel ─────────────────────────────────────────────────────────────

  group('the panel', () {
    List<Block> texts() => [
          box('a', 100,
              'Cells recieve signals. Their are three. We seperated them.'),
          box('b', 300, 'Done ,really.'),
        ];

    Future<void> openPanel(WidgetTester t) async {
      await look(t);
      await t.pump();
      await t.tap(find.byType(ReviewChip));
      await t.pumpAndSettle();
    }

    tw('the status bar says how many, and opens it', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await start(t, texts(), mount: true);
      expect(find.text('3 to review'), findsNothing,
          reason: 'nothing until the page has been looked at');
      await look(t);
      await t.pump();
      expect(find.text('3 to review'), findsOneWidget);

      await t.tap(find.text('3 to review'));
      await t.pumpAndSettle();
      expect(find.byType(ReviewPanel), findsOneWidget);
      expect(find.text('SPELLING · 2'), findsOneWidget);
      expect(find.text('PUNCTUATION · 1'), findsOneWidget);
      expect(find.textContaining('English (Australia)'), findsOneWidget);
    });

    tw('each kind has its own Fix all, and a notice with Undo',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await start(t, texts(), mount: true);
      await openPanel(t);
      expect(find.text('Fix all'), findsNWidgets(2),
          reason: 'one for spelling, one for punctuation (grammar found none: '
              'the capital is not in the stand-in\'s list)');
      await t.tap(find.text('Fix all').first);
      await t.pumpAndSettle();
      expect(textOf('a'), contains('receive'));
      expect(textOf('a'), contains('separated'));
      expect(textOf('b'), 'Done ,really.', reason: 'punctuation untouched');
      expect(find.text('Fixed 2 spelling mistakes'), findsOneWidget);

      await t.tap(find.text('Undo'));
      await t.pumpAndSettle();
      expect(textOf('a'), contains('recieve'));
      expect(textOf('a'), contains('seperated'));
    });

    tw('a row opens its card; the tick and cross act at once',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await start(t, texts(), mount: true);
      await openPanel(t);
      // The top one is open from the start, so it is plain every one can be.
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Not in the dictionary'), findsOneWidget);
      expect(app.review.current!.finding.word, 'recieve');
      // The ROW of the second suggestion (the open card's own context also
      // contains the word, so find the row by its key).
      final second = app.review.items.firstWhere(
          (i) => i.finding.word == 'seperated');
      await t.tap(find.byKey(ValueKey('row-${second.key}')));
      await t.pumpAndSettle();
      expect(app.review.current!.finding.word, 'seperated',
          reason: 'clicking another row opens that one instead');
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Ignore'), findsOneWidget);
      expect(find.text('Add to dictionary'), findsOneWidget);
      expect(app.selectedBlockId, 'a', reason: 'the page moved to it');

      await t.tap(find.text('Accept'));
      await t.pumpAndSettle();
      expect(textOf('a'), contains('separated'));

      // A tick on a closed row.
      await t.tap(find.byKey(const ValueKey('review-accept')).first);
      await t.pumpAndSettle();
      expect(textOf('a'), contains('receive'));
      // And the one that is left, which the card moved on to.
      await t.tap(find.text('Ignore'));
      await t.pumpAndSettle();
      expect(app.writingIgnored, hasLength(1));
      expect(textOf('b'), 'Done ,really.', reason: 'ignoring changes nothing');
    });

    tw('the keys: Down, Enter, Delete and Esc', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await start(t, texts(), mount: true);
      await openPanel(t);
      // The top one is already open, so Enter accepts it.
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(textOf('a'), contains('receive'));
      expect(app.review.current!.finding.word, 'seperated',
          reason: 'the card moves on to what was below it');
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      expect(app.review.current!.finding.word, ' ,');
      await t.sendKeyEvent(LogicalKeyboardKey.delete);
      await t.pumpAndSettle();
      expect(app.writingIgnored, hasLength(1));
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.byType(ReviewPanel), findsNothing);
    });

    tw('F7 opens and closes it, and does nothing outside English',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await start(t, texts(), mount: true);
      await look(t);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.f7);
      await t.pumpAndSettle();
      expect(find.byType(ReviewPanel), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.f7);
      await t.pumpAndSettle();
      expect(find.byType(ReviewPanel), findsNothing);
    });

    tw('no entry and no F7 for a German computer', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await start(t, texts(), mount: true, locale: const Locale('de', 'DE'));
      await look(t);
      await t.pump();
      expect(find.byType(ReviewChip), findsNothing);
      await t.sendKeyEvent(LogicalKeyboardKey.f7);
      await t.pumpAndSettle();
      expect(app.openPanel, isNull);
    });

    tw('when there is nothing left it says so, and the chip goes quiet',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await start(t, [box('a', 100, 'All fine here.')], mount: true);
      await look(t);
      await t.pump();
      expect(find.text('No writing issues'), findsOneWidget);
      await t.tap(find.text('No writing issues'));
      await t.pumpAndSettle();
      expect(find.text('Nothing to review on this page.'), findsOneWidget);
    });
  });

  group('where it sits and how wide', () {
    List<Block> one() => [box('a', 100, 'Cells recieve signals.')];

    tw('the chip is at the far right of the status bar, with no tooltip',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await start(t, one(), mount: true, window: const Size(1600, 900));
      await look(t);
      await t.pump();
      final chip = t.getRect(find.byType(ReviewChip));
      expect(chip.right, greaterThan(1600 - 24),
          reason: 'at the right edge, not floating in the middle of the bar');
      expect(
          find.descendant(
              of: find.byType(ReviewChip), matching: find.byType(Tooltip)),
          findsNothing,
          reason: 'it says what it is; a bubble on top is clutter');
    });

    tw('it is resized by its left edge, and the width is remembered',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await start(t, one(), mount: true, window: const Size(1600, 900));
      await look(t);
      await t.pump();
      app.toggleReview();
      await t.pumpAndSettle();
      expect(t.getSize(find.byType(ReviewPanel)).width, kReviewPanelDefault + 5);

      await t.drag(find.byKey(const ValueKey('review-resize')),
          const Offset(-100, 0));
      await t.pumpAndSettle();
      expect(app.reviewPanelW, kReviewPanelDefault + 100,
          reason: 'dragging left widens it: it is on the right');
      expect(repo.getSetting('reviewPanelW'), kReviewPanelDefault + 100);

      await t.drag(find.byKey(const ValueKey('review-resize')),
          const Offset(-900, 0));
      await t.pumpAndSettle();
      expect(app.reviewPanelW, kReviewPanelMax, reason: 'and stops somewhere');
      await t.drag(find.byKey(const ValueKey('review-resize')),
          const Offset(900, 0));
      await t.pumpAndSettle();
      expect(app.reviewPanelW, kReviewPanelMin);
    });

    tw('panel or sheet follows the room the page has, not the window',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The same window both times. With the navigator open the page column is
      // about 710 wide and cannot spare the panel; with it folded to its rail
      // there is room for both.
      await start(t, one(), mount: true, window: const Size(1000, 900));
      await look(t);
      await t.pump();
      app.toggleReview();
      await t.pumpAndSettle();
      expect(find.byType(ReviewSheet), findsOneWidget);
      expect(find.byType(ReviewPanel), findsNothing);

      app.toggleNavCollapsed();
      await t.pumpAndSettle();
      expect(find.byType(ReviewPanel), findsOneWidget,
          reason: 'the page now has the room: the window did not change');
      expect(find.byType(ReviewSheet), findsNothing);
    });
  });

  group('on a tall, narrow window', () {
    tw('it is a sheet over the lower half, with the kinds as tabs',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await start(
          t,
          [
            box('a', 100, 'Cells recieve signals. Their are three.'),
            box('b', 300, 'Done ,really.'),
          ],
          mount: true,
          window: const Size(1000, 1100));
      await look(t);
      await t.pump();
      await t.tap(find.byType(ReviewChip));
      await t.pumpAndSettle();

      expect(find.byType(ReviewSheet), findsOneWidget);
      expect(find.byType(ReviewPanel), findsNothing,
          reason: 'no side panel: the page keeps its width');
      expect(find.text('Spelling 1'), findsOneWidget);
      expect(find.text('Punctuation 1'), findsOneWidget);
      // One kind at a time, with its own Fix all.
      expect(find.text('SPELLING · 1'), findsOneWidget);
      expect(find.text('PUNCTUATION · 1'), findsNothing);

      // The top suggestion is open and its buttons are touch-sized.
      final accept = t.getSize(find.widgetWithText(FilledButton, 'Accept'));
      expect(accept.height, greaterThanOrEqualTo(36));

      await t.tap(find.text('Punctuation 1'));
      await t.pumpAndSettle();
      expect(find.text('PUNCTUATION · 1'), findsOneWidget);
      await t.tap(find.text('Fix all'));
      await t.pumpAndSettle();
      expect(textOf('b'), 'Done,really.');
      expect(find.text('SPELLING · 1'), findsOneWidget,
          reason: 'with that kind empty, the sheet moves to one that is not');

      // The page above is not covered: it shares the column with the sheet.
      final sheet = t.getRect(find.byType(ReviewSheet));
      final bar = t.getRect(find.textContaining('Sav').first);
      expect(sheet.bottom, lessThanOrEqualTo(bar.top + 1),
          reason: 'the sheet sits on the status bar, not under it');
    });

    tw('widening the window gives it back as a panel', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await start(t, [box('a', 100, 'Cells recieve signals.')],
          mount: true, window: const Size(1000, 1100));
      await look(t);
      await t.pump();
      app.toggleReview();
      await t.pumpAndSettle();
      expect(find.byType(ReviewSheet), findsOneWidget);
      t.view.physicalSize = const Size(1300, 900);
      await t.pumpAndSettle();
      expect(find.byType(ReviewSheet), findsNothing);
      expect(find.byType(ReviewPanel), findsOneWidget);
    });
  });

  // ── The real checker ──────────────────────────────────────────────────────

  tw('with the real checker: found, fixed, counted', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await start(t, [
      box('a', 100, 'I will recieve the parcel tomorrow.'),
    ]);
    await t.runAsync(() async {
      await OnoteText.warmUp(EnglishDialect.australian);
    });
    final real = WritingReview(app); // default checker
    addTearDown(real.dispose);
    await t.runAsync(real.refresh);
    expect(real.itemsOf(ReviewCategory.spelling).map((i) => i.finding.word),
        contains('recieve'));
    final item = real
        .itemsOf(ReviewCategory.spelling)
        .firstWhere((i) => i.finding.word == 'recieve');
    expect(item.firstChoice, 'receive');
    real.accept(item);
    expect(textOf('a'), 'I will receive the parcel tomorrow.');
  }, skip: !OnoteText.available);
}
