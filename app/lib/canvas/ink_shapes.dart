// Drawing a shape with the pen.
//
// Issue #10: *"Drawing diagrams with a mouse is really difficult without the
// simple shapes."* The owner: *"no ink recognition or anything just yet, all i
// want is to be able to draw diagrams and what not with the pen."*
//
// **A shape is a stroke.** Not a new kind of object, not a block, not a record
// in the file format — the same `Stroke` a hand draws, with its points worked
// out instead of sampled. That one decision is why this is small: a shape
// inherits the colour (including `auto`, which follows the theme), the pen
// size, the opacity, both eraser modes, lasso selection, undo, the ink blob
// store, sync, and the InkML and PDF exporters, without any of them being
// told that shapes exist. A rectangle is five points. An ellipse is a
// polyline fine enough that nobody can see the corners.
//
// The cost is that a shape cannot be re-shaped after it is drawn: it is ink,
// and ink is edited with the eraser. That is the right trade for "I need to
// draw a diagram in a lesson" and the wrong one for a diagramming app, which
// this is not trying to be.

import 'dart:math' as math;

import 'dart:ui' show Offset;

/// The shapes the pen can draw instead of following the hand.
enum InkShape {
  line,
  arrow,
  rectangle,
  ellipse,
  triangle;

  /// What to call it, in the plainest word there is.
  ///
  /// Not translated, matching [EraserMode.label] in the same toolbar row. Both
  /// are a gap rather than a decision — see the note on [tooltip].
  String get label => switch (this) {
        InkShape.line => 'Line',
        InkShape.arrow => 'Arrow',
        InkShape.rectangle => 'Rectangle',
        InkShape.ellipse => 'Ellipse',
        InkShape.triangle => 'Triangle',
      };

  /// The name, plus what Shift does to THIS shape.
  ///
  /// On the button rather than written beside the row, which is where it
  /// started. Two reasons, and the second is the real one: a line of text in
  /// the toolbar costs width on the control people came for, and "Shift =
  /// regular" is exactly the sort of half-sentence somebody has to decode —
  /// the year-10 bar says tell them what it does to the thing they are
  /// pointing at. Nobody discovers a modifier key on their own, and a tooltip
  /// is where they look when they wonder.
  String get tooltip => switch (this) {
        InkShape.line => 'Line — hold Shift to keep it straight',
        InkShape.arrow => 'Arrow — hold Shift to keep it straight',
        InkShape.rectangle => 'Rectangle — hold Shift for a square',
        InkShape.ellipse => 'Ellipse — hold Shift for a circle',
        InkShape.triangle => 'Triangle',
      };
}

/// How many segments an ellipse is drawn with.
///
/// Enough that the flats are invisible at the zoom anybody draws at, few
/// enough that a page of them is still cheap to paint and to store: the points
/// are written into the ink blob, so this number is a file-size decision as
/// much as a smoothness one.
const int kEllipseSegments = 48;

/// The barb of an arrow head, as a fraction of the shaft.
///
/// Proportional so a long arrow does not get a stubby head, clamped so a short
/// one does not become all head — the clamp is what stops a 6px nudge drawing
/// a dart.
const double _headFraction = 0.18;
const double _headMin = 9;
const double _headMax = 26;
const double _headAngle = 0.45; // radians, ≈26°

/// **The points of [shape], dragged from [from] to [to].**
///
/// Pure, and deliberately so: every interesting decision here — where an
/// arrow's barbs sit, whether a square is anchored or centred, what Shift does
/// to a line — is arithmetic that can be asserted directly instead of being
/// dragged out of a widget.
///
/// [constrain] is Shift: the regular version of whatever is being drawn. A
/// square rather than a rectangle, a circle rather than an ellipse, and a line
/// snapped to the nearest 45°, which is the one people reach for most because
/// a horizontal rule drawn by hand is never quite horizontal.
///
/// The result always has at least two points, so a caller never has to handle
/// a degenerate stroke; a shape dragged to nothing is a dot, which is what a
/// pen does when you tap it on paper.
List<Offset> shapePoints(InkShape shape, Offset from, Offset to,
    {bool constrain = false}) {
  final end = switch (shape) {
    InkShape.line || InkShape.arrow =>
      constrain ? _snapTo45(from, to) : to,
    _ => constrain ? _squared(from, to) : to,
  };
  return switch (shape) {
    InkShape.line => [from, end],
    InkShape.arrow => _arrow(from, end),
    InkShape.rectangle => _rectangle(from, end),
    InkShape.ellipse => _ellipse(from, end),
    InkShape.triangle => _triangle(from, end),
  };
}

/// [to] pulled onto the nearest 45° ray from [from], keeping its distance.
Offset _snapTo45(Offset from, Offset to) {
  final d = to - from;
  final len = d.distance;
  if (len == 0) return to;
  const step = math.pi / 4;
  final snapped = (math.atan2(d.dy, d.dx) / step).roundToDouble() * step;
  return from + Offset(math.cos(snapped), math.sin(snapped)) * len;
}

/// [to] pulled so the box from [from] is square, keeping the drag's direction.
///
/// The larger of the two sides wins rather than the smaller: a drag that is
/// mostly sideways becomes the square you can see, not the one you can't.
Offset _squared(Offset from, Offset to) {
  final dx = to.dx - from.dx, dy = to.dy - from.dy;
  final side = math.max(dx.abs(), dy.abs());
  return Offset(
    from.dx + (dx.isNegative ? -side : side),
    from.dy + (dy.isNegative ? -side : side),
  );
}

/// Shaft, then both barbs, as ONE retracing polyline.
///
/// A stroke is a single run of points, so the pen goes out to the tip, back
/// along one barb to the tip again, and out along the other — exactly the path
/// a hand draws an arrow with, and it renders identically.
List<Offset> _arrow(Offset from, Offset to) {
  final d = to - from;
  final len = d.distance;
  if (len == 0) return [from, to];
  final head = (len * _headFraction).clamp(_headMin, _headMax);
  // Back along the shaft, so the barbs point the right way whatever the angle.
  final back = math.atan2(-d.dy, -d.dx);
  Offset barb(double turn) =>
      to + Offset(math.cos(back + turn), math.sin(back + turn)) * head;
  return [from, to, barb(_headAngle), to, barb(-_headAngle)];
}

/// Five points: the corners, and back to the first so the outline closes.
List<Offset> _rectangle(Offset a, Offset b) => [
      a,
      Offset(b.dx, a.dy),
      b,
      Offset(a.dx, b.dy),
      a,
    ];

/// Inscribed in the dragged box, closed by repeating the first point.
List<Offset> _ellipse(Offset a, Offset b) {
  final cx = (a.dx + b.dx) / 2, cy = (a.dy + b.dy) / 2;
  final rx = (b.dx - a.dx).abs() / 2, ry = (b.dy - a.dy).abs() / 2;
  return [
    for (var i = 0; i <= kEllipseSegments; i++)
      () {
        final th = i * 2 * math.pi / kEllipseSegments;
        return Offset(cx + rx * math.cos(th), cy + ry * math.sin(th));
      }()
  ];
}

/// Apex centred on the top edge of the dragged box, closed.
///
/// Centred rather than cornered because a triangle is nearly always wanted
/// upright and symmetrical — a roof, an arrowhead, a delta — and a corner
/// apex would need a second drag to fix every time.
List<Offset> _triangle(Offset a, Offset b) => [
      Offset((a.dx + b.dx) / 2, a.dy),
      Offset(b.dx, b.dy),
      Offset(a.dx, b.dy),
      Offset((a.dx + b.dx) / 2, a.dy),
    ];

/// **The gap a shape's points are resampled to, in page units.**
///
/// A shape is ink, and the things that act on ink act on its POINTS: the
/// eraser keeps or drops each point by its distance from the pointer, and the
/// lasso asks which points fall inside the loop. Neither looks at the line
/// BETWEEN two points, because handwriting is sampled densely enough that the
/// question never comes up — a hand moving 200px a second at 120Hz leaves a
/// point every couple of pixels.
///
/// A shape does not. A line is two points, and a rectangle four: drawn raw,
/// you could not rub out the middle of one, because there was nothing there to
/// rub out. The first version of this shipped exactly that, and the test that
/// erases a line is what caught it.
///
/// Three, because the eraser's radius is `12 / scale` page units and the
/// canvas zooms to [CanvasController.maxScale] = 8, so the radius bottoms out
/// at 1.5. Points no more than twice that apart cannot be stepped over at any
/// zoom the app allows. It is also still SPARSER than handwriting, so a shape
/// costs no more to store than drawing one by hand would.
const double kShapeMaxGap = 3;

/// A ceiling on how many points one shape may become.
///
/// Only reachable by dragging a shape across a very large page, where the gaps
/// widen past [kShapeMaxGap] — acceptable, because nothing that big is being
/// erased at maximum zoom.
const int kShapeMaxPoints = 1200;

/// [pts] resampled so no two neighbours are more than [maxGap] apart.
///
/// Straight interpolation, which is exactly right: every shape here is a
/// polyline already, so the added points lie on the line that was going to be
/// drawn anyway and nothing about the shape changes. See [kShapeMaxGap] for
/// why this is needed at all.
List<Offset> densify(List<Offset> pts,
    {double maxGap = kShapeMaxGap, int maxPoints = kShapeMaxPoints}) {
  if (pts.length < 2) return pts;
  final total = [
    for (var i = 1; i < pts.length; i++) (pts[i] - pts[i - 1]).distance
  ].fold(0.0, (a, b) => a + b);
  if (total <= 0) return pts;
  // Widen the gap rather than refuse, so a very large shape is still drawn.
  final gap = math.max(maxGap, total / (maxPoints - pts.length).clamp(1, 1 << 30));

  final out = <Offset>[pts.first];
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1], b = pts[i];
    final len = (b - a).distance;
    final steps = (len / gap).ceil();
    for (var k = 1; k < steps; k++) {
      out.add(Offset.lerp(a, b, k / steps)!);
    }
    // The corner itself, always: a rectangle whose corners were interpolated
    // away would have rounded ones.
    out.add(b);
  }
  return out;
}
