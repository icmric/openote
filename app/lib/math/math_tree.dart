/// The editing tree behind the visual maths editor (plan: v0.18 §8.1).
///
/// **Why a tree and not a string.** The editor this replaces kept the equation
/// as a LaTeX string and re-ran a one-shot rewrite on every keystroke. That is
/// exactly why nothing could build up in place: a string has no stable notion
/// of "inside the second box", so a caret cannot live in one and every
/// structural edit becomes offset archaeology.
///
/// **What we did NOT build.** The typesetting. Every frame the tree serialises
/// back to ordinary TeX — caret and empty slots included, as `\rule` and
/// `\square` — and `flutter_math_fork` draws it. The box model is never
/// forked. The 65 primitives this file emits were each probed against the real
/// renderer before being used here (2026-08-19); `\rlap` was the only casualty,
/// which is why the caret has a real width of 0.07em instead of zero.
///
/// Storage never sees any of this: [rowToTex] with a plain [MathTexCtx] emits
/// the same canonical LaTeX the block has always stored.
library;

/// How an atom behaves when the editor looks left for an operand, and what
/// spacing TeX will give it. `letter`/`digit` are operands; `op`/`rel` are not.
enum MClass { digit, letter, op, rel, open, close, func, other }

/// A horizontal sequence — and the ONLY place a caret can sit. Every slot of
/// every structure is one of these, which is what makes caret movement one
/// rule instead of one rule per construct.
class MRow {
  MRow([List<MNode>? initial]) {
    if (initial != null) addAll(initial);
  }

  final List<MNode> children = [];

  /// The structure this row is a slot of — null only for an equation's root.
  MNode? owner;

  /// Which slot ('num', 'den', 'sup', …). Used for up/down movement and for
  /// naming the box in tests; never emitted.
  String name = '';

  bool get isEmpty => children.isEmpty;
  int get length => children.length;

  void add(MNode n) {
    n.parent = this;
    children.add(n);
  }

  void addAll(Iterable<MNode> ns) {
    for (final n in ns) {
      add(n);
    }
  }

  void insert(int i, MNode n) {
    n.parent = this;
    children.insert(i, n);
  }

  void insertAll(int i, List<MNode> ns) {
    for (final n in ns) {
      n.parent = this;
    }
    children.insertAll(i, ns);
  }

  MNode removeAt(int i) {
    final n = children.removeAt(i);
    n.parent = null;
    return n;
  }

  /// Detach every child, returning them in order — the caller re-parents them.
  List<MNode> drain() {
    final out = List<MNode>.of(children);
    for (final n in out) {
      n.parent = null;
    }
    children.clear();
    return out;
  }
}

/// One element of a row: an atom, or a structure with slots of its own.
sealed class MNode {
  /// The row this node sits in. Maintained by [MRow]; never set by hand.
  MRow? parent;

  /// This node's slots in LEFT-TO-RIGHT walking order. Pressing → at the end
  /// of slot *i* enters slot *i+1*, and off the end of the last slot leaves
  /// the structure — which is the whole of "step into structures at their
  /// edge, not over them" (v0.18 §6).
  List<MRow> get slots;

  String texOf(MathTexCtx c);

  /// The linear characters this structure unbuilds to on Backspace, or null
  /// for "unwrap" — hand the slots' contents back to the parent row in order.
  ///
  /// Only fraction and script have a linear form that provably rebuilds to
  /// the same structure, so only those two return one. Everything else
  /// unwraps, which preserves every character the student typed even though
  /// it does not round-trip through the build-up rules. Both behaviours are
  /// covered in `math_editor_test.dart`; the promise that matters — Backspace
  /// never destroys content — holds for all of them.
  List<MNode>? unbuild() => null;
}

// ─────────────────────────────────────────────────────────────────────────
// Atoms
// ─────────────────────────────────────────────────────────────────────────

/// A single symbol: a typed character, or a named symbol from the inventory.
class MSym extends MNode {
  MSym(this.tex, {this.cls = MClass.other, this.typed});

  /// What this emits. Either one character (`x`, `+`) or a command (`\alpha`).
  final String tex;
  final MClass cls;

  /// The characters the student actually typed, when autocorrect replaced
  /// them (`alpha` → `\alpha`). Kept so Backspace can give them back rather
  /// than deleting a symbol the student never chose to insert as one unit.
  final String? typed;

  bool get isOperand => cls == MClass.digit || cls == MClass.letter;

  @override
  List<MRow> get slots => const [];

  @override
  String texOf(MathTexCtx c) => _cmd(tex);
}

/// Upright words inside maths: `\text{if }`. Imported OneNote equations are
/// full of these, and students need them for "if x > 0".
class MText extends MNode {
  MText(this.text);
  String text;

  @override
  List<MRow> get slots => const [];

  @override
  String texOf(MathTexCtx c) => '\\text{${_escapeText(text)}}';
}

// ─────────────────────────────────────────────────────────────────────────
// Structures
// ─────────────────────────────────────────────────────────────────────────

class MFrac extends MNode {
  MFrac({MRow? num, MRow? den}) {
    this.num = _own(num ?? MRow(), 'num');
    this.den = _own(den ?? MRow(), 'den');
  }

  late final MRow num;
  late final MRow den;

  MRow _own(MRow r, String n) {
    r.owner = this;
    r.name = n;
    return r;
  }

  @override
  List<MRow> get slots => [num, den];

  @override
  String texOf(MathTexCtx c) =>
      '\\frac{${rowToTex(num, c)}}{${rowToTex(den, c)}}';

  /// `\frac{1}{2}` → `1/2`, bracketing a slot that holds more than one atom
  /// so `\frac{n+1}{2}` comes back as `(n+1)/2` and rebuilds to itself.
  @override
  List<MNode> unbuild() => [
        ..._grouped(num),
        MSym('/', cls: MClass.op),
        ..._grouped(den),
      ];
}

/// Powers, indices, and n-ary limits — one node, because TeX already draws
/// `\sum_{a}^{b}` with the limits above and below in display style while
/// drawing `x^{2}` beside. Two behaviours, no second node type.
class MScript extends MNode {
  MScript({MRow? base, MRow? sub, MRow? sup}) {
    this.base = _own(base ?? MRow(), 'base');
    if (sub != null) this.sub = _own(sub, 'sub');
    if (sup != null) this.sup = _own(sup, 'sup');
  }

  late final MRow base;
  MRow? sub;
  MRow? sup;

  MRow _own(MRow r, String n) {
    r.owner = this;
    r.name = n;
    return r;
  }

  MRow ensureSub() => sub ??= _own(MRow(), 'sub');
  MRow ensureSup() => sup ??= _own(MRow(), 'sup');

  @override
  List<MRow> get slots => [base, if (sub != null) sub!, if (sup != null) sup!];

  @override
  String texOf(MathTexCtx c) {
    final b = StringBuffer('{${rowToTex(base, c)}}');
    if (sub != null) b.write('_{${rowToTex(sub!, c)}}');
    if (sup != null) b.write('^{${rowToTex(sup!, c)}}');
    return b.toString();
  }

  @override
  List<MNode> unbuild() => [
        ...base.drain(),
        if (sub != null) ...[
          MSym('_', cls: MClass.op),
          ..._grouped(sub!),
        ],
        if (sup != null) ...[
          MSym('^', cls: MClass.op),
          ..._grouped(sup!),
        ],
      ];
}

class MSqrt extends MNode {
  MSqrt({MRow? radicand, MRow? degree}) {
    this.radicand = _own(radicand ?? MRow(), 'radicand');
    if (degree != null) this.degree = _own(degree, 'degree');
  }

  late final MRow radicand;
  MRow? degree;

  MRow _own(MRow r, String n) {
    r.owner = this;
    r.name = n;
    return r;
  }

  // Degree first: it is drawn up-left of the radical, so a left-to-right walk
  // reaches it before the thing under the sign.
  @override
  List<MRow> get slots => [if (degree != null) degree!, radicand];

  @override
  String texOf(MathTexCtx c) {
    final deg = degree == null ? '' : '[${rowToTex(degree!, c)}]';
    return '\\sqrt$deg{${rowToTex(radicand, c)}}';
  }
}

/// Brackets that grow with what is inside them. `right` may be `.` for a
/// one-sided delimiter — which is exactly what a piecewise brace is.
class MDelim extends MNode {
  MDelim({required this.left, required this.right, MRow? body}) {
    this.body = _own(body ?? MRow(), 'body');
  }

  final String left;
  final String right;
  late final MRow body;

  MRow _own(MRow r, String n) {
    r.owner = this;
    r.name = n;
    return r;
  }

  @override
  List<MRow> get slots => [body];

  @override
  String texOf(MathTexCtx c) =>
      '\\left$left ${rowToTex(body, c)}\\right$right ';
}

class MAccent extends MNode {
  MAccent({required this.cmd, MRow? base}) {
    this.base = _own(base ?? MRow(), 'base');
  }

  /// `\hat`, `\bar`, `\vec`, `\dot`, `\tilde`, `\overline`.
  final String cmd;
  late final MRow base;

  MRow _own(MRow r, String n) {
    r.owner = this;
    r.name = n;
    return r;
  }

  @override
  List<MRow> get slots => [base];

  @override
  String texOf(MathTexCtx c) => '$cmd{${rowToTex(base, c)}}';
}

/// `\binom{n}{r}` — two boxes in tall brackets with no bar. The palette calls
/// it "choose", because that is the word a student says out loud.
class MBinom extends MNode {
  MBinom({MRow? top, MRow? bottom}) {
    this.top = _own(top ?? MRow(), 'top');
    this.bottom = _own(bottom ?? MRow(), 'bottom');
  }

  late final MRow top;
  late final MRow bottom;

  MRow _own(MRow r, String n) {
    r.owner = this;
    r.name = n;
    return r;
  }

  @override
  List<MRow> get slots => [top, bottom];

  @override
  String texOf(MathTexCtx c) =>
      '\\binom{${rowToTex(top, c)}}{${rowToTex(bottom, c)}}';
}

/// Grids: matrices, determinants, and piecewise `cases` — all the same shape
/// with a different environment name and a different pair of edges.
class MMatrix extends MNode {
  MMatrix({required this.env, required List<List<MRow>> cells}) {
    rows = [
      for (var r = 0; r < cells.length; r++)
        [
          for (var k = 0; k < cells[r].length; k++)
            _own(cells[r][k], 'cell$r,$k')
        ]
    ];
  }

  MMatrix.sized({required this.env, int rowCount = 2, int colCount = 2}) {
    rows = [
      for (var r = 0; r < rowCount; r++)
        [for (var k = 0; k < colCount; k++) _own(MRow(), 'cell$r,$k')]
    ];
  }

  /// `pmatrix`, `bmatrix`, `vmatrix`, `cases`.
  final String env;
  late final List<List<MRow>> rows;

  int get rowCount => rows.length;
  int get colCount => rows.isEmpty ? 0 : rows.first.length;

  MRow _own(MRow r, String n) {
    r.owner = this;
    r.name = n;
    return r;
  }

  /// (row, column) of a slot, or null if it isn't ours.
  (int, int)? locate(MRow r) {
    for (var i = 0; i < rows.length; i++) {
      for (var k = 0; k < rows[i].length; k++) {
        if (identical(rows[i][k], r)) return (i, k);
      }
    }
    return null;
  }

  void addRow() {
    final i = rows.length;
    rows.add([for (var k = 0; k < colCount; k++) _own(MRow(), 'cell$i,$k')]);
  }

  @override
  List<MRow> get slots => [for (final r in rows) ...r];

  @override
  String texOf(MathTexCtx c) {
    final body = rows
        .map((r) => r.map((cell) => rowToTex(cell, c)).join(' & '))
        .join(' \\\\ ');
    return '\\begin{$env}$body\\end{$env}';
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Serialisation
// ─────────────────────────────────────────────────────────────────────────

/// How to write the tree out. With [decorate] false this produces the
/// canonical LaTeX that goes to storage, to Markdown export, and to the PDF —
/// identical to what the old string editor stored. With it true, the same walk
/// also draws the caret and the empty boxes, which is why the thing on screen
/// and the thing on disk can never disagree about structure.
class MathTexCtx {
  const MathTexCtx({
    this.caretRow,
    this.caretIndex = -1,
    this.decorate = false,
    this.accent = '#2563EB',
    this.tint = '#DBEAFE',
    this.dim = '#9CA3AF',
  });

  final MRow? caretRow;
  final int caretIndex;
  final bool decorate;

  /// Hex, with the `#`. `flutter_math_fork` takes `\textcolor{#RRGGBB}{…}`
  /// (probed 2026-08-19), so the editor's chrome is theme-coloured without a
  /// second rendering path.
  final String accent;
  final String tint;
  final String dim;

  String get caretTex => '\\textcolor{$accent}{\\rule{0.07em}{0.9em}}';

  /// An empty box nobody is standing in.
  String get idleSlotTex => '\\textcolor{$dim}{\\square}';

  /// The box the caret is in. The tint IS the caret here: a hairline inside an
  /// empty box reads as a stray mark, while a highlighted box reads as "type
  /// here", which is what OneNote does too.
  String get activeSlotTex => '\\colorbox{$tint}{\$\\textcolor{$accent}{\\square}\$}';
}

/// The plain context used for storage and for read-only rendering.
const MathTexCtx kStoreCtx = MathTexCtx();

String rowToTex(MRow r, MathTexCtx c) {
  final caretHere = c.decorate && identical(r, c.caretRow);

  if (r.children.isEmpty) {
    if (!c.decorate) return '';
    // The root of an equation isn't a "box to fill" — an empty one should show
    // a caret, not a placeholder square the student has to delete.
    if (r.owner == null) return caretHere ? c.caretTex : '';
    return caretHere ? c.activeSlotTex : c.idleSlotTex;
  }

  final b = StringBuffer();
  for (var i = 0; i < r.children.length; i++) {
    if (caretHere && i == c.caretIndex) b.write(c.caretTex);
    b.write(r.children[i].texOf(c));
  }
  if (caretHere && c.caretIndex >= r.children.length) b.write(c.caretTex);
  return b.toString();
}

/// Every row in the tree, in document order — the order Tab walks.
List<MRow> allRows(MRow root) {
  final out = <MRow>[root];
  void walk(MRow r) {
    for (final n in r.children) {
      for (final s in n.slots) {
        out.add(s);
        walk(s);
      }
    }
  }

  walk(root);
  return out;
}

/// A command needs a space after it or the next letter joins its name
/// (`\alpha x`, never `\alphax`). Single characters must NOT get one: `{+}`
/// and `+ ` differ to TeX's spacing rules, and `a + b` reads wrong without it.
String _cmd(String tex) {
  if (tex.length > 1 && tex.startsWith('\\')) {
    final last = tex.codeUnitAt(tex.length - 1);
    final isLetter = (last >= 65 && last <= 90) || (last >= 97 && last <= 122);
    if (isLetter) return '$tex ';
  }
  return tex;
}

/// Bracket a slot's contents when unbuilding, so the linear form rebuilds to
/// the same structure. One atom needs no brackets; `n+1` does.
List<MNode> _grouped(MRow r) {
  final kids = r.drain();
  if (kids.length <= 1) return kids;
  return [
    MSym('(', cls: MClass.open),
    ...kids,
    MSym(')', cls: MClass.close),
  ];
}

String _escapeText(String s) => s.replaceAll('\\', ' ').replaceAll('{', '(').replaceAll('}', ')');
