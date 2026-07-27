import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

import '../model/models.dart';

Color colorFromHex(String hex) =>
    Color(0xFF000000 | (int.tryParse(hex.replaceFirst('#', ''), radix: 16) ?? 0));

/// Renders strokes as pressure-responsive variable-width outlines
/// (Ink Data Spec §4 — the perfect-freehand pipeline).
///
/// A stroke whose brush colour is `"auto"` (no explicit colour chosen — e.g.
/// OneNote-imported ink with the default pen) renders in [autoColor], the
/// theme's default ink: dark on a light page, light on a dark page — the same
/// contract as default text colour. Explicitly-coloured strokes always keep
/// their colour.
class InkPainter extends CustomPainter {
  InkPainter(this.strokes,
      {this.wet, this.autoColor = const Color(0xFF211F1B), super.repaint});
  final List<Stroke> strokes;
  final Stroke? wet; // in-progress stroke, drawn last (mutated between repaints)
  final Color autoColor;

  /// Tessellated outlines, attached to the **Stroke object itself**.
  ///
  /// Solving a stroke's variable-width outline (`getStroke`) is the expensive
  /// part of drawing ink, and it used to run for every visible stroke on every
  /// repaint. Because wet ink repaints once per stylus sample (100+/s), a page
  /// carrying a few hundred imported strokes re-solved all of them per sample —
  /// the dominant cost of inking on imported pages.
  ///
  /// Keyed by object identity rather than `Stroke.id` on purpose: stroke
  /// coordinates are page-absolute and are **mutated in place** when an ink
  /// block is dragged, so an id-keyed cache would hand back stale geometry.
  /// The canvas re-decodes strokes into fresh objects whenever a block's
  /// `updatedAt` changes, which invalidates these entries automatically. An
  /// [Expando] also holds its keys weakly, so nothing needs evicting.
  static final Expando<Path> _outlines = Expando<Path>('inkOutline');

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      _paintStroke(canvas, s, cache: true);
    }
    // The wet stroke grows every sample — never cache it.
    if (wet != null) _paintStroke(canvas, wet!, cache: false);
  }

  void _paintStroke(Canvas canvas, Stroke s, {required bool cache}) {
    if (s.x.isEmpty) return;
    Path? path = cache ? _outlines[s] : null;
    if (path == null) {
      path = _outlinePath(s);
      if (path == null) return;
      if (cache) _outlines[s] = path;
    }
    final base = s.colorHex == 'auto' ? autoColor : colorFromHex(s.colorHex);
    final paint = Paint()
      ..color = base.withValues(alpha: s.opacity)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    if (s.tool == 'highlighter') {
      paint.blendMode = BlendMode.multiply;
    }
    canvas.drawPath(path, paint);
  }

  /// Solve one stroke's variable-width outline into a fillable path.
  Path? _outlinePath(Stroke s) {
    final hasPressure = s.p.isNotEmpty;
    final points = [
      for (var i = 0; i < s.x.length; i++)
        PointVector(s.x[i], s.y[i], hasPressure ? s.p[i] : 0.5),
    ];
    final outline = getStroke(
      points,
      options: StrokeOptions(
        size: s.size * (s.tool == 'highlighter' ? 3 : 1),
        thinning: s.tool == 'highlighter' ? 0.0 : 0.6,
        smoothing: 0.5,
        streamline: 0.5,
        simulatePressure: !hasPressure,
      ),
    );
    if (outline.isEmpty) return null;
    // Use dx/dy: getStroke's outline points are Offsets in some
    // perfect_freehand versions and PointVectors (an Offset subclass) in
    // others — dx/dy is the API that exists in both.
    final path = Path()..moveTo(outline.first.dx, outline.first.dy);
    for (final pt in outline.skip(1)) {
      path.lineTo(pt.dx, pt.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(covariant InkPainter old) =>
      old.wet != wet ||
      old.autoColor != autoColor ||
      old.strokes.length != strokes.length ||
      (strokes.isNotEmpty &&
          (!identical(old.strokes.first, strokes.first) ||
              !identical(old.strokes.last, strokes.last)));
}
