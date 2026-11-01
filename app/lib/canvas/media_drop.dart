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
import '../export/csv_import.dart';
import '../math/math_view.dart';
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

/// What counts as a picture when a file arrives by drop or by paste.
///
/// **SVG is one of them** (GitHub #10, promised for this release): a drawing
/// is a picture, and before this a dropped .svg became an attachment chip — a
/// file you could open in something else, on a page that could have drawn it.
/// Nothing else about the path changes, because an SVG blob is referenced the
/// same way a PNG blob is and the renderers ask the bytes which they have.
const _imageExtensions = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg'};

bool _looksLikeImage(String name) =>
    _imageExtensions.contains(name.split('.').last.toLowerCase());

/// **A picture with no box to go in makes one**, at [at] (page coordinates).
///
/// The last of the four routes that still made a standalone `BlockType.image`.
/// Reported by the owner: *"Dragging and dropping an image onto the canvas
/// inserts it as the old discontinued image format rather than the more
/// scalable one which inlines with text. I think the best way to fix this
/// would be to create a regular content box and just insert the image in
/// there."* Quite so, and it is also the answer the plan had already reached
/// (v1.0.2 §3): there is then exactly ONE shape a picture has on a page —
/// `![](sha256:…)` in a text block's own Markdown — and *"1 single unified way
/// of managing any type of data on the page"* is true rather than nearly true.
///
/// What that buys, which is the whole reason: the box can be typed into, so a
/// picture dropped on empty canvas is the start of a note rather than an
/// opaque thing sitting on one. Select, cut, copy, paste and move are the
/// field's own, because the picture is characters. And an image block had no
/// text buffer, which is what made *"I can't type into this box with the
/// image"* literally true.
///
/// Null when the bytes could not be stored (full disk, read-only folder):
/// the failure is already on the status bar via `AppState.saveError`, and a
/// block referencing bytes nothing holds would render as a broken picture
/// that LOOKS like the paste worked.
Block? insertImageInNewBox(AppState app, Uint8List bytes, String mime, Offset at,
    {double width = 320}) {
  final hash = app.tryAddBlob(bytes, mime);
  if (hash == null) return null;
  final b = app.addBlock(Block(
    type: BlockType.text,
    x: at.dx - width / 2,
    // The same geometry the image block used, so a picture still lands where
    // it was dropped rather than hanging below the pointer.
    y: at.dy - width * 0.375,
    w: width,
    // **No `h`**: the box measures itself round the picture, which is what an
    // image block's null height did by aspect ratio. And `autoWidth: false`,
    // because auto-width measures the RAW markdown and eighty characters of
    // hash would pin the box to its maximum width.
    content: {'text': '![](sha256:$hash)', 'autoWidth': false},
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
/// box (the caller then falls back to [insertImageInNewBox]).
/// Put an image into the text box that is being edited RIGHT NOW, at the
/// caret. Returns the block it went into, or null when nothing editable has
/// focus — the caller then falls back to making a standalone image block.
///
/// Exists because "insert an image" arrived by four routes and only three of
/// them could do this. Ctrl+V at the caret, Ctrl+V on the canvas and
/// drag-and-drop all inline; **Insert ▸ Image never did** — it hard-coded a
/// standalone block at the page centre and never looked at the caret. That is
/// the discoverable route, the one a menu-first user takes, so from the menu
/// the answer to "can I have text and a picture in one box?" was simply no.
Block? insertImageAtCaret(AppState app, Uint8List bytes, String mime) {
  final ae = app.activeEditor;
  if (ae == null) return null;
  final target = ae.block;
  if (target.type != BlockType.text) return null;
  // `tryAddBlob` BEFORE the splice: a write that fails (full disk, read-only
  // folder) is already on the status bar, and splicing a reference to bytes
  // nothing holds would leave a broken picture that looks like it worked.
  final hash = app.tryAddBlob(bytes, mime);
  if (hash == null) return null;
  // AppState owns undo, commit and notify for the caret path.
  app.insertTextAtActiveCursor('\n![](sha256:$hash)\n');
  // Auto-width measures the RAW markdown, and a 64-hex-character line would
  // pin the box to its maximum width the moment the image landed.
  target.content['autoWidth'] = false;
  return target;
}

Block? insertImageIntoTextAt(
    AppState app, Uint8List bytes, String mime, Offset pagePt,
    {required bool dark}) {
  final target = _textBlockAt(app, pagePt);
  if (target == null) return null;
  // Same rule as [insertImageAtCaret]: no reference to bytes that were never
  // stored. The caller's fallback to [insertImageInNewBox] fails the same way
  // and the notice is already up.
  final hash = app.tryAddBlob(bytes, mime);
  if (hash == null) return null;
  final ref = '![](sha256:$hash)';

  // Editing that very block? Then the caret is the truth, and AppState already
  // owns undo + commit + notify for that path.
  //
  // **Asked of the registered editor, not of `editingBlockId`.** The two are
  // one frame apart: the click sets `editingBlockId`, and `TextBlockView`
  // registers the controller when it next builds. In between — and while the
  // caret is moving from one box to another, where the registration is still
  // the box you left — `editingBlockId` names this block while `activeEditor`
  // names another one, and `insertTextAtActiveCursor` would splice the
  // picture into THAT box's text. The branch below is no good either: the
  // open controller holds the live text and would write over anything put
  // into `content` behind it. So the honest answer in that window is "not
  // this box", and the caller puts the picture in a box of its own.
  final ae = app.activeEditor;
  if (ae != null && ae.block.id == target.id) {
    app.insertTextAtActiveCursor('\n$ref\n');
    target.content['autoWidth'] = false;
    return target;
  }
  if (app.editingBlockId == target.id) return null;

  final text = target.content['text'] as String? ?? '';
  final at = _offsetInBlock(target, text, pagePt, dark: dark);
  app.pushUndo();
  final (spliced, _) = spliceImageOnOwnLine(text, at, ref);
  target.content['text'] = spliced;
  // A `![](sha256:…)` reference must sit alone on its line to render (it is
  // matched line-anchored), so the splice inserts lines — and every tag and
  // every flashcard at or below that point is now filed under the wrong line
  // unless it is moved. The editor's own matching, so a dropped picture and a
  // typed Enter can never disagree: it had a copy of its own that moved the
  // tags and not the cards' schedules, and rebuilt each tag without its
  // deadline, so a picture dropped above a dated task cleared the date.
  NoteTag.rebase(target.content, text, spliced);
  app.study.remapCardStates(target.id, NoteTag.lineMoves(text, spliced));
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

/// Insert a non-image file as an attachment block.
///
/// Null on a failed write, like [insertImageInNewBox] — an attachment chip whose
/// bytes were never stored is a file the user believes is kept and is not.
Block? insertFileBytes(
    AppState app, Uint8List bytes, String name, Offset at) {
  final mime = mimeForExtension(name);
  final hash = app.tryAddBlob(bytes, mime);
  if (hash == null) return null;
  final b = app.addBlock(Block(
    type: BlockType.file,
    x: at.dx - 110,
    y: at.dy - 24,
    // A PDF renders as a thumbnail card (FileBlockView keys on the mime), so
    // it gets card width; anything else stays a compact attachment chip.
    w: mime == 'application/pdf' ? 300 : 220,
    content: {
      'blob': 'sha256:$hash',
      'name': name,
      'mime': mime,
      'size': bytes.length,
    },
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
      insertImageInNewBox(app, bytes, _mimeOf(fmt), at);
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
          insertImageInNewBox(app, bytes, mimeForExtension(name), at);
        }
        return PasteResult.files;
      }
    }
  }

  if (reader.canProvide(Formats.plainText)) {
    final text = await reader.readValue(Formats.plainText);
    if (text != null && text.trim().isNotEmpty) {
      insertPastedText(app, text, at);
      return PasteResult.text;
    }
  }
  return PasteResult.nothing;
}

/// Paste [text] onto the page at [at]: a MATHS block when the text IS an
/// equation, an ordinary text block otherwise.
///
/// The maths branch is what stops pasting `$\frac{1}{2}$` from landing as a
/// text block showing raw LaTeX source — the one thing the equation editor
/// promised nobody would have to read. `looksLikeMaths` is deliberately
/// narrow (a sentence with two prices in it stays a sentence), and `unwrap`
/// strips the `$…$` so the stored latex is exactly what typing it into the
/// equation editor would have stored.
Block insertPastedText(AppState app, String text, Offset at) {
  if (MathClipboard.looksLikeMaths(text)) {
    // Mirrors AppState.insertEquation — same width, selected and open for
    // editing — so a pasted equation IS the block the equation button makes,
    // not a lookalike that drifts when the real one changes.
    final b = app.addBlock(Block(
      type: BlockType.math,
      x: at.dx,
      y: at.dy,
      w: 360,
      content: {'latex': MathClipboard.unwrap(text), 'display': true},
    ));
    app.select(b.id, edit: true);
    return b;
  }
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
  return b;
}

/// What the system clipboard is offering, read WITHOUT inserting anything.
///
/// Exists for one decision: a canvas Ctrl+V has two clipboards to choose
/// between — the system's and the app's own cut/copied blocks — and it must
/// know what the system holds before letting either act. [pasteOntoCanvas]
/// cannot answer that question, because by the time it has answered it has
/// already pasted. Kinds mirror [pasteOntoCanvas]'s priority order exactly:
/// a clipboard holding both an image and text reports the image, because
/// that is what would paste.
///
/// [plainText] is a different question, and it has to be answered separately:
/// **whatever plain text the clipboard holds, whether or not an image beat it
/// to the kind.** It is what `AppState.blockClipboardIsNewer` compares
/// against, and that comparison's other side — the snapshot taken when the
/// boxes were copied — reads the plain text unconditionally. Reporting null
/// here for a clipboard holding BOTH (a picture copied from a web page, a
/// spreadsheet cell, a document — the common case, not a corner) made the two
/// sides disagree: `null` never equals the text that is really there, so the
/// boxes were ruled stale and Ctrl+V in a box pasted the clipboard's picture
/// instead of the box that had just been cut.
Future<({PasteResult kind, String? text, String? plainText})>
    probeClipboard() async {
  final reader = await _readClipboard();
  const nothing = (kind: PasteResult.nothing, text: null, plainText: null);
  if (reader == null) return nothing;
  String? plain;
  if (reader.canProvide(Formats.plainText)) {
    final t = await reader.readValue(Formats.plainText);
    if (t != null && t.trim().isNotEmpty) plain = t;
  }
  for (final fmt in [Formats.png, Formats.jpeg, Formats.gif, Formats.webp]) {
    if (reader.canProvide(fmt)) {
      return (kind: PasteResult.image, text: null, plainText: plain);
    }
  }
  if (reader.canProvide(Formats.fileUri)) {
    return (kind: PasteResult.files, text: null, plainText: plain);
  }
  if (plain != null) {
    return (kind: PasteResult.text, text: plain, plainText: plain);
  }
  return nothing;
}

/// The clipboard's image, if it holds one.
///
/// Separate from [pasteOntoCanvas] because the caret path needs the bytes
/// rather than a block: pasting a screenshot into the text box you are typing
/// in must land IN the text, not as a picture floating over it.
Future<({Uint8List bytes, String mime})?> readClipboardImage() async {
  final reader = await _readClipboard();
  if (reader == null) return null;
  for (final fmt in [Formats.png, Formats.jpeg, Formats.gif, Formats.webp]) {
    if (!reader.canProvide(fmt)) continue;
    final bytes = await _readFile(reader, fmt);
    if (bytes == null || bytes.isEmpty) continue;
    return (bytes: bytes, mime: _mimeOf(fmt));
  }
  return null;
}

/// **The clipboard, or null when it cannot be read right now.**
///
/// Defensive for the same reasons `AppState.readSystemClipboardText` is, and
/// it was not: an unsupported platform, a channel not yet up, a headless
/// test, or — the one that happens — another application holding the
/// clipboard open on Windows. Every caller here already treats "nothing on
/// the clipboard" as an ordinary answer, so a read that throws became an
/// unhandled exception out of a Ctrl+V that should simply have done nothing.
Future<ClipboardReader?> _readClipboard() async {
  try {
    return await SystemClipboard.instance?.read();
  } catch (e) {
    debugPrint('[openote] could not read the clipboard: $e');
    return null;
  }
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
    // Only what actually landed counts: the caller announces "Added N items"
    // on the strength of this number, and a blob write that failed (full
    // disk, read-only folder) is already on the status bar saying the
    // opposite.
    var landed = false;
    if (looksLikeCsv(name)) {
      // Tabular data becomes a TABLE, not an attachment — "import data
      // (csv, xlsx)" means the rows end up editable on the page, the same
      // block the table button makes. An unusable file falls back to an
      // attachment, so the drop never simply vanishes.
      landed = insertTableFromFile(app, name, bytes, where).placed ||
          insertFileBytes(app, bytes, name, where) != null;
    } else if (!_looksLikeImage(name)) {
      landed = insertFileBytes(app, bytes, name, where) != null;
    } else {
      landed = insertImageIntoTextAt(app, bytes, mimeForExtension(name), where,
              dark: dark) !=
              null ||
          insertImageInNewBox(app, bytes, mimeForExtension(name), where) != null;
    }
    if (landed) {
      offset += 24;
      placed++;
    }
  }
  return placed;
}
