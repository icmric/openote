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
    // Calculate offset to adjust for header height
    double headerHeight = isVisible ? 25.0 : 0.0;

    return Positioned(
      left: position.dx,
      top: position.dy - headerHeight, // Adjust position based on header
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
            // Header - only visible when focused and text is not empty
            if (isVisible)
              Container(
                width: width,
                height: 25,
                color: Colors.grey,
                alignment: Alignment.topCenter, // Align text to the top
                child: const FittedBox(
                  // Use FittedBox to prevent text overflow
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '...',
                    style: TextStyle(color: Colors.white, fontSize: 20),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            SizedBox(
              width: width,
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode, // Assign the focus node
                autofocus: true,
                minLines: 1,
                maxLines: null,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0), // Add padding to adjust cursor position correctly
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
                      width = (textPainter.width + 24).clamp(200.0, 800.0);
                    } else {
                      width = widget.initialWidth;
                      isVisible = false; // Hide header and border when text is empty
                    }
                  });
                },
                onTapOutside: (PointerDownEvent event) {
                  if (widget.controller.text.isEmpty) {
                    widget.onEmptyDelete();
                  } else {
                    widget.focusNode.unfocus(); // Unfocus when clicking outside
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
