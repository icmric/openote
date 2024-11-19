import '../widgets/canvas/canvas_toolbar.dart';
import '/controllers/canvas_controller.dart';
import '../widgets/canvas/canvas_area.dart';
import '../widgets/side_panel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/db.dart';

// Widget that represents the main canvas page of the application.
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
    loadContentFromDB(title: "example");
    return FocusScope(
      node: _canvasFocusScopeNode,
      child: Scaffold(
        backgroundColor: Colors.grey[900],
        appBar: AppBar(
          title: const Column(
            children: [
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
                final fileName = await canvasController.showSaveDialog(context);
                if (fileName != null) {
                  canvasController.savePage(fileName);
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () {
                wipeDB();
              }, //canvasController.newPage,
            ),
          ],
        ),
        body: Column(
          children: [
            SizedBox(
              height: 50,
              child: CanvasToolbar(
                controller: canvasController.activeTextFieldController,
              ),
            ),
            SizedBox(
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height - kToolbarHeight - 50,
              child: Row(
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
          ],
        ),
      ),
    );
  }
}
