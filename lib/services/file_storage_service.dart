import 'dart:convert';
import 'dart:io';
import '/models/canvas_page_data.dart';
import '/widgets/canvas/draggable_text_field.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Service responsible for handling file storage operations, such as saving and loading canvas pages.
class FileStorageService {
  /// Gets the local path for storing files.
  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  /// Creates a File object for the given filename in the local storage directory.
  Future<File> _localFile(String fileName) async {
    final path = await _localPath;
    return File('$path/$fileName.json');
  }

  /// Saves the given CanvasPageData to a JSON file with the specified filename.
  Future<void> savePage(CanvasPageData pageData, String fileName) async {
    final file = await _localFile(fileName);

    final List<Map<String, dynamic>> textFieldsJson = pageData.textFields
        .map((textField) => textField.toJson())
        .toList(); // Convert text fields to JSON.
    final jsonString = jsonEncode(textFieldsJson); // Encode the list as a JSON string.

    await file.writeAsString(jsonString); // Write the JSON string to the file.
  }

  /// Loads CanvasPageData from a JSON file with the specified filename.
  Future<CanvasPageData?> loadPage(String fileName) async {
    try {
      final file = await _localFile(fileName);

      if (await file.exists()) {
        final jsonString = await file.readAsString(); // Read the JSON string from the file.
        final List<dynamic> jsonList =
            jsonDecode(jsonString); // Decode the JSON string into a list.

        // Create DraggableTextField widgets from the JSON data.
        final List<DraggableTextField> loadedTextFields = jsonList
            .map((json) => DraggableTextField.fromJson(
                  json,
                  (newPosition) {}, // Placeholder for onDragEnd callback.
                  () {}, // Placeholder for onEmptyDelete callback.
                  () {}, // Placeholder for onDragStart callback.
                ))
            .toList();

        return CanvasPageData(
          textFields: loadedTextFields,
          canvasSize: const Size(
              800, 600), // You might want to save/load canvas size as well.
        );
      }
    } catch (e) {
      debugPrint("Error loading page: $e");
    }
    return null; // Return null if the file doesn't exist or there's an error.
  }

  /// Loads the list of saved page filenames from the local storage directory.
  Future<List<String>> loadSavedPages() async {
    final path = await _localPath;
    final dir = Directory(path);

    List<String> savedPages = [];
    if (await dir.exists()) {
      await for (var entity in dir.list(recursive: false)) {
        if (entity is File && entity.path.endsWith('.json')) {
          savedPages.add(entity.path.split('/').last.replaceAll('.json', ''));
        }
      }
    }
    return savedPages;
  }
}