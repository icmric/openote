// #43: one right-click menu for making things, on the empty part of the
// section list and the page list, as OneNote has. The plus buttons stay; this
// is a second route for the hands that reach for OneNote's.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/app_shell.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;

  int count(NodeKind k) => app.nodes.where((n) => n.kind == k).length;

  Future<void> shell(WidgetTester tester) async {
    AppState.syncLogEnabled = false;
    await tester.runAsync(() async {
      tmp = Directory.systemTemp.createTempSync('onote_navmenu_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Menu');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      await app.selectPage(
          app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
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

  /// A point in the empty space under the list that holds [plusKey]'s button.
  Offset emptyUnder(WidgetTester tester, String plusKey) {
    final plus = tester.getRect(find.byKey(ValueKey(plusKey)));
    return Offset(plus.left - 40, plus.bottom + 500);
  }

  Future<void> rightClick(WidgetTester tester, Offset at) async {
    await tester.tapAt(at, buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
  }

  testWidgets('empty section list: section, group, notebook, open',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(tester);
    await rightClick(tester, emptyUnder(tester, 'nav-add-section'));
    expect(find.text('New section'), findsOneWidget);
    expect(find.text('New group'), findsOneWidget);
    expect(find.text('New notebook…'), findsOneWidget);
    expect(find.text('Open a notebook from a folder…'), findsOneWidget);
    expect(find.text('New page'), findsNothing,
        reason: 'the section list makes sections');
  });

  testWidgets('and each one does what it says', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(tester);
    final groups = count(NodeKind.sectionGroup);
    await rightClick(tester, emptyUnder(tester, 'nav-add-section'));
    await tester.tap(find.text('New group'));
    await tester.pumpAndSettle();
    expect(count(NodeKind.sectionGroup), groups + 1);

    final sections = count(NodeKind.section);
    await rightClick(tester, emptyUnder(tester, 'nav-add-section'));
    await tester.tap(find.text('New section'));
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(count(NodeKind.section), sections + 1);
  });

  testWidgets('empty page list offers a page, in the open section',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(tester);
    final section = app.activeSection!;
    final before = app.pagesOf(section.id).length;
    await rightClick(tester, emptyUnder(tester, 'nav-add-page'));
    expect(find.text('New page'), findsOneWidget);
    await tester.tap(find.text('New page'));
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(app.pagesOf(section.id).length, before + 1);
  });

  testWidgets('a row keeps its own menu', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(tester);
    // The first page row, just under the page list's header.
    final plus = tester.getRect(find.byKey(const ValueKey('nav-add-page')));
    await rightClick(tester, Offset(plus.left - 60, plus.bottom + 18));
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('New notebook…'), findsNothing,
        reason: 'the create menu is for empty space only');
  });

  // #18: Move to group offers a group that does not exist yet.
  testWidgets('a section can be moved into a new group', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(tester);
    final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
    final groups = count(NodeKind.sectionGroup);

    final g = app.groupSectionAlone(section.id);
    await tester.pumpAndSettle();

    expect(count(NodeKind.sectionGroup), groups + 1);
    final made = app.node(g)!;
    expect(made.parentId, isNull, reason: 'groups are drawn at the top level');
    expect(app.node(section.id)!.parentId, g, reason: 'and the section is in it');
  });

  testWidgets('out of one group into a new one, the new one is top level',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(tester);
    final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
    final first = app.groupSectionAlone(section.id)!;
    final second = app.groupSectionAlone(section.id)!;
    await tester.pumpAndSettle();
    expect(app.node(second)!.parentId, isNull,
        reason: 'never nested inside the group it left');
    expect(app.node(section.id)!.parentId, second);
    expect(app.node(first), isNotNull, reason: 'the old group is left as it is');
  });

  testWidgets('and through the menu: Move to group, New group',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(tester);
    final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
    final groups = count(NodeKind.sectionGroup);
    // The section row sits just under the SECTIONS header and its plus.
    final plus = tester.getRect(find.byKey(const ValueKey('nav-add-section')));
    await rightClick(tester, Offset(plus.left - 40, plus.bottom + 18));
    await tester.tap(find.text('Move to group…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New group'));
    await tester.pumpAndSettle();
    expect(count(NodeKind.sectionGroup), groups + 1);
    expect(app.node(section.id)!.parentId, isNotNull);
  });
}
