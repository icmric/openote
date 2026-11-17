// Issue #33: "PDF files above 4MB cannot be opened."
//
// pdfrx loads a PDF over 1 MB through a per-read callback across isolates, and
// on Windows (pdfrx_engine 0.3.9) the wake-up for each read can be lost, so the
// open hangs for ever; a bigger file makes more reads and loses the race more
// surely. `media/pdf_open.dart` has the whole story. The fix is to give pdfium
// the whole file in memory every time, which only works if nothing in the app
// goes back to the three calls that take the 1 MB default.
//
// pdfium itself cannot run under `flutter test` (see support/pdfium.dart), so
// what can be pinned here is the rule and the reader, not a real open.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/media/pdf_open.dart';

void main() {
  test('nothing in lib/ opens a PDF through the 1 MB default', () {
    // Each of these reaches PdfDocument.openData, whose in-memory limit is
    // fixed at 1 MB and cannot be raised by the caller.
    final banned = RegExp(
        r'PdfDocument\.openData\(|PdfViewer\.data\(|PdfDocumentRefData\(');
    final offenders = <String>[];
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final lines = e.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (!banned.hasMatch(line)) continue;
        // The one sanctioned use: the browser build, which has no pdfium
        // reader to race and no openCustom.
        if (e.path.endsWith('pdf_open.dart') &&
            lines.sublist((i - 1).clamp(0, i), i + 1).any((l) => l.contains('kIsWeb'))) {
          continue;
        }
        offenders.add('${e.path}:${i + 1}: ${line.trim()}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'open PDFs with openPdfBytes / pdfBytesRef (media/pdf_open.dart) '
            'so pdfium always gets the whole file in memory');
  });

  group('the reader handed to pdfium', () {
    final bytes = Uint8List.fromList(List.generate(10, (i) => i));

    test('copies the whole file in one call, which is how it is used', () {
      final buf = Uint8List(10);
      expect(pdfBytesReader(bytes)(buf, 0, 10), 10);
      expect(buf, bytes);
    });

    test('a read that runs past the end is cut short', () {
      final buf = Uint8List(8);
      expect(pdfBytesReader(bytes)(buf, 6, 8), 4);
      expect(buf.sublist(0, 4), [6, 7, 8, 9]);
    });

    test('at the end there is nothing; past it is an error', () {
      final buf = Uint8List(4);
      expect(pdfBytesReader(bytes)(buf, 10, 4), 0);
      expect(pdfBytesReader(bytes)(buf, 11, 4), -1);
      expect(pdfBytesReader(bytes)(buf, -1, 4), -1);
    });
  });
}
