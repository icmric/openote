import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../export/markdown_export.dart';
import '../export/pdf_export.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';

/// Contextual, quiet toolbar (style guide §7): tool group · ink options ·
/// insert · page · history · zoom. Icon-only with tooltips; groups divided.
class OnoteToolbar extends StatelessWidget {
  const OnoteToolbar({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inkToolActive =
        app.tool == Tool.pen || app.tool == Tool.highlighter;

    Widget toolButton(Tool t, IconData icon, String tip) {
      final active = app.tool == t;
      return IconButton(
        icon: Icon(icon),
        tooltip: tip,
        isSelected: active,
        style: IconButton.styleFrom(
          backgroundColor:
              active ? scheme.primary.withValues(alpha: .14) : null,
          foregroundColor: active ? scheme.primary : null,
        ),
        onPressed: () => app.setTool(t),
      );
    }

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border:
            Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          // ── Tools ──
          toolButton(Tool.select, Icons.near_me_outlined, 'Select / move  (V)'),
          toolButton(Tool.text, Icons.text_fields, 'Text — click anywhere  (T)'),
          toolButton(Tool.pen, Icons.edit_outlined, 'Pen  (P)'),
          toolButton(Tool.highlighter, Icons.border_color_outlined, 'Highlighter  (H)'),
          toolButton(Tool.eraser, Icons.cleaning_services_outlined, 'Eraser  (E)'),
          const _Divider(),

          // ── Ink options (contextual: only when an ink tool is active) ──
          if (inkToolActive || app.tool == Tool.eraser) ...[
            if (inkToolActive) ...[
              for (final (i, c) in (app.tool == Tool.highlighter
                      ? OnoteColors.highlighterColors
                      : OnoteColors.penColors)
                  .indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(99),
                    onTap: () {
                      app.penColor = i;
                      app.refresh();
                    },
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          width: 2,
                          color: app.penColor == i
                              ? scheme.primary
                              : Colors.transparent,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              SizedBox(
                width: 110,
                child: Slider(
                  value: app.penSize,
                  min: 1,
                  max: 10,
                  onChanged: (v) {
                    app.penSize = v;
                    app.refresh();
                  },
                ),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('Eraser removes whole strokes',
                    style:
                        TextStyle(fontSize: 12, color: OnoteColors.graphite400)),
              ),
            const _Divider(),
          ],

          // ── Insert ──
          MenuAnchor(
            builder: (context, controller, _) => IconButton(
              icon: const Icon(Icons.add_box_outlined),
              tooltip: 'Insert…',
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
            ),
            menuChildren: [
              MenuItemButton(
                leadingIcon: const Icon(Icons.text_fields, size: 18),
                onPressed: () => _insertText(),
                child: const Text('Text box'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.functions, size: 18),
                onPressed: () => _insertMath(),
                child: const Text('Equation'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.code, size: 18),
                onPressed: () => _insertCode(),
                child: const Text('Code block'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.image_outlined, size: 18),
                onPressed: () => _insertImage(context),
                child: const Text('Image…'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.attach_file, size: 18),
                onPressed: () => _insertFile(context),
                child: const Text('File attachment…'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.link, size: 18),
                onPressed: () => _insertPageLink(context),
                child: const Text('Link to page…'),
              ),
            ],
          ),

          // ── Page setup ──
          MenuAnchor(
            builder: (context, controller, _) => IconButton(
              icon: const Icon(Icons.texture_outlined),
              tooltip: 'Page background',
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
            ),
            menuChildren: [
              for (final (bg, label, icon) in const [
                ('blank', 'Blank', Icons.crop_din),
                ('grid', 'Grid', Icons.grid_4x4),
                ('dotted', 'Dotted', Icons.apps),
                ('ruled', 'Ruled', Icons.notes),
              ])
                MenuItemButton(
                  leadingIcon: Icon(icon,
                      size: 18,
                      color: app.pageProps.background == bg
                          ? scheme.primary
                          : null),
                  onPressed: () => app.setBackground(bg),
                  child: Text(label),
                ),
            ],
          ),
          IconButton(
            icon: Icon(app.snapToGrid ? Icons.grid_goldenratio : Icons.grid_off),
            tooltip: app.snapToGrid
                ? 'Snap to grid: ON — placement aligns to the grid'
                : 'Snap to grid: OFF — free placement',
            isSelected: app.snapToGrid,
            color: app.snapToGrid ? scheme.primary : null,
            onPressed: app.toggleSnap,
          ),
          const _Divider(),

          // ── History ──
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Undo  (Ctrl+Z)',
            onPressed: app.canUndo ? app.undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            tooltip: 'Redo  (Ctrl+Y)',
            onPressed: app.canRedo ? app.redo : null,
          ),
          const _Divider(),

          // ── Find & export ──
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Find on page  (Ctrl+F)',
            isSelected: app.findOpen,
            onPressed: app.toggleFind,
          ),
          MenuAnchor(
            builder: (context, controller, _) => IconButton(
              icon: const Icon(Icons.ios_share_outlined),
              tooltip: 'Export page…',
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
            ),
            menuChildren: [
              MenuItemButton(
                leadingIcon: const Icon(Icons.description_outlined, size: 18),
                onPressed: () async {
                  final path = await exportPageMarkdown(app);
                  if (path != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Exported to $path')));
                  }
                },
                child: const Text('Markdown (.md)'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                onPressed: () async {
                  final path = await exportPagePdf(app);
                  if (path != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Exported to $path')));
                  }
                },
                child: const Text('PDF (.pdf)'),
              ),
            ],
          ),

          const Spacer(),

          // ── Zoom ──
          IconButton(
            icon: const Icon(Icons.remove),
            tooltip: 'Zoom out  (Ctrl+-)',
            onPressed: () => app.canvas.setZoom(app.canvas.scale / 1.2),
          ),
          AnimatedBuilder(
            animation: app.canvas,
            builder: (context, _) => TextButton(
              onPressed: app.canvas.reset,
              child: Text('${(app.canvas.scale * 100).round()}%',
                  style: const TextStyle(fontSize: 12)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Zoom in  (Ctrl+=)',
            onPressed: () => app.canvas.setZoom(app.canvas.scale * 1.2),
          ),
          IconButton(
            icon: const Icon(Icons.fit_screen_outlined),
            tooltip: 'Zoom to fit content',
            onPressed: () => app.canvas.fitTo(app.contentBounds().inflate(24)),
          ),
        ],
      ),
    );
  }

  Future<void> _insertFile(BuildContext context) async {
    final file = await openFile();
    if (file == null) return;
    final Uint8List bytes = await file.readAsBytes();
    final hash = app.repo.putBlob(
        app.notebookId!, bytes, 'application/octet-stream');
    final c = app.canvas.screenToPage(
        Offset(app.canvas.viewport.width / 2, app.canvas.viewport.height / 2));
    final b = app.addBlock(Block(
      type: BlockType.file,
      x: c.dx - 140,
      y: c.dy - 24,
      w: 280,
      content: {
        'blob': 'sha256:$hash',
        'name': file.name,
        'mime': 'application/octet-stream',
        'size': bytes.length,
      },
    ));
    app.select(b.id);
  }

  Future<void> _insertPageLink(BuildContext context) async {
    final pages = app.pages.where((p) => p.id != app.pageId).toList();
    if (pages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No other pages to link to yet.')));
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Link to page'),
        children: [
          for (final p in pages)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, p.id),
              child: Row(children: [
                const Icon(Icons.description_outlined, size: 15),
                const SizedBox(width: 8),
                Flexible(child: Text(p.title, overflow: TextOverflow.ellipsis)),
              ]),
            ),
        ],
      ),
    );
    if (choice != null) app.insertPageLink(choice);
  }

  void _insertText() {
    final c = app.canvas.screenToPage(
        Offset(app.canvas.viewport.width / 2, app.canvas.viewport.height / 2));
    final b = app.addBlock(
        Block(type: BlockType.text, x: c.dx - 140, y: c.dy - 20, w: 280, content: {'text': ''}));
    app.select(b.id, edit: true);
  }

  void _insertMath() {
    final c = app.canvas.screenToPage(
        Offset(app.canvas.viewport.width / 2, app.canvas.viewport.height / 2));
    final b = app.addBlock(Block(
        type: BlockType.math,
        x: c.dx - 180,
        y: c.dy - 30,
        w: 360,
        content: {'latex': '', 'linearSource': ''}));
    app.select(b.id, edit: true);
  }

  void _insertCode() {
    final c = app.canvas.screenToPage(
        Offset(app.canvas.viewport.width / 2, app.canvas.viewport.height / 2));
    final b = app.addBlock(Block(
        type: BlockType.code,
        x: c.dx - 200,
        y: c.dy - 40,
        w: 400,
        content: {'language': 'text', 'source': ''}));
    app.select(b.id, edit: true);
  }

  Future<void> _insertImage(BuildContext context) async {
    const typeGroup = XTypeGroup(
      label: 'Images',
      extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    final Uint8List bytes = await file.readAsBytes();
    final ext = file.name.split('.').last.toLowerCase();
    final mime = switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      _ => 'image/png',
    };
    final hash = app.repo.putBlob(app.notebookId!, bytes, mime);
    final c = app.canvas.screenToPage(
        Offset(app.canvas.viewport.width / 2, app.canvas.viewport.height / 2));
    final b = app.addBlock(Block(
      type: BlockType.image,
      x: c.dx - 160,
      y: c.dy - 120,
      w: 320,
      content: {'blob': 'sha256:$hash', 'mime': mime},
    ));
    app.select(b.id);
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: Theme.of(context).dividerColor,
      );
}
