// The welcome flow, which is the only place that teaches the canvas itself.
//
// It used to be one text-only dialog about getting notes IN — sync, OneNote
// import, or start fresh — shown exactly once, ever, with no way back to it.
// Two things were wrong with that and both are asserted here: it never said
// what the app DOES (clicking anywhere and typing is the whole interaction,
// and nothing on an empty page hints at it), and "Skip" was permanent.
//
// The illustrations are painted, not written, so there is deliberately very
// little text to assert on — these tests are about the SHAPE: three steps,
// forwards and backwards, the last one closes, the starting points survive on
// it, and the animation SETTLES rather than looping (a repeating controller
// means `pumpAndSettle` never returns, which would take every test that opens
// this dialog down with it).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/onboarding.dart';
import 'package:openote/ui/settings_dialog.dart';

import 'support/app.dart';
import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Future<AppState> newApp(WidgetTester tester) async {
    late AppState app;
    late Repository repo;
    final tmp = Directory.systemTemp.createTempSync('onote_onboarding_');
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await tester.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Welcome');
      app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      await app.selectPage(
          app.nodes.where((n) => n.kind == NodeKind.page).first.id);
    });
    return app;
  }

  Future<void> mount(
    WidgetTester tester,
    AppState app,
    Future<void> Function(BuildContext, AppState) open, {
    Size window = const Size(1100, 780),
  }) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testApp(Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => open(context, app),
          child: const Text('open'),
        ),
      ),
    )));
    await tester.tap(find.text('open'));
    // Drains the debounced workspace write (400ms) as well as the dialog's
    // own entrance, so nothing is left pending — once on the way in, and
    // again after settling, since a dialog can arm that write during its own
    // first frames.
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 450));
  }

  testWidgets('the flow steps forward, back, and ends on the page',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(tester);
    await mount(tester, app, showOnboarding);

    // Step one is the canvas — the thing that was missing entirely.
    expect(find.text('The page is a canvas'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget,
        reason: 'the first step offers a way out, not a Back to nowhere');

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Maths and drawing, in with the words'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Your notes are a file you own'), findsOneWidget);
    // The last step keeps every starting point the original dialog had.
    expect(find.text('Sync with another device'), findsOneWidget);
    expect(find.text('Bring notes over from OneNote'), findsOneWidget);
    expect(find.text('Next'), findsNothing,
        reason: 'the last step ends the flow rather than dangling');

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Maths and drawing, in with the words'), findsOneWidget,
        reason: 'Back returns to the previous step, not out of the dialog');

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start writing'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing,
        reason: 'the flow ends by putting you on the page');
    expect(tester.takeException(), isNull);
  });

  // The starting-point cards used to put the main action AND a secondary
  // link on the same line as a paragraph, and the card is only ~450px wide
  // inside the dialog: at ordinary button sizes that is a 25px overflow, on
  // the one step a switcher has to read. The existing smoke test never saw it
  // because it only ever opened step one.
  testWidgets('the starting points lay out without overflowing',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(tester);
    await mount(tester, app, showOnboarding,
        window: const Size(900, 620));

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'the starting points overflowed their card');

    await tester.tap(find.text('How do I export?'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'and again with the export steps folded out');
  });

  // THE ONE THAT WOULD HANG THE SUITE. The canvas demonstration is an
  // animation because the thing it teaches is a sequence — but an animation
  // that repeats forever means the tree never settles, and `pumpAndSettle`
  // in every test that opens this dialog times out. It plays twice and rests.
  testWidgets('the canvas demonstration settles instead of looping',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(tester);
    await mount(tester, app, showOnboarding);

    // `mount` already settled once; if the controller were repeating, that
    // call would never have returned. Prove it again explicitly, then check
    // the picture is still the finished one rather than a blank frame.
    await tester.pumpAndSettle();
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('The page is a canvas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the OneNote export steps fold out on the last step',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(tester);
    await mount(tester, app, showOnboarding);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Exporting from OneNote'), findsNothing);
    await tester.tap(find.text('How do I export?'));
    await tester.pumpAndSettle();
    expect(find.text('Exporting from OneNote'), findsOneWidget,
        reason: 'the step people get stuck on is spelled out on request');
    expect(tester.takeException(), isNull);
  });

  // Skipping used to be permanent: the flow was shown once, on a first run
  // that had already been stamped by the time you decided you wanted it.
  testWidgets('Settings can reopen the flow after it has been seen',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(tester);
    app.markOnboardingSeen();
    await mount(tester, app, showSettingsDialog);

    expect(find.text('Welcome tour'), findsOneWidget,
        reason: 'a door back in is what makes "Skip" a fair offer');
    // By its own icon: Settings stacks several identical "Open…" buttons,
    // and the first of them is Sync.
    await tester.tap(find.ancestor(
        of: find.byIcon(Icons.school_outlined),
        matching: find.byType(TextButton)));
    await tester.pumpAndSettle();
    expect(find.text('The page is a canvas'), findsOneWidget,
        reason: 'the tour really reopens, seen or not');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a workspace that has been used is not greeted as a beginner',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(tester);
    app.markOnboardingSeen();
    await mount(tester, app, maybeShowOnboarding);

    expect(find.text('The page is a canvas'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
