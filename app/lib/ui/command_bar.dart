import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../export/markdown_export.dart';
import '../export/open_export.dart';
import '../export/pdf_export.dart';
import '../export/pdf_vector_export.dart';
import '../export/pdf_import.dart';
import '../export/print_page.dart';
import '../model/models.dart';
import '../model/tags.dart';
import '../planner/agenda.dart';
import '../state/app_state.dart';
import '../study/study_stats.dart';
import '../theme/onote_theme.dart';
import 'color_picker.dart';
import 'font_picker.dart';
import '../theme/tokens.dart';

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
                          fontSize: 13,
                          fontWeight:
                              _tab == i ? FontWeight.w600 : FontWeight.w400,
                          color: _tab == i ? scheme.primary : null,
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                // The trailing cluster scrolls rather than overflowing.
                //
                // A `Row` that overflows is CLIPPED, and clipped pixels do not
                // hit-test — so on a narrow window (laptop + navigator open)
                // the rightmost buttons stopped responding with no visible
                // reason. `Flexible` lets the cluster shrink before the tabs
                // do, and `reverse: true` keeps the right-hand end — the end
                // that would otherwise be cut off — in view.
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      // Current-tool escape hatch: visible whenever not in Select.
                      if (app.tool != Tool.select)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: ActionChip(
                            avatar: Icon(_toolIcon(app.tool), size: 16),
                            label: const Text('Done',
                                style: TextStyle(fontSize: 11)),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => app.setTool(Tool.select),
                          ),
                        ),
                      // Study: the due count is the whole nudge, so it's on the
                      // badge rather than hidden behind the panel.
                      _StudyButton(app: app),
                      // The planner sits beside Study rather than in a menu:
                      // it is the other half of the same daily question, and
                      // the whole complaint it answers was that dates were
                      // reachable only from places you had to already be in.
                      _PlannerButton(app: app),
                      IconButton(
                        icon: const Icon(Icons.label_outline, size: 18),
                        tooltip: 'Find tags',
                        isSelected: app.showTagsPanel,
                        visualDensity: VisualDensity.compact,
                        onPressed: app.toggleTagsPanel,
                      ),
                      IconButton(
                        icon: const Icon(Icons.toc, size: 18),
                        tooltip: 'Page outline',
                        isSelected: app.showTocPanel,
                        visualDensity: VisualDensity.compact,
                        onPressed: app.toggleTocPanel,
                      ),
                      IconButton(
                        icon: const Icon(Icons.account_tree_outlined, size: 18),
                        tooltip: 'Links & backlinks',
                        isSelected: app.showLinksPanel,
                        visualDensity: VisualDensity.compact,
                        onPressed: app.toggleLinksPanel,
                      ),
                      IconButton(
                        icon: const Icon(Icons.search, size: 18),
                        tooltip: 'Find on page  (Ctrl+F)',
                        isSelected: app.findOpen,
                        visualDensity: VisualDensity.compact,
                        onPressed: app.toggleFind,
                      ),
                      MenuAnchor(
                        builder: (context, controller, _) => IconButton(
                          icon: const Icon(Icons.ios_share_outlined, size: 18),
                          tooltip: 'Export page…',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => controller.isOpen
                              ? controller.close()
                              : controller.open(),
                        ),
                        menuChildren: [
                          MenuItemButton(
                            leadingIcon: const Icon(Icons.description_outlined,
                                size: 18),
                            onPressed: () =>
                                _export(context, exportPageMarkdown),
                            child: const Text('Markdown (.md)'),
                          ),
                          // Vector by default: the shared/printed artefact
                          // should be searchable, selectable and small. The
                          // raster capture stays available for the rare page
                          // whose look matters more than its text.
                          MenuItemButton(
                            leadingIcon: const Icon(
                                Icons.picture_as_pdf_outlined,
                                size: 18),
                            onPressed: () =>
                                _export(context, exportPagePdfVector),
                            child: const Text('PDF (.pdf)'),
                          ),
                          MenuItemButton(
                            leadingIcon:
                                const Icon(Icons.print_outlined, size: 18),
                            shortcut: const SingleActivator(
                                LogicalKeyboardKey.keyP, control: true),
                            onPressed: () => printCurrentPage(app),
                            child: const Text('Print…'),
                          ),
                          MenuItemButton(
                            leadingIcon:
                                const Icon(Icons.image_outlined, size: 18),
                            onPressed: () => _export(context, exportPagePdf),
                            child: const Text('PDF — picture of the page'),
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
                            child:
                                const Text('Materialize notebook to folder…'),
                          ),
                        ],
                      ),
                    ]),
                  ),
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
      // **Collapsed to group heads when nothing is focused** (style guide
      // §4.5). "Disabled ≠ hidden" (§7a.2) still holds — the commands are
      // visible, and the hint at the end of the row says how to enable them —
      // but ~20 greyed glyphs was the app's first impression, and a washed-out
      // wall reads as broken rather than as "not yet applicable".
      if (!canFormat) ...[
        fmt(Icons.format_bold, 'Formatting — click into a text box first',
            () {}),
        fmt(Icons.title, 'Headings — click into a text box first', () {}),
        fmt(Icons.format_list_bulleted,
            'Lists — click into a text box first', () {}),
        const _Div(),
      ] else ...[
        fmt(Icons.format_bold, 'Bold  (Ctrl+B)', () => app.wrapSelection('**')),
        fmt(Icons.format_italic, 'Italic  (Ctrl+I)',
            () => app.wrapSelection('*')),
        fmt(Icons.format_underlined, 'Underline  (Ctrl+U)',
            () => app.wrapSelection('++')),
        fmt(Icons.strikethrough_s, 'Strikethrough',
            () => app.wrapSelection('~~')),
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
      ],
      // Tags (TEXT-5). OneNote users organise around these, so they get a
      // first-class place on Home rather than a submenu. The button shows the
      // caret line's active tags, which is why it reads state on every build.
      _TagButton(app: app),
      _MakeCardButton(app: app),
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
                  size: 18, color: canFormat ? null : context.surfaces.textSecondary),
              Container(
                  width: 18,
                  height: 3,
                  margin: const EdgeInsets.only(top: 1),
                  color: canFormat ? curColor : context.surfaces.textSecondary),
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
            size: 18, color: canFormat ? null : context.surfaces.textSecondary),
      ),
      // Font — opens the searchable system-font picker.
      IconButton(
        icon: const Icon(Icons.font_download_outlined, size: 18),
        tooltip: 'Text font…',
        visualDensity: VisualDensity.compact,
        onPressed: canFormat
            ? () async {
                final f = await showFontPicker(context,
                    current:
                        app.activeEditor?.block.content['font'] as String?);
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
            style: TextStyle(fontSize: 11, color: context.surfaces.textSecondary)),
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
      // The lecture-slide flow. Default is a printout down THIS page — one
      // continuous thing you scroll and write on, next to the notes already
      // there — with page-per-slide behind the arrow for a big unit you want
      // in the navigator.
      _PdfImportButton(app: app),
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
            backgroundColor:
                app.tool == t ? scheme.primary.withValues(alpha: .14) : null,
            foregroundColor: app.tool == t ? scheme.primary : null,
          ),
          onPressed: () => app.setTool(t),
        );
    // The swatches also appear with ink selected, so a lassoed diagram can be
    // recoloured without first re-picking the pen.
    final inkActive = app.tool == Tool.pen ||
        app.tool == Tool.highlighter ||
        app.hasInkSelection;
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
                // With ink selected (typically just lassoed), a colour click
                // recolours it rather than only arming the next stroke —
                // recolouring after the fact is most of why you lasso a
                // diagram (INK-7).
                if (app.hasInkSelection) {
                  app.recolorSelectedInk('#'
                      '${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}');
                } else {
                  app.refresh();
                }
              },
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    width: 2,
                    color:
                        app.penColor == i ? scheme.primary : Colors.transparent,
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
            style: TextStyle(fontSize: 11, color: context.surfaces.textSecondary)),
      ] else if (app.tool == Tool.lasso)
        Text('Draw a loop around ink to select it — then drag or delete',
            style: TextStyle(fontSize: 11, color: context.surfaces.textSecondary))
      else
        Text('Pick the pen or highlighter to draw',
            style: TextStyle(fontSize: 11, color: context.surfaces.textSecondary)),
      // NO `Spacer` here, and none in any command row. Every row is built
      // inside a horizontal `SingleChildScrollView`, which offers unbounded
      // width — and a flex child (`Spacer` is `Expanded`) under an unbounded
      // constraint is a hard layout assertion, not a soft one. The Draw row
      // therefore failed to lay out *at all*: no pen, no highlighter, no
      // eraser, nothing clickable. Push things apart with a fixed gap.
      const SizedBox(width: 12),
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
              size: 16, color: context.surfaces.textSecondary),
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
        type: BlockType.text,
        x: pos.dx,
        y: pos.dy,
        w: 320,
        content: {'text': ''}));
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
    final hash = app.addBlob(bytes, 'application/octet-stream');
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
                const Icon(Icons.description_outlined, size: 16),
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

  static const _sizes = <double>[
    8,
    9,
    10,
    11,
    12,
    14,
    16,
    18,
    20,
    24,
    28,
    36,
    48
  ];

  @override
  Widget build(BuildContext context) {
    // Stored px → pt for display; null means "the theme default".
    final px = app.activeBlockFontSize;
    final pt = px == null ? null : px * 72.0 / 120.0;
    final label = pt == null
        ? '–'
        : (pt % 1 == 0 ? pt.toStringAsFixed(0) : pt.toStringAsFixed(1));
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
                      color: enabled ? null : context.surfaces.textSecondary)),
              Icon(Icons.arrow_drop_down,
                  size: 16, color: enabled ? null : context.surfaces.textSecondary),
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
              Icon(active.isEmpty ? Icons.label_outline : active.first.icon,
                  size: 18,
                  color: !enabled
                      ? context.surfaces.textSecondary
                      : active.isEmpty
                          ? null
                          : active.first.color),
              Icon(Icons.arrow_drop_down,
                  size: 16, color: enabled ? null : context.surfaces.textSecondary),
            ]),
          ),
        ),
      ),
      menuChildren: [
        for (final k in TagKind.pickable)
          MenuItemButton(
            leadingIcon: Icon(k.icon, size: 16, color: k.color),
            trailingIcon: active.contains(k)
                ? Icon(Icons.check, size: 16, color: scheme.primary)
                : null,
            onPressed: () => app.toggleTagOnSelection(k),
            child: Text(k.label),
          ),
        // Dating a tag belongs here, beside applying one — a deadline you could
        // only set from a separate panel would be a feature most people never
        // found, and the line you want to date is the line you are on.
        if (active.isNotEmpty) ...[
          const Divider(height: 1),
          MenuItemButton(
            leadingIcon: const Icon(Icons.event_outlined, size: 16),
            onPressed: () => _setDue(context),
            child: Text(_dueOfCaret() == null ? 'Due date…' : 'Change due date…'),
          ),
          if (_dueOfCaret() != null)
            MenuItemButton(
              leadingIcon: const Icon(Icons.event_busy_outlined, size: 16),
              onPressed: _clearDue,
              child: const Text('Clear the due date'),
            ),
        ],
      ],
    );
  }

  /// The dated tag on the caret's line, if any. One date per line rather than
  /// one per tag: a line tagged both To Do and Important has one deadline, and
  /// asking which of the two icons owns it is a question nobody wants.
  NoteTag? _dueOfCaret() {
    final b = app.caretBlock();
    if (b == null) return null;
    final line = app.caretLineIndex();
    for (final t in NoteTag.listFrom(b.content)) {
      if (t.line == line && t.due != null) return t;
    }
    return null;
  }

  Future<void> _setDue(BuildContext context) async {
    final b = app.caretBlock();
    if (b == null) return;
    final line = app.caretLineIndex();
    final tags = [
      for (final t in NoteTag.listFrom(b.content))
        if (t.line == line) t
    ];
    if (tags.isEmpty) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final existing = _dueOfCaret()?.dueDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: existing != null && !existing.isBefore(today)
          ? existing
          : DateTime(today.year, today.month, today.day + 7),
      firstDate: DateTime(today.year, today.month, today.day - 365),
      lastDate: DateTime(today.year + 5, today.month, today.day),
      helpText: 'Due date',
      confirmText: 'Set',
    );
    if (picked == null) return;
    // Onto the first tag on the line, and any other dated tag there is cleared,
    // so the line keeps exactly one deadline however it was tagged.
    app.setTagDue(b.id, line, tags.first.kind, picked);
    for (final t in tags.skip(1)) {
      if (t.due != null) app.setTagDue(b.id, line, t.kind, null);
    }
  }

  void _clearDue() {
    final b = app.caretBlock();
    if (b == null) return;
    final line = app.caretLineIndex();
    for (final t in NoteTag.listFrom(b.content)) {
      if (t.line == line && t.due != null) {
        app.setTagDue(b.id, line, t.kind, null);
      }
    }
  }
}

/// One button that turns the caret's line into a flashcard.
///
/// Tags remain the underlying mechanism — a card is a *view* of a tagged line,
/// which is what makes editing the note edit the card. But "tag it Question or
/// Definition, and remember which one, and get the shape right" is a rule the
/// student has to learn before anything happens, and getting it wrong produced
/// nothing with no explanation. This reads the line, picks the tag, and says
/// what it did.
class _MakeCardButton extends StatelessWidget {
  const _MakeCardButton({required this.app});
  final AppState app;

  void _say(BuildContext context, String? msg) {
    if (msg == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    final enabled = app.canFormatText;
    return MenuAnchor(
      builder: (context, controller, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Make this line a flashcard',
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap:
                  enabled ? () => _say(context, app.makeCardAtCaret()) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: Icon(Icons.style_outlined,
                    size: 18, color: enabled ? null : context.surfaces.textSecondary),
              ),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: enabled
                ? () =>
                    controller.isOpen ? controller.close() : controller.open()
                : null,
            child: Icon(Icons.arrow_drop_down,
                size: 16, color: enabled ? null : context.surfaces.textSecondary),
          ),
        ],
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: Icon(TagKind.question.icon,
              size: 16, color: TagKind.question.color),
          shortcut:
              const SingleActivator(LogicalKeyboardKey.digit3, control: true),
          onPressed: () => app.toggleTagOnSelection(TagKind.question),
          child: const Text('Question card'),
        ),
        MenuItemButton(
          leadingIcon: Icon(TagKind.definition.icon,
              size: 16, color: TagKind.definition.color),
          shortcut:
              const SingleActivator(LogicalKeyboardKey.digit5, control: true),
          onPressed: () => app.toggleTagOnSelection(TagKind.definition),
          child: const Text('Definition card'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.format_underlined, size: 16),
          onPressed: () {
            if (!app.blankOutSelection()) {
              _say(context, 'Select the words to blank out first.');
            }
          },
          child: const Text('Blank out selection'),
        ),
        const Divider(height: 8),
        MenuItemButton(
          leadingIcon: const Icon(Icons.school_outlined, size: 16),
          onPressed: () {
            if (!app.showStudyPanel) app.toggleStudyPanel();
          },
          child: const Text('Open study panel'),
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

  /// How close an exam has to be before the badge changes colour. A week is
  /// when revision stops being a good intention, and it keeps the accent rare
  /// enough to still mean something when it appears.
  static const _urgentDays = 7;

  @override
  Widget build(BuildContext context) {
    final (due, total) = app.study.deckCounts(sectionId: app.activeSectionId);
    // Read from the date map and the counts already in hand — deliberately not
    // through `examPlanFor`, which would walk the deck a second time on a
    // widget that rebuilds with every keystroke.
    final exam = app.study.examDate(app.activeSectionId);
    final daysLeft =
        exam == null ? null : daysBetween(DateTime.now(), exam);
    final urgent =
        daysLeft != null && daysLeft >= 0 && daysLeft <= _urgentDays && due > 0;
    final countdown = daysLeft == null || daysLeft < 0
        ? ''
        : ' · exam ${formatCountdown(daysLeft)}';
    return Tooltip(
      message: total == 0
          ? 'Study — tag a line Question or Definition to make a card'
          : '$due of $total card${total == 1 ? '' : 's'} due in this section'
              '$countdown',
      child: Stack(clipBehavior: Clip.none, children: [
        IconButton(
          icon: const Icon(Icons.school_outlined, size: 18),
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
                  // Brass once the exam is inside a week. Colour never carries
                  // this alone (style guide §3.5) — the tooltip says how many
                  // days, and the count itself is unchanged.
                  color: urgent
                      ? OnoteColors.brass500
                      : Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$due',
                    style: TextStyle(
                        fontSize: 11,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: urgent
                            ? Colors.white
                            : Theme.of(context).colorScheme.onPrimary)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Opens the planner, and says what is on today without opening it.
///
/// The badge counts **today's and overdue** rows, not everything dated. A
/// number that included next month's exam would be permanently non-zero, and a
/// badge that is always lit stops being read — the same reasoning that keeps
/// the study badge on cards *due* rather than on the whole deck.
class _PlannerButton extends StatelessWidget {
  const _PlannerButton({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final sections = app.planner.sections(now: now);
    var count = 0;
    var overdue = false;
    for (final s in sections) {
      if (s.bucket == AgendaBucket.overdue) {
        overdue = true;
        count += s.items.length;
      } else if (s.bucket == AgendaBucket.today) {
        count += s.items.length;
      }
    }
    final alerts = app.planner.pendingAlerts.length;
    return Tooltip(
      message: alerts > 0
          ? '$alerts reminder${alerts == 1 ? '' : 's'} waiting'
          : count == 0
              ? 'Planner — every date you have, in one place'
              : overdue
                  ? 'Planner — $count today or overdue'
                  : 'Planner — $count today',
      child: Stack(clipBehavior: Clip.none, children: [
        IconButton(
          icon: const Icon(Icons.event_note_outlined, size: 18),
          isSelected: app.showPlannerPanel,
          visualDensity: VisualDensity.compact,
          onPressed: app.togglePlannerPanel,
        ),
        if (count > 0 || alerts > 0)
          Positioned(
            right: 2,
            top: 2,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  // Red only for something already late; a waiting reminder is
                  // brass, and an ordinary "3 today" is the primary accent.
                  // Colour never carries this alone (style guide §3.5) — the
                  // tooltip says which it is.
                  color: overdue
                      ? OnoteColors.danger
                      : alerts > 0
                          ? OnoteColors.brass500
                          : Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${alerts > 0 ? alerts : count}',
                    style: TextStyle(
                        fontSize: 11,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: overdue || alerts > 0
                            ? Colors.white
                            : Theme.of(context).colorScheme.onPrimary)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Insert ▸ PDF, as a split button.
///
/// The main action is the one a student wants nine times in ten: the slides
/// laid down THIS page, below what is already on it, the way OneNote's "PDF
/// printout" works. The arrow keeps the page-per-slide import, which is the
/// better shape for a whole unit you want as separate pages in the navigator.
class _PdfImportButton extends StatelessWidget {
  const _PdfImportButton({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (context, controller, _) => Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          TextButton.icon(
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
            label: const Text('PDF slides', style: TextStyle(fontSize: 12)),
            onPressed: () {
              // Close the menu if it is open: otherwise the file picker opens
              // behind a menu that is still sitting on top of it.
              controller.close();
              _importPdfWithProgress(context, app,
                  placement: PdfPlacement.currentPage);
            },
          ),
          Tooltip(
            message: 'Where the slides go',
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              // A bare 16px icon leaves most of the toolbar row's height as
              // dead space around it; sized to the row so the arrow is
              // actually hittable.
              child: const SizedBox(
                width: 22,
                height: 34,
                child: Icon(Icons.arrow_drop_down, size: 16),
              ),
            ),
          ),
        ]),
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.vertical_align_bottom, size: 16),
          onPressed: () => _importPdfWithProgress(context, app,
              placement: PdfPlacement.currentPage),
          child: const Text('Printout on this page'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.auto_stories_outlined, size: 16),
          onPressed: () => _importPdfWithProgress(context, app,
              placement: PdfPlacement.pagePerSlide),
          child: const Text('One page per slide'),
        ),
      ],
    );
  }
}

/// Import a PDF, with progress.
///
/// A lecture deck is 40–120 pages and each one is a pdfium render plus a PNG
/// encode, so this is seconds, not milliseconds — a modal with a live count is
/// the difference between "working" and "frozen".
Future<void> _importPdfWithProgress(BuildContext context, AppState app,
    {PdfPlacement placement = PdfPlacement.currentPage}) async {
  final progress = ValueNotifier<String>('Opening PDF…');
  var dialogOpen = false;
  if (context.mounted) {
    dialogOpen = true;
    showDialog<void>(
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
