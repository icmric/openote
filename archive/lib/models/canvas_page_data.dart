import '../widgets/canvas/draggable_text_field.dart';
import 'package:flutter/material.dart';

/// Represents the data associated with a canvas page.
/// This includes the list of text fields on the canvas and the canvas size.
class CanvasPageData {
  List<DraggableTextField> textFields; // List of draggable text fields on the canvas.
  Size canvasSize; // Size of the canvas.

  CanvasPageData({required this.textFields, required this.canvasSize});
}