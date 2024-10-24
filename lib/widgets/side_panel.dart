import '/controllers/canvas_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SidePanel extends StatefulWidget {
  const SidePanel({super.key});

  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel> {
  double sideWidth = 40; // Initial width of the side panel.

  @override
  Widget build(BuildContext context) {
    final canvasController = Provider.of<CanvasController>(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 100), // Animation duration for expanding/collapsing.
      color: Colors.grey[900], // Background color of the side panel.
      width: sideWidth,
      height: double.infinity,
      child: Column(
        children: [
          // Menu button to expand/collapse the side panel.
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () {
                  setState(() {
                    if (sideWidth == 40) {
                      sideWidth = 200; // Expanded width.
                    } else {
                      sideWidth = 40; // Collapsed width.
                    }
                  });
                },
              ),
              const Spacer(),
            ],
          ),
          // List of saved pages.
          Expanded(
            child: ListView(
              children: sideWidth > 40 ? _buildFileList(canvasController.savedPages) : [],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFileList(List<String> savedPages) {
    Map<String, dynamic> fileTree = {};

    for (var page in savedPages) {
      List<String> parts = page.split(r'\');
      Map<String, dynamic> currentLevel = fileTree;

      for (var part in parts) {
        if (!currentLevel.containsKey(part)) {
          currentLevel[part] = <String, dynamic>{};
        }
        currentLevel = currentLevel[part] as Map<String, dynamic>;
      }
    }

    return _buildFileWidgets(fileTree);
  }

  List<Widget> _buildFileWidgets(Map<String, dynamic> fileTree, [String currentPath = '']) {
    List<Widget> widgets = [];

    fileTree.forEach((key, value) {
      if (value.isEmpty) {
        widgets.add(
          ListTile(
            title: Text(
              currentPath + key,
              style: const TextStyle(color: Colors.white),
            ),
            onTap: () {
              Provider.of<CanvasController>(context, listen: false).loadPage(currentPath + key);
            },
          ),
        );
      } else {
        widgets.add(
          ExpansionTile(
            title: Text(
              key,
              style: const TextStyle(color: Colors.white),
            ),
            expansionAnimationStyle: AnimationStyle(curve: Curves.easeInOut, duration: const Duration(milliseconds: 100)),
            children: _buildFileWidgets(value as Map<String, dynamic>, currentPath + key + r'\'),
          ),
        );
      }
    });

    return widgets;
  }
}
