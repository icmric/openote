import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'draggable_content_field.dart';

/// A widget that provides a scrollable and zoomable canvas area.
/// Implements alt-key based switching between scroll and zoom modes.
class CanvasArea extends StatefulWidget {
  /// The child widget to be displayed within the canvas area
  final Widget child;

  const CanvasArea({
    super.key,
    required this.child,
  });

  @override
  State<CanvasArea> createState() => _CanvasAreaState();
}

class _CanvasAreaState extends State<CanvasArea> {
  // Controllers for handling vertical and horizontal scrolling
  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();

  // Controller for handling zoom and pan transformations
  final TransformationController _controller = TransformationController();

  // Tracks whether Alt key is currently pressed
  bool _isCtrlPressed = false;

  // Focusnode for canvas to regain focus
  FocusNode focusNode = FocusNode();

  // Draggable fields for content on the canvas
  // TODO remove from here??
  List<DraggableContentField> contentFields = [];

  @override
  void initState() {
    super.initState();
    // Register the keyboard event handler when widget initializes
    focusNode.requestFocus();
  }

  @override
  void dispose() {
    // Clean up resources when widget is disposed
    _verticalController.dispose();
    _horizontalController.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Handles keyboard events for Alt key detection
  /// Always returns false, updates local variable instead
  void _onKey(KeyEvent event) {
    final keyPressed = event.logicalKey.keyLabel;

    // If the pressed key is control, continue, otherwise ignore it
    if (keyPressed == 'Control Left' || keyPressed == 'Control Right') {
      // If control is being pressed, set the value to true
      if (event is KeyDownEvent) {
        _isCtrlPressed = true;
      }
      // If is being released, set it to false
      if (event is KeyUpEvent) {
        // Handle Alt key release
        _isCtrlPressed = false;
      }
      // setState to reflect changes in SingleChildScrollViews and InteractiveViewer
      setState(() {});
    }
  }

  void addNewContentField(Offset position) {
    FocusNode focusNode = FocusNode();
    contentFields.add(DraggableContentField(
      initialPosition: position,
      maxWidth: 800,
      focusNode: FocusNode(),
      content: [
        //Image.network('https://media.tenor.com/DOJSd6eNukMAAAAM/so-you%27re-telling-me-telling-me.gif'),
        Container(
          color: Colors.white,
          child: QuillEditor.basic(
            focusNode: focusNode,
            controller: QuillController.basic(),
          ),
        ),
      ],
    ));
    // Request focus for QuillEditor. Remove in the future or find better way of doing it as this will not always be a QuillEditor
    setState(() {
      focusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return KeyboardListener(
          focusNode: focusNode,
          onKeyEvent: (value) {
            _onKey(value);
          },
          child: Scrollbar(
            // Vertical scrollbar configuration
            thickness: 8.0,
            controller: _verticalController,
            scrollbarOrientation: ScrollbarOrientation.right,
            child: Scrollbar(
              // Horizontal scrollbar configuration
              thickness: 8.0,
              controller: _horizontalController,
              scrollbarOrientation: ScrollbarOrientation.bottom,
              // Ensure scrollbar responds to the correct scroll view
              notificationPredicate: (ScrollNotification notif) => notif.depth == 1,
              child: SingleChildScrollView(
                // Vertical scroll view
                controller: _verticalController,
                // Disable scrolling when Ctrl is pressed (zoom mode)
                physics: _isCtrlPressed ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
                child: SingleChildScrollView(
                  // Horizontal scroll view
                  primary: false,
                  controller: _horizontalController,
                  scrollDirection: Axis.horizontal,
                  // Disable scrolling when Ctrl is pressed (zoom mode)
                  physics: _isCtrlPressed ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
                  child: InteractiveViewer(
                    // Enable zooming only when Ctrl is pressed
                    scaleEnabled: _isCtrlPressed,
                    // Disable panning. Make avalible when using touch input?
                    panEnabled: false,
                    alignment: Alignment.topLeft,
                    // Zoom out limit
                    minScale: 0.1,
                    // Zoom in limit
                    maxScale: 4.0,
                    // Margin around the canvas, visible when zoomed out (if not zero)
                    boundaryMargin: const EdgeInsets.all(0),
                    // Gesture Detector to handle taps for adding new content fields
                    child: GestureDetector(
                      // Handle tap events for position detection
                      onTapDown: (gestureDetails) {
                        // TODO: Allow this to call a function passed to it?
                        addNewContentField(gestureDetails.localPosition);
                      },
                      // Displays the canvas area (widget.child) and draggable content fields on top
                      child: Stack(
                        children: [
                          widget.child,
                          ...contentFields,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
