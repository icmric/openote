import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:provider/provider.dart';
import '../components/canvas_area.dart';
import '../components/canvas_background.dart';
import '../components/canvas_controller.dart';

class CanvasPage extends StatelessWidget {
  const CanvasPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CanvasController(),
      child: Scaffold(
        body: Column(
          children: [
            Consumer<CanvasController>(
              builder: (context, canvasController, child) => QuillSimpleToolbar(
                controller: canvasController.focusedQuillController ?? QuillController.basic(),
                configurations: QuillSimpleToolbarConfigurations(),
              ),
            ),
            Expanded(
              child: Consumer<CanvasController>(
                builder: (context, controller, _) => CanvasArea(
                  controller: controller,
                  child: CanvasBackground(canvasSize: Size(2000, 2000)),
                ),
              ),
            ), /*
            Consumer<CanvasController>(
              builder: (context, controller, _) => Row(
                children: [
                  MaterialButton(
                    onPressed: () {
                      // Example of accessing contentFields
                      print('Fields: ${controller.getFocusedField()}');
                    },
                    child: Text('Get Fields'),
                    color: Colors.blue,
                  ),
                ],
              ),
            ),*/
          ],
        ),
      ),
    );
  }

  QuillSimpleToolbar getQuillToolbar(CanvasController? canvasController) {
    if (canvasController?.getFocusedField()?.content?.first is QuillEditor) {
      QuillEditor editor = canvasController?.getFocusedField()?.content?.first as QuillEditor;
      return QuillSimpleToolbar(
        controller: editor.controller,
        configurations: QuillSimpleToolbarConfigurations()
      );
    } else {
      return QuillSimpleToolbar(
        controller: QuillController.basic(),
        configurations: QuillSimpleToolbarConfigurations()
      );
    }
  }
}
