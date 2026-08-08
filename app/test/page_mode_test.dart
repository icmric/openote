// Pages as well as canvas.
//
// The ask: "id like the option to switch between pages and and this
// pageless/canvas mode. By default it should be canvas, but id like the option
// to be able to work in set page sizes (which should be alterable too)." Plus
// the clarification that made it tractable: "in page mode i think text boxes
// shouldnt be the default, it should be like a regular text/md editor.
// Basically ends up being just one really big box."
//
// That last sentence is why there is no block-reflow machinery here. A sheet
// is not a canvas with pagination bolted on; it is a column you write down,
// and the pagination is a consequence of how much you wrote.
//
// The two properties worth defending are that CANVAS IS UNCHANGED (every
// existing page, and every page from an older build, opens exactly as it did)
// and that a sheet has edges that content cannot escape.
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
    tmp = Directory.systemTemp.createTempSync('onote_paged_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Essays');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    section = app.importNode(
        nb.id, TreeNode(kind: NodeKind.section, title: 'S', position: 'a0'));
    app.reloadNodes();
    await app.addPage(sectionId: section.id);
  });

  tearDown(() {
    if (!haveSqlite) return;
    app.cancelPendingSave();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('the format stays compatible', () {
    test('a page from any older build is canvas, exactly as before', () {
      // Additive or nothing: `layout` did not exist, so its absence has to
      // mean the behaviour Openote has always had.
      final old = PageProps.fromJson({'background': 'ruled', 'gridSize': 24.0});
      expect(old.isPaged, isFalse);
      expect(old.layout, 'canvas');
      expect(old.paperSize, 'A4', reason: 'a default, not a decision');
    });

    test('the new fields round-trip', () {
      final p = PageProps.fromJson({
        'layout': 'paged',
        'paperSize': 'Letter',
        'landscape': true,
      });
      expect(p.isPaged, isTrue);
      expect(p.paper.name, 'Letter');
      final back = PageProps.fromJson(p.toJson());
      expect(back.layout, 'paged');
      expect(back.paperSize, 'Letter');
      expect(back.landscape, isTrue);
    });

    test('a canvas page writes exactly what it always wrote', () {
      // The three new keys are omitted unless they say something. Not just
      // tidiness: emitting them unconditionally would rewrite every page in
      // every notebook on the next save and hand the sync log a diff for all
      // of them, for a setting nobody turned on.
      final canvas = PageProps();
      expect(canvas.toJson().keys,
          unorderedEquals(['background', 'gridSize', 'pageWidth']));
      final paged = PageProps(layout: 'paged');
      expect(paged.toJson()['layout'], 'paged');
      expect(paged.toJson().containsKey('landscape'), isFalse,
          reason: 'portrait is the default and says nothing');
    });

    test('properties a NEWER build wrote survive the trip', () {
      final p = PageProps.fromJson({'layout': 'paged', 'marginPreset': 'wide'});
      expect(p.toJson()['marginPreset'], 'wide');
    });
  });

  group('the sheet', () {
    test('landscape swaps the dimensions and keeps the name', () {
      final p = PageProps(layout: 'paged', paperSize: 'A4', landscape: true);
      expect(p.paper.name, 'A4');
      expect(p.paper.width, PaperSize.a4.height);
      expect(p.paper.height, PaperSize.a4.width);
    });

    test('an unknown paper name falls back rather than throwing', () {
      // The name comes out of a file that may have been written by anything.
      expect(PaperSize.byName('Papyrus').name, 'A4');
      expect(PaperSize.byName(null).name, 'A4');
    });

    test('the surface is a whole number of sheets', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.setPageLayout('paged');
      final paper = app.pageProps.paper;
      expect(app.pageSize().width, paper.width,
          reason: 'a sheet never grows sideways — that is what makes it one');
      expect(app.pageSize().height, paper.height);
      expect(app.sheetCount, 1);

      // Content past the bottom of sheet one earns a second sheet, whole.
      app.blocks = [
        Block(
            type: BlockType.text,
            x: 64,
            y: paper.height + 40,
            w: 400,
            h: 100,
            content: {'text': 'overflow'})
      ];
      expect(app.sheetCount, 2);
      expect(app.pageSize().height, paper.height * 2);
    });

    test('canvas mode is untouched by any of it', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      expect(app.pageProps.isPaged, isFalse, reason: 'canvas is the default');
      final before = app.pageSize();
      expect(before.width, greaterThanOrEqualTo(app.pageProps.pageWidth));
      expect(app.sheetCount, 1);
    });
  });

  group('switching to pages', () {
    test('an empty page gets the one big box, full width', () {
      // "Basically ends up being just one really big box."
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      expect(app.blocks, isEmpty);
      app.setPageLayout('paged');

      expect(app.blocks, hasLength(1));
      final body = app.blocks.single;
      expect(body.type, BlockType.text);
      expect(app.sheetBody(), isNotNull);
      final area = app.sheetTextArea();
      expect(body.x, area.left);
      expect(body.w, area.width);
      expect(body.content['autoWidth'], isFalse,
          reason: 'a document body is a column, not a box that hugs its text');
    });

    test('a page you already laid out keeps its boxes', () {
      // Reflowing somebody's freeform layout into a column is a destructive
      // guess. The boxes are still theirs to move.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.blocks = [
        Block(type: BlockType.text, x: 100, y: 200, w: 300, content: {'text': 'a'}),
        Block(type: BlockType.text, x: 500, y: 400, w: 300, content: {'text': 'b'}),
      ];
      app.setPageLayout('paged');
      expect(app.blocks, hasLength(2), reason: 'nothing added, nothing removed');
      expect(app.blocks.map((b) => b.content['text']), ['a', 'b']);
    });

    test('boxes are pulled inside the paper', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final wide = Block(
          type: BlockType.text, x: 2000, y: 300, w: 3000, content: {'text': 'x'});
      app.blocks = [wide];
      app.setPageLayout('paged');

      final paper = app.pageProps.paper;
      expect(wide.w, lessThanOrEqualTo(paper.width),
          reason: 'too wide to fit is narrowed rather than hidden');
      expect(wide.x + wide.w, lessThanOrEqualTo(paper.width),
          reason: 'and pulled back onto the sheet');
      expect(wide.x, greaterThanOrEqualTo(AppState.sheetMargin));
    });

    test('and switching back to canvas keeps everything', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.setPageLayout('paged');
      final body = app.blocks.single;
      body.content['text'] = 'An essay, mostly finished.';
      app.setPageLayout('canvas');
      expect(app.pageProps.isPaged, isFalse);
      expect(app.blocks.single.content['text'], 'An essay, mostly finished.');
      expect(app.sheetBody(), isNull, reason: 'no body on an open canvas');
    });

    test('it is one undo away', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.setPageLayout('paged');
      expect(app.blocks, hasLength(1));
      app.undo();
      expect(app.pageProps.isPaged, isFalse);
      expect(app.blocks, isEmpty);
    });
  });

  group('paper size', () {
    test('changing it re-shapes the sheet', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.setPageLayout('paged');
      expect(app.pageSize().width, PaperSize.a4.width);
      app.setPageLayout('paged', paper: 'Letter');
      expect(app.pageSize().width, PaperSize.letter.width);
      expect(app.pageProps.paperSize, 'Letter');
    });

    test('a new page inherits the shape of the one you were on', () async {
      // A notebook you are writing an essay in must not drop back to open
      // canvas every time you start the next page.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.setPageLayout('paged', paper: 'Legal', landscape: true);
      await app.addPage();
      expect(app.pageProps.isPaged, isTrue);
      expect(app.pageProps.paperSize, 'Legal');
      expect(app.pageProps.landscape, isTrue);
      expect(app.sheetBody(), isNotNull, reason: 'and it has its body box');
    });

    test('a new page after a CANVAS page stays canvas', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await app.addPage();
      expect(app.pageProps.isPaged, isFalse);
      expect(app.blocks, isEmpty, reason: 'canvas pages start empty');
    });
  });
}
