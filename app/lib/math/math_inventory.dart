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
    this.alsoTypeIt = const [],
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

  /// Other commands that build the same thing.
  ///
  /// [typeIt] is the ONE route a tooltip advertises; these are the ones a
  /// student might reasonably reach for anyway. `\root` was the advertised
  /// route to an nth root before `\rt` took over, and a shortcut that used
  /// to work and silently stopped is worse than one that never existed.
  final List<String> alsoTypeIt;

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
    typeIt: r'\subsup',
    build: () => [MScript(sub: MRow(), sup: MRow())],
  ),
  MathItem(
    id: 'sqrt',
    cat: MathCat.structure,
    name: 'square root',
    preview: r'\sqrt{\square}',
    aliases: ['root', 'surd', 'radical'],
    typeIt: r'\sqrt',
    build: () => [MSqrt()],
  ),
  // **The root family you can type.** `\rt` opens a root with an empty index
  // box; `\cbrt` is the cube root; and `\2rt`, `\3rt`, `\7rt` fill the index
  // in for you (see `_buildControlWord`). A bare radical means two, so `\2rt`
  // deliberately DRAWS the two — the owner: *"in the case where someone does
  // \2rt, we should render the 2 even though its otherwise assumed its 2"*.
  MathItem(
    id: 'nthroot',
    cat: MathCat.structure,
    name: 'nth root',
    preview: r'\sqrt[\square]{\square}',
    aliases: ['root', 'radical', 'fourth root', 'fifth root', 'index'],
    typeIt: r'\rt',
    alsoTypeIt: [r'\root', r'\nrt'],
    build: () => [MSqrt(degree: MRow())],
  ),
  MathItem(
    id: 'cbrt',
    cat: MathCat.structure,
    name: 'cube root',
    preview: r'\sqrt[3]{\square}',
    aliases: ['third root', 'root', 'radical'],
    typeIt: r'\cbrt',
    alsoTypeIt: [r'\3rt'],
    build: () => [
      MSqrt(degree: MRow([_s('3', cls: MClass.digit)])),
    ],
  ),
  MathItem(
    id: 'sum',
    cat: MathCat.structure,
    name: 'sum',
    preview: r'\sum_{\square}^{\square}',
    aliases: ['sigma', 'add up', 'series', 'total'],
    typeIt: r'\sum',
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
    typeIt: r'\int',
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
    typeIt: r'\iint',
    build: () => [_s(r'\iint', cls: MClass.op)],
  ),
  MathItem(
    id: 'oint',
    cat: MathCat.structure,
    name: 'closed integral',
    preview: r'\oint',
    aliases: ['contour', 'loop'],
    typeIt: r'\oint',
    build: () => [_s(r'\oint', cls: MClass.op)],
  ),
  MathItem(
    id: 'prod',
    cat: MathCat.structure,
    name: 'product',
    preview: r'\prod_{\square}^{\square}',
    aliases: ['multiply all', 'pi product'],
    typeIt: r'\prod',
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
    typeIt: r'\lim',
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
    typeIt: r'\ddx',
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
    typeIt: r'\partial',
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
    typeIt: r'\abs',
    build: () => [MDelim(left: '|', right: '|')],
  ),
  MathItem(
    id: 'floor',
    cat: MathCat.structure,
    name: 'floor',
    preview: r'\left\lfloor\square\right\rfloor',
    aliases: ['round down', 'integer part'],
    typeIt: r'\floor',
    build: () => [MDelim(left: r'\lfloor', right: r'\rfloor')],
  ),
  MathItem(
    id: 'ceil',
    cat: MathCat.structure,
    name: 'ceiling',
    preview: r'\left\lceil\square\right\rceil',
    aliases: ['round up'],
    typeIt: r'\ceil',
    build: () => [MDelim(left: r'\lceil', right: r'\rceil')],
  ),
  MathItem(
    id: 'cases',
    cat: MathCat.structure,
    name: 'piecewise',
    preview: r'\begin{cases}\square\\\square\end{cases}',
    aliases: ['cases', 'brace', 'split definition', 'if'],
    typeIt: r'\cases',
    build: () => [MMatrix.sized(env: 'cases', rowCount: 2, colCount: 2)],
  ),
  MathItem(
    id: 'matrix',
    cat: MathCat.structure,
    name: 'matrix',
    preview: r'\begin{pmatrix}\square&\square\\\square&\square\end{pmatrix}',
    aliases: ['grid', 'array', 'table of numbers'],
    typeIt: r'\matrix',
    build: () => [MMatrix.sized(env: 'pmatrix')],
  ),
  MathItem(
    id: 'determinant',
    cat: MathCat.structure,
    name: 'determinant',
    preview: r'\begin{vmatrix}\square&\square\\\square&\square\end{vmatrix}',
    aliases: ['det'],
    typeIt: r'\determinant',
    build: () => [MMatrix.sized(env: 'vmatrix')],
  ),
  MathItem(
    id: 'binom',
    cat: MathCat.structure,
    name: 'choose',
    preview: r'\binom{\square}{\square}',
    aliases: ['combination', 'binomial', 'ncr', 'n choose r'],
    typeIt: r'\choose',
    build: () => [MBinom()],
  ),
  MathItem(
    id: 'bar',
    cat: MathCat.structure,
    name: 'bar',
    preview: r'\bar{\square}',
    aliases: ['mean', 'average', 'overline', 'x bar'],
    typeIt: r'\bar',
    build: () => [MAccent(cmd: r'\bar')],
  ),
  MathItem(
    id: 'hat',
    cat: MathCat.structure,
    name: 'hat',
    preview: r'\hat{\square}',
    aliases: ['estimate', 'unit vector', 'circumflex'],
    typeIt: r'\hat',
    build: () => [MAccent(cmd: r'\hat')],
  ),
  MathItem(
    id: 'vec',
    cat: MathCat.structure,
    name: 'vector arrow',
    preview: r'\vec{\square}',
    aliases: ['vector', 'arrow over'],
    typeIt: r'\vec',
    build: () => [MAccent(cmd: r'\vec')],
  ),
  MathItem(
    id: 'dot',
    cat: MathCat.structure,
    name: 'dot',
    preview: r'\dot{\square}',
    aliases: ['rate', 'time derivative'],
    typeIt: r'\dot',
    build: () => [MAccent(cmd: r'\dot')],
  ),
  MathItem(
    id: 'tilde',
    cat: MathCat.structure,
    name: 'tilde',
    preview: r'\tilde{\square}',
    aliases: ['approximation', 'squiggle'],
    typeIt: r'\tilde',
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
    typeIt: r'\text',
    build: () => [MText('')],
  ),
];

// ─────────────────────────────────────────────────────────────────────────
// Symbols (§4.2)
// ─────────────────────────────────────────────────────────────────────────

final List<MathItem> _common = [
  _symbol(id: 'pm', cat: MathCat.common, name: 'plus or minus', label: '±', tex: r'\pm', cls: MClass.op, typeIt: '+-'),
  _symbol(id: 'times', cat: MathCat.common, name: 'times', label: '×', tex: r'\times', cls: MClass.op, aliases: ['multiply', 'multiplied by'], typeIt: r'\times'),
  _symbol(id: 'div', cat: MathCat.common, name: 'divide', label: '÷', tex: r'\div', cls: MClass.op, aliases: ['divided by'], typeIt: r'\div'),
  // A year-10 student inserting a multiplication dot was told they had
  // inserted a vector operation they will not meet for years. The old
  // name stays as a search word.
  _symbol(id: 'cdot', cat: MathCat.common, name: 'times', label: '⋅', tex: r'\cdot', cls: MClass.op, aliases: ['multiply', 'dot product', 'times by'], typeIt: r'\cdot'),
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
  _symbol(id: 'infty', cat: MathCat.common, name: 'infinity', label: '∞', tex: r'\infty', aliases: ['endless', 'forever'], typeIt: r'\oo'),
  _symbol(id: 'factorial', cat: MathCat.common, name: 'factorial', label: '!', tex: '!', aliases: ['bang']),
  _symbol(id: 'propto', cat: MathCat.common, name: 'proportional to', label: '∝', tex: r'\propto', cls: MClass.rel, aliases: ['varies with']),
  _symbol(id: 'ldots', cat: MathCat.common, name: 'and so on', label: '…', tex: r'\ldots', aliases: ['dots', 'ellipsis', 'continues']),
  _symbol(id: 'equiv', cat: MathCat.common, name: 'identical to', label: '≡', tex: r'\equiv', cls: MClass.rel, aliases: ['congruent', 'always equals']),
  _symbol(id: 'pi', cat: MathCat.common, name: 'pi', label: 'π', tex: r'\pi', typeIt: r'\pi'),
  _symbol(id: 'theta', cat: MathCat.common, name: 'theta', label: 'θ', tex: r'\theta', aliases: ['angle'], typeIt: r'\theta'),
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
  // **All twenty-four capitals**, not the eleven LaTeX happens to name.
  //
  // TeX has no `\Alpha`, `\Beta`, `\Rho` and so on for a reason: capital
  // alpha IS a capital A, so the command would be a synonym for a letter you
  // can already type. That is a typesetter's reason, not a student's — asked
  // for the Greek alphabet, "some of it" is a wrong answer, and a student
  // hunting for capital sigma has no way to know that eleven of the
  // twenty-four are special. Each of the other thirteen inserts the Latin
  // capital it is drawn as, which is exactly what it looks like set.
  const upper = <(String, String, String)>[
    ('Alpha', 'Α', 'A'), ('Beta', 'Β', 'B'), ('Gamma', 'Γ', r'\Gamma'),
    ('Delta', 'Δ', r'\Delta'), ('Epsilon', 'Ε', 'E'), ('Zeta', 'Ζ', 'Z'),
    ('Eta', 'Η', 'H'), ('Theta', 'Θ', r'\Theta'), ('Iota', 'Ι', 'I'),
    ('Kappa', 'Κ', 'K'), ('Lambda', 'Λ', r'\Lambda'), ('Mu', 'Μ', 'M'),
    ('Nu', 'Ν', 'N'), ('Xi', 'Ξ', r'\Xi'), ('Omicron', 'Ο', 'O'),
    ('Pi', 'Π', r'\Pi'), ('Rho', 'Ρ', 'P'), ('Sigma', 'Σ', r'\Sigma'),
    ('Tau', 'Τ', 'T'), ('Upsilon', 'Υ', r'\Upsilon'), ('Phi', 'Φ', r'\Phi'),
    ('Chi', 'Χ', 'X'), ('Psi', 'Ψ', r'\Psi'), ('Omega', 'Ω', r'\Omega'),
  ];
  return [
    for (final (n, glyph) in lower)
      _symbol(
        id: 'greek-$n',
        cat: MathCat.greek,
        name: n,
        label: glyph,
        // `epsilon` renders as the round ε students are taught, not
        // \epsilon's lunate ϵ; `phi` likewise.
        tex: switch (n) {
          'epsilon' => r'\varepsilon',
          'phi' => r'\varphi',
          _ => '\\$n',
        },
        typeIt: '\\$n',
      ),
    for (final (n, glyph, tex) in upper)
      _symbol(
        id: 'greek-$n',
        cat: MathCat.greek,
        name: 'capital ${n.toLowerCase()}',
        label: glyph,
        tex: tex,
        // Only the eleven TeX names answer to a backslash; the rest are
        // ordinary capitals and the student simply types them.
        typeIt: tex.startsWith('\\') ? tex : null,
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
  _symbol(id: 'in', cat: MathCat.sets, name: 'is in', label: '∈', tex: r'\in', cls: MClass.rel, aliases: ['element of', 'belongs to', 'member'], typeIt: r'\in'),
  _symbol(id: 'notin', cat: MathCat.sets, name: 'is not in', label: '∉', tex: r'\notin', cls: MClass.rel, aliases: ['not an element']),
  _symbol(id: 'subset', cat: MathCat.sets, name: 'subset of', label: '⊂', tex: r'\subset', cls: MClass.rel, typeIt: r'\subset'),
  _symbol(id: 'subseteq', cat: MathCat.sets, name: 'subset of or equal', label: '⊆', tex: r'\subseteq', cls: MClass.rel),
  _symbol(id: 'notsubset', cat: MathCat.sets, name: 'not a subset of', label: '⊄', tex: r'\not\subset', cls: MClass.rel),
  _symbol(id: 'cup', cat: MathCat.sets, name: 'union', label: '∪', tex: r'\cup', cls: MClass.op, aliases: ['or', 'combined'], typeIt: r'\cup'),
  _symbol(id: 'cap', cat: MathCat.sets, name: 'intersection', label: '∩', tex: r'\cap', cls: MClass.op, aliases: ['and', 'both', 'overlap'], typeIt: r'\cap'),
  _symbol(id: 'emptyset', cat: MathCat.sets, name: 'empty set', label: '∅', tex: r'\emptyset', aliases: ['nothing', 'null set']),
  _symbol(id: 'setminus', cat: MathCat.sets, name: 'without', label: '∖', tex: r'\setminus', cls: MClass.op, aliases: ['minus', 'difference', 'except']),
  _symbol(id: 'naturals', cat: MathCat.sets, name: 'natural numbers', label: 'ℕ', tex: r'\mathbb{N}', aliases: ['counting numbers']),
  _symbol(id: 'integers', cat: MathCat.sets, name: 'integers', label: 'ℤ', tex: r'\mathbb{Z}', aliases: ['whole numbers']),
  _symbol(id: 'rationals', cat: MathCat.sets, name: 'rational numbers', label: 'ℚ', tex: r'\mathbb{Q}', aliases: ['fractions']),
  _symbol(id: 'reals', cat: MathCat.sets, name: 'real numbers', label: 'ℝ', tex: r'\mathbb{R}'),
  _symbol(id: 'complex', cat: MathCat.sets, name: 'complex numbers', label: 'ℂ', tex: r'\mathbb{C}'),
  _symbol(id: 'forall', cat: MathCat.sets, name: 'for all', label: '∀', tex: r'\forall', aliases: ['every', 'any'], typeIt: r'\forall'),
  _symbol(id: 'exists', cat: MathCat.sets, name: 'there exists', label: '∃', tex: r'\exists', aliases: ['some'], typeIt: r'\exists'),
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
  _symbol(id: 'nabla', cat: MathCat.science, name: 'gradient', label: '∇', tex: r'\nabla', aliases: ['del', 'nabla'], typeIt: r'\nabla'),
];

/// Upright function names — the rule every textbook follows, applied without
/// the student having to know it exists.
final List<MathItem> _functions = () {
  // Ordered so an inverse can sit next to what it inverts (the list is built
  // in two passes below, and the panel reads in this order). `sin cos tan`
  // first because that is the order every trigonometry chapter uses.
  const plain = [
    'sin', 'cos', 'tan',
    'sec', 'csc', 'cot',
    'sinh', 'cosh', 'tanh',
    'ln', 'log', 'exp',
    // `max`, `min` and `gcd` used to be here, and a one-argument `max` is
    // nonsense — they are templates now, below.
    'det', 'arg', 'deg',
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
          'det' => ['determinant'],
          _ => const [],
        },
        typeIt: '\\$f',
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
    // **The ones that need more than one thing.** The owner: *"id like you to
    // fill out the format by default when inserting it, so \gcd will add
    // gcd( , ), with the spaces being the boxes we already have elsewhere,
    // this should be the case for anything that REQUIRES multiple arguments,
    // stuff like sin and whatever shouldnt do that as they have only a single
    // argument."*
    //
    // Every name here is on a school calculator. The preview draws the shape
    // you are about to get, boxes and all, so the button IS the instruction.
    for (final c in const [
      (
        'gcd',
        'greatest common divisor',
        ['highest common factor', 'hcf', 'gcf'],
      ),
      ('lcm', 'lowest common multiple', ['least common multiple']),
      ('max', 'larger of', ['maximum', 'biggest', 'greater']),
      ('min', 'smaller of', ['minimum', 'smallest', 'lesser']),
      (
        'nCr',
        'combinations',
        ['n choose r', 'choose', 'binomial coefficient'],
      ),
      ('nPr', 'permutations', ['arrangements', 'ordered choices']),
    ])
      MathItem(
        id: 'fn-${c.$1}',
        cat: MathCat.functions,
        name: c.$2,
        preview: r'\mathrm{' '${c.$1}' r'}\left(\square,\square \right)',
        aliases: c.$3,
        typeIt: '\\${c.$1}',
        build: () => [MCall(name: c.$1)],
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
      // The word a student is taught. "Modulo" is the one they meet later.
      name: 'remainder',
      preview: r'a \bmod b',
      aliases: ['mod', 'modulo', 'remainder after dividing', 'left over'],
      typeIt: r'\mod',
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

/// The negations, kept together.
///
/// The owner: *"missing the nots for some of the chars, those sorts of
/// things."* A student who has ≤ and needs ≰ should not have to know that TeX
/// spells it `\\nleq` — the door has both, side by side, and the plain-words
/// search finds either by "not".
final List<MathItem> _negations = [
  _symbol(id: 'nless', cat: MathCat.compare, name: 'not less than', label: '≮', tex: r'\nless', cls: MClass.rel, aliases: ['not smaller']),
  _symbol(id: 'ngtr', cat: MathCat.compare, name: 'not greater than', label: '≯', tex: r'\ngtr', cls: MClass.rel, aliases: ['not bigger']),
  _symbol(id: 'nleq', cat: MathCat.compare, name: 'not less than or equal', label: '≰', tex: r'\nleq', cls: MClass.rel),
  _symbol(id: 'ngeq', cat: MathCat.compare, name: 'not greater than or equal', label: '≱', tex: r'\ngeq', cls: MClass.rel),
  _symbol(id: 'nsim', cat: MathCat.compare, name: 'not similar to', label: '≁', tex: r'\nsim', cls: MClass.rel),
  _symbol(id: 'ncong', cat: MathCat.compare, name: 'not congruent to', label: '≇', tex: r'\ncong', cls: MClass.rel),
  _symbol(id: 'nequiv', cat: MathCat.compare, name: 'not identical to', label: '≢', tex: r'\not\equiv', cls: MClass.rel),
  _symbol(id: 'nparallel', cat: MathCat.geometry, name: 'not parallel to', label: '∦', tex: r'\nparallel', cls: MClass.rel),
  _symbol(id: 'nsubseteq', cat: MathCat.sets, name: 'not a subset of or equal', label: '⊈', tex: r'\nsubseteq', cls: MClass.rel),
  _symbol(id: 'nsupset', cat: MathCat.sets, name: 'does not contain', label: '⊅', tex: r'\not\supset', cls: MClass.rel),
  _symbol(id: 'nsupseteq', cat: MathCat.sets, name: 'does not contain or equal', label: '⊉', tex: r'\nsupseteq', cls: MClass.rel),
  _symbol(id: 'nexists', cat: MathCat.sets, name: 'there is no', label: '∄', tex: r'\nexists', aliases: ['does not exist', 'none']),
  _symbol(id: 'nrightarrow', cat: MathCat.compare, name: 'does not go to', label: '↛', tex: r'\nrightarrow', cls: MClass.rel),
  _symbol(id: 'nimplies', cat: MathCat.compare, name: 'does not imply', label: '⇏', tex: r'\nRightarrow', cls: MClass.rel),
  _symbol(id: 'niff', cat: MathCat.compare, name: 'not equivalent to', label: '⇎', tex: r'\nLeftrightarrow', cls: MClass.rel),
];

/// The rest of what a student reaches for. Anything here that the renderer
/// cannot draw is cut by `math_inventory_test`'s generated sweep before it can
/// ever reach a button — that is what makes adding to this list safe.
final List<MathItem> _extras = [
  // Arithmetic and grouping.
  _symbol(id: 'mp', cat: MathCat.common, name: 'minus or plus', label: '∓', tex: r'\mp', cls: MClass.op),
  _symbol(id: 'ast', cat: MathCat.common, name: 'star operator', label: '∗', tex: r'\ast', cls: MClass.op, aliases: ['times', 'convolution']),
  _symbol(id: 'circ', cat: MathCat.common, name: 'composed with', label: '∘', tex: r'\circ', cls: MClass.op, aliases: ['ring', 'of']),
  _symbol(id: 'bullet', cat: MathCat.common, name: 'bullet', label: '∙', tex: r'\bullet', cls: MClass.op),
  _symbol(id: 'otimes', cat: MathCat.common, name: 'tensor product', label: '⊗', tex: r'\otimes', cls: MClass.op),
  _symbol(id: 'odot', cat: MathCat.common, name: 'circled dot', label: '⊙', tex: r'\odot', cls: MClass.op),
  _symbol(id: 'surd', cat: MathCat.common, name: 'root sign', label: '√', tex: r'\surd'),
  _symbol(id: 'partial-sym', cat: MathCat.common, name: 'partial', label: '∂', tex: r'\partial', aliases: ['curly d', 'del']),
  _symbol(id: 'vdots', cat: MathCat.common, name: 'vertical dots', label: '⋮', tex: r'\vdots', aliases: ['and so on down']),
  _symbol(id: 'cdots', cat: MathCat.common, name: 'middle dots', label: '⋯', tex: r'\cdots', aliases: ['and so on']),
  _symbol(id: 'ddots', cat: MathCat.common, name: 'diagonal dots', label: '⋱', tex: r'\ddots'),
  // Relations that come up in proofs.
  _symbol(id: 'simeq', cat: MathCat.compare, name: 'asymptotically equal', label: '≃', tex: r'\simeq', cls: MClass.rel),
  _symbol(id: 'doteq', cat: MathCat.compare, name: 'approaches the limit', label: '≐', tex: r'\doteq', cls: MClass.rel),
  _symbol(id: 'models', cat: MathCat.sets, name: 'models', label: '⊨', tex: r'\models', cls: MClass.rel, aliases: ['entails', 'satisfies']),
  _symbol(id: 'vdash', cat: MathCat.sets, name: 'proves', label: '⊢', tex: r'\vdash', cls: MClass.rel, aliases: ['turnstile', 'yields']),
  _symbol(id: 'supset', cat: MathCat.sets, name: 'contains', label: '⊃', tex: r'\supset', cls: MClass.rel, aliases: ['superset']),
  _symbol(id: 'supseteq', cat: MathCat.sets, name: 'contains or equals', label: '⊇', tex: r'\supseteq', cls: MClass.rel),
  _symbol(id: 'subsetneq', cat: MathCat.sets, name: 'strictly a subset of', label: '⊊', tex: r'\subsetneq', cls: MClass.rel, aliases: ['proper subset']),
  _symbol(id: 'ni', cat: MathCat.sets, name: 'contains the element', label: '∋', tex: r'\ni', cls: MClass.rel),
  _symbol(id: 'varnothing', cat: MathCat.sets, name: 'the empty set', label: '∅', tex: r'\varnothing', aliases: ['nothing', 'null']),
  _symbol(id: 'aleph', cat: MathCat.sets, name: 'aleph', label: 'ℵ', tex: r'\aleph', aliases: ['cardinality', 'infinity of sets']),
  _symbol(id: 'primes', cat: MathCat.sets, name: 'prime numbers', label: 'ℙ', tex: r'\mathbb{P}', aliases: ['probability']),
  // Arrows.
  _symbol(id: 'uparrow', cat: MathCat.compare, name: 'up arrow', label: '↑', tex: r'\uparrow', cls: MClass.rel),
  _symbol(id: 'downarrow', cat: MathCat.compare, name: 'down arrow', label: '↓', tex: r'\downarrow', cls: MClass.rel),
  _symbol(id: 'longrightarrow', cat: MathCat.compare, name: 'long arrow', label: '⟶', tex: r'\longrightarrow', cls: MClass.rel),
  _symbol(id: 'hookrightarrow', cat: MathCat.compare, name: 'injects into', label: '↪', tex: r'\hookrightarrow', cls: MClass.rel),
  _symbol(id: 'nearrow', cat: MathCat.compare, name: 'increasing', label: '↗', tex: r'\nearrow', cls: MClass.rel, aliases: ['rising']),
  _symbol(id: 'searrow', cat: MathCat.compare, name: 'decreasing', label: '↘', tex: r'\searrow', cls: MClass.rel, aliases: ['falling']),
  // Geometry and measurement.
  _symbol(id: 'measuredangle', cat: MathCat.geometry, name: 'measured angle', label: '∡', tex: r'\measuredangle'),
  _symbol(id: 'square-shape', cat: MathCat.geometry, name: 'square', label: '□', tex: r'\square', aliases: ['quadrilateral']),
  _symbol(id: 'diamond', cat: MathCat.geometry, name: 'diamond', label: '⋄', tex: r'\diamond'),
  // The chip drew ⦜ and inserted ⊥ — the same glyph as 'perpendicular
  // to' two along, so the button's face did not match what it did and the
  // mark it advertised could not be got at all. (Its id was a copy of
  // 'therefore' too.)
  _symbol(id: 'rightangle', cat: MathCat.geometry, name: 'right angle', label: '⌞', tex: r'\llcorner', aliases: ['square corner', '90 degrees']),
  // Physics and stats.
  _symbol(id: 'propto-sci', cat: MathCat.science, name: 'proportional to', label: '∝', tex: r'\propto', cls: MClass.rel),
  _symbol(id: 'ell', cat: MathCat.science, name: 'length', label: 'ℓ', tex: r'\ell'),
  _symbol(id: 'Re', cat: MathCat.science, name: 'real part', label: 'ℜ', tex: r'\Re'),
  _symbol(id: 'Im', cat: MathCat.science, name: 'imaginary part', label: 'ℑ', tex: r'\Im'),
  _symbol(id: 'mho', cat: MathCat.stats, name: 'sample space', label: 'Ω', tex: r'\Omega', aliases: ['omega', 'outcomes']),
  _symbol(id: 'binomial', cat: MathCat.stats, name: 'binomial distribution', label: 'B', tex: 'B', cls: MClass.letter),
  _symbol(id: 'normal', cat: MathCat.stats, name: 'normal distribution', label: 'N', tex: 'N', cls: MClass.letter, aliases: ['gaussian']),
];

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
  ..._negations,
  ..._extras,
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

  // **A symbol answers to its own name.** The table was keyed off `typeIt`
  // alone, and `typeIt` is the SHORTEST route rather than the canonical one —
  // infinity advertises `\oo`, so `\infty`, the name every student who has
  // met LaTeX would reach for, produced nothing at all. Registering the
  // command a symbol actually emits fixes that for every row at once, and the
  // advertised shortcut still wins where the two differ.
  for (final i in mathItems) {
    for (final n in i.build()) {
      if (n is! MSym) continue;
      final m = RegExp(r'^\\([A-Za-z]+)$').firstMatch(n.tex);
      if (m != null) out.putIfAbsent(m.group(1)!, () => i);
    }
  }

  for (final i in mathItems) {
    final t = i.typeIt;
    if (t == null || t.isEmpty) continue;
    final m = RegExp(r'^\\([A-Za-z]+)$').firstMatch(t);
    if (m == null) continue;
    // Keyed WITHOUT the backslash — the editor has already consumed it as its
    // own atom by the time it looks a command up. The advertised route wins
    // over the derived one, which is why this pass runs second.
    out[m.group(1)!] = i;
  }
  // The routes an item answers to but does not advertise. Third pass and
  // `putIfAbsent`, so nothing here can take a word away from an advertised
  // shortcut.
  for (final i in mathItems) {
    for (final t in i.alsoTypeIt) {
      final m = RegExp(r'^\\([A-Za-z0-9]+)$').firstMatch(t);
      if (m != null) out.putIfAbsent(m.group(1)!, () => i);
    }
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
