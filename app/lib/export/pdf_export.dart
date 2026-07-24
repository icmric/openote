import 'dart:io';
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
  app.select(null);
  final c = app.canvas;
  final oldScale = c.scale;
  final oldOffset = c.offset;
  c.fitTo(app.contentBounds().inflate(24));
  await WidgetsBinding.instance.endOfFrame;

  ui.Image? image;
  try {
    final boundary = ctx.findRenderObject() as RenderRepaintBoundary;
    image = await boundary.toImage(pixelRatio: 2.0);
  } finally {
    c.jumpTo(oldScale, oldOffset); // always restore the user's view
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

  final doc = pw.Document(title: page.title, creator: 'Openote');
  final mem = pw.MemoryImage(byteData.buffer.asUint8List());
  // Points at 0.5 px/pt keeps the page dimensioned like the 2× capture.
  final format = PdfPageFormat(imgW / 2, imgH / 2);
  doc.addPage(pw.Page(
    pageFormat: format,
    margin: pw.EdgeInsets.zero,
    build: (_) => pw.Image(mem, fit: pw.BoxFit.contain),
  ));
  await File(location.path).writeAsBytes(await doc.save());
  return location.path;
}
