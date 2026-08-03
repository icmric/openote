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

import '../editor/text_block_view.dart';
import '../model/models.dart';
import '../model/tags.dart';
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

/// Put an image INTO the text box under [pagePt], in the flow of the writing.
///
/// **Why this exists.** Every insertion path used to make a standalone image
/// block, so dropping a picture onto a note laid an opaque, higher-z block
/// over it that swallowed clicks on the text underneath — "I can't type into
/// this box with the image". An image block has no text buffer and no editor,
/// so there was literally nothing to type into.
///
/// In flow, the picture is `![](sha256:…)` — ordinary characters in the
/// block's own Markdown. That is what makes the whole select/cut/move/paste
/// story work with no new code: it is text, so the field's own selection,
/// Ctrl+X and Ctrl+V handle it, and the blob store is content-addressed and
/// never garbage-collected, so a reference cut and pasted minutes later still
/// resolves.
///
/// Returns the block it went into, or null when the drop missed every text
/// box (the caller then falls back to [insertImageBytes]).
Block? insertImageIntoTextAt(
    AppState app, Uint8List bytes, String mime, Offset pagePt,
    {required bool dark}) {
  final target = _textBlockAt(app, pagePt);
  if (target == null) return null;
  final hash = app.addBlob(bytes, mime);
  final ref = '![](sha256:$hash)';

  // Editing that very block? Then the caret is the truth, and AppState already
  // owns undo + commit + notify for that path.
  if (app.editingBlockId == target.id) {
    app.insertTextAtActiveCursor('\n$ref\n');
    target.content['autoWidth'] = false;
    return target;
  }

  final text = target.content['text'] as String? ?? '';
  final at = _offsetInBlock(target, text, pagePt, dark: dark);
  app.pushUndo();
  final (spliced, addedAt) = spliceImageOnOwnLine(text, at, ref);
  target.content['text'] = spliced;
  // A `![](sha256:…)` reference must sit alone on its line to render (it is
  // matched line-anchored), so the splice inserts lines — and every tag at or
  // below that point now decorates the wrong line unless it is re-based.
  _rebaseTags(target, fromLine: addedAt.line, by: addedAt.linesAdded);
  // Auto-width measures the RAW markdown, and a 64-hex-character line would
  // pin the box to its maximum width the moment the image landed.
  target.content['autoWidth'] = false;
  app.updateBlock(target);
  app.select(target.id);
  return target;
}

/// Topmost text block containing [pagePt], mirroring the canvas's own
/// hit-testing (z order, with `renderSizes` supplying auto-height).
Block? _textBlockAt(AppState app, Offset pagePt) {
  final hits = [
    for (final b in app.blocks)
      if (b.type == BlockType.text &&
          Rect.fromLTWH(b.x, b.y, b.w,
                  b.h ?? app.renderSizes[b.id]?.height ?? 60)
              .contains(pagePt))
        b
  ]..sort((a, b) => b.z.compareTo(a.z));
  return hits.firstOrNull;
}

/// Where in the block's text a page point lands.
int _offsetInBlock(Block b, String text, Offset pagePt, {required bool dark}) {
  final inset = TextBlockView.insetFor(b);
  final style = TextBlockView.baseStyle(b, dark: dark);
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: null,
  )..layout(maxWidth: (b.w - inset.horizontal).clamp(20, double.infinity));
  final local = pagePt - Offset(b.x + inset.left, b.y + inset.top);
  final pos = tp.getPositionForOffset(local);
  tp.dispose();
  return pos.offset.clamp(0, text.length);
}

/// Splice [ref] into [text] near [at], on a line of its own.
///
/// Own line because the renderer matches an image reference line-anchored: one
/// sharing a line with prose renders as literal `![](sha256:…)` source, which
/// would be a new kind of junk rather than a picture.
///
/// Returns the new text plus where it landed, so the block's tags can be
/// re-based over the lines that just appeared.
(String, ({int line, int linesAdded})) spliceImageOnOwnLine(
    String text, int at, String ref) {
  // Snap out to the nearer line boundary: a drop in the middle of a word
  // should not cut the word in half.
  at = at.clamp(0, text.length);
  final nextBreak = text.indexOf('\n', at);
  final prevBreak = at == 0 ? -1 : text.lastIndexOf('\n', at - 1);
  final toNext = nextBreak < 0 ? text.length - at : nextBreak - at;
  final toPrev = prevBreak < 0 ? at : at - prevBreak;
  final cut = toNext <= toPrev
      ? (nextBreak < 0 ? text.length : nextBreak)
      : (prevBreak < 0 ? 0 : prevBreak);

  final head = text.substring(0, cut);
  final tail = text.substring(cut);
  final needsLeading = head.isNotEmpty && !head.endsWith('\n');
  final needsTrailing = tail.isNotEmpty && !tail.startsWith('\n');
  final insert = '${needsLeading ? '\n' : ''}$ref${needsTrailing ? '\n' : ''}';
  final refLine =
      '\n'.allMatches(needsLeading ? '$head\n' : head).length;
  return (
    head + insert + tail,
    (line: refLine, linesAdded: '\n'.allMatches(insert).length),
  );
}

/// Shift tag line indices at or below [fromLine] down by [by].
///
/// Tags record a 0-based line index, and nothing re-bases them when lines are
/// inserted. This is the first code that inserts whole lines programmatically,
/// so it is the first place the omission would be visible — every tag below
/// the picture would suddenly decorate the wrong sentence.
void _rebaseTags(Block b, {required int fromLine, required int by}) {
  if (by <= 0) return;
  final tags = NoteTag.listFrom(b.content);
  if (tags.isEmpty) return;
  NoteTag.writeInto(b.content, [
    for (final t in tags)
      if (t.line >= fromLine)
        NoteTag(
            kind: t.kind, line: t.line + by, checked: t.checked, label: t.label)
      else
        t
  ]);
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
Future<PasteResult> pasteOntoCanvas(AppState app, Offset at,
    {bool dark = false}) async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) return PasteResult.nothing; // unsupported platform
  final reader = await clipboard.read();

  for (final fmt in [Formats.png, Formats.jpeg, Formats.gif, Formats.webp]) {
    if (!reader.canProvide(fmt)) continue;
    final bytes = await _readFile(reader, fmt);
    if (bytes == null || bytes.isEmpty) continue;
    // Into the text box under the cursor when there is one — a screenshot
    // pasted onto a note belongs IN the note, not floating over it.
    if (insertImageIntoTextAt(app, bytes, _mimeOf(fmt), at, dark: dark) == null) {
      insertImageBytes(app, bytes, _mimeOf(fmt), at);
    }
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
        if (!_looksLikeImage(name)) {
          insertFileBytes(app, bytes, name, at);
        } else if (insertImageIntoTextAt(app, bytes, mimeForExtension(name), at,
                dark: dark) ==
            null) {
          insertImageBytes(app, bytes, mimeForExtension(name), at);
        }
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

/// The clipboard's image, if it holds one.
///
/// Separate from [pasteOntoCanvas] because the caret path needs the bytes
/// rather than a block: pasting a screenshot into the text box you are typing
/// in must land IN the text, not as a picture floating over it.
Future<({Uint8List bytes, String mime})?> readClipboardImage() async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) return null;
  final reader = await clipboard.read();
  for (final fmt in [Formats.png, Formats.jpeg, Formats.gif, Formats.webp]) {
    if (!reader.canProvide(fmt)) continue;
    final bytes = await _readFile(reader, fmt);
    if (bytes == null || bytes.isEmpty) continue;
    return (bytes: bytes, mime: _mimeOf(fmt));
  }
  return null;
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
    AppState app, List<String> paths, Offset at, {bool dark = false}) async {
  var placed = 0;
  var offset = 0.0;
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = await file.readAsBytes();
    final name = path.split(Platform.pathSeparator).last;
    // Cascade multiple drops so they don't land exactly on top of each other.
    final where = at + Offset(offset, offset);
    if (!_looksLikeImage(name)) {
      insertFileBytes(app, bytes, name, where);
    } else if (insertImageIntoTextAt(app, bytes, mimeForExtension(name), where,
            dark: dark) ==
        null) {
      insertImageBytes(app, bytes, mimeForExtension(name), where);
    }
    offset += 24;
    placed++;
  }
  return placed;
}
