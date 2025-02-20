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


  
}