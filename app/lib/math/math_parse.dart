/// LaTeX → editing tree (plan: v0.18 §8.1).
///
/// Every equation Openote has ever stored is a LaTeX string — typed, pasted,
/// or decoded out of a OneNote file by the Rust importer. The visual editor
/// works on a tree, so this is the door between them.
///
/// **The honesty rule.** This parser knows a bounded set of commands, and it
/// says so when it meets something outside that set instead of guessing.
/// A guess here would be the worst possible failure: the student opens an
/// imported equation, the editor silently drops the half it didn't recognise,
/// and the first keystroke saves the damage. When [parseLatex] reports
/// `ok == false` the block opens in the LaTeX view instead, with the source
/// intact — which is exactly what v0.18 §6.6 promises.
library;

import 'math_inventory.dart';
import 'math_tree.dart';

class MathParseResult {
  const MathParseResult.ok(this.root)
      : supported = true,
        unknown = null;
  const MathParseResult.unsupported(this.unknown) : root = null, supported = false;

  final MRow? root;
  final bool supported;

  /// The command that stopped us, for the "not in the visual editor" notice.
  final String? unknown;
}

/// Commands that are plain symbols — safe to carry as one atom. Built from the
/// inventory (so anything a button can insert can also be re-opened) plus the
/// ones only imports and hand-written LaTeX produce.
final Set<String> _knownSymbols = () {
  final out = <String>{};
  // Whatever the inventory can emit, this can read back — INCLUDING symbols
  // buried in a structure's slots. `\sum` only ever appears as the base of a
  // script, so a top-level-only scan silently refused every summation the app
  // itself had written.
  void collect(MNode n) {
    if (n is MSym && n.tex.startsWith('\\')) out.add(n.tex);
    // `contentSlots`, not `slots`: an n-ary's operator sign lives in a row the
    // caret deliberately cannot enter, so a navigable-only walk drops \sum,
    // \int, \prod and \lim — and the app then refused to re-open equations it
    // had written itself. Same failure as the original top-level-only scan,
    // one level further in.
    for (final slot in n.contentSlots) {
      for (final child in slot.children) {
        collect(child);
      }
    }
  }

  for (final item in mathItems) {
    item.build().forEach(collect);
  }
  out.addAll([
    // Spacing and punctuation the importer and latex_compat emit.
    r'\,', r'\;', r'\:', r'\!', r'\ ', r'\quad', r'\qquad',
    r'\{', r'\}', r'\|', r'\%', r'\&', r'\#', r'\_', r'\$',
    r'\ldots', r'\cdots', r'\vdots', r'\ddots', r'\dots',
    // Relations and operators outside the palette but common in notes.
    r'\ne', r'\le', r'\ge', r'\lneq', r'\gneq', r'\prec', r'\succ',
    r'\subseteq', r'\supseteq', r'\supset', r'\sqsubset',
    r'\uparrow', r'\downarrow', r'\Uparrow', r'\Downarrow',
    r'\longrightarrow', r'\longleftarrow', r'\longleftrightarrow',
    r'\implies', r'\impliedby', r'\iff', r'\gets',
    r'\ast', r'\star', r'\circ', r'\bullet', r'\otimes', r'\ominus',
    r'\wedge', r'\vee', r'\lnot', r'\top', r'\bot',
    r'\aleph', r'\ell', r'\Re', r'\Im', r'\wp', r'\imath', r'\jmath',
    r'\prime', r'\backslash', r'\surd', r'\infty',
    r'\rightarrow', r'\Rightarrow', r'\leftarrow', r'\Leftarrow',
    r'\leftrightarrow', r'\Leftrightarrow', r'\rightleftharpoons',
    r'\epsilon', r'\vartheta', r'\varphi', r'\varsigma', r'\varrho',
    r'\varepsilon', r'\varpi',
    // Style switches that carry no structure of their own.
    r'\displaystyle', r'\textstyle', r'\scriptstyle', r'\limits', r'\nolimits',
  ]);
  return out;
}();

/// Single-argument wrappers that become an accent node.
const _accents = {
  r'\hat', r'\bar', r'\vec', r'\dot', r'\ddot', r'\tilde', r'\overline',
  r'\widehat', r'\widetilde', r'\check', r'\breve', r'\acute', r'\grave',
};

/// Single-argument wrappers we keep verbatim as one atom (`\mathbb{R}`).
const _fontWrappers = {
  r'\mathbb', r'\mathrm', r'\mathbf', r'\mathit', r'\mathcal', r'\mathfrak',
  r'\mathsf', r'\mathtt', r'\boldsymbol', r'\operatorname',
};

const _matrixEnvs = {'pmatrix', 'bmatrix', 'vmatrix', 'Vmatrix', 'Bmatrix', 'matrix', 'cases'};

/// Delimiters `\left`/`\right` accept.
const _delims = {
  '(', ')', '[', ']', '|', '.', '/', '<', '>',
  r'\{', r'\}', r'\|', r'\langle', r'\rangle',
  r'\lvert', r'\rvert', r'\lVert', r'\rVert',
  r'\lfloor', r'\rfloor', r'\lceil', r'\rceil', r'\vert', r'\Vert',
  r'\uparrow', r'\downarrow',
};

MathParseResult parseLatex(String source) {
  final p = _Parser(_strip(source));
  final row = p.parseRow(depth: 0);
  if (p.unknown != null) return MathParseResult.unsupported(p.unknown);
  if (!p.atEnd) return MathParseResult.unsupported(p.rest);
  return MathParseResult.ok(row);
}

/// `$x$` and `$$x$$` still arrive from Markdown-shaped imports, and a stray
/// pair of dollars is not a reason to refuse the whole equation.
String _strip(String s) {
  var t = s.trim();
  for (final d in [r'$$', r'$']) {
    if (t.length > 2 * d.length && t.startsWith(d) && t.endsWith(d)) {
      t = t.substring(d.length, t.length - d.length).trim();
      break;
    }
  }
  return t;
}

MClass classOf(String tex) {
  if (tex.length == 1) {
    final c = tex.codeUnitAt(0);
    if (c >= 48 && c <= 57) return MClass.digit;
    if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122)) return MClass.letter;
    switch (tex) {
      case '+' || '-' || '*' || '/' || '±':
        return MClass.op;
      case '=' || '<' || '>':
        return MClass.rel;
      case '(' || '[':
        return MClass.open;
      case ')' || ']':
        return MClass.close;
    }
    return MClass.other;
  }
  for (final item in mathItems) {
    for (final n in item.build()) {
      if (n is MSym && n.tex == tex) return n.cls;
    }
  }
  return MClass.other;
}

class _Parser {
  _Parser(this.s);

  final String s;
  int i = 0;
  String? unknown;

  bool get atEnd => i >= s.length;
  String get rest => s.substring(i, (i + 12).clamp(0, s.length));

  void _fail(String what) => unknown ??= what;

  /// Parses until a token that belongs to the caller (`}`, `&`, `\\`,
  /// `\right`, `\end`) or the end of the input.
  MRow parseRow({required int depth}) {
    final row = MRow();
    while (!atEnd && unknown == null) {
      final c = s[i];
      if (c == '}' || c == '&') break;
      if (c == r'\' && (_peekCmd() == r'\\' || _peekCmd() == r'\right' || _peekCmd() == r'\end')) {
        break;
      }
      if (depth > 40) {
        _fail('nesting too deep');
        break;
      }
      _parseOne(row, depth);
    }
    return row;
  }

  String _peekCmd() {
    if (s[i] != r'\') return '';
    if (i + 1 < s.length && s[i + 1] == r'\') return r'\\';
    var j = i + 1;
    while (j < s.length && _isAlpha(s.codeUnitAt(j))) {
      j++;
    }
    if (j == i + 1) return s.substring(i, i + 2);
    return s.substring(i, j);
  }

  String _readCmd() {
    final c = _peekCmd();
    i += c.length;
    return c;
  }

  void _skipSpace() {
    while (i < s.length && (s[i] == ' ' || s[i] == '\n' || s[i] == '\t')) {
      i++;
    }
  }

  /// The next `{…}` group, or a single token if the argument is unbraced
  /// (`\frac12` and `x^2` are both legal LaTeX).
  MRow _argument(int depth) {
    _skipSpace();
    if (atEnd) return MRow();
    if (s[i] == '{') {
      i++;
      final r = parseRow(depth: depth + 1);
      if (!atEnd && s[i] == '}') {
        i++;
      } else {
        _fail('unclosed {');
      }
      return r;
    }
    final one = MRow();
    _parseOne(one, depth + 1);
    return one;
  }

  String _rawBraced() {
    _skipSpace();
    if (atEnd || s[i] != '{') return '';
    var d = 0;
    final start = ++i;
    while (i < s.length) {
      if (s[i] == '{') d++;
      if (s[i] == '}') {
        if (d == 0) break;
        d--;
      }
      i++;
    }
    final out = s.substring(start, i);
    if (i < s.length) i++;
    return out;
  }

  String? _readDelimToken() {
    _skipSpace();
    if (atEnd) return null;
    if (s[i] == r'\') {
      final c = _peekCmd();
      if (_delims.contains(c)) {
        i += c.length;
        return c;
      }
      return null;
    }
    final ch = s[i];
    if (_delims.contains(ch)) {
      i++;
      return ch;
    }
    return null;
  }

  void _parseOne(MRow row, int depth) {
    final c = s[i];

    if (c == ' ' || c == '\n' || c == '\t') {
      i++;
      return;
    }
    if (c == '{') {
      // A bare group: its contents join this row. Grouping only ever mattered
      // to the string form, and the tree has real slots instead.
      i++;
      final inner = parseRow(depth: depth + 1);
      if (!atEnd && s[i] == '}') {
        i++;
      } else {
        _fail('unclosed {');
      }
      row.addAll(inner.drain());
      return;
    }
    if (c == '^' || c == '_') {
      i++;
      final content = _argument(depth);
      _attachScript(row, isSup: c == '^', content: content, depth: depth);
      return;
    }
    if (c != r'\') {
      i++;
      row.add(MSym(c, cls: classOf(c)));
      return;
    }

    // A command.
    final cmd = _readCmd();
    switch (cmd) {
      case r'\frac' || r'\dfrac' || r'\tfrac':
        final n = _argument(depth);
        final d = _argument(depth);
        row.add(MFrac(num: n, den: d));
        return;
      case r'\boxed':
        // An answer the app worked out (see [MAnswer]). Reading it back as an
        // answer rather than as ordinary digits is what makes the box, and
        // the decimal/fraction toggle, survive a save and reload.
        //
        // `\boxed` ONLY. `\fbox` was here too and had to go: the tree can
        // only write one of them back, so opening and saving an imported
        // equation silently rewrote the student's `\fbox{a+b}` into
        // `\boxed{a+b}` — the exact "never silently reshaped" rule this
        // parser exists to keep. Unrecognised, it goes to the LaTeX view with
        // its source intact.
        //
        // A `\boxed` a student wrote themselves IS taken as an answer, and
        // that is accepted: the box means the same thing either way, and the
        // only consequence is that a click can rewrite 0.75 as 3/4 — a
        // change of form, never of value, and reversible with a second
        // click.
        row.add(MAnswer(content: _argument(depth)));
        return;
      case r'\binom' || r'\dbinom' || r'\tbinom':
        row.add(MBinom(top: _argument(depth), bottom: _argument(depth)));
        return;
      case r'\sqrt':
        _skipSpace();
        MRow? deg;
        if (!atEnd && s[i] == '[') {
          i++;
          // `]` is an ordinary character to [parseRow] — it would run straight
          // past the degree and off the end of the equation — so the degree is
          // cut out by hand and parsed on its own.
          final close = s.indexOf(']', i);
          if (close < 0) {
            _fail('unclosed [');
            return;
          }
          deg = _Parser(s.substring(i, close)).parseRow(depth: depth + 1);
          i = close + 1;
        }
        row.add(MSqrt(radicand: _argument(depth), degree: deg));
        return;
      case r'\text' || r'\textrm' || r'\textbf' || r'\textit' || r'\mbox':
        row.add(MText(_rawBraced()));
        return;
      case r'\left':
        final left = _readDelimToken();
        if (left == null) {
          _fail(r'\left');
          return;
        }
        final body = parseRow(depth: depth + 1);
        if (_peekCmd() != r'\right') {
          _fail(r'\right');
          return;
        }
        _readCmd();
        final right = _readDelimToken();
        if (right == null) {
          _fail(r'\right');
          return;
        }
        row.add(MDelim(left: left, right: right, body: body));
        return;
      case r'\begin':
        final env = _rawBraced();
        if (!_matrixEnvs.contains(env)) {
          _fail('\\begin{$env}');
          return;
        }
        row.add(_matrix(env, depth));
        return;
      case r'\end':
        _fail(r'\end');
        return;
      default:
        if (_accents.contains(cmd)) {
          row.add(MAccent(cmd: cmd, base: _argument(depth)));
          return;
        }
        if (_fontWrappers.contains(cmd)) {
          final arg = _rawBraced();
          row.add(MSym('$cmd{$arg}',
              cls: cmd == r'\operatorname' ? MClass.func : MClass.letter));
          return;
        }
        if (cmd == r'\not') {
          // `\not` negates whatever follows and the pair is ONE symbol to the
          // inventory (`\not\subset` is ⊄). Splitting them would re-serialise
          // to something that still draws but no longer matches the table.
          final next = _peekCmd();
          if (next.length > 1 && _knownSymbols.contains('$cmd$next')) {
            i += next.length;
            row.add(MSym('$cmd$next', cls: classOf('$cmd$next')));
            return;
          }
        }
        if (_knownSymbols.contains(cmd)) {
          row.add(MSym(cmd, cls: classOf(cmd)));
          return;
        }
        _fail(cmd);
    }
  }

  MNode _matrix(String env, int depth) {
    final rows = <List<MRow>>[];
    var current = <MRow>[];
    while (true) {
      if (unknown != null) break;
      final cell = parseRow(depth: depth + 1);
      current.add(cell);
      _skipSpace();
      if (atEnd) {
        _fail('\\end{$env}');
        break;
      }
      if (s[i] == '&') {
        i++;
        continue;
      }
      final cmd = _peekCmd();
      if (cmd == r'\\') {
        i += 2;
        rows.add(current);
        current = <MRow>[];
        continue;
      }
      if (cmd == r'\end') {
        _readCmd();
        final got = _rawBraced();
        if (got != env) _fail('\\end{$got}');
        rows.add(current);
        break;
      }
      _fail('\\end{$env}');
      break;
    }
    if (rows.isEmpty) rows.add([MRow()]);
    // A trailing `\\` leaves an empty final row; the student didn't ask for it.
    if (rows.length > 1 &&
        rows.last.length == 1 &&
        rows.last.first.isEmpty) {
      rows.removeLast();
    }
    return MMatrix(env: env, cells: rows);
  }

  void _attachScript(MRow row,
      {required bool isSup, required MRow content, required int depth}) {
    MScript target;
    if (row.children.isNotEmpty && row.children.last is MScript) {
      final last = row.children.last as MScript;
      final free = isSup ? last.sup == null : last.sub == null;
      if (free) {
        target = last;
      } else {
        target = MScript(base: MRow([row.removeAt(row.length - 1)]));
        row.add(target);
      }
    } else {
      final base = MRow();
      if (row.children.isNotEmpty) base.add(row.removeAt(row.length - 1));
      target = MScript(base: base);
      row.add(target);
    }
    final slot = isSup ? target.ensureSup() : target.ensureSub();
    slot.addAll(content.drain());
  }
}

bool _isAlpha(int c) =>
    (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
