// Rename, from the menu people actually open.
//
// Issue #18: *"I would like to be able to right click on a section and change
// the name from 'Section 1' to 'The name I want'."* Double-clicking the title
// has always done it, and the menu left it out on exactly that ground — which
// is true and is not discoverable. Two reports in, the menu is where somebody
// who has not found the double-click looks.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/sidebar.dart';

import 'support/sqlite.dart';

Widget host(AppState app) => MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      theme: onoteTheme(Brightness.light),
      home: Scaffold(
        body: ListenableBuilder(
          listenable: app,
          builder: (_, __) => Sidebar(app: app),
        ),
      ),
    );

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;
  late TreeNode page, section, group;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_renamemenu_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('T');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    final first = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
    TreeNode add(NodeKind kind, String title,
        {String? parent, String position = 'b0'}) {
      final n = app.importNode(nb.id,
          TreeNode(kind: kind, parentId: parent, title: title,
              position: position));
      app.reloadNodes();
      return n;
    }

    page = add(NodeKind.page, 'Chapter 3', parent: first.id);
    section = add(NodeKind.section, 'Term 2', position: 'c0');
    group = add(NodeKind.sectionGroup, 'Year 12', position: 'd0');
    await app.selectPage(page.id);
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

  /// Right-click [label]'s row and choose Rename.
  Future<void> renameFromMenu(WidgetTester t, String label) async {
    final g = await t.startGesture(t.getCenter(find.text(label)),
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await g.up();
    await t.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget,
        reason: 'the menu offers it');
    await t.tap(find.text('Rename'));
    await t.pumpAndSettle();
  }

  /// The inline field, which is the SAME one double-clicking opens — a
  /// dialog would be a second way to do one thing. Found by the title it is
  /// seeded with, because the sidebar's search box is an `EditableText` too.
  Finder renameField(String current) => find.byWidgetPredicate(
      (w) => w is EditableText && w.controller.text == current);

  for (final (what, nodeOf, label, typed) in [
    ('a section', () => section, 'Term 2', 'Thermodynamics'),
    ('a group', () => group, 'Year 12', 'Final year'),
    ('a page', () => page, 'Chapter 3', 'Diffraction'),
  ]) {
    testWidgets('RENAME IN THE MENU RENAMES $what', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // A real window, because the pop-out menu opens beside the row and a
      // 800px test surface leaves it nowhere to go.
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(host(app));
      await t.pumpAndSettle();

      await renameFromMenu(t, label);
      expect(renameField(label), findsOneWidget,
          reason: 'the inline field opened, not a dialog');

      await t.enterText(renameField(label), typed);
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();

      expect(app.node(nodeOf().id)?.title, typed);
      await t.pump(const Duration(seconds: 2));
      await t.pumpAndSettle();
    });
  }
}
