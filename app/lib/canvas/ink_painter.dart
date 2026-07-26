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

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      _paintStroke(canvas, s);
    }
    if (wet != null) _paintStroke(canvas, wet!);
  }

  void _paintStroke(Canvas canvas, Stroke s) {
    if (s.x.isEmpty) return;
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
    if (outline.isEmpty) return;
    // Use dx/dy: getStroke's outline points are Offsets in some
    // perfect_freehand versions and PointVectors (an Offset subclass) in
    // others — dx/dy is the API that exists in both.
    final path = Path()..moveTo(outline.first.dx, outline.first.dy);
    for (final pt in outline.skip(1)) {
      path.lineTo(pt.dx, pt.dy);
    }
    path.close();
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

  @override
  bool shouldRepaint(covariant InkPainter old) =>
      old.wet != wet ||
      old.autoColor != autoColor ||
      old.strokes.length != strokes.length ||
      (strokes.isNotEmpty &&
          (!identical(old.strokes.first, strokes.first) ||
              !identical(old.strokes.last, strokes.last)));
}
