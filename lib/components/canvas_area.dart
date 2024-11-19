import 'package:flutter/material.dart';

class CanvasArea extends StatelessWidget {
  final Widget child;

  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();

  CanvasArea({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      thickness: 8.0,
      controller: _verticalController,
      scrollbarOrientation: ScrollbarOrientation.right,
      child: Scrollbar(
        thickness: 8.0,
        controller: _horizontalController,
        scrollbarOrientation: ScrollbarOrientation.bottom,
        notificationPredicate: (ScrollNotification notif) => notif.depth == 1,
        child: SingleChildScrollView(
          controller: _verticalController,
          child: SingleChildScrollView(
            primary: false,
            controller: _horizontalController,
            scrollDirection: Axis.horizontal,
            child: GestureDetector(
              onTapDown: (details) {
                print(details.localPosition);
              },
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
