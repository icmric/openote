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
      height < 1e12 &&
      _resolvable(x0, x1) &&
      _resolvable(y0, y1);

  /// Can one gridline be told from the next?
  ///
  /// A window may be tiny, and it may be a long way from zero, but not both
  /// at once: past about a million million times its own width, adding a
  /// gridline's spacing to a coordinate does not change it, every number on
  /// the axis reads the same, and the loop that walks them never arrives.
  /// Refusing the zoom is the whole fix — the last window that made sense
  /// stays on screen.
  static bool _resolvable(double a, double b) =>
      math.max(a.abs(), b.abs()) < (b - a).abs() * 1e12;

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
  final fitted = GraphView(x0: view.x0, x1: view.x1, y0: lo, y1: hi);
  // **A fit the window cannot hold is not a window.** `y = x^13` over ten
  // each way runs to ten million million, and `10^{14}+x` is twenty units
  // tall a hundred million million from zero — both fail [GraphView.isSane],
  // and every consumer refuses an insane view in silence: the block draws an
  // empty box with no message, double-tap to reset fits the same one again,
  // and the PDF leaves the graph off the page altogether. The window that was
  // ASKED for is sane (checked in [plotFunction]) and at least shows the axes.
  return fitted.isSane ? fitted : view;
}

/// **The window a graph opens at**, when nobody has moved it yet.
///
/// Ten each way holds a line and a parabola, and it is the wrong window for a
/// sine: in degrees — which is the mode the app starts in — a wave is 360
/// wide, so the ordinary window shows five per cent of one and draws it as a
/// straight diagonal filling the block. The single most likely thing a
/// student graphs, drawn as the one shape it is not.
///
/// Only the x span moves. A fresh graph fits its own y.
GraphView initialViewFor(String source) {
  final t = source.toLowerCase();
  if (!RegExp(r'(sin|cos|tan|sec|csc|cot)\b').hasMatch(t)) {
    return GraphView.initial;
  }
  // The evaluator's own rule for "the angle said radians", so a window and
  // the curve in it can never disagree about which one is being drawn.
  if (t.contains('pi') || t.contains('π') || t.contains('°') ||
      t.contains('rad')) {
    return GraphView.initial;
  }
  if (mathAngleMode != AngleMode.degrees) return GraphView.initial;
  return const GraphView(x0: -360, x1: 360, y0: -10, y1: 10);
}

/// **The spacing of the gridlines**, chosen so the numbers on them are ones a
/// person would write: 1, 2, 5, 10, 20, 50 and so on.
///
/// [target] is roughly how many lines are wanted across the span.
double gridStep(double span, {int target = 8}) {
  if (!span.isFinite || span <= 0) return 1;
  final rough = span / target;
  // Below about 4e-324 the division underflows to zero, log(0) is -infinity
  // and `.floor()` throws; a decimal above it, `pow(10, -324)` IS zero and
  // this returns a spacing of 0, which is not a spacing. No caller can reach
  // either today — both check [GraphView.isSane] first — but this is a
  // public function and its only guard should not live in two other files.
  if (rough <= 0 || !rough.isFinite) return 1;
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

/// **Where the gridlines fall** across [lo]..[hi], walked by index rather
/// than by adding [step] up as it goes.
///
/// Two reasons. Adding drifts — a run of ticks becomes 0.2, 0.4, 0.6000001 —
/// and, worse, adding a small step to a large coordinate can fail to move it
/// at all, which turns a paint loop into a hang. Multiplying an index cannot
/// do either. The count is capped as well: nothing on screen needs four
/// thousand lines, so a window that asks for more gets none.
Iterable<double> ticks(double lo, double hi, double step) sync* {
  if (!step.isFinite || step <= 0 || !lo.isFinite || !hi.isFinite) return;
  final first = (lo / step).ceilToDouble();
  final last = (hi / step).floorToDouble();
  if (!first.isFinite || !last.isFinite || last < first) return;
  final span = last - first;
  if (span > 4096) return;
  final count = span.toInt();
  for (var i = 0; i <= count; i++) {
    yield (first + i) * step;
  }
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
  // A NAME on the left — `y`, `f(x)`, `h` — is what the curve is called, and
  // what it is called changes nothing about what is drawn.
  //
  // Only a name, though. `2y` is not a name, it is y doubled, and drawing
  // the right-hand side unchanged gave a line with twice the gradient and
  // twice the intercept, confidently, with nothing on screen to say so.
  final isName = RegExp(r'^[A-Za-z][A-Za-z0-9]*$').hasMatch(left) ||
      RegExp(r'^[A-Za-z][A-Za-z0-9]*\s*\(\s*x\s*\)$').hasMatch(left);
  if (!isName) return _solvedForLeft(left, right);
  final f = compileFunction(right);
  return f.isOk ? GraphSource.curve(f) : GraphSource.failed(f.error);
}

/// **`2y = 6x + 4`, and the rest of rearranging a linear equation.**
///
/// Rearranging is the year-10 topic this whole feature is for, so an equation
/// that has not been rearranged yet is SOLVED rather than refused — but only
/// when the left really is linear in one name, and that is measured here
/// rather than assumed from how it looks: the gradient and the intercept come
/// from two points, and two more have to agree with them.
///
/// Everything else is refused in words. `y <= 3x` and `y != 3` land here too
/// (their left reads `y<` and `y!`), and they used to be drawn as though the
/// comparison had never been written at all.
GraphSource _solvedForLeft(String left, String right) {
  if (left.contains('x')) {
    return const GraphSource.failed(
        'x is on both sides — that is an equation to solve, not a curve');
  }
  const cannot =
      GraphSource.failed('rearrange it to start with y = before graphing it');
  // One name, one letter, and not a constant the calculator already knows.
  final letters =
      RegExp(r'[A-Za-z]+').allMatches(left).map((m) => m[0]!).toSet();
  if (letters.length != 1 || letters.first.length != 1) return cannot;
  final name = letters.first;
  if (name == 'e') return cannot;
  final lhs = compileFunction(left, variable: name);
  if (!lhs.isOk || lhs.at == null) return GraphSource.failed(lhs.error);
  final rhs = compileFunction(right);
  if (!rhs.isOk || rhs.at == null) return GraphSource.failed(rhs.error);
  final l = lhs.at!;
  final b = l(0);
  final a = l(1) - b;
  final scale = a.abs() + b.abs() + 1;
  if (a == 0 ||
      !a.isFinite ||
      !b.isFinite ||
      (l(2) - (2 * a + b)).abs() > 1e-9 * scale ||
      (l(-1) - (b - a)).abs() > 1e-9 * scale) {
    return cannot;
  }
  final r = rhs.at!;
  return GraphSource.curve(
      CompiledMath.ok((x) => (r(x) - b) / a, variable: 'x'));
}

