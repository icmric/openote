// Making a new page must never take another page's children.
//
// The report: "if im on a parent page and click to make a new page, it makes a
// new page but transfers the sub pages to this new page ... it should be at
// the same level as the current page, so if im currently on a sub page it
// should create it as a new sub page, but it should never steal sub pages."
//
// Sub-pages are not children in the data model — every page's parentId is its
// SECTION, and nesting is "the contiguous following run of pages with a
// greater level". That makes ownership POSITIONAL, so where a new page lands
// decides whose children it inherits. `addPage` used to append at the end of
// the section with level 0 and a lexicographic key minted from the clock; the
// importer mints keys the same way, so "the end" was not reliably the end.
//
// These tests build the orderings directly rather than trusting a key scheme,
// which is also the point of the fix.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Repository repo;
  late Directory tmp;
  late AppState app;
  late TreeNode section;

  setUp(() async {
    if (!haveSqlite) return;
    tmp = Directory.systemTemp.createTempSync('onote_newpage_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Pages');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    section = app.importNode(
        nb.id, TreeNode(kind: NodeKind.section, title: 'S', position: 'a0'));
    app.reloadNodes();
  });

  tearDown(() {
    if (!haveSqlite) return;
    app.cancelPendingSave();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// A page at [level], placed with an explicit key so the ordering under test
  /// is the one written here and not whatever a clock produced.
  TreeNode page(String title, int level, String position) => app.importNode(
      app.notebookId!,
      TreeNode(
          kind: NodeKind.page,
          parentId: section.id,
          title: title,
          level: level,
          position: position));

  /// The order the navigator would draw, as "title(level)".
  List<String> shape() =>
      [for (final p in app.pagesOf(section.id)) '${p.title}(${p.level})'];

  /// Which page owns [title], by the same rule the sidebar renders with.
  String? parentOf(String title) {
    final pages = app.pagesOf(section.id);
    final i = pages.indexWhere((p) => p.title == title);
    if (i < 0) return null;
    for (var j = i - 1; j >= 0; j--) {
      if (pages[j].level < pages[i].level) return pages[j].title;
    }
    return null;
  }

  group('from a parent page', () {
    setUp(() {
      if (!haveSqlite) return;
      page('Parent', 0, 'a100');
      page('Sub one', 1, 'a200');
      page('Sub two', 1, 'a300');
      page('Later', 0, 'a400');
      app.reloadNodes();
    });

    test('the new page does not steal the sub-pages', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await app.selectPage(
          app.pagesOf(section.id).firstWhere((p) => p.title == 'Parent').id);
      await app.addPage();

      expect(parentOf('Sub one'), 'Parent');
      expect(parentOf('Sub two'), 'Parent');
      final made = app.node(app.pageId!)!;
      expect(made.level, 0, reason: 'a sibling of Parent, not its child');
      expect(parentOf(made.title), isNull, reason: 'and top level itself');
    });

    test('it lands after the whole subtree, not at the end of the section',
        () async {
      // A page made while reading page 3 of 50 belongs near page 3. Landing
      // after the subtree is also what makes stealing impossible.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await app.selectPage(
          app.pagesOf(section.id).firstWhere((p) => p.title == 'Parent').id);
      await app.addPage();
      app.renameNode(app.pageId!, 'New');
      expect(shape(),
          ['Parent(0)', 'Sub one(1)', 'Sub two(1)', 'New(0)', 'Later(0)']);
    });
  });

  test('from a sub-page you get another sub-page', () async {
    // "if im currently on a sub page it should create it as a new sub page".
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    page('Parent', 0, 'a100');
    page('Sub one', 1, 'a200');
    page('Later', 0, 'a300');
    app.reloadNodes();

    await app.selectPage(
        app.pagesOf(section.id).firstWhere((p) => p.title == 'Sub one').id);
    await app.addPage();
    app.renameNode(app.pageId!, 'New');

    expect(app.node(app.pageId!)!.level, 1);
    expect(parentOf('New'), 'Parent', reason: 'a sibling of Sub one');
    expect(shape(), ['Parent(0)', 'Sub one(1)', 'New(1)', 'Later(0)']);
  });

  test('a deeper run below a sub-page is not stolen either', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    page('Parent', 0, 'a100');
    page('Sub', 1, 'a200');
    page('Deep', 2, 'a300');
    app.reloadNodes();

    await app.selectPage(
        app.pagesOf(section.id).firstWhere((p) => p.title == 'Sub').id);
    await app.addPage();
    app.renameNode(app.pageId!, 'New');

    expect(parentOf('Deep'), 'Sub', reason: 'Deep still belongs to Sub');
    expect(shape(), ['Parent(0)', 'Sub(1)', 'Deep(2)', 'New(1)']);
  });

  test('with no page open it still works', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await app.addPage(sectionId: section.id);
    expect(app.pagesOf(section.id).length, 1);
    expect(app.node(app.pageId!)!.level, 0);
  });

  group('the deliberate sub-page', () {
    test('addSubpage indents under the current page without taking its kids',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      page('Parent', 0, 'a100');
      page('Existing sub', 1, 'a200');
      app.reloadNodes();

      await app.selectPage(
          app.pagesOf(section.id).firstWhere((p) => p.title == 'Parent').id);
      await app.addSubpage();
      app.renameNode(app.pageId!, 'New sub');

      expect(app.node(app.pageId!)!.level, 1);
      expect(parentOf('New sub'), 'Parent');
      expect(parentOf('Existing sub'), 'Parent',
          reason: 'the existing sub-page did not become a child of the new one');
      expect(shape(), ['Parent(0)', 'New sub(1)', 'Existing sub(1)']);
    });

    test('it cannot indent past the level the tree allows', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      page('Parent', 0, 'a100');
      page('Deep', 2, 'a200');
      app.reloadNodes();
      await app.selectPage(
          app.pagesOf(section.id).firstWhere((p) => p.title == 'Deep').id);
      await app.addSubpage();
      expect(app.node(app.pageId!)!.level, 2,
          reason: 'clamped to the same 0..2 the indent action allows');
    });
  });
}
