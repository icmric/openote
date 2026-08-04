/// Import a PDF as annotatable pages (D1 — the lecture-slide flagship).
///
/// **The pitch:** drop the lecture PDF in, write on the slides with your pen,
/// and search the slide text later.
///
/// This is the workflow GoodNotes and Notability built businesses on, and it
/// is Apple-locked and paid there. OneNote's equivalent ("Insert → PDF
/// printout") rasterises pages into images and loses the text. It composes
/// almost entirely from what Openote already has: each PDF page becomes an
/// Openote page carrying one **locked background image block**, ink rides on
/// top exactly as it always does, and the extracted text feeds the existing
/// notebook-wide search.
///
/// Two deliberate choices:
///
/// - **Pages are rendered to images, not re-typeset.** A slide's layout is the
///   information; re-flowing it into our block model would destroy the thing
///   the student is annotating. The text layer rides alongside for search
///   rather than replacing the picture.
/// - **The background is locked.** An annotation layer is only usable if the
///   thing underneath cannot be nudged, and a 2 MB image that moves when you
///   miss with the pen is worse than no import at all.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../model/models.dart';
import '../state/app_state.dart';

/// Render scale. 2× keeps slide text crisp at 100% zoom and readable when
/// zoomed in, without the memory cost of 3× on a 60-slide deck.
const double kPdfRenderScale = 2.0;

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

/// Import [path], either onto the current page or as one page per slide.
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
  if (placement == PdfPlacement.currentPage && app.pageId == null) {
    // No page open — make one and stack onto it.
    //
    // This used to silently switch to one-page-per-slide, which is a different
    // feature, not a fallback: the deck arrived scattered across dozens of
    // navigator entries and nothing said why. Opening the app on a section
    // rather than a page is an ordinary thing to do, so the "wrong" mode was
    // reachable without the user choosing it. Honour the mode that was asked
    // for; only the arrow menu switches modes now.
    await app.addPage();
    if (app.pageId == null) {
      // Still nowhere to put it (no section at all) — say so rather than
      // quietly doing something else.
      return (pages: 0, sectionId: null, firstPageId: null);
    }
  }

  final doc = await PdfDocument.openFile(path);
  try {
    if (placement == PdfPlacement.currentPage) {
      return await _importOntoCurrentPage(app, nb, doc, onProgress);
    }
    final title =
        displayName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
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

    // Rendered in CHUNKS, then written in one transaction per chunk.
    //
    // Rendering is async (pdfium off the UI thread) and a SQLite transaction
    // must not span awaits, so the whole import cannot be one transaction.
    // Per-page commits would be slow on a 200-slide deck; holding every page's
    // PNG to commit once would be hundreds of megabytes. A chunk is the
    // compromise, and it also bounds how much is lost if the import is
    // interrupted — earlier chunks are already committed pages.
    const chunkSize = 8;
    for (var start = 0; start < total; start += chunkSize) {
      final end = (start + chunkSize).clamp(0, total);
      final batch = <({_Rendered img, String? text, int index})>[];
      for (var i = start; i < end; i++) {
        final page = doc.pages[i];
        final rendered = await _renderPageToPng(page);
        if (rendered == null) continue;
        // Text layer: hidden, but present in the page JSON, so the existing
        // brute-force notebook search finds slides by their words without a
        // second index to keep in step.
        String? text;
        try {
          text = (await page.loadText())?.fullText.trim();
        } catch (_) {
          text = null; // a scanned deck has no text layer; that's fine
        }
        batch.add((img: rendered, text: text, index: i));
      }
      if (batch.isEmpty) continue;

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

          final hash = app.importBlob(nb, item.img.png, 'image/png');
          // Fit the slide to the page width, preserving aspect.
          const w = kPdfPageWidth;
          final h = item.img.height / item.img.width * w;

          app.importPage(
            nb,
            node.id,
            [
              Block(
                type: BlockType.image,
                x: 0,
                y: 0,
                w: w,
                content: {
                  'blob': 'sha256:$hash',
                  'mime': 'image/png',
                  // The two properties that make this an annotation surface
                  // rather than a picture someone dropped on the page.
                  'locked': true,
                  'background': true,
                  if (item.text != null && item.text!.isNotEmpty)
                    'sourceText': item.text,
                },
              )..h = h,
            ],
            PageProps(pageWidth: w),
          );
          made++;
        }
      });
      onProgress?.call(made, total);
      // Yield so a long import doesn't freeze the window between chunks.
      await Future<void>.delayed(Duration.zero);
    }

    app.reloadNodes();
    return (pages: made, sectionId: section.id, firstPageId: firstPageId);
  } finally {
    await doc.dispose();
  }
}

/// Stack every slide down the page that is currently open, below whatever is
/// already on it.
///
/// Deliberately incremental rather than one transaction: each slide is added
/// to the LIVE page as it finishes rendering, so a 60-slide deck fills in
/// visibly instead of the window sitting still and then jumping. That also
/// means the normal save path handles it — no separate import transaction, and
/// the op log records the blocks the same way it records any other edit.
///
/// One `pushUndo` for the whole import, so Ctrl+Z takes the deck back out in
/// one go rather than sixty times.
Future<PdfImportResult> _importOntoCurrentPage(
  AppState app,
  String nb,
  PdfDocument doc,
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
  // Empty when appending at the end, which is the common case.
  final displaced = anchor.displaced;
  Block? first;
  var made = 0;
  for (var i = 0; i < total; i++) {
    final rendered = await _renderPageToPng(doc.pages[i]);
    if (rendered == null) continue;
    String? text;
    try {
      text = (await doc.pages[i].loadText())?.fullText.trim();
    } catch (_) {
      text = null; // a scanned deck has no text layer; that's fine
    }
    final hash = app.addBlob(rendered.png, 'image/png');
    final h = rendered.height / rendered.width * width;
    final block = app.addBlock(
      Block(
        type: BlockType.image,
        x: AppState.pageLeftMargin,
        y: y,
        w: width,
        content: {
          'blob': 'sha256:$hash',
          'mime': 'image/png',
          // Locked, because the point is to write ON it: a 2 MB image that
          // slides sideways when you miss with the pen is worse than no import
          // at all. The move bar and handles are gated on the same flag, so a
          // locked slide has no chrome either.
          'locked': true,
          if (text != null && text.isNotEmpty) 'sourceText': text,
        },
      )..h = h,
      recordUndo: false,
    );
    first ??= block;
    // Read the position back: addBlock may snap it to the grid, and computing
    // the next slide's y from the requested position would drift.
    final advance = block.y + h + kPdfStackGap - y;
    y = block.y + h + kPdfStackGap;
    // Open the gap as we go, so a slide inserted at the caret pushes the notes
    // below it down rather than landing on top of them. Doing it per slide
    // (rather than once at the end from a total height) keeps the page
    // self-consistent at every yield, which matters because the canvas paints
    // between iterations.
    for (final d in displaced) {
      d.y += advance;
    }
    made++;
    onProgress?.call(made, total);
    // Yield so the window keeps painting — this is what makes the slides
    // appear one by one rather than all at the end.
    await Future<void>.delayed(Duration.zero);
  }
  // Bring the result into view. The slides land BELOW everything already on
  // the page, which on a page with any content at all means off screen — so
  // without this the app reports "imported 40 slides" while nothing visibly
  // changes, and the user has to go looking for what they were just told
  // about.
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
/// page wants it at the top. Anchoring on the block being edited (or, failing
/// that, the selected one) reads as "insert here" without needing a separate
/// insertion-point UI.
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
      // merely overlaps the gap stays put, because moving something that
      // starts above the insertion point would look like the import shuffled
      // unrelated notes.
      displaced: [
        for (final b in app.blocks)
          if (b.id != caret.id && b.y >= caret.y + 1) b
      ],
    );
  }

  // Nothing focused: append below everything.
  //
  // Belt and braces, because `contentExtent` can under-report — a block
  // scrolled out of view is culled, so it never measured itself and only an
  // estimate is available — and an import is exactly when most of the page is
  // off screen. Take the lower of the two answers.
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

/// A rendered page's PNG bytes and pixel size.
typedef _Rendered = ({Uint8List png, int width, int height});

Future<_Rendered?> _renderPageToPng(PdfPage page) async {
  final w = (page.width * kPdfRenderScale).round();
  final h = (page.height * kPdfRenderScale).round();
  if (w <= 0 || h <= 0) return null;

  PdfImage? img;
  try {
    img = await page.render(
      fullWidth: w.toDouble(),
      fullHeight: h.toDouble(),
      width: w,
      height: h,
      // White, not transparent: a slide with a transparent background renders
      // as invisible text on the page's own colour, and in dark mode that is
      // black-on-black.
      backgroundColor: 0xFFFFFFFF,
    );
    if (img == null) return null;
    final png = await _bgraToPng(img.pixels, img.width, img.height);
    if (png == null) return null;
    return (png: png, width: img.width, height: img.height);
  } catch (e) {
    debugPrint('[openote/pdf] page render failed: $e');
    return null;
  } finally {
    img?.dispose();
  }
}

/// pdfium hands back raw BGRA; the blob store holds real image files so that a
/// third-party tool reading a notebook gets a PNG, not a pixel dump.
Future<Uint8List?> _bgraToPng(Uint8List bgra, int width, int height) async {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    bgra,
    width,
    height,
    ui.PixelFormat.bgra8888,
    completer.complete,
  );
  final image = await completer.future;
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
