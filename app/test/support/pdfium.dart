/// Pdfium under `flutter test`: DOESN'T WORK, and this file is the record of
/// why, so nobody re-digs the hole.
///
/// The app build has pdfium (build/windows/x64/**/pdfium.dll) and pdfrx has
/// the hooks (`Pdfrx.pdfiumModulePath`, `Pdfrx.getCacheDirectory`,
/// `PdfrxEntryFunctions.instance.init()`). Wiring them up in a test
/// `setUpAll` — the same trick support/sqlite.dart plays — gets as far as
/// `PdfDocument.openData` and then HANGS FOREVER: pdfrx's native path runs
/// pdfium on a worker isolate, and its handshake never completes under the
/// bare test VM. With nothing configured, `openData` instead fails fast
/// ("getCacheDirectory is not set"), which is what lets the pdfium-gated
/// tests skip cleanly in milliseconds.
///
/// So: this deliberately configures NOTHING. The tests guarded on
/// [initPdfiumForTests] stay written and self-skipping — if a future pdfrx
/// runs headless, put the real bootstrap back here and they light up
/// everywhere at once. Until then the pure halves (content shapes,
/// blob_refs) carry the automated coverage, and the rendering halves are
/// verified in the running app.
Future<bool> initPdfiumForTests() async => false;
