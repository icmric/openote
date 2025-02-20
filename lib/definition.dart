import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

enum PageBackgroundType {
  none,
  solidColor,
  canvasGrid,
}

class Notebook {
  /// Unique identifier for the notebook (Auto generated)
  String uuid;

  /// Name of the notebook
  String name;

  /// Date and time when the notebook was created
  DateTime createdAt;

  /// Colour of the icon for the notebook
  String iconColour;

  /// List of chapters in the notebook
  List<Chapter> chapters;

  /// List of groups in the notebook
  List<Group> groups;

  Notebook({
    required this.name,
    required this.createdAt,
    required this.iconColour,
    this.chapters = const [],
    this.groups = const [],
  }) : uuid = const Uuid().v4();
}

class Group {
  /// Unique identifier for the group (Auto generated)
  String uuid;

  /// Name of the group
  String name;

  /// Colour of the icon for the group
  String groupColour;

  /// List of sections in the group
  List<Chapter> chapters;

  Group({
    required this.name,
    required this.groupColour,
    this.chapters = const [],
  }) : uuid = const Uuid().v4();
}

class Chapter {
  /// Unique identifier for the chapter (Auto generated)
  String uuid;

  /// Name of the chapter
  String name;

  /// Colour of the icon for the chapter
  String chapterColour;

  /// List of pages in the chapter
  List<Page> pages;

  Chapter({
    required this.name,
    required this.chapterColour,
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

  /// List of tags for the page
  List<String>? tags;

  /// Background type of the page using the PageBackgroundType enum
  PageBackgroundType backgroundType;

  /// Background colour of the page
  Color? backgroundColor;

  /// Height of the page
  double? pageWidth;

  /// width of the page
  double? pageHeight;

  /// Current view state of the page
  ViewState? viewState;

  Page({
    required this.title,
    required this.createdAt,
    required this.lastModifiedAt,
    this.contentFields = const [],
    this.tags,
    this.backgroundType = PageBackgroundType.none,
    this.backgroundColor,
    this.pageWidth,
    this.pageHeight,
    this.viewState,
  }) : uuid = const Uuid().v4();
}

class ViewState {
  double? zoomLevel;
  double? scrollOffsetX;
  double? scrollOffsetY;

  ViewState({this.zoomLevel, this.scrollOffsetX, this.scrollOffsetY});
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
