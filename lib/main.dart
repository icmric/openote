import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Canvas App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const CanvasPage(),
    );
  }
}

class CanvasPage extends StatefulWidget {
  const CanvasPage({super.key});

  @override
  State<CanvasPage> createState() => _CanvasPageState();
}

class _CanvasPageState extends State<CanvasPage> {
  Offset _canvasOffset = Offset.zero;
  Size _canvasSize = const Size(1000, 800); // Initial size

  // For zooming and panning with InteractiveViewer
  final TransformationController _transformationController = TransformationController();

  List<Offset> _boxPositions = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Canvas App'),
      ),
      body: InteractiveViewer(
        constrained: false,
        boundaryMargin: EdgeInsets.all(double.infinity),
        transformationController: _transformationController,
        child: SizedBox(
          width: _canvasSize.width,
          height: _canvasSize.height,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: (details) {
              Offset canvasTapPosition = details.localPosition;

              setState(() {
                _boxPositions.add(canvasTapPosition);
              });
              print("Canvas Tap Position: $canvasTapPosition");
            },
            child: Stack(
              children: [
                Container(
                  // Background Container
                  width: _canvasSize.width, // Explicitly set width and height
                  height: _canvasSize.height,
                  color: Colors.grey[300],
                  child: CustomPaint(
                    // Grid painter
                    size: _canvasSize, // Provide size to the painter
                    painter: GridPainter(),
                  ),
                ),
                ..._boxPositions.map((position) {
                  return Positioned(
                    left: position.dx,
                    top: position.dy,
                    child: Container(
                      width: 50,
                      height: 50,
                      color: Colors.red,
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void updateCanvasSize(Size newSize) {
    setState(() {
      _canvasSize = newSize;
    });
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 1.0;

    for (double i = 0; i < size.width; i += 50) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 50) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false; // Optimization: only repaint when needed.
  }
}
