// THROWAWAY probe.
// ignore_for_file: depend_on_referenced_packages, avoid_print
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' as pw;
import 'package:pdf/widgets.dart' as w;
import 'package:pdfium_dart/pdfium_dart.dart';

Future<Uint8List> _makePdf() async {
  final doc = w.Document();
  doc.addPage(w.Page(
    pageFormat: pw.PdfPageFormat.a4,
    build: (_) => w.Center(child: w.Text('hello openote')),
  ));
  return Uint8List.fromList(await doc.save());
}

String _probe(String dllPath, Uint8List bytes) {
  final lib = DynamicLibrary.open(dllPath);
  final p = PDFium(lib);
  p.FPDF_InitLibrary();
  final buf = malloc.allocate<Uint8>(bytes.length);
  buf.asTypedList(bytes.length).setAll(0, bytes);
  final doc = p.FPDF_LoadMemDocument(buf.cast(), bytes.length, nullptr);
  if (doc == nullptr) return 'FPDF_LoadMemDocument returned NULL';
  final n = p.FPDF_GetPageCount(doc);
  final page = p.FPDF_LoadPage(doc, 0);
  if (page == nullptr) return 'pages=$n but FPDF_LoadPage returned NULL';
  const wpx = 120, hpx = 170;
  final bmp = p.FPDFBitmap_Create(wpx, hpx, 0);
  p.FPDFBitmap_FillRect(bmp, 0, 0, wpx, hpx, 0xFFFFFFFF);
  p.FPDF_RenderPageBitmap(bmp, page, 0, 0, wpx, hpx, 0, 0);
  final pix = p.FPDFBitmap_GetBuffer(bmp).cast<Uint8>();
  final stride = p.FPDFBitmap_GetStride(bmp);
  var ink = 0;
  final view = pix.asTypedList(stride * hpx);
  for (var i = 0; i < view.length; i++) {
    if (view[i] != 0xFF) ink++;
  }
  p.FPDFBitmap_Destroy(bmp);
  p.FPDF_ClosePage(page);
  p.FPDF_CloseDocument(doc);
  malloc.free(buf);
  return 'pages=$n nonWhiteBytes=$ink';
}

void main() {
  const base = 'build/windows/x64/runner';
  test('pdfium: shipped Release vs Debug', () async {
    final bytes = await _makePdf();
    for (final cfg in [('RELEASE(shipped)', '$base/Release/pdfium.dll'), ('DEBUG(7520)', '$base/Debug/pdfium.dll')]) {
      final f = File(cfg.$2);
      print('${cfg.$1} exists=${f.existsSync()} size=${f.existsSync() ? f.lengthSync() : 0}');
      if (!f.existsSync()) continue;
      try {
        print('${cfg.$1} => ${_probe(f.absolute.path, bytes)}');
      } catch (e) {
        print('${cfg.$1} FAILED => $e');
      }
    }
    // Symbol-resolution check against the shipped DLL for the calls pdfrx makes.
    final rel = DynamicLibrary.open(File('$base/Release/pdfium.dll').absolute.path);
    final missing = <String>[];
    for (final s in const [
      'FPDF_InitLibraryWithConfig', 'FPDF_LoadMemDocument64', 'FPDF_GetPageCount',
      'FPDF_LoadPage', 'FPDF_RenderPageBitmap', 'FPDFBitmap_CreateEx',
      'FPDFText_LoadPage', 'FPDFText_CountChars', 'FPDFLink_GetLinkAtPoint',
      'FPDF_MovePages', 'FPDFPage_GetAnnotCount', 'FPDF_GetDocPermissions',
      'FPDF_RenderPageBitmapWithMatrix', 'FPDFBitmap_GetBuffer',
      'FPDFText_GetBoundedText', 'FPDF_GetPageWidthF', 'FPDF_GetPageHeightF',
    ]) {
      if (!rel.providesSymbol(s)) missing.add(s);
    }
    print('MISSING FROM SHIPPED PDFIUM: $missing');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
