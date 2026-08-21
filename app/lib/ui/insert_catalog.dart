/// **Everything you can add to a page, defined once.**
///
/// The owner's report: *"In insert, we have some redundant options (such as
/// text box, that doesnt need to be there), and it also just feels kinda
/// messy at the moment"*, and of the canvas's right-click menu, *"this should
/// more closley match the insert menu we already have"*.
///
/// The two surfaces had drifted because each carried its own copy of the
/// work. `_insertTable` on the ribbon and `case 'table'` in the menu both
/// spelled out the literal `[['Header','Header'],['','']]`; board and page
/// window were duplicated the same way; and the menu had a CSV importer the
/// ribbon did not while the ribbon had eight things the menu did not. This
/// file is the single list they now both render, so "the menu matches Insert"
/// is true by construction rather than by anyone remembering.
///
/// **What is NOT here, and why.**
///  * *Text box* — a plain left click on the canvas already makes one, and
///    the Draw tab's `T` is the deliberate version. A third route to the same
///    block is most of what "messy" was.
///  * *Flashcard* — Home's own card button reads the line you are on, which
///    is strictly better than dropping an empty `?[Question](Answer)`
///    somewhere else on the page.
///  * *Apply a template* — laying out a whole page is not adding something to
///    it. It lives beside `Save as template…` in the page's own menu, which
///    is where its own "no templates yet" message already sends people.
///  * *Graph* — a graph is a graph OF something, and a blank one would be a
///    box with nothing to edit: a graph has no editor of its own, it follows
///    an equation. The route is the equation's own `⋯` menu, "Draw the
///    graph", which is the same one press whether the equation is in a box or
///    in a sentence.
///
/// ### Where the thing lands
///
/// The ribbon centres it on what you are looking at; a right-click puts its
/// corner where you clicked. Both are the one [InsertRun] with a different
/// [InsertItem.size]-derived anchor — see [insertAnchor] — which is how the
/// ribbon's old hand-written offsets (`c.dx - 180, c.dy - 30` and nine
/// others) turn into one rule.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../canvas/media_drop.dart';
import '../editor/board_block_view.dart';
import '../export/csv_import.dart';
import '../export/pdf_import.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../store/media_store.dart';
import 'insert_portal_dialog.dart';
import 'media_link_dialog.dart';
import 'onote_dialog.dart';

/// Put one thing on the page. [at] is the top-left the block should take.
typedef InsertRun = Future<void> Function(
    BuildContext context, AppState app, Offset at);

/// One thing a student can add.
class InsertItem {
  const InsertItem({
    required this.id,
    required this.icon,
    required this.label,
    required this.size,
    required this.run,
    this.tooltip,
    this.opensPicker = false,
    this.showLabel = true,
    this.extras = const [],
  });

  final String id;
  final IconData icon;

  /// The word on the button. One noun, the one a fifteen-year-old would use.
  final String label;

  /// Roughly how big the thing arrives. Only used to decide where it lands:
  /// a ribbon press centres it on the view, a right-click puts its corner
  /// under the pointer.
  final Size size;

  /// A dialog or a file picker follows, so the label ends in an ellipsis.
  final bool opensPicker;

  /// **Does the ribbon print the word, or is the icon enough?**
  ///
  /// `command_button.dart` already states the rule — *"use wherever an
  /// `IconButton` would be used but the icon alone is not self-explanatory"* —
  /// and the Insert row was breaking it by labelling all thirteen of its
  /// commands. That cost 1362 px of a 965 px row, which put the two least
  /// familiar entries, Page link and Page window, off the right-hand edge of a
  /// 1280 window where nobody would ever find them.
  ///
  /// So a paperclip, a play button, a picture and a PDF badge stand on their
  /// own — they are the same glyphs every application on the machine uses —
  /// while a sigma, a kanban board, a chain link and a picture-in-picture
  /// frame get a word, because none of those says what it makes. Every
  /// wordless one carries its name in its tooltip; nothing is nameless.
  ///
  /// A menu always prints the word: there is no width to save there, and a
  /// column of bare icons is unreadable.
  final bool showLabel;

  /// The extra choices behind a split button's arrow. A plain menu ignores
  /// these and offers the main action only, which is the right default in
  /// every case here.
  final List<InsertItem> extras;

  /// The second line, for a hover. Never repeats the label.
  final String? tooltip;

  final InsertRun run;

  /// The label as it is written in a menu, where an ellipsis is the
  /// convention for "something else opens".
  String get menuLabel => opensPicker ? '$label…' : label;
}

/// A named run of items. The title is shown as a column head in the menu and
/// as nothing at all on the ribbon, where the dividers do the same job
/// without spending a row of height on words.
class InsertGroup {
  const InsertGroup({required this.title, required this.items});
  final String title;
  final List<InsertItem> items;
}

/// Where a ribbon press should put [item] — centred on what you are looking
/// at, which is what every Insert button has always done.
Offset insertAnchor(AppState app, InsertItem item) {
  final c = app.canvas.screenToPage(
      Offset(app.canvas.viewport.width / 2, app.canvas.viewport.height / 2));
  return Offset(c.dx - item.size.width / 2, c.dy - item.size.height / 2);
}

/// Every item, flattened, in the order the groups list them.
List<InsertItem> get kInsertItems =>
    [for (final g in kInsertGroups) ...g.items];

/// The same, with each item's own second choices after it.
///
/// The ribbon shows an extra behind a small arrow; the right-click menu shows
/// it as an indented line. Either way it is the same command, and both
/// surfaces read it from here — which is the whole point of this file, and
/// was quietly untrue for as long as "Table ▸ From a file" existed on one
/// and not the other.
List<InsertItem> get kInsertItemsAndExtras =>
    [for (final i in kInsertItems) ...[i, ...i.extras]];

/// The catalog.
///
/// Three groups, because three is the number of genuinely different things a
/// student is doing: making something to fill in, bringing something in from
/// elsewhere, and pointing at something that already exists.
final List<InsertGroup> kInsertGroups = [
  InsertGroup(title: 'Write', items: [
    InsertItem(
      id: 'equation',
      icon: Icons.functions,
      label: 'Equation',
      tooltip: 'Alt+=',
      size: const Size(360, 60),
      run: (context, app, at) async => app.insertEquation(at: at),
    ),
    InsertItem(
      id: 'table',
      icon: Icons.table_chart_outlined,
      label: 'Table',
      size: const Size(360, 80),
      extras: [
        InsertItem(
          id: 'table-file',
          icon: Icons.grid_on_outlined,
          label: 'From a file',
          tooltip: 'CSV or Excel',
          opensPicker: true,
          size: const Size(360, 80),
          run: insertTableFromPickedFile,
        ),
      ],
      run: (context, app, at) async {
        final b = app.addBlock(Block(
            type: BlockType.table,
            x: at.dx,
            y: at.dy,
            w: 360,
            content: {
              'cells': [
                ['Header', 'Header'],
                ['', ''],
              ]
            }));
        app.select(b.id, edit: true);
      },
    ),
    InsertItem(
      id: 'code',
      icon: Icons.code,
      label: 'Code',
      showLabel: false,
      size: const Size(400, 80),
      run: (context, app, at) async {
        final b = app.addBlock(Block(
            type: BlockType.code,
            x: at.dx,
            y: at.dy,
            w: 400,
            content: {'language': 'text', 'source': ''}));
        app.select(b.id, edit: true);
      },
    ),
    InsertItem(
      id: 'board',
      icon: Icons.view_kanban_outlined,
      label: 'Board',
      tooltip: 'Columns of cards you move along',
      size: const Size(700, 200),
      run: (context, app, at) async {
        final b = app.addBlock(Block(
          type: BlockType.board,
          x: at.dx,
          y: at.dy,
          w: 700,
          content: BoardBlockView.starterContent(),
        ));
        app.select(b.id);
      },
    ),
  ]),
  InsertGroup(title: 'Bring in', items: [
    InsertItem(
      id: 'image',
      icon: Icons.image_outlined,
      // "Picture", not "Image": one is a word a student uses.
      label: 'Picture',
      showLabel: false,
      opensPicker: true,
      size: const Size(320, 240),
      run: insertPickedImage,
    ),
    InsertItem(
      id: 'pdf',
      icon: Icons.picture_as_pdf_outlined,
      label: 'PDF slides',
      showLabel: false,
      opensPicker: true,
      size: Size.zero, // it lays itself out down the page
      extras: [
        InsertItem(
          id: 'pdf-here',
          icon: Icons.vertical_align_bottom,
          label: 'Printout on this page',
          opensPicker: true,
          size: Size.zero,
          run: (c, a, at) =>
              importPdfWithProgress(c, a, placement: PdfPlacement.currentPage),
        ),
        InsertItem(
          id: 'pdf-pages',
          icon: Icons.auto_stories_outlined,
          label: 'One page per slide',
          opensPicker: true,
          size: Size.zero,
          run: (c, a, at) =>
              importPdfWithProgress(c, a, placement: PdfPlacement.pagePerSlide),
        ),
        InsertItem(
          id: 'pdf-card',
          icon: Icons.branding_watermark_outlined,
          label: 'As a card — open in a popup',
          opensPicker: true,
          size: Size.zero,
          run: (c, a, at) =>
              importPdfWithProgress(c, a, placement: PdfPlacement.card),
        ),
      ],
      run: (c, a, at) =>
          importPdfWithProgress(c, a, placement: PdfPlacement.currentPage),
    ),
    InsertItem(
      id: 'video',
      icon: Icons.play_circle_outline,
      label: 'Video',
      tooltip: 'A lecture recording, or any web link',
      showLabel: false,
      opensPicker: true,
      size: const Size(340, 56),
      run: insertVideoOrLink,
    ),
    InsertItem(
      id: 'file',
      icon: Icons.attach_file,
      label: 'File',
      showLabel: false,
      opensPicker: true,
      size: const Size(280, 48),
      run: insertPickedFile,
    ),
  ]),
  InsertGroup(title: 'Link up', items: [
    InsertItem(
      id: 'pagelink',
      icon: Icons.link,
      label: 'Page link',
      opensPicker: true,
      size: const Size(240, 40),
      run: insertPageLink,
    ),
    InsertItem(
      id: 'portal',
      icon: Icons.picture_in_picture_alt_outlined,
      label: 'Page window',
      opensPicker: true,
      size: const Size(380, 260),
      run: (context, app, at) => showInsertPortalDialog(context, app, at),
    ),
  ]),
];

// ── The actions that need more than three lines ─────────────────────────────
//
// Every one of these keeps the "face the failure" rule the ribbon already had:
// a picker that cannot open, or a write that throws, says so on screen. A menu
// item that silently does nothing is indistinguishable from a broken app.

/// Tell the user something went wrong, if there is still a screen to tell.
void _say(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}

Future<XFile?> _pick(BuildContext context,
    {List<XTypeGroup> groups = const []}) async {
  try {
    return await openFile(acceptedTypeGroups: groups);
  } catch (e) {
    _say(context, "Couldn't open the file picker: $e");
    return null;
  }
}

Future<void> insertPickedImage(
    BuildContext context, AppState app, Offset at) async {
  final file = await _pick(context, groups: const [
    XTypeGroup(
        label: 'Images', extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'])
  ]);
  if (file == null) return;
  final Uint8List bytes = await file.readAsBytes();
  final ext = file.name.split('.').last.toLowerCase();
  final mime = switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    _ => 'image/png',
  };
  // Caret first. If a text box has focus the picture belongs IN it, in the
  // flow of the writing — the same thing paste and drag-and-drop already do.
  if (insertImageAtCaret(app, bytes, mime) != null) return;

  // `tryAddBlob`: a full disk or read-only folder throws out of `writeBlob`
  // synchronously, and a block referencing unstored bytes must not be made.
  final hash = app.tryAddBlob(bytes, mime);
  if (hash == null) return;
  final b = app.addBlock(Block(
      type: BlockType.image,
      x: at.dx,
      y: at.dy,
      w: 320,
      content: {'blob': 'sha256:$hash', 'mime': mime}));
  app.select(b.id);
}

Future<void> insertPickedFile(
    BuildContext context, AppState app, Offset at) async {
  final file = await _pick(context);
  if (file == null) return;
  final Uint8List bytes = await file.readAsBytes();
  final hash = app.tryAddBlob(bytes, 'application/octet-stream');
  if (hash == null) return;
  final b = app.addBlock(Block(
      type: BlockType.file,
      x: at.dx,
      y: at.dy,
      w: 280,
      content: {
        'blob': 'sha256:$hash',
        'name': file.name,
        'mime': 'application/octet-stream',
        'size': bytes.length,
      }));
  app.select(b.id);
}

Future<void> insertTableFromPickedFile(
    BuildContext context, AppState app, Offset at) async {
  final file = await _pick(context, groups: const [
    XTypeGroup(label: 'Tables', extensions: ['csv', 'tsv', 'xlsx'])
  ]);
  if (file == null) return;
  final bytes = await file.readAsBytes();
  final r = insertTableFromFile(app, file.name, bytes, at);
  if (!context.mounted) return;
  if (!r.placed) {
    _say(context, 'That file has no rows in it.');
  } else if (r.note != null) {
    _say(context, r.note!);
  }
}

/// MEDIA-7: embed a lecture recording (or any link) as a card in the page.
///
/// A link, not a copy. A lecture video is hundreds of megabytes, and blobs
/// live in the container AND — once a notebook is shared — in
/// `.onotebook/blobs/`; putting one in would undo the storage work of v0.10 in
/// a single drag. A URL is a few dozen bytes and is machine-independent.
Future<void> insertVideoOrLink(
    BuildContext context, AppState app, Offset at) async {
  final result = await showOnoteDialog<MediaChoice>(
    context: context,
    builder: (_) => const MediaLinkDialog(),
  );
  if (result == null) return;
  if (result.pickFile) {
    if (context.mounted) await copyVideoIntoNotebook(context, app, at);
    return;
  }
  final b = app.addBlock(Block(
    type: BlockType.file,
    x: at.dx,
    y: at.dy,
    w: 340,
    content: {
      'url': result.url!,
      'name': result.name!,
      // A hint for the icon, never load-bearing: an older build ignores it,
      // and a card whose `kind` is wrong is still a working link.
      'kind': looksLikeVideo(result.url!) ? 'video' : 'link',
    },
  ));
  app.select(b.id);
}

bool looksLikeVideo(String url) {
  final u = url.toLowerCase();
  return u.contains('youtube.com') ||
      u.contains('youtu.be') ||
      u.contains('vimeo.com') ||
      u.contains('echo360') ||
      u.contains('panopto') ||
      RegExp(r'\.(mp4|mov|mkv|webm|m4v)(\?|$)').hasMatch(u);
}

/// Copy a video or recording from this computer INTO the notebook.
///
/// *"i do really want the ability to put in my own custom videos, even if it
/// will chew through storage."* It genuinely will: the file is copied whole
/// and kept. That is the deal the dialog states before the picker opens, and
/// the reason the copy shows its progress rather than looking like a freeze.
Future<void> copyVideoIntoNotebook(
    BuildContext context, AppState app, Offset at) async {
  final picked = await _pick(context, groups: [
    const XTypeGroup(
        label: 'Video and audio',
        extensions: [...kVideoExtensions, ...kAudioExtensions]),
  ]);
  if (picked == null) return;
  final chosen = picked;
  final source = File(chosen.path);
  final size = await source.length();
  if (!context.mounted) return;
  final progress = ValueNotifier<double>(0);
  var cancelled = false;
  var dialogOpen = true;
  unawaited(showOnoteDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => MediaCopyDialog(
      name: chosen.name,
      bytes: size,
      progress: progress,
      onCancel: () {
        cancelled = true;
        Navigator.of(ctx).pop();
      },
    ),
  ).then((_) => dialogOpen = false));

  try {
    final stored = await MediaStore.add(
      app.currentNotebook,
      source,
      onProgress: (f) => progress.value = f,
      isCancelled: () => cancelled,
    );
    if (dialogOpen && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      dialogOpen = false;
    }
    final b = app.addBlock(Block(
      type: BlockType.file,
      x: at.dx,
      y: at.dy,
      w: 420,
      h: 240,
      content: {
        'kind': 'video',
        'media': stored,
        'name': chosen.name,
        'mime':
            mimeForMediaExtension(chosen.path) ?? 'application/octet-stream',
        'size': size,
      },
    ));
    app.select(b.id);
  } on MediaCopyCancelled {
    // Nothing to report: the user asked for this, and MediaStore already
    // removed the partial file.
  } catch (e) {
    if (dialogOpen && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    _say(context, "That video couldn't be copied in: $e");
  } finally {
    progress.dispose();
  }
}

Future<void> insertPageLink(
    BuildContext context, AppState app, Offset at) async {
  final pages = app.pages.where((p) => p.id != app.pageId).toList();
  if (pages.isEmpty) {
    _say(context, 'No other pages to link to yet.');
    return;
  }
  final choice = await showOnoteDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Link to page'),
      children: [
        for (final p in pages)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, p.id),
            child: Row(children: [
              const Icon(Icons.description_outlined, size: 16),
              const SizedBox(width: 8),
              Flexible(child: Text(p.title, overflow: TextOverflow.ellipsis)),
            ]),
          ),
      ],
    ),
  );
  if (choice == null) return;
  // If a text box is being edited, insert inline at the caret; otherwise drop
  // a new link block.
  if (app.activeEditor != null && app.canFormatText) {
    final title = app.node(choice)?.title ?? 'page';
    app.insertTextAtActiveCursor('[[$title|$choice]]');
  } else {
    app.insertPageLink(choice);
  }
}

/// Import a PDF, with progress.
///
/// A lecture deck is 40–120 pages and each one is a pdfium render plus a PNG
/// encode, so this is seconds, not milliseconds — a modal with a live count is
/// the difference between "working" and "frozen".
Future<void> importPdfWithProgress(BuildContext context, AppState app,
    {PdfPlacement placement = PdfPlacement.currentPage}) async {
  final progress = ValueNotifier<String>('Opening PDF…');
  var dialogOpen = false;
  if (context.mounted) {
    dialogOpen = true;
    showOnoteDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.6)),
          const SizedBox(width: 16),
          Expanded(
            child: ValueListenableBuilder<String>(
              valueListenable: progress,
              builder: (_, text, __) => Text(text),
            ),
          ),
        ]),
      ),
    );
  }
  try {
    final result = await importPdfAsPages(
      app,
      placement: placement,
      onProgress: (done, total) =>
          progress.value = 'Importing page $done of $total…',
    );
    if (dialogOpen && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      dialogOpen = false;
    }
    if (result == null) return; // cancelled at the file picker
    if (!context.mounted) return;
    if (result.pages == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("That PDF couldn't be read.")));
      return;
    }
    // Only navigate for the page-per-slide import — a printout landed on the
    // page you are already looking at, and jumping would be disorienting.
    if (result.sectionId != null && result.firstPageId != null) {
      await app.selectPage(result.firstPageId!);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      content: Text('Imported ${result.pages} '
          '${result.pages == 1 ? 'slide' : 'slides'}'
          '${result.sectionId == null ? ' onto this page' : ''} — pick the pen '
          'and write on them. The slide text is searchable.'),
    ));
  } catch (e) {
    if (dialogOpen && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('PDF import failed: $e')));
    }
  } finally {
    progress.dispose();
  }
}
