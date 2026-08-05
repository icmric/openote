// The Planner panel at the widget level.
//
// The state layer is covered in `planner_state_test.dart`; this is the half
// that only fails on screen. The precedent is the command bar, where both bugs
// that shipped were *layout* failures invisible to every state test and to
// reading the code — and this panel packs an agenda, a month grid, a catch-up
// banner and a footer into a fixed 320px column.
//
// What is asserted is what the student reads: that a date they set appears
// without them navigating to the thing it belongs to (which is the entire
// complaint this feature answers), that overdue work is not quietly hidden,
// that a calendar row does not offer an edit that cannot work, and that none of
// it overflows a small window.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/model/tags.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/markdown/md_render.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/study/study_stats.dart';
import 'package:openote/ui/planner_panel.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  /// A notebook with one section and a page of two to-do lines.
  Future<(AppState, String)> newApp(WidgetTester tester) async {
    late AppState app;
    late Repository repo;
    late String section;
    final tmp = Directory.systemTemp.createTempSync('onote_plannerpanel_');
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await tester.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Planner');
      app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      section = app.nodes.firstWhere((n) => n.kind == NodeKind.section).id;
      final page = app.importNode(
          nb.id,
          TreeNode(
              kind: NodeKind.page,
              parentId: section,
              title: 'Week 3',
              position: 'a001'));
      final b = Block(
          type: BlockType.text,
          x: 0,
          y: 0,
          content: {'text': 'Finish tutorial 4\nDraft the report'});
      NoteTag.writeInto(b.content, [
        NoteTag(kind: TagKind.todo, line: 0, checked: false),
        NoteTag(kind: TagKind.todo, line: 1, checked: false),
      ]);
      app.importPage(nb.id, page.id, [b], PageProps());
      app.reloadNodes();
      await app.selectPage(page.id);
    });
    return (app, section);
  }

  /// The panel as `AppShell` mounts it: a fixed-width column in a real window.
  Widget host(AppState app, {double height = 720}) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: height,
            child: ListenableBuilder(
              listenable: app,
              builder: (_, __) => Row(children: [PlannerPanel(app: app)]),
            ),
          ),
        ),
      );

  /// Past both debounces, twice, because they **chain**: `markDirty` schedules
  /// a 700ms autosave, and the save then calls `_persistSession`, which
  /// schedules the repository's own 400ms workspace write. One pump clears the
  /// first and leaves the second pending — which the framework treats as a
  /// leak, correctly.
  ///
  /// `pumpAndSettle` cannot do this on its own: it does not advance the clock
  /// when no frame is scheduled, and neither timer schedules one.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 2; i++) {
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('an empty planner offers a way out of being empty',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, _) = await newApp(tester);
    await tester.pumpWidget(host(app));
    await tester.pumpAndSettle();

    expect(find.text('PLANNER'), findsOneWidget);
    expect(find.text('Nothing dated yet.'), findsOneWidget);
    // Never a dead end — the rule the study panel was rebuilt around.
    expect(find.text('Set an exam date'), findsOneWidget);
    expect(find.text('Add a reminder'), findsOneWidget);
    expect(find.text('Subscribe to a timetable'), findsOneWidget);
  });

  testWidgets('an exam date is visible without opening the section it is on',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, section) = await newApp(tester);
    await tester.pumpWidget(host(app));
    await tester.pumpAndSettle();

    final title = app.nodes.firstWhere((n) => n.id == section).title;
    app.study.setExamDate(
        section, DateTime.now().add(const Duration(days: 14)));
    await settle(tester);

    // This is the whole complaint: before the planner, that date could only be
    // read from inside the study panel, on the section you happened to be on.
    expect(find.text(title), findsOneWidget);
    expect(find.text('LATER'), findsOneWidget);
  });

  testWidgets('a missed deadline is shown, not quietly dropped',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, _) = await newApp(tester);
    await tester.pumpWidget(host(app));
    await tester.pumpAndSettle();

    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    app.setTagDue(app.blocks.single.id, 0, TagKind.todo, yesterday);
    await settle(tester);

    expect(find.text('OVERDUE'), findsOneWidget);
    expect(find.text('Finish tutorial 4'), findsOneWidget);
    expect(find.text('yesterday'), findsOneWidget);
  });

  testWidgets('ticking a task in the planner ticks it in the note',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, _) = await newApp(tester);
    await tester.pumpWidget(host(app));
    await tester.pumpAndSettle();

    app.setTagDue(app.blocks.single.id, 0, TagKind.todo, DateTime.now());
    await settle(tester);
    expect(find.byType(Checkbox), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await settle(tester);

    // The agenda is a lens: there is one truth, and it is the tag.
    final tag = NoteTag.listFrom(app.blocks.single.content)
        .firstWhere((t) => t.line == 0);
    expect(tag.checked, isTrue);
  });

  testWidgets('a calendar row says it is read-only rather than offering an edit',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, _) = await newApp(tester);
    final tmp = Directory.systemTemp.createTempSync('onote_plannerics_');
    addTearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final start = DateTime.now().add(const Duration(days: 2));
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${start.year}${two(start.month)}${two(start.day)}T090000';
    final ics = File('${tmp.path}/t.ics')
      ..writeAsStringSync('BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\n'
          'UID:e1\r\nSUMMARY:Discrete Maths lecture\r\n'
          'DTSTART:$stamp\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n');
    await tester.runAsync(() => app.planner.subscribeCalendar(ics.path));
    await tester.pumpWidget(host(app));
    await settle(tester);

    // Two: the agenda row, and the "up next" strip above it (v0.8 §2). The
    // strip is not right-clickable, so the row is the LAST of the two — the
    // strip is rendered above the list.
    final titles = find.text('Discrete Maths lecture');
    expect(titles, findsNWidgets(2));

    await tester.tapAt(tester.getCenter(titles.last),
        buttons: 2 /* secondary */);
    await tester.pumpAndSettle();
    expect(find.text('From your calendar — read-only'), findsOneWidget);
    expect(find.text('Clear the date'), findsNothing);

    await tester.tapAt(const Offset(700, 20)); // dismiss the menu
    await tester.pumpAndSettle();
  });

  testWidgets('the month grid marks days that have something on them',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, section) = await newApp(tester);
    app.study.setExamDate(section, DateTime.now().add(const Duration(days: 3)));
    await tester.pumpWidget(host(app));
    await settle(tester);

    // Off by default: the agenda is what a student reads daily, and a grid is
    // a lot of layout before any of it (v0.5 §4).
    expect(find.byTooltip('Show the month'), findsOneWidget);
    await tester.tap(find.byTooltip('Show the month'));
    await settle(tester);

    expect(find.byTooltip('Show the list'), findsOneWidget);
    expect(find.byTooltip('Next month'), findsOneWidget);
    // Monday-start weekday header.
    expect(find.text('W'), findsOneWidget);
  });

  // A deadline visible only inside the planner would be a fact about a line
  // that the line itself does not show — so you would have to remember to go
  // and look, which is the failure the planner exists to fix.
  group('the deadline shows in the note too', () {
    Widget note(Map<int, List<NoteTag>> tags) => MaterialApp(
          home: Scaffold(
            body: MarkdownView(
              text: 'Finish tutorial 4',
              baseStyle: const TextStyle(fontSize: 14),
              tagsByLine: tags,
            ),
          ),
        );

    testWidgets('a date this week reads as a weekday', (tester) async {
      final due = DateTime.now().add(const Duration(days: 3));
      await tester.pumpWidget(note({
        0: [
          NoteTag(
              kind: TagKind.todo,
              line: 0,
              checked: false,
              due: dayKey(due))
        ]
      }));
      await tester.pumpAndSettle();
      const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      expect(find.text(names[due.weekday - 1]), findsOneWidget);
    });

    testWidgets('an undated tag adds nothing to the gutter', (tester) async {
      await tester.pumpWidget(note({
        0: [NoteTag(kind: TagKind.todo, line: 0, checked: false)]
      }));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNothing); // the gutter uses an icon
      expect(find.text('today'), findsNothing);
      expect(find.text('tomorrow'), findsNothing);
    });

    testWidgets('an overdue one says so', (tester) async {
      final due = DateTime.now().subtract(const Duration(days: 1));
      await tester.pumpWidget(note({
        0: [NoteTag(kind: TagKind.todo, line: 0, due: dayKey(due))]
      }));
      await tester.pumpAndSettle();
      expect(find.text('yesterday'), findsOneWidget);
    });
  });

  testWidgets('it survives a short, narrow window without overflowing',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, section) = await newApp(tester);
    tester.view.physicalSize = const Size(900, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    app.study.setExamDate(section, now.add(const Duration(days: 9)));
    app.setTagDue(app.blocks.single.id, 0, TagKind.todo,
        now.subtract(const Duration(days: 2)));
    app.setTagDue(app.blocks.single.id, 1, TagKind.todo, now);
    app.planner.reminders
        .add(text: 'Re-read the proof of 2.7', at: now, id: 'r1');

    await tester.pumpWidget(host(app, height: 560));
    await settle(tester);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Show the month'));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });
}
