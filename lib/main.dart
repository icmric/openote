import 'package:flutter/material.dart';
import 'draggable_text_field.dart';

void main() {
  runApp(const MyApp());
}

// The main application widget.
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

// A stateful widget representing the canvas page where draggable text fields can be added.
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
  final TransformationController _transformationController =
      TransformationController();

  // Handles tap down events to add a new draggable text field 
  // if the tap is not on an existing box.
  void _handleTapDown(TapDownDetails details) {
    Offset canvasTapPosition = details.localPosition;
    bool isOnExistingBox = _boxPositions.any((position) {
      int index = _boxPositions.indexOf(position);
      double width = _textForms[index].initialWidth;
      // Check if tap is within the bounds of an existing box, including the header
      return (canvasTapPosition.dx >= position.dx &&
          canvasTapPosition.dx <= position.dx + width &&
          canvasTapPosition.dy >= position.dy &&
          canvasTapPosition.dy <=
              position.dy +
                  (_focusNodes[index].hasFocus ? 47 : 22)); // Adjust height based on focus
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
          focusNode: newFocusNode, // Assign the focus node to the text field
          initialPosition: canvasTapPosition,
          initialWidth: 200,
          onDragEnd: (newPosition) {
            setState(() {
              int index = _textForms
                  .indexWhere((form) => form.controller == _textControllers.last);
              if (index != -1) {
                _boxPositions[index] = newPosition;
              }
            });
          },
          onEmptyDelete: () {
            setState(() {
              int index = _textForms
                  .indexWhere((form) => form.controller == _textControllers.last);
              if (index != -1) {
                _boxPositions.removeAt(index);
                _textControllers.removeAt(index);
                _focusNodes.removeAt(index); // Remove the corresponding focus node
                _textForms.removeAt(index);
                /*
                // If there are other text boxes, request focus for the last one
                if (_textForms.isNotEmpty) {
                  _focusNodes.last.requestFocus();
                } else {
                  // If no other text boxes, create a new one at the last tap position
                  _handleTapDown(TapDownDetails(
                      globalPosition: details.globalPosition,
                      localPosition: details.localPosition));
                }*/
              }
            });
          },
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
            canvasTapPosition.dy <=
                position.dy +
                    (_focusNodes[_boxPositions.indexOf(position)].hasFocus
                        ? 47
                        : 22)); // Adjust height based on focus
      });
      if (index != -1) {
        _focusNodes[index].requestFocus();
      }
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
        boundaryMargin: const EdgeInsets.all(double.infinity),
        transformationController: _transformationController,
        child: SizedBox(
          width: _canvasSize.width,
          height: _canvasSize.height,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTap: () {
              updateCanvasSize(const Size(2000, 800));
            },
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

  // Updates the canvas size.
  void updateCanvasSize(Size newSize) {
    setState(() {
      _canvasSize = newSize;
    });
  }
}

// A custom painter to draw a grid on the canvas.
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