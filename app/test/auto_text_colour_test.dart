// Default text colour on top of a slide.
//
// The owner: *"when typing on a PDF, auto text colour should work like auto
// ink colour where it adjusts between black and white based on the PDF."*
//
// The pen has worked this way since the same thing was reported about ink —
// `auto` meant "contrast with the PAGE", so in dark mode it wrote white on
// the white scan somebody was annotating. A document brings its own
// background, so what is on top of it contrasts with the document. Text was
// the half that never got the rule.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/text_block_view.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_autotext_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Slides');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    await app
        .selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
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

  /// A slide as `pdf_import.dart` writes one: a locked picture with its own
  /// proportions and no stored height.
  Block slide() => app.addBlock(Block(
        type: BlockType.image,
        x: 0,
        y: 0,
        w: 800,
        content: {
          'pdf': 'sha256:deck',
          'page': 0,
          'mime': 'application/pdf',
          'naturalW': 800,
          'naturalH': 1000,
          'locked': true,
        },
      ))
    ..x = 0
    ..y = 0;

  Block noteAt(double x, double y) =>
      app.addBlock(Block(type: BlockType.text, x: x, y: y, w: 200, content: {
        'text': 'annotation',
      }))
        ..x = x
        ..y = y;

  test('A BOX ON A SLIDE IS DARK IN EITHER THEME', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    slide();
    final note = noteAt(100, 300);
    expect(app.overDocument(note), isTrue);

    for (final dark in [false, true]) {
      expect(
          TextBlockView.baseStyle(note,
                  dark: dark, onDocument: app.overDocument(note))
              .color,
          OnoteColors.graphite900,
          reason: 'white text on a white scan is the reported bug');
    }
  });

  test('AND A BOX ON THE PAGE STILL FOLLOWS THE THEME', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    slide();
    final note = noteAt(100, 1400); // below the slide
    expect(app.overDocument(note), isFalse);

    expect(
        TextBlockView.baseStyle(note, dark: true, onDocument: false).color,
        OnoteColors.moon100);
    expect(
        TextBlockView.baseStyle(note, dark: false, onDocument: false).color,
        OnoteColors.graphite700);
  });

  test('the slide itself is not on a document', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final s = slide();
    expect(app.overDocument(s), isFalse,
        reason: 'a picture does not sit on itself, and asking would make '
            'every slide a slide on a slide');
  });

  test('a slide with no stored height still has its real rectangle', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final s = slide();
    expect(s.h, isNull, reason: 'the importer stores a width and no height');
    expect(app.blockRect(s).height, 1000,
        reason: 'from its own proportions, which the alignment guides used to '
            'miss — they fell back to a sixty-pixel strip');
  });
}
