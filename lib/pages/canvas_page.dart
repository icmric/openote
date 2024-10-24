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
      create: (context) =>
          CanvasController(), // Provide an instance of CanvasController to its descendants.
      child: _CanvasPageContent(),
    );
  }
}

class _CanvasPageContent extends StatefulWidget {
  const _CanvasPageContent({super.key});

  @override
  State<_CanvasPageContent> createState() => _CanvasPageContentState();
}

class _CanvasPageContentState extends State<_CanvasPageContent> {
  @override
  Widget build(BuildContext context) {
    final canvasController = Provider.of<CanvasController>(context);

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
    );
  }
}