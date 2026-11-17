// On a phone the page gets the screen: notebook, section and page are chosen in
// a drawer, nothing sits under the status bar or the gesture bar, and wider
// windows are untouched.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/app_shell.dart';
import 'package:openote/ui/notebook_manager.dart';
import 'package:openote/ui/phone_shell.dart';
import 'package:openote/ui/sidebar.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;

  Future<void> shell(WidgetTester t, Size size,
      {FakeViewPadding padding = FakeViewPadding.zero}) async {
    AppState.syncLogEnabled = false;
    await t.runAsync(() async {
      tmp = Directory.systemTemp.createTempSync('onote_phone_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Phone');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      await app.addSection();
      app.reloadNodes();
      await app.selectPage(
          app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
    });
    app.markOnboardingSeen();
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    t.view.padding = padding;
    t.view.viewPadding = padding;
    addTearDown(t.view.reset);
    addTearDown(() {
      AppState.syncLogEnabled = true;
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      theme: onoteTheme(Brightness.light),
      home: AppShell(app: app),
    ));
    await t.pump(const Duration(milliseconds: 900));
    await t.pumpAndSettle();
  }

  testWidgets('a phone: no side navigator, and the page has most of the screen',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(t, const Size(390, 844));
    expect(find.byType(Sidebar), findsNothing,
        reason: 'the navigator is a drawer, not a column beside the page');
    expect(find.byType(PhoneTopBar), findsOneWidget);
    final canvas = t.getSize(find.byType(PageCanvas));
    expect(canvas.width, 390, reason: 'the whole width');
    expect(canvas.height, greaterThan(844 * 0.6),
        reason: 'and well over half the height (it was a third)');
    app.cancelPendingSave();
  });

  testWidgets('nothing sits under the status bar or the gesture bar',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(t, const Size(390, 844),
        padding: const FakeViewPadding(top: 40, bottom: 24));
    expect(t.getTopLeft(find.byType(PhoneTopBar)).dy, greaterThanOrEqualTo(40),
        reason: 'the top bar starts below the status bar or notch');
    expect(t.getBottomLeft(find.byType(PageCanvas)).dy, lessThanOrEqualTo(844 - 24));
    app.cancelPendingSave();
  });

  testWidgets('the menu opens the drawer; choosing a page opens it and closes the drawer',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(t, const Size(390, 844));
    final pages = app.nodes.where((n) => n.kind == NodeKind.page).toList();
    // A second page to choose.
    await t.runAsync(() => app.addPage());
    await t.pumpAndSettle();
    final first = pages.first;
    await t.tap(find.byIcon(Icons.menu));
    await t.pumpAndSettle();
    expect(find.byType(PhoneNavigator), findsOneWidget);
    expect(find.text(app.currentNotebook.title), findsWidgets,
        reason: 'the notebook, at the top of the drawer');
    await t.tap(find
        .descendant(of: find.byType(PhoneNavigator), matching: find.text(first.title))
        .first);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pumpAndSettle();
    expect(find.byType(PhoneNavigator), findsNothing, reason: 'the drawer closed');
    expect(app.pageId, first.id, reason: 'on the page chosen');
    app.cancelPendingSave();
  });

  testWidgets('the notebook list fits a phone: no buttons run off the side',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(t, const Size(360, 780));
    unawaited(showNotebookManager(t.element(find.byType(PhoneTopBar)), app));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(t.takeException(), isNull, reason: 'no overflow');
    final dialog = t.getRect(find.byType(AlertDialog));
    expect(dialog.left, greaterThanOrEqualTo(0));
    expect(dialog.right, lessThanOrEqualTo(360));
    for (final b in find.byType(TextButton).evaluate()) {
      final r = t.getRect(find.byWidget(b.widget));
      expect(r.right, lessThanOrEqualTo(dialog.right), reason: 'inside the dialog');
    }
    app.cancelPendingSave();
  });

  testWidgets('a wide window keeps the desktop layout', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(t, const Size(1200, 800));
    expect(find.byType(Sidebar), findsOneWidget);
    expect(find.byType(PhoneTopBar), findsNothing);
    app.cancelPendingSave();
  });

  testWidgets('Insert opens a sheet of everything you can add, not a row to scroll',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(t, const Size(390, 844));
    await t.tap(find.text('Insert'));
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Table'), findsOneWidget);
    // The strip underneath did not turn into the Insert row.
    await t.tapAt(const Offset(195, 120)); // the scrim closes it
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    app.cancelPendingSave();
  });

  testWidgets('the Write strip is short, and Aa holds the rest', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(t, const Size(390, 844));
    // Not the twenty-five of the desktop row: strikethrough, code, colours and
    // the font are behind Aa.
    expect(find.byIcon(Icons.strikethrough_s), findsNothing);
    expect(find.byIcon(Icons.format_color_text), findsNothing);
    await t.tap(find.byIcon(Icons.text_format));
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byIcon(Icons.strikethrough_s), findsOneWidget);
    expect(find.byIcon(Icons.format_color_text), findsOneWidget);
    expect(find.byIcon(Icons.font_download_outlined), findsOneWidget);
    app.cancelPendingSave();
  });
}
