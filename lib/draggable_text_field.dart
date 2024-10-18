import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_quill/flutter_quill.dart';

class DraggableTextField extends StatefulWidget {
  final Offset initialPosition;
  final double initialWidth;
  final Function(Offset) onDragEnd;
  final Function onEmptyDelete;
  final Function onDragStart;
  final FocusNode focusNode;

  Offset position;
  double width;
  late QuillController controller;

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
        controller = QuillController.basic(),
        super(key: key);

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
    final document = Document.fromJson(jsonDecode(json['document']));
    final focusNode = FocusNode();
    final controller = QuillController(document: document, selection: TextSelection.collapsed(offset: 0));

    return DraggableTextField(
      initialPosition: position,
      initialWidth: width,
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

    widget.controller.addListener(() {
      setState(() {
        isVisible = widget.focusNode.hasFocus && !widget.controller.document.isEmpty();
      });
    });

    widget.focusNode.addListener(() {
      if (!widget.focusNode.hasFocus && widget.controller.document.isEmpty()) {
        widget.onEmptyDelete();
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
                Container(
                  constraints: const BoxConstraints(minWidth: 200, maxWidth: 600),
                  decoration: BoxDecoration(
                    border: Border.all(color: isVisible ? Colors.black : Colors.transparent),
                  ),
                  child: QuillEditor.basic(
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