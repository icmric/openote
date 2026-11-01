// A new page looks like the page it is filed next to.
//
// The other half of what replaced page templates. A template was a thing you
// had to go and ask for, from a menu, by name, from a list that showed you
// none of what it would do; a page's SHAPE — ruling or grid, grid size,
// width, canvas or sheet — can simply be taken from its neighbour, and then
// nobody has to ask for anything.
//
// What was there before carried the paper size and orientation only, and took
// them from whatever page happened to be on screen. So setting a section to
// grid did nothing for the next page in it, and adding a page to Maths right
// after reading an essay in English dragged the essay's shape over. Pages
// live in sections, so the neighbour is the honest source.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;
  late String nb;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_pageshape_');
    repo = await Repository.openAt(tmp);
    final ref = await repo.createNotebook('T');
    nb = ref.id;
    app = AppState(repo)
      ..notebookId = nb
      ..spellCheckEnabled = false;
    app.reloadNodes();
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

  TreeNode section(String title, {String position = 'c0'}) {
    final n = app.importNode(nb,
        TreeNode(kind: NodeKind.section, title: title, position: position));
    app.reloadNodes();
    return n;
  }

  /// A page in [sectionId] with the given shape.
  TreeNode shapedPage(String sectionId, String title, PageProps props,
      {String position = 'b0'}) {
    final n = app.importNode(
        nb,
        TreeNode(
            kind: NodeKind.page,
            parentId: sectionId,
            title: title,
            position: position));
    app.importPage(nb, n.id, const <Block>[], props);
    app.reloadNodes();
    return n;
  }

  test('a new page takes the ruling, grid and width of the page above it',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final maths = section('Maths');
    final p = shapedPage(maths.id, 'Quadratics',
        PageProps(background: 'grid', gridSize: 40, pageWidth: 1400));
    await app.selectPage(p.id);

    await app.addPage();

    expect(app.pageProps.background, 'grid',
        reason: 'set the section to grid once and new pages are grid');
    expect(app.pageProps.gridSize, 40);
    expect(app.pageProps.pageWidth, 1400);
    expect(app.node(app.pageId!)!.parentId, maths.id);
    app.cancelPendingSave();
  });

  test('and that survives closing the page and coming back to it', () async {
    // The shape has to be WRITTEN, not just held in memory: a page whose
    // props were never persisted comes back blank, which would make the whole
    // thing look like it had not worked.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final maths = section('Maths');
    final p = shapedPage(maths.id, 'Quadratics', PageProps(background: 'grid'));
    await app.selectPage(p.id);
    await app.addPage();
    final made = app.pageId!;

    await app.selectPage(p.id);
    await app.selectPage(made);
    expect(app.pageProps.background, 'grid');
    expect(repo.readPage(nb, made).props.background, 'grid',
        reason: 'and it is on disk, not only on the screen');
    app.cancelPendingSave();
  });

  test('THE ONE THAT WAS WRONG: it comes from the section, not the screen',
      () async {
    // Reading an essay in English and then adding a page to Maths used to
    // give you a page shaped like the essay.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final english = section('English', position: 'c0');
    final maths = section('Maths', position: 'c1');
    final essay = shapedPage(english.id, 'Macbeth',
        PageProps(background: 'ruled', layout: 'paged', paperSize: 'A4'));
    shapedPage(maths.id, 'Quadratics', PageProps(background: 'grid'));

    await app.selectPage(essay.id);
    expect(app.pageProps.background, 'ruled', reason: 'precondition');

    await app.addPage(sectionId: maths.id);

    expect(app.pageProps.background, 'grid',
        reason: "the Maths section's shape, not the essay's");
    expect(app.pageProps.isPaged, isFalse,
        reason: 'and not the essay\'s sheet of paper either');
    app.cancelPendingSave();
  });

  test('a section with no pages yet gets the plain defaults', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final fresh = section('Physics');
    await app.addPage(sectionId: fresh.id);
    expect(app.pageProps.background, 'blank');
    expect(app.pageProps.layout, 'canvas');
    app.cancelPendingSave();
  });

  test('STILL TRUE: a sheet of paper is inherited, size and orientation',
      () async {
    // The one thing the old rule did get right, kept. `setPageLayout` also
    // has to run for a paged page — a sheet needs its body box — so this
    // checks the page is usable, not only that the flags came across.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final essays = section('Essays');
    final p = shapedPage(essays.id, 'Draft',
        PageProps(layout: 'paged', paperSize: 'A3', landscape: true));
    await app.selectPage(p.id);

    await app.addPage();

    expect(app.pageProps.isPaged, isTrue);
    expect(app.pageProps.paperSize, 'A3');
    expect(app.pageProps.landscape, isTrue);
    expect(app.blocks, isNotEmpty,
        reason: 'a paged page comes with the one big box to write in');
    app.cancelPendingSave();
  });

  test('a sub-page is shaped like the page it sits under', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final maths = section('Maths');
    final p = shapedPage(
        maths.id, 'Quadratics', PageProps(background: 'dotted', gridSize: 16));
    await app.selectPage(p.id);

    await app.addSubpage();

    expect(app.node(app.pageId!)!.level, 1, reason: 'precondition: a sub-page');
    expect(app.pageProps.background, 'dotted');
    expect(app.pageProps.gridSize, 16);
    app.cancelPendingSave();
  });
}
