// The navigator, tidied (S7): one plus for adding sections, Recent and the
// Recycle bin as places at the foot, dragging a section onto another to group
// them, and a bin that says what is in it.
//
// Dragged through real pointer events, because the zone under the pointer
// (top quarter, middle half, bottom quarter) is what decides what a drop does,
// and a test that calls the state method directly would never notice the zones
// being wrong.
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

  late Directory tmp;
  late Repository repo;
  late AppState app;

  List<TreeNode> sections() =>
      app.nodes.where((n) => n.kind == NodeKind.section).toList();

  /// A notebook with [extra] more sections than the one it starts with, and a
  /// page in the first.
  Future<void> shell(WidgetTester tester, {int extra = 2}) async {
    AppState.syncLogEnabled = false;
    await tester.runAsync(() async {
      tmp = Directory.systemTemp.createTempSync('onote_s7_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('S7');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      for (var i = 0; i < extra; i++) {
        await app.addSection();
      }
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

  /// Delete the first page of the [i]th section: one entry in the bin. (A
  /// deleted SECTION puts its pages in there as well.)
  Future<TreeNode> deletePageOf(WidgetTester tester, int i) async {
    final page = app.pagesOf(sections()[i].id).first;
    await tester.runAsync(() => app.deleteNode(page.id));
    return page;
  }

  /// The rename field of a row currently showing [text].
  Finder renaming(String text) => find.byWidgetPredicate(
      (w) => w is EditableText && w.controller.text == text);

  /// Long enough for the debounced workspace save, which is left to fire.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
  }

  Finder inNav(Finder f) => find.descendant(of: find.byType(Sidebar), matching: f);

  /// Carry the section named [from] to [where] (a point), without letting go.
  Future<TestGesture> carry(
      WidgetTester tester, String from, Offset where) async {
    final g = await tester.startGesture(tester.getCenter(inNav(find.text(from))));
    await g.moveBy(const Offset(0, 6));
    await tester.pump();
    await g.moveTo(where);
    await tester.pump();
    return g;
  }

  // ── The state change ─────────────────────────────────────────────────────

  group('grouping two sections', () {
    testWidgets('two loose sections become the members of a new group',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await shell(tester);
      final s = sections();
      final moving = s[0], target = s[1];
      final id = app.groupSectionsTogether(moving.id, target.id);
      expect(id, isNotNull);
      final g = app.node(id)!;
      expect(g.kind, NodeKind.sectionGroup);
      expect(app.node(moving.id)!.parentId, id);
      expect(app.node(target.id)!.parentId, id);
      expect(app.node(s[2].id)!.parentId, isNull,
          reason: 'a third section is left where it was');
      expect(app.groupToRename, id,
          reason: 'the new group opens for its name to be typed over');
      await settle(tester);
    });

    testWidgets('dropped on a section that is already in a group, it joins',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await shell(tester);
      final s = sections();
      final g = app.groupSectionsTogether(s[0].id, s[1].id)!;
      final groups = app.nodes.where((n) => n.kind == NodeKind.sectionGroup);
      expect(groups.length, 1);
      final again = app.groupSectionsTogether(s[2].id, s[1].id);
      expect(again, g, reason: 'no second group is made');
      expect(app.node(s[2].id)!.parentId, g);
      expect(app.nodes.where((n) => n.kind == NodeKind.sectionGroup).length, 1);
      await settle(tester);
    });

    testWidgets('a section on itself, or a page, does nothing', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await shell(tester);
      final s = sections();
      final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
      expect(app.groupSectionsTogether(s[0].id, s[0].id), isNull);
      expect(app.groupSectionsTogether(page.id, s[0].id), isNull);
      expect(app.groupSectionsTogether(s[0].id, page.id), isNull);
      expect(app.nodes.where((n) => n.kind == NodeKind.sectionGroup), isEmpty);
      await settle(tester);
    });
  });

  // ── Dragging, by pointer ─────────────────────────────────────────────────

  group('dragging a section', () {
    testWidgets('over the middle of another says so, and groups on letting go',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await shell(tester);
      final s = sections();
      final over = tester.getCenter(inNav(find.text(s[1].title)));
      final g = await carry(tester, s[0].title, over);
      expect(find.text('Group together'), findsOneWidget,
          reason: 'the pill under the pointer says what letting go will do');

      await g.up();
      await settle(tester);
      expect(find.text('Group together'), findsNothing,
          reason: 'and goes when the drag does');
      final groups =
          app.nodes.where((n) => n.kind == NodeKind.sectionGroup).toList();
      expect(groups.length, 1);
      expect(app.node(s[0].id)!.parentId, groups.single.id);
      expect(app.node(s[1].id)!.parentId, groups.single.id);
      // The group's name is open for typing.
      expect(renaming(groups.single.title), findsOneWidget);
    });

    testWidgets('over the top edge it moves above, and nothing is grouped',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await shell(tester);
      final s = sections();
      final row = inNav(find.text(s[0].title));
      // Section 3 carried to the top quarter of Section 1's row.
      final top = tester.getTopLeft(row) + const Offset(10, -6);
      final g = await carry(tester, s[2].title, top);
      expect(find.text('Move above'), findsOneWidget);
      await g.up();
      await settle(tester);
      expect(app.nodes.where((n) => n.kind == NodeKind.sectionGroup), isEmpty);
      final order = sections().map((n) => n.id).toList();
      expect(order.indexOf(s[2].id), lessThan(order.indexOf(s[0].id)),
          reason: 'it landed above');
    });

    testWidgets('a drag that is let go over nothing leaves no pill behind',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await shell(tester);
      final s = sections();
      final g = await carry(
          tester, s[0].title, tester.getCenter(inNav(find.text(s[1].title))));
      expect(find.text('Group together'), findsOneWidget);
      await g.moveTo(const Offset(900, 500));
      await tester.pump();
      expect(find.text('Group together'), findsNothing);
      await g.up();
      await settle(tester);
      expect(app.nodes.where((n) => n.kind == NodeKind.sectionGroup), isEmpty);
    });

    testWidgets('a page dragged onto a section says it will move there',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await shell(tester);
      final s = sections();
      final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
      final g = await tester
          .startGesture(tester.getCenter(inNav(find.text(page.title)).first));
      await g.moveBy(const Offset(0, 6));
      await tester.pump();
      await g.moveTo(tester.getCenter(inNav(find.text(s[1].title))));
      await tester.pump();
      expect(find.text('Move to this section'), findsOneWidget);
      await g.up();
      await settle(tester);
      expect(app.node(page.id)!.parentId, s[1].id);
    });
  });

  // ── One plus ─────────────────────────────────────────────────────────────

  group('the plus above the section list', () {
    testWidgets('opens a short menu, and the old buttons are gone',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await shell(tester, extra: 0);
      expect(inNav(find.text('SECTIONS')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav-add-section')), findsOneWidget);
      // The big button and the small group button at the foot are gone.
      expect(inNav(find.text('Section')), findsNothing);
      expect(find.byTooltip('New section group'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('nav-add-section')));
      await tester.pumpAndSettle();
      expect(find.text('New section'), findsOneWidget);
      expect(find.text('New section group'), findsOneWidget);

      final before = sections().length;
      await tester.tap(find.text('New section'));
      await settle(tester);
      expect(sections().length, before + 1);
    });

    testWidgets('a new group opens for its name', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await shell(tester, extra: 0);
      await tester.tap(find.byKey(const ValueKey('nav-add-section')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New section group'));
      await settle(tester);
      expect(app.nodes.where((n) => n.kind == NodeKind.sectionGroup).length, 1);
      final g = app.nodes.firstWhere((n) => n.kind == NodeKind.sectionGroup);
      expect(renaming(g.title), findsOneWidget,
          reason: 'the name is selected for typing over, not a name to hunt for');
    });

    testWidgets('a group has a folder in front of it, not a dot',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await shell(tester);
      final s = sections();
      app.groupSectionsTogether(s[0].id, s[1].id);
      app.groupToRename = null;
      app.notifyListeners();
      await settle(tester);
      expect(inNav(find.byIcon(Icons.folder_outlined)), findsOneWidget);
    });
  });

  // ── Places ───────────────────────────────────────────────────────────────

  group('Recent and the Recycle bin', () {
    testWidgets('are a row of places at the foot, named', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await shell(tester);
      expect(inNav(find.text('Recent')), findsOneWidget);
      expect(inNav(find.text('Recycle bin')), findsOneWidget);
      expect(inNav(find.text('Home')), findsNothing,
          reason: 'Home is called Recent now, and lives down here');
      await tester.tap(inNav(find.text('Recent')));
      await settle(tester);
      expect(app.navHome, isTrue);
    });

    testWidgets('the bin carries a count of what is in it', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await shell(tester);
      expect(app.binCount, 0);
      await deletePageOf(tester, 1);
      await settle(tester);
      expect(app.binCount, 1);
      expect(inNav(find.text('1')), findsOneWidget);
    });

    testWidgets('and gives up its words before it gives up its count',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await shell(tester);
      await deletePageOf(tester, 1);
      app.toggleNavSectionsCollapsed();
      app.navPagesW = 190;
      app.refresh();
      await settle(tester);
      expect(inNav(find.text('Recycle bin')), findsNothing,
          reason: 'the bin\'s name goes first');
      expect(inNav(find.text('Recent')), findsOneWidget);
      expect(inNav(find.text('1')), findsOneWidget, reason: 'the count stays');

      app.navPagesW = 150;
      app.refresh();
      await settle(tester);
      expect(inNav(find.text('Recent')), findsNothing,
          reason: 'then Recent\'s');
      expect(find.byTooltip('Recycle bin'), findsOneWidget,
          reason: 'with the tooltip still saying what the icon is');
    });
  });

  // ── The bin's panel ──────────────────────────────────────────────────────

  group('the recycle bin panel', () {
    Future<List<TreeNode>> deleteTwo(WidgetTester tester) async {
      final a = await deletePageOf(tester, 1);
      final b = await deletePageOf(tester, 2);
      await settle(tester);
      return [a, b];
    }

    testWidgets('names each thing, what it is, and offers Restore',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await shell(tester);
      final gone = await deleteTwo(tester);
      await tester.tap(inNav(find.text('Recycle bin')));
      await tester.pumpAndSettle();

      expect(find.text(gone[0].title), findsWidgets);
      expect(find.text('Page · today'), findsNWidgets(2));
      expect(find.text('Restore'), findsNWidgets(2));
      expect(find.text('Empty'), findsOneWidget);

      await tester.tap(find.text('Restore').first);
      await tester.pumpAndSettle();
      expect(app.binCount, 1, reason: 'one came back');
    });

    testWidgets('a deleted section is one row, and brings its pages back',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await shell(tester);
      final victim = sections().last;
      final pages = app.pagesOf(victim.id).map((p) => p.id).toList();
      expect(pages, isNotEmpty);
      await tester.runAsync(() => app.deleteNode(victim.id));
      await settle(tester);

      expect(app.binCount, 1,
          reason: 'the section, not the section and each page in it');
      await tester.tap(inNav(find.text('Recycle bin')));
      await tester.pumpAndSettle();
      expect(find.text('Section · today'), findsOneWidget);
      expect(find.text('Page · today'), findsNothing);

      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      expect(app.binCount, 0);
      expect(app.node(victim.id), isNotNull);
      for (final p in pages) {
        expect(app.node(p), isNotNull, reason: 'its pages came back with it');
      }
    });

    testWidgets('a page deleted earlier keeps its own row', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await shell(tester);
      final s = sections();
      // Give the last section a second page, delete that page, THEN the section.
      await tester.runAsync(() async {
        await app.activateSection(s.last.id);
        await app.addPage(sectionId: s.last.id);
      });
      final extra = app.pagesOf(s.last.id).last;
      await tester.runAsync(() async {
        await app.deleteNode(extra.id);
        // Real time, so the two deletes carry different stamps.
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await app.deleteNode(s.last.id);
      });
      await settle(tester);
      expect(app.binCount, 2,
          reason: 'the old page and the section; the section\'s other page '
              'went in with it and is not listed');
    });

    testWidgets('the cross asks first, and Cancel keeps it', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await shell(tester);
      await deleteTwo(tester);
      await tester.tap(inNav(find.text('Recycle bin')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete permanently').first);
      await tester.pumpAndSettle();
      expect(find.text('Delete permanently?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(app.binCount, 2, reason: 'nothing was removed');

      await tester.tap(find.byTooltip('Delete permanently').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete forever'));
      await tester.pumpAndSettle();
      expect(app.binCount, 1);
    });

    testWidgets('Empty asks first, then removes everything', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await shell(tester);
      await deleteTwo(tester);
      await tester.tap(inNav(find.text('Recycle bin')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Empty'));
      await tester.pumpAndSettle();
      expect(find.text('Empty the recycle bin?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(app.binCount, 2);

      await tester.tap(find.text('Empty'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Empty'));
      await tester.pumpAndSettle();
      expect(app.binCount, 0);
      expect(find.text('Nothing deleted.'), findsOneWidget);
    });

    testWidgets('Escape closes it', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await shell(tester);
      await tester.tap(inNav(find.text('Recycle bin')));
      await tester.pumpAndSettle();
      expect(find.text('Items here are permanently deleted after 30 days.'),
          findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Items here are permanently deleted after 30 days.'),
          findsNothing);
    });
  });
}
