/// Open a PDF the app already holds in memory — the only way the app opens one.
///
/// **Issue #33: "PDF files above 4MB cannot be opened", on every route that
/// inserts one.** The size was the clue and the cause was not ours.
/// `PdfDocument.openData` (and `PdfViewer.data`, which calls it) copies the
/// bytes into pdfium's memory only up to `maxSizeToCacheOnMemory`, which it
/// does not let the caller set and which defaults to **1 MB**. Above that it
/// hands pdfium a custom file reader instead: pdfium, on pdfrx's worker
/// isolate, asks for each block it needs and blocks on a condition variable
/// while the main isolate copies the bytes and wakes it.
///
/// On Windows that wake is lost. pdfrx_engine 0.3.9's Win32 helper calls
/// `WakeConditionVariable` without holding the critical section the worker
/// sleeps on, and the worker waits with no predicate and an INFINITE timeout.
/// If the copy finishes in the window between the worker posting the request
/// and going to sleep, the worker never wakes and the open never returns. Each
/// read is a chance to lose that race and a bigger file makes more reads, so
/// a 2 MB deck usually opens and a 5 MB one almost never does. (The pthread
/// helper Linux, macOS and Android use takes its mutex, and is safe.)
///
/// Upstream fixed it in pdfrx_engine 0.6.0 ("Fixed a race while reading PDF
/// data on Windows", espresso3389/pdfrx#595), which needs Dart 3.13 — newer
/// than the Flutter this app is pinned to. So rather than wait, never take the
/// custom-reader path at all: the bytes are already in memory, so give pdfium
/// all of them up front with `maxSizeToCacheOnMemory` set to the file's own
/// size. pdfium then loads with `FPDF_LoadMemDocument` and nothing crosses an
/// isolate per read. The cost is one native copy of the file for as long as
/// the document is open, which the callers already bound (`PdfPages` keeps at
/// most four documents open).
///
/// `test/pdf_open_guard_test.dart` fails if anything in `lib/` goes back to
/// `openData`, `PdfViewer.data` or `PdfDocumentRefData`.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

/// Open [bytes] as a PDF, loading every byte into pdfium at once.
Future<PdfDocument> openPdfBytes(Uint8List bytes, {required String sourceName}) {
  // The browser build has no pdfium file access to race, and no openCustom.
  if (kIsWeb) return PdfDocument.openData(bytes, sourceName: sourceName);
  return PdfDocument.openCustom(
    read: pdfBytesReader(bytes),
    fileSize: bytes.length,
    sourceName: sourceName,
    maxSizeToCacheOnMemory: bytes.length,
  );
}

/// The same thing for `PdfViewer`, which takes a reference it opens itself.
PdfDocumentRef pdfBytesRef(Uint8List bytes, {required String sourceName}) {
  if (kIsWeb) return PdfDocumentRefData(bytes, sourceName: sourceName);
  return PdfDocumentRefCustom(
    read: pdfBytesReader(bytes),
    fileSize: bytes.length,
    sourceName: sourceName,
    maxSizeToCacheOnMemory: bytes.length,
  );
}

/// pdfrx's read callback over [bytes]: copy up to [size] bytes from
/// [position] into [buffer] and return how many were copied, or -1 for a
/// position past the end.
///
/// With the whole file cached this is called once, for all of it.
@visibleForTesting
int Function(Uint8List buffer, int position, int size) pdfBytesReader(
    Uint8List bytes) {
  return (buffer, position, size) {
    if (position < 0 || position > bytes.length) return -1;
    final n = size.clamp(0, bytes.length - position);
    buffer.setRange(0, n, bytes, position);
    return n;
  };
}
