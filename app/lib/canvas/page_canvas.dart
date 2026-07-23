import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../ui/context_menus.dart';
import 'block_view.dart';
import 'canvas_controller.dart';
import 'ink_painter.dart';
import 'page_title_view.dart';

/// The page canvas (CANVAS-1 v0.3): an auto-growing page surface on a neutral
/// backdrop. Select-mode input model (style guide §8):
///   · click empty page (nothing selected)  → create text box, type (CANVAS-3)
///   · click empty page (something selected)→ deselect
///   · drag empty page                      → marquee multi-select (CANVAS-7)
///   · click ink                            → select ink block; drag moves it
///   · middle-drag                          → pan · Ctrl+scroll → zoom
///   · trackpad pan/pinch                   → pan/zoom · two-finger touch → pinch
class PageCanvas extends StatefulWidget {
  const PageCanvas({super.key, required this.state});
  final AppState state;

  @override
  State<PageCanvas> createState() => _PageCanvasState();
}

enum _DragMode { none, pending, marquee, moveSelection, pan }

class _PageCanvasState extends State<PageCanvas> {
  Stroke? _wet;
  bool _eraseUndoPushed = false;
  bool _moveUndoPushed = false;

  _DragMode _mode = _DragMode.none;
  Offset _downScreen = Offset.zero;
  Offset _marqueeStartPage = Offset.zero;
  Offset _marqueeEndPage = Offset.zero;
  Offset _lastScreen = Offset.zero;

  // Two-finger touch pinch tracking.
  final Map<int, Offset> _touches = {};
  double? _pinchBaseDist;
  double _pzLastScale = 1.0;

  // Lasso-select (INK-7): the freeform loop being drawn, in page space.
  List<Offset>? _lasso;

  AppState get app => widget.state;
  CanvasController get controller => app.canvas;

  bool get _inkTool =>
      app.tool == Tool.pen || app.tool == Tool.highlighter || app.tool == Tool.eraser;

  bool get _lassoTool => app.tool == Tool.lasso;

  /// Decoded-stroke cache keyed by block id + updatedAt: strokes are decoded
  /// once per edit, not on every frame (§7a.6 — no hot-path JSON decoding).
  final Map<String, List<Stroke>> _strokeCache = {};

  List<Stroke> _strokesOf(Block b) {
    if (_strokeCache.length > 128) _strokeCache.clear();
    return _strokeCache.putIfAbsent(
      '${b.id}#${b.updatedAt}',
      () => [
        for (final sj in b.content['strokes'] as List)
          Stroke.fromJson((sj as Map).cast<String, dynamic>()),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.pageSize = app.pageSize();
      // Restore this page's remembered view (§7a.5), else the default.
      final mem = app.pageId == null ? null : app.viewFor(app.pageId!);
      if (mem != null) {
        controller.jumpTo(mem[0], Offset(mem[1], mem[2]));
        controller.clampToPage();
      } else {
        controller.centerPage();
      }
    });
  }

  // ── Ink capture (page-space, Ink Data Spec §1) ──────────────────────────

  void _inkDown(PointerDownEvent e) {
    app.claimedPointers.remove(e.pointer); // keep the claim set tidy
    final pt = _clampToPagePoint(controller.screenToPage(e.localPosition));
    if (app.tool == Tool.eraser) {
      _eraseAt(pt);
      return;
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final colors = app.tool == Tool.highlighter
        ? OnoteColors.highlighterColors
        : OnoteColors.penColors;
    var color = colors[app.penColor % colors.length];
    if (dark && color == OnoteColors.graphite900) color = OnoteColors.moon0;
    setState(() {
      _wet = Stroke(
        tool: app.tool == Tool.highlighter ? 'highlighter' : 'pen',
        colorHex:
            '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
        size: app.penSize,
        opacity: app.tool == Tool.highlighter ? 0.4 : 1.0,
      );
      _addPoint(e, pt);
    });
  }

  void _inkMove(PointerMoveEvent e) {
    if (app.tool == Tool.eraser) {
      _eraseAt(controller.screenToPage(e.localPosition));
      return;
    }
    if (_wet == null) return;
    setState(() =>
        _addPoint(e, _clampToPagePoint(controller.screenToPage(e.localPosition))));
  }

  Offset _clampToPagePoint(Offset p) =>
      Offset(math.max(0, p.dx), math.max(0, p.dy));

  void _addPoint(PointerEvent e, Offset pagePt) {
    final w = _wet!;
    w.x.add(pagePt.dx);
    w.y.add(pagePt.dy);
    w.p.add(e.pressure.isFinite && e.pressureMax > 0
        ? (e.pressure / e.pressureMax).clamp(0.0, 1.0)
        : 0.5);
    w.t.add(nowMs() - w.strokeStart);
  }

  void _inkUp(PointerUpEvent e) {
    _eraseUndoPushed = false;
    final w = _wet;
    if (w == null || w.x.length < 2) {
      setState(() => _wet = null);
      return;
    }
    app.pushUndo();
    Block? target;
    for (final b in app.blocks.reversed) {
      if (b.type == BlockType.ink &&
          nowMs() - b.updatedAt < 2000 &&
          (b.content['strokes'] as List).length < 512) {
        target = b;
        break;
      }
    }
    target ??= app.addBlock(
        Block(type: BlockType.ink, x: 0, y: 0, content: {'strokes': []}),
        recordUndo: false);
    (target.content['strokes'] as List).add(w.toJson());
    _refitInkBounds(target);
    app.updateBlock(target);
    setState(() => _wet = null);
  }

  /// True area-erase (INK-6, Ink Spec §2): remove points within the eraser
  /// radius and split surviving runs into fresh strokes.
  void _eraseAt(Offset pt) {
    if (!_eraseUndoPushed) {
      app.pushUndo();
      _eraseUndoPushed = true;
    }
    final radius = 12.0 / controller.scale;
    var changed = false;
    for (final b in app.blocks.where((b) => b.type == BlockType.ink)) {
      final strokes = (b.content['strokes'] as List);
      final out = <Map<String, dynamic>>[];
      var blockChanged = false;
      for (final sj in strokes) {
        final s = Stroke.fromJson((sj as Map).cast<String, dynamic>());
        final keep = List<bool>.generate(s.x.length,
            (i) => (Offset(s.x[i], s.y[i]) - pt).distance >= radius);
        if (!keep.contains(false)) {
          out.add(sj.cast<String, dynamic>());
          continue;
        }
        blockChanged = true;
        // Split surviving runs into new strokes (fresh ids per spec §2).
        var i = 0;
        while (i < keep.length) {
          if (!keep[i]) {
            i++;
            continue;
          }
          var j = i;
          while (j < keep.length && keep[j]) {
            j++;
          }
          if (j - i >= 2) {
            out.add(Stroke(
              tool: s.tool,
              colorHex: s.colorHex,
              size: s.size,
              opacity: s.opacity,
              x: s.x.sublist(i, j),
              y: s.y.sublist(i, j),
              p: s.p.isEmpty ? [] : s.p.sublist(i, j),
              t: s.t.sublist(i, j),
              strokeStart: s.strokeStart,
            ).toJson());
          }
          i = j;
        }
      }
      if (blockChanged) {
        changed = true;
        b.content['strokes'] = out;
        if (out.isNotEmpty) _refitInkBounds(b);
        app.updateBlock(b);
      }
    }
    if (changed) {
      app.blocks.removeWhere(
          (b) => b.type == BlockType.ink && (b.content['strokes'] as List).isEmpty);
      app.markDirty();
      setState(() {});
    }
  }

  void _refitInkBounds(Block b) {
    var mnx = double.infinity, mny = double.infinity, mxx = -1e18, mxy = -1e18;
    for (final sj in b.content['strokes'] as List) {
      final s = Stroke.fromJson((sj as Map).cast<String, dynamic>());
      final bb = s.bounds();
      mnx = math.min(mnx, bb.minX);
      mny = math.min(mny, bb.minY);
      mxx = math.max(mxx, bb.maxX);
      mxy = math.max(mxy, bb.maxY);
    }
    if (mnx.isFinite) {
      b
        ..x = mnx
        ..y = mny
        ..w = mxx - mnx
        ..h = mxy - mny;
    }
  }

  // ── Lasso-select ink (INK-7) ────────────────────────────────────────────

  void _lassoDown(PointerDownEvent e) {
    app.claimedPointers.remove(e.pointer);
    setState(() => _lasso = [
          _clampToPagePoint(controller.screenToPage(e.localPosition))
        ]);
  }

  void _lassoMove(PointerMoveEvent e) {
    if (_lasso == null) return;
    setState(() => _lasso!
        .add(_clampToPagePoint(controller.screenToPage(e.localPosition))));
  }

  void _lassoUp(PointerUpEvent e) {
    final poly = _lasso;
    setState(() => _lasso = null);
    if (poly == null || poly.length < 3) return;
    _gatherLassoedStrokes(poly);
  }

  /// Gather every stroke whose points mostly fall inside the drawn loop into a
  /// single new ink block, then select it — so the existing move/delete/copy
  /// machinery works on a freeform ink selection regardless of which blocks the
  /// strokes originally lived in (Ink Spec §2: strokes are immutable and carry
  /// page-absolute coordinates, so re-homing them is just a splice).
  void _gatherLassoedStrokes(List<Offset> poly) {
    // 1) Detect matches WITHOUT mutating, so the undo snapshot below captures
    //    the true pre-lasso state.
    final gathered = <Map<String, dynamic>>[];
    final keepByBlock = <String, List<dynamic>>{};
    for (final b in app.blocks.where((b) => b.type == BlockType.ink)) {
      final keep = <dynamic>[];
      var blockChanged = false;
      for (final sj in (b.content['strokes'] as List)) {
        final s = Stroke.fromJson((sj as Map).cast<String, dynamic>());
        if (_strokeInsidePoly(s, poly)) {
          gathered.add(sj.cast<String, dynamic>());
          blockChanged = true;
        } else {
          keep.add(sj);
        }
      }
      if (blockChanged) keepByBlock[b.id] = keep;
    }
    if (gathered.isEmpty) return;

    // 2) Snapshot, then apply: splice matched strokes out of their blocks,
    //    drop now-empty blocks, and re-home the gathered strokes into one new
    //    selected ink block.
    app.pushUndo();
    for (final entry in keepByBlock.entries) {
      final b = app.blocks.where((x) => x.id == entry.key).firstOrNull;
      if (b == null) continue;
      if (entry.value.isEmpty) {
        app.removeBlock(b.id, recordUndo: false);
      } else {
        b.content['strokes'] = entry.value;
        _refitInkBounds(b);
        b.updatedAt = nowMs();
      }
    }
    final grouped = app.addBlock(
        Block(type: BlockType.ink, x: 0, y: 0, content: {'strokes': gathered}),
        recordUndo: false);
    _refitInkBounds(grouped);
    app.updateBlock(grouped);
    app.select(grouped.id);
    // Switch back to Select so the gathered ink can be dragged/deleted at once.
    app.setTool(Tool.select);
  }

  /// A stroke counts as lassoed when the majority of its sample points lie
  /// inside the loop — robust to a stroke poking slightly outside the boundary.
  bool _strokeInsidePoly(Stroke s, List<Offset> poly) {
    if (s.x.isEmpty) return false;
    var inside = 0;
    for (var i = 0; i < s.x.length; i++) {
      if (_pointInPoly(Offset(s.x[i], s.y[i]), poly)) inside++;
    }
    return inside / s.x.length >= 0.6;
  }

  /// Ray-casting point-in-polygon test.
  bool _pointInPoly(Offset pt, List<Offset> poly) {
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final a = poly[i], b = poly[j];
      if (((a.dy > pt.dy) != (b.dy > pt.dy)) &&
          (pt.dx <
              (b.dx - a.dx) * (pt.dy - a.dy) / (b.dy - a.dy) + a.dx)) {
        inside = !inside;
      }
    }
    return inside;
  }

  // ── Touch pan/pinch (shared: pen-mode palm rejection & navigation) ──────

  void _touchDown(PointerDownEvent e) {
    _touches[e.pointer] = e.localPosition;
    _lastScreen = e.localPosition;
    if (_touches.length == 2) {
      final pts = _touches.values.toList();
      _pinchBaseDist = (pts[0] - pts[1]).distance;
    }
  }

  void _touchMove(PointerMoveEvent e) {
    _touches[e.pointer] = e.localPosition;
    if (_touches.length >= 2 && _pinchBaseDist != null) {
      final pts = _touches.values.toList();
      final d = (pts[0] - pts[1]).distance;
      final focal = (pts[0] + pts[1]) / 2;
      if (_pinchBaseDist! > 0 && d > 0) {
        controller.zoomAt(focal, d / _pinchBaseDist!);
        _pinchBaseDist = d;
      }
      setState(() {});
    } else if (_touches.length == 1) {
      controller.panBy(e.localPosition - _lastScreen);
      _lastScreen = e.localPosition;
      setState(() {});
    }
  }

  void _touchUp(PointerUpEvent e) {
    _touches.remove(e.pointer);
    if (_touches.length < 2) _pinchBaseDist = null;
    if (_touches.length == 1) _lastScreen = _touches.values.first;
  }

  // ── Select-mode pointer model ───────────────────────────────────────────

  Rect _blockRect(Block b) => Rect.fromLTWH(
      b.x, b.y, b.w, b.h ?? app.renderSizes[b.id]?.height ?? 60);

  String? _hitInk(Offset pagePt) {
    for (final b in app.blocks.reversed.where((b) => b.type == BlockType.ink)) {
      if (_blockRect(b).inflate(6).contains(pagePt)) return b.id;
    }
    return null;
  }

  void _selectDown(PointerDownEvent e) {
    if (app.claimedPointers.remove(e.pointer)) return; // a block owns this one
    _downScreen = e.localPosition;
    _lastScreen = e.localPosition;

    if (e.kind == PointerDeviceKind.mouse &&
        (e.buttons & kMiddleMouseButton) != 0) {
      _mode = _DragMode.pan;
      return;
    }
    // Right-click on empty canvas → context menu (blocks claim theirs first).
    if (e.kind == PointerDeviceKind.mouse &&
        (e.buttons & kSecondaryMouseButton) != 0) {
      _mode = _DragMode.none;
      showCanvasMenu(
          context, app, e.position, controller.screenToPage(e.localPosition));
      return;
    }
    if (e.kind == PointerDeviceKind.touch) {
      _touches[e.pointer] = e.localPosition;
      if (_touches.length == 2) {
        final pts = _touches.values.toList();
        _pinchBaseDist = (pts[0] - pts[1]).distance;
        _mode = _DragMode.none;
        return;
      }
    }

    final pagePt = controller.screenToPage(e.localPosition);
    final inkHit = _hitInk(pagePt);
    if (inkHit != null) {
      if (!app.selectedIds.contains(inkHit)) {
        app.select(inkHit,
            additive: HardwareKeyboard.instance.isShiftPressed);
      }
      _mode = _DragMode.moveSelection;
      _moveUndoPushed = false;
      app.setDragging(true);
      return;
    }
    _mode = _DragMode.pending;
    _marqueeStartPage = pagePt;
    _marqueeEndPage = pagePt;
  }

  void _selectMove(PointerMoveEvent e) {
    if (_touches.containsKey(e.pointer)) {
      _touches[e.pointer] = e.localPosition;
      if (_touches.length == 2 && _pinchBaseDist != null) {
        final pts = _touches.values.toList();
        final d = (pts[0] - pts[1]).distance;
        final focal = (pts[0] + pts[1]) / 2;
        if (_pinchBaseDist! > 0 && d > 0) {
          controller.zoomAt(focal, d / _pinchBaseDist!);
          _pinchBaseDist = d;
        }
        setState(() {});
        return;
      }
    }
    final delta = e.localPosition - _lastScreen;
    _lastScreen = e.localPosition;
    switch (_mode) {
      case _DragMode.pan:
        controller.panBy(delta);
        setState(() {});
      case _DragMode.pending:
        if ((e.localPosition - _downScreen).distance > 5) {
          _mode = _DragMode.marquee;
          _marqueeEndPage = controller.screenToPage(e.localPosition);
          setState(() {});
        }
      case _DragMode.marquee:
        _marqueeEndPage = controller.screenToPage(e.localPosition);
        setState(() {});
      case _DragMode.moveSelection:
        if (!_moveUndoPushed) {
          app.pushUndo();
          _moveUndoPushed = true;
        }
        app.moveSelectedBy(delta.dx / controller.scale, delta.dy / controller.scale);
      case _DragMode.none:
        break;
    }
  }

  void _selectUp(PointerUpEvent e) {
    _touches.remove(e.pointer);
    if (_touches.length < 2) _pinchBaseDist = null;
    final mode = _mode;
    _mode = _DragMode.none;
    switch (mode) {
      case _DragMode.pending:
        final pagePt = controller.screenToPage(e.localPosition);
        if (app.tool == Tool.text) {
          _createTextAt(pagePt); // Text tool: always create
        } else if (app.selectedIds.isNotEmpty || app.editingBlockId != null) {
          app.select(null); // first click clears; next click creates
        } else {
          // Click-anywhere-to-type (CANVAS-3). The seamless backdrop is part
          // of the page, so this also works out in the margin when zoomed out.
          _createTextAt(pagePt);
        }
      case _DragMode.marquee:
        final rect = Rect.fromPoints(_marqueeStartPage, _marqueeEndPage);
        final hit = [
          for (final b in app.blocks)
            if (rect.overlaps(_blockRect(b))) b.id
        ];
        hit.isEmpty ? app.select(null) : app.selectMany(hit);
        setState(() {});
      case _DragMode.moveSelection:
        app.settleSelected();
        app.setDragging(false);
        _moveUndoPushed = false;
      default:
        break;
    }
  }

  void _createTextAt(Offset pagePt) {
    // OneNote-style: interpret intent rather than land pixel-exact.
    final pos = app.smartTextPosition(pagePt);
    final b = app.addBlock(Block(
      type: BlockType.text,
      x: pos.dx,
      y: pos.dy,
      w: 320,
      content: {'text': ''},
    ));
    app.select(b.id, edit: true);
    if (app.tool == Tool.text) app.setTool(Tool.select);
  }

  // ── Wheel / trackpad ────────────────────────────────────────────────────

  void _onScroll(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final ctrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (ctrl) {
      controller.zoomAt(e.localPosition, e.scrollDelta.dy > 0 ? 1 / 1.1 : 1.1);
    } else if (shift) {
      // Shift+wheel → horizontal scroll (a mouse's vertical wheel drives X).
      controller.panBy(Offset(-e.scrollDelta.dy - e.scrollDelta.dx, 0));
    } else {
      controller.panBy(-e.scrollDelta);
    }
    setState(() {});
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Page size is content-driven (this bounds scrolling — constrained
    // horizontal at normal zoom). The backdrop is drawn the same colour as the
    // page (seamless — no "page floating on canvas"), and clicks anywhere in
    // the viewport create content, so zooming out lets you place a box out in
    // the margin; if you don't, the page reconstrains to content next frame.
    final ext = app.contentExtent();
    final pw =
        math.max(app.pageProps.pageWidth, ext.right + AppState.pageGrowMargin);
    final ph = math.max(
        AppState.defaultPageHeight, ext.bottom + AppState.pageGrowMargin);
    final pageSize = Size(pw, ph);
    controller.pageSize = pageSize;

    // Visible page-space rect (padded) for culling (CANVAS-9).
    final visible = Rect.fromPoints(
      controller.screenToPage(Offset.zero),
      controller.screenToPage(
          Offset(controller.viewport.width, controller.viewport.height)),
    ).inflate(200);

    final inkBlocks = app.blocks.where((b) => b.type == BlockType.ink);
    final visibleStrokes = [
      for (final b in inkBlocks)
        if (visible.overlaps(_blockRect(b))) ..._strokesOf(b),
    ];
    final selectedInkRects = [
      for (final b in inkBlocks)
        if (app.selectedIds.contains(b.id)) _blockRect(b),
    ];

    Widget canvas = LayoutBuilder(builder: (context, constraints) {
      controller.viewport = Size(constraints.maxWidth, constraints.maxHeight);
      return AnimatedBuilder(
        animation: controller,
        builder: (context, _) => RepaintBoundary(
          key: app.canvasKey,
          child: ClipRect(
            child: Stack(
              children: [
                // Backdrop + page surface + page background pattern
                Positioned.fill(
                  child: CustomPaint(
                    painter: _PagePainter(
                      controller: controller,
                      pageSize: pageSize,
                      background: app.pageProps.background,
                      gridSize: app.gridSize,
                      dark: dark,
                    ),
                  ),
                ),
                // Page space
                Positioned.fill(
                  child: Transform(
                    transform: controller.matrix,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 0,
                          top: 0,
                          child: IgnorePointer(
                            child: RepaintBoundary(
                              child: CustomPaint(
                                size: Size.zero,
                                painter: InkPainter(visibleStrokes, wet: _wet),
                              ),
                            ),
                          ),
                        ),
                        // In-page title band (OneNote-style)
                        Positioned(
                          left: AppState.pageLeftMargin,
                          top: 20,
                          child: IgnorePointer(
                            ignoring: _inkTool,
                            child: PageTitleView(
                              key: ValueKey('title-${app.pageId}'),
                              app: app,
                              width: pageSize.width -
                                  AppState.pageLeftMargin * 2,
                            ),
                          ),
                        ),
                        // Painted in z order (review fix: z was stored but
                        // insertion order used to win).
                        for (final b in ([
                          ...app.blocks.where((b) =>
                              b.type != BlockType.ink &&
                              (visible.overlaps(_blockRect(b)) ||
                                  app.selectedIds.contains(b.id) ||
                                  app.editingBlockId == b.id))
                        ]..sort((a, b) => a.z.compareTo(b.z))))
                          BlockView(
                            key: ValueKey('${b.id}#${app.docRevision}'),
                            block: b,
                            app: app,
                            controller: controller,
                          ),
                      ],
                    ),
                  ),
                ),
                // Alignment grid — only visible while dragging a block
                if (app.draggingBlock && app.snapToGrid)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _DragGridPainter(
                          controller: controller,
                          gridSize: app.gridSize,
                          dark: dark,
                        ),
                      ),
                    ),
                  ),
                // Marquee + selected-ink outlines (screen-space overlay)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _OverlayPainter(
                        controller: controller,
                        marquee: _mode == _DragMode.marquee
                            ? Rect.fromPoints(_marqueeStartPage, _marqueeEndPage)
                            : null,
                        inkSelections: selectedInkRects,
                        lasso: _lasso,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });

    if (_lassoTool) {
      // Lasso: draw a freeform loop; on release, the enclosed strokes are
      // gathered into one selection.
      canvas = Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _lassoDown,
        onPointerMove: _lassoMove,
        onPointerUp: _lassoUp,
        child: canvas,
      );
    } else if (_inkTool) {
      // Palm rejection (INK-4): the pen (stylus) and mouse draw; fingers
      // (touch) pan/pinch instead of drawing — so a resting palm never marks
      // the page. Matches OneNote's default "draw with pen, navigate with
      // touch" behaviour.
      canvas = Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          if (e.kind == PointerDeviceKind.touch) {
            _touchDown(e);
          } else {
            _inkDown(e);
          }
        },
        onPointerMove: (e) {
          if (_touches.containsKey(e.pointer)) {
            _touchMove(e);
          } else if (e.kind != PointerDeviceKind.touch) {
            _inkMove(e);
          }
        },
        onPointerUp: (e) {
          if (_touches.containsKey(e.pointer)) {
            _touchUp(e);
          } else {
            _inkUp(e);
          }
        },
        child: canvas,
      );
    } else {
      canvas = Listener(
        onPointerDown: _selectDown,
        onPointerMove: _selectMove,
        onPointerUp: _selectUp,
        behavior: HitTestBehavior.translucent,
        child: canvas,
      );
    }

    return Listener(
      onPointerSignal: _onScroll,
      onPointerPanZoomStart: (e) => _pzLastScale = 1.0,
      onPointerPanZoomUpdate: (e) {
        if (e.scale != 1.0) {
          controller.zoomAt(e.localPosition, e.scale / _pzLastScale);
          _pzLastScale = e.scale;
        }
        if (e.panDelta != Offset.zero) controller.panBy(e.panDelta);
        setState(() {});
      },
      child: MouseRegion(
        cursor: switch (app.tool) {
          Tool.text => SystemMouseCursors.text,
          Tool.pen || Tool.highlighter => SystemMouseCursors.precise,
          Tool.eraser => SystemMouseCursors.cell,
          Tool.lasso => SystemMouseCursors.precise,
          _ => MouseCursor.defer,
        },
        child: canvas,
      ),
    );
  }
}

/// The page surface. At normal zoom the page fills the whole viewport so it
/// reads as one continuous page (no "page floating on a desk"). Only when
/// zoomed out (<85%) does it draw as a bounded sheet on a backdrop, revealing
/// that it's a page you can treat as a canvas.
class _PagePainter extends CustomPainter {
  _PagePainter({
    required this.controller,
    required this.pageSize,
    required this.background,
    required this.gridSize,
    required this.dark,
  });
  final CanvasController controller;
  final Size pageSize;
  final String background;
  final double gridSize;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final pageColor = dark ? OnoteColors.night0 : OnoteColors.paper0;
    // Seamless: the whole viewport is the page colour — one consistent
    // surface at every zoom (the backdrop and page are the same thing).
    canvas.drawRect(Offset.zero & size, Paint()..color = pageColor);

    // Background pattern (blank = nothing). Drawn across the visible area but
    // starting below the title band and aligned to the content top, so the
    // lines don't run over the title and match the writing spacing.
    if (background == 'blank') return;
    final step = gridSize * controller.scale;
    if (step < 6) return;
    final originY = controller.pageToScreen(
        const Offset(0, AppState.contentTop)).dy;
    final right = size.width, bottom = size.height;
    final paint = Paint()
      ..color = dark ? OnoteColors.night200 : OnoteColors.paper200
      ..strokeWidth = 1;
    switch (background) {
      case 'grid':
        final ox = controller.offset.dx % step;
        for (var x = ox; x <= right; x += step) {
          canvas.drawLine(Offset(x, originY), Offset(x, bottom), paint);
        }
        for (var y = originY; y <= bottom; y += step) {
          canvas.drawLine(Offset(0, y), Offset(right, y), paint);
        }
      case 'ruled':
        for (var y = originY; y <= bottom; y += step) {
          canvas.drawLine(Offset(0, y), Offset(right, y), paint);
        }
      case 'dotted':
        final dot = Paint()..color = paint.color;
        final ox = controller.offset.dx % step;
        for (var x = ox; x <= right; x += step) {
          for (var y = originY; y <= bottom; y += step) {
            canvas.drawCircle(Offset(x, y), 1.2, dot);
          }
        }
    }
  }

  @override
  bool shouldRepaint(covariant _PagePainter old) =>
      old.background != background ||
      old.dark != dark ||
      old.pageSize != pageSize ||
      old.controller.scale != controller.scale ||
      old.controller.offset != controller.offset;
}

/// Faint alignment grid shown only while a block is being dragged.
class _DragGridPainter extends CustomPainter {
  _DragGridPainter(
      {required this.controller, required this.gridSize, required this.dark});
  final CanvasController controller;
  final double gridSize;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final step = gridSize * controller.scale;
    if (step < 6) return;
    final paint = Paint()
      ..color = (dark ? OnoteColors.night200 : OnoteColors.paper200)
          .withValues(alpha: .7)
      ..strokeWidth = 1;
    final ox = controller.offset.dx % step;
    final oy = controller.offset.dy % step;
    for (var x = ox; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = oy; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DragGridPainter old) =>
      old.controller.scale != controller.scale ||
      old.controller.offset != controller.offset ||
      old.dark != dark;
}

/// Marquee rectangle + dashed outlines for selected ink blocks.
class _OverlayPainter extends CustomPainter {
  _OverlayPainter({
    required this.controller,
    required this.marquee,
    required this.inkSelections,
    required this.lasso,
    required this.color,
  });
  final CanvasController controller;
  final Rect? marquee;
  final List<Rect> inkSelections;
  final List<Offset>? lasso;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final lassoPts = lasso;
    if (lassoPts != null && lassoPts.length > 1) {
      final path = Path()
        ..moveTo(
            controller.pageToScreen(lassoPts.first).dx,
            controller.pageToScreen(lassoPts.first).dy);
      for (final pt in lassoPts.skip(1)) {
        final sp = controller.pageToScreen(pt);
        path.lineTo(sp.dx, sp.dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: .08));
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = color.withValues(alpha: .7));
    }
    if (marquee != null) {
      final r = Rect.fromPoints(controller.pageToScreen(marquee!.topLeft),
          controller.pageToScreen(marquee!.bottomRight));
      canvas.drawRect(r, Paint()..color = color.withValues(alpha: .08));
      canvas.drawRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = color.withValues(alpha: .6));
    }
    for (final pr in inkSelections) {
      final r = Rect.fromPoints(controller.pageToScreen(pr.topLeft),
              controller.pageToScreen(pr.bottomRight))
          .inflate(4);
      _dashedRect(canvas, r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color);
    }
  }

  void _dashedRect(Canvas canvas, Rect r, Paint p) {
    const dash = 6.0, gap = 4.0;
    void line(Offset a, Offset b) {
      final total = (b - a).distance;
      final dir = (b - a) / total;
      var d = 0.0;
      while (d < total) {
        final e = math.min(d + dash, total);
        canvas.drawLine(a + dir * d, a + dir * e, p);
        d = e + gap;
      }
    }

    line(r.topLeft, r.topRight);
    line(r.topRight, r.bottomRight);
    line(r.bottomRight, r.bottomLeft);
    line(r.bottomLeft, r.topLeft);
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) =>
      old.marquee != marquee ||
      old.inkSelections.length != inkSelections.length ||
      old.lasso != lasso ||
      (lasso?.length ?? 0) != (old.lasso?.length ?? 0) ||
      old.controller.offset != controller.offset ||
      old.controller.scale != controller.scale;
}
