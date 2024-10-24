import '/widgets/canvas/canvas_toolbar.dart';
import '/controllers/canvas_controller.dart';
import '/widgets/canvas/canvas_area.dart';
import '/widgets/side_panel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Widget that represents the main canvas page of the application.
class CanvasPage extends StatelessWidget {
  const CanvasPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => CanvasController(), // Provide an instance of CanvasController to its descendants.
      child: const _CanvasPageContent(),
    );
  }
}

class _CanvasPageContent extends StatefulWidget {
  const _CanvasPageContent();

  @override
  State<_CanvasPageContent> createState() => _CanvasPageContentState();
}

class _CanvasPageContentState extends State<_CanvasPageContent> {
  final FocusScopeNode _canvasFocusScopeNode = FocusScopeNode();

  @override
  Widget build(BuildContext context) {
    final canvasController = Provider.of<CanvasController>(context);

    return FocusScope(
      node: _canvasFocusScopeNode,
      child: Scaffold(
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
          bottom: PreferredSize(
            // Or place CanvasToolbar below AppBar in a Container
            preferredSize: const Size.fromHeight(kToolbarHeight),
            child: FocusScope(
              canRequestFocus: false,
              child: CanvasToolbar(
                controller: canvasController.activeTextFieldController,
              ),
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: () async {
                final fileName = await canvasController.showSaveDialog(context);
                if (fileName != null) {
                  canvasController.savePage(fileName);
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: canvasController.newPage,
            ),
          ],
        ),
        body: Row(
          children: [
            const SidePanel(),
            Container(
              width: 75,
              color: Colors.grey[800],
            ),
            const CanvasArea(),
          ],
        ),
      ),
    );
  }
}
