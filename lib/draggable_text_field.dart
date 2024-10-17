import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// A draggable text field widget.
class DraggableTextField extends StatefulWidget {
  final Offset initialPosition;
  final double initialWidth;
  final Function(Offset) onDragEnd;
  final Function onEmptyDelete;
  final Function onDragStart;
  final FocusNode focusNode;

  Offset position; // Make position public
  double width; // Make width public

  DraggableTextField({
    required this.initialPosition,
    required this.initialWidth,
    required this.onDragEnd,
    required this.onEmptyDelete,
    required this.onDragStart,
    required this.focusNode,
    Key? key,
  })  : position = initialPosition,
        width = initialWidth,
        super(key: key);

  @override
  _DraggableTextFieldState createState() => _DraggableTextFieldState();
}

class _DraggableTextFieldState extends State<DraggableTextField> {
  bool isVisible = false; // Track visibility of the drag handle
  bool isDragging = false; // Track if the text field is being dragged
  late TextEditingController _controller;
  bool _isEditing = true; // Flag to track if the text field is being edited

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();

    // Add listener to show/hide header based on focus and text content.
    widget.focusNode.addListener(() {
      setState(() {
        isVisible = widget.focusNode.hasFocus && _controller.text.isNotEmpty;
      });
    });

    // Add listener to delete the text field when it loses focus and is empty.
    widget.focusNode.addListener(() {
      if (!widget.focusNode.hasFocus && _controller.text.isEmpty) {
        widget.onEmptyDelete();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose(); // Dispose the controller when the widget is disposed
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.position.dx,
      top: widget.position.dy,
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
            widget.onDragStart();
            setState(() {
              isDragging = true;
            });
          },
          onPanUpdate: (details) {
            setState(() {
              widget.position += details.delta;
            });
          },
          onPanEnd: (details) {
            setState(() {
              isDragging = false;
            });
            widget.onDragEnd(widget.position);
          },
          child: Column(
            children: [
              // Drag handle
              Container(
                width: widget.width,
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
              Container(
                width: widget.width,
                decoration: BoxDecoration(
                  border: Border.all(color: isVisible ? Colors.black : Colors.transparent),
                ),
                child: _isEditing
                    ? TextField(
                        controller: _controller,
                        focusNode: widget.focusNode,
                        autofocus: true,
                        minLines: 1,
                        maxLines: null,
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.all(5),
                          border: InputBorder.none,
                        ),
                        onChanged: (text) {
                          setState(() {
                            if (text.isNotEmpty) {
                              isVisible = true;

                              // Calculate width based on the regular text
                              TextPainter textPainter = TextPainter(
                                text: TextSpan(text: text, style: const TextStyle(fontSize: 16)),
                                textDirection: TextDirection.ltr,
                                maxLines: 1,
                              )..layout();
                              widget.width = (textPainter.width + 80).clamp(200.0, 600.0);
                            } else {
                              isVisible = false;
                            }
                          });
                        },
                        onTapOutside: (PointerDownEvent event) {
                          if (_controller.text.isEmpty) {
                            // Also being done in initState, but seems to break without this?
                            widget.onEmptyDelete();
                          } else {
                            setState(() {
                              _isEditing = false; // Switch to Markdown rendering
                            });
                            widget.focusNode.unfocus();
                          }
                        },
                      )
                    : GestureDetector(
                        child: Markdown(
                          data: _controller.text, // Display Markdown when not editing
                          selectable: true,
                          onTapLink: (text, href, title) {
                            // Handle link taps if needed
                          },
                          shrinkWrap: true,
                          styleSheet: MarkdownStyleSheet(
                            p: const TextStyle(fontSize: 16),
                            h1: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                            // ... other styles
                          ),
                        ),
                        onTap: () {
                          setState(() {
                            _isEditing = true; // Switch back to editing
                          });
                          widget.focusNode.requestFocus();
                        },
                      ),
              ),

              /*TextField(
                  controller: _controller,
                  focusNode: widget.focusNode,
                  autofocus: true,
                  minLines: 1,
                  maxLines: null,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.all(5),
                    border: isVisible ? const OutlineInputBorder() : InputBorder.none,
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
                        widget.width = (textPainter.width + 80).clamp(200.0, 600.0);
                      } else {
                        isVisible = false;
                      }
                    });
                  },
                  onTapOutside: (PointerDownEvent event) {
                    if (_controller.text.isEmpty) {
                      widget.onEmptyDelete();
                    } else {
                      widget.focusNode.unfocus();
                    }
                  },
                ),
              ),*/
            ],
          ),
        ),
      ),
    );
  }
}
