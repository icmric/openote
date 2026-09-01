/// **A graph on the page** (plan: v0.23 §5, owner brief B15–B18).
///
/// The owner: *"Id like to be able to write an equation (such as y = 3x+10) in
/// my notes in the maths type, then either highlight it and have some option
/// to 'create graph' … and have it insert a graph, not touching the written
/// equation but inserting a new graph element on the page which i can move
/// around seperatley but is still tied to that equation (so if i then update
/// it to y = 2x+6 that change is reflected in the graph)."*
///
/// ## What it stores, and why
///
/// ```
/// content: {
///   'latex':  'y=3x+10',     // its OWN truth
///   'from':   '<block id>',  // the equation it follows, when there is one
///   'view':   {x0,x1,y0,y1}, // where it is looking
///   'fitY':   true,          // until somebody moves it by hand
/// }
/// ```
///
/// **The graph owns a copy of the equation.** The v0.22 plan settled this and
/// it still holds: a graph that is only a pointer draws nothing once the
/// equation is deleted, and exports and prints as an empty box. So the latex
/// is the graph's own, and `from` is how it FOLLOWS: editing the equation
/// pushes the new latex into every graph that names it
/// (`AppState.pushEquationToGraphs`). A `from` that names nothing — the
/// equation was deleted, or the graph was copied to another page — simply
/// stops following, and the link highlight switches off with it. Nothing
/// breaks; the graph keeps drawing what it was last told.
///
/// ## The window survives an undo
///
/// `BlockView`'s key carries `app.docRevision`, and an undo anywhere on the
/// page bumps it — so every block widget is destroyed and rebuilt. Pan and
/// zoom therefore live in `content['view']`, not in this State, or a Ctrl+Z
/// on some other block would jump every graph back to the origin.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../math/graph_plot.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';

class GraphBlockView extends StatefulWidget {
  const GraphBlockView({super.key, required this.block, required this.app});

  final Block block;
  final AppState app;

  @override
  State<GraphBlockView> createState() => _GraphBlockViewState();
}

class _GraphBlockViewState extends State<GraphBlockView> {
  Block get b => widget.block;

  String get _latex => b.content['latex'] as String? ?? '';

  /// The window. Until somebody has moved it, one chosen for what is being
  /// drawn — see [initialViewFor], and the sine that arrived as a straight
  /// line.
  GraphView get _view => b.content['view'] == null
      ? initialViewFor(_latex)
      : GraphView.fromJson(b.content['view']);

  /// True until the student moves the window themselves. Fitting the height
  /// to the curve is right for a graph that has just been made and wrong the
  /// moment somebody has said where they want to look.
  bool get _fitY => b.content['fitY'] != false;

  // The compiled function, kept across rebuilds so a repaint that changes
  // nothing does not re-read the equation. Keyed on the source, which is the
  // only thing that can invalidate it.
  String? _compiledFrom;
  GraphSource? _source;

  GraphSource get _sourceFor {
    if (_compiledFrom != _latex || _source == null) {
      _compiledFrom = _latex;
      _source = graphSourceFromLatex(_latex);
    }
    return _source!;
  }

  /// The window the curve was last actually DRAWN in.
  ///
  /// A fitted graph is drawn in a window the fit chose, which is not the one
  /// stored on the block, and a drag has to start from what is on screen or
  /// the first movement jumps. Held here rather than written back: the fit
  /// reads the samples, the number of samples follows the canvas zoom, so
  /// storing it turned scrolling around a page into an EDIT — a bumped
  /// timestamp, a save, and a git commit for a change nobody made.
  GraphView? _drawn;

  /// What is on screen: the fitted window if there is one, else the stored.
  GraphView get _live => _drawn ?? _view;

  void _setView(GraphView v) {
    if (!v.isSane) return;
    b.content['view'] = v.toJson();
    b.content['fitY'] = false;
    _drawn = null;
    b.updatedAt = nowMs();
    widget.app.markDirty();
    setState(() {});
  }

  /// Back to a window that holds the curve. The one gesture that undoes any
  /// amount of getting lost.
  void _reset() {
    b.content.remove('view');
    b.content['fitY'] = true;
    _drawn = null;
    b.updatedAt = nowMs();
    widget.app.markDirty();
    setState(() {});
  }

  // ── gestures ────────────────────────────────────────────────────────────
  //
  // The block claims its pointers, or the canvas pans at the same time as the
  // graph does; and `BlockView` is told not to move the block on a body drag
  // (see its `_bodyDragStart` opt-out), or the graph would slide out from
  // under the gesture it is answering.

  Size _lastSize = Size.zero;

  void _pan(DragUpdateDetails d) {
    if (_lastSize.isEmpty) return;
    _setView(_panned(_live, d.delta));
  }

  GraphView _panned(GraphView v, Offset screenDelta) => v.panned(
        -screenDelta.dx * v.width / _lastSize.width,
        screenDelta.dy * v.height / _lastSize.height,
      );

  GraphView _zoomedAbout(GraphView v, double factor, Offset localPosition) {
    final aboutX = v.x0 + (localPosition.dx / _lastSize.width) * v.width;
    final aboutY = v.y1 - (localPosition.dy / _lastSize.height) * v.height;
    return v.zoomed(factor, aboutX: aboutX, aboutY: aboutY);
  }

  /// Zoom the window under the pointer.
  ///
  /// **Through the resolver**, because a wheel notch is delivered to EVERY
  /// listener under the pointer and the page canvas has one of its own: one
  /// notch used to zoom the graph and scroll the page out from under it at
  /// the same time. Registering makes it the innermost claim, and the
  /// innermost registrant is the one that runs. The claim on pointer DOWN
  /// beside this (which is what stops a drag panning the page) never covered
  /// signals — a wheel notch has no pointer to claim.
  void _wheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || _lastSize.isEmpty) return;
    // **Sideways is not a zoom.** A trackpad's horizontal swipe, a tilt
    // wheel and Shift+wheel all arrive here with dy of zero, and the
    // up-or-down test had no middle: five sideways flicks magnified the
    // graph four times over and turned its auto-fit off for good.
    if (e.scrollDelta.dy == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (_) {
      _setView(_zoomedAbout(
          _live, e.scrollDelta.dy > 0 ? 1.15 : 1 / 1.15, e.localPosition));
    });
  }

  /// Cumulative scale since the LAST update, for a trackpad pinch — see
  /// [_panZoomUpdate].
  double _pzLastScale = 1.0;

  /// **A trackpad's two-finger pan and pinch, isolated from the page the
  /// same way the wheel and a mouse drag already are.**
  ///
  /// Reported: scrolling and zooming inside a graph moved the page
  /// underneath it too. A wheel notch goes through the shared
  /// [GestureBinding.pointerSignalResolver] (see [_wheel]) and a mouse
  /// drag is kept out by [_GraphBlockViewState]'s own pointer-down claim —
  /// but `PointerPanZoomStartEvent`/`UpdateEvent` are a THIRD event family,
  /// dispatched to every `Listener` along the hit-test chain like an
  /// ordinary pointer event rather than funnelled through one shared
  /// resolver. Neither existing mechanism touched it at all: the graph
  /// never claimed the pointer for it, and `page_canvas.dart`'s own handler
  /// never checked whether anything inner had. Both sides are fixed
  /// together — this claims the pointer on start, and `PageCanvas` now
  /// declines to move for a pointer that is already claimed.
  void _panZoomStart(PointerPanZoomStartEvent e) {
    widget.app.claimedPointers.add(e.pointer);
    _pzLastScale = 1.0;
  }

  void _panZoomUpdate(PointerPanZoomUpdateEvent e) {
    if (_lastSize.isEmpty) return;
    var v = _live;
    // **Zooming and panning are mutually exclusive within a single frame.**
    //
    // Reported: pinching a trackpad "zooms a bit but also moves me heaps
    // too" — working fine with a mouse, and "with touch it seems to work
    // alright ... although its pretty jagged". A trackpad's own gesture
    // recognition is not clean two-finger-centroid data: the pan it reports
    // alongside a pinch is largely an artifact of the pinch itself, not the
    // student asking to pan, and running it through the same conversion an
    // intentional two-finger PAN uses reads as a much bigger, unwanted
    // slide — the jaggedness on touch is this same stray pan, smaller but
    // still there every frame.
    //
    // Which this frame actually is gets told apart by comparing the
    // cumulative scale to what it was LAST frame, not to 1.0: an unchanged
    // scale is an ordinary pan (exactly what already worked), a changed one
    // is a pinch, and its own residual pan is discarded rather than
    // trusted — zooming about the pointer already keeps the point under the
    // fingers fixed, which is all a pinch is asking for.
    if (e.scale != _pzLastScale) {
      // Inverted relative to `CanvasController.zoomAt`'s convention: a
      // GraphView's factor multiplies its SPAN, so spreading fingers apart
      // (scale rising) must SHRINK the window to read as zooming in, the
      // opposite of a magnification level rising.
      v = _zoomedAbout(v, _pzLastScale / e.scale, e.localPosition);
      _pzLastScale = e.scale;
    } else if (e.panDelta != Offset.zero) {
      v = _panned(v, e.panDelta);
    }
    _setView(v);
  }

  void _panZoomEnd(PointerPanZoomEndEvent e) {
    widget.app.claimedPointers.remove(e.pointer);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final source = _sourceFor;
    // **The link, shown only while one end of it is chosen.** The owner:
    // *"should ONLY EVER be visible when one is clicked AND there is a linked
    // graph, i dont want the highlighting to be always there ... This should
    // work both ways."* `graphLinkHighlight` already encodes "one end of the
    // link is selected" — it says so for THIS graph when the graph itself is
    // selected, and it says so just as much when the EQUATION is. Re-checking
    // "is the graph itself selected" here, as this used to, threw the second
    // half away: clicking the equation could never light up its graph's
    // border, only the reverse. Plain selection (no link, or a link neither
    // end of which is chosen) already gets its own indicator from the
    // enclosing `BlockView`'s border, so this one has nothing left to decide
    // beyond the link itself.
    final linkOn = widget.app.graphLinkHighlight(b) != null;

    return Listener(
      onPointerSignal: _wheel,
      onPointerDown: (e) => widget.app.claimedPointers.add(e.pointer),
      onPointerPanZoomStart: _panZoomStart,
      onPointerPanZoomUpdate: _panZoomUpdate,
      onPointerPanZoomEnd: _panZoomEnd,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() {
          _hovering = false;
          _hoverLocal = null;
        }),
        onHover: (e) => setState(() => _hoverLocal = e.localPosition),
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            _AltAwarePan:
                GestureRecognizerFactoryWithHandlers<_AltAwarePan>(
              _AltAwarePan.new,
              (r) => r.onUpdate = _pan,
            ),
            DoubleTapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<DoubleTapGestureRecognizer>(
              DoubleTapGestureRecognizer.new,
              (r) => r.onDoubleTap = _reset,
            ),
          },
          child: LayoutBuilder(builder: (context, cons) {
            _lastSize = Size(cons.maxWidth, cons.maxHeight.isFinite
                ? cons.maxHeight
                : (b.h ?? 240));
            return Container(
              decoration: BoxDecoration(
                color: s.raised,
                borderRadius: BorderRadius.circular(OnoteRadius.md),
                border: Border.all(
                  color: linkOn ? widget.app.graphLinkHighlight(b)! : s.border,
                  width: linkOn ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: source.isOk
                        ? _canvas(context, source)
                        : _problem(
                            context, source.error ?? 'nothing to graph yet'),
                  ),
                  // **The way back, once there is somewhere to come back
                  // from.** Reported: "If it has bene moved/changed there
                  // should be some way for me to reset it back to the
                  // default too." Double-tap already does this — it always
                  // has — but nothing on screen ever said so, which is not
                  // a way to reset a graph, it's a way to have one. Shown
                  // only once `_fitY` is false: a graph nobody has touched
                  // has nothing to reset, and a button that always does
                  // nothing is worse than no button.
                  if (_hovering && !_fitY)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: _ResetButton(onPressed: _reset),
                    ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  bool _hovering = false;

  /// Raw pointer position, in this widget's own local coordinates — the
  /// same space [_lastSize] measures. Cleared on exit; see [_canvas] for
  /// what it turns into.
  Offset? _hoverLocal;

  Widget _canvas(BuildContext context, GraphSource source) {
    final s = context.surfaces;
    final scheme = Theme.of(context).colorScheme;
    // Samples follow the ZOOM: a block painter draws in page units inside the
    // canvas transform, so a magnified curve drawn at block-width resolution
    // turns into a polygon.
    final px = (_lastSize.width * widget.app.canvas.scale)
        .clamp(2.0, 4000.0)
        .round();
    final plot = source.verticalAt != null
        ? Plot(pieces: const [], view: _view)
        : plotFunction(source.fn!, _view, samples: px, fitY: _fitY);
    // Remembered, so the next drag starts from where the curve actually is
    // rather than from where it was asked to be. Not stored — see [_drawn].
    _drawn = _fitY && plot.view.isSane ? plot.view : null;

    // **Hover, against the window actually ON SCREEN.** Reported: "id like
    // to be able to hover over a point on the line and have it provide me
    // the values for that point." `plot.view`, not `_view`: a fitted graph
    // draws in a window the fit chose, and matching the hit-test to a
    // window that is not what is drawn would put the dot wherever the
    // cursor is over a DIFFERENT curve's worth of geometry.
    final hover = _hoverLocal == null
        ? null
        : hoverPointNear(_hoverLocal!,
            source: source, view: plot.view, size: _lastSize);

    return RepaintBoundary(
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              size: Size.infinite,
              painter: GraphPainter(
                plot: plot,
                verticalAt: source.verticalAt,
                hover: hover,
                curve: scheme.primary,
                axis: s.textSecondary,
                grid: s.border,
                label: s.textSecondary,
                hoverDot: scheme.primary,
              ),
            ),
          ),
          if (hover != null) _HoverLabel(hover: hover, size: _lastSize),
        ],
      ),
    );
  }

  Widget _problem(BuildContext context, String why) {
    final s = context.surfaces;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.show_chart, size: 20, color: s.textSecondary),
            const SizedBox(height: 6),
            Text(why,
                textAlign: TextAlign.center,
                style: OnoteType.small.copyWith(color: s.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// **The numbers beside the dot.** A widget, not painted text inside
/// [GraphPainter] — ordinary `Text` layout is one line instead of a
/// hand-measured box, and it is what lets the values come from [gridLabel]
/// unchanged rather than a second formatting path.
///
/// Sits on whichever side of the dot has room, judged by which half of the
/// graph the dot is in — there is no text measurement to consult before the
/// label itself is built, so this is a rule of thumb rather than a
/// guarantee, but a label a few pixels from an edge is a cosmetic slip; one
/// that could clip off it entirely is not.
class _HoverLabel extends StatelessWidget {
  const _HoverLabel({required this.hover, required this.size});

  final HoverPoint hover;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final onRight = hover.screen.dx < size.width / 2;
    final onBottom = hover.screen.dy < size.height / 2;
    final text = hover.y.isNaN
        ? 'x = ${hover.xLabel}'
        : 'x = ${hover.xLabel}, y = ${hover.yLabel}';
    return Positioned(
      left: onRight ? hover.screen.dx + 8 : null,
      right: onRight ? null : size.width - hover.screen.dx + 8,
      top: onBottom ? hover.screen.dy + 8 : null,
      bottom: onBottom ? null : size.height - hover.screen.dy + 8,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: s.raised.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: s.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            child: Text(text,
                style: OnoteType.small.copyWith(
                    color: s.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ),
      ),
    );
  }
}

/// A small, quiet way back to the default window — see the comment where
/// this is placed for the report it answers. Deliberately not a full
/// `IconButton`'s 48px tap target: at that size, in a graph's own corner,
/// it would eat the one place a student might want to pan or zoom FROM.
class _ResetButton extends StatelessWidget {
  const _ResetButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    return Tooltip(
      message: 'Reset the view',
      child: Material(
        color: s.raised.withValues(alpha: 0.85),
        shape: const CircleBorder(),
        elevation: 1,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(Icons.restart_alt, size: 16, color: s.textSecondary),
          ),
        ),
      ),
    );
  }
}

/// The picture itself.
///
/// Everything is drawn in DEVICE coordinates from maths coordinates through
/// one mapping, so there is exactly one place a sign or a flip can be wrong.
/// A pan that stands aside while Alt is held.
///
/// **Alt-drag moves the BLOCK** — the escape hatch every block whose body
/// belongs to something else has, and the one `BlockView._bodyDragStart`
/// spells out for a graph by name. The graph's own pan used to win the
/// gesture arena outright, so that promise was unreachable and the title bar
/// was the only way to move a graph on the page. Declining the pointer, as
/// opposed to accepting it and doing nothing, is what lets the block's
/// recogniser have it.
class _AltAwarePan extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (HardwareKeyboard.instance.isAltPressed) return;
    super.addAllowedPointer(event);
  }

  /// **Never a trackpad's own pan/zoom.**
  ///
  /// `PanGestureRecognizer` (via `DragGestureRecognizer`) accepts a
  /// `PointerPanZoomStartEvent` by default, exactly like an ordinary
  /// pointer-down — so this recognizer was quietly running a SECOND,
  /// competing pan from the very same physical gesture [_panZoomUpdate]
  /// already answers, on top of whatever that method decided. Reported:
  /// pinching "zooms a bit but also moves me heaps too", and on a
  /// touchscreen "it seems to work alright ... although its pretty
  /// jagged" — both are this recognizer's own drag update fighting the
  /// zoom-about-the-pointer [_panZoomUpdate] had already applied, every
  /// single frame. The trackpad/touch stream is claimed and answered
  /// entirely by this widget's `Listener.onPointerPanZoom*` callbacks;
  /// this recognizer has no business seeing it at all.
  @override
  bool isPointerPanZoomAllowed(PointerPanZoomStartEvent event) => false;
}

class GraphPainter extends CustomPainter {
  const GraphPainter({
    required this.plot,
    required this.curve,
    required this.axis,
    required this.grid,
    required this.label,
    this.verticalAt,
    this.hover,
    this.hoverDot,
  });

  final Plot plot;
  final double? verticalAt;
  final Color curve;
  final Color axis;
  final Color grid;
  final Color label;

  /// Where the cursor has found itself close to the curve, if anywhere —
  /// see `_GraphBlockViewState._canvas`. Drawn as a small dot; the numbers
  /// beside it are [_HoverLabel]'s job, a plain widget rather than painted
  /// text, so they get ordinary layout instead of a hand-measured box.
  final HoverPoint? hover;
  final Color? hoverDot;

  @override
  void paint(Canvas canvas, Size size) {
    final v = plot.view;
    if (!v.isSane || size.isEmpty) return;
    double sx(double x) => (x - v.x0) / v.width * size.width;
    // y grows UP in maths and DOWN on a screen. One flip, here.
    double sy(double y) => size.height - (y - v.y0) / v.height * size.height;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = axis
      ..strokeWidth = 1.4;

    // ── gridlines and their numbers ──────────────────────────────────────
    final stepX = gridStep(v.width, target: math.max(3, size.width ~/ 90));
    final stepY = gridStep(v.height, target: math.max(3, size.height ~/ 60));
    for (final x in ticks(v.x0, v.x1, stepX)) {
      canvas.drawLine(Offset(sx(x), 0), Offset(sx(x), size.height), gridPaint);
    }
    for (final y in ticks(v.y0, v.y1, stepY)) {
      canvas.drawLine(Offset(0, sy(y)), Offset(size.width, sy(y)), gridPaint);
    }

    // ── the axes, drawn where they are and pinned to the edge when the
    //    origin is off screen, so a graph is never unlabelled ─────────────
    final xAxisY = sy(0).clamp(0.5, size.height - 0.5);
    final yAxisX = sx(0).clamp(0.5, size.width - 0.5);
    canvas.drawLine(
        Offset(0, xAxisY), Offset(size.width, xAxisY), axisPaint);
    canvas.drawLine(
        Offset(yAxisX, 0), Offset(yAxisX, size.height), axisPaint);

    // ── the numbers ──────────────────────────────────────────────────────
    void text(String t, Offset at, {bool rightAlign = false}) {
      final tp = TextPainter(
        text: TextSpan(
            text: t,
            style: TextStyle(fontSize: 9, color: label, height: 1)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at.translate(rightAlign ? -tp.width : 0, 0));
    }

    for (final x in ticks(v.x0, v.x1, stepX)) {
      if (x.abs() < stepX / 1000) continue; // the origin is labelled once
      text(gridLabel(x, stepX),
          Offset(sx(x) + 2, (xAxisY + 2).clamp(0, size.height - 12)));
    }
    for (final y in ticks(v.y0, v.y1, stepY)) {
      if (y.abs() < stepY / 1000) continue;
      text(gridLabel(y, stepY),
          Offset((yAxisX - 3).clamp(12, size.width), sy(y) + 1),
          rightAlign: true);
    }

    // ── the curve ────────────────────────────────────────────────────────
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final line = Paint()
      ..color = curve
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    if (verticalAt != null) {
      final x = sx(verticalAt!);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (final piece in plot.pieces) {
      if (piece.length < 2) continue;
      final path = Path()..moveTo(sx(piece.first.dx), sy(piece.first.dy));
      for (var k = 1; k < piece.length; k++) {
        path.lineTo(sx(piece[k].dx), sy(piece[k].dy));
      }
      canvas.drawPath(path, line);
    }

    final h = hover;
    if (h != null && hoverDot != null) {
      canvas.drawCircle(
          h.screen, 3.5, Paint()..color = hoverDot!..style = PaintingStyle.fill);
      canvas.drawCircle(
          h.screen,
          3.5,
          Paint()
            ..color = axis
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(GraphPainter old) =>
      old.plot != plot ||
      old.verticalAt != verticalAt ||
      old.curve != curve ||
      old.axis != axis ||
      old.grid != grid ||
      old.hover?.screen != hover?.screen;
}
