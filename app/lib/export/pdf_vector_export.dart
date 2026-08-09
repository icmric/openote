/// Vector PDF export (OPEN-7) — text as text, ink as paths.
///
/// **Why this replaces the raster capture.** Students share notes as PDFs; it is
/// the one export a classmate will actually open. The previous exporter
/// screenshotted the canvas at 2×, which meant the result was unsearchable,
/// unselectable, enormous, and blurry when zoomed — three of the four things
/// people do with a shared PDF. It also made "print revision sheets" pointless.
///
/// So every block is emitted as real PDF content:
///
/// - **text** becomes PDF text runs in the bundled Inter face, so Ctrl+F works
///   in any reader and the file is a few hundred KB rather than tens of MB;
/// - **ink** becomes stroked paths, so a diagram stays crisp at any zoom;
/// - **images** are embedded once, at their stored bytes.
///
/// **Pagination is the other half.** An Openote page is one tall canvas — a PDF
/// printout of a 40-slide deck is metres long — so the canvas is sliced into
/// sheets and every block is drawn into whichever sheets it overlaps, with the
/// clip doing the cutting. A block that straddles a boundary appears on both,
/// cut at the fold, which is what a printer does and what the reader expects.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:flutter/material.dart' show Colors, SizedBox, TextStyle;
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:pdf/widgets.dart' as pw;

import '../canvas/ink_painter.dart' show colorFromHex;
import '../media/pdf_pages.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import 'md_common.dart';
import 'pdf_export.dart' show buildPageRasterPdf;
import 'widget_raster.dart';

/// Page px per PDF point.
///
/// The canvas works in a 120 dpi space (the OneNote importer's unit), and PDF
/// points are 72 dpi, so 120/72 keeps an exported page the physical size it
/// claims to be — an A4-width note comes out A4 width.
const double _pxPerPoint = 120.0 / 72.0;

/// Sheet height, in page px, at the page's own width.
///
/// Derived from the page width so the aspect matches whatever the note is set
/// to rather than forcing everything to A4 portrait: a wide "slides" page
/// paginates into wide sheets. √2 is the ISO ratio, which is what makes an A4
/// note print without scaling.
double _sheetHeight(double widthPx) => widthPx * 1.41421356;

/// Export the current page as a vector PDF. Returns the written path.
Future<String?> exportPagePdfVector(AppState app) async {
  final pageId = app.pageId;
  if (pageId == null) return null;
  final page = app.nodes.where((n) => n.id == pageId).firstOrNull;
  if (page == null) return null;

  final location = await getSaveLocation(
    suggestedName: '${safeFilename(page.title, fallback: 'page')}.pdf',
    acceptedTypeGroups: const [
      XTypeGroup(label: 'PDF', extensions: ['pdf'])
    ],
  );
  if (location == null) return null;

  // If the vector build cannot be produced, still produce a PDF. A picture of
  // the page is worse than real text — unsearchable, unselectable, bigger —
  // but it is a document the user can hand in, and "the export failed" is not.
  // The reasoning is theirs: "if we are able to render it on screen there must
  // be a way to render it in the pdf too."
  Uint8List bytes;
  try {
    bytes = await buildPagePdf(app, pageId, title: page.title);
  } catch (_) {
    final fallback = await buildPageRasterPdf(app);
    if (fallback == null) rethrow;
    bytes = fallback;
  }
  await File(location.path).writeAsBytes(bytes);
  return location.path;
}

/// Export a whole section — a lecture deck, a week's notes — as one PDF.
///
/// The unit a student shares is rarely one page. It is also the last piece of
/// the PDF-annotation flagship (Phase B step 4): a deck imported one-slide-per-
/// page comes back out as one document you can hand in.
Future<String?> exportSectionPdfVector(AppState app, String sectionId) async {
  final section = app.nodes.where((n) => n.id == sectionId).firstOrNull;
  if (section == null) return null;
  if (app.pagesOf(sectionId).isEmpty) return null;

  final location = await getSaveLocation(
    suggestedName: '${safeFilename(section.title, fallback: 'section')}.pdf',
    acceptedTypeGroups: const [
      XTypeGroup(label: 'PDF', extensions: ['pdf'])
    ],
  );
  if (location == null) return null;

  final bytes = await buildDeckPdf(app, sectionId, title: section.title);
  await File(location.path).writeAsBytes(bytes);
  return location.path;
}

/// Build the PDF bytes for a page.
///
/// Separated from the file-picker half so printing (P13) and annotated-slide
/// re-export can reuse it, and so it is testable without a UI.
Future<Uint8List> buildPagePdf(AppState app, String pageId,
    {required String title}) async {
  final doc = pw.Document(title: title, creator: 'Openote');
  final theme = await _theme();
  await _addPageSheets(doc, app, pageId, theme);
  return doc.save();
}

/// Build one PDF from every page of a section, in navigator order.
Future<Uint8List> buildDeckPdf(AppState app, String sectionId,
    {required String title}) async {
  final doc = pw.Document(title: title, creator: 'Openote');
  final theme = await _theme();
  for (final p in app.pagesOf(sectionId)) {
    await _addPageSheets(doc, app, p.id, theme);
  }
  return doc.save();
}

/// Append one Openote page to [doc] as one or more sheets.
///
/// Reads the page's **own** properties rather than the open page's — exporting
/// a section means most of these pages are closed, and borrowing the open
/// page's width would have laid every one of them out at the wrong size.
Future<void> _addPageSheets(
    pw.Document doc, AppState app, String pageId, pw.ThemeData? theme) async {
  final data = app.pageId == pageId ? null : app.readPage(pageId);
  final blocks = data?.blocks ?? app.blocks;
  final props = data?.props ?? app.pageProps;

  // Equations are painted BEFORE the document is laid out: rasterising a
  // widget is asynchronous and the sheet builder below is not. One image per
  // math block, keyed by block id. PDF slides join the same map for the same
  // reason — an on-demand slide (storage wave 1c) has no stored pixels until
  // something renders them, and the sheet builder cannot await.
  final maths = await _renderMaths(blocks);
  for (final b in blocks) {
    final pdf = b.content['pdf'];
    if (b.type != BlockType.image || pdf is! String) continue;
    final png = await PdfPages.pageImage(
        app, pdf, (b.content['page'] as num?)?.toInt() ?? 0);
    if (png != null) maths[b.id] = png;
  }

  // Content bounds in page px. The page's own width wins over the content's, so
  // a note narrower than its page still exports at the page size the user set.
  //
  // A PAGED page has a real sheet, and it is not `pageWidth` — that field is
  // the canvas-mode surface width and nothing keeps the two in step. Exporting
  // an A4 page at 1100 px wide is how a sheet the user chose came out the
  // wrong size, and it is why `_sheetHeight`'s root-2 guess is skipped below:
  // guessing the aspect from the width is right for a canvas note and wrong
  // for Letter, Legal or anything landscape.
  final paper = props.isPaged ? props.paper : null;
  final widthPx = paper?.width ?? props.pageWidth;
  var bottomPx = 0.0;
  for (final b in blocks) {
    final h = b.h ?? app.renderSizes[b.id]?.height ?? app.estimatedHeight(b);
    if (b.y + h > bottomPx) bottomPx = b.y + h;
  }
  if (bottomPx <= 0) bottomPx = _sheetHeight(widthPx);

  // A slide keeps its own shape. An imported deck is one full-width locked
  // background image per page, and forcing that onto an ISO sheet would print
  // a 16:9 slide across the top third of a portrait page with a field of white
  // underneath — which is exactly what makes OneNote's printouts unusable to
  // hand in. The sheet becomes the slide, and anything written past its edge
  // extends the sheet rather than starting a second one, so one slide is always
  // one page of the output.
  final slide = paper == null ? _slideHeight(blocks, widthPx) : null;
  final sheetPx = paper?.height ??
      (slide == null
          ? _sheetHeight(widthPx)
          : (bottomPx > slide ? bottomPx : slide));
  final sheets = (bottomPx / sheetPx).ceil().clamp(1, 500);
  final format = PdfPageFormat(widthPx / _pxPerPoint, sheetPx / _pxPerPoint);

  for (var sheet = 0; sheet < sheets; sheet++) {
    final top = sheet * sheetPx;
    final bottom = top + sheetPx;
    // Only what this sheet shows. A block straddling the fold is drawn on both
    // sheets and clipped by the page edge, which is how a printout works.
    final visible = [
      for (final b in blocks)
        if (_overlaps(app, b, top, bottom)) b
    ]..sort((a, b) => a.z.compareTo(b.z));
    if (visible.isEmpty && sheet > 0) continue;

    doc.addPage(pw.Page(
      pageFormat: format,
      theme: theme,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Stack(
        children: [
          // The title band, on the first sheet only — the same place and the
          // same shape the canvas draws it (page_title_view.dart). The exporter
          // iterates `blocks`, and the title is not a block: it lives on the
          // TreeNode. So a PDF of a note came out with no indication of which
          // note it was, which is most of what you need from a page you have
          // shared or handed in.
          if (sheet == 0) ..._titleBand(app, pageId, widthPx),
          for (final b in visible)
            if (_blockWidget(app, b, top, maths) case final w?) w,
        ],
      ),
    ));
  }
}

/// The height of the slide this page IS, or null if it isn't one.
///
/// "Is a slide" means exactly one locked background image, at the top, filling
/// the page width — which is what `pdf_import` writes for one-page-per-slide.
/// Anything else (a note that happens to contain a picture) is a normal page.
/// What a text block decomposes into, in order: `text`, `image` or `card`.
///
/// Exposed because the thing worth testing — that an in-flow picture becomes a
/// PICTURE rather than being deleted — is not observable in the finished file.
/// Once a TTF is embedded the content stream carries glyph indices, not words,
/// which is why no test in here has ever searched the output for note text.
@visibleForTesting
List<String> debugFlowKinds(AppState app, Block b) {
  final text = b.content['text'] as String? ?? '';
  final out = <String>[];
  var pendingText = false;
  for (final line in text.split('\n')) {
    final img = _imageLineRe.firstMatch(line);
    if (img != null && app.blob(img.group(1)!) != null) {
      if (pendingText) {
        out.add('text');
        pendingText = false;
      }
      out.add('image');
      continue;
    }
    if (_cardLineRe.hasMatch(line)) {
      if (pendingText) {
        out.add('text');
        pendingText = false;
      }
      out.add('card');
      continue;
    }
    pendingText = true;
  }
  if (pendingText) out.add('text');
  return out;
}

/// The sheet size the exporter would use for a page, in POINTS.
///
/// Exposed because the defect it guards — "the exported pdf page size doesnt
/// even match the actual page size" — is invisible in the byte stream and
/// trivially checkable here.
@visibleForTesting
PdfPageFormat debugPageFormat(AppState app, String pageId) {
  final data = app.pageId == pageId ? null : app.readPage(pageId);
  final props = data?.props ?? app.pageProps;
  final blocks = data?.blocks ?? app.blocks;
  final paper = props.isPaged ? props.paper : null;
  final widthPx = paper?.width ?? props.pageWidth;
  var bottomPx = 0.0;
  for (final b in blocks) {
    final h = b.h ?? app.renderSizes[b.id]?.height ?? app.estimatedHeight(b);
    if (b.y + h > bottomPx) bottomPx = b.y + h;
  }
  if (bottomPx <= 0) bottomPx = _sheetHeight(widthPx);
  final slide = paper == null ? _slideHeight(blocks, widthPx) : null;
  final sheetPx = paper?.height ??
      (slide == null
          ? _sheetHeight(widthPx)
          : (bottomPx > slide ? bottomPx : slide));
  return PdfPageFormat(widthPx / _pxPerPoint, sheetPx / _pxPerPoint);
}

@visibleForTesting
double? slideHeightOf(List<Block> blocks, double widthPx) =>
    _slideHeight(blocks, widthPx);

double? _slideHeight(List<Block> blocks, double widthPx) {
  Block? found;
  for (final b in blocks) {
    if (b.type != BlockType.image) continue;
    if (b.content['background'] != true || b.content['locked'] != true) continue;
    if (found != null) return null; // two backgrounds: not a slide page
    found = b;
  }
  final h = found?.h;
  if (found == null || h == null) return null;
  if (found.y > 1) return null;
  if ((found.w - widthPx).abs() > 2) return null;
  return found.y + h;
}

bool _overlaps(AppState app, Block b, double top, double bottom) {
  final h = b.h ?? app.renderSizes[b.id]?.height ?? app.estimatedHeight(b);
  return b.y < bottom && b.y + h > top;
}

/// One block, positioned for the sheet starting at [sheetTop].
///
/// Returns null for a block this exporter has nothing useful to say about, so
/// an unknown future block type is skipped rather than drawn as a placeholder.
pw.Widget? _blockWidget(AppState app, Block b, double sheetTop,
    Map<String, Uint8List> maths) {
  final h = b.h ?? app.renderSizes[b.id]?.height ?? app.estimatedHeight(b);
  final left = b.x / _pxPerPoint;
  final top = (b.y - sheetTop) / _pxPerPoint;
  final w = b.w / _pxPerPoint;

  final child = switch (b.type) {
    BlockType.ink => _inkWidget(b, h),
    BlockType.image => _imageWidget(app, b, h, prerendered: maths[b.id]),
    BlockType.math => _mathWidget(b, maths[b.id]),
    BlockType.text || BlockType.code => _textWidget(app, b),
    BlockType.table => _tableWidget(b),
    BlockType.embed => _embedWidget(app, b, h),
    _ => null,
  };
  if (child == null) return null;
  return pw.Positioned(
    left: left,
    top: top,
    child: pw.SizedBox(width: w, child: child),
  );
}

/// A page window (live embed). Print cannot be live, and v1 keeps no
/// snapshot to inline (EMBED-8's fallback), so the export draws the frame
/// with its attribution rather than pretending the content was here.
pw.Widget _embedWidget(AppState app, Block b, double h) {
  final ref = (b.content['ref'] as Map?)?.cast<String, dynamic>();
  final title =
      (app.node(ref?['pageId'] as String? ?? '')?.title ?? '').trim();
  return pw.Container(
    height: h / _pxPerPoint,
    padding: const pw.EdgeInsets.all(4),
    decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: .5)),
    child: pw.Text(
      'Window onto: ${title.isEmpty ? 'another page' : title}',
      style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
    ),
  );
}

/// The page's name and when it was made, drawn where the canvas draws them.
///
/// Positions come from the same constants the screen uses
/// (`AppState.pageLeftMargin`, `titleBandHeight`), so the exported band lines
/// up with the content beneath it rather than being a header invented here.
List<pw.Widget> _titleBand(AppState app, String pageId, double widthPx) {
  final node = app.node(pageId);
  final title = (node?.title ?? '').trim();
  if (title.isEmpty) return const [];
  const left = AppState.pageLeftMargin;
  return [
    pw.Positioned(
      left: left / _pxPerPoint,
      top: 20 / _pxPerPoint,
      child: pw.SizedBox(
        width: (widthPx - left * 2) / _pxPerPoint,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title,
                style: pw.TextStyle(
                    fontSize: 26 / _pxPerPoint,
                    fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6 / _pxPerPoint),
            pw.Text(_dateLine(node?.createdAt ?? 0),
                style: const pw.TextStyle(
                    fontSize: 12 * 72 / 120,
                    color: PdfColors.grey600)),
          ],
        ),
      ),
    ),
  ];
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Kept textually in step with `PageTitleView._dateLine` — the exported page
/// saying a different date to the screen would be its own small betrayal.
String _dateLine(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ap = d.hour < 12 ? 'AM' : 'PM';
  final mm = d.minute.toString().padLeft(2, '0');
  return '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]} ${d.year}'
      '    $h:$mm $ap';
}

/// Text as real text — the whole point of this exporter.
///
/// Markdown markers are stripped rather than styled. Faithful inline styling
/// would mean re-implementing the renderer against the `pdf` package's very
/// different text model; the thing that matters for a shared or printed note is
/// that the words are *there*, selectable and searchable, at roughly the right
/// size. Headings keep their weight because that carries the structure.
pw.Widget? _textWidget(AppState app, Block b) {
  // A text block is a container of MIXED content (Data Model §5.1): pictures
  // and flashcards live on their own lines inside the prose. The exporter used
  // to delete both — `_stripInline` threw away every `![](sha256:…)` on the
  // grounds that "the image itself is a separate block", which was true before
  // in-flow images existed and has been false since. So a picture you put in
  // the middle of your notes simply was not in the PDF.
  if (b.type == BlockType.text) {
    final mixed = _mixedFlow(app, b);
    if (mixed != null) return mixed;
  }
  return _plainTextWidget(b);
}

/// A block whose text carries in-flow pictures or cards, as a column of real
/// widgets. Null when it is ordinary prose, which is the overwhelming majority
/// and keeps the simple path simple.
pw.Widget? _mixedFlow(AppState app, Block b) {
  final text = b.content['text'] as String? ?? '';
  if (!text.contains('![') && !text.contains('?[')) return null;
  final lines = text.split('\n');
  final children = <pw.Widget>[];
  final run = <String>[];

  void flushRun() {
    if (run.isEmpty) return;
    final w = _plainTextWidget(b, override: run.join('\n'));
    if (w != null) children.add(w);
    run.clear();
  }

  for (final line in lines) {
    final img = _imageLineRe.firstMatch(line);
    if (img != null) {
      final bytes = app.blob(img.group(1)!);
      if (bytes != null) {
        flushRun();
        // The stored ` =WxH` is in page px, like everything else here.
        final wPx = double.tryParse(img.group(2) ?? '');
        final hPx = double.tryParse(img.group(3) ?? '');
        try {
          // A picture with no ` =WxH` has no size in POINTS, and leaving it
          // null lets the encoder read its intrinsic PIXEL dimensions as
          // points — a 600px screenshot drawn 8 inches wide. Falling back to
          // the block's own width is what the screen does too.
          final wPt = (wPx ?? b.w) / _pxPerPoint;
          children.add(pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Image(pw.MemoryImage(bytes),
                width: wPt,
                height: hPx == null ? null : hPx / _pxPerPoint,
                fit: pw.BoxFit.contain,
                alignment: pw.Alignment.centerLeft),
          ));
        } catch (_) {
          // An image the encoder cannot read must not take the words with it.
        }
        continue;
      }
      // No bytes: fall through and let the reference print as text, so the
      // reader can see something is missing rather than nothing at all.
    }
    final card = _cardLineRe.firstMatch(line);
    if (card != null) {
      flushRun();
      children.add(_cardWidget(card.group(1) ?? '', card.group(2) ?? ''));
      continue;
    }
    run.add(line);
  }
  flushRun();
  if (children.isEmpty) return null;
  return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start, children: children);
}

/// Kept textually in step with the renderers' own patterns
/// (`md_render._reImage`, `live_markdown_controller._imageLineRe`).
final _imageLineRe =
    RegExp(r'^\s*!\[[^\]]*\]\(([^)\s]+)(?:\s+=(\d+)x(\d+))?\)\s*$');
final _cardLineRe = RegExp(r'^\s*\?\[([^\]]*)\]\(([^)]*)\)\s*$');

/// Paint every equation on the page, once, off screen.
///
/// Returns only what succeeded — a block missing from the map falls back to
/// printing its source, which is what the exporter did for everything before.
Future<Map<String, Uint8List>> _renderMaths(List<Block> blocks) async {
  final out = <String, Uint8List>{};
  for (final b in blocks) {
    if (b.type != BlockType.math) continue;
    final tex = (b.content['latex'] as String? ?? '').trim();
    if (tex.isEmpty) continue;
    // 3x, so the equation is still crisp when the reader zooms in — the whole
    // complaint about the OLD raster exporter was that its output went to mush.
    final png = await rasteriseOffscreen(
      Math.tex(tex,
          textStyle: const TextStyle(fontSize: 24, color: Colors.black),
          onErrorFallback: (_) => const SizedBox.shrink()),
      pixelRatio: 3,
    );
    if (png != null) out[b.id] = png;
  }
  return out;
}

/// An equation as the picture the app draws, or as its source when that could
/// not be painted.
///
/// A picture, and deliberately: "its fine to rasterise it into an image, it
/// does not need to remain selectable". Nothing else in this exporter is
/// rasterised, and the file stays searchable everywhere else — an equation is
/// the one thing nobody Ctrl+Fs for.
pw.Widget? _mathWidget(Block b, Uint8List? png) {
  if (png == null) return _plainTextWidget(b);
  try {
    return pw.Image(pw.MemoryImage(png),
        fit: pw.BoxFit.contain, alignment: pw.Alignment.centerLeft);
  } catch (_) {
    return _plainTextWidget(b);
  }
}

/// A flashcard, printed as both sides. On paper there is nothing to flip, and
/// a question with its answer withheld is not something anyone can revise from.
pw.Widget _cardWidget(String front, String back) => pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 3),
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.7),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(_stripInline(front),
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Text(_stripInline(back),
              style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );

pw.Widget? _plainTextWidget(Block b, {String? override}) {
  // `source`, not `code`. Nothing in the app has ever written `content['code']`
  // — the code editor reads and writes `source` (code_block_view.dart), as do
  // the Markdown and open-folder exporters — so this key missed, `raw` came
  // back null, and every code block was dropped from the PDF in silence. The
  // same wrong key in `debugPlainText` below is why no test caught it: the
  // oracle repeated the defect.
  //
  // `linearSource` is preferred over `latex` for maths because it is what the
  // user actually typed and reads as an equation; `latex` is the machine form,
  // full of backslashes and braces. Neither is SYMBOLS — see the note on
  // _blockWidget.
  final raw = override ??
      (b.content['text'] ??
      b.content['source'] ??
          b.content['linearSource'] ??
          b.content['latex']) as String?;
  if (raw == null || raw.trim().isEmpty) return null;
  final sizePx = (b.content['fontSize'] as num?)?.toDouble() ?? 15.0;
  final size = sizePx / _pxPerPoint;
  // Code keeps a monospaced face — alignment IS the content in a code block.
  final mono =
      b.type == BlockType.code ? (_mono ?? pw.Font.courier()) : null;

  final spans = <pw.TextSpan>[];
  for (final line in raw.split('\n')) {
    // Headings are the one piece of Markdown structure worth keeping: it is
    // what makes a printed note skimmable.
    final heading = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(line);
    final text = heading != null ? heading.group(2)! : _stripInline(line);
    spans.add(pw.TextSpan(
      text: '$text\n',
      style: pw.TextStyle(
        fontSize: heading != null
            ? size * (1.6 - 0.2 * heading.group(1)!.length)
            : size,
        fontWeight: heading != null ? pw.FontWeight.bold : pw.FontWeight.normal,
        font: mono,
        lineSpacing: size * 0.25,
      ),
    ));
  }
  return pw.RichText(text: pw.TextSpan(children: spans));
}

/// The plain text this exporter will draw for [b].
///
/// Exposed because the PDF itself cannot be checked for it: text is written as
/// hex glyph indices into an embedded Inter subset (with a `/ToUnicode` CMap, so
/// readers search and copy it correctly), which means a byte search for a word
/// finds nothing however right the export is. This is the same string the
/// exporter emits, so pinning it here pins what lands on the page.
@visibleForTesting
String debugPlainText(Block b) {
  final raw =
      // The same wrong key the real path had — see `_textWidget`. Keeping the
      // oracle in step with the exporter is the whole reason it exists.
      (b.content['text'] ??
          b.content['source'] ??
          b.content['linearSource'] ??
          b.content['latex']) as String?;
  if (raw == null) return '';
  return [
    for (final line in raw.split('\n'))
      RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(line)?.group(2) ??
          _stripInline(line)
  ].join('\n');
}

/// Drop the inline markers, keeping the words.
String _stripInline(String s) {
  var out = s;
  for (final re in [
    RegExp(r'\*\*(.+?)\*\*'),
    RegExp(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)'),
    RegExp(r'\+\+(.+?)\+\+'),
    RegExp(r'~~(.+?)~~'),
    RegExp(r'==(.+?)=='),
    RegExp(r'`(.+?)`'),
    RegExp(r'\{\{#[0-9A-Fa-f]{6,8} (.+?)\}\}'),
    RegExp(r'\[\[([^\]|]+)(?:\|[^\]]+)?\]\]'),
  ]) {
    out = out.replaceAllMapped(re, (m) => m.group(1) ?? '');
  }
  // An in-flow image reference has no textual meaning; the image itself is a
  // separate block, so leaving the raw `![](sha256:…)` would just be noise.
  out = out.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '');
  return out;
}

pw.Widget? _tableWidget(Block b) {
  final rows = (b.content['cells'] as List?) ?? const [];
  if (rows.isEmpty) return null;
  return pw.Table(
    border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey600),
    children: [
      for (final r in rows)
        pw.TableRow(children: [
          for (final c in (r as List? ?? const []))
            pw.Padding(
              padding: const pw.EdgeInsets.all(3),
              child: pw.Text(_stripInline(c?.toString() ?? ''),
                  style: const pw.TextStyle(fontSize: 8)),
            ),
        ]),
    ],
  );
}

pw.Widget? _imageWidget(AppState app, Block b, double h,
    {Uint8List? prerendered}) {
  final wPt = b.w / _pxPerPoint;
  final hPt = h / _pxPerPoint;

  // The picture, if it can be drawn at all. A missing blob or an image the PDF
  // encoder can't read (an odd PNG variant) must not take the whole export
  // down — and, since the text layer below is independent of it, must not take
  // the slide's *words* with it either. Losing the picture is bad; losing the
  // picture and silently losing everything written on it is worse.
  //
  // [prerendered] is an on-demand PDF slide's pixels, painted in the async
  // pass above; a stored image still reads its own blob here.
  pw.Widget? image;
  final ref = b.content['blob'] as String?;
  final bytes = prerendered ?? (ref == null ? null : app.blob(ref));
  if (bytes != null) {
    try {
      image = pw.Image(pw.MemoryImage(bytes),
          width: wPt, height: hPt, fit: pw.BoxFit.fill);
    } catch (_) {
      image = null;
    }
  }

  // An imported slide carries the text pdfium pulled out of it. Emitting it
  // closes the loop the importer opened: "the slide's text stays searchable"
  // was true inside Openote and stopped being true the moment the annotated
  // deck was exported to hand in — the picture went out, the words did not.
  final source = b.content['sourceText'];
  final searchable = source is String && source.trim().isNotEmpty
      ? _searchableLayer(source, wPt, hPt)
      : null;

  if (image == null) return searchable;
  if (searchable == null) return image;
  return pw.Stack(children: [image, searchable]);
}

/// The slide's text, present to a reader but not to the eye.
///
/// Rendering mode 3 is the PDF standard's own "neither fill nor stroke" — the
/// technique every OCR layer uses. The glyphs are real text operators in the
/// content stream, so Ctrl+F, copy-paste and any indexer see them; nothing is
/// painted, so the slide looks exactly as it did.
///
/// **What this layer is not:** per-word positioned. pdfium hands us the page's
/// text in reading order, not a box per word, so selecting part of the slide
/// gives you the whole slide's text rather than the phrase under the cursor.
/// Searching — which is what the feature promised — works either way, and
/// per-word geometry is a much larger piece of pdfium plumbing.
pw.Widget _searchableLayer(String text, double wPt, double hPt) => pw.SizedBox(
      width: wPt,
      height: hPt,
      child: pw.ClipRect(
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: _invisibleFontSize(wPt, hPt, text.length),
            renderingMode: PdfTextRenderingMode.invisible,
          ),
        ),
      ),
    );

/// A size at which [chars] characters fit inside [wPt]×[hPt].
///
/// Sized to fit rather than fixed, because the layer is clipped to the slide
/// and a font too large for a text-heavy slide would push the tail outside the
/// box — losing exactly the words a search was most likely to be for. Assumes
/// an average glyph around half the point size wide and lines at 1.2×, which is
/// close enough for a bound that only has to avoid overflow.
@visibleForTesting
double invisibleFontSize(double wPt, double hPt, int chars) =>
    _invisibleFontSize(wPt, hPt, chars);

double _invisibleFontSize(double wPt, double hPt, int chars) {
  if (chars <= 0) return 6;
  // capacity(s) ≈ (w / 0.5s) * (h / 1.2s) = w*h / 0.6s²  ⇒  s = √(w*h/0.6n)
  final s = math.sqrt((wPt * hPt) / (0.6 * chars));
  return s.clamp(0.5, 8.0);
}

/// Ink as stroked PDF paths.
///
/// A polyline through the sample points, stroked with a round join and cap,
/// rather than the tessellated variable-width outline the screen uses.
/// Reproducing perfect-freehand's outline as a filled path would be closer to
/// the screen, but it multiplies the point count by ~4 and a 65 000-stroke
/// notebook is already the biggest thing in the file — and at print resolution
/// the difference is a fraction of a millimetre of nib shape.
pw.Widget? _inkWidget(Block b, double h) {
  final raw = (b.content['strokes'] as List?) ?? const [];
  if (raw.isEmpty) return null;
  final strokes = <Stroke>[];
  for (final s in raw) {
    if (s is Map) strokes.add(Stroke.fromJson(s.cast<String, dynamic>()));
  }
  if (strokes.isEmpty) return null;

  // Stroke coordinates are page-absolute; the widget is positioned at the
  // block's origin, so draw relative to it.
  final ox = b.x, oy = b.y;
  return pw.SizedBox(
    width: b.w / _pxPerPoint,
    height: h / _pxPerPoint,
    child: pw.CustomPaint(
      size: PdfPoint(b.w / _pxPerPoint, h / _pxPerPoint),
      painter: (canvas, size) {
        for (final s in strokes) {
          if (s.x.length < 2) continue;
          final c = s.colorHex == 'auto'
              ? const PdfColor(0.13, 0.12, 0.11)
              : _pdfColor(s.colorHex);
          canvas
            ..setStrokeColor(c)
            ..setLineWidth(
                (s.size * (s.tool == 'highlighter' ? 3 : 1)) / _pxPerPoint)
            ..setLineCap(PdfLineCap.round)
            ..setLineJoin(PdfLineJoin.round)
            ..setGraphicState(PdfGraphicState(strokeOpacity: s.opacity));
          // PDF's y axis points UP from the bottom-left; the canvas's points
          // down from the top-left. Flip inside the block's own box.
          double fy(double v) => size.y - (v - oy) / _pxPerPoint;
          canvas.moveTo((s.x.first - ox) / _pxPerPoint, fy(s.y.first));
          for (var i = 1; i < s.x.length && i < s.y.length; i++) {
            canvas.lineTo((s.x[i] - ox) / _pxPerPoint, fy(s.y[i]));
          }
          canvas.strokePath();
        }
      },
    ),
  );
}

PdfColor _pdfColor(String hex) {
  final c = colorFromHex(hex);
  return PdfColor(c.r, c.g, c.b);
}

/// The document theme, using the bundled Inter so exported text carries the
/// same glyph coverage the app has — a maths note full of ∀ ∃ ⊆ would otherwise
/// export with holes in it, since the PDF standard fonts are Latin-1 only.
/// The embedded monospace face, once the theme has loaded it. Null in a test
/// harness with no assets, where [_textWidget] falls back to Courier.
pw.Font? _mono;

/// Faces borrowed from the operating system so writing that is not Latin
/// survives the export.
///
/// Inter covers Latin, Greek and Cyrillic and nothing else — so a note with
/// Chinese, Japanese, Korean, Arabic, Hebrew, Thai or Devanagari in it came
/// out blank. The `pdf` package does not substitute for a glyph the embedded
/// font lacks; it has to be handed an alternative.
///
/// BORROWED, not bundled, and that is a trade made deliberately: a CJK face
/// alone is 16 MB or more, which would roughly double an install already
/// larger than the user wants (docs/planning/install-size-findings.md). Every
/// desktop that can DISPLAY these scripts already has a font for them, so the
/// export reads one off disk when it needs one and embeds only the glyphs used.
///
/// All best-effort: a missing path, a format the encoder will not read, a
/// locked file — each is skipped. An export that loses a script is bad; one
/// that fails outright because a font moved is worse.
///
/// **What this reaches, and what it does not.** Greek, Cyrillic, Arabic,
/// Hebrew, Thai and the Indic scripts are covered on every desktop. Chinese,
/// Japanese and Korean usually are NOT on Windows or macOS, because the system
/// faces for them are `.ttc` collections the encoder cannot read; on Linux,
/// Noto's plain OTF build does work. Bundling a CJK face would fix it
/// everywhere and cost 16 MB — a decision that belongs with the install-size
/// work, not here.
Future<List<pw.Font>> _systemFallbacks() async {
  final cached = _systemFallbackCache;
  if (cached != null) return cached;
  // **No `.ttc`.** A TrueType Collection holds several faces in one file and
  // the `pdf` package's parser cannot read one — and it fails at LAYOUT, deep
  // inside `Document.save`, not when the bytes are loaded. So a collection in
  // this list does not degrade an export, it destroys it. That rules out most
  // of Windows' and macOS's CJK faces, which are all collections.
  final candidates = <String>[
    // Windows. Tahoma is the wide one: Greek, Cyrillic, Arabic, Hebrew, Thai.
    r'C:\Windows\Fonts\tahoma.ttf',
    r'C:\Windows\Fonts\Nirmala.ttf', // Devanagari and the Indic scripts
    r'C:\Windows\Fonts\malgun.ttf', // Korean
    // macOS.
    '/Library/Fonts/Arial Unicode.ttf',
    '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
    // Linux, where Noto is the near-universal answer and ships as plain TTF.
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/usr/share/fonts/truetype/noto/NotoSansArabic-Regular.ttf',
    '/usr/share/fonts/truetype/noto/NotoSansDevanagari-Regular.ttf',
    '/usr/share/fonts/opentype/noto/NotoSansCJKsc-Regular.otf',
  ];
  final out = <pw.Font>[];
  for (final path in candidates) {
    if (out.length >= 3) break; // enough coverage; each one costs memory
    try {
      if (path.endsWith('.ttc')) continue; // see above
      final f = File(path);
      if (!f.existsSync()) continue;
      out.add(pw.Font.ttf(ByteData.sublistView(await f.readAsBytes())));
    } catch (_) {
      // Unreadable, or a format the encoder rejects — try the next.
    }
  }
  return _systemFallbackCache = out;
}

List<pw.Font>? _systemFallbackCache;

Future<pw.ThemeData?> _theme() async {
  try {
    final regular = pw.Font.ttf(
        await rootBundle.load('assets/fonts/inter/Inter-Regular.ttf'));
    final bold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/inter/Inter-SemiBold.ttf'));
    final italic = pw.Font.ttf(
        await rootBundle.load('assets/fonts/inter/Inter-Italic.ttf'));
    // The app's own code face, embedded. `pw.Font.courier()` is a PDF base-14
    // font and costs no embedding, which is why it was reached for — but it is
    // WinAnsi only, so a code block containing an arrow, an accent or a box
    // character loses those glyphs on the way out. Alignment IS the content in
    // a code block; silently dropping characters from one is worse than the
    // ~270 KB.
    _mono = pw.Font.ttf(await rootBundle
        .load('assets/fonts/jetbrains-mono/JetBrainsMono-Regular.ttf'));
    return pw.ThemeData.withFont(
      base: regular,
      bold: bold,
      italic: italic,
      fontFallback: [if (_mono != null) _mono!, ...await _systemFallbacks()],
    );
  } catch (_) {
    // No bundled font (a test harness without assets): fall back to the PDF
    // standard faces rather than failing the export.
    return null;
  }
}
