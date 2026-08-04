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
}
