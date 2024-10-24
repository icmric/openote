import '/controllers/canvas_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Widget that represents the side panel of the application.
/// It contains a menu button to expand/collapse the panel and a list of saved pages.
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
          IconButton(
            icon: const Icon(Icons.menu),
            alignment: Alignment.topLeft,
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
          // List of saved pages.
          Expanded(
            child: ListView.builder(
              itemCount: canvasController.savedPages.length,
              itemBuilder: (BuildContext context, int index) {
                // Display list tiles only when the side panel is expanded.
                return sideWidth > 40
                    ? ListTile(
                        title: Text(
                          canvasController.savedPages[index],
                          style: const TextStyle(color: Colors.white),
                        ),
                        onTap: () {
                          canvasController.loadPage(
                              canvasController.savedPages[index]); // Load the selected page.
                        },
                      )
                    : null;
              },
            ),
          ),
        ],
      ),
    );
  }
}