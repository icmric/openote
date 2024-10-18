import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

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
  QuillController _controller = QuillController.basic();
  double _currentWidth = 200.0;

  @override
  void initState() {
    super.initState();
    _controller = QuillController.basic();

    // Add listener to show/hide header based on focus and text content.
    _controller.addListener(() {
      setState(() {
        isVisible = widget.focusNode.hasFocus && !_controller.document.isEmpty();
      });
    });

    // Add listener to delete the text field when it loses focus and is empty.
    widget.focusNode.addListener(() {
      if (!widget.focusNode.hasFocus && _controller.document.isEmpty()) {
        widget.onEmptyDelete();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
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
          child: IntrinsicWidth(
            child: Column(
              children: [
                // QuillSimpleToolbar(
                //   controller: _controller,
                //   configurations: QuillSimpleToolbarConfigurations(),
                // ),
                // Drag handle
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
                            height: 0.1, // Aligns dots correctly in container
                          ),
                          style: TextStyle(color: Colors.white, fontSize: 15),
                        )
                      : null,
                ),
                // Text field
                Container(
                  constraints: const BoxConstraints(minWidth: 200, maxWidth: 600),
                  decoration: BoxDecoration(
                    border: Border.all(color: isVisible ? Colors.black : Colors.transparent),
                  ),
                  child: QuillEditor.basic(
                    controller: _controller,
                    focusNode: widget.focusNode,
                    configurations: QuillEditorConfigurations(
                      padding: EdgeInsets.all(10),
                      showCursor: true,
                      autoFocus: true,
                      onTapOutside: (PointerDownEvent event, FocusNode node) {
                        if (_controller.document.isEmpty()) {
                          widget.onEmptyDelete();
                        } else {
                          widget.focusNode.unfocus();
                          setState(() {
                            isVisible = false;
                          });
                        }
                      },
                    ),
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
