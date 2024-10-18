import 'package:flutter/material.dart';
import 'draggable_text_field.dart';
import 'canvas_grid_painter.dart'; // Moved GridPainter to a separate file

void main() {
  runApp(const MyApp());
}

/// The root widget of the application.
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

/// A stateful widget representing the canvas page.
class CanvasPage extends StatefulWidget {
  const CanvasPage({super.key});

  @override
  State<CanvasPage> createState() => _CanvasPageState();
}

class _CanvasPageState extends State<CanvasPage> {
  final List<DraggableTextField> _textFields = []; // Simplified to store only DraggableTextField widgets
  Size _canvasSize = const Size(800, 600);
  final TransformationController _transformationController = TransformationController();
  double sideWidth = 40;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeCanvasSize();
      _positionCanvasTopLeft();
    });
  }

  /// Initializes the canvas size based on the screen size.
  void _initializeCanvasSize() {
    final Size screenSize = MediaQuery.of(context).size;
    setState(() {
      _canvasSize = Size(screenSize.width * 2, screenSize.height * 2);
    });
  }

  /// Positions the canvas so its top-left corner is at the top-left of the screen.
  void _positionCanvasTopLeft() {
    // This might throw an exception if called before the InteractiveViewer is built.
    // We wrap it in a try-catch to handle this gracefully.
    try {
      _transformationController.value = Matrix4.identity()..translate(100, 100);
    } catch (e) {
      // Ignore the exception if it occurs.
    }
  }

  /// Handles tap down events to add or focus text fields.
  void _handleTapDown(TapDownDetails details) {
    Offset canvasTapPosition = details.localPosition;

    // Check if the tap is on an existing text field.
    int tappedTextFieldIndex = _getTappedTextFieldIndex(canvasTapPosition);

    if (tappedTextFieldIndex == -1) {
      // Add a new text field if the tap is not on an existing one.
      _addNewTextField(canvasTapPosition);
    } else {
      // Focus the tapped text field.
      _textFields[tappedTextFieldIndex].focusNode.requestFocus();
    }
  }

  /// Adds a new draggable text field to the canvas.
  void _addNewTextField(Offset position) {
    FocusNode newFocusNode = FocusNode();

    setState(() {
      _textFields.add(DraggableTextField(
        initialPosition: position - const Offset(10, 50), // Adjust for drag bar and text padding
        initialWidth: 200,
        onDragEnd: (newPosition) {
          setState(() {
            int index = _textFields.indexOf(_textFields.last);
            _textFields[index].position = newPosition;
          });
        },
        onEmptyDelete: () {
          setState(() {
            _textFields.removeLast();
          });
        },
        onDragStart: _unfocusAllTextFields,
        focusNode: newFocusNode,
      ));

      // Request focus after the text field is added to the widget tree.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        newFocusNode.requestFocus();
      });
    });
  }

  /// Returns the index of the tapped text field, or -1 if no text field was tapped.
  int _getTappedTextFieldIndex(Offset tapPosition) {
    for (int i = 0; i < _textFields.length; i++) {
      final textField = _textFields[i];
      final position = textField.position;
      final width = textField.width;
      final height = textField.focusNode.hasFocus ? 47 : 22; // Adjust height based on focus

      if (tapPosition.dx >= position.dx && tapPosition.dx <= position.dx + width && tapPosition.dy >= position.dy && tapPosition.dy <= position.dy + height) {
        return i;
      }
    }
    return -1;
  }

  /// Unfocuses all text fields on the canvas.
  void _unfocusAllTextFields() {
    for (var textField in _textFields) {
      textField.focusNode.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Column(
          children: [
            Text('Canvas App'),
            Wrap(
              spacing: 10,
              alignment: WrapAlignment.start,
              children: [
                Text("File"),
                Text("Home"),
                Text("Insert"),
              ],
            )
          ],
        ),
      ),
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 50),
            color: Colors.grey[900],
            width: sideWidth,
            height: double.infinity,
            alignment: Alignment.topLeft,
            child: Column(
              children: [
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    setState(() {
                      if (sideWidth == 40) {
                        sideWidth = 200;
                      } else {
                        sideWidth = 40;
                      }
                    });
                  },
                ),
                ListView.builder(
                  itemCount: sideWidth > 40 ? 5 : 0,
                  shrinkWrap: true,
                  itemBuilder: (BuildContext context, int index) {
                    return ListTile(
                      title: Text("Item", style: TextStyle(color: Colors.white)),
                    );
                  },
                )
              ],
            ),
          ),
          Expanded(
            child: InteractiveViewer(
              constrained: false,
              boundaryMargin: const EdgeInsets.all(100),
              transformationController: _transformationController,
              child: SizedBox(
                width: _canvasSize.width,
                height: _canvasSize.height,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapDown: _handleTapDown,
                  child: Stack(
                    children: [
                      // Background grid
                      Container(
                        width: _canvasSize.width,
                        height: _canvasSize.height,
                        color: Colors.grey[850],
                        child: CustomPaint(
                          size: _canvasSize,
                          painter: CanvasGridPainter(), // Using the new CanvasGridPainter
                        ),
                      ),
                      // Draggable text fields
                      ..._textFields,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
