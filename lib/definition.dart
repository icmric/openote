import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

class Notebook {
  /// Unique identifier for the notebook (Auto generated)
  String uuid;

  /// Name of the notebook
  String name;

  /// Date and time when the notebook was created
  DateTime createdAt;

  /// Colour of the icon for the notebook
  String iconColour;

  /// List of sections in the notebook
  List<Section> sections;

  /// List of groups in the notebook
  List<Group> groups;

  Notebook({
    required this.name,
    required this.createdAt,
    required this.iconColour,
    this.sections = const [],
    this.groups = const [],
  }) : uuid = const Uuid().v4();
}

class Section {
  /// Unique identifier for the section (Auto generated)
  String uuid;

  /// Name of the section
  String name;

  /// List of chapters in the section
  List<Chapter> chapters;

  Section({
    required this.name,
    this.chapters = const [],
  }) : uuid = const Uuid().v4();
}

class Group {
  /// Unique identifier for the group (Auto generated)
  String uuid;

  /// Name of the group
  String name;

  /// List of sections in the group
  List<Section> sections;

  Group({
    required this.name,
    this.sections = const [],
  }) : uuid = const Uuid().v4();
}

class Chapter {
  /// Unique identifier for the chapter (Auto generated)
  String uuid;

  /// Name of the chapter
  String name;

  /// List of pages in the chapter
  List<Page> pages;

  Chapter({
    required this.name,
    this.pages = const [],
  }) : uuid = const Uuid().v4();
}

class Page {
  /// Unique identifier for the page (Auto generated)
  String uuid;

  /// Title of the page
  String title;

  /// Date and time when the page was created
  DateTime createdAt;

  /// Date and time when the page was last modified
  DateTime lastModifiedAt;

  /// List of content fields in the page
  List<DraggableContentField> contentFields;

  Page({
    required this.title,
    required this.createdAt,
    required this.lastModifiedAt,
    this.contentFields = const [],
  }) : uuid = const Uuid().v4();
}

class DraggableContentField {
  /// Unique identifier for the draggable content field (Auto generated)
  String uuid;

  /// Initial position of the draggable content field
  Offset initialPosition;

  /// Minimum width of the draggable content field
  double minWidth;

  /// Maximum width of the draggable content field
  double maxWidth;

  /// List of widgets (content) in the draggable content field
  List<Widget> content;

  DraggableContentField({
    required this.initialPosition,
    required this.minWidth,
    required this.maxWidth,
    required this.content,
  }) : uuid = const Uuid().v4();
}