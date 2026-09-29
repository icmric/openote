// The arithmetic behind drawing a shape with the pen.
//
// Issue #10: *"Drawing diagrams with a mouse is really difficult without the
// simple shapes."* Every decision worth arguing about lives in `shapePoints`
// and is asserted here rather than dragged out of a widget: where an arrow's
// barbs sit, which way a square grows, what Shift does to a line.

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/ink_shapes.dart';

void main() {
  const a = Offset(100, 100);

  /// The axis-aligned box the points occupy.
  ({double l, double t, double r, double b}) boundsOf(List<Offset> pts) => (
        l: pts.map((p) => p.dx).reduce(math.min),
        t: pts.map((p) => p.dy).reduce(math.min),
        r: pts.map((p) => p.dx).reduce(math.max),
        b: pts.map((p) => p.dy).reduce(math.max),
      );

  group('every shape', () {
    test('has at least two points, even dragged to nothing', () {
      // A caller must never have to handle a degenerate stroke: `_inkUp`
      // discards anything shorter than two points, so a shape that collapsed
      // to one would silently not be drawn at all.
      for (final s in InkShape.values) {
        expect(shapePoints(s, a, a).length, greaterThanOrEqualTo(2),
            reason: '${s.name} dragged to nothing');
      }
    });

    test('stays inside the box it was dragged out, give or take nothing', () {
      // The preview follows the pointer, so a shape that overflowed its drag
      // would not be where the person is pointing. The arrow is exempt: its
      // barbs deliberately sit outside the shaft's line.
      const b = Offset(300, 220);
      for (final s in InkShape.values) {
        if (s == InkShape.arrow) continue;
        final r = boundsOf(shapePoints(s, a, b));
        expect(r.l, greaterThanOrEqualTo(a.dx - 0.001), reason: s.name);
        expect(r.t, greaterThanOrEqualTo(a.dy - 0.001), reason: s.name);
        expect(r.r, lessThanOrEqualTo(b.dx + 0.001), reason: s.name);
        expect(r.b, lessThanOrEqualTo(b.dy + 0.001), reason: s.name);
      }
    });

    test('is drawn the same way dragged backwards as forwards', () {
      // Dragging up-left is as ordinary as dragging down-right, and a shape
      // that only worked one way would look broken half the time.
      const b = Offset(300, 220);
      for (final s in InkShape.values) {
        if (s == InkShape.arrow || s == InkShape.line) continue;
        final f = boundsOf(shapePoints(s, a, b));
        final r = boundsOf(shapePoints(s, b, a));
        expect(r.r - r.l, closeTo(f.r - f.l, 0.001), reason: '${s.name} width');
        expect(r.b - r.t, closeTo(f.b - f.t, 0.001), reason: '${s.name} height');
      }
    });
  });

  group('line', () {
    test('is the two ends and nothing else', () {
      expect(shapePoints(InkShape.line, a, const Offset(200, 160)),
          [a, const Offset(200, 160)]);
    });

    test('snaps to the nearest 45° with Shift, keeping its length', () {
      // The one people reach for most: a rule drawn freehand is never quite
      // horizontal, and a diagram made of nearly-straight lines looks wrong in
      // a way that is hard to point at.
      final pts = shapePoints(InkShape.line, a, const Offset(200, 108),
          constrain: true);
      expect(pts.last.dy, closeTo(100, 0.001), reason: 'pulled flat');
      expect((pts.last - a).distance,
          closeTo((const Offset(200, 108) - a).distance, 0.001),
          reason: 'and no shorter than it was dragged');
    });

    test('snaps to a true diagonal too, not only to the axes', () {
      // Dragged to within a few degrees of 45°, so the nearest ray really is
      // the diagonal — (200, 90) is 5.7° off HORIZONTAL and correctly snaps
      // flat, which is a fine thing for the code to do and a poor test of
      // diagonals.
      final pts =
          shapePoints(InkShape.line, a, const Offset(200, 10), constrain: true);
      final d = pts.last - a;
      expect(d.dx, closeTo(d.dy.abs(), 0.001));
      expect(d.dy, lessThan(0), reason: 'up and to the right, as dragged');
    });
  });

  group('arrow', () {
    const tip = Offset(300, 100);
    test('retraces through the tip, so one stroke draws all three lines', () {
      // A stroke is a single run of points. Out to the tip, back along one
      // barb, out again — the path a hand actually takes.
      final pts = shapePoints(InkShape.arrow, a, tip);
      expect(pts.length, 5);
      expect(pts[0], a);
      expect(pts[1], tip);
      expect(pts[3], tip, reason: 'back to the tip between the barbs');
    });

    test('puts both barbs behind the tip, one either side', () {
      final pts = shapePoints(InkShape.arrow, a, tip);
      for (final barb in [pts[2], pts[4]]) {
        expect(barb.dx, lessThan(tip.dx), reason: 'behind the tip');
      }
      expect((pts[2].dy - tip.dy).sign, isNot((pts[4].dy - tip.dy).sign),
          reason: 'and on opposite sides of the shaft');
    });

    test('keeps the head in proportion, but never lets it eat the arrow', () {
      // A long arrow with a stubby head reads as a line; a short one with a
      // full-size head reads as a dart. Proportional, then clamped.
      final long = shapePoints(InkShape.arrow, Offset.zero, const Offset(4000, 0));
      final short = shapePoints(InkShape.arrow, Offset.zero, const Offset(20, 0));
      final longHead = (long[2] - long[1]).distance;
      final shortHead = (short[2] - short[1]).distance;
      expect(longHead, lessThanOrEqualTo(26.001));
      expect(shortHead, greaterThanOrEqualTo(8.999));
      expect(shortHead, lessThan(20), reason: 'still shorter than the shaft');
    });

    test('points the right way whichever way it is drawn', () {
      final left = shapePoints(InkShape.arrow, const Offset(300, 100), a);
      for (final barb in [left[2], left[4]]) {
        expect(barb.dx, greaterThan(a.dx),
            reason: 'barbs trail BEHIND a leftward tip, not in front of it');
      }
    });
  });

  group('rectangle', () {
    test('is four corners, closed', () {
      const b = Offset(300, 220);
      final pts = shapePoints(InkShape.rectangle, a, b);
      expect(pts.length, 5);
      expect(pts.first, pts.last, reason: 'an open rectangle has a gap in it');
      expect(pts.toSet().length, 4, reason: 'four distinct corners');
    });

    test('becomes a square with Shift, following the longer side', () {
      // The larger side wins: a drag that is mostly sideways becomes the
      // square you can see rather than the one you cannot.
      final pts = shapePoints(InkShape.rectangle, a, const Offset(400, 150),
          constrain: true);
      final r = boundsOf(pts);
      expect(r.r - r.l, closeTo(300, 0.001));
      expect(r.b - r.t, closeTo(300, 0.001));
    });

    test('and a square dragged up-left goes up-left', () {
      final pts = shapePoints(InkShape.rectangle, a, const Offset(-100, 40),
          constrain: true);
      final r = boundsOf(pts);
      expect(r.r - r.l, closeTo(200, 0.001));
      expect(r.l, closeTo(-100, 0.001), reason: 'grew leftwards, as dragged');
    });
  });

  group('ellipse', () {
    const b = Offset(300, 200);
    test('fills the dragged box exactly', () {
      final r = boundsOf(shapePoints(InkShape.ellipse, a, b));
      expect(r.l, closeTo(100, 0.001));
      expect(r.r, closeTo(300, 0.001));
      expect(r.t, closeTo(100, 0.001));
      expect(r.b, closeTo(200, 0.001));
    });

    test('is closed, and smooth enough that no flat is visible', () {
      final pts = shapePoints(InkShape.ellipse, a, b);
      expect(pts.length, kEllipseSegments + 1);
      expect(pts.first.dx, closeTo(pts.last.dx, 0.001));
      expect(pts.first.dy, closeTo(pts.last.dy, 0.001));
    });

    test('becomes a circle with Shift', () {
      final r = boundsOf(
          shapePoints(InkShape.ellipse, a, const Offset(400, 150),
              constrain: true));
      expect(r.r - r.l, closeTo(r.b - r.t, 0.001));
    });
  });

  group('triangle', () {
    test('stands upright on the bottom edge, apex centred', () {
      // Upright and symmetrical is what a triangle is nearly always wanted
      // for — a roof, a delta, a warning — and a corner apex would need a
      // second drag to fix every single time.
      const b = Offset(300, 220);
      final pts = shapePoints(InkShape.triangle, a, b);
      expect(pts.length, 4);
      expect(pts.first, pts.last, reason: 'closed');
      expect(pts[0].dx, closeTo(200, 0.001), reason: 'apex centred');
      expect(pts[0].dy, closeTo(100, 0.001), reason: 'apex on the top edge');
      expect(pts[1].dy, closeTo(220, 0.001));
      expect(pts[2].dy, closeTo(220, 0.001));
    });
  });

  group('densify', () {
    // Why this exists at all: the eraser keeps or drops each POINT by its
    // distance from the pointer, and the lasso asks which points fall inside
    // the loop. Neither looks at the line between two points, because
    // handwriting is sampled far too finely for it ever to matter. A shape is
    // not — a line is two points — so drawn raw you could not rub out the
    // middle of one. A real test erasing a real line is what found this.

    test('leaves no gap the eraser could step over', () {
      for (final shape in InkShape.values) {
        final pts =
            densify(shapePoints(shape, const Offset(0, 0), const Offset(400, 300)));
        for (var i = 1; i < pts.length; i++) {
          expect((pts[i] - pts[i - 1]).distance,
              lessThanOrEqualTo(kShapeMaxGap + 0.001),
              reason: shape.name);
        }
      }
    });

    test('keeps the corners, or a rectangle would come out rounded', () {
      final corners = shapePoints(InkShape.rectangle, Offset.zero, const Offset(90, 60));
      final dense = densify(corners);
      for (final c in corners) {
        expect(dense.any((p) => (p - c).distance < 0.001), isTrue,
            reason: '$c was interpolated away');
      }
    });

    test('adds points along the line and nowhere else', () {
      // Straight interpolation: every added point is ON the segment it came
      // from, so densifying changes nothing about the shape.
      final pts = densify([const Offset(0, 0), const Offset(30, 0)]);
      expect(pts.length, 11);
      for (final p in pts) {
        expect(p.dy, closeTo(0, 0.001));
      }
      expect(pts.first, Offset.zero);
      expect(pts.last, const Offset(30, 0));
    });

    test('widens the gaps rather than refusing a very large shape', () {
      // A shape dragged right across a big page would otherwise be tens of
      // thousands of points. Acceptable: nothing that big is being erased at
      // maximum zoom.
      final pts = densify(
          shapePoints(InkShape.rectangle, Offset.zero, const Offset(9000, 9000)));
      expect(pts.length, lessThanOrEqualTo(kShapeMaxPoints + 8));
      expect(pts.length, greaterThan(100), reason: 'but still drawn');
    });

    test('passes a degenerate run through untouched', () {
      expect(densify(const [Offset(5, 5)]), const [Offset(5, 5)]);
      expect(densify(const [Offset(5, 5), Offset(5, 5)]).length, 2);
    });
  });
}
