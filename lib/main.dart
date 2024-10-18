import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:convert';

import 'package:flutter_quill/quill_delta.dart';
import 'package:path_provider/path_provider.dart';

class MyCanvasApp extends StatefulWidget {
  @override
  _MyCanvasAppState createState() => _MyCanvasAppState();
}

class _MyCanvasAppState extends State<MyCanvasApp> {
  QuillController _controller = QuillController.basic();
  TransformationController _transformationController = TransformationController();
  Size _canvasSize = Size(800, 600);
  double sideWidth = 50;
  List<FileSystemEntity> _savedFiles = [];

  @override
  void initState() {
    super.initState();
    _loadSavedFiles();
  }

  void _loadSavedFiles() async {
    final directory = await getApplicationDocumentsDirectory();
    setState(() {
      _savedFiles = directory.listSync();
    });
  }

  void _saveCanvas() async {
    final json = jsonEncode(_controller.document.toDelta().toJson());
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save your canvas',
      fileName: 'canvas.json',
    );

    if (result != null) {
      final file = File(result);
      await file.writeAsString(json);
      _loadSavedFiles();
    }
  }

  void _loadCanvas(String path) async {
    final file = File(path);
    final json = await file.readAsString();
    final delta = Delta.fromJson(jsonDecode(json));
    setState(() {
      _controller = QuillController(
        document: Document.fromDelta(delta),
        selection: TextSelection.collapsed(offset: 0),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Canvas App'),
        actions: [
          IconButton(
            icon: Icon(Icons.save),
            onPressed: _saveCanvas,
          ),
        ],
      ),
      body: Row(
        children: [
          Container(
            width: sideWidth,
            child: ListView.builder(
              itemCount: _savedFiles.length,
              shrinkWrap: true,
              itemBuilder: (BuildContext context, int index) {
                final file = _savedFiles[index];
                return ListTile(
                  title: Text(file.path.split('/').last, style: TextStyle(color: Colors.white)),
                  onTap: () => _loadCanvas(file.path),
                );
              },
            ),
          ),
          Expanded(
            child: InteractiveViewer(
              constrained: false,
              boundaryMargin: const EdgeInsets.all(20),
              transformationController: _transformationController,
              child: SizedBox(
                width: _canvasSize.width,
                height: _canvasSize.height,
                child: QuillEditor.basic(
                  configurations: QuillEditorConfigurations(controller: _controller),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}