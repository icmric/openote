/// The tree, written the way the calculator reads (review round 3).
///
/// The Maths tab's live answer was DEAD for anything built visually: the
/// editor fed its canonical LaTeX into [evaluateLinear], whose parser has no
/// `\` and no `{` atom — so `\frac{1}{2}` was refused and the readout never
/// appeared for a fraction, a power or a root, which is to say for the normal
/// case. This walk writes the tree in the linear grammar the evaluator was
/// built for: `\frac{1}{2}` becomes `((1)/(2))`, `\sqrt{16}` becomes
/// `sqrt(16)`, `x^{2}` becomes `(x)^(2)`.
///
/// Honesty rule, same as everywhere in the editor: a node with no numeric
/// meaning (a matrix, a words box, an accent) emits a token the evaluator
/// REJECTS, so the answer readout simply does not appear — it never guesses.
library;

import 'math_tree.dart';

/// A token no expression grammar accepts, emitted for the unevaluable.
const String _veto = '§'; // silcrow: no grammar accepts it

/// The row as linear maths, for [evaluateLinear]. May contain [_veto]; the
/// evaluator then reports not-ok and the caller shows nothing, which is the
/// point.
String rowToLinear(MRow r) {
  // One piece per child, so a script can reach BACK for the base it really
  // has. Reading each node in isolation is what made `(2+3)^2` come out as
  // `(2+3())^(2)` and `16^2` (pasted, where LaTeX puts only the `6` under the
  // script) come out as `1(6)^(2)` = 36 — the brackets around a lone base
  // turning what should have been one number into an implicit product.
  final parts = <String>[];
  var i = 0;
  while (i < r.children.length) {
    final n = r.children[i];
    if (n is MScript && !n.fixedBase && n.sub == null && n.sup != null) {
      final consumed = _scriptWithContext(r, i, parts);
      if (consumed > 0) {
        i += consumed;
        continue;
      }
    }
    parts.add(_nodeToLinear(n));
    i++;
  }
  return parts.join();
}

/// A script whose base is only half the story. Returns how many children were
/// taken (0 when the ordinary path should handle it); [parts] may be shortened
/// where the real base was already written out.
int _scriptWithContext(MRow r, int at, List<String> parts) {
  final s = r.children[at] as MScript;
  final above = rowToLinear(s.sup!).trim();
  // A degree sign is not a power. It rides on the number in front of it, and
  // the digit-run rule below would otherwise claim the base first and emit
  // `(30)^(°)` — which nothing can read.
  if (above == '°') {
    var k = at - 1;
    while (k >= 0) {
      final c = r.children[k];
      if (c is MSym && (_isDigit(c.tex) || c.tex == '.')) {
        k--;
        continue;
      }
      break;
    }
    final run = parts.sublist(k + 1).join() + rowToLinear(s.base);
    parts.removeRange(k + 1, parts.length);
    parts.add('$run°');
    return 1;
  }
  final power = '^(${rowToLinear(s.sup!)})';
  if (s.base.length != 1) return 0;
  final b = s.base.children.first;
  if (b is! MSym) return 0;

  // **`sin^2(x)` is `(sin x)^2`.** The base is the function NAME, and its
  // argument is the next thing in the row — the schoolbook reading, and the
  // one this palette's own buttons produce. `sin^2 x + cos^2 x = 1` is the
  // most-written identity in senior trigonometry and it could not be checked:
  // the projection emitted `(sin )^(2)` and orphaned the bracket after it.
  final fname = _functionNames[b.tex];
  if (fname != null && rowToLinear(s.sup!).trim() != '-1') {
    final arg = _argumentAfter(r, at + 1);
    if (arg != null) {
      parts.add('($fname(${arg.text}))$power');
      final span = arg.span;
      return 1 + span;
    }
    return 0;
  }

  // **A closing bracket is not a base.** Plain `(` and `)` are ordinary
  // atoms, so a script written after one attached to the bracket itself:
  // `(2+3)^2` projected to `(2+3())^(2)` and errored. Walk back to the
  // bracket that opened it and take the whole group.
  if (b.tex == ')') {
    var depth = 1;
    var k = at - 1;
    while (k >= 0) {
      final c = r.children[k];
      if (c is MSym && c.tex == ')') depth++;
      if (c is MSym && c.tex == '(') {
        depth--;
        if (depth == 0) break;
      }
      k--;
    }
    if (k < 0) return 0; // unmatched: leave it to the ordinary path
    final inner = parts.sublist(k + 1).join();
    parts.removeRange(k, parts.length);
    parts.add('($inner)$power');
    return 1;
  }

  // **A digit is rarely the whole number.** LaTeX puts one token under a
  // script, so `16^2` from a textbook or a chat message has only the `6` as
  // its base. Reading it that way is right for a RENDERER — it draws 16²
  // either way — and wrong for a calculator, which answered 36. The digit run
  // in front of it belongs to the base.
  if (_isDigit(b.tex)) {
    var k = at - 1;
    while (k >= 0) {
      final c = r.children[k];
      if (c is MSym && (_isDigit(c.tex) || c.tex == '.')) {
        k--;
        continue;
      }
      break;
    }
    if (k == at - 1) return 0; // nothing in front: the ordinary path is right
    final run = parts.sublist(k + 1).join() + b.tex;
    parts.removeRange(k + 1, parts.length);
    parts.add('($run)$power');
    return 1;
  }
  return 0;
}

/// The bracketed argument starting at [from], however it is written.
///
/// A `\left(…\right)` pair is one node; a plain `(`…`)` typed on the
/// keyboard or pasted from a textbook is a RUN of ordinary atoms. Both are
/// arguments, and only reading the first was why `sin^2(30)` — with the
/// brackets every textbook uses — could not be worked out.
({String text, int span})? _argumentAfter(MRow r, int from) {
  if (from >= r.children.length) return null;
  final first = r.children[from];
  if (first is MDelim && first.left == '(') {
    return (text: rowToLinear(first.body), span: 1);
  }
  if (first is! MSym || first.tex != '(') return null;
  var depth = 1;
  var k = from + 1;
  final inner = MRow();
  while (k < r.children.length) {
    final c = r.children[k];
    if (c is MSym && c.tex == '(') depth++;
    if (c is MSym && c.tex == ')') {
      depth--;
      if (depth == 0) break;
    }
    inner.children.add(c);
    k++;
  }
  if (depth != 0) {
    inner.children.clear();
    return null; // unclosed: not an argument
  }
  final text = rowToLinear(inner);
  inner.children.clear();
  return (text: text, span: k - from + 1);
}

bool _isDigit(String t) =>
    t.length == 1 && t.codeUnitAt(0) >= 0x30 && t.codeUnitAt(0) <= 0x39;

/// Every function symbol the evaluator knows, by its TeX name.
const Map<String, String> _functionNames = {
  r'\sin': 'sin', r'\cos': 'cos', r'\tan': 'tan',
  r'\sinh': 'sinh', r'\cosh': 'cosh', r'\tanh': 'tanh',
  r'\ln': 'ln', r'\log': 'log',
};

String _nodeToLinear(MNode n) => switch (n) {
      MSym() => _symToLinear(n),
      // An answer is a number like any other: `2+3=5` then `+1=` works out
      // the 5 as readily as if it had been typed.
      MAnswer() => rowToLinear(n.content),
      MFrac() => '((${rowToLinear(n.num)})/(${rowToLinear(n.den)}))',
      MScript() => _scriptToLinear(n),
      MSqrt() => n.degree == null
          ? 'sqrt(${rowToLinear(n.radicand)})'
          // An nth root is a fractional power; the evaluator has no rootn().
          : '((${rowToLinear(n.radicand)})^(1/(${rowToLinear(n.degree!)})))',
      MDelim() => _delimToLinear(n),
      // `gcd(a,b)` reads across to the calculator exactly as it is written.
      MCall() => '${n.name}(${n.args.map(rowToLinear).join(',')})',
      // A choose, a matrix, an accent, a words box: no single number to be.
      MBinom() => _veto,
      MMatrix() => _veto,
      MAccent() => _veto,
      MText() => _veto,
    };

/// The inverse of each trig function, by the name the evaluator knows.
const Map<String, String> _inverseOf = {
  r'\sin': 'asin ', r'\cos': 'acos ', r'\tan': 'atan ',
};

String _scriptToLinear(MScript s) {
  // **A log with a base under it**: `log₂ 8`, which is how a textbook and a
  // Casio both write it, and how this app's own "log to a base" button
  // builds it. The evaluator spells the same thing `log2(8)`, so the base
  // simply joins the name. Whole numbers only — `log_x` is algebra, not
  // arithmetic, and refusing is the honest answer.
  final under = s.sub;
  if (!s.fixedBase && under != null && s.sup == null && s.base.length == 1) {
    final base = s.base.children.first;
    final digits = rowToLinear(under).trim();
    if (base is MSym &&
        (base.tex == r'\log' || base.tex == r'\ln') &&
        RegExp(r'^[0-9]+$').hasMatch(digits)) {
      return 'log$digits ';
    }
  }
  // A subscript is a NAME (x₁), not arithmetic — refuse rather than misread
  // x_1 as x times 1. An n-ary's limits (∑, ∫) are far beyond a calculator.
  if (s.fixedBase || s.sub != null) return _veto;

  final power = s.sup;
  if (power != null && s.base.length == 1) {
    final base = s.base.children.first;
    final above = rowToLinear(power).trim();
    // **`sin⁻¹` is the INVERSE, not one over sin.** The owner chose `⁻¹` over
    // `arcsin` for the palette, so this is the app's own inverse
    // trigonometry — and it projected to `(sin )^(-1)`, which the evaluator
    // read as a reciprocal and then choked on. Every inverse trig button was
    // dead to the calculator.
    if (base is MSym && above == '-1') {
      final inv = _inverseOf[base.tex];
      if (inv != null) return inv;
    }
    // `30°` is an angle, not thirty to the power of a degree sign. The tree
    // hangs the sign off the LAST digit (`3` then `0` with the script), so
    // emitting the base and the sign bare lets the digits rejoin.
    if (above == '°') return rowToLinear(s.base) + '°';
  }
  final sup = s.sup == null ? '' : '^(${rowToLinear(s.sup!)})';
  return '(${rowToLinear(s.base)})$sup';
}

String _delimToLinear(MDelim d) {
  final body = rowToLinear(d.body);
  // |x| is the one bracket pair with its own meaning.
  if (d.left == '|' && d.right == '|') return '|$body|';
  if (d.left == '(' && d.right == ')') return '($body)';
  if (d.left == '[' && d.right == ']') return '($body)';
  // Floor, ceil, braces-as-sets: the evaluator has no reading for them.
  return _veto;
}

/// One symbol, in the calculator's vocabulary. Anything unknown that LOOKS
/// like a command is vetoed; a bare character passes through and the
/// evaluator's own grammar decides.
String _symToLinear(MSym s) {
  final t = s.tex;
  // The degree sign is the one symbol in the inventory that does not begin
  // with a backslash: the palette writes the ring as the single atom
  // `{}^{\circ}`. Without this line the button inserted something the
  // evaluator had never heard of — 30, the degrees button, `=`, and no
  // answer at all.
  if (t == r'{}^{\circ}') return '°';
  if (!t.startsWith('\\')) return t;
  const map = <String, String>{
    // Operators the evaluator spells differently.
    r'\times': '*', r'\cdot': '*', r'\div': '/', r'\pm': _veto,
    // Constants and named functions it knows by word.
    //
    // EVERY word carries a trailing space, constants included. Without it
    // `\pi` followed by `e` concatenated into the single unknown name `pie`
    // (measured), and `2\pi r` into `pir` — the evaluator takes the longest
    // letter run as ONE name, so two adjacent words fuse. With the space the
    // evaluator's own implicit-product rule takes over and reads them as the
    // product they are.
    // Function words carry a trailing space - the evaluator's own
    // 'sin x' form. Without it a bare argument fused into one unknown
    // name: cos followed by 0 read as 'cos0'.
    r'\pi': 'pi ', r'\infty': 'inf ',
    r'\sin': 'sin ', r'\cos': 'cos ', r'\tan': 'tan ',
    r'\arcsin': 'asin ', r'\arccos': 'acos ', r'\arctan': 'atan ',
    r'\sinh': 'sinh ', r'\cosh': 'cosh ', r'\tanh': 'tanh ',
    r'\ln': 'ln ', r'\log': 'log ', r'\exp': 'exp ',
    // A remainder, written the way it is written: `17 mod 5`. The spaces
    // matter — without them `17mod5` is a name the evaluator has never heard
    // of.
    r'\bmod': ' mod ',
    // A degree sign. The evaluator turns it into radians on the spot, so
    // an angle written `30°` means degrees however the surrounding rule
    // reads.
    r'\circ': '°', r'\degree': '°',
    // A space atom is just spacing.
    r'\ ': ' ',
    // Punctuation TeX spells with commands.
    // A per cent sign, which the evaluator reads as "divide by a hundred".
    r'\%': '%',
    r'\#': '#',
  };
  return map[t] ?? _veto;
}
