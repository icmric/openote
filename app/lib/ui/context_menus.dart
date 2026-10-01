import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../canvas/portal_view.dart';
import '../media/pdf_pages.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'color_picker.dart';
import 'insert_catalog.dart';
import 'pdf_viewer_dialog.dart';
import 'save_picture.dart';

/// Right-click menus (style guide: most actions within ≤2 clicks).

/// **One right-click menu, worn by both of the things that draw one.**
///
/// The owner: *"we need to make the right click menus all the same visually,
/// we currently have 2."* Quite so — a block's menu is a Material popup with
/// icons and shortcut hints, while a text field's is Flutter's own selection
/// toolbar, which is a row of bare words. Same gesture, same kind of list,
/// two completely different objects on screen.
///
/// This gives the text field the block menu's clothes: the same surface, the
/// same 36px rows, the same icon-then-label-then-shortcut layout. It keeps
/// `DesktopTextSelectionToolbar` for the SURFACE and the positioning, because
/// a selection menu has to sit against the selection and that widget already
/// knows how — the parts worth sharing are the ones you can see.
Widget onoteTextContextMenu(
    BuildContext context, EditableTextState editable,
    List<ContextMenuButtonItem> items) {
  // **Paste is always offered, greyed when there is nothing to paste.**
  //
  // Flutter leaves the row out altogether unless the clipboard reports
  // something pasteable (`pasteEnabled` is `!readOnly && status ==
  // pasteable`), so an empty clipboard produced a menu with no Paste in it at
  // all — reported as *"the menu is also missing the option to paste which is
  // fairly major"*. Missing and disabled say very different things: one reads
  // as "this app cannot paste", the other as "there is nothing on the
  // clipboard". Every other editor on Windows shows the second.
  //
  // Only when the field could accept a paste at all; a read-only one is right
  // to say nothing.
  final rows = [...items];
  if (!editable.widget.readOnly &&
      !rows.any((i) => i.type == ContextMenuButtonType.paste)) {
    rows.add(const ContextMenuButtonItem(
        onPressed: null, type: ContextMenuButtonType.paste));
  }
  return DesktopTextSelectionToolbar(
    anchor: editable.contextMenuAnchors.primaryAnchor,
    children: [
      for (final item in rows)
        _ToolbarRow(
          icon: _iconFor(item),
          // **Not `item.label`**, which is null for every one of Flutter's own
          // items: a `ContextMenuButtonItem` carries a TYPE, and the toolbar
          // is what turns that into words in the reader's language. Falling
          // back to a placeholder labelled every standard row "More" —
          // reported as *"the tooltips for paste and select just say More
          // which seems very wrong"*. Openote's own items set a label and
          // this hands those straight back, so both kinds read properly.
          label: AdaptiveTextSelectionToolbar.getButtonLabel(context, item),
          shortcut: _shortcutFor(item),
          onPressed: item.onPressed,
        ),
    ],
  );
}

/// The icon for one toolbar row.
///
/// Flutter's own items carry a [ContextMenuButtonType], which is the reliable
/// thing to switch on. Openote's own are added by label from the editor, so
/// they are matched by label — which is fragile in general and safe here,
/// because both ends of the match live in this repository and a miss costs a
/// missing icon rather than a missing row.
IconData _iconFor(ContextMenuButtonItem item) => switch (item.type) {
      ContextMenuButtonType.cut => Icons.cut_outlined,
      ContextMenuButtonType.copy => Icons.copy_outlined,
      ContextMenuButtonType.paste => Icons.content_paste_outlined,
      ContextMenuButtonType.selectAll => Icons.select_all,
      ContextMenuButtonType.delete => Icons.delete_outline,
      ContextMenuButtonType.lookUp => Icons.search,
      ContextMenuButtonType.searchWeb => Icons.travel_explore_outlined,
      ContextMenuButtonType.share => Icons.share_outlined,
      ContextMenuButtonType.liveTextInput => Icons.text_fields,
      ContextMenuButtonType.custom => switch (item.label) {
          'Save image as…' => Icons.download_outlined,
          'Edit link…' => Icons.link,
          'Show as a page window' => Icons.picture_in_picture_alt_outlined,
          'Add to dictionary' => Icons.library_add_outlined,
          _ => Icons.spellcheck, // a spelling suggestion: the word itself
        },
    };

String? _shortcutFor(ContextMenuButtonItem item) => switch (item.type) {
      ContextMenuButtonType.cut => 'Ctrl+X',
      ContextMenuButtonType.copy => 'Ctrl+C',
      ContextMenuButtonType.paste => 'Ctrl+V',
      ContextMenuButtonType.selectAll => 'Ctrl+A',
      _ => null,
    };

/// One row, laid out exactly as [_item] lays out a block-menu row.
class _ToolbarRow extends StatelessWidget {
  const _ToolbarRow({
    required this.icon,
    required this.label,
    required this.shortcut,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String? shortcut;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        alignment: AlignmentDirectional.centerStart,
        minimumSize: const Size.fromHeight(36),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: const RoundedRectangleBorder(),
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        textStyle: const TextStyle(fontSize: 13),
      ),
      onPressed: onPressed,
      child: Row(children: [
        Icon(icon, size: 16),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        if (shortcut != null)
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: Text(shortcut!,
                style: OnoteType.caption
                    .copyWith(color: context.surfaces.textSecondary)),
          ),
      ]),
    );
  }
}

PopupMenuItem<String> _item(String v, IconData icon, String label,
    {bool enabled = true, String? shortcut}) {
  return PopupMenuItem<String>(
    value: v,
    enabled: enabled,
    height: 36,
    child: Row(children: [
      Icon(icon, size: 16),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
      if (shortcut != null)
        // A Builder because this is a top-level helper with no context of its
        // own, and the shortcut hint must follow the surface role rather than
        // hard-code a grey that fails AA in one mode or the other.
        Builder(
          builder: (context) => Text(shortcut,
              style: OnoteType.caption
                  .copyWith(color: context.surfaces.textSecondary)),
        ),
    ]),
  );
}

/// Swap a page window for a one-line link to the same page.
///
/// A replacement rather than an edit, because [Block.type] is final — and
/// that is the honest shape of it anyway: an embed and a paragraph are not
/// the same block wearing different clothes.
///
/// **The link is a wiki link, `[[Title|id]]`, and that matters.**
///
/// The first cut wrote `[Title](onote://page/id)`, which LOOKS like the right
/// answer and is not: that is the shape `md_common.markdownInline` projects a
/// page link into on the way OUT to a `.md` file. Inside the editor the
/// grammar's `_link` branch matches `https?:` and `mailto:` only, on purpose —
/// so `onote://` cannot be claimed by it and stays free for atom references.
/// A page link written that way is therefore not a link at all; it is eleven
/// characters of punctuation sitting in the sentence. The owner: *"it seems to
/// write out the markdown for it correctly but doesnt actually register it as
/// a link."*
///
/// `[[Title|id]]` is what Ctrl+K writes ([applyLink]) and what `linkSiteAt`
/// finds again, so a link made here can be edited and removed with the same
/// keystrokes as any other.
void _turnIntoPageLink(AppState app, Block b) {
  final ref = PortalRef.parse(b.content);
  if (ref == null) return;
  final title = app.node(ref.pageId)?.title;
  app.pushUndo();
  // An empty label falls back to the id rather than to words, for the reason
  // `applyLink` gives: `[[|id]]` matches nothing, because the wiki label is
  // `[^\]|]+`.
  final label =
      title == null || title.trim().isEmpty ? ref.pageId : title.trim();
  final link = '[[$label|${ref.pageId}]]';
  final made = app.addBlock(Block(
    type: BlockType.text,
    x: b.x,
    y: b.y,
    // Not the window's width: a line of text in a 380px box would wrap where
    // nothing needs to wrap, and the box is what you see when you click it.
    w: 320,
    z: b.z,
    content: {'text': link},
  ));
  app.removeBlock(b.id, recordUndo: false);
  app.select(made.id);
}

/// **The menu one picture in a sentence answers with.**
///
/// The owner: *"To be able to save an image, i need to be both in editing
/// mode and have the cursor on the image, right clicking it not in editing
/// mode or while in editing but with the cursor else where should bring up
/// the option to save the image."*
///
/// The block's own menu cannot offer this, and correctly: a picture in a
/// sentence is characters in the text, so the block is a paragraph and
/// `pictureIn` says — rightly — that it holds no picture. The picture is the
/// only thing that knows where it is, so it is the thing that answers.
///
/// Drawn by the same [showMenu] with the same [_item] rows as every other
/// right-click in the app.
Future<void> showPictureMenu(
    BuildContext context, AppState app, String src, Offset globalPos) async {
  final action = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
        globalPos.dx, globalPos.dy, globalPos.dx, globalPos.dy),
    items: [_item('save-image', Icons.download_outlined, 'Save image as…')],
  );
  if (action != 'save-image' || !context.mounted) return;
  // An in-flow reference records no mime — it is the hash and nothing else —
  // so the name is worked out from the bytes themselves.
  await savePictureBytes(
    context,
    app.blob(src),
    notHereYet: "That picture isn't here yet — it may still be syncing.",
  );
}

Future<void> showBlockMenu(BuildContext context, AppState app, Block b,
    Offset globalPos) async {
  if (!app.selectedIds.contains(b.id)) app.select(b.id);
  final action = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
        globalPos.dx, globalPos.dy, globalPos.dx, globalPos.dy),
    items: [
      // **No "Edit".** The owner: *"Please remove the edit button in the
      // right click menu as thats accesable by left clicking the boxes."*
      // Quite so — a left click has opened a box for editing since the
      // beginning, and a menu row that repeats the gesture you used to open
      // the menu is a row everything else has to be read past. The same
      // reasoning already kept "Text box" off this menu and, later, off the
      // Insert ribbon.
      _item('copy', Icons.copy_outlined, 'Copy', shortcut: 'Ctrl+C'),
      _item('cut', Icons.cut_outlined, 'Cut', shortcut: 'Ctrl+X'),
      _item('duplicate', Icons.copy_all_outlined, 'Duplicate',
          shortcut: 'Ctrl+D'),
      // An imported PDF slide is locked so the pen can't shove it around.
      // Without a way back out, "won't move" reads as a broken control rather
      // than a state — and the slides now land on the user's own page.
      _item(
          'lock',
          b.content['locked'] == true ? Icons.lock_open_outlined : Icons.lock_outline,
          b.content['locked'] == true ? 'Unlock' : 'Lock in place'),
      // The box itself gets attributes, starting with a fill. The picker
      // returns RRGGBBAA, so transparency comes with it — a translucent
      // highlight over a diagram is half of why anyone tints a box.
      _item('bg', Icons.format_color_fill, 'Background colour…'),
      if (b.content['bg'] != null)
        _item('bg-clear', Icons.format_color_reset_outlined,
            'Remove background'),
      // A slide is a page of a stored PDF; the viewer is where its text is
      // selectable, which the raster on the canvas can never be.
      if (b.content['pdf'] is String)
        _item('open-pdf', Icons.picture_as_pdf_outlined, 'Open the PDF…'),
      // **Get the picture back out.** Issue #10: *"There is the possibility
      // that you need an image you imported into the note. It would be REALLY
      // useful to have a save image button."* A note that can swallow a
      // picture and never give it back is a one-way door, and an attachment
      // and a video have had their own "Save a copy…" all along.
      //
      // In the right-click menu because that is where every browser and every
      // document editor puts "Save image as…", so it is the first place
      // anybody looks — and it costs the picture no chrome drawn over it.
      if (pictureIn(b) != null)
        _item('save-image', Icons.download_outlined, 'Save image as…'),
      // **A window onto a page, or a line that points at one.** The owner
      // asked for the window to be draggable out of the navigator *"(and
      // right clicking this should provide the option to change this to a
      // page link)"* — because the two are the same intention at different
      // sizes, and which one you want is often clear only once you can see
      // the window taking up a third of the page.
      if (b.type == BlockType.embed && PortalRef.parse(b.content) != null)
        _item('to-link', Icons.link, 'Change to a page link'),
      const PopupMenuDivider(),
      _item('front', Icons.flip_to_front, 'Bring to front'),
      _item('back', Icons.flip_to_back, 'Send to back'),
      const PopupMenuDivider(),
      _item('delete', Icons.delete_outline, 'Delete', shortcut: 'Del'),
    ],
  );
  switch (action) {
    case 'lock':
      app.pushUndo();
      if (b.content['locked'] == true) {
        b.content.remove('locked');
      } else {
        b.content['locked'] = true;
      }
      app.updateBlock(b);
    case 'bg':
      if (context.mounted) {
        final hex = await showOnoteColorPicker(context, app,
            initial: b.content['bg'] as String?,
            title: 'Background colour');
        if (hex != null) {
          app.pushUndo();
          b.content['bg'] = hex;
          app.updateBlock(b);
        }
      }
    case 'bg-clear':
      app.pushUndo();
      b.content.remove('bg');
      app.updateBlock(b);
    case 'open-pdf':
      if (context.mounted) {
        await showPdfViewerDialog(context, app,
            hash: b.content['pdf'] as String,
            initialPage: (b.content['page'] as num?)?.toInt() ?? 0);
      }
    case 'save-image':
      if (context.mounted) await _saveImage(context, app, b);
    case 'to-link':
      _turnIntoPageLink(app, b);
    case 'copy':
      app.copySelectedBlocks();
    case 'cut':
      app.cutSelectedBlocks();
    case 'duplicate':
      app.duplicateBlock(b.id);
    case 'front':
      app.bringToFront(b.id);
    case 'back':
      app.sendToBack(b.id);
    case 'delete':
      app.removeSelected();
  }
}

/// **What this block holds that could be written out as a picture**, or null.
///
/// Two shapes qualify. An image block is bytes in the blob store. A slide is a
/// REFERENCE — `{pdf: sha256:…, page: n}` — whose pixels exist only while
/// something is looking at them, so saving one means rendering it. Both are
/// pictures to the person looking at the page, so both offer the item; the
/// difference lives in [_saveImage] and nowhere else.
@visibleForTesting
({bool slide, String hash})? pictureIn(Block b) {
  final pdf = b.content['pdf'];
  if (pdf is String) return (slide: true, hash: pdf);
  if (b.type != BlockType.image) return null;
  final blob = b.content['blob'];
  return blob is String ? (slide: false, hash: blob) : null;
}

/// Write the picture in [b] to a file the person chooses.
///
/// Every failure gets words. The same three the attachment's "Save a copy…"
/// already handles, because they are the three that happen: the bytes are not
/// here yet (a picture still syncing), the write threw (a full stick, a
/// protected folder), and the happy path — which also says something, so a
/// save that went somewhere unexpected is findable.
Future<void> _saveImage(BuildContext context, AppState app, Block b) async {
  final pic = pictureIn(b);
  if (pic == null) return;

  final Uint8List? bytes;
  final String base;
  final String? mime;
  if (pic.slide) {
    final page = (b.content['page'] as num?)?.toInt() ?? 0;
    bytes = await PdfPages.pageImage(app, pic.hash, page);
    // One-based: the person is looking at "page 1", not at index 0.
    base = 'slide-${page + 1}';
    mime = 'image/png'; // what the renderer produced, not what the PDF is
  } else {
    bytes = app.blob(pic.hash);
    base = 'image';
    mime = b.content['mime'] as String?;
  }
  if (!context.mounted) return;
  await savePictureBytes(context, bytes,
      mime: mime,
      base: base,
      notHereYet: pic.slide
          ? "That PDF isn't here yet — it may still be syncing."
          : "That picture isn't here yet — it may still be syncing.");
}

/// The canvas's own menu: paste, the ten things you can add, and the page's
/// background.
///
/// The owner: *"when right clicking on the canvas, it comes up with a bunch
/// of options saying 'insert x here', the insert here bit is already implied
/// so that doesnt need to be put in, also again the text box option is
/// redundant since they can just left click. … this should more closley match
/// the insert menu we already have, although that is quite busy and i dont
/// want it to be a huge drop down."*
///
/// All three are answered by one change: it renders [kInsertGroups], the same
/// list the Insert ribbon renders, as **three columns**. The word "here" is
/// gone from every label because a right click already means here; there is
/// no text box because a left click already makes one; and the columns make
/// the menu SHORTER than the eleven-row stack it replaces, not longer —
/// eleven rows was about 430px tall, this is about 200.
///
/// The four `Background: …` rows become one submenu with a tick on the
/// current one, which the old rows never showed.
Future<void> showCanvasMenu(BuildContext context, AppState app,
    Offset globalPos, Offset pagePt) async {
  final action = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
        globalPos.dx, globalPos.dy, globalPos.dx, globalPos.dy),
    // Wide enough for three columns; without it the menu sizes to the Paste
    // row and the grid overflows off the edge, where it can be neither seen
    // nor pressed.
    constraints: const BoxConstraints(minWidth: 428, maxWidth: 460),
    items: [
      // First, because it is what people right-click for. Greyed rather than
      // hidden: a menu whose rows move about is a menu you cannot learn.
      _item('paste', Icons.paste_outlined, 'Paste',
          enabled: app.canPasteBlocks, shortcut: 'Ctrl+V'),
      const PopupMenuDivider(height: 9),
      const _InsertGrid(),
      const PopupMenuDivider(height: 9),
      _bgSubmenu(context, app),
    ],
  );
  if (action == null) return;
  if (action.startsWith('bg-')) {
    app.setBackground(action.substring(3));
    return;
  }
  if (action == 'paste') {
    app.pasteBlocks(at: pagePt);
    return;
  }
  for (final item in kMenuItemsAndExtras) {
    if (item.id == action) {
      // **Here means here.** Every one of these commands puts what it makes
      // at the caret when a paragraph has one — which is right for the
      // ribbon, and wrong for a right click several inches away: a picture
      // chosen from this menu was spliced into the sentence you happened to
      // be writing. Choosing something from a menu that opened AT a point is
      // choosing that point, so the caret is let go of first.
      app.select(null);
      if (context.mounted) await item.run(context, app, pagePt);
      return;
    }
  }
}

/// The page's own backgrounds, with a tick on the one that is on.
PopupMenuEntry<String> _bgSubmenu(BuildContext context, AppState app) {
  const kinds = [
    ('blank', Icons.crop_din, 'Blank'),
    ('grid', Icons.grid_4x4, 'Grid'),
    ('dotted', Icons.apps, 'Dotted'),
    ('ruled', Icons.notes, 'Ruled'),
  ];
  return PopupMenuItem<String>(
    height: 36,
    padding: EdgeInsets.zero,
    child: PopupMenuButton<String>(
      tooltip: '',
      position: PopupMenuPosition.under,
      onSelected: (v) {
        Navigator.of(context).pop('bg-$v');
      },
      itemBuilder: (_) => [
        for (final (id, icon, label) in kinds)
          CheckedPopupMenuItem<String>(
            value: id,
            checked: app.pageProps.background == id,
            child: Row(children: [
              Icon(icon, size: 16),
              const SizedBox(width: 10),
              Text(label, style: const TextStyle(fontSize: 13)),
            ]),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          const Icon(Icons.wallpaper_outlined, size: 16),
          const SizedBox(width: 10),
          const Expanded(
              child: Text('Page background',
                  style: TextStyle(fontSize: 13))),
          Icon(Icons.chevron_right,
              size: 16, color: context.surfaces.textSecondary),
        ]),
      ),
    ),
  );
}

/// The catalog, as three columns of tiles.
///
/// A `PopupMenuEntry` rather than a run of `PopupMenuItem`s, because ten rows
/// in a column is the tall drop-down the owner does not want and three
/// columns of four is a third of the height. `represents` is false: no single
/// value stands for this row, and each tile pops with its own.
class _InsertGrid extends PopupMenuEntry<String> {
  const _InsertGrid();

  @override
  double get height {
    final tallest = kMenuGroups
        .map((g) => g.items.fold(0, (n, i) => n + 1 + i.extras.length))
        .reduce(math.max);
    return 26.0 + tallest * 30.0;
  }

  @override
  bool represents(String? value) => false;

  @override
  State<_InsertGrid> createState() => _InsertGridState();
}

class _InsertGridState extends State<_InsertGrid> {
  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final group in kMenuGroups)
            SizedBox(
              width: 134,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 4, 0, 4),
                    child: Text(group.title(L.of(context)).toUpperCase(),
                        style: OnoteType.caption.copyWith(
                          color: s.textSecondary,
                          letterSpacing: 0.6,
                          fontWeight: FontWeight.w600,
                        )),
                  ),
                  for (final item in group.items) ...[
                    _Tile(item: item, surfaces: s),
                    // A second choice, indented under the thing it belongs
                    // to: the ribbon hides these behind a small arrow, and a
                    // menu has no room for one. "Table ▸ From a file" was on
                    // the ribbon and not here, which is exactly the drift the
                    // shared catalog exists to end.
                    for (final extra in item.extras)
                      _Tile(item: extra, surfaces: s, indented: true),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(
      {required this.item, required this.surfaces, this.indented = false});
  final InsertItem item;
  final OnoteSurfaces surfaces;

  /// A second choice, set in under the command it belongs to.
  final bool indented;

  @override
  Widget build(BuildContext context) => InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(OnoteRadius.sm),
        onTap: () => Navigator.of(context).pop(item.id),
        child: SizedBox(
          height: 30,
          child: Padding(
            padding: EdgeInsets.only(left: indented ? 20 : 6, right: 6),
            child: Row(children: [
              Icon(item.icon, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(item.menuLabel(L.of(context)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        color: indented ? surfaces.textSecondary : null)),
              ),
            ]),
          ),
        ),
      );
}
