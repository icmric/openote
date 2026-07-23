import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
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

  AppState get app => widget.state;
  CanvasController get controller => app.canvas;

  bool get _inkTool =>
      app.tool == Tool.pen || app.tool == Tool.highlighter || app.tool == Tool.eraser;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.pageSize = app.pageSize();
      controller.centerPage();
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
        if (app.tool == Tool.text && _insidePage(pagePt)) {
          _createTextAt(pagePt); // Text tool: always create
        } else if (app.selectedIds.isNotEmpty || app.editingBlockId != null) {
          app.select(null); // first click clears; next click creates
        } else if (_insidePage(pagePt)) {
          _createTextAt(pagePt); // CANVAS-3: click-anywhere-to-type
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
        _moveUndoPushed = false;
      default:
        break;
    }
  }

  bool _insidePage(Offset p) {
    final ps = controller.pageSize ?? Size.zero;
    return p.dx >= 0 && p.dy >= 0 && p.dx <= ps.width && p.dy <= ps.height;
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
    if (ctrl) {
      controller.zoomAt(e.localPosition, e.scrollDelta.dy > 0 ? 1 / 1.1 : 1.1);
    } else {
      controller.panBy(-e.scrollDelta);
    }
    setState(() {});
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Effective on-screen page size: content-driven, but at least filling the
    // viewport in normal zoom so the page reads like a page (no backdrop);
    // zoom out (<0.85) and it stops chasing so the page bounds become visible.
    final ext = app.contentExtent();
    var pw = math.max(app.pageProps.pageWidth, ext.right + AppState.pageGrowMargin);
    var ph = math.max(AppState.defaultPageHeight, ext.bottom + AppState.pageGrowMargin);
    if (controller.scale >= 0.85 && controller.viewport != Size.zero) {
      final rv = controller.screenToPage(
          Offset(controller.viewport.width, controller.viewport.height));
      pw = math.max(pw, rv.dx);
      ph = math.max(ph, rv.dy);
    }
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
        if (visible.overlaps(_blockRect(b)))
          for (final sj in b.content['strokes'] as List)
            Stroke.fromJson((sj as Map).cast<String, dynamic>()),
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
                      snapOverlay: app.snapToGrid,
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
                            child: CustomPaint(
                              size: Size.zero,
                              painter: InkPainter(visibleStrokes, wet: _wet),
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
                        for (final b in app.blocks.where((b) =>
                            b.type != BlockType.ink &&
                            (visible.overlaps(_blockRect(b)) ||
                                app.selectedIds.contains(b.id) ||
                                app.editingBlockId == b.id)))
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

    if (_inkTool) {
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
          _ => MouseCursor.defer,
        },
        child: canvas,
      ),
    );
  }
}

/// Backdrop + page surface + page background pattern (clipped to the page).
class _PagePainter extends CustomPainter {
  _PagePainter({
    required this.controller,
    required this.pageSize,
    required this.background,
    required this.gridSize,
    required this.snapOverlay,
    required this.dark,
  });
  final CanvasController controller;
  final Size pageSize;
  final String background;
  final double gridSize;
  final bool snapOverlay;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    // Backdrop
    canvas.drawRect(Offset.zero & size,
        Paint()..color = dark ? OnoteColors.night50 : OnoteColors.paper100);

    // Page surface (screen-space rect)
    final tl = controller.pageToScreen(Offset.zero);
    final br = controller.pageToScreen(Offset(pageSize.width, pageSize.height));
    final page = Rect.fromPoints(tl, br);
    canvas.drawRRect(
      RRect.fromRectAndRadius(page.shift(const Offset(0, 2)), const Radius.circular(2)),
      Paint()
        ..color = Colors.black.withValues(alpha: dark ? .5 : .10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRect(
        page, Paint()..color = dark ? OnoteColors.night0 : OnoteColors.paper0);
    canvas.drawRect(
        page,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = dark ? OnoteColors.night300 : OnoteColors.paper300);

    // Background pattern, clipped to the page
    final mode = snapOverlay && background == 'blank' ? 'grid' : background;
    if (mode == 'blank') return;
    final step = gridSize * controller.scale;
    if (step < 6) return;
    canvas.save();
    canvas.clipRect(page);
    final paint = Paint()
      ..color = dark ? OnoteColors.night200 : OnoteColors.paper200
      ..strokeWidth = 1;
    switch (mode) {
      case 'grid':
        for (var x = page.left; x <= page.right; x += step) {
          canvas.drawLine(Offset(x, page.top), Offset(x, page.bottom), paint);
        }
        for (var y = page.top; y <= page.bottom; y += step) {
          canvas.drawLine(Offset(page.left, y), Offset(page.right, y), paint);
        }
      case 'ruled':
        final ruled = step * 1.4;
        for (var y = page.top + ruled; y <= page.bottom; y += ruled) {
          canvas.drawLine(Offset(page.left, y), Offset(page.right, y), paint);
        }
      case 'dotted':
        final dot = Paint()..color = paint.color;
        for (var x = page.left; x <= page.right; x += step) {
          for (var y = page.top; y <= page.bottom; y += step) {
            canvas.drawCircle(Offset(x, y), 1.2, dot);
          }
        }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PagePainter old) =>
      old.background != background ||
      old.snapOverlay != snapOverlay ||
      old.dark != dark ||
      old.pageSize != pageSize ||
      old.controller.scale != controller.scale ||
      old.controller.offset != controller.offset;
}

/// Marquee rectangle + dashed outlines for selected ink blocks.
class _OverlayPainter extends CustomPainter {
  _OverlayPainter({
    required this.controller,
    required this.marquee,
    required this.inkSelections,
    required this.color,
  });
  final CanvasController controller;
  final Rect? marquee;
  final List<Rect> inkSelections;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
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
      old.controller.offset != controller.offset ||
      old.controller.scale != controller.scale;
}
