import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fleather/fleather.dart';

class DraggableTextField extends StatefulWidget {
  final Offset initialPosition;
  final double maxWidth;
  final Function(Offset) onDragEnd;
  final Function onEmptyDelete;
  final Function onDragStart;
  final FocusNode focusNode;

  Offset position;
  double width;
  FleatherController controller = FleatherController();

  DraggableTextField({
    required this.initialPosition,
    required this.maxWidth,
    required this.onDragEnd,
    required this.onEmptyDelete,
    required this.onDragStart,
    required this.focusNode,
    super.key,
  })  : position = initialPosition,
        width = maxWidth;

  @override
  _DraggableTextFieldState createState() => _DraggableTextFieldState();

  Map<String, dynamic> toJson() {
    return {
      'position': {'dx': position.dx, 'dy': position.dy},
      'width': width,
      'document': jsonEncode(controller.document.toDelta().toJson()),
    };
  }

  static DraggableTextField fromJson(
    Map<String, dynamic> json,
    Function(Offset) onDragEnd,
    Function onEmptyDelete,
    Function onDragStart,
  ) {
    final position = Offset(json['position']['dx'], json['position']['dy']);
    final width = json['width'];
    final document = ParchmentDocument.fromJson(jsonDecode(json['document']));

    final focusNode = FocusNode();
    final controller = FleatherController(document: document);

    return DraggableTextField(
      initialPosition: position,
      maxWidth: width,
      onDragEnd: onDragEnd,
      onEmptyDelete: onEmptyDelete,
      onDragStart: onDragStart,
      focusNode: focusNode,
    )..controller = controller;
  }
}

class _DraggableTextFieldState extends State<DraggableTextField> {
  bool isVisible = false;
  bool isDragging = false;

  @override
  void initState() {
    super.initState();

    if (widget.maxWidth < 200) {
      widget.width = 200;
    }

    widget.controller.addListener(() {
      setState(() {
        isVisible = widget.focusNode.hasFocus && widget.controller.document.length >= 2;
      });
    });
    
    widget.focusNode.addListener(() {
      if (!widget.focusNode.hasFocus) {
        setState(() {
          isVisible = false;
        });
      }
    });

    widget.focusNode.addListener(() {
      if (!widget.focusNode.hasFocus && widget.controller.document.length < 2) {
        setState(() {
          widget.onEmptyDelete();
        });
      }
    });
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.position.dx,
      top: widget.position.dy,
      // Makes box visible/invisible when mousing over
      child: MouseRegion(
        // Mouse starts hovering over the box
        onEnter: (_) {
          // If the box is not empty, make it visible, otherwise just show cursor
          if (widget.controller.document.length >= 2) {
            setState(() {
              isVisible = true;
            });
          }
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
                //FleatherToolbar.basic(controller: widget.controller),
                Container(
                  constraints: BoxConstraints(minWidth: 200, maxWidth: widget.width),
                  decoration: BoxDecoration(
                    border: Border.all(color: isVisible ? Colors.black : Colors.transparent),
                  ),
                  child: FleatherEditor(
                    focusNode: widget.focusNode,
                    controller: widget.controller,
                    autofocus: true,
                  ),

                  /* QuillEditor.basic(
                    focusNode: widget.focusNode,
                    controller: widget.controller,
                    configurations: QuillEditorConfigurations(
                      padding: const EdgeInsets.all(10),
                      showCursor: true,
                      autoFocus: true,
                      onTapOutside: (PointerDownEvent event, FocusNode node) {
                        if (widget.controller.document.isEmpty()) {
                          widget.onEmptyDelete();
                        } else {
                          widget.focusNode.unfocus();
                          setState(() {
                            isVisible = false;
                          });
                        }
                      },
                    ),
                  ),*/
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
