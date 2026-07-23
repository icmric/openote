import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../editor/code_block_view.dart';
import '../editor/file_block_view.dart';
import '../editor/image_block_view.dart';
import '../editor/math_block_view.dart';
import '../editor/table_block_view.dart';
import '../editor/text_block_view.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../ui/context_menus.dart';
import 'canvas_controller.dart';

/// Selection chrome + move/resize for one block; dispatches content by type.
/// Interaction (F-4 fix): single tap on text/code/math enters editing
/// directly (OneNote behavior); drag moves (all selected move together);
/// shift-click adds to the selection.
class BlockView extends StatefulWidget {
  const BlockView({
    super.key,
    required this.block,
    required this.app,
    required this.controller,
  });
  final Block block;
  final AppState app;
  final CanvasController controller;

  @override
  State<BlockView> createState() => _BlockViewState();
}

class _BlockViewState extends State<BlockView> {
  bool _hover = false;
  bool _dragUndoPushed = false;
  bool _resizeUndoPushed = false;

  Block get b => widget.block;
  AppState get app => widget.app;
  bool get selected => app.selectedIds.contains(b.id);
  bool get primary => app.selectedBlockId == b.id;
  bool get editing => app.editingBlockId == b.id;

  bool get _editableType =>
      b.type == BlockType.text ||
      b.type == BlockType.code ||
      b.type == BlockType.math ||
      b.type == BlockType.table;

  void _tap() {
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (shift) {
      app.select(b.id, additive: true);
    } else if (_editableType) {
      app.select(b.id, edit: true); // tap-to-edit (F-4)
    } else {
      app.select(b.id);
    }
  }

  void _dragStart(DragStartDetails d) {
    if (!selected) app.select(b.id);
    app.setDragging(true);
  }

  void _drag(DragUpdateDetails d) {
    if (!_dragUndoPushed) {
      app.pushUndo();
      _dragUndoPushed = true;
    }
    if (!selected) app.select(b.id);
    app.moveSelectedBy(
        d.delta.dx / widget.controller.scale, d.delta.dy / widget.controller.scale);
  }

  void _dragEnd(DragEndDetails d) {
    _dragUndoPushed = false;
    app.settleSelected();
    app.setDragging(false);
  }

  String _a11yLabel() {
    final t = switch (b.type) {
      BlockType.text => b.content['text'] as String? ?? '',
      BlockType.code =>
        'Code block. ${b.content['source'] as String? ?? ''}',
      BlockType.math =>
        'Equation. ${b.content['linearSource'] ?? b.content['latex'] ?? ''}',
      BlockType.image => 'Image',
      BlockType.file => 'Attachment: ${b.content['name'] ?? 'file'}',
      _ => '${b.type.name} block',
    };
    return t.trim().isEmpty ? '${b.type.name} block' : t;
  }

  void _resize(DragUpdateDetails d) {
    if (!_resizeUndoPushed) {
      app.pushUndo();
      _resizeUndoPushed = true;
    }
    // Manual resize locks the width (text boxes stop auto-growing).
    if (b.type == BlockType.text) b.content['autoWidth'] = false;
    b.w = (b.w + d.delta.dx / widget.controller.scale).clamp(80.0, 4000.0);
    app.updateBlock(b);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    // Auto-width text boxes are measured HERE (parent build) so the box grows
    // in the same frame the text changes — no wrapping-before-resize lag. We
    // only measure the box being *edited* (the sole time width must track
    // content live); other blocks reuse their stored width, so panning/zooming
    // never re-measures every text box. The measured width is written back to
    // the model so persistence, export, and hit-testing agree with the screen.
    double displayW = b.w;
    if (b.type == BlockType.text &&
        editing &&
        b.content['autoWidth'] != false) {
      displayW = TextBlockView.autoWidth(b, dark: dark);
      b.w = displayW;
    }

    final content = switch (b.type) {
      BlockType.text => TextBlockView(block: b, app: app),
      BlockType.math => MathBlockView(block: b, app: app),
      BlockType.image => ImageBlockView(block: b, app: app),
      BlockType.code => CodeBlockView(block: b, app: app),
      BlockType.table => TableBlockView(block: b, app: app),
      BlockType.file => FileBlockView(block: b, app: app),
      _ => Padding(
          padding: const EdgeInsets.all(8),
          child: Text('Unsupported block: ${b.type.name}',
              style: TextStyle(color: OnoteColors.graphite400)),
        ),
    };
    // Expose content to assistive tech (PLAT-5).
    final labelled = Semantics(
      container: true,
      label: _a11yLabel(),
      selected: selected,
      child: content,
    );

    // While an ink tool is active, blocks are inert — the pen draws OVER
    // them instead of dragging/editing them (fixes ink-over-block dragging).
    final inkToolActive = app.tool == Tool.pen ||
        app.tool == Tool.highlighter ||
        app.tool == Tool.eraser;

    return Positioned(
      left: b.x,
      top: b.y,
      child: IgnorePointer(
        ignoring: inkToolActive,
        child: Listener(
        // Claim this pointer so the canvas-level handler ignores it.
        onPointerDown: (e) => app.claimedPointers.add(e.pointer),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          cursor: _editableType && !editing
              ? SystemMouseCursors.text
              : MouseCursor.defer,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: editing ? null : _tap,
            onSecondaryTapUp: editing
                ? null
                : (d) => showBlockMenu(context, app, b, d.globalPosition),
            onPanStart: editing ? null : _dragStart,
            onPanUpdate: editing ? null : _drag,
            onPanEnd: editing ? null : _dragEnd,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                _MeasureSize(
                  onChange: (size) => app.renderSizes[b.id] = size,
                  child: Container(
                    width: displayW,
                    height: b.h,
                    constraints: const BoxConstraints(minHeight: 36),
                    decoration: BoxDecoration(
                      color: editing || selected || _hover
                          ? (dark ? OnoteColors.night50 : OnoteColors.paper0)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        width: primary && !editing ? 2 : 1,
                        color: editing
                            ? primaryColor.withValues(alpha: .55)
                            : selected
                                ? primaryColor
                                : _hover
                                    ? (dark
                                        ? OnoteColors.night300
                                        : OnoteColors.paper300)
                                    : Colors.transparent,
                      ),
                    ),
                    child: labelled,
                  ),
                ),
                // Resize handle — available whenever the block is primary,
                // including while editing a text box (so it's resizable).
                if (primary) ...[
                  Positioned(
                    right: -6,
                    top: 0,
                    bottom: 0,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeLeftRight,
                      child: GestureDetector(
                        onPanUpdate: _resize,
                        onPanEnd: (_) => _resizeUndoPushed = false,
                        child: Center(
                          child: Container(
                            width: 10,
                            height: 28,
                            decoration: BoxDecoration(
                              color: primaryColor.withValues(alpha: .85),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                // Duplicate/delete affordances only when selected, not typing.
                if (primary && !editing) ...[
                  Positioned(
                    top: -16,
                    right: -8,
                    child: Row(
                      children: [
                        IconButton.filledTonal(
                          iconSize: 13,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.copy_all_outlined),
                          tooltip: 'Duplicate (Ctrl+D)',
                          onPressed: () => app.duplicateBlock(b.id),
                        ),
                        const SizedBox(width: 2),
                        IconButton.filledTonal(
                          iconSize: 13,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close),
                          tooltip: 'Delete (Del)',
                          onPressed: () => app.removeSelected(),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

/// Reports the child's laid-out size (post-frame) so the app can hit-test,
/// cull, and fit auto-height blocks accurately.
class _MeasureSize extends StatefulWidget {
  const _MeasureSize({required this.onChange, required this.child});
  final void Function(Size) onChange;
  final Widget child;

  @override
  State<_MeasureSize> createState() => _MeasureSizeState();
}

class _MeasureSizeState extends State<_MeasureSize> {
  Size? _last;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final size = context.size;
      if (size != null && size != _last) {
        _last = size;
        widget.onChange(size);
      }
    });
    return widget.child;
  }
}
