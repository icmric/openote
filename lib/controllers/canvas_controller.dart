import 'package:flutter_quill/flutter_quill.dart';

import '/models/canvas_page_data.dart';
import '/services/file_storage_service.dart';
import '/widgets/canvas/draggable_text_field.dart';
import 'package:flutter/material.dart';

/// Controller that manages the state and logic of the canvas page.
class CanvasController with ChangeNotifier {
  final FileStorageService _fileStorageService = FileStorageService(); // Service for file storage operations.

  QuillController? _activeTextFieldController;
  QuillController? get activeTextFieldController => _activeTextFieldController;

  CanvasPageData _canvasPageData = CanvasPageData(
    textFields: [],
    canvasSize: const Size(2000, 1000), // Initial canvas size.
  );

  CanvasPageData get canvasPageData => _canvasPageData; // Accessor for canvasPageData.

  final TransformationController _transformationController = TransformationController(); // Controller for handling canvas transformations (zoom, pan).

  TransformationController get transformationController => _transformationController; // Accessor for transformationController.

  List<String> _savedPages = []; // List of saved page filenames.
  List<String> get savedPages => _savedPages; // Accessor for savedPages.

  CanvasController() {
    _initialize(); // Initialize the controller when it's created.
  }

  /// Initializes the canvas by positioning it and loading saved pages.
  Future<void> _initialize() async {
    _positionCanvasTopLeft(); // Position the canvas initially.
    _savedPages = await _fileStorageService.loadSavedPages(); // Load the list of saved page filenames.
    notifyListeners(); // Notify listeners that the state has changed.
  }

  /// Positions the canvas to the top-left corner initially.
  void _positionCanvasTopLeft() {
    try {
      _transformationController.value = Matrix4.identity()..translate(100, 100);
    } catch (e) {
      // Will throw an error when its done before canvas is finished drawing. Catch it and move on
      //debugPrint("Error positioning canvas: $e");
    }
  }

  /// Handles tap down events on the canvas.
  /// Adds a new text field if no existing text field was tapped.
  void handleTapDown(TapDownDetails details) {
    Offset canvasTapPosition = details.localPosition;

    int tappedTextFieldIndex = _getTappedTextFieldIndex(canvasTapPosition);

    if (tappedTextFieldIndex == -1) {
      _addNewTextField(canvasTapPosition); // Add a new text field at the tap position.
    } else {
      _canvasPageData.textFields[tappedTextFieldIndex].focusNode.requestFocus(); // Focus the tapped text field.
    }
  }

  /// Adds a new draggable text field to the canvas at the given position.
  void _addNewTextField(Offset position) {
    FocusNode newFocusNode = FocusNode();
    QuillController newController = QuillController.basic(); // Create a new QuillController

    _canvasPageData.textFields.add(
      DraggableTextField(
        initialPosition: position - const Offset(10, 50),
        maxWidth: 600,
        controller: newController,
        onDragEnd: (newPosition) {
          int index = _canvasPageData.textFields.indexOf(_canvasPageData.textFields.last);
          _canvasPageData.textFields[index].position = newPosition;
          notifyListeners(); // Notify listeners that the text field position has changed.
        },
        onEmptyDelete: () {
          _canvasPageData.textFields.removeLast();
          notifyListeners(); // Notify listeners that a text field has been removed.
        },
        onDragStart: _unfocusAllTextFields,
        focusNode: newFocusNode,
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      newFocusNode.requestFocus(); // Request focus for the new text field after the frame is built.
    });

    notifyListeners(); // Notify listeners that a new text field has been added.
  }

  /// Returns the index of the tapped text field, or -1 if no text field was tapped.
  int _getTappedTextFieldIndex(Offset tapPosition) {
    for (int i = 0; i < _canvasPageData.textFields.length; i++) {
      final textField = _canvasPageData.textFields[i];
      final position = textField.position;
      final width = textField.width;
      final height = textField.focusNode.hasFocus ? 47 : 22;

      if (tapPosition.dx >= position.dx && tapPosition.dx <= position.dx + width && tapPosition.dy >= position.dy && tapPosition.dy <= position.dy + height) {
        return i;
      }
    }
    return -1;
  }

  /// Unfocuses all text fields on the canvas.
  void _unfocusAllTextFields() {
    for (var textField in _canvasPageData.textFields) {
      textField.focusNode.unfocus();
    }
  }

  /// Saves the current page to a file with the given filename.
  Future<void> savePage(String fileName) async {
    await _fileStorageService.savePage(_canvasPageData, fileName);
    _savedPages = await _fileStorageService.loadSavedPages();
    notifyListeners(); // Notify listeners that the saved pages list has changed.
  }

  /// Loads a page from a file with the given filename.
  Future<void> loadPage(String fileName) async {
    final loadedPageData = await _fileStorageService.loadPage(fileName);
    if (loadedPageData != null) {
      _canvasPageData = loadedPageData;
      notifyListeners(); // Notify listeners that the page data has changed.
    }
  }

  /// Clears the canvas and creates a new page.
  void newPage() {
    _canvasPageData.textFields.clear();
    notifyListeners(); // Notify listeners that the page data has changed.
  }

  /// Shows a dialog to get the filename for saving the page.
  Future<String?> showSaveDialog(BuildContext context) async {
    String fileName = '';
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Save Page'),
          content: TextField(
            onChanged: (value) {
              fileName = value;
            },
            decoration: const InputDecoration(hintText: "Enter file name"),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Save'),
              onPressed: () {
                Navigator.of(context).pop(fileName);
              },
            ),
          ],
        );
      },
    );
  }

  void setActiveTextFieldController(QuillController? controller) {
    _activeTextFieldController = controller;
    notifyListeners();
  }
}
