/// Where, horizontally, each top-level atom of an equation begins and ends
/// (plan: v0.20 §E.3).
///
/// `flutter_math_fork` exposes no per-node geometry, which is why clicking an
/// equation used to jump the caret to the end no matter where the click
/// landed. But geometry per PREFIX is measurable without touching the
/// renderer: lay out `rowToTex(children[0..i])` for every `i` and the width
/// of each prefix IS the x of boundary `i`. The field builds those prefixes
/// offstage on pointer-down — the equation cannot change while the button is
/// held, so the `n + 1` layouts happen once per gesture, never per keystroke
/// (the v0.19 rule), and the table is discarded on pointer-up.
///
/// Accuracy limits, stated rather than discovered:
///  * TeX spaces a trailing binary `+` differently from the same `+` between
///    two operands, so a prefix width can be a few px off. The result snaps
///    to a boundary, so a few px only ever picks the neighbouring one.
///  * While a highlight is DRAWN, its `\fcolorbox` shifts everything after it
///    right by 0.68 em; boundaries measured without the box are then that far
///    left of the glyphs. A drag can therefore snap one atom short near the
///    highlight's right edge — accepted for now, stated here so the day it
///    matters nobody has to rediscover why.
library;

import 'math_tree.dart';

class MathHitTable {
  MathHitTable(this.row, this.bounds)
      : assert(bounds.length == row.length + 1);

  final MRow row;

  /// `bounds[i]` = the laid-out width of the first `i` children — that is,
  /// the x of the gap BEFORE child `i`. `bounds[0]` is 0 by construction and
  /// `bounds[n]` is the whole row's width.
  final List<double> bounds;

  /// The TeX of every prefix of [row], in order — what the field lays out
  /// offstage to build [bounds]. Children are borrowed into the probe row by
  /// LIST manipulation, never re-parented: the probe must not touch the tree
  /// it is measuring (the same trick `selectionLatex` uses).
  static List<String> prefixTexes(MRow row) {
    final probe = MRow();
    final out = <String>[''];
    for (var i = 0; i < row.length; i++) {
      probe.children.add(row.children[i]);
      out.add(rowToTex(probe, kStoreCtx));
    }
    probe.children.clear();
    return out;
  }

  /// The nearest boundary to [dx] — where a click puts the caret.
  int boundaryAt(double dx) {
    var best = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < bounds.length; i++) {
      final d = (bounds[i] - dx).abs();
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }

  /// The child under [dx], or -1 when the pointer is PAST the row's own
  /// extent. Clicking to the right of an equation is how a student puts the
  /// caret at the end, so a clamped answer would make the last thing in the
  /// row un-clickable-past — you would toggle the answer every time you
  /// aimed for the end.
  int childStrictlyAt(double dx) {
    if (row.isEmpty || dx < bounds.first || dx > bounds.last) return -1;
    return childAt(dx);
  }

  /// The child under [dx] — what a double-click selects. Clamped to the row,
  /// so a double-click in the margin takes the nearest end child.
  int childAt(double dx) {
    for (var i = 0; i < row.length; i++) {
      if (dx < bounds[i + 1]) return i;
    }
    return row.length - 1;
  }
}
