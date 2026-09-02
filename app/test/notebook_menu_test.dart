// The notebook bar must open the ONE notebook surface.
//
// Regression guard for the "two different menus for one thing" report: there
// used to be a dropdown (switching) *and* a manager panel (everything else).
// Tapping the bar now opens the manager, which both switches and manages, so
// there is exactly one surface — and no `MenuAnchor` left in the navigator's
// notebook area to reintroduce the second one.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/sidebar.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  testWidgets('tapping the notebook bar opens the single notebook surface',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');

    late Repository repo;
    late AppState app;
    final tmp = Directory.systemTemp.createTempSync('onote_menu_');
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await tester.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final a = await repo.createNotebook('Alpha');
      await repo.createNotebook('Beta');
      app = AppState(repo)..notebookId = a.id;
      app.nodes = repo.loadNodes(a.id);
      app.activeSectionId =
          app.nodes.firstWhere((n) => n.kind == NodeKind.section).id;
    });

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: Scaffold(body: Sidebar(app: app)),
    ));
    await tester.pumpAndSettle();

    // Exactly one notebook affordance, and it is not a dropdown menu.
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.byType(MenuAnchor), findsNothing,
        reason: 'the notebook dropdown was replaced by the manager');

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    // The manager is open: it lists BOTH notebooks (so it can switch) and offers
    // the management actions (so it is the single surface).
    expect(find.text('Notebooks'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });
}
