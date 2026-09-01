// Where a curve breaks, and how tall the window should be (plan: v0.23 §5).
//
// Each group here is one of the four traps that produce a PLAUSIBLE BUT WRONG
// picture rather than an error — the worst kind of defect a graph can have,
// because nothing on screen says anything went wrong.
import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

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

  group('a window too far from zero for its own width', () {
    // Zoom out to the far right, then zoom back in on a point out there, and
    // the window ends up narrow AND enormous. Adding the gridline spacing to
    // a coordinate that big does not change it: the loop that walks the
    // gridlines never reaches the end and the app stops responding. This is
    // the one class of defect a drawing can have that a person cannot get
    // out of, so it is refused at the door.
    test('is refused, so the last sensible window stays', () {
      final lost = GraphView(x0: 1e12, x1: 1e12 + 0.01, y0: -1, y1: 1);
      expect(lost.width, greaterThan(1e-9), reason: 'wide enough on its own');
      expect(lost.isSane, isFalse);
    });

    test('a small window near zero is still fine', () {
      expect(GraphView(x0: -1e-8, x1: 1e-8, y0: -1e-8, y1: 1e-8).isSane,
          isTrue);
    });

    test('a big window far out is still fine', () {
      expect(GraphView(x0: 1e10, x1: 1e10 + 100, y0: -50, y1: 50).isSane,
          isTrue);
    });

    test('zooming in stops rather than losing the numbers', () {
      var v = GraphView(x0: 1e9, x1: 1e9 + 20, y0: -10, y1: 10);
      for (var i = 0; i < 400; i++) {
        final next = v.zoomed(0.8, aboutX: 1e9 + 10, aboutY: 0);
        if (!next.isSane) break;
        v = next;
      }
      // Whatever it settled on, the gridlines can still be told apart.
      final step = gridStep(v.width);
      final walked = ticks(v.x0, v.x1, step).toList();
      expect(walked.length, greaterThan(1));
      expect(walked.toSet().length, walked.length,
          reason: 'every gridline is at its own place');
    });
  });

  group('ticks', () {
    test('walks a plain span without drifting', () {
      expect(ticks(0, 1, 0.2).toList(),
          [0.0, 0.2, 0.4, 0.6000000000000001, 0.8, 1.0]);
    });

    test('always terminates, whatever it is handed', () {
      for (final step in [0.0, -1.0, double.nan, double.infinity]) {
        expect(ticks(0, 10, step).toList(), isEmpty, reason: 'step $step');
      }
      expect(ticks(double.nan, 1, 1).toList(), isEmpty);
      // Far more lines than a screen could hold: none, rather than a freeze.
      expect(ticks(0, 1e9, 1).toList(), isEmpty);
    });

    test('gives nothing when no tick falls inside', () {
      expect(ticks(1.1, 1.9, 1).toList(), isEmpty);
    });
  });


  group('a window the curve will not fit in', () {
    // Fitting the height to `y = x^13` asks for a window ten million million
    // tall, and every consumer refuses a window like that IN SILENCE: the
    // block draws an empty box with no message, double-tap to reset fits the
    // same one again, and the PDF leaves the graph off the page altogether.
    Plot plot(String src, {bool fitY = true}) => plotFunction(
        compileFunction(src), GraphView.initial,
        samples: 400, fitY: fitY);

    test('is refused, and the window that was asked for is kept', () {
      for (final src in ['x^13', '100^x', 'e^(x^2)', '10^13', '10^14+x',
        '6.02*10^23*x']) {
        final p = plot(src);
        expect(p.view.isSane, isTrue, reason: src);
        expect(p.view.x0, GraphView.initial.x0, reason: src);
      }
    });

    test('and an ordinary curve is still fitted', () {
      final p = plot('x^2');
      expect(p.view.y1, lessThan(120), reason: 'fitted, not the default');
      expect(p.view.y1, greaterThan(90));
    });
  });

  group('the left of the equals sign', () {
    double at(String src, double x) {
      final s = graphSourceFromLinear(src);
      expect(s.isOk, isTrue, reason: '$src: ${s.error}');
      return s.fn!.at!(x);
    }

    test('a name is only a label', () {
      expect(at('y=4x', 3), 12);
      expect(at('h=4x', 3), 12);
      expect(at('f(x)=4x', 3), 12);
      expect(at('y1=4x', 3), 12);
    });

    test('but a coefficient is not a label, it is y scaled', () {
      // `2y = 4x` was drawn as `y = 4x`: twice the gradient, twice the
      // intercept, confidently, with nothing on screen to say so. Rearranging
      // a linear equation is the year-10 topic this feature is for.
      expect(at('2y=4x', 3), 6);
      expect(at('-y=x', 3), -3);
      expect(at('y/2=x', 3), 6);
      expect(at('3y=6x-9', 3), 3);
      expect(at('2y+4=6x', 1), 1, reason: '2y = 6x - 4, so y = 3x - 2');
    });

    test('and what cannot be rearranged is refused in words', () {
      for (final src in ['y^2=x', 'y*y=x', 'sin(y)=x', '2=x']) {
        final s = graphSourceFromLinear(src);
        expect(s.isOk, isFalse, reason: src);
        expect(s.error, contains('rearrange'), reason: src);
      }
    });

    test('a comparison is not an equation, and is no longer drawn', () {
      for (final src in ['y<=3x', 'y!=3', 'y>x']) {
        expect(graphSourceFromLinear(src).isOk, isFalse, reason: src);
      }
    });

    test('x on both sides still says so', () {
      final s = graphSourceFromLinear('2x+y=x');
      expect(s.isOk, isFalse);
      expect(s.error, contains('both sides'));
    });
  });

  group('the window a graph opens at', () {
    tearDown(() => mathAngleMode = AngleMode.degrees);

    test('a degrees sine opens on a whole wave, not on 5% of one', () {
      // Ten each way is twenty degrees. The single most likely thing a
      // student graphs was drawn as a straight diagonal filling the block.
      mathAngleMode = AngleMode.degrees;
      final v = initialViewFor(r'y=\sin(x)');
      expect(v.x0, -360);
      expect(v.x1, 360);
      final p = plotFunction(compileFunction('sin(x)'), v,
          samples: 400, fitY: true);
      var turns = 0;
      final pts = p.pieces.first;
      for (var i = 1; i < pts.length - 1; i++) {
        final a = pts[i].dy - pts[i - 1].dy;
        final b = pts[i + 1].dy - pts[i].dy;
        if (a != 0 && b != 0 && a.sign != b.sign) turns++;
      }
      expect(turns, greaterThanOrEqualTo(3), reason: 'it is a wave');
    });

    test('in radians it is ten each way, as it always was', () {
      mathAngleMode = AngleMode.radians;
      expect(initialViewFor(r'y=\sin(x)'), GraphView.initial);
    });

    test('and an angle that says radians keeps the small window', () {
      mathAngleMode = AngleMode.degrees;
      expect(initialViewFor(r'y=\sin(\pi x)'), GraphView.initial);
      expect(initialViewFor('y=sin(x rad)'), GraphView.initial);
    });

    test('anything that is not trigonometry is untouched', () {
      mathAngleMode = AngleMode.degrees;
      for (final src in ['y=3x+10', 'y=x^2', r'y=\frac{1}{x}', 'y=cosh(x)']) {
        expect(initialViewFor(src), GraphView.initial, reason: src);
      }
    });
  });

  group('hovering finds a point on the curve, or nothing', () {
    // Owner: "id like to be able to hover over a point on the line and have
    // it provide me the values for that point ... the values it shows
    // should be sensible (i.e. not showing crazy random decimals of x when
    // it doesnt make sense)."
    const view = GraphView(x0: -10, x1: 10, y0: -10, y1: 10);
    const size = Size(200, 200);
    // sx(x) = (x - -10) / 20 * 200 = (x + 10) * 10; sy(y) mirrors it.
    double sx(double x) => (x + 10) * 10;
    double sy(double y) => 200 - (y + 10) * 10;

    test('directly on the curve, x and y both come back', () {
      final src = graphSourceFromLinear('y=x'); // through the origin
      final hit = hoverPointNear(Offset(sx(0), sy(0)),
          source: src, view: view, size: size);
      expect(hit, isNotNull);
      expect(hit!.x, closeTo(0, 1e-9));
      expect(hit.y, closeTo(0, 1e-9));
    });

    test('within the pixel threshold still counts', () {
      final src = graphSourceFromLinear('y=x');
      final hit = hoverPointNear(Offset(sx(0) + 6, sy(0) + 6),
          source: src, view: view, size: size, maxDistance: 16);
      expect(hit, isNotNull, reason: 'inside the 16px radius asked for');
    });

    test('far from the curve vertically finds nothing', () {
      // y=x passes through the origin; up near the top of the window at
      // x=0 the curve is 10 units away, nowhere near the cursor.
      final src = graphSourceFromLinear('y=x');
      final hit = hoverPointNear(Offset(sx(0), sy(9)),
          source: src, view: view, size: size);
      expect(hit, isNull,
          reason: 'close in x is not the same as close to the curve');
    });

    test('the values are snapped, not raw pixel arithmetic', () {
      // A pixel at x=137 maps to a maths x with a long tail of decimals;
      // the returned x must be a clean multiple of the snap step instead.
      final src = graphSourceFromLinear('y=x');
      final hit = hoverPointNear(const Offset(137, 63),
          source: src, view: view, size: size, maxDistance: 200);
      expect(hit, isNotNull);
      final snap = gridStep(view.width, target: math.max(3, size.width ~/ 90)) / 10;
      final ratio = hit!.x / snap;
      expect(ratio, closeTo(ratio.round(), 1e-9),
          reason: 'x = ${hit.x} is not a clean multiple of $snap');
    });

    test('a vertical line reports x and no y', () {
      final src = graphSourceFromLinear('x=3');
      final near = hoverPointNear(Offset(sx(3), 100),
          source: src, view: view, size: size);
      expect(near, isNotNull);
      expect(near!.x, 3);
      expect(near.y.isNaN, isTrue,
          reason: 'every y is on a vertical line — none of them is THE y');

      final far = hoverPointNear(Offset(sx(8), 100),
          source: src, view: view, size: size);
      expect(far, isNull);
    });

    test('a point outside the visible window is not offered', () {
      // 1/x near zero is real and finite at the sampled x, but miles
      // outside a -10..10 window — nothing a dot should ever land on.
      final src = graphSourceFromLinear('1/x');
      final hit = hoverPointNear(Offset(sx(0.01), sy(0)),
          source: src, view: view, size: size);
      expect(hit, isNull);
    });

    test('a domain gap (sqrt of a negative) is not offered either', () {
      final src = graphSourceFromLinear('sqrt(x)');
      final hit = hoverPointNear(Offset(sx(-5), sy(0)),
          source: src, view: view, size: size);
      expect(hit, isNull);
    });

    test('an insane view is refused outright', () {
      final src = graphSourceFromLinear('y=x');
      final hit = hoverPointNear(const Offset(50, 50),
          source: src,
          view: const GraphView(x0: 0, x1: 0, y0: 0, y1: 0),
          size: size);
      expect(hit, isNull);
    });

    test('a graph that failed to compile offers nothing to hover', () {
      final src = graphSourceFromLinear('this is not maths');
      expect(src.isOk, isFalse);
      final hit = hoverPointNear(const Offset(50, 50),
          source: src, view: view, size: size);
      expect(hit, isNull);
    });
  });

  group('substituting a value into an equation', () {
    test('a straight line, at an ordinary point', () {
      final r = substituteInto(graphSourceFromLinear('y=3x+10'), '2');
      expect(r.variable, 'x');
      expect(r.result.isOk, isTrue);
      expect(r.result.value, 16);
    });

    test('the typed value is itself an expression, not just a literal', () {
      // The owner asked for "sub in a value for x ... this doesnt have to
      // be linked to the graph though" — but it should still feel like the
      // rest of the app, where `2+3` and `pi` are numbers too.
      final r = substituteInto(graphSourceFromLinear('y=x^2'), '2+3');
      expect(r.result.isOk, isTrue);
      expect(r.result.value, 25);
    });

    test('a rearranged equation is still substituted into for x', () {
      // `2y=6x+4` is rearranged to `y=3x+2` before it is ever compiled
      // (graphSourceFromLinear's own job) — the variable substituted into
      // is x either way, which is what this checks.
      final r = substituteInto(graphSourceFromLinear('2y=6x+4'), '1');
      expect(r.variable, 'x');
      expect(r.result.value, closeTo(5, 1e-9));
    });

    test('a vertical line has nothing to substitute into', () {
      final r = substituteInto(graphSourceFromLinear('x=3'), '1');
      expect(r.result.isOk, isFalse);
    });

    test('an equation the calculator cannot read propagates its own error',
        () {
      final source = graphSourceFromLinear('this is not maths');
      final r = substituteInto(source, '1');
      expect(r.result.isOk, isFalse);
      expect(r.result.error, source.error);
    });

    test('nonsense typed as the value is an error, not a crash', () {
      final r = substituteInto(graphSourceFromLinear('y=x'), 'banana');
      expect(r.result.isOk, isFalse);
    });

    test('a value outside the domain reads undefined, not a crash', () {
      final r = substituteInto(graphSourceFromLinear('y=sqrt(x)'), '-1');
      expect(r.result.isOk, isTrue);
      expect(r.result.display, 'undefined');
    });
  });
}
