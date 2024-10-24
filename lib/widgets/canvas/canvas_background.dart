import 'package:flutter/material.dart';

/// Widget that draws the background of the canvas, which is currently a grid.
class CanvasBackground extends StatelessWidget {
  final Size canvasSize;

  const CanvasBackground({Key? key, required this.canvasSize}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: canvasSize.width,
      height: canvasSize.height,
      color: Colors.grey[850], // Background color of the canvas.
      child: CustomPaint(
        size: canvasSize,
        painter: CanvasBackgroundPainter(), // Uses CanvasBackgroundPainter to draw the grid.
      ),
    );
  }
}

/// Custom painter that draws a grid on the canvas.
class CanvasBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue.shade700 // Color of the grid lines.
      ..strokeWidth = 1.0; // Width of the grid lines.

    // Draw vertical grid lines.
    for (double i = 0; i < size.width; i += 50) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }

    // Draw horizontal grid lines.
    for (double i = 0; i < size.height; i += 50) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false; // Optimization: only repaint when needed.
  }
}