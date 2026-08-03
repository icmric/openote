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

/// Result of an import, for the caller's summary.
typedef PdfImportResult = ({int pages, String? sectionId, String? firstPageId});

/// Pick a PDF and import it into the current notebook as annotatable pages.
Future<PdfImportResult?> importPdfAsPages(AppState app,
    {BuildContext? progressContext,
    void Function(int done, int total)? onProgress}) async {
  const typeGroup = XTypeGroup(label: 'PDF', extensions: ['pdf']);
  final file = await openFile(acceptedTypeGroups: [typeGroup]);
  if (file == null) return null;
  return importPdfFile(app, file.path, file.name, onProgress: onProgress);
}

/// Import [path] as one Openote page per PDF page.
///
/// Exposed separately from the picker so it can be driven by a drop, by a
/// test, or by a future "attach the reading list" flow.
Future<PdfImportResult> importPdfFile(
  AppState app,
  String path,
  String displayName, {
  void Function(int done, int total)? onProgress,
}) async {
  final nb = app.notebookId;
  if (nb == null) return (pages: 0, sectionId: null, firstPageId: null);

  final doc = await PdfDocument.openFile(path);
  try {
    final title = displayName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
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
