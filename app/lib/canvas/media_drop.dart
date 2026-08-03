/// Getting media onto the page: paste, drag-and-drop, and the file picker
/// (MEDIA-1).
///
/// For a student this is *the* capture flow — screenshot a slide, paste it
/// into the page. Until now the only route was Insert → Image → file dialog,
/// which means saving the screenshot to disk first. Three entry points now
/// share one insertion function so an image lands identically however it
/// arrived.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../model/models.dart';
import '../state/app_state.dart';

/// MIME type from a file extension, defaulting to PNG.
String mimeForExtension(String name) {
  final ext = name.split('.').last.toLowerCase();
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'bmp' => 'image/bmp',
    'svg' => 'image/svg+xml',
    'pdf' => 'application/pdf',
    _ => 'image/png',
  };
}

const _imageExtensions = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};

bool _looksLikeImage(String name) =>
    _imageExtensions.contains(name.split('.').last.toLowerCase());

/// Insert image bytes as a block at [at] (page coordinates), sized to fit.
///
/// The block is created at a sane width and left selected, so the very next
/// gesture can move or resize it — pasting something you then have to hunt for
/// is barely better than not pasting at all.
Block insertImageBytes(AppState app, Uint8List bytes, String mime, Offset at,
    {double width = 320}) {
  final hash = app.addBlob(bytes, mime);
  final b = app.addBlock(Block(
    type: BlockType.image,
    x: at.dx - width / 2,
    y: at.dy - width * 0.375,
    w: width,
    content: {'blob': 'sha256:$hash', 'mime': mime},
  ));
  app.select(b.id);
  return b;
}

/// Insert a non-image file as an attachment block.
Block insertFileBytes(
    AppState app, Uint8List bytes, String name, Offset at) {
  final hash = app.addBlob(bytes, mimeForExtension(name));
  final b = app.addBlock(Block(
    type: BlockType.file,
    x: at.dx - 110,
    y: at.dy - 24,
    w: 220,
    content: {'blob': 'sha256:$hash', 'name': name},
  ));
  app.select(b.id);
  return b;
}

/// What a paste produced, so the caller can report it.
enum PasteResult { nothing, image, text, files }

/// Paste whatever the clipboard holds onto the page at [at].
///
/// Image first, then files, then text: a screenshot copied from a browser
/// carries *both* an image and a text/HTML representation, and the image is
/// invariably what was meant.
Future<PasteResult> pasteOntoCanvas(AppState app, Offset at) async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) return PasteResult.nothing; // unsupported platform
  final reader = await clipboard.read();

  for (final fmt in [Formats.png, Formats.jpeg, Formats.gif, Formats.webp]) {
    if (!reader.canProvide(fmt)) continue;
    final bytes = await _readFile(reader, fmt);
    if (bytes == null || bytes.isEmpty) continue;
    insertImageBytes(app, bytes, _mimeOf(fmt), at);
    return PasteResult.image;
  }

  if (reader.canProvide(Formats.fileUri)) {
    final uri = await reader.readValue(Formats.fileUri);
    if (uri != null) {
      final path = uri.toFilePath();
      final file = File(path);
      if (file.existsSync()) {
        final bytes = await file.readAsBytes();
        final name = path.split(Platform.pathSeparator).last;
        _looksLikeImage(name)
            ? insertImageBytes(app, bytes, mimeForExtension(name), at)
            : insertFileBytes(app, bytes, name, at);
        return PasteResult.files;
      }
    }
  }

  if (reader.canProvide(Formats.plainText)) {
    final text = await reader.readValue(Formats.plainText);
    if (text != null && text.trim().isNotEmpty) {
      // Text pastes into a NEW text block rather than the focused editor:
      // this path only runs when the canvas has focus, and a block is what
      // the canvas can hold.
      final b = app.addBlock(Block(
        type: BlockType.text,
        x: at.dx,
        y: at.dy,
        w: 360,
        content: {'text': text},
      ));
      app.select(b.id, edit: true);
      return PasteResult.text;
    }
  }
  return PasteResult.nothing;
}

String _mimeOf(FileFormat fmt) {
  if (fmt == Formats.jpeg) return 'image/jpeg';
  if (fmt == Formats.gif) return 'image/gif';
  if (fmt == Formats.webp) return 'image/webp';
  return 'image/png';
}

Future<Uint8List?> _readFile(ClipboardReader reader, FileFormat fmt) async {
  final completer = Completer<Uint8List?>();
  reader.getFile(fmt, (file) async {
    try {
      completer.complete(await file.readAll());
    } catch (_) {
      completer.complete(null);
    }
  }, onError: (_) => completer.complete(null));
  return completer.future;
}

/// Handle files dropped onto the canvas at [at].
///
/// Images become image blocks, everything else an attachment — dropping a PDF
/// or a lab handout onto a page and having it just be there is most of why
/// drag-and-drop matters.
Future<int> dropFilesOntoCanvas(
    AppState app, List<String> paths, Offset at) async {
  var placed = 0;
  var offset = 0.0;
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = await file.readAsBytes();
    final name = path.split(Platform.pathSeparator).last;
    // Cascade multiple drops so they don't land exactly on top of each other.
    final where = at + Offset(offset, offset);
    _looksLikeImage(name)
        ? insertImageBytes(app, bytes, mimeForExtension(name), where)
        : insertFileBytes(app, bytes, name, where);
    offset += 24;
    placed++;
  }
  return placed;
}
