// Where a curve breaks, and how tall the window should be (plan: v0.23 §5).
//
// Each group here is one of the four traps that produce a PLAUSIBLE BUT WRONG
// picture rather than an error — the worst kind of defect a graph can have,
// because nothing on screen says anything went wrong.
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/math/evaluate.dart';
import 'package:openote/math/graph_plot.dart';

Plot plot(String src, {GraphView? view, int samples = 400, bool fitY = false}) =>
    plotFunction(compileFunction(src), view ?? GraphView.initial,
        samples: samples, fitY: fitY);

void main() {
  tearDown(() => mathAngleMode = AngleMode.degrees);

  group('an ordinary curve is one unbroken piece', () {
    test('a line', () {
      final p = plot('3x+10');
      expect(p.error, isNull);
      expect(p.pieces.length, 1);
      expect(p.pieces.single.length, 400);
      // …and it really is the line.
      final first = p.pieces.single.first;
      expect(first.dx, closeTo(-10, 1e-9));
      expect(first.dy, closeTo(-20, 1e-9));
    });

    test('a parabola', () {
      final p = plot('x^2');
      expect(p.pieces.length, 1);
      final mid = p.pieces.single
          .reduce((a, b) => a.dy.abs() < b.dy.abs() ? a : b);
      expect(mid.dy, closeTo(0, 0.01), reason: 'the vertex is on the axis');
    });

    test('and a curve that leaves the top and comes back is still one piece',
        () {
      // x^2 runs far above the window in both corners and dips through it.
      // Leaving the window is not a break — only crossing from one side to
      // the other in a single step is.
      final p = plot('x^2', view: const GraphView(x0: -10, x1: 10, y0: -1, y1: 5));
      expect(p.pieces.length, 1);
    });
  });

  group('trap 1: an asymptote is not an infinity', () {
    test('1/x is cut in two at the pole', () {
      final p = plot('1/x');
      expect(p.pieces.length, 2,
          reason: 'without the cut, a near-vertical line joins +inf to -inf '
              'straight through the axis and reads as part of the curve');
      // Every point of the left piece is left of zero, and vice versa.
      expect(p.pieces[0].every((o) => o.dx < 0), isTrue);
      expect(p.pieces[1].every((o) => o.dx > 0), isTrue);
    });

    test('tan has a pole every 180 degrees, and none of them is infinite', () {
      mathAngleMode = AngleMode.degrees;
      // tan(90) is 1.63e16 — a perfectly finite double. Testing isInfinite
      // would find nothing to cut and draw the whole thing joined up.
      expect(compileFunction('tan(x)').at!(90).isFinite, isTrue);
      final p = plot('tan(x)',
          view: const GraphView(x0: -180, x1: 180, y0: -5, y1: 5),
          samples: 900);
      expect(p.pieces.length, 3,
          reason: 'poles at -90 and +90 cut the span into three');
      for (final piece in p.pieces) {
        for (var k = 1; k < piece.length; k++) {
          // No segment inside a piece may jump the whole window.
          final jump = (piece[k].dy - piece[k - 1].dy).abs();
          expect(jump, lessThan(1e6), reason: 'a joined-up pole survived');
        }
      }
    });

    test('the cut reaches toward the pole rather than stopping short', () {
      final p = plot('1/x', view: const GraphView(x0: -2, x1: 2, y0: -10, y1: 10));
      final leftEnd = p.pieces.first.last;
      expect(leftEnd.dy, lessThan(-10),
          reason: 'the drawn line should leave the BOTTOM edge, not bend '
              'toward a point just above it');
      final rightStart = p.pieces.last.first;
      expect(rightStart.dy, greaterThan(10));
    });

    test('a steep but continuous curve is NOT cut', () {
      final p = plot('x^3', view: const GraphView(x0: -3, x1: 3, y0: -20, y1: 20));
      expect(p.pieces.length, 1,
          reason: 'x cubed crosses the window continuously; cutting it would '
              'be an invented discontinuity');
    });
  });

  group('trap 2: a run of no-value is one gap', () {
    test('sqrt(x) is one piece, starting at zero', () {
      final p = plot('sqrt(x)');
      expect(p.pieces.length, 1,
          reason: 'the whole left half has no value; a break per sample would '
              'give two hundred empty pieces');
      expect(p.pieces.single.first.dx, greaterThanOrEqualTo(0));
    });

    test('a curve with a hole in the middle is two pieces', () {
      final p = plot('sqrt(x^2-4)',
          view: const GraphView(x0: -6, x1: 6, y0: -1, y1: 6));
      expect(p.pieces.length, 2, reason: 'no value between -2 and 2');
    });

    test('a function with no value anywhere draws nothing, and says so', () {
      final p = plot('sqrt(-1-x^2)');
      expect(p.isEmpty, isTrue);
      expect(p.error, isNull, reason: 'it compiled; it simply has no points');
    });
  });

  group('trap 3: one pole must not flatten the curve', () {
    test('fitting y to 1/x uses the middle, not the extremes', () {
      final p = plot('1/x', fitY: true);
      expect(p.view.height, lessThan(20),
          reason: 'the extremes reach ten million; a window that tall draws '
              'every feature as a flat line on the axis. Got '
              '${p.view.height}');
      expect(p.view.height, greaterThan(0.2));
    });

    test('a parabola fits to what it actually does', () {
      final p = plot('x^2', fitY: true);
      expect(p.view.y0, lessThanOrEqualTo(0.1));
      expect(p.view.y1, greaterThan(10));
    });

    test('a constant line is given room either side', () {
      final p = plot('5', fitY: true);
      expect(p.view.y0, lessThan(5));
      expect(p.view.y1, greaterThan(5));
      expect(p.view.height, greaterThan(0.5),
          reason: 'a zero-height window cannot be drawn in');
    });

    test('and zero is kept in view when the curve comes near it', () {
      final p = plot('x^2+1', fitY: true);
      expect(p.view.y0, lessThanOrEqualTo(0),
          reason: 'an axis you cannot see is a graph with no frame of '
              'reference');
    });
  });

  group('trap 4: samples are pixels', () {
    test('the count is honoured, and clamped to something sane', () {
      expect(plot('x', samples: 50).pieces.single.length, 50);
      expect(plot('x', samples: 1).pieces.single.length, 2,
          reason: 'two points is the fewest a line can have');
      expect(plot('x', samples: 100000).pieces.single.length, 4000,
          reason: 'past a few thousand nothing more can be seen and the '
              'painter is paying for it every frame');
    });
  });

  group('the window itself', () {
    test('panning and zooming are what they say', () {
      const v = GraphView(x0: -10, x1: 10, y0: -10, y1: 10);
      expect(v.panned(5, 0).x0, -5);
      expect(v.zoomed(0.5).width, 10);
      // Zooming about a point leaves that point where it was.
      final z = v.zoomed(0.5, aboutX: 4, aboutY: 0);
      expect(z.x0, 4 - 7);
      expect(z.x1, 4 + 3);
    });

    test('nonsense is refused rather than drawn', () {
      const bad = GraphView(x0: 1, x1: 1, y0: 0, y1: 1);
      expect(bad.isSane, isFalse);
      final p = plotFunction(compileFunction('x'), bad, samples: 10);
      expect(p.view, GraphView.initial,
          reason: 'a window with no width falls back to one that has some');
    });

    test('it survives being stored and read back', () {
      const v = GraphView(x0: -2.5, x1: 7.5, y0: -1, y1: 3);
      expect(GraphView.fromJson(v.toJson()), v);
      expect(GraphView.fromJson(null), GraphView.initial);
      expect(GraphView.fromJson({'x0': 'nonsense'}), GraphView.initial);
      // A field at a time: a stored window with one bad number keeps the
      // numbers that ARE readable rather than throwing the lot away.
      expect(GraphView.fromJson({'x0': -1, 'x1': double.nan}).x0, -1);
      expect(GraphView.fromJson({'x0': -1, 'x1': double.nan}).x1,
          GraphView.initial.x1);
    });
  });

  group('the numbers on the gridlines are ones a person would write', () {
    test('the step is 1, 2 or 5 times a power of ten', () {
      for (final span in [1.0, 3.0, 7.0, 20.0, 137.0, 0.05, 1e6]) {
        final step = gridStep(span);
        final mag =
            math.pow(10, (math.log(step) / math.ln10).floor()).toDouble();
        final norm = step / mag;
        expect([1.0, 2.0, 5.0, 10.0].any((n) => (norm - n).abs() < 1e-9),
            isTrue,
            reason: 'span $span gave a step of $step (mantissa $norm)');
      }
    });

    test('and there are roughly as many as asked for', () {
      for (final span in [1.0, 3.0, 7.0, 20.0, 137.0]) {
        final count = span / gridStep(span, target: 8);
        expect(count, greaterThan(3), reason: 'span $span');
        expect(count, lessThan(20), reason: 'span $span');
      }
    });

    test('a label says the number and not the floating point', () {
      expect(gridLabel(0, 1), '0');
      expect(gridLabel(-0.0, 1), '0');
      expect(gridLabel(5, 1), '5');
      expect(gridLabel(0.6000000000000001, 0.2), '0.6');
      expect(gridLabel(-2, 1), '-2');
      expect(gridLabel(1500000, 500000), contains('e'));
    });
  });

  group('when there is nothing to draw', () {
    test('the reason is the calculator\'s own words', () {
      final p = plot('3z+1');
      expect(p.pieces, isEmpty);
      expect(p.error, contains('z'));
    });
  });

  group('it is fast enough to redraw as you type', () {
    test('nine hundred samples of a curve with poles in it', () {
      final f = compileFunction('tan(x)+1/x');
      final sw = Stopwatch()..start();
      for (var frame = 0; frame < 10; frame++) {
        plotFunction(f, GraphView.initial, samples: 900, fitY: true);
      }
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(160),
          reason: 'ten frames took ${sw.elapsedMilliseconds}ms; one frame at '
              '60fps is 16ms and the painter is not the only thing in it');
    });
  });

  test('a piece is a real polyline, in maths coordinates', () {
    final p = plot('x', view: const GraphView(x0: 0, x1: 1, y0: 0, y1: 1),
        samples: 3);
    expect(p.pieces.single, [
      const Offset(0, 0),
      const Offset(0.5, 0.5),
      const Offset(1, 1),
    ]);
  });
}
