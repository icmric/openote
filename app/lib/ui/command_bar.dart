import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../export/markdown_export.dart';
import '../export/open_export.dart';
import '../export/pdf_export.dart';
import '../model/models.dart';
import '../model/tags.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'color_picker.dart';
import 'font_picker.dart';

/// The tabbed command bar (style guide §7 revised): Home · Insert · Draw ·
/// View. OneNote's few-clicks accessibility in Openote's calm language — a
/// slim tab row over a single command row of grouped icon buttons.
class CommandBar extends StatefulWidget {
  const CommandBar({super.key, required this.app});
  final AppState app;

  @override
  State<CommandBar> createState() => _CommandBarState();
}

class _CommandBarState extends State<CommandBar> {
  int _tab = 0;
  static const _tabs = ['Home', 'Insert', 'Draw', 'View'];

  AppState get app => widget.app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border:
            Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        children: [
          // ── Tab row ──
          SizedBox(
            height: 32,
            child: Row(
              children: [
                const SizedBox(width: 6),
                for (var i = 0; i < _tabs.length; i++)
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => setState(() => _tab = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            width: 2,
                            color:
                                _tab == i ? scheme.primary : Colors.transparent,
                          ),
                        ),
                      ),
                      child: Text(
                        _tabs[i],
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight:
                              _tab == i ? FontWeight.w600 : FontWeight.w400,
                          color: _tab == i ? scheme.primary : null,
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                // Current-tool escape hatch: visible whenever not in Select.
                if (app.tool != Tool.select)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ActionChip(
                      avatar: Icon(_toolIcon(app.tool), size: 14),
                      label: const Text('Done', style: TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => app.setTool(Tool.select),
                    ),
                  ),
                // Study: the due count is the whole nudge, so it's on the
                // badge rather than hidden behind the panel.
                _StudyButton(app: app),
                IconButton(
                  icon: const Icon(Icons.label_outline, size: 17),
                  tooltip: 'Find tags',
                  isSelected: app.showTagsPanel,
                  visualDensity: VisualDensity.compact,
                  onPressed: app.toggleTagsPanel,
                ),
                IconButton(
                  icon: const Icon(Icons.toc, size: 17),
                  tooltip: 'Page outline',
                  isSelected: app.showTocPanel,
                  visualDensity: VisualDensity.compact,
                  onPressed: app.toggleTocPanel,
                ),
                IconButton(
                  icon: const Icon(Icons.account_tree_outlined, size: 17),
                  tooltip: 'Links & backlinks',
                  isSelected: app.showLinksPanel,
                  visualDensity: VisualDensity.compact,
                  onPressed: app.toggleLinksPanel,
                ),
                IconButton(
                  icon: const Icon(Icons.search, size: 17),
                  tooltip: 'Find on page  (Ctrl+F)',
                  isSelected: app.findOpen,
                  visualDensity: VisualDensity.compact,
                  onPressed: app.toggleFind,
                ),
                MenuAnchor(
                  builder: (context, controller, _) => IconButton(
                    icon: const Icon(Icons.ios_share_outlined, size: 17),
                    tooltip: 'Export page…',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
                  ),
                  menuChildren: [
                    MenuItemButton(
                      leadingIcon:
                          const Icon(Icons.description_outlined, size: 18),
                      onPressed: () => _export(context, exportPageMarkdown),
                      child: const Text('Markdown (.md)'),
                    ),
                    MenuItemButton(
                      leadingIcon:
                          const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      onPressed: () => _export(context, exportPagePdf),
                      child: const Text('PDF (.pdf)'),
                    ),
                    MenuItemButton(
                      leadingIcon:
                          const Icon(Icons.hub_outlined, size: 18),
                      onPressed: () =>
                          _export(context, exportPageJsonCanvas),
                      child: const Text('JSON Canvas (.canvas)'),
                    ),
                    MenuItemButton(
                      leadingIcon: const Icon(Icons.gesture, size: 18),
                      onPressed: () => _export(context, exportPageInkML),
                      child: const Text('Ink → InkML (.inkml)'),
                    ),
                    const Divider(height: 6),
                    MenuItemButton(
                      leadingIcon:
                          const Icon(Icons.folder_zip_outlined, size: 18),
                      onPressed: () =>
                          _export(context, materializeNotebook),
                      child: const Text('Materialize notebook to folder…'),
                    ),
                  ],
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
          // ── Command row ──
          // Horizontally scrollable so a narrow window scrolls the controls
          // instead of throwing a RenderFlex overflow (style guide §7).
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: switch (_tab) {
                0 => _homeRow(context),
                1 => _insertRow(context),
                2 => _drawRow(context),
                _ => _viewRow(context),
              },
            ),
          ),
        ],
      ),
    );
  }

  static IconData _toolIcon(Tool t) => switch (t) {
        Tool.pen => Icons.edit_outlined,
        Tool.highlighter => Icons.border_color_outlined,
        Tool.eraser => Icons.cleaning_services_outlined,
        Tool.text => Icons.text_fields,
        _ => Icons.near_me_outlined,
      };

  Future<void> _export(
      BuildContext context, Future<String?> Function(AppState) fn) async {
    final path = await fn(app);
    if (path != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Exported to $path')));
    }
  }

  // ── HOME: history + text formatting ──────────────────────────────────

  Widget _homeRow(BuildContext context) {
    // Enable from state, not child build order (fixes the greyed-out bug).
    final canFormat = app.canFormatText;
    Widget fmt(IconData icon, String tip, VoidCallback fn) => IconButton(
          icon: Icon(icon, size: 18),
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          onPressed: canFormat ? fn : null,
        );
    final lcv = int.tryParse(app.lastColor, radix: 16) ?? 0;
    final curColor = app.lastColor.length == 8
        ? Color(((lcv & 0xFF) << 24) | (lcv >> 8))
        : Color(0xFF000000 | lcv);
    return Row(children: [
      IconButton(
        icon: const Icon(Icons.undo, size: 18),
        tooltip: 'Undo  (Ctrl+Z)',
        visualDensity: VisualDensity.compact,
        onPressed: app.canUndo ? app.undo : null,
      ),
      IconButton(
        icon: const Icon(Icons.redo, size: 18),
        tooltip: 'Redo  (Ctrl+Y)',
        visualDensity: VisualDensity.compact,
        onPressed: app.canRedo ? app.redo : null,
      ),
      const _Div(),
      fmt(Icons.format_bold, 'Bold  (Ctrl+B)', () => app.wrapSelection('**')),
      fmt(Icons.format_italic, 'Italic  (Ctrl+I)', () => app.wrapSelection('*')),
      fmt(Icons.format_underlined, 'Underline  (Ctrl+U)',
          () => app.wrapSelection('++')),
      fmt(Icons.strikethrough_s, 'Strikethrough', () => app.wrapSelection('~~')),
      fmt(Icons.code, 'Inline code', () => app.wrapSelection('`')),
      fmt(Icons.border_color, 'Highlight', () => app.wrapSelection('==')),
      const _Div(),
      fmt(Icons.title, 'Heading 1', () => app.toggleLinePrefix('# ')),
      _TextBtn('H2', canFormat, () => app.toggleLinePrefix('## ')),
      _TextBtn('H3', canFormat, () => app.toggleLinePrefix('### ')),
      const _Div(),
      fmt(Icons.format_list_bulleted, 'Bullet list',
          () => app.toggleLinePrefix('- ')),
      fmt(Icons.format_list_numbered, 'Numbered list',
          () => app.toggleLinePrefix('1. ')),
      fmt(Icons.check_box_outlined, 'Checkbox',
          () => app.toggleLinePrefix('- [ ] ')),
      fmt(Icons.format_quote, 'Quote', () => app.toggleLinePrefix('> ')),
      const _Div(),
      // Tags (TEXT-5). OneNote users organise around these, so they get a
      // first-class place on Home rather than a submenu. The button shows the
      // caret line's active tags, which is why it reads state on every build.
      _TagButton(app: app),
      const _Div(),
      // Text colour — split button (§7a.2): main area applies the current
      // colour; the arrow opens the full picker (palette/wheel/RGBA).
      Tooltip(
        message: 'Apply text colour',
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: canFormat ? () => app.applyTextColor(app.lastColor) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.format_color_text,
                  size: 17, color: canFormat ? null : OnoteColors.graphite400),
              Container(
                  width: 18,
                  height: 3,
                  margin: const EdgeInsets.only(top: 1),
                  color: canFormat ? curColor : OnoteColors.graphite400),
            ]),
          ),
        ),
      ),
      InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: canFormat
            ? () async {
                final hex = await showOnoteColorPicker(context, app,
                    initial: app.lastColor);
                if (hex != null) app.applyTextColor(hex);
              }
            : null,
        child: Icon(Icons.arrow_drop_down,
            size: 18, color: canFormat ? null : OnoteColors.graphite400),
      ),
      // Font — opens the searchable system-font picker.
      IconButton(
        icon: const Icon(Icons.font_download_outlined, size: 18),
        tooltip: 'Text font…',
        visualDensity: VisualDensity.compact,
        onPressed: canFormat
            ? () async {
                final f = await showFontPicker(context,
                    current: app.activeEditor?.block.content['font'] as String?);
                if (f != null) app.setActiveBlockFont(f);
              }
            : null,
      ),
      // Font size (TEXT-1). Points, because that's how people think about type
      // and how OneNote/Word present it; stored as 120-dpi px.
      _FontSizeField(app: app, enabled: canFormat),
      if (!canFormat) ...[
        const SizedBox(width: 10),
        Text('Click into a text box to format',
            style: TextStyle(fontSize: 11, color: OnoteColors.graphite400)),
      ],
    ]);
  }

  // ── INSERT ────────────────────────────────────────────────────────────

  Widget _insertRow(BuildContext context) {
    Widget ins(IconData icon, String label, VoidCallback fn) => Padding(
          padding: const EdgeInsets.only(right: 4),
          child: TextButton.icon(
            icon: Icon(icon, size: 16),
            label: Text(label, style: const TextStyle(fontSize: 12)),
            onPressed: fn,
          ),
        );
    return Row(children: [
      ins(Icons.text_fields, 'Text box', _insertText),
      ins(Icons.functions, 'Equation', _insertMath),
      ins(Icons.code, 'Code', _insertCode),
      ins(Icons.table_chart_outlined, 'Table', _insertTable),
      ins(Icons.image_outlined, 'Image', () => _insertImage(context)),
      ins(Icons.attach_file, 'File', () => _insertFile(context)),
      ins(Icons.link, 'Page link', () => _insertPageLink(context)),
      ins(Icons.dashboard_customize_outlined, 'Template',
          () => _applyTemplate(context)),
    ]);
  }

  // ── DRAW ──────────────────────────────────────────────────────────────

  Widget _drawRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget toolButton(Tool t, IconData icon, String tip) => IconButton(
          icon: Icon(icon, size: 18),
          tooltip: tip,
          isSelected: app.tool == t,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            backgroundColor: app.tool == t
                ? scheme.primary.withValues(alpha: .14)
                : null,
            foregroundColor: app.tool == t ? scheme.primary : null,
          ),
          onPressed: () => app.setTool(t),
        );
    final inkActive = app.tool == Tool.pen || app.tool == Tool.highlighter;
    final colors = app.tool == Tool.highlighter
        ? OnoteColors.highlighterColors
        : OnoteColors.penColors;
    return Row(children: [
      toolButton(Tool.select, Icons.near_me_outlined, 'Select / move  (V)'),
      toolButton(Tool.text, Icons.text_fields, 'Text  (T)'),
      toolButton(Tool.pen, Icons.edit_outlined, 'Pen  (P)'),
      toolButton(
          Tool.highlighter, Icons.border_color_outlined, 'Highlighter  (H)'),
      toolButton(Tool.eraser, Icons.cleaning_services_outlined, 'Eraser  (E)'),
      toolButton(Tool.lasso, Icons.gesture_outlined, 'Lasso-select ink'),
      const _Div(),
      if (inkActive) ...[
        for (final (i, c) in colors.indexed)
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
      ] else if (app.tool == Tool.eraser) ...[
        SegmentedButton<EraserMode>(
          segments: [
            for (final m in EraserMode.values)
              ButtonSegment(
                  value: m,
                  label: Text(m.label, style: const TextStyle(fontSize: 11))),
          ],
          selected: {app.eraserMode},
          onSelectionChanged: (s) => app.setEraserMode(s.first),
          showSelectedIcon: false,
          style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        ),
        const SizedBox(width: 8),
        Text(
            app.eraserMode == EraserMode.area
                ? 'Splits strokes where you rub'
                : 'Removes any stroke you touch',
            style: TextStyle(fontSize: 11, color: OnoteColors.graphite400)),
      ]
      else if (app.tool == Tool.lasso)
        Text('Draw a loop around ink to select it — then drag or delete',
            style: TextStyle(fontSize: 11, color: OnoteColors.graphite400))
      else
        Text('Pick the pen or highlighter to draw',
            style: TextStyle(fontSize: 11, color: OnoteColors.graphite400)),
      const Spacer(),
      // Touch drawing (INK-1). Exposed because the right answer depends on
      // hardware we can't detect reliably: "Auto" suits a pen-and-touch
      // convertible, "Always" a touch-only tablet, "Never" anyone who rests a
      // hand on the glass while thinking.
      const _Div(),
      Tooltip(
        message: 'Draw with your finger.\nAuto: a finger draws until you use '
            'the pen, then touch pans so your palm can\'t mark the page.\n'
            'Two fingers always pan and zoom.',
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.touch_app_outlined,
              size: 16, color: OnoteColors.graphite400),
          const SizedBox(width: 4),
          DropdownButtonHideUnderline(
            child: DropdownButton<TouchDrawing>(
              value: app.touchDrawing,
              isDense: true,
              style: TextStyle(fontSize: 11, color: scheme.onSurface),
              items: [
                for (final v in TouchDrawing.values)
                  DropdownMenuItem(value: v, child: Text(v.label)),
              ],
              onChanged: (v) => v == null ? null : app.setTouchDrawing(v),
            ),
          ),
        ]),
      ),
      const SizedBox(width: 4),
    ]);
  }

  // ── VIEW ──────────────────────────────────────────────────────────────

  Widget _viewRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget bg(String v, IconData icon, String tip) => IconButton(
          icon: Icon(icon, size: 18),
          tooltip: 'Background: $tip',
          isSelected: app.pageProps.background == v,
          visualDensity: VisualDensity.compact,
          color: app.pageProps.background == v ? scheme.primary : null,
          onPressed: () => app.setBackground(v),
        );
    return Row(children: [
      bg('blank', Icons.crop_din, 'blank'),
      bg('grid', Icons.grid_4x4, 'grid'),
      bg('dotted', Icons.apps, 'dotted'),
      bg('ruled', Icons.notes, 'ruled'),
      const _Div(),
      IconButton(
        icon: Icon(app.snapToGrid ? Icons.grid_goldenratio : Icons.grid_off,
            size: 18),
        tooltip: app.snapToGrid
            ? 'Snap to grid: ON (grid shows while dragging)'
            : 'Snap to grid: OFF — free placement',
        isSelected: app.snapToGrid,
        visualDensity: VisualDensity.compact,
        color: app.snapToGrid ? scheme.primary : null,
        onPressed: app.toggleSnap,
      ),
      const _Div(),
      IconButton(
        icon: const Icon(Icons.remove, size: 18),
        tooltip: 'Zoom out  (Ctrl+-)',
        visualDensity: VisualDensity.compact,
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
        icon: const Icon(Icons.add, size: 18),
        tooltip: 'Zoom in  (Ctrl+=)',
        visualDensity: VisualDensity.compact,
        onPressed: () => app.canvas.setZoom(app.canvas.scale * 1.2),
      ),
      IconButton(
        icon: const Icon(Icons.fit_screen_outlined, size: 18),
        tooltip: 'Zoom to fit content',
        visualDensity: VisualDensity.compact,
        onPressed: () => app.canvas.fitTo(app.contentBounds().inflate(24)),
      ),
      const _Div(),
      SegmentedButton<ThemeMode>(
        showSelectedIcon: false,
        style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11))),
        segments: const [
          ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
          ButtonSegment(value: ThemeMode.light, label: Text('Light')),
          ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
        ],
        selected: {app.themeMode},
        onSelectionChanged: (s) => app.setThemeMode(s.first),
      ),
      const _Div(),
      // Spell check (TEXT-11). English-only in this release; the toggle exists
      // because a wordlist checker WILL flag jargon and proper nouns, and the
      // answer to that has to be one click away.
      Tooltip(
        message: 'Underline misspelled words while editing (English)',
        child: IconButton(
          icon: const Icon(Icons.spellcheck, size: 18),
          isSelected: app.spellCheckEnabled,
          visualDensity: VisualDensity.compact,
          color: app.spellCheckEnabled ? scheme.primary : null,
          onPressed: () => app.setSpellCheck(!app.spellCheckEnabled),
        ),
      ),
    ]);
  }

  // ── Insert actions ────────────────────────────────────────────────────

  Offset _center() => app.canvas.screenToPage(
      Offset(app.canvas.viewport.width / 2, app.canvas.viewport.height / 2));

  void _insertText() {
    final pos = app.smartTextPosition(_center());
    final b = app.addBlock(Block(
        type: BlockType.text, x: pos.dx, y: pos.dy, w: 320, content: {'text': ''}));
    app.select(b.id, edit: true);
  }

  void _insertMath() {
    final c = _center();
    final b = app.addBlock(Block(
        type: BlockType.math,
        x: c.dx - 180,
        y: c.dy - 30,
        w: 360,
        content: {'latex': '', 'linearSource': ''}));
    app.select(b.id, edit: true);
  }

  void _insertCode() {
    final c = _center();
    final b = app.addBlock(Block(
        type: BlockType.code,
        x: c.dx - 200,
        y: c.dy - 40,
        w: 400,
        content: {'language': 'text', 'source': ''}));
    app.select(b.id, edit: true);
  }

  void _insertTable() {
    final c = _center();
    final b = app.addBlock(Block(
        type: BlockType.table,
        x: c.dx - 180,
        y: c.dy - 40,
        w: 360,
        content: {
          'cells': [
            ['Header', 'Header'],
            ['', ''],
          ]
        }));
    app.select(b.id, edit: true);
  }

  Future<void> _insertImage(BuildContext context) async {
    const typeGroup = XTypeGroup(
        label: 'Images', extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp']);
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
    final hash = app.addBlob(bytes, mime);
    final c = _center();
    final b = app.addBlock(Block(
        type: BlockType.image,
        x: c.dx - 160,
        y: c.dy - 120,
        w: 320,
        content: {'blob': 'sha256:$hash', 'mime': mime}));
    app.select(b.id);
  }

  Future<void> _insertFile(BuildContext context) async {
    final file = await openFile();
    if (file == null) return;
    final Uint8List bytes = await file.readAsBytes();
    final hash =
        app.addBlob(bytes, 'application/octet-stream');
    final c = _center();
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
        }));
    app.select(b.id);
  }

  Future<void> _applyTemplate(BuildContext context) async {
    final names = app.templateNames();
    if (names.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'No templates yet — right-click a page and "Save as template…"')));
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Apply template'),
        children: [
          for (final n in names)
            SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, n), child: Text(n)),
        ],
      ),
    );
    if (choice != null) app.applyTemplate(choice);
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
    if (choice != null) {
      // If a text box is being edited, insert inline at the caret; otherwise
      // drop a new link block.
      if (app.activeEditor != null && app.canFormatText) {
        final title = app.node(choice)?.title ?? 'page';
        app.insertTextAtActiveCursor('[[$title|$choice]]');
      } else {
        app.insertPageLink(choice);
      }
    }
  }
}

class _TextBtn extends StatelessWidget {
  const _TextBtn(this.label, this.enabled, this.onTap);
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: enabled ? onTap : null,
        style: TextButton.styleFrom(
            minimumSize: const Size(30, 32),
            padding: const EdgeInsets.symmetric(horizontal: 6)),
        child: Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

class _Div extends StatelessWidget {
  const _Div();
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 22,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: Theme.of(context).dividerColor,
      );
}

/// Font-size control for the text block being edited (TEXT-1).
///
/// A dropdown of the sizes people actually use, plus the current value shown
/// even when it came from an import — OneNote pages carry per-box sizes, and
/// before this there was no way to see or change them.
class _FontSizeField extends StatelessWidget {
  const _FontSizeField({required this.app, required this.enabled});
  final AppState app;
  final bool enabled;

  static const _sizes = <double>[8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 36, 48];

  @override
  Widget build(BuildContext context) {
    // Stored px → pt for display; null means "the theme default".
    final px = app.activeBlockFontSize;
    final pt = px == null ? null : px * 72.0 / 120.0;
    final label = pt == null ? '–' : (pt % 1 == 0 ? pt.toStringAsFixed(0) : pt.toStringAsFixed(1));
    return Tooltip(
      message: enabled
          ? 'Text size (points)'
          : 'Click into a text box to change its size',
      child: MenuAnchor(
        builder: (context, controller, _) => InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: enabled
              ? () => controller.isOpen ? controller.close() : controller.open()
              : null,
          child: Container(
            constraints: const BoxConstraints(minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: enabled
                      ? Theme.of(context).colorScheme.outline
                      : Colors.transparent),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: enabled ? null : OnoteColors.graphite400)),
              Icon(Icons.arrow_drop_down,
                  size: 16,
                  color: enabled ? null : OnoteColors.graphite400),
            ]),
          ),
        ),
        menuChildren: [
          MenuItemButton(
            onPressed: () => app.setActiveBlockFontSize(null),
            child: const Text('Default'),
          ),
          for (final s in _sizes)
            MenuItemButton(
              onPressed: () => app.setActiveBlockFontSize(s),
              child: Text('${s.toStringAsFixed(0)} pt'),
            ),
        ],
      ),
    );
  }
}

/// The tag button on Home: applies a tag to the caret's line, and shows which
/// tags that line already carries.
///
/// A menu rather than a row of buttons because the set is open-ended (nine
/// built-ins plus, later, user-defined ones) and the toolbar is already dense.
class _TagButton extends StatelessWidget {
  const _TagButton({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = app.tagsAtCaret();
    final enabled = app.canFormatText;
    return MenuAnchor(
      builder: (context, controller, _) => Tooltip(
        message: active.isEmpty
            ? 'Tag this line (To Do, Important, Question…)'
            : 'Tagged: ${active.map((k) => k.label).join(', ')}',
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: enabled
              ? () => controller.isOpen ? controller.close() : controller.open()
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                  active.isEmpty
                      ? Icons.label_outline
                      : active.first.icon,
                  size: 17,
                  color: !enabled
                      ? OnoteColors.graphite400
                      : active.isEmpty
                          ? null
                          : active.first.color),
              Icon(Icons.arrow_drop_down,
                  size: 16,
                  color: enabled ? null : OnoteColors.graphite400),
            ]),
          ),
        ),
      ),
      menuChildren: [
        for (final k in TagKind.pickable)
          MenuItemButton(
            leadingIcon: Icon(k.icon, size: 16, color: k.color),
            trailingIcon: active.contains(k)
                ? Icon(Icons.check, size: 15, color: scheme.primary)
                : null,
            onPressed: () => app.toggleTagOnSelection(k),
            child: Text(k.label),
          ),
      ],
    );
  }
}

/// Study button with a due badge.
///
/// The count is the feature's entire nudge — "12 due" the week before an exam
/// is what turns notes into revision, and a bare icon says nothing.
class _StudyButton extends StatelessWidget {
  const _StudyButton({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final (due, total) = app.deckCounts(sectionId: app.activeSectionId);
    return Tooltip(
      message: total == 0
          ? 'Study — tag a line Question or Definition to make a card'
          : '$due of $total card${total == 1 ? '' : 's'} due in this section',
      child: Stack(clipBehavior: Clip.none, children: [
        IconButton(
          icon: const Icon(Icons.school_outlined, size: 17),
          isSelected: app.showStudyPanel,
          visualDensity: VisualDensity.compact,
          onPressed: app.toggleStudyPanel,
        ),
        if (due > 0)
          Positioned(
            right: 2,
            top: 2,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$due',
                    style: TextStyle(
                        fontSize: 9,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onPrimary)),
              ),
            ),
          ),
      ]),
    );
  }
}
