import 'package:flutter/material.dart';

import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';

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
        Text(shortcut,
            style: TextStyle(fontSize: 11, color: OnoteColors.graphite400)),
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
