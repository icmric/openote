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

  /// Initializes the canvas position
  void initializeCanvas() {
    try {
      transformationController.value = Matrix4.identity()..translate(100, 100);
    } catch (e) {
      // Initial positioning can fail if canvas isn't ready
      debugPrint("Canvas positioning deferred: $e");
    }
  }

  /// Adds a new content field at the specified position
  void addContentField(Offset position) {
    final focusNode = FocusNode();
    final controller = QuillController.basic();
    final newField = DraggableContentField(
      initialPosition: position,
      maxWidth: 800,
      focusNode: focusNode,
      content: [
        Container(
          color: Colors.white,
          child: QuillEditor.basic(
            focusNode: focusNode,
            controller: controller,
          ),
        ),
      ],
    );
    _focusedQuillController = controller;
    contentFields.add(newField);
    focusNode.requestFocus();
    notifyListeners();
  }

  /// Updates control key state for zoom functionality
  void setCtrlPressed(bool pressed) {
    isCtrlPressed = pressed;
    notifyListeners();
  }

  /// Checks if a point is inside any content field
  bool isPointInsideContentField(Offset position) {
    return contentFields.any((field) {
      final RenderBox? renderBox = 
          field.globalKey.currentContext?.findRenderObject() as RenderBox?;
      
      if (renderBox == null) return false;

      final fieldPosition = renderBox.localToGlobal(Offset.zero);
      final fieldSize = renderBox.size;

      return position.dx >= fieldPosition.dx &&
             position.dx <= fieldPosition.dx + fieldSize.width &&
             position.dy >= fieldPosition.dy &&
             position.dy <= fieldPosition.dy + fieldSize.height;
    });
  }

/// Gets the currently focused content field
DraggableContentField? getFocusedField() {
  try {
    return contentFields.firstWhere(
      (field) => field.focusNode.hasFocus,
    );
  } catch (e) {
    return null;
  }
}

  /// Handles tap events on the canvas
  void handleTapDown(TapDownDetails details) {
    if (!isPointInsideContentField(details.globalPosition)) {
      addContentField(details.localPosition);
    }
  }

  @override
  void dispose() {
    transformationController.dispose();
    super.dispose();
  }
}