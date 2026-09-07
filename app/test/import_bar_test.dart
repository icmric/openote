// The strip above the page that says a notebook is filling up.
//
// The owner, after a successful import: "please make that import popup a bit
// clearer since its so easy to miss at the moment and people might think
// nothing is happening. Have a think about the best way to do this, ideally
// not super intrusive but also needs to be very clear."
//
// The two halves of that pull apart, and the resolution is *where* rather than
// *how loud*. The card is bottom-left and 360px wide; somebody watching the
// middle of a large screen for their notes to appear can miss it entirely, and
// what they conclude is that nothing is happening. A louder card is still in
// the corner. So the news goes where they are already looking — one line above
// the page, in the content column, stealing no focus and covering nothing.
//
// It is the same strip that already says a notebook is unfinished. One place,
// one shape, two things it can say — a second vocabulary for the same idea
// would be the intrusion the owner was warning about.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/export/import_job.dart';
import 'package:openote/export/import_status.dart';
import 'package:openote/onenote/unfinished_import.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/unfinished_import_bar.dart';

import 'support/app.dart';
import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());
  tearDown(() => ImportJob.current = null);

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
      final nb = await repo.createNotebook('Computing Science');
      app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
    });
    return app;
  }

  Future<void> pump(WidgetTester tester, AppState app) async {
    await tester.pumpWidget(
        testApp(Scaffold(body: UnfinishedImportBar(app: app))));
    await tester.pump();
  }

  testWidgets('a running import says so above the page, with a count',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await fixture(tester, 'onote_bar_running_');

    ImportJob.current = ImportJob.debugCreate(app, 'Computing Science')
      ..notebookId = app.notebookId
      ..pagesDone = 42
      ..pagesTotal = 332
      ..status = const ImportStatus(ImportStage.bringingIn,
          name: 'Week 1', count: 42, total: 332);
    await pump(tester, app);

    expect(find.text('42 / 332'), findsOneWidget);
    expect(find.textContaining('Week 1'), findsOneWidget);
    // Movement, not just words: a bar that is filling says "working" to
    // somebody who has not read anything yet.
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('before the total is known it still says something is happening',
      (tester) async {
    // The stretch the complaint is really about: minutes with nothing on the
    // page yet. An indeterminate bar reads as "working", where an empty one
    // reads as "nothing".
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await fixture(tester, 'onote_bar_early_');

    ImportJob.current = ImportJob.debugCreate(app, 'Computing Science')
      ..notebookId = app.notebookId
      ..status = const ImportStatus(ImportStage.lookingAround);
    await pump(tester, app);

    final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator));
    expect(bar.value, isNull, reason: 'indeterminate, not empty');
    expect(find.textContaining('Looking through'), findsOneWidget);
  });

  testWidgets('it offers no buttons of its own while running', (tester) async {
    // Every action for a running import lives on the card. Two places
    // offering the same Stop is how somebody presses the wrong one.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await fixture(tester, 'onote_bar_nobuttons_');

    ImportJob.current = ImportJob.debugCreate(app, 'Computing Science')
      ..notebookId = app.notebookId
      ..pagesTotal = 10;
    await pump(tester, app);

    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('an import into ANOTHER notebook does not appear on this one',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await fixture(tester, 'onote_bar_other_');

    ImportJob.current = ImportJob.debugCreate(app, 'Somewhere else')
      ..notebookId = 'a-different-notebook'
      ..pagesTotal = 10;
    await pump(tester, app);

    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('when it is over, the strip goes back to the unfinished notice',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await fixture(tester, 'onote_bar_after_');
    app.recordUnfinishedImport(
      app.notebookId!,
      UnfinishedImport(
        graphNotebookId: 'NB',
        notebookName: 'Computing Science',
        pagesDone: 152,
        pagesTotal: 332,
        donePageIds: const [],
        linkMap: const {},
        reason: UnfinishedReason.throttled,
        lastTryMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await pump(tester, app);

    expect(find.textContaining('180 pages to go'), findsOneWidget);
    expect(find.text('Finish now'), findsOneWidget);

    // Writing the record arms the debounced workspace save; drain it or the
    // test ends holding a timer and fails on that instead.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 900));
  });
}
