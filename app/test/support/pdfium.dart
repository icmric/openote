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
/// **The hang is a swallowed error, not the test VM** (found 17 November,
/// while proving #33's fix against a real pdfium). pdfrx_engine 0.3.9 loads
/// pdfium inside the worker; when that load throws, the worker's error never
/// reaches the waiting future, so the open waits for ever (fixed upstream in
/// 0.4.7: "propagates callback errors instead of hanging"). And the load
/// does throw, because `Pdfrx.pdfiumModulePath` set on the main isolate does
/// not reliably reach the worker, which then looks for
/// `<directory of the running executable>/lib/libpdfium.so`. A plain `dart
/// run` program with the library at that path opens and renders PDFs up to
/// 25 MB. So the way back in is to put the library where the worker looks
/// (beside `flutter_tester`, per platform), not to wait for a new pdfrx — not
/// done yet, because it means a test touching the Flutter SDK's directory.
///
/// So: this deliberately configures NOTHING. The tests guarded on
/// [initPdfiumForTests] stay written and self-skipping — if a future pdfrx
/// runs headless, put the real bootstrap back here and they light up
/// everywhere at once. Until then the pure halves (content shapes,
/// blob_refs) carry the automated coverage, and the rendering halves are
/// verified in the running app.
Future<bool> initPdfiumForTests() async => false;
