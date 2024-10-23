import 'dart:convert';
import 'dart:io';
import 'package:fleather/fleather.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'draggable_text_field.dart';
import 'canvas_grid_painter.dart';

// Entry point of the Flutter application
void main() {
  runApp(const MyApp());
}

// Root widget of the application
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Canvas App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const CanvasPage(),
    );
  }
}

// StatefulWidget that represents the main canvas page
class CanvasPage extends StatefulWidget {
  const CanvasPage({super.key});

  @override
  State<CanvasPage> createState() => _CanvasPageState();
}

class _CanvasPageState extends State<CanvasPage> {
  // List to store the draggable text fields on the canvas
  final List<DraggableTextField> _textFields = [];
  // Size of the canvas
  Size _canvasSize = const Size(800, 600);
  // Controller for handling transformations (e.g., zoom, pan) on the canvas
  final TransformationController _transformationController = TransformationController();
  // Width of the side panel
  double sideWidth = 40;
  // List to store the names of saved pages
  List<String> _savedPages = [];

  int? focusedTextFieldIndex = null;

  @override
  void initState() {
    super.initState();
    // Run code after the first frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeCanvasSize();
      _positionCanvasTopLeft();
      _loadSavedPages("C:/src/temp"); // Load saved pages from the specified directory
    });
  }

  // Initialize the canvas size based on the screen size
  void _initializeCanvasSize() {
    final Size screenSize = MediaQuery.of(context).size;
    setState(() {
      _canvasSize = Size(screenSize.width * 2, screenSize.height * 2);
    });
  }

  // Position the canvas initially to the top-left corner
  void _positionCanvasTopLeft() {
    try {
      _transformationController.value = Matrix4.identity()..translate(100, 100);
    } catch (e) {
      // Ignore the exception if it occurs.
    }
  }

  // Handle tap down events on the canvas
  void _handleTapDown(TapDownDetails details) {
    // Get the tap position on the canvas
    Offset canvasTapPosition = details.localPosition;

    // Check if a text field was tapped
    int tappedTextFieldIndex = _getTappedTextFieldIndex(canvasTapPosition);

    // If no text field was tapped, add a new one at the tap position
    if (tappedTextFieldIndex == -1) {
      _addNewTextField(canvasTapPosition);
      focusedTextFieldIndex = _textFields.length - 1;
    } else {
      // Otherwise, focus the tapped text field
      _textFields[tappedTextFieldIndex].focusNode.requestFocus();
      focusedTextFieldIndex = tappedTextFieldIndex;
    }
  }

  // Add a new draggable text field to the canvas
  void _addNewTextField(Offset position) {
    // Create a new focus node for the text field
    FocusNode newFocusNode = FocusNode();

    setState(() {
      _textFields.add(DraggableTextField(
        initialPosition: position - const Offset(10, 50), // Initial position of the text field
        maxWidth: 600, // Initial width of the text field
        onDragEnd: (newPosition) {
          // Update the position of the text field when dragging ends
          setState(() {
            int index = _textFields.indexOf(_textFields.last);
            _textFields[index].position = newPosition;
          });
        },
        onEmptyDelete: () {
          // Remove the text field if it's empty and the delete key is pressed
          setState(() {
            _textFields.removeLast();
          });
        },
        onDragStart: _unfocusAllTextFields, // Unfocus all text fields when dragging starts
        focusNode: newFocusNode, // Assign the focus node to the text field
      ));

      // Request focus for the newly added text field after the frame is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        newFocusNode.requestFocus();
      });
    });
  }

  // Get the index of the tapped text field, or -1 if no text field was tapped
  int _getTappedTextFieldIndex(Offset tapPosition) {
    for (int i = 0; i < _textFields.length; i++) {
      final textField = _textFields[i];
      final position = textField.position;
      final width = textField.width;
      final height = textField.focusNode.hasFocus ? 47 : 22; // Adjust height based on focus state

      // Check if the tap position is within the bounds of the text field
      if (tapPosition.dx >= position.dx && tapPosition.dx <= position.dx + width && tapPosition.dy >= position.dy && tapPosition.dy <= position.dy + height) {
        return i;
      }
    }
    return -1;
  }

  // Unfocus all text fields on the canvas
  void _unfocusAllTextFields() {
    for (var textField in _textFields) {
      textField.focusNode.unfocus();
    }
    focusedTextFieldIndex = null;
  }

  // Save the current page's text fields to a JSON file
  Future<void> _savePage(String fileName) async {
    // Get the application documents directory
    final directory = Directory('C:/src/temp');
    // Create a File object for the JSON file
    final file = File('${directory.path}/$fileName.json');

    // Convert the text fields to a JSON-encodable list of maps
    final List<Map<String, dynamic>> textFieldsJson = _textFields.map((textField) => textField.toJson()).toList();
    // Encode the list of maps as a JSON string
    final jsonString = jsonEncode(textFieldsJson);

    // Write the JSON string to the file
    await file.writeAsString(jsonString);
    // Reload the saved pages list
    _loadSavedPages("C:/src/temp");
  }

  // Load a page from a JSON file
  Future<void> _loadPage(String filePath) async {
    // Get the application documents directory
    //final directory = await getApplicationDocumentsDirectory();
    // Construct the full path to the JSON file
    final file = File('C:/src/temp/$filePath');

    // Check if the file exists
    if (await file.exists()) {
      // Read the JSON string from the file
      final jsonString = await file.readAsString();
      // Decode the JSON string into a list of dynamic objects
      final List<dynamic> jsonList = jsonDecode(jsonString);
      setState(() {
        // Clear the existing text fields
        _textFields.clear();
        // Create DraggableTextField widgets from the JSON data
        for (var json in jsonList) {
          print(json);
          _textFields.add(DraggableTextField.fromJson(
            json,
            (newPosition) {
              // Update the position of the text field when dragging ends
              setState(() {
              int index = _textFields.indexOf(_textFields.last);
              _textFields[index].position = newPosition;
              });
            },
            () {
              // Remove the text field if it's empty and the delete key is pressed
              setState(() {
                _textFields.removeLast();
              });
            },
            _unfocusAllTextFields, // Pass the _unfocusAllTextFields function
          ));
        }
      }); 
    }
  }

  // Clear the canvas and create a new page
  void _newPage() {
    setState(() {
      _textFields.clear();
    });
  }

  /// Loads the names of all JSON files found within the specified directory and its subdirectories into the `_savedPages` list.
  ///
  /// The file names are stored in `_savedPages` with a modified format where the platform-specific path separator is replaced with "~/~".
  /// This allows for consistent representation of file paths across different operating systems.
  ///
  /// For example, if a JSON file is found at "folder1/folder2/file.json", it will be added to `_savedPages` as "folder1~/~folder2~/~file.json".
  ///
  /// **Parameters:**
  ///
  /// * `filePath`: The path to the directory from which to start searching for JSON files.
  Future<void> _loadSavedPages(String filePath) async {
    // Initialize an empty list to store the JSON file names.
    List<String> jsonFiles = [];
    // Create a Directory object representing the specified file path.
    Directory directory = Directory(filePath);

    // Check if the directory exists.
    if (await directory.exists()) {
      // Asynchronously iterate through all files and subdirectories within the directory.
      await for (FileSystemEntity entity in directory.list(recursive: true)) {
        // Check if the current entity is a file and its path ends with ".json".
        if (entity is File && entity.path.endsWith('.json')) {
          // Extract the relative path of the JSON file from the specified directory.
          String relativePath = entity.path.substring(filePath.length + 1);
          // Add the relative path to the list of JSON file names, replacing the platform-specific path separator with "~/~".
          jsonFiles.add(relativePath.replaceAll(Platform.pathSeparator, '~/~'));
        }
      }
    }

    // Update the state of the widget to reflect the loaded JSON file names.
    setState(() {
      _savedPages = jsonFiles;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: Column(
          children: [
            const Text('Canvas App'),
            // TODO move this to its own thing seperate from AppBar, remove AppBar?
            focusedTextFieldIndex != null && focusedTextFieldIndex! < _textFields.length ? FleatherToolbar.basic(controller: _textFields[focusedTextFieldIndex!].controller) : Container(),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () async {
              final fileName = await _showSaveDialog();
              if (fileName != null) {
                _savePage(fileName);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _newPage,
          ),
        ],
      ),
      body: Row(
        children: [
          // Side panel
          AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            color: Colors.grey[900],
            width: sideWidth,
            height: double.infinity,
            child: Column(
              children: [
                // Menu button to expand/collapse the side panel
                IconButton(
                  icon: const Icon(Icons.menu),
                  alignment: Alignment.topLeft,
                  onPressed: () {
                    setState(() {
                      if (sideWidth == 40) {
                        sideWidth = 200;
                      } else {
                        sideWidth = 40;
                      }
                    });
                  },
                ),
                // List of saved pages
                Expanded(
                  child: ListView.builder(
                    itemCount: _savedPages.length,
                    itemBuilder: (BuildContext context, int index) {
                      // Display list tiles only when the side panel is expanded
                      return sideWidth > 40
                          ? ListTile(
                              title: Text(
                                _savedPages[index],
                                style: const TextStyle(color: Colors.white),
                              ),
                              onTap: () {
                                _loadPage(_savedPages[index]);
                              },
                            )
                          : null;
                    },
                  ),
                ),
              ],
            ),
          ),
          // Spacer between side panel and canvas
          Container(
            width: 75,
            color: Colors.grey[800],
          ),
          // Canvas area
          Expanded(
            child: InteractiveViewer(
              constrained: false,
              boundaryMargin: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
              transformationController: _transformationController,
              child: SizedBox(
                width: _canvasSize.width,
                height: _canvasSize.height,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapDown: _handleTapDown,
                  child: Stack(
                    children: [
                      // Background grid of the canvas
                      Container(
                        width: _canvasSize.width,
                        height: _canvasSize.height,
                        color: Colors.grey[850],
                        child: CustomPaint(
                          size: _canvasSize,
                          painter: CanvasGridPainter(),
                        ),
                      ),
                      // Draggable text fields
                      ..._textFields,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Show a dialog to get the file name for saving the page
  Future<String?> _showSaveDialog() async {
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        String fileName = '';
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
}
