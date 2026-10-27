// Ink has to decode the same in a browser as it does on a desktop.
//
// Two faults shipped here at once, and the browser demo showed neither of
// them: the handwriting was simply absent, with nothing on the console.
//
//   * `InkCodec` inflated with `dart:io`'s zlib, which the web does not have.
//     Every blob over 256 bytes is deflated, so nearly every blob threw, and
//     `InkStorage.toWorking` blanks a block whose bytes will not decode —
//     deliberately, so that one bad blob cannot take a page down.
//   * Undoing the zigzag was `(u >>> 1) ^ -(u & 1)`. `dart2js` normalises an
//     integer bitwise result into the unsigned 32-bit range, so every
//     NEGATIVE delta came back as about 4.29e9. Odd `u` only, which is why
//     the effect was not "no ink" but "ink 268 million pixels long".
//
// **This file is why `--platform chrome` is in CI.** Run on the VM it passes
// against both bugs, which is exactly how they survived: CI tested the VM on
// three desktops and never compiled for a browser.
//
// The blob below is real — the drawing on the demo notebook's Maths page,
// 20 strokes in seven colours, encoded by the Windows build. Keeping the
// bytes here rather than reading the asset is what lets the test run in a
// browser, where there is no file to open.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/ink/ink_codec.dart';
import 'package:openote/model/models.dart';

/// `assets/demo/demo.onote`, the `ink` block on the Maths page.
const String _demoInk =
    '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'
    'aL0JOuj/AUgJ/es=';

void main() {
  test('a blob the desktop wrote decodes to the same ink here', () {
    final bytes = base64Decode(_demoInk);
    expect(bytes.length, 1577);
    // Deflated, which is the half of this the web could not do at all.
    expect(bytes[5], 1, reason: 'the fixture stopped being a deflated blob');

    final strokes = InkCodec.decode(bytes, originX: 100, originY: 200);
    expect(strokes.length, 20);
    expect(strokes.fold<int>(0, (a, s) => a + s.x.length), 551);
    expect(
        strokes.map((s) => s.colorHex).toSet(),
        containsAll(<String>[
          'auto',
          '#2F6FB3',
          '#C63838',
          '#2E8B57',
          '#6A4BC0',
          '#D9971F',
          '#8BF224',
        ]));

    // The whole drawing sits in a box about 338 x 68 at the origin it was
    // given. Before the zigzag fix a browser put points 268,435,406 px away,
    // so a generous bound still fails loudly there.
    for (final s in strokes) {
      for (var i = 0; i < s.x.length; i++) {
        expect(s.x[i], inInclusiveRange(100 - 1, 100 + 400),
            reason: 'x escaped the block');
        expect(s.y[i], inInclusiveRange(200 - 1, 200 + 400),
            reason: 'y escaped the block');
      }
    }
  });

  test('a delta that doubles back survives the round trip', () {
    // The sign is the whole point: only negative deltas decoded wrongly, so a
    // stroke that only ever moves right and down passes against the bug.
    final back = Stroke(
      tool: 'pen',
      colorHex: '#C63838',
      size: 2,
      x: const [0, 100, 50, 150, 25],
      y: const [0, 50, 10, 90, 5],
    );
    final out = InkCodec.decode(
      InkCodec.encode([back], originX: 0, originY: 0),
      originX: 0,
      originY: 0,
    );
    expect(out.single.x, back.x);
    expect(out.single.y, back.y);
  });

  test('re-encoding the demo blob gives back the same bytes', () {
    // The store is content-addressed, so a change in what the encoder emits
    // is a change in every hash. `archive` delegating to `dart:io` natively
    // is what keeps that true.
    final bytes = base64Decode(_demoInk);
    final again = InkCodec.encode(
      InkCodec.decode(bytes, originX: 0, originY: 0),
      originX: 0,
      originY: 0,
    );
    expect(again, bytes);
  });
}
