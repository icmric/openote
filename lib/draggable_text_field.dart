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
  final Function onDragStart; // Callback to notify when dragging starts

  const DraggableTextField({
    required this.controller,
    required this.focusNode,
    required this.initialPosition,
    required this.onDragEnd,
    required this.initialWidth,
    required this.onEmptyDelete,
    required this.onDragStart, // Add the new callback parameter
    Key? key,
  }) : super(key: key);

  @override
  _DraggableTextFieldState createState() => _DraggableTextFieldState();
}

class _DraggableTextFieldState extends State<DraggableTextField> {
  late Offset position;
  late double width;
  bool isVisible = false; // Track visibility of the text box and header
  bool isDragging = false; // Track if the text field is being dragged

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
      child: MouseRegion(
        onEnter: (_) {
          setState(() {
            isVisible = true;
          });
        },
        onExit: (_) {
          if (!widget.focusNode.hasFocus) {
            setState(() {
              isVisible = false;
            });
          }
        },
        child: GestureDetector(
          onPanStart: (_) {
            widget.onDragStart(); // Unfocus all text fields when dragging
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
            widget.onDragEnd(position);
          },
          child: Column(
            children: [
              // Drag handle
              Container(
                width: width,
                height: 15,
                padding: const EdgeInsets.all(0),
                color: isVisible ? Colors.grey : Colors.transparent,
                alignment: Alignment.center,
                child: isVisible
                    ? const Text(
                        '...',
                        strutStyle: StrutStyle(
                          forceStrutHeight: true,
                          height: 0.5, // Aligns dots correctly in container
                        ),
                        style: TextStyle(color: Colors.white, fontSize: 15),
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
      ),
    );
  }
}
