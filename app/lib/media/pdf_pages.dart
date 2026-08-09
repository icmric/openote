/// Render pages of a stored PDF on demand — storage wave 1c.
///
/// A PDF used to be imported by rasterising EVERY page to a PNG blob at 2×:
/// a 60-slide deck became ~240 MB of pixels standing in for a 4 MB file, and
/// the text under the pixels was gone. Now the notebook stores the PDF ITSELF,
/// once, as an ordinary content-addressed blob — it syncs like an image does —
/// and a slide on a page is a reference `{pdf: sha256:…, page: 3}` rendered
/// here when it scrolls into view. The look is identical (same engine, same
/// 2× scale the importer used); the storage cost is the PDF, once; and the
/// text survives, which is what makes the viewer's selection and copy work.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import '../state/app_state.dart';

/// Render scale for page images: the importer's historical choice, kept so an
/// on-demand slide is pixel-for-pixel the slide the raster path produced.
const double kPdfPageScale = 2.0;

abstract final class PdfPages {
  /// Open documents, keyed by blob hash. An open pdfium document holds a file
  /// parse and native memory, so the cache is small and evicts the least
  /// recently used document that has no render in flight.
  static final LinkedHashMap<String, _Doc> _docs = LinkedHashMap();
  static const _maxDocs = 4;

  /// Rendered page PNGs, keyed `hash#page`. Bounded by total bytes rather
  /// than entry count: one A0 poster page is worth fifty slides.
  static final LinkedHashMap<String, Uint8List> _pages = LinkedHashMap();
  static var _pageBytes = 0;
  static const _maxPageBytes = 96 << 20; // ~96 MB of decoded slides

  /// The rendered image for [page] of the PDF stored as [hash], from cache or
  /// freshly rendered. Null when the blob is absent (a sync still bringing it
  /// across) or the bytes are not a readable PDF.
  static Future<Uint8List?> pageImage(
      AppState app, String hash, int page) async {
    final key = '$hash#$page';
    final hit = _pages.remove(key);
    if (hit != null) {
      _pages[key] = hit; // re-insert: LRU freshness
      return hit;
    }
    final doc = await _open(app, hash);
    if (doc == null) return null;
    doc.busy++;
    try {
      if (page < 0 || page >= doc.doc.pages.length) return null;
      final png = await renderPdfPageToPng(doc.doc.pages[page]);
      if (png == null) return null;
      _pages[key] = png.png;
      _pageBytes += png.png.length;
      while (_pageBytes > _maxPageBytes && _pages.length > 1) {
        _pageBytes -= _pages.remove(_pages.keys.first)!.length;
      }
      return png.png;
    } finally {
      doc.busy--;
    }
  }

  /// Cached synchronously, for paint paths that cannot await.
  static Uint8List? cached(String hash, int page) => _pages['$hash#$page'];

  /// How many pages the stored PDF has, or null when it cannot be opened.
  static Future<int?> pageCount(AppState app, String hash) async =>
      (await _open(app, hash))?.doc.pages.length;

  static Future<_Doc?> _open(AppState app, String hash) async {
    final held = _docs.remove(hash);
    if (held != null) {
      _docs[hash] = held;
      return held.failed ? null : held;
    }
    final bytes = app.blob(hash);
    if (bytes == null) return null;
    final entry = _Doc();
    _docs[hash] = entry;
    try {
      entry.doc = await PdfDocument.openData(bytes, sourceName: hash);
    } catch (e) {
      // Remembered as failed rather than retried per frame: a corrupt blob
      // stays corrupt, and every caller re-opening it would jank the canvas.
      entry.failed = true;
      debugPrint('[openote/pdf] could not open $hash: $e');
      return null;
    }
    // Evict beyond the cap — least recently used first, never one mid-render.
    final evictable = _docs.entries
        .where((e) => e.key != hash && e.value.busy == 0 && !e.value.failed)
        .map((e) => e.key)
        .toList();
    while (_docs.length > _maxDocs && evictable.isNotEmpty) {
      final victim = _docs.remove(evictable.removeAt(0))!;
      unawaited(victim.doc.dispose());
    }
    return entry;
  }

  /// Drop everything — for tests, and for a notebook switch where holding
  /// another notebook's documents open would pin its blobs in memory.
  static Future<void> reset() async {
    final docs = _docs.values.where((d) => !d.failed).toList();
    _docs.clear();
    _pages.clear();
    _pageBytes = 0;
    for (final d in docs) {
      await d.doc.dispose();
    }
  }
}

class _Doc {
  late PdfDocument doc;
  var busy = 0;
  var failed = false;
}

/// A rendered page's PNG bytes and pixel size.
typedef RenderedPdfPage = ({Uint8List png, int width, int height});

/// Render one page at the standard scale. Shared by the importer (which uses
/// it for nothing but sizing now), the on-demand path above, and the vector
/// PDF exporter's pre-render pass.
Future<RenderedPdfPage?> renderPdfPageToPng(PdfPage page) async {
  final w = (page.width * kPdfPageScale).round();
  final h = (page.height * kPdfPageScale).round();
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

/// pdfium hands back raw BGRA; consumers get a real PNG so that anything
/// downstream — an export, a clipboard — holds an image file, not a pixel dump.
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
