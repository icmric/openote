import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../state/app_state.dart';
import 'md_common.dart';

/// Page → PDF export (OPEN-7 MVP cut): fit the view to the page content,
/// rasterize the canvas at 2×, and emit a single-page PDF sized to match.
/// (Vector PDF export arrives with the open-folder "materialize" pass, P2.)
Future<String?> exportPagePdf(AppState app) async {
  if (app.pageId == null) return null;
  final ctx = app.canvasKey.currentContext;
  if (ctx == null) return null;

  final page = app.nodes.firstWhere((n) => n.id == app.pageId);

  // Clean capture: no selection chrome, fitted to content.
  //
  // **Put the selection back afterwards.** The view was restored and the
  // selection was not, so exporting a PDF quietly threw away whatever the
  // student had picked out — they asked for a file, not to be deselected.
  final wasSelected = app.selectedIds.toList();
  app.select(null);
  final c = app.canvas;
  final oldScale = c.scale;
  final oldOffset = c.offset;
  c.fitTo(app.contentBounds().inflate(24));
  await WidgetsBinding.instance.endOfFrame;
  // The canvas can go away across that frame — the user navigates, or the
  // notebook closes — and `findRenderObject` on an unmounted element throws
  // rather than returning null. Nothing was exported at this point, so
  // abandoning quietly is the right outcome.
  if (!ctx.mounted) return null;

  ui.Image? image;
  try {
    final boundary = ctx.findRenderObject() as RenderRepaintBoundary;
    image = await boundary.toImage(pixelRatio: 2.0);
  } finally {
    c.jumpTo(oldScale, oldOffset); // always restore the user's view
    if (wasSelected.isNotEmpty) app.selectMany(wasSelected);
  }
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  final imgW = image.width, imgH = image.height;
  image.dispose(); // release the GPU-backed capture; bytes are copied out
  if (byteData == null) return null;

  final location = await getSaveLocation(
    suggestedName: '${safeFilename(page.title, fallback: 'page')}.pdf',
    acceptedTypeGroups: const [
      XTypeGroup(label: 'PDF', extensions: ['pdf'])
    ],
  );
  if (location == null) return null;

  await File(location.path).writeAsBytes(
      await _wrapCapture(page.title, byteData.buffer.asUint8List(), imgW, imgH));
  return location.path;
}

Future<Uint8List> _wrapCapture(
    String title, Uint8List png, int imgW, int imgH) async {
  final doc = pw.Document(title: title, creator: 'Openote');
  final mem = pw.MemoryImage(png);
  // Points at 0.5 px/pt keeps the page dimensioned like the 2x capture.
  final format = PdfPageFormat(imgW / 2, imgH / 2);
  doc.addPage(pw.Page(
    pageFormat: format,
    margin: pw.EdgeInsets.zero,
    build: (_) => pw.Image(mem, fit: pw.BoxFit.contain),
  ));
  return doc.save();
}

/// A picture of the page as PDF bytes, for when the vector export cannot be
/// produced. Null when the canvas is not on screen to be photographed.
///
/// "if it fails during an export, should we maybe do a fallback where we
/// export as pdf still but just do it as an image" — yes, and this is the
/// half that makes it possible: the same capture the raster exporter does,
/// without the file dialog, so the caller can write it to a location the user
/// has already chosen.
Future<Uint8List?> buildPageRasterPdf(AppState app) async {
  final ctx = app.canvasKey.currentContext;
  if (ctx == null) return null;
  final page = app.nodes.where((n) => n.id == app.pageId).firstOrNull;
  if (page == null) return null;
  app.select(null);
  final c = app.canvas;
  final oldScale = c.scale;
  final oldOffset = c.offset;
  c.fitTo(app.contentBounds().inflate(24));
  await WidgetsBinding.instance.endOfFrame;
  if (!ctx.mounted) return null;
  ui.Image? image;
  try {
    final boundary = ctx.findRenderObject() as RenderRepaintBoundary;
    image = await boundary.toImage(pixelRatio: 2.0);
  } catch (_) {
    return null;
  } finally {
    c.jumpTo(oldScale, oldOffset);
  }
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final w = image.width, h = image.height;
  image.dispose();
  if (data == null) return null;
  return _wrapCapture(page.title, data.buffer.asUint8List(), w, h);
}
