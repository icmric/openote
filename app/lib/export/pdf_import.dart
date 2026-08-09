/// Import a PDF as annotatable pages (D1 — the lecture-slide flagship).
///
/// **The pitch:** drop the lecture PDF in, write on the slides with your pen,
/// and search the slide text later.
///
/// This is the workflow GoodNotes and Notability built businesses on, and it
/// is Apple-locked and paid there. OneNote's equivalent ("Insert → PDF
/// printout") rasterises pages into images and loses the text.
///
/// **The PDF is stored ONCE, and pages are references** (storage wave 1c).
/// The importer used to rasterise every page to a 2× PNG blob: a 60-slide
/// deck became hundreds of megabytes of pixels standing in for a 4 MB file.
/// Now the source PDF goes into the blob store once — it syncs exactly like
/// an image does — and each slide block carries `{pdf: sha256:…, page: i}`,
/// rendered on demand by `PdfPages` at the same scale, so it looks identical
/// and costs almost nothing at rest. It also means the PDF's own text is
/// still there for the viewer's selection and copy.
///
/// Two deliberate choices survive from the raster era:
///
/// - **Slides keep their layout.** A slide's layout is the information;
///   re-flowing it into our block model would destroy the thing the student
///   is annotating. The text layer rides alongside for search.
/// - **The background is locked.** An annotation layer is only usable if the
///   thing underneath cannot be nudged.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../model/models.dart';
import '../state/app_state.dart';

/// Page width we lay imported slides out at, matching the default page width
/// so a slide fills the page the way it does in a PDF reader.
const double kPdfPageWidth = 1100.0;

/// Gap between stacked slides on a single page, and above the first one.
const double kPdfStackGap = 36.0;

/// Where the imported slides go.
enum PdfPlacement {
  /// Every slide stacked down the CURRENT page, below whatever is already
  /// there. The default, because a printout is what a student reaches for:
  /// one continuous page you scroll through and write on, exactly like
  /// OneNote's "Insert ▸ PDF printout", and it keeps the slides next to the
  /// notes already on that page.
  currentPage,

  /// One Openote page per PDF page, in a new section named after the file.
  /// Better for a 200-slide unit you want in the navigator as separate pages.
  pagePerSlide,

  /// One small card with a thumbnail — the whole deck behind a click, not
  /// spread over the page. "Have a little thumbnail appear in my page, but
  /// not have the whole thing always open." Clicking the card opens the
  /// viewer, where the text is selectable.
  card,
}

/// Result of an import, for the caller's summary.
typedef PdfImportResult = ({int pages, String? sectionId, String? firstPageId});

/// Pick a PDF and import it into the current notebook.
Future<PdfImportResult?> importPdfAsPages(
  AppState app, {
  BuildContext? progressContext,
  PdfPlacement placement = PdfPlacement.currentPage,
  void Function(int done, int total)? onProgress,
}) async {
  const typeGroup = XTypeGroup(label: 'PDF', extensions: ['pdf']);
  final file = await openFile(acceptedTypeGroups: [typeGroup]);
  if (file == null) return null;
  return importPdfFile(app, file.path, file.name,
      placement: placement, onProgress: onProgress);
}

/// Import [path] — onto the current page, as one page per slide, or as a card.
///
/// Exposed separately from the picker so it can be driven by a drop, by a
/// test, or by a future "attach the reading list" flow.
Future<PdfImportResult> importPdfFile(
  AppState app,
  String path,
  String displayName, {
  PdfPlacement placement = PdfPlacement.currentPage,
  void Function(int done, int total)? onProgress,
}) async {
  final nb = app.notebookId;
  if (nb == null) return (pages: 0, sectionId: null, firstPageId: null);
  if (placement != PdfPlacement.pagePerSlide && app.pageId == null) {
    // No page open — make one and put it there.
    //
    // This used to silently switch to one-page-per-slide, which is a different
    // feature, not a fallback: the deck arrived scattered across dozens of
    // navigator entries and nothing said why. Honour the mode that was asked
    // for; only the arrow menu switches modes.
    await app.addPage();
    if (app.pageId == null) {
      return (pages: 0, sectionId: null, firstPageId: null);
    }
  }

  // The source file, once, into the content-addressed store. Everything else
  // in this import is a reference to this hash.
  final bytes = await File(path).readAsBytes();
  final doc = await PdfDocument.openData(bytes, sourceName: displayName);
  try {
    final pdfHash = placement == PdfPlacement.pagePerSlide
        ? app.importBlob(nb, bytes, 'application/pdf')
        : app.addBlob(bytes, 'application/pdf');
    final title =
        displayName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');

    if (placement == PdfPlacement.card) {
      return _importAsCard(app, doc, pdfHash,
          title.isEmpty ? displayName : title);
    }
    if (placement == PdfPlacement.currentPage) {
      return await _importOntoCurrentPage(app, doc, pdfHash, onProgress);
    }

    // A section per PDF: a 60-slide deck dumped into an existing section
    // would bury everything already there.
    final section = app.importNode(
        nb,
        TreeNode(
          kind: NodeKind.section,
          title: title.isEmpty ? 'PDF' : title,
          position: 'a${nowMs().toString().padLeft(15, '0')}',
        ));

    String? firstPageId;
    var made = 0;
    final total = doc.pages.length;
    var pos = nowMs();

    // Chunked transactions, as before — but the per-page work is now only
    // TEXT EXTRACTION, so a 200-slide import that used to render for minutes
    // finishes in seconds.
    const chunkSize = 16;
    for (var start = 0; start < total; start += chunkSize) {
      final end = (start + chunkSize).clamp(0, total);
      final batch = <({PdfPage page, String? text, int index})>[];
      for (var i = start; i < end; i++) {
        batch.add((page: doc.pages[i], text: await _textOf(doc.pages[i]), index: i));
      }

      app.importBatch(nb, () {
        for (final item in batch) {
          final node = app.importNode(
              nb,
              TreeNode(
                kind: NodeKind.page,
                parentId: section.id,
                title: '${item.index + 1}',
                position: 'a${(pos++).toString().padLeft(15, '0')}',
              ));
          firstPageId ??= node.id;

          const w = kPdfPageWidth;
          final h = item.page.height / item.page.width * w;
          app.importPage(
            nb,
            node.id,
            [
              _slideBlock(pdfHash, item.page, item.index, item.text,
                  x: 0, y: 0, w: w, background: true)
                ..h = h
            ],
            PageProps(pageWidth: w),
          );
          made++;
        }
      });
      onProgress?.call(made, total);
      // A real delay, not Duration.zero: this loop runs on the UI isolate, and
      // on Windows posted work outranks hardware input, so a queue that never
      // goes idle starves the mouse and keyboard for the whole import.
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }

    app.reloadNodes();
    return (pages: made, sectionId: section.id, firstPageId: firstPageId);
  } finally {
    await doc.dispose();
  }
}

/// One reference block for one slide.
Block _slideBlock(
  String pdfHash,
  PdfPage page,
  int index,
  String? text, {
  required double x,
  required double y,
  required double w,
  bool background = false,
}) =>
    Block(
      type: BlockType.image,
      x: x,
      y: y,
      w: w,
      content: {
        'pdf': 'sha256:$pdfHash',
        'page': index,
        'mime': 'application/pdf',
        // The PDF's own geometry, so aspect and proportional resize never
        // need the pixels.
        'naturalW': page.width,
        'naturalH': page.height,
        // The two properties that make this an annotation surface rather
        // than a picture someone dropped on the page.
        'locked': true,
        if (background) 'background': true,
        if (text != null && text.isNotEmpty) 'sourceText': text,
      },
    );

Future<String?> _textOf(PdfPage page) async {
  try {
    // Hidden, but present in the page JSON, so the existing brute-force
    // notebook search finds slides by their words.
    return (await page.loadText())?.fullText.trim();
  } catch (_) {
    return null; // a scanned deck has no text layer; that's fine
  }
}

/// The card: one block, the deck behind a click.
PdfImportResult _importAsCard(
    AppState app, PdfDocument doc, String pdfHash, String name) {
  final anchor = _insertionAnchor(app);
  app.pushUndo();
  final b = app.addBlock(
    Block(
      type: BlockType.file,
      x: AppState.pageLeftMargin,
      y: anchor.top,
      w: 300,
      content: {
        'kind': 'pdf',
        'blob': 'sha256:$pdfHash',
        'name': name,
        'mime': 'application/pdf',
        'pages': doc.pages.length,
      },
    ),
    recordUndo: false,
  );
  app.select(b.id);
  return (pages: doc.pages.length, sectionId: null, firstPageId: app.pageId);
}

/// Stack every slide down the page that is currently open, below whatever is
/// already on it.
///
/// One `pushUndo` for the whole import, so Ctrl+Z takes the deck back out in
/// one go rather than sixty times. With rendering gone from the import path,
/// the whole deck lands in one visible step.
Future<PdfImportResult> _importOntoCurrentPage(
  AppState app,
  PdfDocument doc,
  String pdfHash,
  void Function(int done, int total)? onProgress,
) async {
  final total = doc.pages.length;
  // Slide width: the page's own writing column, so a slide lines up with the
  // text already on the page instead of hanging off the side.
  final width = (app.pageProps.pageWidth - AppState.pageLeftMargin * 2)
      .clamp(320.0, kPdfPageWidth);
  final anchor = _insertionAnchor(app);
  var y = anchor.top;

  app.pushUndo();
  final top = y;
  // Everything that sat below the insertion point moves down as slides land,
  // so inserting at the caret opens a gap instead of burying what follows.
  final displaced = anchor.displaced;
  Block? first;
  var made = 0;
  for (var i = 0; i < total; i++) {
    final page = doc.pages[i];
    final text = await _textOf(page);
    final h = page.height / page.width * width;
    final block = app.addBlock(
      _slideBlock(pdfHash, page, i, text,
          x: AppState.pageLeftMargin, y: y, w: width)
        ..h = h,
      recordUndo: false,
    );
    first ??= block;
    // Read the position back: addBlock may snap it to the grid, and computing
    // the next slide's y from the requested position would drift.
    final advance = block.y + h + kPdfStackGap - y;
    y = block.y + h + kPdfStackGap;
    for (final d in displaced) {
      d.y += advance;
    }
    made++;
    onProgress?.call(made, total);
    // Text extraction is quick, but the loop still yields so a 200-slide
    // deck never freezes input — and a REAL delay, for the same Windows
    // message-loop reason as always.
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  // Bring the result into view — the slides land below everything already on
  // the page, which on a page with content means off screen.
  if (first != null) {
    app.select(first.id);
    app.canvas.centerOn(Offset(width / 2 + AppState.pageLeftMargin, top + 200));
  }
  await app.flushSave();
  return (pages: made, sectionId: null, firstPageId: app.pageId);
}

/// Where a printout should start, and which blocks have to move to make room.
///
/// **At the cursor if there is one, below everything otherwise.** A student
/// importing a deck mid-lecture wants it where they are working, not appended
/// a screen and a half below their last note; a student importing into an empty
/// page wants it at the top.
///
/// [displaced] is every block strictly below the anchor, which the caller
/// shifts down as slides land. Landing on top of somebody's notes is not a
/// recoverable mistake.
({double top, List<Block> displaced}) _insertionAnchor(AppState app) {
  final caretId = app.editingBlockId ?? app.selectedBlockId;
  final caret = caretId == null
      ? null
      : app.blocks.where((b) => b.id == caretId).firstOrNull;

  double bottomOf(Block b) =>
      b.y + (b.h ?? app.renderSizes[b.id]?.height ?? app.estimatedHeight(b));

  if (caret != null) {
    final top = bottomOf(caret) + kPdfStackGap;
    return (
      top: top,
      // Strictly below the anchor block, by its own top edge — a block that
      // merely overlaps the gap stays put.
      displaced: [
        for (final b in app.blocks)
          if (b.id != caret.id && b.y >= caret.y + 1) b
      ],
    );
  }

  // Nothing focused: append below everything. Belt and braces, because
  // `contentExtent` can under-report for culled, never-measured blocks — and
  // an import is exactly when most of the page is off screen.
  var y = app.contentExtent().bottom;
  for (final b in app.blocks) {
    final bottom = bottomOf(b);
    if (bottom > y) y = bottom;
  }
  return (top: y + kPdfStackGap, displaced: const []);
}

/// The placement decision, exposed for tests.
///
/// The rendering half needs pdfium and a real file; the *placement* half is
/// where the reported bug lived, and it is pure.
@visibleForTesting
({double top, List<Block> displaced}) debugInsertionAnchor(AppState app) =>
    _insertionAnchor(app);
