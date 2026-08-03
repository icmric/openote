import 'package:flutter/gestures.dart' show PointerDeviceKind;
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
    final scale = widget.controller.scale;
    app.moveSelectedBy(d.delta.dx / scale, d.delta.dy / scale);
    // Alignment guides (CANVAS-7). Computed after the move so the guide
    // reflects where the block actually is, and the snap nudges it flush.
    app.updateAlignGuides(scale);
  }

  void _dragEnd(DragEndDetails d) {
    _dragUndoPushed = false;
    app.applyAlignSnap();
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

  /// Height is only draggable for blocks that own one. A text block's height
  /// comes from its text, so a height handle there would fight the content.
  bool get _canResizeHeight =>
      b.type == BlockType.ink ||
      b.type == BlockType.image ||
      b.type == BlockType.table ||
      b.h != null;

  void _resize(DragUpdateDetails d) => _resizeBy(d, width: true, height: false);

  /// Resize by a drag delta (CANVAS-4).
  ///
  /// [width]/[height] pick which axes the handle drives, so the same code
  /// serves the right edge, the bottom edge and the corner.
  ///
  /// **Ink scales with its block.** OneNote does this, and the alternative —
  /// clipping — silently destroys strokes the moment a box is made smaller.
  /// Stroke coordinates are page-absolute (Ink Spec §3), so they are scaled
  /// about the block's own origin, which is what keeps the drawing where the
  /// user put it relative to the box.
  void _resizeBy(DragUpdateDetails d,
      {required bool width, required bool height}) {
    if (!_resizeUndoPushed) {
      app.pushUndo();
      _resizeUndoPushed = true;
    }
    final scale = widget.controller.scale;
    final oldW = b.w;
    final oldH = b.h ?? app.renderSizes[b.id]?.height;

    if (width) {
      // Manual resize locks the width (text boxes stop auto-growing).
      if (b.type == BlockType.text) b.content['autoWidth'] = false;
      b.w = (b.w + d.delta.dx / scale).clamp(80.0, 4000.0);
    }
    if (height && oldH != null) {
      b.h = (oldH + d.delta.dy / scale).clamp(40.0, 4000.0);
    }

    if (b.type == BlockType.ink) {
      _scaleInk(
        sx: width && oldW > 0 ? b.w / oldW : 1.0,
        sy: height && oldH != null && oldH > 0 && b.h != null
            ? b.h! / oldH
            : 1.0,
      );
    }
    app.updateBlock(b);
  }

  /// Scale every stroke coordinate about the block's origin.
  void _scaleInk({required double sx, required double sy}) {
    if (sx == 1.0 && sy == 1.0) return;
    final strokes = b.content['strokes'];
    if (strokes is! List) return;
    for (final raw in strokes) {
      if (raw is! Map) continue;
      final xs = raw['x'], ys = raw['y'];
      if (xs is List) {
        for (var i = 0; i < xs.length; i++) {
          final v = xs[i];
          if (v is num) xs[i] = b.x + (v - b.x) * sx;
        }
      }
      if (ys is List) {
        for (var i = 0; i < ys.length; i++) {
          final v = ys[i];
          if (v is num) ys[i] = b.y + (v - b.y) * sy;
        }
      }
    }
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
    double? displayW = b.w;
    if (b.type == BlockType.text &&
        editing &&
        b.content['autoWidth'] != false) {
      displayW = TextBlockView.autoWidth(b, dark: dark);
      b.w = displayW;
    }
    // Math sizes itself: equations are tall/wide in ways a stored width can't
    // anticipate, and clamping them into the box scaled them illegibly small.
    // A null width lets the container wrap the rendered equation; the measured
    // size flows back through _MeasureSize below so w/h (hit-testing, marquee,
    // culling, export) track what's actually on screen.
    if (b.type == BlockType.math && !editing) {
      displayW = null;
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
            // Trackpad two-finger scrolls arrive as PointerPanZoom events,
            // which drag recognizers would otherwise claim — hovering a block
            // and scrolling must pan the CANVAS, never move the block. A
            // physical trackpad click-drag reports as a mouse pointer, so
            // deliberate drags still work with the trackpad excluded here.
            supportedDevices: const {
              PointerDeviceKind.mouse,
              PointerDeviceKind.touch,
              PointerDeviceKind.stylus,
              PointerDeviceKind.invertedStylus,
            },
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
                  onChange: (size) {
                    app.renderSizes[b.id] = size;
                    // Keep the model width in sync for self-sizing math blocks
                    // (see displayW above) so hit-testing/export match the
                    // screen. Silent sync — no notify, no updatedAt churn.
                    if (b.type == BlockType.math &&
                        (size.width - b.w).abs() > 2) {
                      b.w = size.width;
                    }
                  },
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
                        // Same trackpad exclusion as the block drag above.
                        supportedDevices: const {
                          PointerDeviceKind.mouse,
                          PointerDeviceKind.touch,
                          PointerDeviceKind.stylus,
                          PointerDeviceKind.invertedStylus,
                        },
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
                  // Bottom edge and corner (CANVAS-4). Only offered when the
                  // block has a real height to drive: an auto-height text box
                  // is sized by its content, and a handle that fought the text
                  // would be a control that appears not to work.
                  if (_canResizeHeight) ...[
                    Positioned(
                      left: 0,
                      right: 12,
                      bottom: -6,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeUpDown,
                        child: GestureDetector(
                          supportedDevices: const {
                            PointerDeviceKind.mouse,
                            PointerDeviceKind.touch,
                            PointerDeviceKind.stylus,
                            PointerDeviceKind.invertedStylus,
                          },
                          onPanUpdate: (d) =>
                              _resizeBy(d, width: false, height: true),
                          onPanEnd: (_) => _resizeUndoPushed = false,
                          child: Center(
                            child: Container(
                              width: 28,
                              height: 10,
                              decoration: BoxDecoration(
                                color: primaryColor.withValues(alpha: .85),
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: -6,
                      bottom: -6,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeDownRight,
                        child: GestureDetector(
                          supportedDevices: const {
                            PointerDeviceKind.mouse,
                            PointerDeviceKind.touch,
                            PointerDeviceKind.stylus,
                            PointerDeviceKind.invertedStylus,
                          },
                          onPanUpdate: (d) =>
                              _resizeBy(d, width: true, height: true),
                          onPanEnd: (_) => _resizeUndoPushed = false,
                          child: Container(
                            width: 13,
                            height: 13,
                            decoration: BoxDecoration(
                              color: primaryColor,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
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
