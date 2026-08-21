import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'color_picker.dart';
import 'insert_catalog.dart';
import 'pdf_viewer_dialog.dart';

/// Right-click menus (style guide: most actions within ≤2 clicks).

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

Future<void> showBlockMenu(BuildContext context, AppState app, Block b,
    Offset globalPos) async {
  if (!app.selectedIds.contains(b.id)) app.select(b.id);
  final editable = b.type == BlockType.text ||
      b.type == BlockType.code ||
      b.type == BlockType.math;
  final action = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
        globalPos.dx, globalPos.dy, globalPos.dx, globalPos.dy),
    items: [
      if (editable) _item('edit', Icons.edit_outlined, 'Edit'),
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
      const PopupMenuDivider(),
      _item('front', Icons.flip_to_front, 'Bring to front'),
      _item('back', Icons.flip_to_back, 'Send to back'),
      const PopupMenuDivider(),
      _item('delete', Icons.delete_outline, 'Delete', shortcut: 'Del'),
    ],
  );
  switch (action) {
    case 'edit':
      app.select(b.id, edit: true);
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
                    child: Text(group.title.toUpperCase(),
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
                child: Text(item.menuLabel,
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
