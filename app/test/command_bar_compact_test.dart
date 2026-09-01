// The command bar's own trailing cluster compacts, instead of scrolling
// (UI consistency pass, 2026-09-01).
//
// Reported: "it doesnt handle resizing well (menus should either compact as
// required or become sliding, again i belive the former is cleaner)." The
// generic mechanics are covered by compacting_toolbar_test.dart; these are
// the tests that would have caught the WIRING into the real command bar
// specifically being wrong — the right controls folding, the folded ones
// still doing the same thing, and nothing else on the row moving.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/command_bar.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_cmdbar_');
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

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: app,
          builder: (_, __) => CommandBar(app: app),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a wide window shows every trailing control inline, no fold',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(tester, const Size(2600, 1200));
    // Study and Planner carry their OWN dynamic tooltip text (how many
    // cards are due, etc.) rather than a fixed string, so they are found
    // by icon here — everything else has a fixed tooltip message.
    expect(find.byIcon(Icons.school_outlined), findsOneWidget, reason: 'Study');
    expect(find.byIcon(Icons.event_note_outlined), findsOneWidget,
        reason: 'Planner');
    for (final tip in const [
      'Find tags',
      'Page outline',
      'Links & backlinks',
      'Export page…',
      'Settings…',
    ]) {
      expect(find.byTooltip(tip), findsOneWidget, reason: tip);
    }
    expect(find.byTooltip('More'), findsNothing,
        reason: 'a fold button folding nothing is worse than none');
    app.cancelPendingSave();
  });

  testWidgets(
      'a narrow window folds the lowest-priority controls into More, '
      'not off screen', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // Narrow enough to force a fold, wide enough that this is a realistic
    // "laptop with the navigator open" window, not a pathological one.
    await pump(tester, const Size(700, 900));

    expect(find.byTooltip('More'), findsOneWidget,
        reason: 'the trailing cluster does not fit at 700px — something '
            'has to fold, or a wider net regression than this test caught '
            'it');

    // Whatever folded is REACHABLE from More, not simply gone.
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsWidgets);
    app.cancelPendingSave();
  });

  testWidgets('a folded Settings still opens the real settings dialog',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(tester, const Size(700, 900));
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();

    final settings = find.widgetWithText(MenuItemButton, 'Settings');
    // Fall through gracefully if Settings happens to still be inline on
    // whatever platform/font metrics this runs under — the point of this
    // test is "if it folds, it still works", not pinning the exact pixel
    // threshold a font substitution could nudge.
    if (settings.evaluate().isEmpty) {
      expect(find.byTooltip('Settings…'), findsOneWidget);
      return;
    }
    final onPressed = tester.widget<MenuItemButton>(settings).onPressed;
    expect(onPressed, isNotNull);
    onPressed!();
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.text('Settings')),
        findsOneWidget,
        reason: 'the SAME dialog the inline button opens');
  });

  testWidgets('folding the trailing cluster leaves the tabs and Home row '
      'exactly where they were', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(tester, const Size(2600, 1200));
    final wideTabLeft = tester.getTopLeft(find.text('Home')).dx;

    await pump(tester, const Size(700, 900));
    final narrowTabLeft = tester.getTopLeft(find.text('Home')).dx;

    expect(narrowTabLeft, wideTabLeft,
        reason: 'folding the trailing cluster must not shove the tabs, '
            'which sit at the OPPOSITE end of the same row');
    app.cancelPendingSave();
  });
}
