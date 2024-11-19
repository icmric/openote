import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:provider/provider.dart';
import '../../controllers/canvas_controller.dart';

/// Represents a draggable text field on the canvas.
/// Users can drag, resize, and edit the text within these fields.
// ignore: must_be_immutable
class DraggableTextField extends StatefulWidget {
  final Offset initialPosition; // Initial position of the text field.
  final double maxWidth; // Maximum width of the text field.
  final Function(Offset) onDragEnd; // Callback when dragging ends.
  final Function onEmptyDelete; // Callback when the text field is empty and the delete key is pressed.
  final Function onDragStart; // Callback when dragging starts.
  final FocusNode focusNode; // FocusNode for managing focus.
  final QuillController controller; // Now passed as a parameter

  Offset position; // Current position of the text field.
  double width; // Current width of the text field.

  DraggableTextField({
    required this.initialPosition,
    required this.maxWidth,
    required this.onDragEnd,
    required this.onEmptyDelete,
    required this.onDragStart,
    required this.focusNode,
    required this.controller,
    super.key,
  })  : position = initialPosition,
        width = maxWidth;

  @override
  DraggableTextFieldState createState() => DraggableTextFieldState();

  /// Converts the DraggableTextField object to a JSON map for saving.
  Map<String, dynamic> toJson() {
    return {
      'position': {'dx': position.dx, 'dy': position.dy},
      'width': width,
      'document': jsonEncode(controller.document.toDelta().toJson()), // Encode the Quill document as JSON.
    };
  }

  /// Creates a DraggableTextField object from a JSON map loaded from a file.
  factory DraggableTextField.fromJson(
    Map<String, dynamic> json,
    Function(Offset) onDragEnd,
    Function onEmptyDelete,
    Function onDragStart,
  ) {
    final position = Offset(json['position']['dx'], json['position']['dy']);
    final width = json['width'];
    final document = Document.fromJson(jsonDecode(json['document'])); // Decode the JSON document.
    final focusNode = FocusNode();
    final controller = QuillController(document: document, selection: const TextSelection.collapsed(offset: 0)); // Initialize QuillController.
    return DraggableTextField(
      initialPosition: position,
      maxWidth: width,
      onDragEnd: onDragEnd,
      onEmptyDelete: onEmptyDelete,
      onDragStart: onDragStart,
      focusNode: focusNode,
      controller: controller,
    ); // Assign the created controller.
  }
}

class DraggableTextFieldState extends State<DraggableTextField> {
  bool isVisible = false; // Whether the text field border and toolbar are visible.
  bool isDragging = false; // Whether the text field is currently being dragged.

  @override
  void initState() {
    super.initState();

    // Ensure minimum width.
    if (widget.maxWidth < 200) {
      widget.width = 200;
    }

    // Listen for changes in the Quill controller to update visibility.
    widget.controller.addListener(() {
      setState(() {
        isVisible = widget.focusNode.hasFocus && !widget.controller.document.isEmpty();
      });
    });

    // Makes sure toolbar is always linked to currently selected textField
    widget.focusNode.addListener(_handleFocusChange);

    // Listen for focus changes to delete the text field if it's empty and loses focus.
    widget.focusNode.addListener(() {
      if (!widget.focusNode.hasFocus && widget.controller.document.isEmpty() && !_isLosingFocusToAlertDialog()) {
        widget.onEmptyDelete();
      }
    });
  }

  @override
  void dispose() {
    widget.controller.dispose(); // Dispose of the QuillController when the widget is disposed.
    widget.focusNode.removeListener(_handleFocusChange); // Remove the listener
    super.dispose();
  }

  void _handleFocusChange() {
    if (widget.focusNode.hasFocus) {
      Provider.of<CanvasController>(context, listen: false).setActiveTextFieldController(widget.controller);
    } else {
      Provider.of<CanvasController>(context, listen: false).setActiveTextFieldController(null);
    }
  }

  bool _isLosingFocusToAlertDialog() {
    // If focus is being lost to an alert dialog, return true, otherwise return false
    final focusManager = FocusManager.instance;
    final primaryFocus = focusManager.primaryFocus;
    if (primaryFocus != null && primaryFocus.context != null) {
      final context = primaryFocus.context!;
      final route = ModalRoute.of(context);

      // Using DialogRoute<dynamic> will match any DialogRoute regardless of type parameter
      return route is DialogRoute<dynamic>;
    }
    return false;
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
          if (!widget.controller.document.isEmpty()) {
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
                // The Quill editor for text input.
                Container(
                  constraints: BoxConstraints(minWidth: 200, maxWidth: widget.width),
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
                        // Checks if tap is on the canvas and is not losing focus to an AlertDialog
                        if (_isTapWithinCanvas(event.localPosition) && !_isLosingFocusToAlertDialog()) {
                          // Checks if the text field is empty
                          if (widget.controller.document.isEmpty()) {
                            widget.onEmptyDelete();
                            // if it isnt, then just unfocus and hide decoration
                          } else {
                            widget.focusNode.unfocus();
                            setState(() {
                              isVisible = false;
                            });
                          }
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

  bool _isTapWithinCanvas(Offset localPosition) {
    // 1. Get the RenderBox of the CanvasArea widget
    final canvasAreaRenderBox = context.findAncestorRenderObjectOfType<RenderBox>() as RenderBox;

    // 2. Get the global offset of the CanvasArea
    final canvasAreaGlobalOffset = canvasAreaRenderBox.localToGlobal(Offset.zero);

    // 3. Calculate the tap position relative to the CanvasArea
    final tapPositionInCanvas = localPosition - canvasAreaGlobalOffset;

    // 4. Check if the tap position is within the CanvasArea's size
    return tapPositionInCanvas.dx >= 0 && tapPositionInCanvas.dy >= 0 && tapPositionInCanvas.dx <= canvasAreaRenderBox.size.width && tapPositionInCanvas.dy <= canvasAreaRenderBox.size.height;
  }
}
