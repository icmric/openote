import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

// *** NOT IMPLEMENTED YET ***

/// Represents a draggable text field on the canvas.
/// Users can drag, resize, and edit the text within these fields.
class DraggableContentField extends StatefulWidget {
  final Offset initialPosition; // Initial position of the text field.
  final double maxWidth; // Maximum width of the text field.
  final FocusNode focusNode; // FocusNode for managing focus.
  final List<Widget>? content; // Optional passed content

  const DraggableContentField({
    required this.initialPosition,
    required this.maxWidth,
    required this.focusNode,
    this.content,
    super.key,
  });

  @override
  DraggableContentFieldState createState() => DraggableContentFieldState();
}

class DraggableContentFieldState extends State<DraggableContentField> {
  bool isVisible = false; // Whether the text field border and toolbar are visible.
  bool isDragging = false; // Whether the text field is currently being dragged.
  double maxWidth = 200; // Current width of the text field.
  Offset position = Offset(0, 0); // Current position of the text field.
  late List<Widget> content;

  @override
  void initState() {
    super.initState();

    content = widget.content ?? [];
    maxWidth = widget.maxWidth;
    position = widget.initialPosition;
  }

  @override
  void dispose() {
    //widget.controller.dispose(); // Dispose of the QuillController when the widget is disposed.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      // Makes box visible/invisible when mousing over
      child: MouseRegion(
        // Mouse starts hovering over the box
        onEnter: (_) {
          // If the box is not empty, make it visible, otherwise just show cursor
          setState(() {
            isVisible = true;
          });
        },
        // Mouse stops hovering over the box
        onExit: (_) {
          // If the box is not focused, make it invisible
          if (!widget.focusNode.hasFocus && !isDragging) {
            setState(() {
              isVisible = false;
            });
          }
        },
        child: GestureDetector(
          onPanStart: (_) {
            // On Drag Start
            setState(() {
              isDragging = true;
            });
          },
          onPanUpdate: (details) {
            setState(() {
              position += details.delta;
            });
          },
          onPanEnd: (details) {
            setState(() {
              isDragging = false;
            });
            // On Drag End
          },
          child: IntrinsicWidth(
            child: Column(
              children: [
                // Bar ontop of the field used to drag the field around
                Container(
                  height: 15,
                  padding: const EdgeInsets.all(0),
                  color: isVisible ? Colors.grey : Colors.transparent,
                  alignment: Alignment.center,
                  child: isVisible
                      ? const Text(
                          '...',
                          strutStyle: StrutStyle(
                            forceStrutHeight: true,
                            height: 0.1,
                          ),
                          style: TextStyle(color: Colors.white, fontSize: 15),
                        )
                      : null,
                ),
                // The main body of the content field
                Container(
                  // Contraints allow for dynamic resizing
                  constraints: BoxConstraints(minWidth: 200, maxWidth: maxWidth),
                  // Content field border
                  decoration: BoxDecoration(
                    border: Border.all(color: isVisible ? Colors.black : Colors.transparent),
                  ),
                  child: Column(
                    children: [...content],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
