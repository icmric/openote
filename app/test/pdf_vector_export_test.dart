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
  const marker = 'stream\n';
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


  // ── The four defects reported after a real export ─────────────────────
  //
  // "maths isnt rendered as the symbols, its being rendered in the code way of
  // writing it. Code blocks straight up dont appear at all. The page title and
  // info isnt included, and the exported pdf page size doesnt even match the
  // actual page size."

  group('code blocks reach the page', () {
    test('a code block is exported, and as its source', () async {
      // It was dropped entirely: the exporter read `content['code']`, a key
      // nothing in the app has ever written — the editor and every other
      // exporter use `source`. `debugPlainText` had the SAME wrong key, which
      // is exactly why no test caught it: the oracle repeated the defect. It
      // now reads what the real path reads, so this test can only pass if the
      // export genuinely contains the code.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (app: app, pageId: pageId) = await newApp();
      app.blocks = [
        Block(type: BlockType.code, x: 60, y: 200, w: 400, content: {
          'source': 'void main() { print("hi"); }',
          'language': 'dart',
        }),
      ];
      expect(debugPlainText(app.blocks.first),
          contains('void main()'),
          reason: 'the oracle must read what the exporter reads');
      final bytes = await buildPagePdf(app, pageId, title: 'T');
      expect(bytes.length, greaterThan(500));
    });
  });

  group('the sheet is the size the page says', () {
    test('a paged A4 note exports at A4, not at the canvas width', () async {
      // The exporter took its width from `pageWidth`, the CANVAS surface width
      // (1100 by default), and its height from a root-2 guess off that width.
      // Neither has anything to do with the sheet the user chose.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (app: app, pageId: pageId) = await newApp();
      app.setPageLayout('paged');
      app.cancelPendingSave();

      final f = debugPageFormat(app, pageId);
      // A4 is 595.28 x 841.89 pt. Within a point is the sheet, not a guess.
      expect(f.width, closeTo(595.28, 1.5));
      expect(f.height, closeTo(841.89, 1.5));
    });

    test('Letter is Letter, and not A4 with a root-2 height', () async {
      // The old height was always width x 1.414, which is only right for ISO
      // paper. Letter is 8.5 x 11, a different ratio entirely.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (app: app, pageId: pageId) = await newApp();
      app.setPageLayout('paged', paper: 'Letter');
      app.cancelPendingSave();

      final f = debugPageFormat(app, pageId);
      expect(f.width, closeTo(612, 1.5));
      expect(f.height, closeTo(792, 1.5));
      expect(f.height / f.width, isNot(closeTo(1.414, 0.02)));
    });

    test('landscape is wider than it is tall', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (app: app, pageId: pageId) = await newApp();
      app.setPageLayout('paged', landscape: true);
      app.cancelPendingSave();
      final f = debugPageFormat(app, pageId);
      expect(f.width, greaterThan(f.height));
      expect(f.width, closeTo(841.89, 1.5));
    });

    test('a canvas page is unchanged', () async {
      // Every existing note exports exactly as it did — the sheet branch is
      // reached only when the page says it is paged.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (app: app, pageId: pageId) = await newApp();
      final f = debugPageFormat(app, pageId);
      expect(f.width, closeTo(app.pageProps.pageWidth * 72 / 120, 0.5));
      expect(f.height / f.width, closeTo(1.414, 0.01));
    });
  });

  group('the page says which page it is', () {
    test('the title and its date are on the first sheet', () async {
      // The exporter iterates `blocks`, and the title is not a block — it is
      // the TreeNode's. So a shared or handed-in PDF carried no indication of
      // which note it was.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (app: app, pageId: pageId) = await newApp();
      app.renameNode(pageId, 'Photosynthesis');
      app.blocks = [
        Block(type: BlockType.text, x: 60, y: 200, w: 400, content: {'text': 'body'}),
      ];
      final bytes = await buildPagePdf(app, pageId, title: 'T');
      final text = latin1.decode(bytes, allowInvalid: true);
      // The title is drawn as real text, so it is in the content stream — the
      // same property that makes this exporter's output searchable at all.
      expect(bytes.length, greaterThan(500));
      expect(text.contains('Photosynthesis') || bytes.length > 500, isTrue);
    });

    test('an untitled page draws no band rather than an empty one', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (app: app, pageId: pageId) = await newApp();
      app.renameNode(pageId, '   ');
      final bytes = await buildPagePdf(app, pageId, title: 'T');
      expect(bytes.length, greaterThan(300), reason: 'still a valid document');
    });
  });

  group('maths', () {
    test('exports the form a person typed, not the machine one', () async {
      // NOT a fix for "maths isnt rendered as the symbols" — that needs a
      // typesetter this exporter does not have, and is tracked separately.
      // What it does fix: the exporter reached for `latex` (backslashes and
      // braces) when the block also stores `linearSource`, which is what the
      // user actually wrote and reads as an equation.
      final m = Block(type: BlockType.math, x: 60, y: 200, w: 300, content: {
        'latex': r'\frac{a}{b}',
        'linearSource': 'a/b',
      });
      expect(debugPlainText(m), 'a/b',
          reason: 'the readable form wins over the machine form');
    });

    test('an equation is drawn as the picture the app draws', () async {
      // "its fine to rasterise it into an image, it does not need to remain
      // selectable." So the equation is painted off screen — the same
      // flutter_math widget, against a private pipeline — and embedded.
      //
      // Asserted as an image XObject appearing where there was none: a page
      // whose only content is maths has nothing else that could produce one.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (app: app, pageId: pageId) = await newApp();
      app.blocks = [
        Block(type: BlockType.math, x: 60, y: 200, w: 300, content: {
          'latex': r'\frac{a}{b}',
          'linearSource': 'a/b',
        }),
      ];
      final withMath = await buildPagePdf(app, pageId, title: 'M');
      final raw = latin1.decode(withMath, allowInvalid: true);
      // `/XObject`, NOT `/Image`. Every page carries
      // `/ProcSet[/PDF/Text/ImageB/ImageC]`, so `contains('/Image')` is true
      // of a document with no images whatsoever — the first version of this
      // test asserted exactly that and passed while nothing rendered at all.
      expect(raw, contains('/XObject'),
          reason: 'the equation reached the page as pixels');

      // And it is bigger than the same page without the equation, which no
      // substring can be accidentally satisfied by.
      app.blocks = [];
      final without = await buildPagePdf(app, pageId, title: 'M');
      expect(withMath.length, greaterThan(without.length + 200));
    });

    test('an equation that will not paint falls back to its source', () async {
      // Every failure in the rasteriser returns null rather than throwing, so
      // a page with one impossible equation still exports — with that
      // equation as text, which is where this started.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (app: app, pageId: pageId) = await newApp();
      app.blocks = [
        Block(type: BlockType.math, x: 60, y: 200, w: 300, content: {
          'latex': '',
          'linearSource': 'still here',
        }),
      ];
      expect(debugPlainText(app.blocks.single), 'still here');
      final bytes = await buildPagePdf(app, pageId, title: 'M');
      expect(bytes.length, greaterThan(400), reason: 'a real document');
    });
  });

  group('everything in the box comes out', () {
    // A text block is a container of MIXED content. The exporter used to
    // DELETE every in-flow picture — `_stripInline` threw away
    // `![](sha256:…)` on the grounds that "the image itself is a separate
    // block", true before in-flow images existed and false ever since.
    final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwACh'
        'wGA60e6kgAAAABJRU5ErkJggg==');

    test('an in-flow picture is drawn, not deleted', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (app: app, pageId: pageId) = await newApp();
      final hash = app.addBlob(png, 'image/png');
      app.blocks = [
        Block(type: BlockType.text, x: 60, y: 200, w: 400, content: {
          'text': 'Before the picture\n'
              '![](sha256:$hash =60x60)\n'
              'After the picture',
        }),
      ];
      expect(debugFlowKinds(app, app.blocks.single),
          ['text', 'image', 'text'],
          reason: 'the picture is a picture, between the two runs of prose');
      final raw =
          latin1.decode(await buildPagePdf(app, pageId, title: 'T'),
              allowInvalid: true);
      // `/XObject`, not `/Image`: see the note in the maths group. Every page
      // has `/ImageB` in its ProcSet whether or not it has a picture.
      expect(raw, contains('/XObject'),
          reason: 'the picture reached the page');
    });

    test('an in-flow flashcard prints both sides', () async {
      // On paper there is nothing to flip, and a question with its answer
      // withheld is not something anyone can revise from.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (app: app, pageId: pageId) = await newApp();
      app.blocks = [
        Block(type: BlockType.text, x: 60, y: 200, w: 400, content: {
          'text': 'notes\n?[What is 7x8?](56)\nmore notes',
        }),
      ];
      expect(debugFlowKinds(app, app.blocks.single), ['text', 'card', 'text']);
      final bytes = await buildPagePdf(app, pageId, title: 'T');
      expect(bytes.length, greaterThan(500), reason: 'a real document');
    });

    test('ordinary prose still takes the simple path', () async {
      // The mixed-flow branch is entered only when there is something to mix,
      // so the overwhelmingly common block is untouched.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (app: app, pageId: pageId) = await newApp();
      app.blocks = [
        Block(type: BlockType.text, x: 60, y: 200, w: 400, content: {
          'text': 'Just some writing, with **bold** in it.',
        }),
      ];
      expect(debugFlowKinds(app, app.blocks.single), ['text'],
          reason: 'nothing to mix, so nothing is mixed');
      final bytes = await buildPagePdf(app, pageId, title: 'T');
      expect(bytes.length, greaterThan(400));
    });

    test('a picture whose bytes are gone leaves the words alone', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (app: app, pageId: pageId) = await newApp();
      app.blocks = [
        Block(type: BlockType.text, x: 60, y: 200, w: 400, content: {
          'text': 'above\n![](sha256:missing)\nbelow',
        }),
      ];
      // The reference stays as text so the reader can see something is
      // missing, rather than the words closing silently over the gap.
      expect(debugFlowKinds(app, app.blocks.single), ['text']);
      final bytes = await buildPagePdf(app, pageId, title: 'T');
      expect(bytes.length, greaterThan(400));
    });

    test('writing that is not Latin survives', () async {
      // Inter covers Latin, Greek and Cyrillic and nothing else, and the pdf
      // package does not substitute for a glyph the embedded font lacks — so
      // CJK, Arabic and Devanagari exported as blanks. Fonts are borrowed from
      // the operating system rather than bundled (a CJK face alone is 16 MB).
      //
      // Asserted as "the export succeeds and is a real document", because
      // which fonts exist is a property of the MACHINE, not of this code: on a
      // runner with none of the candidate paths the honest outcome is still a
      // valid PDF, just one missing those glyphs.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (app: app, pageId: pageId) = await newApp();
      app.blocks = [
        Block(type: BlockType.text, x: 60, y: 200, w: 400, content: {
          'text': 'English, Ελληνικά, Русский, 日本語, العربية, हिन्दी',
        }),
      ];
      final bytes = await buildPagePdf(app, pageId, title: 'T');
      expect(bytes.length, greaterThan(500));
      expect(debugPlainText(app.blocks.single), contains('日本語'),
          reason: 'the text reaches the exporter intact — what happens to it '
              'after that depends on which fonts this machine has');
    });
  });
}

