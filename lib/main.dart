import 'package:flutter/material.dart';
import '/pages/canvas_page.dart';
import '/pages/menu_page.dart';

class AppPage {
  final String title;
  final String route;
  final WidgetBuilder builder;

  AppPage({required this.title, required this.route, required this.builder});
}

final List<AppPage> appPages = [
  AppPage(title: 'Canvas', route: '/', builder: (context) => const CanvasPage()),
  AppPage(title: 'Menu', route: '/menu', builder: (context) => MenuPage()),
];

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      initialRoute: '/',
      routes: {
        for (var page in appPages) page.route: page.builder,
      },
    );
  }
}