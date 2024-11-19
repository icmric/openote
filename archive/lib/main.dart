import 'pages/canvas_page.dart';
import 'package:flutter/material.dart';

// Entry point of the Flutter application.
void main() {
  runApp(const MyApp());
}

// The root widget of the application.
// It sets up the MaterialApp and defines the initial route to the CanvasPage.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const CanvasPage(), // The initial page to display is CanvasPage.
    );
  }
}