// Three toolbar buttons become one, and the panel switches between them.
//
// The owner: *"I think we can probably combine page tags, outline, and linked
// to/from into a single button up there to reduce clutter. Some sort of page
// overview thing. think about how to thoughtfully implement that and if that
// is actually the best option or if we should do it in some other way."*
//
// The thinking, written down because the alternatives are not obviously
// worse:
//
//   * **One panel with three tabs inside it** — chosen. They are one question
//     asked three ways (what is on this page, and what is it attached to),
//     and three toggles in the toolbar made you answer it before you had
//     asked. Landing on one and moving is a step taken having already seen
//     something.
//   * **A menu on the button.** Rejected: it costs a click on the way IN for
//     every use, to save a click nobody was spending — and a menu cannot show
//     you that the outline is empty, which is often the answer.
//   * **One merged panel showing all three at once.** Rejected: the outline
//     of a long page is already taller than the panel, so the other two would
//     be below the fold, which is where they are now.
//
// The switcher is in the panel HEADER rather than a strip below it, because
// the panel already has one row of chrome and a second would take the height
// from the content, which is the thing in short supply.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/command_bar.dart';

import 'support/app.dart';
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
    tmp = Directory.systemTemp.createTempSync('onote_overview_');
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

  group('the button', () {
    Future<void> bar(WidgetTester tester) async {
      tester.view.physicalSize = const Size(2600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(testApp(Scaffold(
        body: ListenableBuilder(
          listenable: app,
          builder: (_, __) => CommandBar(app: app),
        ),
      )));
      await tester.pumpAndSettle();
    }

    testWidgets('opens the outline the first time', (tester) async {
      // The only one of the three that is never empty on a page with anything
      // written on it, so it is the right thing to land on before anyone has
      // said what they wanted.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await bar(tester);

      await tester.tap(find.byTooltip('Page overview'));
      await tester.pumpAndSettle();
      expect(app.openPanel, SidePanelKind.outline);
      expect(app.showPageOverview, isTrue);
    });

    testWidgets('and closes what it opened', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await bar(tester);

      await tester.tap(find.byTooltip('Page overview'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Page overview'));
      await tester.pumpAndSettle();
      expect(app.openPanel, isNull);
    });

    testWidgets('it comes back where you left it', (tester) async {
      // Within a sitting: somebody working through a page's links closes the
      // panel to look at something and reopens it expecting the links.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await bar(tester);
      app.showPageOverviewAs(SidePanelKind.links);
      app.closePanel();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Page overview'));
      await tester.pumpAndSettle();
      expect(app.openPanel, SidePanelKind.links);
    });

    testWidgets('there is exactly one of it', (tester) async {
      // The point of the exercise. Three toggles were three answers offered
      // before the question had been asked.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await bar(tester);
      expect(find.byTooltip('Page overview'), findsOneWidget);
      for (final gone in ['Find tags', 'Page outline', 'Links & backlinks']) {
        expect(find.byTooltip(gone), findsNothing, reason: gone);
      }
    });
  });

  group('the state', () {
    test('a panel that is not one of the three is not the overview', () {
      final a = AppState(_NoopRepo());
      a.showPanel(SidePanelKind.study);
      expect(a.showPageOverview, isFalse);
      expect(a.pageOverviewKind, SidePanelKind.outline,
          reason: 'and opening an unrelated panel does not move the memory');
    });

    test('every one of the three is reachable and remembered', () {
      final a = AppState(_NoopRepo());
      for (final kind in AppState.pageOverviewKinds) {
        a.showPageOverviewAs(kind);
        expect(a.openPanel, kind);
        expect(a.pageOverviewKind, kind);
        expect(a.showPageOverview, isTrue);
      }
    });
  });
}

class _NoopRepo implements Repository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
