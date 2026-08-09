import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../export/csv_import.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'color_picker.dart';
import 'insert_portal_dialog.dart';

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
            initial: b.content['bg'] as String?);
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

Future<void> showCanvasMenu(BuildContext context, AppState app,
    Offset globalPos, Offset pagePt) async {
  final action = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
        globalPos.dx, globalPos.dy, globalPos.dx, globalPos.dy),
    items: [
      _item('text', Icons.text_fields, 'New text box here'),
      _item('math', Icons.functions, 'New equation here'),
      _item('table', Icons.table_chart_outlined, 'New table here'),
      _item('portal', Icons.picture_in_picture_alt_outlined,
          'Page window here…'),
      _item('csv', Icons.grid_on_outlined, 'Table from CSV here…'),
      _item('paste', Icons.paste_outlined, 'Paste',
          enabled: app.canPasteBlocks, shortcut: 'Ctrl+V'),
      const PopupMenuDivider(),
      _item('bg-blank', Icons.crop_din, 'Background: blank'),
      _item('bg-grid', Icons.grid_4x4, 'Background: grid'),
      _item('bg-dotted', Icons.apps, 'Background: dotted'),
      _item('bg-ruled', Icons.notes, 'Background: ruled'),
    ],
  );
  switch (action) {
    case 'text':
      final pos = app.smartTextPosition(pagePt);
      final b = app.addBlock(Block(
          type: BlockType.text, x: pos.dx, y: pos.dy, w: 320, content: {'text': ''}));
      app.select(b.id, edit: true);
    case 'math':
      final b = app.addBlock(Block(
          type: BlockType.math,
          x: pagePt.dx,
          y: pagePt.dy,
          w: 360,
          content: {'latex': '', 'linearSource': ''}));
      app.select(b.id, edit: true);
    case 'table':
      final b = app.addBlock(Block(
          type: BlockType.table,
          x: pagePt.dx,
          y: pagePt.dy,
          w: 360,
          content: {
            'cells': [
              ['Header', 'Header'],
              ['', ''],
            ]
          }));
      app.select(b.id, edit: true);
    case 'portal':
      if (context.mounted) {
        await showInsertPortalDialog(context, app, pagePt);
      }
    case 'csv':
      // Same face-the-failure rule as the Insert ribbon's pickers: a picker
      // that cannot open must say so, not be a menu item that does nothing.
      final XFile? file;
      try {
        file = await openFile(acceptedTypeGroups: const [
          XTypeGroup(label: 'Tables', extensions: ['csv', 'tsv'])
        ]);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Couldn't open the file picker: $e")));
        }
        return;
      }
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final r = insertCsvTable(app, bytes, pagePt);
      if (context.mounted) {
        if (!r.placed) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('That file has no rows in it.')));
        } else if (r.note != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(r.note!)));
        }
      }
    case 'paste':
      app.pasteBlocks(at: pagePt);
    case 'bg-blank':
      app.setBackground('blank');
    case 'bg-grid':
      app.setBackground('grid');
    case 'bg-dotted':
      app.setBackground('dotted');
    case 'bg-ruled':
      app.setBackground('ruled');
  }
}
