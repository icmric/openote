// A first import is a different situation from every later one.
//
// Reported: "as it creates a blank notebook its easy to think that its just
// doing nothing/it failed. This needs to be far clearer on all first imports
// (i.e. when importing and there is no existing notebook)".
//
// The import creates the notebook empty and opens it straight away, which is
// right — it is what lets somebody watch their pages arrive. But on a first
// run that means staring at an empty notebook with a modest card away in one
// corner, and the natural reading of that is that nothing happened.
//
// So a first import explains itself in the middle of the notebook it is
// filling, and every later one keeps the corner card. What must NOT change is
// that either way the app stays usable: the panel is not a modal, because a
// modal would put back the wait that importing in the background removed.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/export/import_job.dart';
import 'package:openote/export/import_status.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/import_progress.dart';

import 'support/app.dart';
import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());
  tearDown(() => ImportJob.current = null);

  /// Opening a repository is real file and SQLite work, and a widget test
  /// runs on a fake clock — so it has to happen inside `runAsync` or it waits
  /// for a timer that will never fire.
  Future<AppState> fixture(WidgetTester tester, String name) async {
    late AppState app;
    late Repository repo;
    final tmp = Directory.systemTemp.createTempSync(name);
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await tester.runAsync(() async {
      repo = await Repository.openAt(tmp);
      app = AppState(repo);
    });
    return app;
  }

  Future<void> pump(WidgetTester tester, AppState app) async {
    // Through the shared helper: it installs the localisation delegates the
    // real app installs, and a bare MaterialApp without them wedges any
    // surface that reads its words from the .arb.
    await tester.pumpWidget(testApp(Scaffold(
      body: Stack(children: [ImportProgressCard(app: app)]),
    )));
    await tester.pump();
  }

  testWidgets('a first import explains itself where the person is looking',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await fixture(tester, 'onote_firstimport_');

    final job = ImportJob.debugCreate(app, 'Computing Science')
      ..isFirstNotebook = true
      ..pagesDone = 12
      ..pagesTotal = 332
      ..message = 'Bringing in "Week 1" — 12 of 332 pages…';
    ImportJob.current = job;
    await pump(tester, app);

    expect(find.text('Bringing your notes over'), findsOneWidget);
    expect(find.text('12 of 332 pages'), findsOneWidget);
    // The sentence that stops somebody sitting and watching a bar.
    expect(
        find.textContaining('no need to wait here', findRichText: true),
        findsOneWidget);
    // And a way to make it go away that does NOT stop the import.
    expect(find.text('Keep importing, hide this'), findsOneWidget);
  });

  testWidgets('the panel is not a modal — it dismisses without stopping',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await fixture(tester, 'onote_firstimport_bg_');

    final job = ImportJob.debugCreate(app, 'Computing Science')
      ..isFirstNotebook = true
      ..pagesTotal = 10;
    ImportJob.current = job;
    await pump(tester, app);

    await tester.tap(find.text('Keep importing, hide this'));
    await tester.pump();

    expect(ImportJob.current, isNull, reason: 'the panel is gone');
    expect(job.state, isNot(ImportJobState.cancelled),
        reason: 'dismissing the explanation must not stop the import');
  });

  testWidgets("the card speaks the reader's language", (tester) async {
    // The import card was the last English-only surface in an app that ships
    // in seven languages — and it is the FIRST thing a switcher sees, so a
    // German student picking their notebook out of OneNote watched the whole
    // thing happen in English.
    //
    // The cause was structural rather than an oversight: ImportJob is a
    // ChangeNotifier with no BuildContext, so it could not reach L, so every
    // sentence had to be built where there was no way to say it in anybody's
    // language. It reports a stage and some numbers now, and the card does the
    // wording.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await fixture(tester, 'onote_import_l10n_');

    final job = ImportJob.debugCreate(app, 'Computing Science')
      ..isFirstNotebook = true
      ..pagesDone = 12
      ..pagesTotal = 332
      ..status = const ImportStatus(ImportStage.bringingIn,
          name: 'Week 1', count: 12, total: 332);
    ImportJob.current = job;

    await tester.pumpWidget(testApp(
      Scaffold(body: Stack(children: [ImportProgressCard(app: app)])),
      locale: const Locale('de'),
    ));
    await tester.pump();

    expect(find.textContaining('Week 1'), findsOneWidget,
        reason: "the section name is the user's own and is not translated");
    expect(find.textContaining('übertragen'), findsOneWidget,
        reason: 'but the sentence around it is');
    // And the English fallback is still there for anything without a context.
    expect(job.message, isNotEmpty);
  });

  testWidgets('a later import keeps the small corner card', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await fixture(tester, 'onote_laterimport_');

    final job = ImportJob.debugCreate(app, 'Second Notebook')
      ..isFirstNotebook = false
      ..pagesTotal = 10;
    ImportJob.current = job;
    await pump(tester, app);

    expect(find.text('Bringing your notes over'), findsNothing);
    expect(find.textContaining('Importing'), findsOneWidget);
  });

  testWidgets('once it has finished, the big panel gets out of the way',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await fixture(tester, 'onote_firstimport_done_');

    final job = ImportJob.debugCreate(app, 'Computing Science')
      ..isFirstNotebook = true
      ..state = ImportJobState.done
      ..message = 'Imported 332 pages.';
    ImportJob.current = job;
    await pump(tester, app);

    // A finished import has a notebook to show for itself; the explanation
    // has done its job and the result belongs in the corner with its
    // Open button.
    expect(find.text('Bringing your notes over'), findsNothing);
    expect(find.text('Notebook ready'), findsOneWidget);
  });
}
