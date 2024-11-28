import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:mosapad/components/draggable_content_field.dart';

/// Controls the canvas state and operations.
/// Manages content fields, transformations, and interactions.
class CanvasController with ChangeNotifier {
  /// List of content fields on the canvas
  final List<DraggableContentField> contentFields = [];

  /// Controller for canvas transformations (zoom/pan)
  final TransformationController transformationController = TransformationController();

  /// Tracks if control key is pressed for zoom functionality
  bool isCtrlPressed = false;

  /// Currently focused QuillController, if any
  QuillController? _focusedQuillController;

  /// Gets the currently focused QuillController
  QuillController? get focusedQuillController => _focusedQuillController;

  /// Sets the focused QuillController and notifies listeners
  set focusedQuillController(QuillController? controller) {
    if (_focusedQuillController != controller) {
      _focusedQuillController = controller;
      notifyListeners();
    }
  }

  // ... rest of existing code ...
}

class CanvasToolbar extends StatelessWidget {
  final QuillController? controller;

  const CanvasToolbar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[200], // Example background color
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: controller != null ? QuillToolbar.simple(controller: controller, configurations: QuillSimpleToolbarConfigurations(buttonOptions: QuillSimpleToolbarButtonOptions())) : _buildDisabledToolbar(),
    );
  }

  Widget _buildDisabledToolbar() {
    return Opacity(
      opacity: 0.5, // Make it semi-transparent
      child: QuillToolbar.simple(
        controller: QuillController.basic(), // Use a dummy controller
      ),
    );
  }
}
