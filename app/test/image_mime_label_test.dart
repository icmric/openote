// A picture is labelled with what it actually is.
//
// Nothing in the OneNote importer transcodes, so a JPEG in a section stays a
// JPEG — and every imported picture was labelled `image/png` anyway. The open
// folder derives an asset's filename from the label, so a notebook exported
// after an import contained JPEGs called `.png`. Backlog §1.4.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/export/md_common.dart';
import 'package:openote/store/repository.dart';

void main() {
  Uint8List bytesOf(List<int> head) =>
      Uint8List.fromList([...head, ...List<int>.filled(32, 0)]);

  group('what the bytes say they are', () {
    test('a PNG', () {
      expect(Repository.sniffMime(bytesOf([0x89, 0x50, 0x4e, 0x47])),
          'image/png');
    });

    test('a JPEG', () {
      expect(
          Repository.sniffMime(bytesOf([0xff, 0xd8, 0xff, 0xe0])),
          'image/jpeg');
    });

    test('a BMP, which OneNote does embed', () {
      expect(Repository.sniffMime(bytesOf([0x42, 0x4d])), 'image/bmp');
    });

    test('a TIFF, either byte order', () {
      expect(Repository.sniffMime(bytesOf([0x49, 0x49, 0x2a, 0x00])),
          'image/tiff');
      expect(Repository.sniffMime(bytesOf([0x4d, 0x4d, 0x00, 0x2a])),
          'image/tiff');
    });

    test('and nothing it recognises', () {
      expect(Repository.sniffMime(bytesOf([0x01, 0x02, 0x03, 0x04])),
          'application/octet-stream');
    });
  });

  group('the filename an exported asset gets', () {
    test('a JPEG is .jpg, not .jpeg', () {
      expect(extensionForMime('image/jpeg'), 'jpg');
    });

    test('SVG is .svg — splitting the mime at the slash gave svg+xml', () {
      expect(extensionForMime('image/svg+xml'), 'svg');
    });

    test('bytes nobody recognised are .bin, not .octet-stream', () {
      expect(extensionForMime('application/octet-stream'), 'bin');
    });

    test('a label in capitals still lands', () {
      expect(extensionForMime('IMAGE/PNG'), 'png');
    });
  });
}
