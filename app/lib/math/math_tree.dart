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

/// The operators that carry their limits ON the sign rather than beside it.
///
/// A script whose base is exactly one of these is an N-ARY: the base is the
/// operator itself, not something the student wrote, so it is not a box they
/// should ever be able to walk into. See [MScript.fixedBase].
const Set<String> kBigOperators = {
  r'\sum', r'\prod', r'\coprod', r'\int', r'\iint', r'\iiint', r'\oint',
  r'\bigcup', r'\bigcap', r'\bigvee', r'\bigwedge', r'\bigoplus',
  r'\lim', r'\limsup', r'\liminf', r'\max', r'\min', r'\sup', r'\inf',
};

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

  /// Every row this node OWNS, navigable or not.
  ///
  /// [slots] is where the caret may go; this is where the content lives. They
  /// differ for an n-ary, whose base holds the operator sign itself — the
  /// caret must never enter it, but unwrapping the node must not throw the
  /// sign away either.
  List<MRow> get contentSlots => slots;

  /// True when every slot the student can reach is empty, so removing the node
  /// loses nothing they wrote. This is what lets Backspace delete a structure
  /// already emptied while refusing to delete one that still holds work.
  bool get isBlank => slots.every((s) => s.isEmpty);
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
  String texOf(MathTexCtx c) => _emit(tex);

  /// Does this atom START a script? The degree sign and the prime do, and two
  /// script starts in a row is `x^{2}^\circ` — a double superscript, which TeX
  /// refuses outright. [rowToTex] puts an empty group between them.
  bool get startsScript => tex.startsWith('^') || tex.startsWith('_');
}

/// Upright words inside maths: `\text{if }`. Imported OneNote equations are
/// full of these, and students need them for "if x > 0".
class MText extends MNode {
  MText(this.text);
  String text;

  @override
  List<MRow> get slots => const [];

  @override
  String texOf(MathTexCtx c) {
    // An empty words box has to be VISIBLE. It drew exactly 0 px before, so
    // pressing the button was pixel-identical to not pressing it.
    if (text.isEmpty) {
      if (!c.decorate) return '';
      return identical(c.activeText, this) ? c.activeSlotTex : c.idleSlotTex;
    }
    return '\\text{${_escapeText(text)}}';
  }
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

  /// Is the base the operator ITSELF rather than something the student wrote?
  ///
  /// Computed, never stored, so the parser, the palette and the build-up rules
  /// cannot disagree about it. Everything that went wrong around a summation
  /// came from the base being an ordinary navigable box:
  ///
  ///  * Up from the lower limit landed IN it rather than on the upper limit.
  ///  * The caret sitting there made the script attach to the caret rule, so
  ///    the limits jumped off the sign and sat beside it — the owner's "they
  ///    sometimes move to the front".
  ///  * Typing there brace-wrapped the operator and stored the limits beside
  ///    the sign permanently.
  ///  * Two Backspaces from the front of the lower limit deleted the summation
  ///    sign with nothing to show it had gone.
  ///
  /// None of those is reachable once the caret cannot get in.
  bool get fixedBase {
    if (base.length != 1) return false;
    final only = base.children.first;
    return only is MSym && kBigOperators.contains(only.tex);
  }

  @override
  List<MRow> get slots => [
        if (!fixedBase) base,
        if (sub != null) sub!,
        if (sup != null) sup!,
      ];

  @override
  List<MRow> get contentSlots =>
      [base, if (sub != null) sub!, if (sup != null) sup!];

  @override
  String texOf(MathTexCtx c) {
    final inner = rowToTex(base, c);
    // **Do not brace a lone base.** `{\int}_{5}^{2}` and `\int_{5}^{2}` are not
    // the same equation: braces make the base an ORDINARY atom, and TeX only
    // puts limits above and below a BIG OPERATOR. Braced, the 5 and the 2 slide
    // out beside the sign like the indices of a variable — which is exactly
    // what the owner photographed. Hits every n-ary: ∫ ∑ ∏ ∬ ∮ and lim.
    //
    // A base of two or more atoms still needs its braces (`{a+b}^{2}`), and an
    // empty one needs `{}` or the script has nothing to attach to.
    final b = StringBuffer(base.length == 1 ? inner : '{$inner}');
    if (sub != null) b.write('_{${rowToTex(sub!, c)}}');
    if (sup != null) b.write('^{${rowToTex(sup!, c)}}');
    return b.toString();
  }
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
/// An answer the APP worked out, not something the student typed.
///
/// The owner asked for two things at once and they turn out to be the same
/// object: *"id like for the auto calculated results to have a subtle box
/// outlining them, this shows the area to click in … but also so people know
/// that was calculated in app rather than typed up"*, and *"id then like to
/// be able to click on the answer to switch it between dec and fraction"*.
/// A box that means "computed" is exactly the target for the click that
/// switches how it is written.
///
/// **It serialises as `oxed{…}`**, which is deliberate on three counts:
/// it is real LaTeX, so an answer pasted into Word or Overleaf is a boxed
/// number rather than a private marker; it draws identically in read mode,
/// in edit mode and in print, because there is only one string; and it
/// **round-trips** — the parser reads `oxed{…}` straight back into an
/// answer, so the box, and the toggle, survive save and reload with no
/// side-car metadata to drift out of step.
///
/// Nothing is cached. The value is recovered by projecting [content] and
/// evaluating it, which is the same walk the calculator uses — two copies of
/// one fact is exactly the drift this codebase keeps paying for.
class MAnswer extends MNode {
  MAnswer({MRow? content}) {
    this.content = _own(content ?? MRow(), 'answer');
  }

  late final MRow content;

  MRow _own(MRow r, String n) {
    r.owner = this;
    r.name = n;
    return r;
  }

  /// NO slots: an answer is one object to the caret, so arrow keys step over
  /// it and Backspace takes the whole thing. Editing it character by
  /// character would make "the app worked this out" a lie.
  @override
  List<MRow> get slots => const [];

  /// …but it IS content, so every sweep that collects what an equation
  /// contains still walks inside. (Getting this distinction wrong is what
  /// dropped `\sum` from the parser twice.)
  @override
  List<MRow> get contentSlots => [content];

  @override
  String texOf(MathTexCtx c) =>
      // TWO backslashes: `'\boxed'` in a plain Dart string is the ESCAPE
      // `\b`, a backspace character, so the equation serialised as
      // `2+3=<BS>oxed{5}` and reopened as `2+3=oxed5`. The same trap the
      // caret code carries a note about.
      '\\boxed{${rowToTex(content, c)}}';

  /// How many significant figures the student asked for, or null for "as many
  /// as the number needs".
  ///
  /// **Not serialised, and deliberately.** The digits themselves carry the
  /// answer's precision the way a calculator's do — `0.500` IS three figures —
  /// so a saved note needs no metadata riding alongside it. This field is the
  /// belt to that braces: within one editing session it remembers the choice
  /// exactly, so re-working `1/3` at 3 s.f. into `2/3` still gives `0.667`
  /// rather than silently reverting because `0.333` happened to look like an
  /// ordinary number.
  int? sigFigs;
}

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

  /// A new column AFTER [after], in every row — a matrix stays rectangular
  /// or its TeX does not compile.
  void addColumnAfter(int after) {
    for (var i = 0; i < rows.length; i++) {
      rows[i].insert(after + 1, _own(MRow(), 'cell$i,${after + 1}'));
    }
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
    this.activeText,
    this.selectionRow,
    this.selectionStart = -1,
    this.selectionEnd = -1,
    this.accent = '#2563EB',
    this.tint = '#DBEAFE',
    this.selectionTint = '#B9C0F5',
    this.dim = '#9CA3AF',
    this.display = true,
    this.showEmptySlots = false,
  });

  final MRow? caretRow;
  final int caretIndex;
  final bool decorate;

  /// The highlighted run: a contiguous slice of ONE row. Drawn with
  /// `\fcolorbox`, because `\colorbox` never paints its fill in
  /// flutter_math_fork 0.7.4 — the same discovery that made the active-slot
  /// box visible.
  final MRow? selectionRow;
  final int selectionStart;
  final int selectionEnd;

  /// The words box being filled, so an empty one can show as the active slot
  /// rather than as nothing at all.
  final MText? activeText;

  /// Hex, with the `#`. `flutter_math_fork` takes `\textcolor{#RRGGBB}{…}`
  /// (probed 2026-08-19), so the editor's chrome is theme-coloured without a
  /// second rendering path.
  final String accent;
  final String tint;

  /// The highlight's fill — its OWN colour, not [tint]. The slot tint is
  /// deliberately faint (it sits under a box you are typing into); measured
  /// against the block's white editing fill it is 1.34:1, and a one-atom
  /// selection in it read as "nothing happened" — which is exactly what the
  /// owner reported. A selection has to announce itself.
  final String selectionTint;

  final String dim;

  /// Display style (a block) vs text style (inline). Carried INTO the
  /// highlight box: `\fcolorbox` resets its contents to text style, so
  /// without this token a highlighted fraction physically SHRINKS the moment
  /// you select it — measured at 44.2px tall plain, 41.1px boxed.
  final bool display;

  /// Draw a SAVED empty slot as the small dim square instead of nothing.
  /// Read mode and print only: with the plain storage ctx an empty slot
  /// serialises to bare `{}`, which TeX draws as a hole — a half-filled
  /// fraction became a bar over nothing, with no marker that anything was
  /// unfinished. "What you see is what prints" (v0.18 5.3) needs the square
  /// everywhere the equation shows; STORAGE keeps the bare braces.
  final bool showEmptySlots;

  /// The caret. Sized in `ex`, not `em`: an `em` rule is measured against the
  /// font size where it sits, so nesting made the caret GROW — measured at
  /// 2.9× too tall inside a script of a script, when it should shrink with the
  /// text around it. `ex` tracks the x-height, which is what a caret matches.
  String get caretTex => '\\textcolor{$accent}{\\rule{0.06em}{1.5ex}}';

  /// An empty box nobody is standing in.
  String get idleSlotTex => '\\textcolor{$dim}{\\square}';

  /// The box the caret is in. The tint IS the caret here: a hairline inside an
  /// empty box reads as a stray mark, while a highlighted box reads as "type
  /// here", which is what OneNote does too.
  ///
  /// `\fcolorbox`, not `\colorbox`: flutter_math_fork 0.7.4 draws `\colorbox`'s
  /// contents and never paints its fill, so this box has been INVISIBLE since
  /// it shipped — the student saw the same grey placeholder whether the caret
  /// was in it or not. `\fcolorbox` paints; the same colour for border and
  /// fill keeps the shape it was meant to have.
  String get activeSlotTex =>
      '\\fcolorbox{$tint}{$tint}{\$\\textcolor{$accent}{\\square}\$}';

  /// Opens the highlight. The content between this and [selectionClose] is
  /// re-entered as maths, so anything at all can sit inside it — WITH the
  /// style it had outside, or a selected fraction changes size (see
  /// [display]).
  String get selectionOpen => display
      ? '\\fcolorbox{$selectionTint}{$selectionTint}{\$\\displaystyle '
      : '\\fcolorbox{$selectionTint}{$selectionTint}{\$\\textstyle ';
  String get selectionClose => '\$}';
}

/// The plain context used for storage and for read-only rendering.
const MathTexCtx kStoreCtx = MathTexCtx();

String rowToTex(MRow r, MathTexCtx c) {
  var caretHere = c.decorate && identical(r, c.caretRow);

  if (r.children.isEmpty) {
    if (!c.decorate) {
      return c.showEmptySlots && r.owner != null ? c.idleSlotTex : '';
    }
    // The root of an equation isn't a "box to fill" — an empty one should show
    // a caret, not a placeholder square the student has to delete.
    if (r.owner == null) return caretHere ? c.caretTex : '';
    return caretHere ? c.activeSlotTex : c.idleSlotTex;
  }

  final selHere = c.decorate &&
      identical(r, c.selectionRow) &&
      c.selectionStart >= 0 &&
      c.selectionEnd > c.selectionStart;

  // One or the other, never both: a text editor shows a highlight OR a
  // caret. Both at once — the caret is always at one END of the highlight —
  // read as a stray hairline glued to the box's edge.
  if (selHere) caretHere = false;

  final b = StringBuffer();
  var prevEndsScript = false;
  for (var i = 0; i < r.children.length; i++) {
    if (caretHere && i == c.caretIndex) b.write(c.caretTex);
    if (selHere && i == c.selectionStart) b.write(c.selectionOpen);
    final n = r.children[i];
    // **Two scripts cannot touch.** `x^{2}` followed by the degree sign or a
    // prime emits `x^{2}^\circ` — a double superscript, which TeX refuses, so
    // the whole equation falls back to a grey box of source. An empty group
    // between them is the standard fix and costs nothing on screen.
    if (prevEndsScript && n is MSym && n.startsScript) b.write('{}');
    b.write(n.texOf(c));
    if (selHere && i + 1 == c.selectionEnd) b.write(c.selectionClose);
    prevEndsScript = n is MScript || (n is MSym && n.startsScript);
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

/// The characters TeX reserves. Typed into an equation they used to go
/// straight through, and every one of them broke it:
///
/// * `{ } $ # &` made the equation undrawable — a grey box of source where the
///   student's maths had been.
/// * `%` was worse than an error: it is TeX's COMMENT character, so `20%` drew
///   as `20` and `30%+2` drew as `30`. The rest vanished with nothing to say
///   it had gone.
/// * A balanced pair of braces — `{1,2,3}`, which is how a student writes a
///   set — became invisible grouping, so the braces simply were not there.
///
/// `^` has no escape that works in both modes (`\^{}` falls back), so it goes
/// through `\char`, which was probed in maths mode and in text mode.
const Map<String, String> _mathEscapes = {
  '{': r'\{',
  '}': r'\}',
  r'$': r'\$',
  '#': r'\#',
  '&': r'\&',
  '%': r'\%',
  '_': r'\_',
  '^': r'\char94 ',
  '~': r'\sim ',
  '\\': r'\backslash ',
};

/// Text mode needs a different set: `\backslash` and `\sim` are maths-only and
/// fall back inside `\text{…}` (probed).
const Map<String, String> _textEscapes = {
  '{': r'\{',
  '}': r'\}',
  r'$': r'\$',
  '#': r'\#',
  '&': r'\&',
  '%': r'\%',
  '_': r'\_',
  '^': r'\char94 ',
  '~': r'\char126 ',
  '\\': r'\char92 ',
};

final RegExp _trailingCommand = RegExp(r'\\[a-zA-Z]+$');

/// One atom, made safe.
///
/// A command needs a space after it or the next letter joins its name
/// (`\alpha x`, never `\alphax`) — and that has to be tested on the END of the
/// string, not the start, because `^\circ` is a command too and `30^\circC`
/// was an undrawable equation. Single characters must NOT get one: `{+}` and
/// `+ ` differ to TeX's spacing rules, and `a + b` reads wrong without it.
String _emit(String tex) {
  if (tex.length == 1) return _mathEscapes[tex] ?? tex;
  if (_trailingCommand.hasMatch(tex)) return '$tex ';
  return tex;
}

/// Words inside maths. Every reserved character is ESCAPED rather than
/// swapped: the old version turned a typed `{` into `(` and a backslash into a
/// space, so a words box quietly said something the student had not written —
/// and left `% $ # & _ ^` alone, any one of which killed the render outright.
String _escapeText(String s) {
  final b = StringBuffer();
  for (final ch in s.split('')) {
    b.write(_textEscapes[ch] ?? ch);
  }
  return b.toString();
}
