import 'package:flutter/material.dart';
import 'package:fleather/fleather.dart';

class Toolbar extends StatelessWidget {
  final FleatherController? controller;

  const Toolbar({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    if (controller == null) {
      return Container(
        padding: EdgeInsets.all(8.0),
        color: Colors.blue,
      );
    }

    return Container(
      padding: EdgeInsets.all(8.0),
      color: Colors.grey[200],
      child: FleatherToolbar.basic(controller: controller!),
    );
  }
}
