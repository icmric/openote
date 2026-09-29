// Dropping into the space under a list means "put it at the end".
//
// The owner: *"When im dragging a page or section to reorder it, if i drop it
// anywhere in the column below the existing pages, it should move it to the
// bottom."*
//
// Every drop target in this navigator was a ROW — one to go above, below or
// inside — so a drop past the last row hit nothing and the drag was silently
// abandoned. Which is the one place a hand overshooting a short list actually
// lands.
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
  late String sectionId;

  Future<void> shell(WidgetTester tester) async {
    AppState.syncLogEnabled = false;
    await tester.runAsync(() async {
      tmp = Directory.systemTemp.createTempSync('onote_drop_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Drop');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      sectionId = app.nodes.firstWhere((n) => n.kind == NodeKind.section).id;
      // Through the app's own calls rather than hand-written `position`
      // strings. Positions are zero-padded to a fixed width and compared as
      // TEXT, so an invented 'a900' sorts after a real one and the fixture
      // ends up testing the fixture.
      for (var i = 0; i < 3; i++) {
        await app.addPage(sectionId: sectionId);
        app.renameNode(app.pageId!, 'Page $i');
      }
      // A second section, so "the bottom of the section list" is a real place.
      await app.addSection();
      app.renameNode(app.activeSectionId!, 'Later');
      app.reloadNodes();
      await app.selectPage(
          app.nodes.firstWhere((n) => n.title == 'Page 1').id);
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

  /// Titles of [kind] under [parent], in the order the navigator shows them.
  ///
  /// Only the rows this test made: a new notebook ships with a page and a
  /// section of its own, and neither is what any of this is about.
  List<String> order(NodeKind kind, String? parent, String prefix) => [
        for (final n in app.nodes)
          if (n.kind == kind && n.parentId == parent && n.title.startsWith(prefix))
            n.title
      ];

  /// Drag the row labelled [label] (inside the navigator) to [to].
  Future<void> dragTo(WidgetTester tester, String label, Offset to) async {
    final row = find.descendant(
        of: find.byType(Sidebar), matching: find.text(label));
    expect(row, findsOneWidget, reason: label);
    final g = await tester.startGesture(tester.getCenter(row));
    // Past the touch slop in a couple of steps, the way a hand does it —
    // one jump can outrun the recogniser.
    await g.moveBy(const Offset(0, 24));
    await tester.pump();
    await g.moveTo(to);
    await tester.pump();
    await g.moveBy(const Offset(0, 1)); // a move while OVER the target
    await tester.pump();
    await g.up();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  testWidgets('a page dropped under the list goes to the bottom',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(tester);
    expect(order(NodeKind.page, sectionId, 'Page '),
        ['Page 0', 'Page 1', 'Page 2']);

    // Well below the last row, in the empty part of the pages column.
    final last = tester.getRect(
        find.descendant(of: find.byType(Sidebar), matching: find.text('Page 2')));
    await dragTo(tester, 'Page 0', Offset(last.center.dx, last.bottom + 150));

    expect(order(NodeKind.page, sectionId, 'Page '),
        ['Page 1', 'Page 2', 'Page 0'],
        reason: 'the drop used to hit nothing at all and be abandoned');
  });

  testWidgets('a section dropped under the list goes to the bottom',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(tester);
    // Both sections this test cares about: the notebook's own, renamed
     // nowhere, and the one added after it.
    final before = order(NodeKind.section, null, '');
    expect(before.last, 'Later');

    final row = tester.getRect(
        find.descendant(of: find.byType(Sidebar), matching: find.text('Later')));
    await dragTo(tester, before.first, Offset(row.center.dx, row.bottom + 150));

    expect(order(NodeKind.section, null, '').last, before.first,
        reason: 'the same gesture, in the other column');
  });

  testWidgets('and a drop ON a row still means what it always meant',
      (tester) async {
    // The new target wraps the list, so it sits BEHIND every row. If it were
    // taking drops meant for a row, nesting would be unreachable — Flutter
    // resolves a drop to the innermost target, and this asserts that it does.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(tester);
    final onto = tester.getCenter(find.descendant(
        of: find.byType(Sidebar), matching: find.text('Page 2')));
    await dragTo(tester, 'Page 0', onto);

    final moved = app.nodes.firstWhere((n) => n.title == 'Page 0');
    expect(moved.level, 1,
        reason: 'dropped onto the middle of a row, which has always meant '
            '"make it a subpage"');
  });

  test('moveNodeToEnd promotes a subpage rather than stranding it', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final dir = Directory.systemTemp.createTempSync('onote_end_');
    final r = await Repository.openAt(dir);
    final nb = await r.createNotebook('End');
    final a = AppState(r)..notebookId = nb.id;
    a.reloadNodes();
    final sec = a.nodes.firstWhere((n) => n.kind == NodeKind.section).id;
    for (var i = 0; i < 2; i++) {
      final p = a.importNode(
          nb.id,
          TreeNode(
              kind: NodeKind.page,
              parentId: sec,
              title: 'P$i',
              level: i, // P1 is a subpage of P0
              position: 'a${(100 + i).toString().padLeft(10, '0')}'));
      a.importPage(nb.id, p.id, [], PageProps());
    }
    a.reloadNodes();
    addTearDown(() {
      a.cancelPendingSave();
      r.dispose();
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    final sub = a.nodes.firstWhere((n) => n.title == 'P1');
    expect(sub.level, 1);
    a.moveNodeToEnd(sub.id);
    expect(a.nodes.firstWhere((n) => n.title == 'P1').level, 0,
        reason: 'a page dragged past the end of the list is a page of that '
            'section by the act of putting it there — leaving it at level 1 '
            'indents it under nothing');
  });
}
