import 'package:fleather/fleather.dart';
import 'package:flutter/material.dart';
import '../components/toolbar.dart';
import '../components/canvas_area.dart';

class NotebookPage extends StatefulWidget {
  const NotebookPage({super.key});

  @override
  NotebookPageState createState() => NotebookPageState();
}

class NotebookPageState extends State<NotebookPage> {
  bool _isExpanded = false;
  final GlobalKey<CanvasAreaState> _canvasKey = GlobalKey<CanvasAreaState>();
  
  // Add these new properties
  final List<FleatherController> textControllers = [];
  final ValueNotifier<FleatherController?> activeControllerNotifier = ValueNotifier<FleatherController?>(null);

  // Add method to create new text field
  void addNewTextField(Offset position) {
    final controller = FleatherController();
    final focusNode = FocusNode();
    
    focusNode.addListener(() {
      if (focusNode.hasFocus) {
        activeControllerNotifier.value = controller;
      } else {
        // Check if any other editor has focus
        if (!_canvasKey.currentState!.contentFields.any((field) => field.focusNode.hasFocus)) {
          activeControllerNotifier.value = null;
        }
      }
    });

    textControllers.add(controller);
    _canvasKey.currentState?.addNewContentField(position, controller, focusNode);
  }

  @override
  void dispose() {
    for (var controller in textControllers) {
      controller.dispose();
    }
    activeControllerNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          ValueListenableBuilder<FleatherController?>(
            valueListenable: activeControllerNotifier,
            builder: (context, controller, child) {
              return Toolbar(controller: controller);
            },
          ),
          Expanded(
            child: Row(
              children: [
                // ... existing GestureDetector code ...
                Expanded(
                  child: CanvasArea(
                    key: _canvasKey,
                    onTapDown: addNewTextField,
                    child: Image.network('https://www.nme.com/wp-content/uploads/2021/07/RickAstley2021.jpg'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}