import 'package:flutter/material.dart';

/// A draggable text field widget that can be moved around the screen.
/// The text field's width adjusts dynamically based on its content.
class DraggableTextField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Offset initialPosition;
  final Function(Offset) onDragEnd;
  final double initialWidth;
  final Function onEmptyDelete; // Callback to notify when the text box should be deleted

  const DraggableTextField({
    required this.controller,
    required this.focusNode,
    required this.initialPosition,
    required this.onDragEnd,
    required this.initialWidth,
    required this.onEmptyDelete,
    Key? key,
  }) : super(key: key);

  @override
  _DraggableTextFieldState createState() => _DraggableTextFieldState();
}

class _DraggableTextFieldState extends State<DraggableTextField> {
  late Offset position;
  late double width;
  bool isVisible = false; // Track visibility of the text box and header

  @override
  void initState() {
    super.initState();
    position = widget.initialPosition;
    width = widget.initialWidth;

    // Add listener to show/hide header based on focus
    widget.focusNode.addListener(() {
      setState(() {
        isVisible = widget.focusNode.hasFocus && widget.controller.text.isNotEmpty;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            position += details.delta;
          });
        },
        onPanEnd: (details) {
          widget.onDragEnd(position);
        },
        child: Column(
          children: [
            // Draggable handle
            //if (isVisible)
            Container(
              width: width,
              height: 25,
              color: isVisible ? Colors.grey : Colors.transparent,
              alignment: Alignment.center,
              child: isVisible
                  ? const Text(
                      '...',
                      style: TextStyle(color: Colors.white, fontSize: 20),
                    )
                  : null,
            ),
            // Text field
            SizedBox(
              width: width,
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                autofocus: true,
                minLines: 1,
                maxLines: null,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.all(5), // Text padding
                  border: isVisible ? const OutlineInputBorder() : InputBorder.none, // Show border only when focused and text is not empty
                ),
                onChanged: (text) {
                  setState(() {
                    if (text.isNotEmpty) {
                      isVisible = true;
                      TextPainter textPainter = TextPainter(
                        text: TextSpan(text: text, style: const TextStyle(fontSize: 16)),
                        textDirection: TextDirection.ltr,
                        maxLines: 1,
                      )..layout();
                      width = (textPainter.width + 80).clamp(200.0, 600.0);
                    } else {
                      isVisible = false;
                    }
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
