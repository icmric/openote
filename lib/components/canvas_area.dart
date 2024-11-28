import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'canvas_controller.dart';
import 'draggable_content_field.dart';

/// A widget that provides a scrollable and zoomable canvas area.
/// NOTE: This widget is not yet fully implemented and may not work as expected.
/// Trackpad and touch input is not yet fully supported.
///
/// Scrollwheel to scroll vertically
///
/// Scrollwheel + Shift to scroll horizontally
///
/// Scrollwheel + Ctrl to zoom in and out
class CanvasArea extends StatefulWidget {
  /// The child widget to be displayed within the canvas area
  final Widget child;

  /// WRITE DOCUMENTATION
  final CanvasController controller;

  const CanvasArea({
    super.key,
    required this.child,
    required this.controller,
  });

  @override
  State<CanvasArea> createState() => CanvasAreaState();
}

class CanvasAreaState extends State<CanvasArea> {
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return KeyboardListener(
          focusNode: focusNode,
          // Requires autofocus to make sure events are captures even while a DraggabeContentField is focused
          autofocus: true,
          onKeyEvent: (event) {
            if (event.logicalKey.keyLabel.contains('Control')) {
              if (event is KeyDownEvent) {
                _isCtrlPressed = true;
              } else if (event is KeyUpEvent) {
                _isCtrlPressed = false;
              }
              setState(() {});
            }
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
                    child: GestureDetector(
                      // Handle tap events on the canvas
                      onTapDown: widget.controller.handleTapDown,
                      // TODO: Allow this to call a function passed to CanvasArea?
                      // Displays the canvas area (widget.child) and draggable content fields on top
                      child: Stack(
                        children: [
                          widget.child,
                          // I belive order of children determines which is on top (with the last one being on top)
                          // When implementing a bring forwards/backwards feature, try just reordering the children??
                          ...widget.controller.contentFields,
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
