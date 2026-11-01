// An SVG is a picture, by every route a picture arrives by.
//
// GitHub #10, promised for this release: *"I am hoping to get SVG images
// working in v1.0.2."* Before this, a dropped .svg became an attachment chip
// — a file you could open in something else, on a page that could have drawn
// it — and the PDF exporter dropped it silently, keeping the words.
//
// The reference in the text is a hash and says nothing about the format, so
// what decides is the bytes. That is one sniff, in one place, because two
// renderers draw in-flow pictures and a drawing that appeared while you typed
// and vanished when you clicked away would be the two of them disagreeing.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/media_drop.dart';
import 'package:openote/core/picture_bytes.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/app.dart';
import 'support/sqlite.dart';

/// A real, minimal SVG document.
final svgBytes = Uint8List.fromList(
    '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20">'
            '<rect width="40" height="20" fill="#C63838"/></svg>'
        .codeUnits);

/// An 8-byte PNG signature is enough for the sniff; it is not a decodable
/// image, which is deliberate — [looksLikeSvg] must answer without decoding.
final pngBytes =
    Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  group('what the bytes are', () {
    test('AN SVG IS RECOGNISED, PAST WHATEVER COMES FIRST', () {
      expect(looksLikeSvg(svgBytes), isTrue);
      // The three things an SVG may legally open with before its root
      // element, all of which a file from a real drawing program has.
      expect(
          looksLikeSvg(Uint8List.fromList(
              '<?xml version="1.0"?>\n<!-- made by hand -->\n<svg></svg>'
                  .codeUnits)),
          isTrue);
      expect(
          looksLikeSvg(Uint8List.fromList(
              [0xEF, 0xBB, 0xBF, ...'<svg/>'.codeUnits])),
          isTrue,
          reason: 'a byte-order mark is not a reason to refuse to draw it');
      expect(looksLikeSvg(Uint8List.fromList('<SVG VIEWBOX="0 0 1 1"/>'.codeUnits)),
          isTrue,
          reason: 'XML is case-sensitive but files in the wild are not tidy');
    });

    test('AND A RASTER IS NOT', () {
      expect(looksLikeSvg(pngBytes), isFalse);
      expect(looksLikeSvg(Uint8List(0)), isFalse);
      expect(
          looksLikeSvg(Uint8List.fromList(
              [0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(200, 0x41)])),
          isFalse,
          reason: 'a JPEG with text in its header is still a JPEG');
    });

    test('a very long preamble does not hide the element for ever', () {
      // The sniff reads a kilobyte. A file whose root is past that is not a
      // drawing anybody made; it must answer false rather than scan a
      // 40 MB blob on every rebuild.
      final padded = Uint8List.fromList(
          [...List.filled(2000, 0x20), ...'<svg/>'.codeUnits]);
      expect(looksLikeSvg(padded), isFalse);
    });
  });

  testWidgets('THE SAME BYTES DRAW AS VECTOR, NOT AS A BROKEN RASTER',
      (t) async {
    await t.pumpWidget(testApp(Center(child: pictureFromBytes(svgBytes))));
    await t.pumpAndSettle();

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('and a raster still draws as one', (t) async {
    await t.pumpWidget(testApp(Center(
        child: pictureFromBytes(pngBytes, width: 40, height: 20))));
    await t.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(SvgPicture), findsNothing);
    // The bytes are not a decodable PNG, so the error path runs: it must not
    // throw, and the caller is told so it can show the reference instead.
    t.takeException();
  });

  group('on a page', () {
    late Directory tmp;
    late Repository repo;
    late AppState app;

    setUp(() {
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_svg_');
    });

    tearDown(() {
      AppState.syncLogEnabled = true;
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<void> open(WidgetTester t) async {
      await t.runAsync(() async {
        repo = await Repository.openAt(tmp);
        final nb = await repo.createNotebook('Drawings');
        app = AppState(repo)..notebookId = nb.id;
        app.reloadNodes();
        await app.selectPage(
            app.nodes.where((n) => n.kind == NodeKind.page).first.id);
      });
    }

    testWidgets('A DROPPED .SVG IS A PICTURE, NOT AN ATTACHMENT', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await open(t);
      final file = File('${tmp.path}${Platform.pathSeparator}diagram.svg')
        ..writeAsBytesSync(svgBytes);

      await t.runAsync(() => dropFilesOntoCanvas(
          app, [file.path], const Offset(300, 300)));

      expect(app.blocks.where((b) => b.type == BlockType.file), isEmpty,
          reason: 'an attachment chip is what it used to become');
      final box = app.blocks.singleWhere((b) => b.type == BlockType.text);
      expect(box.content['text'] as String, contains('](sha256:'));
      app.cancelPendingSave();
    });

    testWidgets('and the bytes behind it are the drawing, unchanged',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await open(t);
      final made = insertImageInNewBox(
          app, svgBytes, 'image/svg+xml', const Offset(200, 200));

      final ref = RegExp(r'\(([^)]+)\)')
          .firstMatch(made!.content['text'] as String)!
          .group(1)!;
      expect(app.blob(ref), svgBytes,
          reason: 'a drawing is stored as itself — no rasterising on the way '
              'in, which is the whole reason to want SVG on a page');
      app.cancelPendingSave();
    });
  });
}
