// Does PDFium work in a browser? — run with `--platform chrome`.
//
// The question this answers, asked before putting a PDF in the demo
// notebook: a PDF card on the canvas draws its first page as a cover and
// opens the whole document on a click, and both go through
// `PdfDocument.openData` + a page render (`media/pdf_pages.dart`). On the web
// that means PDFium compiled to WASM, and `main.dart` deliberately does NOT
// call `pdfrxFlutterInitialize()` there — it is gated on
// `Capability.localFiles` to avoid fetching 3.8 MB of `pdfium.wasm` for a
// feature whose every INSERT route starts at a file picker the browser
// does not have.
//
// So the open question was whether the rendering half still works without
// that call. Reading the package says it should: `pdfrxFlutterInitialize`
// sets `Pdfrx.loadAsset` (needed only by `openAsset`, which Openote never
// uses — it passes blob bytes to `openData`) and the native font-cache
// directory, while the WASM worker is booted by `init()`, which
// `_openByFunc` awaits on every open. This checks that reading rather than
// trusting it.
//
// It is in `test/web/` and not in the default run: `flutter test` compiles
// for the VM, where this proves nothing, and the suite must not need Chrome.
//
//   flutter test --platform chrome test/web/pdf_on_web_test.dart
//
// **If it fails with a message about `pdfium_client.js`**, the WASM module is
// not in the build. `dart run pdfrx:remove_wasm_modules` comments the assets
// line out of pdfrx's pubspec IN THE PUB CACHE — the release workflow runs it
// for desktop, and run locally it stays until reverted, taking PDFium out of
// web builds on this machine. `--revert` once per time it was run.
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' as pw;
import 'package:pdf/widgets.dart' as pww;
import 'package:pdfrx/pdfrx.dart';

void main() {
  /// A real two-page PDF, built rather than checked in.
  Future<Uint8List> makePdf() async {
    final doc = pww.Document();
    for (final word in ['Osmosis', 'Diffusion']) {
      doc.addPage(pww.Page(
        pageFormat: pw.PdfPageFormat.a4,
        build: (_) => pww.Center(child: pww.Text(word)),
      ));
    }
    return Uint8List.fromList(await doc.save());
  }

  test('a PDF opens from bytes, with no pdfrxFlutterInitialize call',
      () async {
    final bytes = await makePdf();
    expect(latin1.decode(bytes.take(5).toList()), '%PDF-',
        reason: 'precondition: these are PDF bytes');

    // Exactly what `PdfPages._open` does, and nothing has initialised pdfrx:
    // `_openByFunc` awaits `init()`, which injects `pdfium_client.js` and
    // boots the WASM worker.
    final pdf = await PdfDocument.openData(bytes, sourceName: 'test');
    addTearDown(pdf.dispose);
    expect(pdf.pages.length, 2);
  });

  test('and its first page renders, which is the cover on the card', () async {
    final bytes = await makePdf();
    final pdf = await PdfDocument.openData(bytes, sourceName: 'cover');
    addTearDown(pdf.dispose);

    // `PdfPages.pageImage` renders at 2x — the scale the importer used, kept
    // so an on-demand slide is pixel-for-pixel what the raster path produced.
    final page = pdf.pages[0];
    final image = await page.render(
      fullWidth: page.width * 2,
      fullHeight: page.height * 2,
    );
    expect(image, isNotNull, reason: 'PDFium rendered nothing');
    addTearDown(image!.dispose);
    expect(image.width, greaterThan(page.width.round()));
    expect(image.height, greaterThan(page.height.round()));
    // Not a blank buffer: a render that silently produced nothing would still
    // have the right dimensions.
    expect(image.pixels.any((b) => b != 0), isTrue,
        reason: 'every pixel was zero');
  });

  test('the text survives, which is what the viewer selects', () async {
    // The reason a PDF is stored as a PDF rather than as pictures of pages
    // (storage wave 1c). If this fails on the web, the viewer opens but
    // selection and copy inside it do not work.
    final pdf = await PdfDocument.openData(await makePdf(), sourceName: 't');
    addTearDown(pdf.dispose);
    final text = await pdf.pages[1].loadText();
    expect(text?.fullText, contains('Diffusion'));
  });
}
