/// Everything the maths editor offers, as ONE table (plan: v0.18 §4).
///
/// This list is the single source for five surfaces: the palette buttons, the
/// plain-words search, the hover tooltips, the type-it-yourself autocorrect,
/// and `math_inventory_test.dart`'s generated sweep — which renders every row
/// below through the real renderer and fails if any of them falls back to
/// source. That test is what turns "the palette only offers what we can draw"
/// from a promise into a property.
///
/// Curation bar: year 10 through first-year university. The owner's own
/// imported notebook (countable sets, Big-O) sets the ceiling; anything above
/// it goes through the LaTeX view, which can still write anything.
library;

import 'math_tree.dart';

enum MathCat {
  structure('Build'),
  common('Common'),
  greek('Greek'),
  compare('Compare'),
  sets('Sets & logic'),
  stats('Stats'),
  geometry('Geometry'),
  science('Science'),
  functions('Functions');

  const MathCat(this.title);
  final String title;
}

/// One offer: a button, a search hit, and an autocorrect rule at once.
class MathItem {
  const MathItem({
    required this.id,
    required this.cat,
    required this.name,
    required this.build,
    this.label,
    this.preview,
    this.aliases = const [],
    this.typeIt,
  });

  /// Stable identifier — used by "recently used" and by tests.
  final String id;
  final MathCat cat;

  /// What a student would call it. Shown in the tooltip and searched.
  final String name;

  /// Plain text on the button face, when a character says it best (π, ≤).
  final String? label;

  /// TeX drawn on the button face, when only a picture says it (a fraction).
  final String? preview;

  /// Extra words that should find this. "to the power", "choose", "surd".
  final List<String> aliases;

  /// The keyboard route, shown in the tooltip and honoured by autocorrect.
  /// A bare word (`alpha`, `sqrt`) becomes a space-triggered control word; a
  /// punctuation run (`<=`) is matched as you type.
  final String? typeIt;

  /// Fresh nodes to drop at the caret. A function, not a value, because every
  /// insertion needs its OWN slots — sharing one node between two insertions
  /// is how an editor ends up with two carets in the same box.
  final List<MNode> Function() build;

  /// Everything this should match on, lowercased.
  Iterable<String> get searchTerms =>
      [name, ...aliases, if (typeIt != null) typeIt!, id].map((s) => s.toLowerCase());
}

MSym _s(String tex, {MClass cls = MClass.other}) => MSym(tex, cls: cls);
List<MNode> Function() _sym(String tex, {MClass cls = MClass.other}) =>
    () => [MSym(tex, cls: cls)];

/// A symbol entry, the shape most of this table takes.
MathItem _symbol({
  required String id,
  required MathCat cat,
  required String name,
  required String label,
  required String tex,
  MClass cls = MClass.other,
  List<String> aliases = const [],
  String? typeIt,
}) =>
    MathItem(
      id: id,
      cat: cat,
      name: name,
      label: label,
      aliases: aliases,
      typeIt: typeIt,
      build: _sym(tex, cls: cls),
    );

// ─────────────────────────────────────────────────────────────────────────
// Structures — templates with boxes to fill (§4.1)
// ─────────────────────────────────────────────────────────────────────────

final List<MathItem> _structures = [
  MathItem(
    id: 'frac',
    cat: MathCat.structure,
    name: 'fraction',
    preview: r'\frac{\square}{\square}',
    aliases: ['over', 'divide', 'divided by', 'quotient', 'half'],
    typeIt: '1/2',
    build: () => [MFrac()],
  ),
  MathItem(
    id: 'power',
    cat: MathCat.structure,
    name: 'power',
    preview: r'\square^{\square}',
    aliases: ['squared', 'cubed', 'exponent', 'index', 'to the', 'superscript'],
    typeIt: 'x^2',
    build: () => [MScript(sup: MRow())],
  ),
  MathItem(
    id: 'subscript',
    cat: MathCat.structure,
    name: 'subscript',
    preview: r'\square_{\square}',
    aliases: ['below', 'small', 'index', 'suffix'],
    typeIt: 'x_1',
    build: () => [MScript(sub: MRow())],
  ),
  MathItem(
    id: 'subsup',
    cat: MathCat.structure,
    name: 'power and subscript',
    preview: r'\square_{\square}^{\square}',
    aliases: ['both', 'sub and super'],
    typeIt: 'subsup',
    build: () => [MScript(sub: MRow(), sup: MRow())],
  ),
  MathItem(
    id: 'sqrt',
    cat: MathCat.structure,
    name: 'square root',
    preview: r'\sqrt{\square}',
    aliases: ['root', 'surd', 'radical'],
    typeIt: 'sqrt',
    build: () => [MSqrt()],
  ),
  MathItem(
    id: 'nthroot',
    cat: MathCat.structure,
    name: 'nth root',
    preview: r'\sqrt[\square]{\square}',
    aliases: ['cube root', 'root', 'radical'],
    typeIt: 'root',
    build: () => [MSqrt(degree: MRow())],
  ),
  MathItem(
    id: 'sum',
    cat: MathCat.structure,
    name: 'sum',
    preview: r'\sum_{\square}^{\square}',
    aliases: ['sigma', 'add up', 'series', 'total'],
    typeIt: 'sum',
    build: () => [
      MScript(
          base: MRow([_s(r'\sum', cls: MClass.op)]), sub: MRow(), sup: MRow())
    ],
  ),
  MathItem(
    id: 'int',
    cat: MathCat.structure,
    name: 'integral',
    preview: r'\int_{\square}^{\square}',
    aliases: ['area under', 'integrate', 'antiderivative'],
    typeIt: 'int',
    build: () => [
      MScript(
          base: MRow([_s(r'\int', cls: MClass.op)]), sub: MRow(), sup: MRow())
    ],
  ),
  MathItem(
    id: 'iint',
    cat: MathCat.structure,
    name: 'double integral',
    preview: r'\iint',
    aliases: ['area', 'volume'],
    typeIt: 'iint',
    build: () => [_s(r'\iint', cls: MClass.op)],
  ),
  MathItem(
    id: 'oint',
    cat: MathCat.structure,
    name: 'closed integral',
    preview: r'\oint',
    aliases: ['contour', 'loop'],
    typeIt: 'oint',
    build: () => [_s(r'\oint', cls: MClass.op)],
  ),
  MathItem(
    id: 'prod',
    cat: MathCat.structure,
    name: 'product',
    preview: r'\prod_{\square}^{\square}',
    aliases: ['multiply all', 'pi product'],
    typeIt: 'prod',
    build: () => [
      MScript(
          base: MRow([_s(r'\prod', cls: MClass.op)]), sub: MRow(), sup: MRow())
    ],
  ),
  MathItem(
    id: 'lim',
    cat: MathCat.structure,
    name: 'limit',
    preview: r'\lim_{\square}',
    aliases: ['approaches', 'tends to', 'as x goes to'],
    typeIt: 'lim',
    build: () => [
      MScript(base: MRow([_s(r'\lim', cls: MClass.func)]), sub: MRow())
    ],
  ),
  MathItem(
    id: 'ddx',
    cat: MathCat.structure,
    name: 'derivative',
    preview: r'\frac{d}{dx}',
    aliases: ['differentiate', 'rate of change', 'dy dx'],
    typeIt: 'ddx',
    build: () => [
      MFrac(
          num: MRow([_s('d', cls: MClass.letter)]),
          den: MRow([_s('d', cls: MClass.letter), _s('x', cls: MClass.letter)]))
    ],
  ),
  MathItem(
    id: 'partial',
    cat: MathCat.structure,
    name: 'partial derivative',
    preview: r'\frac{\partial}{\partial x}',
    aliases: ['partial', 'del'],
    typeIt: 'partial',
    build: () => [
      MFrac(
          num: MRow([_s(r'\partial')]),
          den: MRow([_s(r'\partial'), _s('x', cls: MClass.letter)]))
    ],
  ),
  MathItem(
    id: 'paren',
    cat: MathCat.structure,
    name: 'brackets that grow',
    preview: r'\left(\square\right)',
    aliases: ['parentheses', 'round brackets', 'group'],
    typeIt: '(',
    build: () => [MDelim(left: '(', right: ')')],
  ),
  MathItem(
    id: 'abs',
    cat: MathCat.structure,
    name: 'absolute value',
    preview: r'\left|\square\right|',
    aliases: ['modulus', 'magnitude', 'size', 'distance from zero'],
    typeIt: 'abs',
    build: () => [MDelim(left: '|', right: '|')],
  ),
  MathItem(
    id: 'floor',
    cat: MathCat.structure,
    name: 'floor',
    preview: r'\left\lfloor\square\right\rfloor',
    aliases: ['round down', 'integer part'],
    typeIt: 'floor',
    build: () => [MDelim(left: r'\lfloor', right: r'\rfloor')],
  ),
  MathItem(
    id: 'ceil',
    cat: MathCat.structure,
    name: 'ceiling',
    preview: r'\left\lceil\square\right\rceil',
    aliases: ['round up'],
    typeIt: 'ceil',
    build: () => [MDelim(left: r'\lceil', right: r'\rceil')],
  ),
  MathItem(
    id: 'cases',
    cat: MathCat.structure,
    name: 'piecewise',
    preview: r'\begin{cases}\square\\\square\end{cases}',
    aliases: ['cases', 'brace', 'split definition', 'if'],
    typeIt: 'cases',
    build: () => [MMatrix.sized(env: 'cases', rowCount: 2, colCount: 2)],
  ),
  MathItem(
    id: 'matrix',
    cat: MathCat.structure,
    name: 'matrix',
    preview: r'\begin{pmatrix}\square&\square\\\square&\square\end{pmatrix}',
    aliases: ['grid', 'array', 'table of numbers'],
    typeIt: 'matrix',
    build: () => [MMatrix.sized(env: 'pmatrix')],
  ),
  MathItem(
    id: 'determinant',
    cat: MathCat.structure,
    name: 'determinant',
    preview: r'\begin{vmatrix}\square&\square\\\square&\square\end{vmatrix}',
    aliases: ['det'],
    typeIt: 'determinant',
    build: () => [MMatrix.sized(env: 'vmatrix')],
  ),
  MathItem(
    id: 'binom',
    cat: MathCat.structure,
    name: 'choose',
    preview: r'\binom{\square}{\square}',
    aliases: ['combination', 'binomial', 'ncr', 'n choose r'],
    typeIt: 'choose',
    build: () => [MBinom()],
  ),
  MathItem(
    id: 'bar',
    cat: MathCat.structure,
    name: 'bar',
    preview: r'\bar{\square}',
    aliases: ['mean', 'average', 'overline', 'x bar'],
    typeIt: 'bar',
    build: () => [MAccent(cmd: r'\bar')],
  ),
  MathItem(
    id: 'hat',
    cat: MathCat.structure,
    name: 'hat',
    preview: r'\hat{\square}',
    aliases: ['estimate', 'unit vector', 'circumflex'],
    typeIt: 'hat',
    build: () => [MAccent(cmd: r'\hat')],
  ),
  MathItem(
    id: 'vec',
    cat: MathCat.structure,
    name: 'vector arrow',
    preview: r'\vec{\square}',
    aliases: ['vector', 'arrow over'],
    typeIt: 'vec',
    build: () => [MAccent(cmd: r'\vec')],
  ),
  MathItem(
    id: 'dot',
    cat: MathCat.structure,
    name: 'dot',
    preview: r'\dot{\square}',
    aliases: ['rate', 'time derivative'],
    typeIt: 'dot',
    build: () => [MAccent(cmd: r'\dot')],
  ),
  MathItem(
    id: 'tilde',
    cat: MathCat.structure,
    name: 'tilde',
    preview: r'\tilde{\square}',
    aliases: ['approximation', 'squiggle'],
    typeIt: 'tilde',
    build: () => [MAccent(cmd: r'\tilde')],
  ),
  MathItem(
    id: 'prime',
    cat: MathCat.structure,
    name: 'prime',
    label: '′',
    aliases: ['dash', 'derivative', 'f dash'],
    typeIt: "'",
    // `{}^{\prime}` rather than a bare `'`: after any script — and `\sum_i^n`
    // is a script — a bare prime is a second superscript and the equation
    // stops drawing.
    build: () => [_s(r'{}^{\prime}')],
  ),
  MathItem(
    id: 'words',
    cat: MathCat.structure,
    name: 'words',
    preview: r'\text{if}',
    aliases: ['text', 'label', 'if', 'where', 'writing'],
    typeIt: 'text',
    build: () => [MText('')],
  ),
];

// ─────────────────────────────────────────────────────────────────────────
// Symbols (§4.2)
// ─────────────────────────────────────────────────────────────────────────

final List<MathItem> _common = [
  _symbol(id: 'pm', cat: MathCat.common, name: 'plus or minus', label: '±', tex: r'\pm', cls: MClass.op, typeIt: '+-'),
  _symbol(id: 'times', cat: MathCat.common, name: 'times', label: '×', tex: r'\times', cls: MClass.op, aliases: ['multiply', 'multiplied by'], typeIt: 'times'),
  _symbol(id: 'div', cat: MathCat.common, name: 'divide', label: '÷', tex: r'\div', cls: MClass.op, aliases: ['divided by'], typeIt: 'div'),
  _symbol(id: 'cdot', cat: MathCat.common, name: 'dot product', label: '⋅', tex: r'\cdot', cls: MClass.op, aliases: ['times', 'multiply'], typeIt: 'cdot'),
  _symbol(id: 'neq', cat: MathCat.common, name: 'not equal', label: '≠', tex: r'\neq', cls: MClass.rel, aliases: ['does not equal'], typeIt: '!='),
  _symbol(id: 'approx', cat: MathCat.common, name: 'roughly equal', label: '≈', tex: r'\approx', cls: MClass.rel, aliases: ['about', 'approximately'], typeIt: '~='),
  _symbol(id: 'leq', cat: MathCat.common, name: 'less than or equal', label: '≤', tex: r'\leq', cls: MClass.rel, aliases: ['at most', 'no more than'], typeIt: '<='),
  _symbol(id: 'geq', cat: MathCat.common, name: 'greater than or equal', label: '≥', tex: r'\geq', cls: MClass.rel, aliases: ['at least', 'no less than'], typeIt: '>='),
  _symbol(id: 'lt', cat: MathCat.common, name: 'less than', label: '<', tex: '<', cls: MClass.rel),
  _symbol(id: 'gt', cat: MathCat.common, name: 'greater than', label: '>', tex: '>', cls: MClass.rel),
  _symbol(id: 'percent', cat: MathCat.common, name: 'percent', label: '%', tex: r'\%', aliases: ['per cent', 'out of 100']),
  // `{}^{\circ}`, not `^\circ`. The bare form is BOTH an unterminated command
  // — `30^\circC` ran the C into the command name and drew nothing — and a
  // script start, so `x^{2}` followed by it was a double superscript. The
  // empty group in front fixes both at the source.
  _symbol(id: 'degree', cat: MathCat.common, name: 'degrees', label: '°', tex: r'{}^{\circ}', aliases: ['angle', 'temperature']),
  _symbol(id: 'infty', cat: MathCat.common, name: 'infinity', label: '∞', tex: r'\infty', aliases: ['endless', 'forever'], typeIt: 'oo'),
  _symbol(id: 'factorial', cat: MathCat.common, name: 'factorial', label: '!', tex: '!', aliases: ['bang']),
  _symbol(id: 'propto', cat: MathCat.common, name: 'proportional to', label: '∝', tex: r'\propto', cls: MClass.rel, aliases: ['varies with']),
  _symbol(id: 'ldots', cat: MathCat.common, name: 'and so on', label: '…', tex: r'\ldots', aliases: ['dots', 'ellipsis', 'continues']),
  _symbol(id: 'equiv', cat: MathCat.common, name: 'identical to', label: '≡', tex: r'\equiv', cls: MClass.rel, aliases: ['congruent', 'always equals']),
  _symbol(id: 'pi', cat: MathCat.common, name: 'pi', label: 'π', tex: r'\pi', typeIt: 'pi'),
  _symbol(id: 'theta', cat: MathCat.common, name: 'theta', label: 'θ', tex: r'\theta', aliases: ['angle'], typeIt: 'theta'),
];

/// The full Greek alphabet, lower and upper. Each carries its NAME, so a
/// student who can only say "theta" finds θ, and typing `theta` writes it.
final List<MathItem> _greek = () {
  const lower = <(String, String)>[
    ('alpha', 'α'), ('beta', 'β'), ('gamma', 'γ'), ('delta', 'δ'),
    ('epsilon', 'ε'), ('zeta', 'ζ'), ('eta', 'η'), ('theta', 'θ'),
    ('iota', 'ι'), ('kappa', 'κ'), ('lambda', 'λ'), ('mu', 'μ'),
    ('nu', 'ν'), ('xi', 'ξ'), ('pi', 'π'), ('rho', 'ρ'),
    ('sigma', 'σ'), ('tau', 'τ'), ('upsilon', 'υ'), ('phi', 'φ'),
    ('chi', 'χ'), ('psi', 'ψ'), ('omega', 'ω'),
  ];
  const upper = <(String, String)>[
    ('Gamma', 'Γ'), ('Delta', 'Δ'), ('Theta', 'Θ'), ('Lambda', 'Λ'),
    ('Xi', 'Ξ'), ('Pi', 'Π'), ('Sigma', 'Σ'), ('Upsilon', 'Υ'),
    ('Phi', 'Φ'), ('Psi', 'Ψ'), ('Omega', 'Ω'),
  ];
  return [
    for (final (n, glyph) in [...lower, ...upper])
      _symbol(
        id: 'greek-$n',
        cat: MathCat.greek,
        // `epsilon` renders as the round ε students are taught, not \epsilon's
        // lunate ϵ; `phi` likewise.
        name: n.toLowerCase() == n ? n : 'capital ${n.toLowerCase()}',
        label: glyph,
        tex: switch (n) {
          'epsilon' => r'\varepsilon',
          'phi' => r'\varphi',
          _ => '\\$n',
        },
        typeIt: n,
      ),
  ];
}();

final List<MathItem> _compare = [
  _symbol(id: 'eq', cat: MathCat.compare, name: 'equals', label: '=', tex: '=', cls: MClass.rel),
  _symbol(id: 'cong', cat: MathCat.compare, name: 'congruent to', label: '≅', tex: r'\cong', cls: MClass.rel, aliases: ['same shape and size']),
  _symbol(id: 'll', cat: MathCat.compare, name: 'much less than', label: '≪', tex: r'\ll', cls: MClass.rel),
  _symbol(id: 'gg', cat: MathCat.compare, name: 'much greater than', label: '≫', tex: r'\gg', cls: MClass.rel),
  _symbol(id: 'to', cat: MathCat.compare, name: 'goes to', label: '→', tex: r'\to', cls: MClass.rel, aliases: ['approaches', 'tends to', 'arrow', 'maps to'], typeIt: '->'),
  // **No `<-` shortcut.** `x <-3` is an inequality against a negative number
  // far more often than it is a left arrow, and the shortcut turned one into
  // the other silently. `->` stays: `x ->` is not otherwise valid maths.
  _symbol(id: 'gets', cat: MathCat.compare, name: 'left arrow', label: '←', tex: r'\leftarrow', cls: MClass.rel),
  _symbol(id: 'leftrightarrow', cat: MathCat.compare, name: 'both ways', label: '↔', tex: r'\leftrightarrow', cls: MClass.rel),
  _symbol(id: 'implies', cat: MathCat.compare, name: 'implies', label: '⇒', tex: r'\Rightarrow', cls: MClass.rel, aliases: ['therefore', 'so', 'then'], typeIt: '=>'),
  _symbol(id: 'impliedby', cat: MathCat.compare, name: 'is implied by', label: '⇐', tex: r'\Leftarrow', cls: MClass.rel),
  _symbol(id: 'iff', cat: MathCat.compare, name: 'if and only if', label: '⇔', tex: r'\Leftrightarrow', cls: MClass.rel, aliases: ['iff', 'equivalent']),
  _symbol(id: 'mapsto', cat: MathCat.compare, name: 'maps to', label: '↦', tex: r'\mapsto', cls: MClass.rel),
  _symbol(id: 'therefore', cat: MathCat.compare, name: 'therefore', label: '∴', tex: r'\therefore', cls: MClass.rel),
  _symbol(id: 'because', cat: MathCat.compare, name: 'because', label: '∵', tex: r'\because', cls: MClass.rel),
];

final List<MathItem> _sets = [
  _symbol(id: 'in', cat: MathCat.sets, name: 'is in', label: '∈', tex: r'\in', cls: MClass.rel, aliases: ['element of', 'belongs to', 'member'], typeIt: 'in'),
  _symbol(id: 'notin', cat: MathCat.sets, name: 'is not in', label: '∉', tex: r'\notin', cls: MClass.rel, aliases: ['not an element']),
  _symbol(id: 'subset', cat: MathCat.sets, name: 'subset of', label: '⊂', tex: r'\subset', cls: MClass.rel, typeIt: 'subset'),
  _symbol(id: 'subseteq', cat: MathCat.sets, name: 'subset of or equal', label: '⊆', tex: r'\subseteq', cls: MClass.rel),
  _symbol(id: 'notsubset', cat: MathCat.sets, name: 'not a subset of', label: '⊄', tex: r'\not\subset', cls: MClass.rel),
  _symbol(id: 'cup', cat: MathCat.sets, name: 'union', label: '∪', tex: r'\cup', cls: MClass.op, aliases: ['or', 'combined'], typeIt: 'cup'),
  _symbol(id: 'cap', cat: MathCat.sets, name: 'intersection', label: '∩', tex: r'\cap', cls: MClass.op, aliases: ['and', 'both', 'overlap'], typeIt: 'cap'),
  _symbol(id: 'emptyset', cat: MathCat.sets, name: 'empty set', label: '∅', tex: r'\emptyset', aliases: ['nothing', 'null set']),
  _symbol(id: 'setminus', cat: MathCat.sets, name: 'without', label: '∖', tex: r'\setminus', cls: MClass.op, aliases: ['minus', 'difference', 'except']),
  _symbol(id: 'naturals', cat: MathCat.sets, name: 'natural numbers', label: 'ℕ', tex: r'\mathbb{N}', aliases: ['counting numbers']),
  _symbol(id: 'integers', cat: MathCat.sets, name: 'integers', label: 'ℤ', tex: r'\mathbb{Z}', aliases: ['whole numbers']),
  _symbol(id: 'rationals', cat: MathCat.sets, name: 'rational numbers', label: 'ℚ', tex: r'\mathbb{Q}', aliases: ['fractions']),
  _symbol(id: 'reals', cat: MathCat.sets, name: 'real numbers', label: 'ℝ', tex: r'\mathbb{R}'),
  _symbol(id: 'complex', cat: MathCat.sets, name: 'complex numbers', label: 'ℂ', tex: r'\mathbb{C}'),
  _symbol(id: 'forall', cat: MathCat.sets, name: 'for all', label: '∀', tex: r'\forall', aliases: ['every', 'any'], typeIt: 'forall'),
  _symbol(id: 'exists', cat: MathCat.sets, name: 'there exists', label: '∃', tex: r'\exists', aliases: ['some'], typeIt: 'exists'),
  _symbol(id: 'lnot', cat: MathCat.sets, name: 'not', label: '¬', tex: r'\neg', aliases: ['negation']),
  _symbol(id: 'land', cat: MathCat.sets, name: 'and', label: '∧', tex: r'\land', cls: MClass.op, aliases: ['conjunction']),
  _symbol(id: 'lor', cat: MathCat.sets, name: 'or', label: '∨', tex: r'\lor', cls: MClass.op, aliases: ['disjunction']),
  _symbol(id: 'oplus', cat: MathCat.sets, name: 'exclusive or', label: '⊕', tex: r'\oplus', cls: MClass.op, aliases: ['xor']),
  _symbol(id: 'mid', cat: MathCat.sets, name: 'divides', label: '∣', tex: r'\mid', cls: MClass.rel, aliases: ['such that', 'given']),
  _symbol(id: 'nmid', cat: MathCat.sets, name: 'does not divide', label: '∤', tex: r'\nmid', cls: MClass.rel),
];

final List<MathItem> _stats = [
  MathItem(
    id: 'xbar',
    cat: MathCat.stats,
    name: 'sample mean',
    preview: r'\bar{x}',
    aliases: ['x bar', 'average'],
    build: () => [MAccent(cmd: r'\bar', base: MRow([_s('x', cls: MClass.letter)]))],
  ),
  MathItem(
    id: 'xhat',
    cat: MathCat.stats,
    name: 'estimate',
    preview: r'\hat{x}',
    aliases: ['x hat', 'predicted'],
    build: () => [MAccent(cmd: r'\hat', base: MRow([_s('x', cls: MClass.letter)]))],
  ),
  _symbol(id: 'sim', cat: MathCat.stats, name: 'is distributed as', label: '∼', tex: r'\sim', cls: MClass.rel, aliases: ['follows the distribution', 'tilde']),
  _symbol(id: 'mu', cat: MathCat.stats, name: 'mean', label: 'μ', tex: r'\mu', aliases: ['population mean', 'mu']),
  _symbol(id: 'sigma-sym', cat: MathCat.stats, name: 'standard deviation', label: 'σ', tex: r'\sigma', aliases: ['sigma', 'spread']),
  MathItem(
    id: 'variance',
    cat: MathCat.stats,
    name: 'variance',
    preview: r'\sigma^{2}',
    aliases: ['sigma squared'],
    build: () => [
      MScript(base: MRow([_s(r'\sigma')]), sup: MRow([_s('2', cls: MClass.digit)]))
    ],
  ),
  _symbol(id: 'prob', cat: MathCat.stats, name: 'probability', label: 'P', tex: 'P', cls: MClass.letter, aliases: ['chance', 'p of']),
  _symbol(id: 'expect', cat: MathCat.stats, name: 'expected value', label: 'E', tex: 'E', cls: MClass.letter, aliases: ['mean of', 'expectation']),
  _symbol(id: 'given', cat: MathCat.stats, name: 'given', label: '∣', tex: r'\mid', cls: MClass.rel, aliases: ['conditional', 'given that']),
];

final List<MathItem> _geometry = [
  _symbol(id: 'angle', cat: MathCat.geometry, name: 'angle', label: '∠', tex: r'\angle'),
  _symbol(id: 'triangle', cat: MathCat.geometry, name: 'triangle', label: '△', tex: r'\triangle'),
  _symbol(id: 'parallel', cat: MathCat.geometry, name: 'parallel to', label: '∥', tex: r'\parallel', cls: MClass.rel),
  _symbol(id: 'perp', cat: MathCat.geometry, name: 'perpendicular to', label: '⊥', tex: r'\perp', cls: MClass.rel, aliases: ['at right angles']),
  _symbol(id: 'similar', cat: MathCat.geometry, name: 'similar to', label: '∼', tex: r'\sim', cls: MClass.rel, aliases: ['same shape']),
  _symbol(id: 'congruent', cat: MathCat.geometry, name: 'congruent to', label: '≅', tex: r'\cong', cls: MClass.rel),
];

/// Small and honest (§4.2): every row here was probed against the renderer
/// before it was offered, and anything that fell back was cut rather than
/// worked around.
final List<MathItem> _science = [
  _symbol(id: 'rlharp', cat: MathCat.science, name: 'reversible reaction', label: '⇌', tex: r'\rightleftharpoons', cls: MClass.rel, aliases: ['equilibrium', 'both directions']),
  _symbol(id: 'Delta-sci', cat: MathCat.science, name: 'change in', label: 'Δ', tex: r'\Delta', aliases: ['delta', 'difference']),
  _symbol(id: 'rho', cat: MathCat.science, name: 'density', label: 'ρ', tex: r'\rho', aliases: ['rho']),
  _symbol(id: 'lambda-sci', cat: MathCat.science, name: 'wavelength', label: 'λ', tex: r'\lambda', aliases: ['lambda']),
  _symbol(id: 'hbar', cat: MathCat.science, name: 'reduced Planck constant', label: 'ℏ', tex: r'\hbar', aliases: ['h bar', 'planck']),
  _symbol(id: 'nabla', cat: MathCat.science, name: 'gradient', label: '∇', tex: r'\nabla', aliases: ['del', 'nabla'], typeIt: 'nabla'),
];

/// Upright function names — the rule every textbook follows, applied without
/// the student having to know it exists.
final List<MathItem> _functions = () {
  const plain = [
    'sin', 'cos', 'tan', 'sec', 'csc', 'cot',
    'sinh', 'cosh', 'tanh', 'ln', 'log', 'exp',
    'max', 'min', 'gcd', 'det', 'arg', 'deg',
  ];
  return <MathItem>[
    for (final f in plain)
      MathItem(
        id: 'fn-$f',
        cat: MathCat.functions,
        name: f,
        label: f,
        aliases: switch (f) {
          'ln' => ['natural log'],
          'log' => ['logarithm'],
          'exp' => ['e to the'],
          'gcd' => ['highest common factor', 'hcf'],
          _ => const [],
        },
        typeIt: f,
        build: () => [_s('\\$f', cls: MClass.func)],
      ),
    // Q1, decided by the owner 2026-08-19: the buttons read sin⁻¹, which is
    // what AU school textbooks and calculators print. `arcsin` stays a search
    // alias so the other convention still finds it.
    for (final f in ['sin', 'cos', 'tan'])
      MathItem(
        id: 'fn-arc$f',
        cat: MathCat.functions,
        name: '$f inverse',
        preview: '\\$f^{-1}',
        aliases: ['arc$f', 'inverse $f'],
        build: () => [
          MScript(
            base: MRow([_s('\\$f', cls: MClass.func)]),
            sup: MRow([_s('-', cls: MClass.op), _s('1', cls: MClass.digit)]),
          )
        ],
      ),
    MathItem(
      id: 'fn-logbase',
      cat: MathCat.functions,
      name: 'log to a base',
      preview: r'\log_{\square}',
      aliases: ['log base', 'logarithm base'],
      build: () => [
        MScript(base: MRow([_s(r'\log', cls: MClass.func)]), sub: MRow())
      ],
    ),
    MathItem(
      id: 'fn-etox',
      cat: MathCat.functions,
      name: 'e to the power',
      preview: r'e^{\square}',
      aliases: ['exponential', 'e^x'],
      build: () => [
        MScript(base: MRow([_s('e', cls: MClass.letter)]), sup: MRow())
      ],
    ),
    MathItem(
      id: 'fn-mod',
      cat: MathCat.functions,
      name: 'modulo',
      preview: r'\bmod',
      aliases: ['mod', 'remainder'],
      build: () => [_s(r'\bmod', cls: MClass.op)],
    ),
    MathItem(
      id: 'fn-dx',
      cat: MathCat.functions,
      name: 'with respect to x',
      preview: r'\,\mathrm{d}x',
      aliases: ['dx', 'differential'],
      build: () => [_s(r'\,\mathrm{d}x')],
    ),
  ];
}();

/// THE table. Everything the editor offers, in palette order.
final List<MathItem> mathItems = [
  ..._structures,
  ..._common,
  ..._greek,
  ..._compare,
  ..._sets,
  ..._stats,
  ..._geometry,
  ..._science,
  ..._functions,
];

final Map<String, MathItem> mathItemsById = {
  for (final i in mathItems) i.id: i,
};

List<MathItem> mathItemsIn(MathCat cat) =>
    [for (final i in mathItems) if (i.cat == cat) i];

/// Control words that autocorrect when a space (or an operator) follows —
/// `alpha` → α, `sqrt` → the radical. Derived from the table's own `typeIt`,
/// so the tooltip cannot promise a shortcut the editor doesn't honour.
///
/// Where two entries share a word (θ appears in Common and Greek), the FIRST
/// wins, which is why Common is listed before Greek above.
final Map<String, MathItem> mathControlWords = () {
  final out = <String, MathItem>{};
  for (final i in mathItems) {
    final t = i.typeIt;
    if (t == null || t.isEmpty) continue;
    if (!RegExp(r'^[A-Za-z]+$').hasMatch(t)) continue;
    out.putIfAbsent(t, () => i);
  }
  return out;
}();

/// Punctuation runs that autocorrect the moment they're complete: `<=` → ≤.
/// Longest first, so `<->` is never eaten by `<-`.
///
/// Only runs made ENTIRELY of punctuation qualify. Several entries advertise
/// an *example* rather than a shortcut — `x^2`, `1/2`, `x_1` teach the shape,
/// they are not sequences to substitute — and treating those as runs turned
/// every typed `x_1` into a subscript template.
final List<(String, MathItem)> mathOperatorRuns = () {
  final out = <(String, MathItem)>[];
  final punctuationOnly = RegExp(r'^[^A-Za-z0-9]+$');
  for (final i in mathItems) {
    final t = i.typeIt;
    if (t == null || t.length < 2) continue;
    if (!punctuationOnly.hasMatch(t)) continue;
    out.add((t, i));
  }
  out.sort((a, b) => b.$1.length.compareTo(a.$1.length));
  return out;
}();

/// Plain-words search over the whole table.
///
/// Two rules the first version got wrong, both measured:
///
/// * **A NAME must beat an ALIAS.** Every term scored alike, so an earlier
///   row's loose alias outranked a later row's exact name: "angle" found the
///   degree sign before ∠, "sigma" found Σ before σ, "therefore" found ⇒
///   before ∴. The student typed the thing's own name and got something else —
///   and since Enter inserts the first hit, they got it in their equation.
/// * **A query LONGER than the stored term must still match.** Scoring only
///   compared equality, prefix and substring, so "greater than or equal to"
///   scored zero against the name "greater than or equal", and the panel then
///   told the student the symbol did not exist. A token-overlap branch catches
///   the natural longer phrasing.
List<MathItem> searchMathItems(String query, {int limit = 40}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final qWords = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();

  // A name outranks an alias at every tier, by more than any tier gap — so no
  // alias can outrank a name that matched at least as well.
  int scoreTerm(String term, {required bool isName}) {
    final bonus = isName ? 200 : 0;
    if (term == q) return 100 + bonus;
    if (term.startsWith(q)) return 70 + bonus;
    if (term.split(' ').any((w) => w.startsWith(q))) return 55 + bonus;
    if (term.contains(q)) return 40 + bonus;
    if (qWords.length > 1) {
      final tWords = term.split(RegExp(r'\s+')).toSet();
      final shared = qWords.intersection(tWords).length;
      if (shared > 0 && shared >= tWords.length) return 45 + bonus;
      if (shared >= 2) return 35 + bonus;
    }
    return 0;
  }

  final scored = <(int, int, MathItem)>[];
  for (var idx = 0; idx < mathItems.length; idx++) {
    final item = mathItems[idx];
    var best = scoreTerm(item.name.toLowerCase(), isName: true);
    for (final term in [
      ...item.aliases,
      item.id,
      if (item.typeIt != null) item.typeIt!,
    ]) {
      final v = scoreTerm(term.toLowerCase(), isName: false);
      if (v > best) best = v;
    }
    // Pasting the character itself finds it.
    if (item.label == query) best = 400;
    if (best > 0) scored.add((best, idx, item));
  }
  scored.sort((a, b) => a.$1 == b.$1 ? a.$2.compareTo(b.$2) : b.$1.compareTo(a.$1));
  return [for (final s in scored.take(limit)) s.$3];
}
