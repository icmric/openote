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

/// Screen-space chrome reserved AROUND the block's content, in page units.
///
/// Reserved rather than overflowed, and that is the whole trick.
/// `RenderBox.hitTest` rejects anything outside a box's own size — `Clip.none`
/// affects painting only — so the old chrome, drawn at negative offsets, was
/// mostly unclickable: of a 10px resize handle at `right: -6` only 4px could be
/// grabbed, and the duplicate/delete buttons at `top: -16` sat on top of the
/// block's own first line of text and stole clicks from it. Padding the render
/// box means every piece of chrome has a non-negative offset and is fully
/// hit-testable, while the content still paints at exactly (b.x, b.y).
const double _kChromePad = 8;

/// Height of the move bar — the strip above the content that is the ONLY place
/// a drag moves the container. OneNote's model, and the reason for it is that
/// a click-drag inside a text box means "select this text" to everyone who has
/// ever used a text box.
const double _kBarH = 16;

class _BlockViewState extends State<BlockView> {
  bool _hoverBody = false;
  bool _hoverChrome = false;
  bool get _hover => _hoverBody || _hoverChrome;
  bool _dragUndoPushed = false;
  bool _resizeUndoPushed = false;

  /// Whether the in-progress body drag is allowed to move the block. Editable
  /// blocks say no unless Alt is held — see [_bodyDragStart].
  bool _bodyDragMoves = false;

  /// Text-drag selection state, driven from the raw [Listener] rather than a
  /// gesture recognizer so it never has to win an arena against the field's
  /// own selection gestures.
  Offset? _pressGlobal;
  int? _selectBase;
  bool _textDragging = false;

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
      // Where the click landed, so the caret goes there instead of jumping to
      // the end of the block. Only TEXT consumes it — a click on a table, a
      // code block or an equation would otherwise leave the token set, and the
      // next text box you opened by any other route would jump its caret to a
      // point on a completely different block.
      if (b.type == BlockType.text) app.pendingCaretGlobal = _pressGlobal;
      app.select(b.id, edit: true); // tap-to-edit (F-4)
    } else {
      app.select(b.id);
    }
  }

  // ── Pointer-level text selection ───────────────────────────────────────
  //
  // A non-editing text block renders read-only Markdown — there is no field to
  // drag-select in until the session exists. So the FIRST drag over the body
  // opens the editor, resolves the press point to a text offset, and extends
  // the selection from there. Done on the raw Listener because the pointer
  // route is pinned at down: it keeps arriving even once the widget tree under
  // the cursor has been replaced by the editing view.

  void _pointerDown(PointerDownEvent e) {
    app.claimedPointers.add(e.pointer);
    _pressGlobal = e.position;
    _selectBase = null;
    _textDragging = false;
  }

  void _pointerMove(PointerMoveEvent e) {
    final from = _pressGlobal;
    if (from == null || !_editableType || _locked) return;
    if (!_textDragging && (e.position - from).distance < 4) return;
    if (HardwareKeyboard.instance.isAltPressed) return; // Alt-drag moves
    if (!_textDragging) {
      _textDragging = true;
      if (!editing) {
        if (b.type == BlockType.text) app.pendingCaretGlobal = from;
        app.select(b.id, edit: true);
        return; // the field appears next frame; extend from the move after
      }
    }
    final session = app.activeSession;
    if (session == null || app.editingBlockId != b.id) return;
    _selectBase ??= session.offsetAtGlobal(from);
    final base = _selectBase;
    final extent = session.offsetAtGlobal(e.position);
    if (base == null || extent == null) return;
    // The session's own post-frame caret placement runs AFTER this handler in
    // the same frame and would collapse the selection we just made. Once the
    // drag has taken over, it has nothing left to do.
    session.pendingCaretGlobal = null;
    session.setSelection(base, extent);
  }

  void _pointerUp(PointerEvent e) {
    _selectBase = null;
    _textDragging = false;
    // _pressGlobal is left for _tap, which fires after the pointer is up.
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

  // Dragging the BODY of a text box means "select this text", so the body pan
  // is registered but declines to move unless Alt is held (the escape hatch)
  // or the block has no text to select — an image or an attachment, where
  // dragging the picture is unambiguous and matches OneNote.
  void _bodyDragStart(DragStartDetails d) {
    _bodyDragMoves = _locked
        ? false
        : !_editableType || HardwareKeyboard.instance.isAltPressed;
    if (_bodyDragMoves) _dragStart(d);
  }

  void _bodyDrag(DragUpdateDetails d) {
    if (_bodyDragMoves) _drag(d);
  }

  void _bodyDragEnd(DragEndDetails d) {
    if (_bodyDragMoves) _dragEnd(d);
    _bodyDragMoves = false;
  }

  /// Long-press reports a cumulative offset, not a delta.
  Offset _lastLongPress = Offset.zero;

  void _longPressStart(LongPressStartDetails d) {
    _lastLongPress = Offset.zero;
    _dragStart(DragStartDetails(globalPosition: d.globalPosition));
  }

  void _longPressMove(LongPressMoveUpdateDetails d) {
    final delta = d.offsetFromOrigin - _lastLongPress;
    _lastLongPress = d.offsetFromOrigin;
    _drag(DragUpdateDetails(globalPosition: d.globalPosition, delta: delta));
  }

  void _longPressEnd(LongPressEndDetails d) => _dragEnd(DragEndDetails());

  /// The strip above the block: the only place a drag moves the container.
  ///
  /// OneNote's model, adopted because it resolves an ambiguity that has no
  /// other answer — inside a text box, a click-drag means "select this text"
  /// to everybody, so the container needs somewhere else to be grabbed. It
  /// also gives block actions a home that isn't sitting on top of the block's
  /// own first line of text, and clicking it selects the whole container,
  /// which is the reliable way to get a text box into a multi-selection.
  Widget _moveBar(BuildContext context, Color primaryColor, bool dark) {
    final live = selected || editing;
    return MouseRegion(
      onEnter: (_) => setState(() => _hoverChrome = true),
      onExit: (_) => setState(() => _hoverChrome = false),
      cursor: SystemMouseCursors.move,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        supportedDevices: const {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
        },
        // Moving is allowed WHILE editing — OneNote lets you drag a container
        // by its bar with the caret still in it.
        onPanStart: _dragStart,
        onPanUpdate: _drag,
        onPanEnd: _dragEnd,
        onTap: () =>
            app.select(b.id, additive: HardwareKeyboard.instance.isShiftPressed),
        // Block actions stay reachable while editing, which they were not
        // when the only right-click target was the text itself.
        onSecondaryTapUp: (d) => showBlockMenu(context, app, b, d.globalPosition),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _kChromePad),
          child: Container(
            decoration: BoxDecoration(
              color: live
                  ? primaryColor.withValues(alpha: .85)
                  : (dark ? OnoteColors.night200 : OnoteColors.paper200),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                const SizedBox(width: 6),
                Icon(Icons.drag_indicator,
                    size: 12,
                    color: live
                        ? Theme.of(context).colorScheme.onPrimary
                        : OnoteColors.graphite400),
                const Spacer(),
                if (primary) ...[
                  _barButton(context, Icons.copy_all_outlined,
                      'Duplicate (Ctrl+D)', () => app.duplicateBlock(b.id), live),
                  _barButton(context, Icons.close, 'Delete (Del)',
                      () => app.removeSelected(), live),
                  const SizedBox(width: 2),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _barButton(BuildContext context, IconData icon, String tip,
          VoidCallback onTap, bool live) =>
      Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Icon(icon,
                size: 11,
                color: live
                    ? Theme.of(context).colorScheme.onPrimary
                    : OnoteColors.graphite400),
          ),
        ),
      );

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

  /// True for a background layer that must not be moved or resized —
  /// currently an imported PDF slide (see `export/pdf_import.dart`).
  bool get _locked => b.content['locked'] == true;

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
    // Measured in BOTH modes, not just while editing. Measuring only the
    // block being edited meant an auto-width box carried whatever width it
    // was created with until you first clicked into it, and then snapped to
    // its real width — the "slight horizontal growth when editing" report.
    // The measurement is memoised, so the read-mode cost is a map lookup.
    // (Imported boxes are `autoWidth: false` — OneNote gave them a real
    // width — so this does not disturb an imported layout.)
    if (b.type == BlockType.text && b.content['autoWidth'] != false) {
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

    // Chrome is only live for its OWN block, so two abutting blocks can never
    // both offer a bar at once even though the reserved strips overlap.
    final showChrome = !inkToolActive && !_locked && (_hover || selected || editing);

    const devices = {
      // Trackpad two-finger scrolls arrive as PointerPanZoom events, which
      // drag recognizers would otherwise claim — hovering a block and
      // scrolling must pan the CANVAS, never move the block. A physical
      // trackpad click-drag reports as a mouse pointer, so deliberate drags
      // still work with the trackpad excluded here.
      PointerDeviceKind.mouse,
      PointerDeviceKind.touch,
      PointerDeviceKind.stylus,
      PointerDeviceKind.invertedStylus,
    };

    final body = MouseRegion(
      onEnter: (_) => setState(() => _hoverBody = true),
      onExit: (_) => setState(() => _hoverBody = false),
      cursor: _editableType && !editing
          ? SystemMouseCursors.text
          : MouseCursor.defer,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        supportedDevices: devices,
        onTap: editing ? null : _tap,
        onSecondaryTapUp: editing
            ? null
            : (d) => showBlockMenu(context, app, b, d.globalPosition),
        // A locked block (an imported PDF slide) is an annotation surface: it
        // must not move when the pen misses, or the whole point of writing on
        // it is lost.
        onPanStart: editing || _locked ? null : _bodyDragStart,
        onPanUpdate: editing || _locked ? null : _bodyDrag,
        onPanEnd: editing || _locked ? null : _bodyDragEnd,
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
                          ? (dark ? OnoteColors.night300 : OnoteColors.paper300)
                          : Colors.transparent,
            ),
          ),
          child: labelled,
        ),
      ),
    );

    // Touch has no hover, so the bar cannot be the only way to move a block.
    // Long-press-then-drag is the platform convention there — and it is scoped
    // to touch and stylus so a slow mouse click can never move a text box by
    // accident, which is the very complaint the bar exists to fix.
    final touchable = GestureDetector(
      supportedDevices: const {
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
      },
      onLongPressStart: editing || _locked ? null : _longPressStart,
      onLongPressMoveUpdate: editing || _locked ? null : _longPressMove,
      onLongPressEnd: editing || _locked ? null : _longPressEnd,
      child: body,
    );

    return Positioned(
      // Shifted by the reserved chrome so the CONTENT still paints at
      // (b.x, b.y) — renderSizes, marquee, culling and export all continue to
      // mean the content box.
      left: b.x - _kChromePad,
      top: b.y - _kBarH,
      child: IgnorePointer(
        ignoring: inkToolActive,
        // Raw pointer stream: claims the pointer so the canvas ignores it, and
        // drives text drag-selection. `deferToChild` (the default) means the
        // reserved margin does NOT claim clicks that miss the content — a
        // click just outside a box still creates a new text box.
        child: Listener(
          onPointerDown: _pointerDown,
          onPointerMove: _pointerMove,
          onPointerUp: _pointerUp,
          onPointerCancel: _pointerUp,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    _kChromePad, _kBarH, _kChromePad, _kChromePad),
                child: _MeasureSize(
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
                  child: touchable,
                ),
              ),
              if (showChrome)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: _kBarH,
                  child: _moveBar(context, primaryColor, dark),
                ),
              // Resize handles. Now that the chrome sits INSIDE the render
              // box, each handle's full visual extent is grabbable instead of
              // the 4px sliver that was all the old negative offsets left
              // inside the box.
              if (primary && !_locked) ...[
                Positioned(
                  right: 0,
                  top: _kBarH,
                  bottom: 0,
                  width: _kChromePad + 6,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: GestureDetector(
                      supportedDevices: devices,
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
                    left: _kChromePad,
                    right: _kChromePad + 12,
                    bottom: 0,
                    height: _kChromePad + 6,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeUpDown,
                      child: GestureDetector(
                        supportedDevices: devices,
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
                    right: 1,
                    bottom: 1,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeDownRight,
                      child: GestureDetector(
                        supportedDevices: devices,
                        onPanUpdate: (d) =>
                            _resizeBy(d, width: true, height: true),
                        onPanEnd: (_) => _resizeUndoPushed = false,
                        child: Container(
                          width: 14,
                          height: 14,
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
            ],
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
