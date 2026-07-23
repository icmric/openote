/// Linear math input → LaTeX (Math Input Spec, docs/specs/12-math-input-spec.md).
/// This is the MVP subset of the §3 grammar: control-word autocorrect,
/// fractions, sub/superscripts with grouping, n-ary operators with limits,
/// roots (incl. degree), matrices (`■(a&b@c&d)` / `\matrix(...)`), cases, and
/// function sugar (\abs, \norm, \floor, \ceil, \dx…). It grows toward the full
/// spec; unparseable input passes through untouched (never blocks the user).
library;

const _controlWords = <String, String>{
  // Greek (subset; extend from the palette data file later)
  'alpha': r'\alpha', 'beta': r'\beta', 'gamma': r'\gamma', 'delta': r'\delta',
  'epsilon': r'\varepsilon', 'theta': r'\theta', 'lambda': r'\lambda',
  'mu': r'\mu', 'pi': r'\pi', 'sigma': r'\sigma', 'phi': r'\phi',
  'omega': r'\omega', 'Gamma': r'\Gamma', 'Delta': r'\Delta', 'Omega': r'\Omega',
  // Operators & relations
  'infty': r'\infty', 'oo': r'\infty', 'times': r'\times', 'cdot': r'\cdot',
  'pm': r'\pm', 'leq': r'\leq', 'geq': r'\geq', 'neq': r'\neq',
  'approx': r'\approx', 'to': r'\to', 'in': r'\in', 'subset': r'\subset',
  'cup': r'\cup', 'cap': r'\cap', 'forall': r'\forall', 'exists': r'\exists',
  'partial': r'\partial', 'nabla': r'\nabla',
  // N-ary
  'sum': r'\sum', 'prod': r'\prod', 'int': r'\int', 'iint': r'\iint',
  'lim': r'\lim', 'sqrt': r'\sqrt',
};

/// Converts Openote linear input to LaTeX. Idempotent for plain LaTeX input:
/// constructs it doesn't recognize are left as-is.
String linearToLatex(String input) {
  var s = input.trim();
  if (s.isEmpty) return s;

  // 1) Differential sugar before generic control words: \dx → \,\mathrm{d}x
  s = s.replaceAllMapped(
      RegExp(r'\\d([a-z])\b'), (m) => '\\,\\mathrm{d}${m[1]}');

  // 2) Control-word autocorrect for bare words like `oo` used by AsciiMath fans.
  s = s.replaceAllMapped(RegExp(r'(?<![\\a-zA-Z])oo(?![a-zA-Z])'), (_) => r'\infty');

  // 3) Function sugar: \abs(x) → \lvert x\rvert etc.
  s = _replaceCall(s, r'\abs', r'\lvert ', r'\rvert');
  s = _replaceCall(s, r'\norm', r'\lVert ', r'\rVert');
  s = _replaceCall(s, r'\floor', r'\lfloor ', r'\rfloor');
  s = _replaceCall(s, r'\ceil', r'\lceil ', r'\rceil');

  // 4) Matrices & cases: ■(a&b@c&d), \matrix(...), \cases(...)
  s = _matrixLike(s, marker: '■(', open: r'\begin{pmatrix}', close: r'\end{pmatrix}');
  s = _matrixLike(s, marker: r'\matrix(', open: r'\begin{pmatrix}', close: r'\end{pmatrix}');
  s = _matrixLike(s, marker: r'\cases(', open: r'\begin{cases}', close: r'\end{cases}');

  // 5) Root with degree: √(n&x) or \sqrt(n&x) → \sqrt[n]{x}; then plain √(x).
  s = s.replaceAllMapped(RegExp('(?:√|\\\\sqrt)\\(([^&()]+)&([^()]+)\\)'),
      (m) => '\\sqrt[${m[1]}]{${m[2]}}');
  s = s.replaceAllMapped(
      RegExp('√\\(([^()]+)\\)'), (m) => '\\sqrt{${m[1]}}');
  s = s.replaceAllMapped(RegExp('√([A-Za-z0-9])'), (m) => '\\sqrt{${m[1]}}');

  // 6) n-ary with limits written linear-style: ∑_(lo)^(hi) or \sum_(lo)^(hi)
  //    Convert `_(...)` / `^(...)` groups to `_{...}` / `^{...}`.
  s = s.replaceAllMapped(
      RegExp(r'([_^])\(([^()]*)\)'), (m) => '${m[1]}{${m[2]}}');

  // 7) Unicode n-ary/ops → LaTeX so storage stays pure LaTeX.
  const uni = {
    '∑': r'\sum', '∏': r'\prod', '∫': r'\int', '∞': r'\infty', '×': r'\times',
    '⋅': r'\cdot', '≤': r'\leq', '≥': r'\geq', '≠': r'\neq', '±': r'\pm',
    '→': r'\to', 'π': r'\pi', '∈': r'\in', '∂': r'\partial', '∇': r'\nabla',
  };
  uni.forEach((k, v) => s = s.replaceAll(k, '$v '));

  // 8) Fractions: (a)/(b), {a}/{b}, mixed, and simple x/y — innermost first.
  var prev = '';
  while (prev != s) {
    prev = s;
    // Bare operands may carry scripts (spec §3.3: ^/_ bind tighter than /),
    // so `1/n^2` → \frac{1}{n^2}.
    const bare = r'(?:[A-Za-z0-9\\]+(?:[\^_](?:\{[^{}]*\}|\([^()]*\)|[A-Za-z0-9\\]+))*)';
    s = s.replaceAllMapped(
        RegExp(r'(\(([^()]*)\)|\{([^{}]*)\}|(' + bare + r'))\s*/\s*'
            r'(\(([^()]*)\)|\{([^{}]*)\}|(' + bare + r'))'),
        (m) {
      final num = m[2] ?? m[3] ?? m[4]!;
      final den = m[6] ?? m[7] ?? m[8]!;
      return '\\frac{$num}{$den}';
    });
  }

  // 9) Bare control words like `sum`,`lim` typed without backslash before _ or (
  s = s.replaceAllMapped(RegExp(r'(?<!\\)\b([a-zA-Z]+)(?=[_^(])'), (m) {
    final w = _controlWords[m[1]!];
    return w ?? m[1]!;
  });

  return s.trim();
}

String _replaceCall(String s, String name, String open, String close) {
  final marker = '$name(';
  while (true) {
    final i = s.indexOf(marker);
    if (i < 0) return s;
    final j = _matchParen(s, i + marker.length - 1);
    if (j < 0) return s;
    final inner = s.substring(i + marker.length, j);
    s = s.replaceRange(i, j + 1, '$open$inner$close');
  }
}

String _matrixLike(String s, {required String marker, required String open, required String close}) {
  while (true) {
    final i = s.indexOf(marker);
    if (i < 0) return s;
    final j = _matchParen(s, i + marker.length - 1);
    if (j < 0) return s;
    final body = s
        .substring(i + marker.length, j)
        .split('@')
        .map((row) => row.trim())
        .join(r' \\ ');
    s = s.replaceRange(i, j + 1, '$open $body $close');
  }
}

/// Index of the ')' matching the '(' at [openIdx], or -1.
int _matchParen(String s, int openIdx) {
  var depth = 0;
  for (var k = openIdx; k < s.length; k++) {
    if (s[k] == '(') depth++;
    if (s[k] == ')') {
      depth--;
      if (depth == 0) return k;
    }
  }
  return -1;
}
