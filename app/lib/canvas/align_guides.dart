/// Alignment guides (CANVAS-7): the lines that appear while you drag a block
/// past a neighbour's edge, and the nudge that snaps it flush.
///
/// This is the cheapest large win in "it feels unfinished". Freeform placement
/// means every box is a few pixels off from its neighbours, and a page of
/// almost-aligned boxes reads as sloppy in a way users notice without being
/// able to name. OneNote has these; so does every design tool.
///
/// Pure functions over rectangles so the behaviour is testable without a
/// canvas — the geometry is the part that goes subtly wrong.
library;

import 'dart:ui';

/// A guide to draw, in page coordinates.
class AlignGuide {
  const AlignGuide({
    required this.vertical,
    required this.position,
    required this.from,
    required this.to,
  });

  /// True for a vertical line (aligning x), false for horizontal (aligning y).
  final bool vertical;

  /// The x (vertical guide) or y (horizontal guide) the line sits at.
  final double position;

  /// The span the line covers, so it visibly connects the two blocks rather
  /// than crossing the whole page.
  final double from;
  final double to;
}

/// The result of testing a candidate position against its neighbours.
class SnapResult {
  const SnapResult({required this.offset, required this.guides});

  /// The correction to apply to the dragged rect, page units. Zero on no snap.
  final Offset offset;
  final List<AlignGuide> guides;

  bool get snapped => offset != Offset.zero || guides.isNotEmpty;
}

/// Edges of a rect that can align, in the order they're preferred.
///
/// Centre before far edge: when two candidates are within threshold, matching
/// centres reads as more deliberate than matching a trailing edge.
List<double> _xEdges(Rect r) => [r.left, r.center.dx, r.right];
List<double> _yEdges(Rect r) => [r.top, r.center.dy, r.bottom];

/// Find alignments between [moving] and [others].
///
/// [threshold] is in page units and should be scaled by the caller for zoom —
/// a guide that triggers at 6 page-pixels feels sticky when zoomed in and
/// unreachable when zoomed out.
SnapResult findAlignment(
  Rect moving,
  Iterable<Rect> others, {
  double threshold = 6.0,
  int maxGuides = 3,
}) {
  double? bestDx, bestDy;
  var bestXDist = threshold, bestYDist = threshold;
  final guides = <AlignGuide>[];

  for (final other in others) {
    // Vertical alignment (x edges).
    for (final mx in _xEdges(moving)) {
      for (final ox in _xEdges(other)) {
        final dist = (mx - ox).abs();
        if (dist > threshold) continue;
        if (dist < bestXDist) {
          bestXDist = dist;
          bestDx = ox - mx;
        }
        if (dist <= threshold) {
          guides.add(AlignGuide(
            vertical: true,
            position: ox,
            // Span both blocks so the line shows what it is aligning to.
            from: [moving.top, other.top].reduce((a, b) => a < b ? a : b),
            to: [moving.bottom, other.bottom].reduce((a, b) => a > b ? a : b),
          ));
        }
      }
    }
    // Horizontal alignment (y edges).
    for (final my in _yEdges(moving)) {
      for (final oy in _yEdges(other)) {
        final dist = (my - oy).abs();
        if (dist > threshold) continue;
        if (dist < bestYDist) {
          bestYDist = dist;
          bestDy = oy - my;
        }
        if (dist <= threshold) {
          guides.add(AlignGuide(
            vertical: false,
            position: oy,
            from: [moving.left, other.left].reduce((a, b) => a < b ? a : b),
            to: [moving.right, other.right].reduce((a, b) => a > b ? a : b),
          ));
        }
      }
    }
  }

  // De-duplicate: several neighbours often share an edge, and drawing the same
  // line five times just makes it thicker.
  final seen = <String>{};
  final unique = <AlignGuide>[];
  for (final g in guides) {
    final key = '${g.vertical}:${g.position.toStringAsFixed(2)}';
    if (!seen.add(key)) continue;
    unique.add(g);
    if (unique.length >= maxGuides * 2) break;
  }

  return SnapResult(
    offset: Offset(bestDx ?? 0, bestDy ?? 0),
    guides: unique,
  );
}
