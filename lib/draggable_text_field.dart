import 'package:flutter/material.dart';

class DraggableTextField extends StatefulWidget {
  final TextEditingController controller;
  final Offset initialPosition;
  final Function(Offset) onDragEnd;
  final double initialWidth;

  const DraggableTextField({
    required this.controller,
    required this.initialPosition,
    required this.onDragEnd,
    required this.initialWidth,
    Key? key,
  }) : super(key: key);

  @override
  _DraggableTextFieldState createState() => _DraggableTextFieldState();
}

class _DraggableTextFieldState extends State<DraggableTextField> {
  late Offset position;
  late double width;

  @override
  void initState() {
    super.initState();
    position = widget.initialPosition;
    width = widget.initialWidth;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            position += details.delta;
          });
        },
        onPanEnd: (details) {
          widget.onDragEnd(position);
        },
        child: Column(
          children: [
            Container(
              width: width,
              height: 25,
              color: Colors.grey,
              padding: const EdgeInsets.all(0),
              alignment: Alignment.center,
              child: const Text(
                '...',
                style: TextStyle(color: Colors.white, fontSize: 20),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(
              width: width,
              child: TextField(
                controller: widget.controller,
                autofocus: true,
                minLines: 1,
                maxLines: null,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(0), // Remove padding inside the TextField
                ),
                onChanged: (text) {
                  setState(() {
                    TextPainter textPainter = TextPainter(
                      text: TextSpan(text: text, style: const TextStyle(fontSize: 16)),
                      textDirection: TextDirection.ltr,
                      maxLines: 1,
                    )..layout();
                    width = (textPainter.width + 80).clamp(200.0, 800.0);
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}