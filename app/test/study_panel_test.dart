// The study panel's motivation surface (P1), at the widget level.
//
// The v0.3 plan lists `study_panel` among the surfaces with no widget tests at
// all, and the last review made the case for why that matters: both bugs that
// shipped in the command bar were *layout* failures, invisible to every state
// test and to reading the code. This panel now renders a countdown, a progress
// bar and an activity strip inside a fixed 300px column, which is exactly the
// shape of thing that lays out fine in the author's window and nowhere else.
//
// So these tests assert what the student actually reads, and that it survives
// a narrow, short window.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/model/tags.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/study/flashcards.dart';
import 'package:openote/ui/study_panel.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  /// A notebook with [cards] Question cards on one page, ready to study.
  Future<AppState> newApp(WidgetTester tester, {int cards = 6}) async {
    late AppState app;
    late Repository repo;
    final tmp = Directory.systemTemp.createTempSync('onote_studypanel_');
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await tester.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Study');
      app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      final section =
          app.nodes.firstWhere((n) => n.kind == NodeKind.section).id;
      final page = app.importNode(
          nb.id,
          TreeNode(
              kind: NodeKind.page,
              parentId: section,
              title: 'Lecture 1',
              position: 'a001'));
      final blocks = <Block>[];
      for (var i = 0; i < cards; i++) {
        final b = Block(
            type: BlockType.text,
            x: 0,
            y: i * 40,
            content: {'text': 'What is $i?\n  Because $i.'});
        NoteTag.writeInto(b.content, [NoteTag(kind: TagKind.question, line: 0)]);
        blocks.add(b);
      }
      app.importPage(nb.id, page.id, blocks, PageProps());
      app.reloadNodes();
      await app.selectPage(page.id);
    });
    return app;
  }

  /// The panel as `AppShell` mounts it: a fixed-width column in a real window.
  /// [height] is deliberately settable — the overview grew a whole section
  /// below the fold, and "does it still fit on a laptop?" is the question.
  Widget host(AppState app, {double height = 720}) => MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: SizedBox(
            height: height,
            child: ListenableBuilder(
              listenable: app,
              builder: (_, __) => Row(children: [StudyPanel(app: app)]),
            ),
          ),
        ),
      );

  String? sectionOf(AppState app) => app.activeSectionId;

  /// Pump past the repository's 400ms debounced workspace write.
  ///
  /// Grading a card and setting an exam date both persist through
  /// `setSetting`, which coalesces bursts behind a timer. `pumpAndSettle`
  /// alone does not advance the clock when no frame is scheduled, so the timer
  /// would still be pending when the test ends — which the framework treats as
  /// a leak, correctly.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
  }

  testWidgets('the overview shows how much of the deck has been seen',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(tester);
    await tester.pumpWidget(host(app));
    await tester.pumpAndSettle();

    expect(find.text('SEEN'), findsOneWidget);
    expect(find.text('0 of 6'), findsOneWidget);

    // Grading two cards moves the progress line, and nothing else has to be
    // told about it.
    for (final c in app.study.deck().take(2)) {
      app.study.gradeCard(c.id, Grade.good);
    }
    await settle(tester);
    expect(find.text('2 of 6'), findsOneWidget);
  });

  testWidgets('the streak appears once you have studied at all',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(tester);
    await tester.pumpWidget(host(app));
    await tester.pumpAndSettle();

    // Nothing to boast about yet: a first-time user is not shown a row of
    // zeroes telling them they have done nothing.
    expect(find.byIcon(Icons.local_fire_department), findsNothing);

    app.study.gradeCard(app.study.deck().first.id, Grade.good);
    await settle(tester);
    expect(find.byIcon(Icons.local_fire_department), findsOneWidget);
    expect(find.text('1-day streak · 1 today'), findsOneWidget);
  });

  testWidgets('an exam date turns into a countdown and a daily target',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(tester);
    await tester.pumpWidget(host(app));
    await tester.pumpAndSettle();

    // Offered, not demanded, while there is no date.
    expect(find.text('Add an exam date'), findsOneWidget);

    final today = DateTime.now();
    app.study.setExamDate(
        sectionOf(app)!, DateTime(today.year, today.month, today.day + 3));
    await settle(tester);

    expect(find.text('3 days'), findsOneWidget);
    // Six unseen cards over three days, rounded up so the plan finishes.
    expect(find.textContaining('6 to learn'), findsOneWidget);
    expect(find.textContaining('2 a day'), findsOneWidget);
    expect(find.text('Add an exam date'), findsNothing);
  });

  testWidgets('an exam that has passed stays visible and removable',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(tester);
    await tester.pumpWidget(host(app));
    await tester.pumpAndSettle();

    final today = DateTime.now();
    final section = sectionOf(app)!;
    app.study.setExamDate(section, DateTime(today.year, today.month, today.day - 2));
    await settle(tester);

    // Vanishing silently would read as a bug; only the student knows whether
    // the date was wrong or the exam is simply over.
    expect(find.text('Exam 2 days ago'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove exam date'));
    await settle(tester);
    expect(app.study.examDate(section), isNull);
    expect(find.text('Add an exam date'), findsOneWidget);
  });

  // The failure mode this rules out is the one that shipped twice in the
  // command bar: content that overflows is clipped, and clipped pixels do not
  // hit-test. The panel scrolls, so the correct outcome is no overflow at any
  // height — including a laptop with a browser open beside it.
  testWidgets('the overview does not overflow a short window', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(tester, cards: 40);
    app.study.setExamDate(sectionOf(app)!, DateTime.now().add(const Duration(days: 9)));
    app.study.gradeCard(app.study.deck().first.id, Grade.good);

    for (final h in [480.0, 600.0, 900.0]) {
      await tester.pumpWidget(host(app, height: h));
      await settle(tester);
      expect(tester.takeException(), isNull,
          reason: 'the overview overflowed at ${h}px tall');
      expect(find.text('SEEN'), findsOneWidget);
    }
  });
}
