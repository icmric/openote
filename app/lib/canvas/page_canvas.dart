import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../ui/context_menus.dart';
import 'block_view.dart';
import 'align_guides.dart';
import 'canvas_controller.dart';
import 'ink_ops.dart';
import 'media_drop.dart';
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

  /// Bumped per wet-ink point so ONLY the ink layer repaints (the painter
  /// listens via `repaint:`). A setState per pointer move rebuilt every
  /// visible block at stylus rate — the "inking feels sluggish" report.
  final ValueNotifier<int> _wetTick = ValueNotifier(0);
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

  /// When a stylus was last seen, so palm rejection can be *conditional*
  /// (INK-4) instead of absolute.
  ///
  /// The previous rule sent every touch to pan unconditionally, which does
  /// implement palm rejection — and also means **a finger can never draw**, so
  /// on a touch-only tablet ink was simply unreachable, contradicting INK-1.
  /// The distinction the old rule missed is that a resting palm is only a
  /// hazard when a pen is in use; with no pen present, a finger is the only
  /// input the user has.
  DateTime? _lastStylus;

  /// True while a file drag hovers the page, for the drop affordance.
  bool _dragOver = false;

  /// A palm rests *while* writing, so the window only has to outlive the gap
  /// between strokes, not a pause for thought.
  static const _stylusGrace = Duration(seconds: 2);

  bool get _stylusActive {
    final t = _lastStylus;
    return t != null && DateTime.now().difference(t) < _stylusGrace;
  }

  /// Whether this touch should draw rather than pan.
  ///
  /// Single finger only: a second finger always means pan/zoom, which is what
  /// every drawing app does and what makes the canvas navigable while a drawing
  /// tool is selected.
  bool _touchDraws() => touchShouldDraw(
        mode: app.touchDrawing,
        activeTouches: _touches.length,
        stylusActive: _stylusActive,
      );

  void _noteStylus(PointerEvent e) {
    if (e.kind == PointerDeviceKind.stylus ||
        e.kind == PointerDeviceKind.invertedStylus) {
      _lastStylus = DateTime.now();
    }
  }

  /// Abandon the stroke in progress without committing it — used when a second
  /// finger lands, turning what looked like a draw into a pinch. Without this
  /// the first finger of every two-finger gesture would leave a stray mark.
  void _cancelWetStroke() {
    if (_wet != null) setState(() => _wet = null);
  }

  bool get _lassoTool => app.tool == Tool.lasso;

  /// Decoded strokes per ink block, tagged with the `updatedAt` they were
  /// decoded at: strokes are decoded once per edit, not on every frame
  /// (§7a.6 — no hot-path JSON decoding).
  ///
  /// Keyed by **block id alone**, with the revision stored alongside, so a block
  /// that changes replaces its own entry. The previous key was
  /// `'$id#$updatedAt'` with a `length > 128 → clear()` guard, which meant a
  /// continuous erase gesture (every pointer sample bumps `updatedAt`) piled up
  /// 128 dead entries and then wiped the cache for *every* block on the page,
  /// forcing a full re-decode mid-gesture.
  final Map<String, ({int rev, List<Stroke> strokes})> _strokeCache = {};

  List<Stroke> _strokesOf(Block b) {
    final hit = _strokeCache[b.id];
    if (hit != null && hit.rev == b.updatedAt) return hit.strokes;
    final decoded = [
      for (final sj in b.content['strokes'] as List)
        Stroke.fromJson((sj as Map).cast<String, dynamic>()),
    ];
    _strokeCache[b.id] = (rev: b.updatedAt, strokes: decoded);
    return decoded;
  }

  @override
  void dispose() {
    _wetTick.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.pageSize = app.pageSize();
      // Restore this page's remembered view if the user actually adjusted it
      // (§7a.5); otherwise fit the page width so content placed off to the
      // right — e.g. imported images at their OneNote offsets — is visible on
      // open instead of sitting off-screen. A stored default view (100%,
      // top-left) counts as "unadjusted" and gets the fit.
      final mem = app.pageId == null ? null : app.viewFor(app.pageId!);
      if (mem != null && !(mem[0] == 1.0 && mem[1] == 0.0 && mem[2] == 0.0)) {
        controller.jumpTo(mem[0], Offset(mem[1], mem[2]));
        controller.clampToPage();
      } else {
        controller.fitWidth(app.contentExtent().right);
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
    // Repaint-only: grow the stroke and nudge the ink painter. No setState —
    // rebuilding every visible block per point made inking sluggish.
    _addPoint(e, _clampToPagePoint(controller.screenToPage(e.localPosition)));
    _wetTick.value++;
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
    final r2 = radius * radius;
    // INK-6: 'area' rubs points out mid-stroke (splitting survivors); 'stroke'
    // removes any stroke the eraser touches whole — OneNote's default, and the
    // mode that makes cleaning up a scratched-out word one swipe instead of
    // twenty.
    final wholeStroke = app.eraserMode == EraserMode.stroke;
    var changed = false;
    for (final b in app.blocks.where((b) => b.type == BlockType.ink)) {
      // Cheap reject: the eraser can only affect a block whose rect it touches.
      // This runs per pointer sample, so skipping distant blocks before looking
      // at any stroke is what keeps erasing cheap on an ink-heavy page.
      if (!_blockRect(b).inflate(radius).contains(pt)) continue;
      final strokes = (b.content['strokes'] as List);
      // Reuse the decoded strokes rather than re-parsing JSON per sample.
      final decoded = _strokesOf(b);
      final out = <Map<String, dynamic>>[];
      var blockChanged = false;
      for (var si = 0; si < strokes.length; si++) {
        final sj = strokes[si] as Map;
        final s = si < decoded.length
            ? decoded[si]
            : Stroke.fromJson(sj.cast<String, dynamic>());
        // Squared distance — avoids a sqrt per point per sample.
        final keep = List<bool>.generate(s.x.length, (i) {
          final dx = s.x[i] - pt.dx, dy = s.y[i] - pt.dy;
          return dx * dx + dy * dy >= r2;
        });
        if (!keep.contains(false)) {
          out.add(sj.cast<String, dynamic>());
          continue;
        }
        if (wholeStroke) {
          // Touched at all → the whole stroke goes; no splitting.
          blockChanged = true;
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
              // Carry per-point channels through the split, or erasing would
              // quietly strip tilt from the surviving runs.
              tx: s.tx.isEmpty ? [] : s.tx.sublist(i, j),
              ty: s.ty.isEmpty ? [] : s.ty.sublist(i, j),
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

    Widget canvas = LayoutBuilder(builder: (context, constraints) {
      controller.viewport = Size(constraints.maxWidth, constraints.maxHeight);
      return AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
        // Visible page-space rect (padded) for culling (CANVAS-9). Computed
        // INSIDE the AnimatedBuilder: the transform changes without a full
        // rebuild (viewport assignment above, per-page view restore, pans), and
        // a culling list captured outside would go stale — the "page is blank
        // until I scroll" bug, where the first frame culled everything against
        // an uninitialised viewport and nothing invalidated the list.
        final visible = Rect.fromPoints(
          controller.screenToPage(Offset.zero),
          controller.screenToPage(
              Offset(controller.viewport.width, controller.viewport.height)),
        ).inflate(200);
        final inkBlocks = app.blocks.where((b) => b.type == BlockType.ink);
        final visibleStrokes = [
          for (final b in inkBlocks)
            // Never cull the selected/editing block (CANVAS-9), so a selected
            // ink block off-screen still paints under its selection rect.
            if (app.selectedIds.contains(b.id) ||
                app.editingBlockId == b.id ||
                visible.overlaps(_blockRect(b)))
              ..._strokesOf(b),
        ];
        final selectedInkRects = [
          for (final b in inkBlocks)
            if (app.selectedIds.contains(b.id)) _blockRect(b),
        ];
        return RepaintBoundary(
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
                      sheet: app.pageProps.isPaged
                          ? Size(app.pageProps.paper.width,
                              app.pageProps.paper.height)
                          : null,
                      sheets: app.sheetCount,
                    ),
                  ),
                ),
                // Page space. `Positioned(left/top only)` gives loose
                // constraints so the inner Stack can be sized to the FULL page
                // (not the viewport). This is essential for hit-testing: a Stack
                // sized to the viewport refuses pointer events on children below
                // the fold, so clicks on a tall text box's lower half used to
                // fall through and create a new box (the reported bug).
                Positioned(
                  left: 0,
                  top: 0,
                  child: Transform(
                    transform: controller.matrix,
                    child: SizedBox(
                      width: pageSize.width,
                      height: pageSize.height,
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
                                painter: InkPainter(visibleStrokes,
                                    wet: _wet,
                                    // Per-point repaint without widget rebuild.
                                    repaint: _wetTick,
                                    // Theme default for "auto" strokes: dark
                                    // ink on light pages, light ink on dark.
                                    autoColor: dark
                                        ? OnoteColors.moon100
                                        : OnoteColors.graphite900),
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
                        // insertion order used to win) — except that the
                        // SELECTION outranks z. Hit-testing follows paint
                        // order, so a selected box whose end runs under a
                        // neighbour could not be resized or have its text
                        // reached where they overlap: the neighbour's opaque
                        // body swallowed the click. The box the user chose is
                        // the box the mouse should mean, so it paints (and
                        // therefore hit-tests) above everything while
                        // selected, and drops back into place on deselect.
                        for (final b in ([
                          ...app.blocks.where((b) =>
                              b.type != BlockType.ink &&
                              (visible.overlaps(_blockRect(b)) ||
                                  app.selectedIds.contains(b.id) ||
                                  app.editingBlockId == b.id))
                        ]..sort((a, b) {
                            int lift(Block x) => app.selectedIds.contains(x.id) ||
                                    app.editingBlockId == x.id
                                ? 1
                                : 0;
                            final byLift = lift(a) - lift(b);
                            return byLift != 0 ? byLift : a.z.compareTo(b.z);
                          })))
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
                ),
                // Alignment grid — only visible while dragging a block
                // effectiveSnap, not snapToGrid: holding Ctrl mid-drag pulls
                // the block out of the grid, and the grid must stop being
                // drawn at the same moment or the overlay is telling the user
                // something that is no longer true.
                if (app.draggingBlock && app.effectiveSnap)
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
                // Alignment guides (CANVAS-7), above the grid so they read as
                // the stronger signal while dragging.
                if (app.alignGuides.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _AlignGuidePainter(
                          controller: controller,
                          guides: app.alignGuides,
                          color: Theme.of(context).colorScheme.primary,
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
        );
        },
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
      // Palm rejection (INK-4), stylus-CONDITIONAL. Pen and mouse always draw.
      // A finger draws too — unless a stylus is in use, in which case touch
      // reverts to pan/pinch so a resting palm never marks the page (OneNote's
      // "draw with pen, navigate with touch"). A second finger always pans,
      // whatever the setting, so the canvas stays navigable while a drawing
      // tool is selected. See `app.touchDrawing` for the user override.
      canvas = Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          _noteStylus(e);
          if (e.kind != PointerDeviceKind.touch) {
            _inkDown(e);
            return;
          }
          _touches[e.pointer] = e.localPosition;
          if (_touches.length > 1) {
            // The first finger may already be mid-stroke; a pinch is not a
            // drawing, so drop it rather than leaving a stray mark.
            _cancelWetStroke();
            _touchDown(e);
            return;
          }
          if (_touchDraws()) {
            _touches.remove(e.pointer); // it's a drawing pointer, not a gesture
            _inkDown(e);
          } else {
            _touches.remove(e.pointer); // _touchDown re-adds and sets up pinch
            _touchDown(e);
          }
        },
        onPointerMove: (e) {
          _noteStylus(e);
          if (_touches.containsKey(e.pointer)) {
            _touchMove(e);
          } else {
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
        onPointerCancel: (e) {
          _touches.remove(e.pointer);
          _cancelWetStroke();
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

    // Drag-and-drop (MEDIA-1): files dropped anywhere on the page land where
    // they were dropped. Wraps the whole canvas so the drop target matches
    // what the user sees, and highlights only while a drag is over it.
    canvas = DropTarget(
      onDragEntered: (_) => setState(() => _dragOver = true),
      onDragExited: (_) => setState(() => _dragOver = false),
      onDragDone: (details) async {
        setState(() => _dragOver = false);
        // `details.localPosition` is ALREADY local to this DropTarget —
        // desktop_drop calls globalToLocal itself. Converting a second time
        // subtracted the canvas's global origin (navigator width, command-bar
        // height) again, so every dropped file landed up and to the left of
        // the cursor. That was survivable while a drop made a floating block;
        // it is not, now that the drop point decides which text box you are
        // dropping INTO.
        final at = controller.screenToPage(details.localPosition);
        final n = await dropFilesOntoCanvas(
            app, [for (final f in details.files) f.path], at,
            dark: Theme.of(context).brightness == Brightness.dark);
        if (n > 0 && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Added $n item${n == 1 ? '' : 's'}')));
        }
      },
      child: Stack(children: [
        canvas,
        if (_dragOver)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: .06),
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 1.5),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Text('Drop to add to this page'),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );

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
    this.sheet,
    this.sheets = 1,
  });
  final CanvasController controller;
  final Size pageSize;
  final String background;
  final double gridSize;
  final bool dark;

  /// The paper, when this page is in paged mode. Null on open canvas.
  final Size? sheet;

  /// How many sheets of it the content occupies.
  final int sheets;

  @override
  void paint(Canvas canvas, Size size) {
    final pageColor = dark ? OnoteColors.night0 : OnoteColors.paper0;
    final paper = sheet;
    if (paper != null) {
      // A SHEET has edges, and edges are the whole point of page mode: the
      // desk around it is darker so the paper reads as an object you could
      // pick up, and where one sheet ends the next begins. Canvas mode paints
      // the viewport all one colour precisely because it has no edges.
      canvas.drawRect(Offset.zero & size,
          Paint()..color = dark ? OnoteColors.night200 : OnoteColors.paper200);
      final topLeft = controller.pageToScreen(Offset.zero);
      final w = paper.width * controller.scale;
      final h = paper.height * controller.scale;
      final shadow = Paint()
        ..color = Colors.black.withValues(alpha: dark ? .35 : .12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      for (var i = 0; i < sheets; i++) {
        final r = Rect.fromLTWH(topLeft.dx, topLeft.dy + h * i, w, h);
        // Skip sheets that are nowhere near the viewport: a fifty-page essay
        // must not cost fifty shadow blurs a frame.
        if (r.bottom < -h || r.top > size.height + h) continue;
        canvas.drawRect(r.deflate(1).shift(const Offset(0, 2)), shadow);
        canvas.drawRect(r, Paint()..color = pageColor);
      }
      _paintPattern(canvas, size);
      // The break between sheets, drawn last so it sits over the pattern.
      final edge = Paint()
        ..color = dark ? OnoteColors.night300 : OnoteColors.paper300
        ..strokeWidth = 1;
      for (var i = 1; i < sheets; i++) {
        final y = topLeft.dy + h * i;
        if (y < 0 || y > size.height) continue;
        canvas.drawLine(Offset(topLeft.dx, y), Offset(topLeft.dx + w, y), edge);
      }
      return;
    }
    // Seamless: the whole viewport is the page colour — one consistent
    // surface at every zoom (the backdrop and page are the same thing).
    canvas.drawRect(Offset.zero & size, Paint()..color = pageColor);
    _paintPattern(canvas, size);
  }

  void _paintPattern(Canvas canvas, Size size) {

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
      old.sheet != sheet ||
      old.sheets != sheets ||
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

/// Draws the alignment guides while a block is being dragged.
///
/// Screen-space, one physical pixel wide at any zoom: a guide scaled with the
/// page becomes a fat bar zoomed in and invisible zoomed out, when what it
/// needs to be is a hairline that says "these edges match".
class _AlignGuidePainter extends CustomPainter {
  _AlignGuidePainter({
    required this.controller,
    required this.guides,
    required this.color,
  }) : super(repaint: controller);

  final CanvasController controller;
  final List<AlignGuide> guides;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: .85)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (final g in guides) {
      final a = controller.pageToScreen(
          g.vertical ? Offset(g.position, g.from) : Offset(g.from, g.position));
      final b = controller.pageToScreen(
          g.vertical ? Offset(g.position, g.to) : Offset(g.to, g.position));
      // Extend a little past both blocks so the line clearly spans them.
      const overhang = 10.0;
      final dir = g.vertical ? const Offset(0, 1) : const Offset(1, 0);
      canvas.drawLine(a - dir * overhang, b + dir * overhang, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AlignGuidePainter old) =>
      old.guides != guides || old.color != color;
}
