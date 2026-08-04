// Where an imported PDF printout lands.
//
// Reported: "it will print each page of the PDF to its own new page… I want it
// to insert it onto the current page either at the cursor or below the last
// box, and should insert every PDF page on the one single openote page one
// after the other."
//
// The rendering half needs pdfium and a real file, so these tests pin the
// *placement* decision — which is where the bug was — through the same helper
// the importer uses.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/export/pdf_import.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Future<AppState> newApp() async {
    final tmp = Directory.systemTemp.createTempSync('onote_pdfpos_');
    final repo = await Repository.openAt(tmp);
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final nb = await repo.createNotebook('Slides');
    final app = AppState(repo)..notebookId = nb.id;
    app.nodes = repo.loadNodes(nb.id);
    return app;
  }

  Block img(String id, double y, double h) => Block(
        id: id,
        type: BlockType.image,
        x: 60,
        y: y,
        w: 400,
        content: {'blob': 'sha256:x'},
      )..h = h;

  test('with nothing focused, slides append below the last box', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp();
    app.blocks = [img('a', 100, 200), img('b', 400, 150)];

    final anchor = debugInsertionAnchor(app);

    expect(anchor.top, greaterThanOrEqualTo(550),
        reason: 'below the bottom-most block (400 + 150)');
    expect(anchor.displaced, isEmpty,
        reason: 'appending at the end moves nothing');
  });

  test('with a block focused, slides start below IT and push the rest down',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp();
    final top = img('a', 100, 200);
    final middle = img('b', 400, 100);
    final bottom = img('c', 700, 100);
    app.blocks = [top, middle, bottom];
    app.editingBlockId = 'b';

    final anchor = debugInsertionAnchor(app);

    expect(anchor.top, closeTo(400 + 100 + 36, 0.01),
        reason: 'just below the focused block, not below the whole page');
    expect([for (final b in anchor.displaced) b.id], ['c'],
        reason: 'only what sits below the caret moves; the anchor and anything '
            'above it stay put');
  });

  test('selection counts as the cursor when nothing is being edited', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp();
    app.blocks = [img('a', 100, 200), img('b', 900, 100)];
    app.select('a');

    final anchor = debugInsertionAnchor(app);

    expect(anchor.top, closeTo(100 + 200 + 36, 0.01));
    expect([for (final b in anchor.displaced) b.id], ['b']);
  });

  test('an empty page anchors at the top, not at some stale extent', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp();
    app.blocks = [];

    final anchor = debugInsertionAnchor(app);

    expect(anchor.top, lessThan(400),
        reason: 'an empty page must not push the first slide down the canvas');
    expect(anchor.displaced, isEmpty);
  });
}
