// "Rename" in the navigator's right-click menu, for all three kinds of row.
//
// Asked for directly: *"add the 'edit title' button to the right click menu for
// section groups, sections, and pages."*
//
// It was left out on purpose once — `showNodeMenu`'s own comment said *"Rename
// lives inline (double-click the title) so it's not in this list"* — and that
// reasoning is true and insufficient. A right-click menu is where somebody
// looks to find out what can be done to a thing, and an action missing from it
// reads as an action that does not exist.
//
// Each case goes through the real menu over a real repository, because the
// three rows are three separate widgets with three separate copies of the
// rename state, and the whole risk is that one of them is wired and another is
// not.

import 'dart:io';

import 'package:flutter/gestures.dart' show kSecondaryButton;
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
    final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
    TreeNode add(NodeKind kind, String title,
        {String? parent, String position = 'b0'}) {
      final n = app.importNode(
          nb.id,
          TreeNode(
              kind: kind, parentId: parent, title: title, position: position));
      app.reloadNodes();
      return n;
    }

    final page = add(NodeKind.page, 'Chapter 3', parent: section.id);
    add(NodeKind.section, 'Term 2', position: 'c0');
    add(NodeKind.sectionGroup, 'Year 12', position: 'd0');
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

  /// A window the navigator actually fits in.
  ///
  /// At the 800x600 test default the sidebar is squeezed to 256px and its rows
  /// overflow, which fails the test on a layout error that has nothing to do
  /// with renaming.
  void sizeWindow(WidgetTester t) {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  /// The field whose contents are exactly [text].
  ///
  /// Scoped rather than `find.byType(TextField)`: the navigator has a search
  /// box of its own, so a bare type finder matches two and says "too many".
  Finder fieldWith(String text) => find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == text);

  /// Right-click the row labelled [label] and return once its menu is up.
  Future<void> openMenuOn(WidgetTester t, String label) async {
    final row = find.text(label);
    expect(row, findsOneWidget, reason: 'precondition: the $label row is up');
    await t.tapAt(t.getCenter(row), buttons: kSecondaryButton);
    await t.pumpAndSettle();
  }

  /// Close a menu or an in-flight rename without committing anything.
  Future<void> escape(WidgetTester t) async {
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    app.cancelPendingSave();
  }

  for (final (kind, label) in const [
    ('a page', 'Chapter 3'),
    ('a section', 'Term 2'),
    ('a section group', 'Year 12'),
  ]) {
    testWidgets('$kind offers Rename, and it turns the row into a field',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      sizeWindow(t);
      await t.pumpWidget(host(app));
      await t.pumpAndSettle();

      await openMenuOn(t, label);
      final rename = find.text('Rename');
      expect(rename, findsOneWidget, reason: '$kind must offer it');

      await t.tap(rename);
      await t.pumpAndSettle();

      // The row becomes an editable field in place, prefilled with the
      // current title — the same thing the double-click does. A dialog would
      // be a different (worse) answer.
      expect(fieldWith(label), findsOneWidget,
          reason: 'the $kind row should now be a field holding its own title');

      await escape(t);
    });
  }

  testWidgets('Rename is the first item, above the move actions', (t) async {
    // Placement is the point of the request: it is the thing most often
    // wanted from this menu, so it should not be hunted for below six
    // structural actions.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    sizeWindow(t);
    await t.pumpWidget(host(app));
    await t.pumpAndSettle();
    await openMenuOn(t, 'Chapter 3');

    final renameY = t.getCenter(find.text('Rename')).dy;
    final moveUpY = t.getCenter(find.text('Move up')).dy;
    expect(renameY, lessThan(moveUpY));

    await escape(t);
  });

  testWidgets('and the typed title is what the node ends up called', (t) async {
    // The whole round trip: menu, field, type, commit, and the tree agrees.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    sizeWindow(t);
    await t.pumpWidget(host(app));
    await t.pumpAndSettle();
    await openMenuOn(t, 'Term 2');
    await t.tap(find.text('Rename'));
    await t.pumpAndSettle();

    await t.enterText(fieldWith('Term 2'), 'Term 2 (revised)');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    app.cancelPendingSave();

    final renamed = app.nodes.where((n) => n.title == 'Term 2 (revised)');
    expect(renamed, hasLength(1), reason: 'the section carries the new title');
    expect(app.nodes.any((n) => n.title == 'Term 2'), isFalse,
        reason: 'and not the old one as well');
  });
}
