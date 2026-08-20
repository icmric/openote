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
  final b = StringBuffer();
  for (final n in r.children) {
    b.write(_nodeToLinear(n));
  }
  return b.toString();
}

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
    // A degree sign. The evaluator turns it into radians on the spot, so
    // an angle written `30°` means degrees however the surrounding rule
    // reads.
    r'\circ': '°', r'\degree': '°',
    // A space atom is just spacing.
    r'\ ': ' ',
    // Punctuation TeX spells with commands.
    r'\%': _veto, r'\#': '#',
  };
  return map[t] ?? _veto;
}
