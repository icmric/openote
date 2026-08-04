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
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../canvas/ink_painter.dart' show colorFromHex;
import '../model/models.dart';
import '../state/app_state.dart';
import 'md_common.dart';

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

  final bytes = await buildPagePdf(app, pageId, title: page.title);
  await File(location.path).writeAsBytes(bytes);
  return location.path;
}

/// Build the PDF bytes for a page.
///
/// Separated from the file-picker half so printing (P13) and annotated-slide
/// re-export can reuse it, and so it is testable without a UI.
Future<Uint8List> buildPagePdf(AppState app, String pageId,
    {required String title}) async {
  final blocks =
      app.pageId == pageId ? app.blocks : app.readPage(pageId).blocks;

  final doc = pw.Document(title: title, creator: 'Openote');
  final theme = await _theme();

  // Content bounds in page px. The page's own width wins over the content's, so
  // a note narrower than its page still exports at the page size the user set.
  final widthPx = app.pageProps.pageWidth;
  var bottomPx = 0.0;
  for (final b in blocks) {
    final h = b.h ?? app.renderSizes[b.id]?.height ?? app.estimatedHeight(b);
    if (b.y + h > bottomPx) bottomPx = b.y + h;
  }
  if (bottomPx <= 0) bottomPx = _sheetHeight(widthPx);

  final sheetPx = _sheetHeight(widthPx);
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
          for (final b in visible)
            if (_blockWidget(app, b, top) case final w?) w,
        ],
      ),
    ));
  }
  return doc.save();
}

bool _overlaps(AppState app, Block b, double top, double bottom) {
  final h = b.h ?? app.renderSizes[b.id]?.height ?? app.estimatedHeight(b);
  return b.y < bottom && b.y + h > top;
}

/// One block, positioned for the sheet starting at [sheetTop].
///
/// Returns null for a block this exporter has nothing useful to say about, so
/// an unknown future block type is skipped rather than drawn as a placeholder.
pw.Widget? _blockWidget(AppState app, Block b, double sheetTop) {
  final h = b.h ?? app.renderSizes[b.id]?.height ?? app.estimatedHeight(b);
  final left = b.x / _pxPerPoint;
  final top = (b.y - sheetTop) / _pxPerPoint;
  final w = b.w / _pxPerPoint;

  final child = switch (b.type) {
    BlockType.ink => _inkWidget(b, h),
    BlockType.image => _imageWidget(app, b, h),
    BlockType.text || BlockType.code || BlockType.math => _textWidget(b),
    BlockType.table => _tableWidget(b),
    _ => null,
  };
  if (child == null) return null;
  return pw.Positioned(
    left: left,
    top: top,
    child: pw.SizedBox(width: w, child: child),
  );
}

/// Text as real text — the whole point of this exporter.
///
/// Markdown markers are stripped rather than styled. Faithful inline styling
/// would mean re-implementing the renderer against the `pdf` package's very
/// different text model; the thing that matters for a shared or printed note is
/// that the words are *there*, selectable and searchable, at roughly the right
/// size. Headings keep their weight because that carries the structure.
pw.Widget? _textWidget(Block b) {
  final raw =
      (b.content['text'] ?? b.content['code'] ?? b.content['latex']) as String?;
  if (raw == null || raw.trim().isEmpty) return null;
  final sizePx = (b.content['fontSize'] as num?)?.toDouble() ?? 15.0;
  final size = sizePx / _pxPerPoint;
  // Code keeps a monospaced face — alignment IS the content in a code block,
  // and Courier is a PDF standard font so it costs no embedding.
  final mono = b.type == BlockType.code ? pw.Font.courier() : null;

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
      (b.content['text'] ?? b.content['code'] ?? b.content['latex']) as String?;
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

pw.Widget? _imageWidget(AppState app, Block b, double h) {
  final ref = b.content['blob'] as String?;
  if (ref == null) return null;
  final bytes = app.blob(ref);
  if (bytes == null) return null;
  try {
    return pw.Image(pw.MemoryImage(bytes),
        width: b.w / _pxPerPoint, height: h / _pxPerPoint, fit: pw.BoxFit.fill);
  } catch (_) {
    // An image the PDF encoder can't read (an odd PNG variant) must not take
    // the whole export down with it.
    return null;
  }
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
Future<pw.ThemeData?> _theme() async {
  try {
    final regular = pw.Font.ttf(
        await rootBundle.load('assets/fonts/inter/Inter-Regular.ttf'));
    final bold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/inter/Inter-SemiBold.ttf'));
    final italic = pw.Font.ttf(
        await rootBundle.load('assets/fonts/inter/Inter-Italic.ttf'));
    return pw.ThemeData.withFont(base: regular, bold: bold, italic: italic);
  } catch (_) {
    // No bundled font (a test harness without assets): fall back to the PDF
    // standard faces rather than failing the export.
    return null;
  }
}
