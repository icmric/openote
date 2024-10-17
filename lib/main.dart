import 'dart:developer';

import 'package:flutter/material.dart';
import 'draggable_text_field.dart';

void main() {
  runApp(const MyApp());
}

/// The main application widget.
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

/// A stateful widget representing the canvas page where draggable text fields can be added.
class CanvasPage extends StatefulWidget {
  const CanvasPage({super.key});

  @override
  State<CanvasPage> createState() => _CanvasPageState();
}

class _CanvasPageState extends State<CanvasPage> {
  final List<Offset> _boxPositions = [];
  final List<TextEditingController> _textControllers = [];
  final List<DraggableTextField> _textForms = [];
  final List<FocusNode> _focusNodes = []; // List to store focus nodes
  Size _canvasSize = const Size(800, 600);
  final TransformationController _transformationController = TransformationController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeCanvasSize();
      _positionCanvasTopLeft();
    });
  }

  void _initializeCanvasSize() {
    final Size screenSize = MediaQuery.of(context).size;

    setState(() {
      _canvasSize = Size(screenSize.width * 2, screenSize.height * 2);
    });
  }

  void _positionCanvasTopLeft() {
    try {
      _transformationController.value = Matrix4.identity()..translate(100, 100); // Ensure the top-left of the canvas is at the top-left of the screen
    } catch (e) {}
  }

  /// Handles tap down events to add a new draggable text field if the tap is not on an existing box.
  void _handleTapDown(TapDownDetails details) {
    Offset canvasTapPosition = details.localPosition;
    bool isOnExistingBox = _boxPositions.any((position) {
      int index = _boxPositions.indexOf(position);
      double width = _textForms[index].initialWidth;
      // Check if tap is within the bounds of an existing box, including the header
      return (canvasTapPosition.dx >= position.dx &&
          canvasTapPosition.dx <= position.dx + width &&
          canvasTapPosition.dy >= position.dy &&
          canvasTapPosition.dy <= position.dy + (_focusNodes[index].hasFocus ? 47 : 22)); // Adjust height based on focus
    });

    if (!isOnExistingBox) {
      // Create a new focus node and request focus for it
      FocusNode newFocusNode = FocusNode();

      setState(() {
        _boxPositions.add(canvasTapPosition);
        _textControllers.add(TextEditingController());
        _focusNodes.add(newFocusNode); // Add the new focus node to the list
        _textForms.add(DraggableTextField(
          controller: _textControllers.last,
          // TODO loses focus when draging the text field
          focusNode: newFocusNode, // Assign the focus node to the text field
          initialPosition: canvasTapPosition - const Offset(5, 50), // Adjust for drag bar and text padding
          initialWidth: 200,
          onDragEnd: (newPosition) {
            setState(() {
              int index = _textForms.indexWhere((form) => form.controller == _textControllers.last);
              if (index != -1) {
                _boxPositions[index] = newPosition;
              }
            });
          },
          onEmptyDelete: () {
            setState(() {
              int index = _textForms.indexWhere((form) => form.controller == _textControllers.last);
              if (index != -1) {
                _boxPositions.removeAt(index);
                _textControllers.removeAt(index);
                _focusNodes.removeAt(index); // Remove the corresponding focus node
                _textForms.removeAt(index);
              }
            });
          },
          onDragStart: _unfocusAllTextFields,
        ));
        // Request focus after adding to the list to avoid issues with focus jumping
        WidgetsBinding.instance.addPostFrameCallback((_) {
          newFocusNode.requestFocus();
        });
      });
    } else {
      // Find the index of the tapped text box and request focus for it
      int index = _boxPositions.indexWhere((position) {
        double width = _textForms[_boxPositions.indexOf(position)].initialWidth;
        return (canvasTapPosition.dx >= position.dx &&
            canvasTapPosition.dx <= position.dx + width &&
            canvasTapPosition.dy >= position.dy &&
            canvasTapPosition.dy <= position.dy + (_focusNodes[_boxPositions.indexOf(position)].hasFocus ? 47 : 22)); // Adjust height based on focus
      });
      if (index != -1) {
        _focusNodes[index].requestFocus();
      }
    }
  }

  void _unfocusAllTextFields() {
    for (var focusNode in _focusNodes) {
      focusNode.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Canvas App'),
      ),
      body: InteractiveViewer(
        constrained: false,
        boundaryMargin: const EdgeInsets.all(100), // amount of empty space around the canvas
        transformationController: _transformationController,
        child: SizedBox(
          width: _canvasSize.width,
          height: _canvasSize.height,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: _handleTapDown,
            child: Stack(
              children: [
                Container(
                  width: _canvasSize.width,
                  height: _canvasSize.height,
                  color: Colors.grey[300],
                  child: CustomPaint(
                    size: _canvasSize,
                    painter: GridPainter(),
                  ),
                ),
                ..._textForms,
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Updates the canvas size.
  void updateCanvasSize(Size newSize) {
    setState(() {
      _canvasSize = newSize;
    });
  }
}

/// A custom painter to draw a grid on the canvas.
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
