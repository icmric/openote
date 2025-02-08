import 'package:flutter/material.dart';

class ResizableImage extends StatefulWidget {
  final String imageUrl;
  final Function(double, double) onResize;

  const ResizableImage({
    required this.imageUrl,
    required this.onResize,
    super.key,
  });

  @override
  ResizableImageState createState() => ResizableImageState();
}

class ResizableImageState extends State<ResizableImage> {
  double _width = 200; // Initial width
  double _height = 150; // Initial height

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          _width += details.delta.dx;
          _height += details.delta.dy;
        });
        widget.onResize(_width, _height);
      },
      child: Container(
        width: _width,
        height: _height,
        decoration: BoxDecoration(
          image: DecorationImage(
            image: NetworkImage(widget.imageUrl),
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}