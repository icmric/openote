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

String _scriptToLinear(MScript s) {
  // A subscript is a NAME (x₁), not arithmetic — refuse rather than misread
  // x_1 as x times 1. An n-ary's limits (∑, ∫) are far beyond a calculator.
  if (s.fixedBase || s.sub != null) return _veto;
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
    // Function words carry a trailing space - the evaluator's own
    // 'sin x' form. Without it a bare argument fused into one unknown
    // name: cos followed by 0 read as 'cos0'.
    r'\pi': 'pi', r'\infty': 'inf',
    r'\sin': 'sin ', r'\cos': 'cos ', r'\tan': 'tan ',
    r'\arcsin': 'asin ', r'\arccos': 'acos ', r'\arctan': 'atan ',
    r'\sinh': 'sinh ', r'\cosh': 'cosh ', r'\tanh': 'tanh ',
    r'\ln': 'ln ', r'\log': 'log ', r'\exp': 'exp ',
    // A space atom is just spacing.
    r'\ ': ' ',
    // Punctuation TeX spells with commands.
    r'\%': _veto, r'\#': '#',
  };
  return map[t] ?? _veto;
}
