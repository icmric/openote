/// **Turning a function into something to draw** (plan: v0.23 §5).
///
/// Deliberately free of Flutter beyond `Offset`: everything here is arithmetic
/// over maths coordinates, so the hard parts — where a curve breaks, how tall
/// the window should be — are testable without a widget tree standing up
/// around them.
///
/// The four traps this exists to get right, each of which produces a
/// *plausible but wrong picture* rather than an error:
///
///  1. **An asymptote is not an infinity.** `tan(x)` at π/2 measures
///     1.63×10¹⁶ — a perfectly finite double — so testing `isInfinite` misses
///     every pole a student will actually plot, and the curve is drawn with a
///     near-vertical line joining +∞ to −∞ straight through the axis. The test
///     has to be geometric: two samples on OPPOSITE sides of the window, both
///     outside it, is a pole between them.
///  2. **A run of NaN is one gap, not a thousand.** `sqrt(x)` left of zero has
///     no value at any sample; emitting a break per sample makes the polyline
///     list as long as the sample count.
///  3. **One pole must not flatten the curve.** Auto-fitting y to the extremes
///     of `1/x` gives a window millions of units tall in which every
///     interesting feature is a flat line on the axis. Percentiles, not
///     extremes.
///  4. **Samples are pixels, not units.** A block painter draws in page units
///     inside the canvas transform, so the sample count has to follow the
///     zoom or a magnified curve turns into a polygon.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'evaluate.dart';
import 'math_linear_projection.dart';
import 'math_parse.dart';

/// The window a graph looks through, in maths units.
class GraphView {
  const GraphView({
    required this.x0,
    required this.x1,
    required this.y0,
    required this.y1,
  });

  /// What a new graph shows before anybody moves it: ten each way, which
  /// holds a line, a parabola and one period of a degrees-mode sine.
  static const GraphView initial =
      GraphView(x0: -10, x1: 10, y0: -10, y1: 10);

  final double x0, x1, y0, y1;

  double get width => x1 - x0;
  double get height => y1 - y0;
  double get midX => (x0 + x1) / 2;
  double get midY => (y0 + y1) / 2;

  bool get isSane =>
      width.isFinite &&
      height.isFinite &&
      width > 1e-9 &&
      height > 1e-9 &&
      width < 1e12 &&
      height < 1e12;

  GraphView panned(double dx, double dy) =>
      GraphView(x0: x0 + dx, x1: x1 + dx, y0: y0 + dy, y1: y1 + dy);

  /// Zoom about a point in maths coordinates — the point under the pointer
  /// stays under the pointer, which is what makes a wheel zoom feel like a
  /// zoom rather than a jump.
  GraphView zoomed(double factor, {double? aboutX, double? aboutY}) {
    final cx = aboutX ?? midX;
    final cy = aboutY ?? midY;
    return GraphView(
      x0: cx + (x0 - cx) * factor,
      x1: cx + (x1 - cx) * factor,
      y0: cy + (y0 - cy) * factor,
      y1: cy + (y1 - cy) * factor,
    );
  }

  Map<String, double> toJson() => {'x0': x0, 'x1': x1, 'y0': y0, 'y1': y1};

  static GraphView fromJson(Object? raw) {
    if (raw is! Map) return initial;
    double f(String k, double fallback) {
      final v = raw[k];
      return v is num && v.toDouble().isFinite ? v.toDouble() : fallback;
    }

    final v = GraphView(
      x0: f('x0', initial.x0),
      x1: f('x1', initial.x1),
      y0: f('y0', initial.y0),
      y1: f('y1', initial.y1),
    );
    return v.isSane ? v : initial;
  }

  @override
  bool operator ==(Object other) =>
      other is GraphView &&
      other.x0 == x0 &&
      other.x1 == x1 &&
      other.y0 == y0 &&
      other.y1 == y1;

  @override
  int get hashCode => Object.hash(x0, x1, y0, y1);

  @override
  String toString() => 'GraphView($x0..$x1, $y0..$y1)';
}

/// Everything the painter needs: the pieces of curve, and the window they are
/// drawn in (which may not be the window that was asked for, if the y range
/// was left to fit itself).
class Plot {
  const Plot({required this.pieces, required this.view, this.error});

  /// One list per unbroken run of the curve, in maths coordinates. A pole, a
  /// gap in the domain and the edge of the world all end a piece.
  final List<List<Offset>> pieces;

  final GraphView view;

  /// Why there is nothing to draw, in the words the calculator would use.
  final String? error;

  bool get isEmpty => pieces.every((p) => p.length < 2);
}

/// Sample [f] across [view] and cut it where it should be cut.
///
/// [samples] is a pixel count, not a taste: one sample per device pixel of
/// width is the point past which more samples cannot be seen.
Plot plotFunction(
  CompiledMath f,
  GraphView view, {
  required int samples,
  bool fitY = false,
}) {
  if (!f.isOk || f.at == null) {
    return Plot(pieces: const [], view: view, error: f.error);
  }
  if (!view.isSane) {
    return Plot(pieces: const [], view: GraphView.initial, error: null);
  }
  final at = f.at!;
  final n = samples.clamp(2, 4000);
  final step = view.width / (n - 1);

  // Pass one: the values. Kept because fitting y needs all of them and
  // because the break test needs its neighbours.
  final xs = List<double>.filled(n, 0);
  final ys = List<double>.filled(n, 0);
  for (var k = 0; k < n; k++) {
    final x = view.x0 + step * k;
    xs[k] = x;
    ys[k] = at(x);
  }

  final drawn = fitY ? _fitY(view, ys) : view;

  // Pass two: cut it into pieces.
  final pieces = <List<Offset>>[];
  var current = <Offset>[];
  void endPiece() {
    if (current.length > 1) pieces.add(current);
    current = <Offset>[];
  }

  for (var k = 0; k < n; k++) {
    final y = ys[k];
    if (!y.isFinite) {
      // Trap 2: a run of NaN is ONE gap. The piece is already ended, and
      // ending it again would push an empty list per sample.
      endPiece();
      continue;
    }
    if (current.isNotEmpty && _breaks(ys[k - 1], y, drawn)) {
      // Trap 1: a pole. Walk a few bisections toward it from each side so
      // the curve visibly runs off the top and the bottom rather than
      // stopping a whole pixel short.
      current.add(_towardPole(at, xs[k - 1], xs[k], drawn, fromLeft: true));
      endPiece();
      current.add(_towardPole(at, xs[k - 1], xs[k], drawn, fromLeft: false));
    }
    current.add(Offset(xs[k], y));
  }
  endPiece();

  return Plot(pieces: pieces, view: drawn);
}

/// **Two samples on opposite sides of the window, both outside it.**
///
/// Nothing continuous can do that in one pixel, and everything with a pole
/// does it at every pole. Testing the magnitude of the jump instead would
/// break a genuinely steep curve, and testing `isInfinite` would miss
/// `tan(π/2)`, which is 1.63×10¹⁶ and perfectly finite.
bool _breaks(double a, double b, GraphView v) {
  if (!a.isFinite || !b.isFinite) return true;
  final aAbove = a > v.y1, aBelow = a < v.y0;
  final bAbove = b > v.y1, bBelow = b < v.y0;
  return (aAbove && bBelow) || (aBelow && bAbove);
}

/// The last point on one side of a pole that is still worth drawing.
Offset _towardPole(double Function(double) at, double xa, double xb,
    GraphView v, {required bool fromLeft}) {
  var lo = xa, hi = xb;
  var best = fromLeft ? xa : xb;
  for (var step = 0; step < 8; step++) {
    final mid = (lo + hi) / 2;
    final y = at(mid);
    final onOurSide = y.isFinite &&
        (fromLeft ? !_breaks(at(xa), y, v) : !_breaks(y, at(xb), v));
    if (onOurSide) {
      best = mid;
      if (fromLeft) {
        lo = mid;
      } else {
        hi = mid;
      }
    } else {
      if (fromLeft) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
  }
  final y = at(best);
  // Clamped well outside the window so the drawn line leaves the top or the
  // bottom edge rather than bending toward a point just off it.
  final far = v.height * 4;
  return Offset(
      best, y.isFinite ? y.clamp(v.y0 - far, v.y1 + far) : v.y1 + far);
}

/// **Fit y to what the curve mostly does**, not to what it does at its worst.
///
/// Trap 3: `1/x` near zero reaches ten million, and a window ten million tall
/// draws every other feature as a flat line on the axis. The middle 96% of
/// the finite values is what a student is actually looking at.
GraphView _fitY(GraphView view, List<double> ys) {
  final finite = [for (final y in ys) if (y.isFinite) y]..sort();
  if (finite.length < 2) return view;
  double at(double q) =>
      finite[(q * (finite.length - 1)).round().clamp(0, finite.length - 1)];
  var lo = at(0.02), hi = at(0.98);
  // Zero earns its place when the curve comes anywhere near it: an axis you
  // cannot see is a graph with no frame of reference.
  if (lo > 0 && lo < (hi - lo)) lo = 0;
  if (hi < 0 && -hi < (hi - lo)) hi = 0;
  if (hi - lo < 1e-9) {
    // A constant function. Give it room either side so the line is not
    // pinned to an edge.
    final pad = math.max(hi.abs(), 1.0);
    lo -= pad;
    hi += pad;
  } else {
    final pad = (hi - lo) * 0.08;
    lo -= pad;
    hi += pad;
  }
  return GraphView(x0: view.x0, x1: view.x1, y0: lo, y1: hi);
}

/// **The spacing of the gridlines**, chosen so the numbers on them are ones a
/// person would write: 1, 2, 5, 10, 20, 50 and so on.
///
/// [target] is roughly how many lines are wanted across the span.
double gridStep(double span, {int target = 8}) {
  if (!span.isFinite || span <= 0) return 1;
  final rough = span / target;
  final mag = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
  final norm = rough / mag;
  final nice = norm < 1.5
      ? 1.0
      : norm < 3.5
          ? 2.0
          : norm < 7.5
              ? 5.0
              : 10.0;
  return nice * mag;
}

/// A gridline's label, short enough to sit under a tick.
String gridLabel(double v, double step) {
  if (v == 0) return '0';
  // How many decimals the STEP needs — so a run of ticks reads 0.2, 0.4, 0.6
  // rather than 0.2, 0.4000000001.
  final decimals = step >= 1
      ? 0
      : math.min(6, (-(math.log(step) / math.ln10)).ceil() + 0);
  if (v.abs() >= 1e6 || (v.abs() < 1e-4 && v != 0)) {
    return v.toStringAsPrecision(3);
  }
  var s = v.toStringAsFixed(decimals);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return s == '-0' ? '0' : s;
}

/// **What a graph makes of an equation.**
///
/// The owner writes `y = 3x + 10` in their notes and asks for a graph of it,
/// so the reading has to start at the LaTeX the equation editor stores and
/// end at something a painter can call.
///
/// Three shapes, and nothing clever beyond them:
///
///  * `y = f(x)`, or any single name on the left — the curve is the right
///    hand side. This is nearly everything.
///  * `x = 3` — a vertical line, which is not a function of x at all and
///    would otherwise be refused with a confusing message.
///  * `3x + 10` with no equals sign — taken as the curve itself, because a
///    student who selects an expression and asks for a graph means that.
///
/// Anything else says why in the calculator's own words. There is no solving:
/// `x^2 + y^2 = 9` is a circle and this returns the reason rather than half
/// of one.
class GraphSource {
  const GraphSource.curve(this.fn)
      : verticalAt = null,
        error = null;
  const GraphSource.vertical(this.verticalAt)
      : fn = null,
        error = null;
  const GraphSource.failed(this.error)
      : fn = null,
        verticalAt = null;

  final CompiledMath? fn;

  /// The x of a vertical line, for `x = 3`.
  final double? verticalAt;

  final String? error;

  bool get isOk => error == null;
}

/// Read [latex] as something to draw.
GraphSource graphSourceFromLatex(String latex) {
  final t = latex.trim();
  if (t.isEmpty) return const GraphSource.failed('nothing to graph yet');
  final parsed = parseLatex(t);
  if (!parsed.supported || parsed.root == null) {
    return GraphSource.failed(
        'this equation uses something the grapher cannot read yet');
  }
  final linear = rowToLinear(parsed.root!).trim();
  return graphSourceFromLinear(linear);
}

/// The same reading, from the linear form the calculator speaks.
GraphSource graphSourceFromLinear(String linear) {
  final t = linear.trim();
  if (t.isEmpty) return const GraphSource.failed('nothing to graph yet');
  final eq = t.indexOf('=');
  if (eq < 0) {
    final f = compileFunction(t);
    return f.isOk ? GraphSource.curve(f) : GraphSource.failed(f.error);
  }
  final left = t.substring(0, eq).trim();
  final right = t.substring(eq + 1).trim();
  if (right.contains('=')) {
    return const GraphSource.failed('one equals sign, please');
  }
  if (right.isEmpty) return const GraphSource.failed('nothing to graph yet');

  // `x = 3`: a vertical line, and the only shape here that is not a function.
  if (left == 'x') {
    final v = evaluateLinear(right);
    if (v.isOk && v.value.isFinite) return GraphSource.vertical(v.value);
    return const GraphSource.failed(
        'a vertical line needs a number on the right');
  }
  // Anything else on the left is a name for the curve — `y`, `f(x)`, `h`.
  // What it is called changes nothing about what is drawn.
  if (left.contains('x')) {
    // …unless x is on BOTH sides, which is an equation to solve rather than
    // a curve to draw.
    if (!RegExp(r'^[A-Za-z]+\s*\(\s*x\s*\)$').hasMatch(left)) {
      return const GraphSource.failed(
          'x is on both sides — that is an equation to solve, not a curve');
    }
  }
  final f = compileFunction(right);
  return f.isOk ? GraphSource.curve(f) : GraphSource.failed(f.error);
}

