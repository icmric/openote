// Field report: mouse clicks on sidebar pages/sections take ~half a
// second to act, hotkeys are instant, hover feedback is missing. That
// combination smells like tap-gesture resolution being DEFERRED (a
// competing recognizer holding the arena). This probe taps a page tile
// and asks: does selectPage fire on pointer-up, or only after a timeout?
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('a sidebar page click acts on pointer-up, not on a timeout',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    AppState.syncLogEnabled = false;
    late Directory tmp;
    late Repository repo;
    late AppState app;
    late List<String> pageIds;
    await tester.runAsync(() async {
      tmp = Directory.systemTemp.createTempSync('onote_tap_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('T');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      final section =
          app.nodes.firstWhere((n) => n.kind == NodeKind.section);
      pageIds = [
        for (var p = 0; p < 3; p++)
          app
              .importNode(
                  nb.id,
                  TreeNode(
                      kind: NodeKind.page,
                      parentId: section.id,
                      title: 'Target page $p',
                      position: 'a$p'))
              .id
      ];
      app.reloadNodes();
      await app.selectPage(pageIds[0]);
    });
    app.markOnboardingSeen();

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      theme: onoteTheme(Brightness.light),
      home: AppShell(app: app),
    ));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();

    // Tap page 1's tile, then give ONLY ONE 16ms frame — no timeouts.
    final tile = find.text('Target page 1');
    expect(tile, findsOneWidget);
    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 16));
    final actedImmediately = app.pageId == pageIds[1];

    // Now allow timeouts to expire and see if it acts LATE.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    final actedEventually = app.pageId == pageIds[1];

    // ignore: avoid_print
    print('TAPPROBE immediate=$actedImmediately eventual=$actedEventually');
    expect(actedEventually, isTrue, reason: 'the click must work at all');
    expect(actedImmediately, isTrue,
        reason: 'selectPage must fire on pointer-up — a click that acts '
            'only after a gesture timeout is the half-second Eric feels');

    // The affordance the deferral was paying for must still exist: two
    // quick clicks open the inline rename (first click selects — the
    // file-explorer behaviour).
    //
    // The clock is DRIVEN, not waited on. The gate measures wall-clock time
    // and `tester.pump(Duration)` moves only the fake clock, so left alone
    // this asserted that the machine could rebuild the sidebar between two
    // taps in under 300 ms — true on a fast machine, false on a slower one,
    // and nothing to do with the code under test. Here the two clicks are 80 ms
    // apart by construction.
    var fake = DateTime(2026, 8, 10, 12);
    sidebarNow = () => fake;
    addTearDown(() => sidebarNow = DateTime.now);

    // .first = the sidebar tile; the open page paints its title on the
    // canvas too after the first click selects it.
    await tester.tap(find.text('Target page 2').first);
    await tester.pump(const Duration(milliseconds: 80));
    fake = fake.add(const Duration(milliseconds: 80));
    await tester.tap(find.text('Target page 2').first);
    await tester.pumpAndSettle();
    // The navigator always holds ONE TextField (the search box); the
    // inline rename editor makes it two.
    expect(
        find.descendant(
            of: find.byType(Sidebar), matching: find.byType(TextField)),
        findsNWidgets(2),
        reason: 'double-click still renames');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    AppState.syncLogEnabled = true;
  });
}
