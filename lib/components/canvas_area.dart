import 'dart:developer';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A widget that provides a scrollable and zoomable canvas area.
/// Implements alt-key based switching between scroll and zoom modes.
class CanvasArea extends StatefulWidget {
  /// The child widget to be displayed within the canvas area
  final Widget child;

  const CanvasArea({
    Key? key,
    required this.child,
  }) : super(key: key);

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
  bool _isAltPressed = false;

  @override
  void initState() {
    super.initState();
    // Register the keyboard event handler when widget initializes
    ServicesBinding.instance.keyboard.addHandler(_onKey);
  }

  @override
  void dispose() {
    // Clean up resources when widget is disposed
    ServicesBinding.instance.keyboard.removeHandler(_onKey);
    _verticalController.dispose();
    _horizontalController.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Handles keyboard events for Alt key detection
  /// Always returns false, updates local variable instead
  bool _onKey(KeyEvent event) {
    final key = event.logicalKey.keyLabel;

    if (event is KeyDownEvent) {
      // Handle Alt key press
      if (key == 'Alt Left' || key == 'Alt Right') {
        setState(() => _isAltPressed = true);
      }
    } else if (event is KeyUpEvent) {
      // Handle Alt key release
      if (key == 'Alt Left' || key == 'Alt Right') {
        setState(() => _isAltPressed = false);
      }
    }

    return false; // Allow other keyboard handlers to process the event
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
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
          // Disable scrolling when Alt is pressed (zoom mode)
          physics: _isAltPressed ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
          child: SingleChildScrollView(
            // Horizontal scroll view
            primary: false,
            controller: _horizontalController,
            scrollDirection: Axis.horizontal,
            // Disable scrolling when Alt is pressed (zoom mode)
            physics: _isAltPressed ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
            child: GestureDetector(
              // Handle tap events for position detection
              onTapDown: (gestureDetails) {
                print(gestureDetails.localPosition);
              },
              // TODO: Wrap in Focus widget, returning focus after alt is not pressed?
              // TODO: Otherwise try wrapping something else in a focus widget
              child: InteractiveViewer(
                // Enable zooming only when Alt is pressed
                scaleEnabled: _isAltPressed,
                transformationController: _controller,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
