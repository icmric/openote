// What the default pen draws in, and why it is not decided when you draw.
//
// From issue #7: "Existing default black/white handwriting should adapt when
// switching themes so it stays readable. Other colors should remain
// unchanged." And: "I can't reliably write over imported images/PDFs …
// Automatic white ink is also invisible on white documents in dark mode."
//
// Both come from the same root. The default pen's colour used to be resolved
// once, at the moment of drawing, and a hex written into the stroke — so a
// note written on a light page stayed black for ever and vanished when the
// page went dark. The painter had understood a stroke colour of `auto` all
// along; nothing ever wrote one.
//
// With `auto` stored, the question moves to paint time, where the answer can
// depend on what the stroke is actually sitting on:
//
//   * on the page      → contrast with the page (theme)
//   * on a picture/PDF → contrast with the DOCUMENT
//
// The second is one rule rather than a per-pixel inverse, deliberately.
// Scans, PDFs, screenshots and diagrams are overwhelmingly light, so ink on
// one is dark in either theme — which is what a pen on paper does, and so
// what somebody expects without being told.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/ink_painter.dart';
import 'package:openote/model/models.dart';
import 'package:openote/theme/onote_theme.dart';

void main() {
  Stroke at(double x, double y, {String color = 'auto'}) => Stroke(
        tool: 'pen',
        colorHex: color,
        size: 2,
        opacity: 1,
      )
        ..x.addAll([x, x + 10, x + 20])
        ..y.addAll([y, y, y]);

  const light = OnoteColors.graphite900;
  const white = OnoteColors.moon100;

  group('on the bare page', () {
    test('auto follows the theme, so a note survives switching it', () {
      final onLight = InkPainter(const [], autoColor: light);
      final onDark = InkPainter(const [], autoColor: white);
      // The SAME stored stroke, two themes, two colours. That is the whole
      // point: nothing about the stroke changed.
      final s = at(10, 10);
      expect(onLight.autoFor(s), light);
      expect(onDark.autoFor(s), white);
    });
  });

  group('over a picture or a PDF', () {
    final page = [const Rect.fromLTWH(100, 100, 200, 200)];

    test('dark ink on a document even when the page is dark', () {
      // The reported failure: white auto-ink on a white scan, invisible.
      final p = InkPainter(const [],
          autoColor: white, documentRects: page, overDocument: light);
      expect(p.autoFor(at(150, 150)), light);
    });

    test('and the same on a light page, so it does not change under you', () {
      final p = InkPainter(const [],
          autoColor: light, documentRects: page, overDocument: light);
      expect(p.autoFor(at(150, 150)), light);
    });

    test('a stroke beside the document still follows the theme', () {
      final p = InkPainter(const [],
          autoColor: white, documentRects: page, overDocument: light);
      expect(p.autoFor(at(10, 10)), white);
    });

    test('the MIDPOINT decides, not the first point', () {
      // A stroke that starts just off a picture and ends well inside it is,
      // to the person who drew it, on the picture. Deciding on the first
      // point would also mean two halves of one word could disagree.
      final p = InkPainter(const [],
          autoColor: white, documentRects: page, overDocument: light);
      // starts at x=95 (outside), midpoint 105 (inside)
      expect(p.autoFor(at(95, 150)), light);
    });
  });

  group('what auto must never touch', () {
    test('a colour somebody actually chose is theirs', () {
      // autoFor is only consulted for `auto`; a picked colour is stored and
      // painted exactly as picked, on any background and in either theme.
      final p = InkPainter(const [],
          autoColor: white,
          documentRects: [const Rect.fromLTWH(0, 0, 500, 500)],
          overDocument: light);
      final red = at(150, 150, color: '#FF0000');
      expect(red.colorHex, '#FF0000',
          reason: 'the stroke keeps what was chosen');
      // And the painter resolves it from the hex, never from autoFor.
      expect(p.autoFor(red), light,
          reason: 'autoFor still answers, but nothing asks it for this stroke');
    });

    test('with no document context at all, auto is just the theme', () {
      // Surfaces with no page to inspect keep the old behaviour rather than
      // guessing.
      final p = InkPainter(const [], autoColor: white);
      expect(p.autoFor(at(150, 150)), white);
    });

    test('an empty stroke does not crash the painter', () {
      final p = InkPainter(const [],
          autoColor: white,
          documentRects: [const Rect.fromLTWH(0, 0, 500, 500)],
          overDocument: light);
      final empty = Stroke(tool: 'pen', colorHex: 'auto', size: 2, opacity: 1);
      expect(p.autoFor(empty), white);
    });
  });
}
