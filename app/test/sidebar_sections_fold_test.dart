// Folding the sections column away, and what that buys.
//
// The owner: *"i want to be able to colapse the section bar to provide extra
// space"*. The navigator already had a collapse — `navCollapsed`, which folds
// the WHOLE thing to a 44px rail — and it is not this: it takes the page list
// with it, and the page list is what you are reading while you write.
//
// So the test that matters is not "does the column disappear" but "does the
// navigator give the width back", because the extra space is the entire point.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/app_shell.dart';
import 'package:openote/ui/sidebar.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;

  Future<void> shell(WidgetTester tester) async {
    AppState.syncLogEnabled = false;
    await tester.runAsync(() async {
      tmp = Directory.systemTemp.createTempSync('onote_fold_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Fold');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
      final page = app.importNode(
          nb.id,
          TreeNode(
              kind: NodeKind.page,
              parentId: section.id,
              title: 'A page',
              position: 'a0'));
      app.importPage(nb.id, page.id, [], PageProps());
      app.reloadNodes();
      await app.selectPage(page.id);
    });
    app.markOnboardingSeen();
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() {
      AppState.syncLogEnabled = true;
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      theme: onoteTheme(Brightness.light),
      home: AppShell(app: app),
    ));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
  }

  /// Long enough for the 400ms workspace save `setSetting` arms. Left to
  /// fire rather than cancelled: writing the preference down is half of what
  /// folding the column means.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  double navWidth(WidgetTester tester) =>
      tester.getSize(find.byType(Sidebar)).width;

  /// The "Home" row at the top of the sections column.
  final homeTile = find.descendant(
      of: find.byType(Sidebar), matching: find.text('Home'));

  testWidgets('the sections column folds away, and the navigator narrows',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(tester);

    // "Home" lives in the sections column and nowhere else in the
    // navigator, so it is the honest marker for whether that column is on
    // screen. Scoped to the Sidebar because the shell draws more than one
    // thing that says it.
    expect(homeTile, findsOneWidget);
    expect(find.text('A page'), findsWidgets,
        reason: 'the page list is the half you are reading while you write');
    final wide = navWidth(tester);

    app.toggleNavSectionsCollapsed();
    await settle(tester);

    expect(homeTile, findsNothing, reason: 'the column is gone');
    expect(find.text('A page'), findsWidgets,
        reason: 'and the page list emphatically is not — that is the whole '
            'difference between this and `navCollapsed`');
    expect(navWidth(tester), lessThan(wide - 90),
        reason: 'the width the column was spending goes back to the page, '
            'which is the extra space that was asked for');
  });

  testWidgets('and the button that does it is on screen either way',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(tester);

    Future<void> press(String tip) async {
      final b = find.byTooltip(tip);
      expect(b, findsOneWidget, reason: tip);
      await tester.tap(b);
      await settle(tester);
    }

    await press('Hide the section list');
    expect(app.navSectionsCollapsed, isTrue);
    expect(homeTile, findsNothing);

    // The button has to still be findable, or folding the sections away is a
    // one-way door. It is in the footer for exactly this reason: the pages
    // pane's own header is not drawn on Home.
    await press('Show the section list');
    expect(app.navSectionsCollapsed, isFalse);
    expect(homeTile, findsOneWidget);
  });

  testWidgets('it stays folded across a restart', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(tester);
    app.toggleNavSectionsCollapsed();
    await settle(tester);
    expect(repo.getSetting('navSectionsCollapsed'), true,
        reason: 'folded is a preference, not a mood');
  });

  testWidgets('folded on Home too, where the pages header does not exist',
      (tester) async {
    // The reason the button is in the footer rather than beside the section
    // name. Home replaces the whole pages pane, header and all.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(tester);
    app.openHome();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Hide the section list'), findsOneWidget);
    await tester.tap(find.byTooltip('Hide the section list'));
    await settle(tester);
    expect(find.byTooltip('Show the section list'), findsOneWidget,
        reason: 'still a way back, with the sections column gone AND the '
            'pages pane replaced');
  });
}
