// definition.dart

import 'package:flutter/material.dart';

class Notebook {
  String name;
  List<Section> sections;
  List<Group> groups;

  Notebook({required this.name, this.sections = const [], this.groups = const []});
}

class Section {
  String name;
  List<Chapter> chapters;

  Section({required this.name, this.chapters = const []});
}

class Group {
  String name;
  List<Chapter> chapters;

  Group({required this.name, this.chapters = const []});
}

class Chapter {
  String name;
  List<Page> pages;

  Chapter({required this.name, this.pages = const []});
}

class Page {
  String title;
  DateTime createdAt;
  DateTime lastModifiedAt;
  List<DraggableContentField> contentFields;

  Page({
    required this.title,
    required this.createdAt,
    required this.lastModifiedAt,
    this.contentFields = const [],
  });
}

class DraggableContentField {
  Offset initialPosition;
  double minWidth;
  double maxWidth;
  List<Widget> content;

  DraggableContentField({
    required this.initialPosition,
    required this.minWidth,
    required this.maxWidth,
    required this.content,
  });
}

// Example usage (you can add initializers or helper functions here later)
// For example:
// Notebook createNewNotebook(String name) {
//   return Notebook(name: name, sections: [], groups: []);
// }

// Or:
// Global functions:
// void saveNotebook(Notebook notebook) {
//   // Implementation for saving the notebook
// }