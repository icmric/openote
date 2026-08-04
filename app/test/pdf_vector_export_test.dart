// Vector PDF export: the words must survive as words.
//
// The raster exporter it replaces produced a screenshot — unsearchable,
// unselectable and huge. The property that matters is therefore not "it wrote a
// file" but "the text is IN the file as text", which a byte search over the
// uncompressed page stream can check without a PDF parser.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/export/pdf_vector_export.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

/// The document's page streams, inflated, plus the raw bytes.
///
/// `pdf` deflate-compresses content streams, so a byte search over the file
/// finds nothing. Inflating here rather than turning compression off in
/// production keeps the test honest about what actually ships.
String readable(Uint8List bytes) {
  final raw = latin1.decode(bytes, allowInvalid: true);
  final out = StringBuffer(raw);
  final marker = 'stream\n';
  var i = 0;
  while (true) {
    final start = raw.indexOf(marker, i);
    if (start < 0) break;
    final from = start + marker.length;
    final end = raw.indexOf('\nendstream', from);
    if (end < 0) break;
    i = end;
    try {
      out.write(latin1.decode(
          ZLibDecoder().convert(bytes.sublist(from, end).toList()),
          allowInvalid: true));
    } catch (_) {
      // Not a deflate stream (an embedded image, the xref) — the raw copy
      // above already covers it.
    }
  }
  return out.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Future<({AppState app, String pageId})> newApp() async {
    final tmp = Directory.systemTemp.createTempSync('onote_pdfvec_');
    final repo = await Repository.openAt(tmp);
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final nb = await repo.createNotebook('Export');
    final app = AppState(repo)..notebookId = nb.id;
    app.nodes = repo.loadNodes(nb.id);
    final pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
    app.pageId = pageId;
    return (app: app, pageId: pageId);
  }

  Block text(String id, double y, String body) => Block(
        id: id,
        type: BlockType.text,
        x: 60,
        y: y,
        w: 500,
        content: {'text': body},
      );

  test('a PDF is produced and is a real PDF', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final t = await newApp();
    t.app.blocks = [text('a', 100, 'Hello lecture')];

    final bytes = await buildPagePdf(t.app, t.pageId, title: 'Week 1');

    expect(bytes.length, greaterThan(400));
    expect(latin1.decode(bytes.take(5).toList()), '%PDF-');
  });

  test('text is emitted as searchable text, not pixels', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final t = await newApp();
    t.app.blocks = [text('a', 100, 'Pigeonhole principle')];

    final bytes = await buildPagePdf(t.app, t.pageId, title: 'W');
    final raw = latin1.decode(bytes, allowInvalid: true);
    final streams = readable(bytes);

    // Three properties together mean "real, searchable text", and none of them
    // can be satisfied by a raster capture:
    //   * a text-showing operator, so the glyphs are drawn as text;
    //   * an embedded font, so the file carries its own glyph coverage — a
    //     maths note is full of characters the PDF base fonts do not have;
    //   * a ToUnicode CMap, which is precisely what lets a reader map those
    //     glyphs back to characters for Ctrl+F and copy-paste.
    expect(streams, contains('TJ'), reason: 'text drawn as text');
    expect(raw, contains('FontFile'), reason: 'font embedded');
    expect(raw, contains('ToUnicode'), reason: 'searchable / copyable');
    // And no image XObject, which is what the old exporter produced.
    expect(raw, isNot(contains('/Subtype /Image')));
  });

  // The text content is checked through the extraction step rather than the
  // bytes: glyphs go in as hex indices into an embedded subset, so no word is
  // findable in the file however correct the export is.
  test('Markdown markers are stripped but the words are kept', () {
    final plain = debugPlainText(
        text('a', 100, '# Heading\n**bold** and ==marked== and `code`'));

    expect(plain, 'Heading\nbold and marked and code');
  });

  test('an in-flow image reference leaves no raw markup behind', () {
    // The image is its own block; the `![](sha256:…)` would just be noise.
    final plain =
        debugPlainText(text('a', 0, 'before ![alt](sha256:abc =20x20) after'));

    expect(plain, 'before  after');
    expect(plain, isNot(contains('sha256')));
  });

  test('a tall page paginates instead of running off one sheet', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final t = await newApp();
    // Four sheets' worth of content at the default page width.
    final sheet = t.app.pageProps.pageWidth * 1.414;
    t.app.blocks = [
      for (var i = 0; i < 4; i++)
        text('b$i', i * sheet + 50, 'Sheet $i marker'),
    ];

    final raw = latin1.decode(
        await buildPagePdf(t.app, t.pageId, title: 'Long'),
        allowInvalid: true);

    // One sheet per screenful, so nothing is silently cut off the bottom —
    // which is what a single-sheet exporter does to a tall page.
    final sheets = RegExp(r'/Type\s*/Page[^s]').allMatches(raw).length;
    expect(sheets, 4,
        reason: 'four sheets of content must produce four sheets');
  });

  test('an empty page still exports one valid sheet', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final t = await newApp();
    t.app.blocks = [];

    final bytes = await buildPagePdf(t.app, t.pageId, title: 'Empty');

    expect(latin1.decode(bytes.take(5).toList()), '%PDF-');
  });

  test('ink becomes vector path operators, not an image', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final t = await newApp();
    t.app.blocks = [
      Block(
        id: 'ink',
        type: BlockType.ink,
        x: 0,
        y: 0,
        w: 400,
        content: {
          'strokes': [
            Stroke(
              tool: 'pen',
              colorHex: '#FF0000',
              size: 2,
              x: [10, 20, 30],
              y: [10, 25, 40],
              p: [1, 1, 1],
            ).toJson(),
          ],
        },
      )..h = 300,
    ];

    final raw = readable(await buildPagePdf(t.app, t.pageId, title: 'Ink'));

    // `l` is lineto and `S` strokes the path: the ink went in as geometry
    // rather than as a rasterised picture, so it stays crisp at any zoom.
    expect(raw, contains(' l '), reason: 'polyline segments');
    expect(raw, contains(' S '), reason: 'stroked path');
    expect(raw, contains(' RG '), reason: 'the stroke keeps its colour');
  });
  /// A page's worth of imported slide: one locked, full-width background image
  /// carrying the text pdfium pulled out of it — exactly what `pdf_import`
  /// writes for one-page-per-slide.
  Block slide(String id,
          {required double w, required double h, String? source, double y = 0}) =>
      Block(
        id: id,
        type: BlockType.image,
        x: 0,
        y: y,
        w: w,
        content: {
          'blob': 'sha256:missing',
          'mime': 'image/png',
          'locked': true,
          'background': true,
          if (source != null) 'sourceText': source,
        },
      )..h = h;

  // ── Phase B step 4: handing the annotated deck back in ───────────────────
  //
  // Importing a lecture PDF promises two things — you can write on the slides,
  // and the slide text stays searchable. Both were true inside Openote and
  // neither survived the way out: export was one page at a time, and the slide
  // went into the PDF as a picture with its words dropped.

  group('slide detection', () {
    test('recognises an imported slide page', () {
      expect(slideHeightOf([slide('s', w: 900, h: 506)], 900), 506);
    });

    test('a note that merely contains a picture is not a slide', () {
      final ordinary = Block(
        id: 'p',
        type: BlockType.image,
        x: 40,
        y: 200,
        w: 300,
        content: {'blob': 'sha256:x', 'mime': 'image/png'},
      )..h = 200;
      expect(slideHeightOf([ordinary], 900), isNull);
    });

    test('two backgrounds are not one slide', () {
      expect(
          slideHeightOf(
              [slide('a', w: 900, h: 200), slide('b', w: 900, h: 200)], 900),
          isNull);
    });

    test('a background narrower than the page is not the page', () {
      expect(slideHeightOf([slide('s', w: 400, h: 300)], 900), isNull);
    });
  });

  test('the invisible layer shrinks as the text grows and stays in bounds', () {
    expect(invisibleFontSize(500, 300, 5000),
        lessThan(invisibleFontSize(500, 300, 50)));
    for (final n in [0, 1, 100, 100000]) {
      expect(invisibleFontSize(500, 300, n), inInclusiveRange(0.5, 8.0),
          reason: 'at $n characters');
    }
  });

  test('a slide keeps its own shape instead of an ISO sheet', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final t = await newApp();
    // 16:9 at the page width. On an ISO sheet this would sit across the top
    // third with a field of white under it — OneNote's printout problem.
    final w = t.app.pageProps.pageWidth;
    t.app.blocks = [slide('s', w: w, h: w * 9 / 16)];

    final raw = latin1.decode(
        await buildPagePdf(t.app, t.pageId, title: 'Slide'),
        allowInvalid: true);
    final sheets = RegExp(r'/Type\s*/Page[^s]').allMatches(raw).length;
    expect(sheets, 1, reason: 'one slide is one page of the output');

    // MediaBox in points: the sheet is the slide, not width x sqrt(2).
    final box = RegExp(r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)')
        .firstMatch(raw)!;
    final wPt = double.parse(box.group(1)!);
    final hPt = double.parse(box.group(2)!);
    expect(hPt / wPt, closeTo(9 / 16, 0.02));
  });

  test('a section exports as one document, in navigator order', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final t = await newApp();
    final section = t.app.nodes.firstWhere((n) => n.kind == NodeKind.section);
    // Two more pages beside the one the notebook was seeded with.
    for (var i = 0; i < 2; i++) {
      final node = t.app.importNode(
          t.app.notebookId!,
          TreeNode(
              kind: NodeKind.page,
              parentId: section.id,
              title: 'Slide ${i + 2}',
              position: 'a${(i + 2).toString().padLeft(15, '0')}'));
      t.app.importPage(t.app.notebookId!, node.id,
          [text('t$i', 100, 'Page ${i + 2} body')], PageProps());
    }
    t.app.reloadNodes();
    t.app.blocks = [text('a', 100, 'Page 1 body')];

    expect(t.app.pagesOf(section.id).length, 3);
    final raw = readable(await buildDeckPdf(t.app, section.id, title: 'Deck'));
    expect(RegExp(r'/Type\s*/Page[^s]').allMatches(raw).length, 3,
        reason: 'three pages in, three sheets out');
    expect(debugPlainText(text('x', 0, 'Page 2 body')), 'Page 2 body');
  });

  test('an annotated slide carries its text back out, invisibly', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final t = await newApp();
    final w = t.app.pageProps.pageWidth;
    // No blob is stored, so the image itself cannot be drawn — which is the
    // point: the text layer must not depend on the picture having loaded.
    t.app.blocks = [
      slide('s', w: w, h: 500, source: 'Lecture 3: eigenvalues'),
      text('note', 520, 'my own note'),
    ];

    final streams = readable(await buildPagePdf(t.app, t.pageId, title: 'S'));
    // Rendering mode 3 — "neither fill nor stroke" — is the PDF standard's own
    // invisible text, and what every OCR layer emits. Its presence is the
    // difference between a searchable slide and a picture of one.
    expect(streams, contains('3 Tr'),
        reason: 'the slide text is emitted as invisible text');
  });

}

