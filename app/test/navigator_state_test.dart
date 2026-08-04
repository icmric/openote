// The two-column navigator's state layer: remembered per-section pages, Home,
// and the layout state the shell memoises on.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  /// Two sections, three pages each.
  Future<(Repository, Directory, AppState)> fixture(String name) async {
    final tmp = Directory.systemTemp.createTempSync(name);
    final repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Nav');
    final app = AppState(repo)..notebookId = nb.id;
    app.reloadNodes();
    final secA = app.nodes.firstWhere((n) => n.kind == NodeKind.section).id;
    final secB = app.importNode(
        nb.id,
        TreeNode(
            kind: NodeKind.section, title: 'B', position: 'a2'));
    for (final (sec, label) in [(secA, 'A'), (secB.id, 'B')]) {
      for (var i = 0; i < 3; i++) {
        final node = app.importNode(
            nb.id,
            TreeNode(
                kind: NodeKind.page,
                parentId: sec,
                title: '$label$i',
                position: 'a${(100 + i).toString().padLeft(10, '0')}'));
        app.importPage(nb.id, node.id, [], PageProps());
      }
    }
    app.reloadNodes();
    return (repo, tmp, app);
  }

  void cleanup(Repository repo, Directory tmp) {
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  }

  TreeNode byTitle(AppState app, String t) =>
      app.nodes.firstWhere((n) => n.title == t);

  test('browsing sections never loses your place', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // The old activateSection jumped to the FIRST page every time, so merely
    // looking at another section threw away where you were in it.
    final (repo, tmp, app) = await fixture('onote_nav_place_');
    addTearDown(() => cleanup(repo, tmp));

    final a2 = byTitle(app, 'A2');
    final secA = a2.parentId!;
    final secB = byTitle(app, 'B0').parentId!;

    await app.selectPage(a2.id); // deep in section A
    await app.activateSection(secB); // look at B…
    expect(app.node(app.pageId)?.parentId, secB);
    await app.activateSection(secA); // …and come back
    expect(app.pageId, a2.id,
        reason: 'must return to the page you were on, not the first page');
  });

  test('a never-visited section still opens its first page', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp, app) = await fixture('onote_nav_first_');
    addTearDown(() => cleanup(repo, tmp));
    final secB = byTitle(app, 'B0').parentId!;
    await app.activateSection(secB);
    expect(app.node(app.pageId)?.parentId, secB);
    expect(app.node(app.pageId)?.title, 'B0');
  });

  test('a remembered page that was deleted falls back safely', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp, app) = await fixture('onote_nav_gone_');
    addTearDown(() => cleanup(repo, tmp));

    final b1 = byTitle(app, 'B1');
    final secB = b1.parentId!;
    final secA = byTitle(app, 'A0').parentId!;
    await app.selectPage(b1.id); // remember B1 for section B
    await app.activateSection(secA);
    await app.deleteNode(b1.id); // the remembered page is now gone
    await app.activateSection(secB);
    expect(app.node(app.pageId)?.parentId, secB,
        reason: 'a dangling memory must fall back, not crash or no-op');
  });

  test('Home is a springboard: selecting any page leaves it', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp, app) = await fixture('onote_nav_home_');
    addTearDown(() => cleanup(repo, tmp));

    await app.selectPage(byTitle(app, 'A0').id);
    app.openHome();
    expect(app.navHome, isTrue);
    // activeSectionId stays a REAL section while Home is up — Home is a
    // boolean beside it, so study scoping and exam plans never see a
    // sentinel id.
    expect(app.node(app.activeSectionId!)?.kind, NodeKind.section);

    await app.selectPage(byTitle(app, 'B2').id);
    expect(app.navHome, isFalse,
        reason: 'going somewhere returns the pane to that somewhere');
  });

  test('layout state persists and clamps', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp, app) = await fixture('onote_nav_layout_');
    addTearDown(() => cleanup(repo, tmp));

    app.setNavSectionsW(500); // beyond the clamp
    app.setNavPagesW(10);
    app.toggleNavCollapsed();
    expect(app.navSectionsW, 220);
    expect(app.navPagesW, 140);
    expect(repo.getSetting('navSectionsW'), 220);
    expect(repo.getSetting('navPagesW'), 140);
    expect(repo.getSetting('navCollapsed'), true);
  });

  test('collapse and favourite toggles bump navRevision', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // The navigator memo keys on this counter; lengths can alias (one
    // collapse + one expand between frames looks unchanged), a counter can't.
    final (repo, tmp, app) = await fixture('onote_nav_rev_');
    addTearDown(() => cleanup(repo, tmp));

    final before = app.navRevision;
    app.togglePageCollapsed(byTitle(app, 'A0').id);
    app.toggleFavourite(byTitle(app, 'A1').id);
    expect(app.navRevision, greaterThan(before + 1));
  });
}
