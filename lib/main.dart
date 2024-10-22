import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'draggable_text_field.dart';
import 'canvas_grid_painter.dart';

void main() {
  runApp(const MyApp());
}

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

class CanvasPage extends StatefulWidget {
  const CanvasPage({super.key});

  @override
  State<CanvasPage> createState() => _CanvasPageState();
}

class _CanvasPageState extends State<CanvasPage> {
  final List<DraggableTextField> _textFields = [];
  Size _canvasSize = const Size(800, 600);
  final TransformationController _transformationController = TransformationController();
  double sideWidth = 40;
  List<String> _savedPages = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeCanvasSize();
      _positionCanvasTopLeft();
      _loadSavedPages(subdirectory: "/Notes Test");
    });
  }

  void _initializeCanvasSize() {
    final Size screenSize = MediaQuery.of(context).size;
    setState(() {
      _canvasSize = Size(screenSize.width * 2, screenSize.height * 2);
    });
  }

  void _positionCanvasTopLeft() {
    try {
      _transformationController.value = Matrix4.identity()..translate(100, 100);
    } catch (e) {
      // Ignore the exception if it occurs.
    }
  }

  void _handleTapDown(TapDownDetails details) {
    Offset canvasTapPosition = details.localPosition;

    int tappedTextFieldIndex = _getTappedTextFieldIndex(canvasTapPosition);

    if (tappedTextFieldIndex == -1) {
      _addNewTextField(canvasTapPosition);
    } else {
      _textFields[tappedTextFieldIndex].focusNode.requestFocus();
    }
  }

  void _addNewTextField(Offset position) {
    FocusNode newFocusNode = FocusNode();

    setState(() {
      _textFields.add(DraggableTextField(
        initialPosition: position - const Offset(10, 50),
        initialWidth: 200,
        onDragEnd: (newPosition) {
          setState(() {
            int index = _textFields.indexOf(_textFields.last);
            _textFields[index].position = newPosition;
          });
        },
        onEmptyDelete: () {
          setState(() {
            _textFields.removeLast();
          });
        },
        onDragStart: _unfocusAllTextFields,
        focusNode: newFocusNode,
      ));

      WidgetsBinding.instance.addPostFrameCallback((_) {
        newFocusNode.requestFocus();
      });
    });
  }

  int _getTappedTextFieldIndex(Offset tapPosition) {
    for (int i = 0; i < _textFields.length; i++) {
      final textField = _textFields[i];
      final position = textField.position;
      final width = textField.width;
      final height = textField.focusNode.hasFocus ? 47 : 22;

      if (tapPosition.dx >= position.dx && tapPosition.dx <= position.dx + width && tapPosition.dy >= position.dy && tapPosition.dy <= position.dy + height) {
        return i;
      }
    }
    return -1;
  }

  void _unfocusAllTextFields() {
    for (var textField in _textFields) {
      textField.focusNode.unfocus();
    }
  }

  Future<void> _savePage(String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$fileName.json');

    final List<Map<String, dynamic>> textFieldsJson = _textFields.map((textField) => textField.toJson()).toList();
    final jsonString = jsonEncode(textFieldsJson);

    await file.writeAsString(jsonString);
    _loadSavedPages(subdirectory: "/Notes Test");
  }

  Future<void> _loadPage(String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('$fileName.json');

    if (await file.exists()) {
      final jsonString = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(jsonString);

      setState(() {
        _textFields.clear();
        for (var json in jsonList) {
          _textFields.add(DraggableTextField.fromJson(
            json,
            (newPosition) {
              setState(() {
                int index = _textFields.indexOf(_textFields.last);
                _textFields[index].position = newPosition;
              });
            },
            () {
              setState(() {
                _textFields.removeLast();
              });
            },
            _unfocusAllTextFields,
          ));
        }
      });
    }
  }

  void _newPage() {
    setState(() {
      _textFields.clear();
    });
  }

  Future<void> _loadSavedPages({String subdirectory = ''}) async {
    final directory = await getApplicationDocumentsDirectory();
    final targetDirectory = Directory('${directory.path}$subdirectory');
    List<String> savedPages = [];

    void traverseDirectory(Directory dir) {
      final List<FileSystemEntity> entities = dir.listSync();
      for (var entity in entities) {
        if (entity is File && entity.path.endsWith('.json')) {
          // Calculate relative path from targetDirectory
          String relativePath = entity.path.replaceFirst("${targetDirectory.path}/", '');
          print(relativePath);
          savedPages.add(relativePath);
        } else if (entity is Directory) {
          // Check if the directory is not the initial targetDirectory
          if (entity.path != targetDirectory.path) {
            traverseDirectory(entity);
          }
        }
      }
    }

    traverseDirectory(targetDirectory);
    setState(() {
      _savedPages = savedPages;
    });
    print(_savedPages);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Column(
          children: [
            Text('Canvas App'),
            Wrap(
              spacing: 10,
              alignment: WrapAlignment.start,
              children: [
                Text("File"),
                Text("Home"),
                Text("Insert"),
              ],
            )
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
          AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            color: Colors.grey[900],
            width: sideWidth,
            height: double.infinity,
            child: Column(
              children: [
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
                Expanded(
                  child: ListView.builder(
                    itemCount: _savedPages.length,
                    itemBuilder: (BuildContext context, int index) {
                      return ListTile(
                        title: Text(
                          _savedPages[index],
                          style: const TextStyle(color: Colors.white),
                        ),
                        onTap: () {
                          _loadPage(_savedPages[index]);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 75,
            color: Colors.grey[800],
          ),
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
                      Container(
                        width: _canvasSize.width,
                        height: _canvasSize.height,
                        color: Colors.grey[850],
                        child: CustomPaint(
                          size: _canvasSize,
                          painter: CanvasGridPainter(),
                        ),
                      ),
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
