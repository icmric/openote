// The binary ink codec.
//
// This replaces JSON stroke arrays, which measured 36.2 bytes per point on a
// real notebook — 63 MB of one notebook's op log, and the same JSON again in
// the container. The codec has to be exactly lossless within a stated
// tolerance, deterministic (the blobs are content-addressed, so identical
// strokes must produce identical bytes or a save would duplicate the object),
// and it has to survive the shapes real data actually contains: coordinates
// out at x = 1.3 million from an import, strokes with pressure and strokes
// without in the same block, empty strokes.
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/ink/ink_codec.dart';
import 'package:openote/model/models.dart';

void main() {
  /// Strokes shaped like the real notebook's: 28 points mean, pressure on
  /// almost every stroke, no time or tilt channel, one pen.
  List<Stroke> sample({
    int count = 20,
    int seed = 7,
    double originX = 100,
    double originY = 200,
    bool pressure = true,
    bool time = false,
    bool tilt = false,
  }) {
    final rnd = Random(seed);
    return [
      for (var s = 0; s < count; s++)
        () {
          final n = 4 + rnd.nextInt(50);
          var x = originX + rnd.nextDouble() * 900;
          var y = originY + rnd.nextDouble() * 600;
          final xs = <double>[], ys = <double>[], ps = <double>[];
          final ts = <int>[], txs = <double>[], tys = <double>[];
          for (var i = 0; i < n; i++) {
            x += rnd.nextDouble() * 6 - 3;
            y += rnd.nextDouble() * 6 - 3;
            xs.add(x);
            ys.add(y);
            if (pressure) ps.add(rnd.nextDouble());
            if (time) ts.add(i * 8);
            if (tilt) {
              txs.add(rnd.nextDouble() * 2 - 1);
              tys.add(rnd.nextDouble() * 2 - 1);
            }
          }
          return Stroke(
            id: 'seed-$s',
            tool: s % 7 == 0 ? 'highlighter' : 'pen',
            colorHex: s % 3 == 0 ? '#211F1B' : '#C8102E',
            size: s % 7 == 0 ? 12 : 2.5,
            opacity: s % 7 == 0 ? 0.35 : 1.0,
            x: xs,
            y: ys,
            p: ps,
            t: ts,
            tx: txs,
            ty: tys,
            strokeStart: 1780000000000 + s * 1200,
          );
        }()
    ];
  }

  /// Every point within half a quantisation step, and everything else exact.
  void expectEquivalent(List<Stroke> a, List<Stroke> b,
      {double tol = 1 / (2 * kInkScale)}) {
    expect(b.length, a.length, reason: 'stroke count and order must survive');
    for (var i = 0; i < a.length; i++) {
      final s = a[i], d = b[i];
      expect(d.tool, s.tool, reason: 'stroke $i tool');
      expect(d.colorHex.toUpperCase(), s.colorHex.toUpperCase(),
          reason: 'stroke $i colour');
      expect(d.size, closeTo(s.size, 1 / 64), reason: 'stroke $i size');
      expect(d.opacity, closeTo(s.opacity, 1 / 255), reason: 'stroke $i opacity');
      expect(d.strokeStart, s.strokeStart, reason: 'stroke $i start');
      expect(d.x.length, s.x.length, reason: 'stroke $i point count');
      for (var k = 0; k < s.x.length; k++) {
        expect(d.x[k], closeTo(s.x[k], tol), reason: 'stroke $i point $k x');
        expect(d.y[k], closeTo(s.y[k], tol), reason: 'stroke $i point $k y');
      }
      expect(d.p.length, s.p.length, reason: 'stroke $i pressure count');
      for (var k = 0; k < s.p.length; k++) {
        expect(d.p[k], closeTo(s.p[k], 1 / 255), reason: 'stroke $i p $k');
      }
      expect(d.t, s.t, reason: 'stroke $i time channel');
      for (var k = 0; k < s.tx.length; k++) {
        expect(d.tx[k], closeTo(s.tx[k], 1 / 64), reason: 'stroke $i tx $k');
        expect(d.ty[k], closeTo(s.ty[k], 1 / 64), reason: 'stroke $i ty $k');
      }
    }
  }

  group('round trip', () {
    test('strokes survive with page-absolute coordinates', () {
      final strokes = sample();
      final bytes =
          InkCodec.encode(strokes, originX: 100, originY: 200);
      final back =
          InkCodec.decode(bytes, originX: 100, originY: 200);
      expectEquivalent(strokes, back);
    });

    test('ENCODING IS DETERMINISTIC', () {
      // Load-bearing: the blob is addressed by the hash of these bytes, so a
      // save that produced different bytes for identical strokes would create
      // a second copy of the same handwriting every time.
      final strokes = sample();
      final a = InkCodec.encode(strokes, originX: 100, originY: 200);
      final b = InkCodec.encode(strokes, originX: 100, originY: 200);
      expect(a, equals(b));
      // And re-encoding what was decoded is byte-identical, which is what
      // makes a rebuild comparable to a container.
      final c = InkCodec.encode(
          InkCodec.decode(a, originX: 100, originY: 200),
          originX: 100,
          originY: 200);
      expect(c, equals(a), reason: 'decode then encode must be a fixed point');
    });

    test('the time and tilt channels round-trip when present', () {
      // Tilt is not captured by any device Flutter exposes, but a file written
      // by another tool can contain it, and it used to be destroyed simply by
      // opening and saving the page.
      final strokes = sample(count: 6, time: true, tilt: true);
      final bytes = InkCodec.encode(strokes, originX: 0, originY: 0);
      expectEquivalent(
          strokes, InkCodec.decode(bytes, originX: 0, originY: 0));
    });

    test('a block with some pressure-less strokes keeps the distinction', () {
      final withP = sample(count: 4, seed: 1);
      final without = sample(count: 4, seed: 2, pressure: false);
      final mixed = [...withP, ...without];
      final bytes = InkCodec.encode(mixed, originX: 0, originY: 0);
      final back = InkCodec.decode(bytes, originX: 0, originY: 0);
      expect(back.take(4).every((s) => s.p.isNotEmpty), isTrue);
      expect(back.skip(4).every((s) => s.p.isEmpty), isTrue,
          reason: 'a stroke without pressure must not gain a fabricated one');
      expectEquivalent(mixed, back);
    });

    test('no strokes at all', () {
      final bytes = InkCodec.encode(const [], originX: 0, originY: 0);
      expect(InkCodec.decode(bytes, originX: 0, originY: 0), isEmpty);
      expect(InkCodec.decodeHeader(bytes).strokeCount, 0);
    });

    test('coordinates a million pixels out still work', () {
      // The real notebook contains an imported block reaching x = 1,312,485.
      // Blob-local storage is what keeps the deltas small, and this proves the
      // varints do not overflow on the absolute first point either.
      final strokes = sample(count: 3, originX: 1312485, originY: 987654);
      final bytes =
          InkCodec.encode(strokes, originX: 1312485, originY: 987654);
      expectEquivalent(strokes,
          InkCodec.decode(bytes, originX: 1312485, originY: 987654));
    });

    test('an unusual colour string is not silently normalised away', () {
      // The format spec's rule is that data a build does not understand
      // survives a round trip rather than being helpfully cleaned up.
      final s = Stroke(
          id: 'x',
          tool: 'pen',
          colorHex: 'rebeccapurple',
          size: 3,
          x: [1, 2, 3],
          y: [1, 2, 3]);
      final bytes = InkCodec.encode([s], originX: 0, originY: 0);
      expect(InkCodec.decode(bytes, originX: 0, originY: 0).single.colorHex,
          'rebeccapurple');
    });
  });

  group('the header answers layout questions without decoding points', () {
    test('bounds and count match the strokes', () {
      final strokes = sample(count: 12, originX: 50, originY: 60);
      final bytes = InkCodec.encode(strokes, originX: 50, originY: 60);
      final h = InkCodec.decodeHeader(bytes);
      expect(h.strokeCount, 12);

      var minX = double.infinity, minY = double.infinity;
      var maxX = -double.infinity, maxY = -double.infinity;
      for (final s in strokes) {
        for (var i = 0; i < s.x.length; i++) {
          minX = min(minX, s.x[i]);
          maxX = max(maxX, s.x[i]);
          minY = min(minY, s.y[i]);
          maxY = max(maxY, s.y[i]);
        }
      }
      // Header bounds are blob-local; add the origin back to compare.
      expect(h.minX + 50, closeTo(minX, 1 / kInkScale));
      expect(h.maxX + 50, closeTo(maxX, 1 / kInkScale));
      expect(h.minY + 60, closeTo(minY, 1 / kInkScale));
      expect(h.maxY + 60, closeTo(maxY, 1 / kInkScale));
    });
  });

  group('the transform is applied on read', () {
    test('an origin shift moves every point and costs no bytes', () {
      // This is why a drag does not rewrite a blob: the SAME bytes decode at a
      // new place.
      final strokes = sample(count: 5, originX: 0, originY: 0);
      final bytes = InkCodec.encode(strokes, originX: 0, originY: 0);
      final moved = InkCodec.decode(bytes, originX: 40, originY: -25);
      for (var i = 0; i < strokes.length; i++) {
        for (var k = 0; k < strokes[i].x.length; k++) {
          expect(moved[i].x[k], closeTo(strokes[i].x[k] + 40, 1 / kInkScale));
          expect(moved[i].y[k], closeTo(strokes[i].y[k] - 25, 1 / kInkScale));
        }
      }
    });

    test('a scale multiplies about the origin, also for free', () {
      final strokes = sample(count: 4, originX: 10, originY: 10);
      final bytes = InkCodec.encode(strokes, originX: 10, originY: 10);
      final big = InkCodec.decode(bytes,
          originX: 10, originY: 10, scaleX: 2, scaleY: 2);
      for (var i = 0; i < strokes.length; i++) {
        for (var k = 0; k < strokes[i].x.length; k++) {
          expect(big[i].x[k], closeTo(10 + (strokes[i].x[k] - 10) * 2, 0.13));
          expect(big[i].y[k], closeTo(10 + (strokes[i].y[k] - 10) * 2, 0.13));
        }
      }
    });
  });

  group('refusing bad input', () {
    test('random bytes are not mistaken for ink', () {
      final junk = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      expect(InkCodec.looksLikeInk(junk), isFalse);
      expect(() => InkCodec.decode(junk, originX: 0, originY: 0),
          throwsA(isA<FormatException>()));
    });

    test('a truncated blob throws rather than returning half a page', () {
      // Silently returning the strokes it managed to read would let a save
      // diff against a partial page and delete the rest.
      final bytes = InkCodec.encode(sample(), originX: 0, originY: 0);
      final cut = Uint8List.sublistView(bytes, 0, bytes.length ~/ 2);
      expect(() => InkCodec.decode(cut, originX: 0, originY: 0),
          throwsA(isA<Object>()));
    });

    test('a future version is refused by name', () {
      final bytes = InkCodec.encode(sample(count: 2), originX: 0, originY: 0);
      bytes[4] = 99;
      expect(
          () => InkCodec.decode(bytes, originX: 0, originY: 0),
          throwsA(isA<FormatException>().having(
              (e) => e.message, 'message', contains('newer than this build'))));
    });
  });

  group('it is actually smaller — the whole point', () {
    test('bytes per point beats the JSON it replaces by an order of magnitude',
        () {
      // The real notebook measured 36.2 bytes per point as JSON. Anything
      // above ~5 here means a regression in the encoding, which is otherwise
      // invisible: every other test would still pass.
      final strokes = sample(count: 400, seed: 99);
      final points =
          strokes.fold<int>(0, (sum, s) => sum + s.x.length);
      final bytes = InkCodec.encode(strokes, originX: 0, originY: 0);
      final perPoint = bytes.length / points;
      expect(perPoint, lessThan(5),
          reason: '$perPoint bytes/point over $points points '
              '(${bytes.length} bytes); JSON was 36.2');
    });

    test('deflate is skipped when it would not help', () {
      // A single erased fragment is a few dozen bytes and the zlib header
      // would be most of it.
      final tiny = [
        Stroke(id: 'a', tool: 'pen', colorHex: '#000000', size: 2,
            x: [1, 2], y: [1, 2])
      ];
      final bytes = InkCodec.encode(tiny, originX: 0, originY: 0);
      expect(bytes[5], 0, reason: 'method 0 = stored');
      expectEquivalent(tiny, InkCodec.decode(bytes, originX: 0, originY: 0));
    });
  });
}
