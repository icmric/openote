/// Makes ordinary LaTeX renderable by `flutter_math_fork`.
///
/// The renderer is a KaTeX *subset*, and the gaps are not exotic corners — an
/// empirical sweep of 85 constructs (parse + real widget layout) found these
/// failing outright, all of them things a maths student writes every week:
///
///   * `\begin{align}` / `align*` / `split` / `eqnarray` — "No such environment"
///   * `\begin{gather}` / `gathered` / `multline` / `flalign` / `alignat*` — same
///   * `\begin{equation}` — same
///   * a bare `\\` line break outside any environment — parsed, then threw
///     "Unsanitized build exception … Temporary node CrNode encountered" at
///     LAYOUT time, i.e. after the parse said yes
///   * `\smash`, `\mathstrut`, `\href`, `\tag`, `\notag`, `\nonumber`, `\label`
///   * an equation still wrapped in its `$…$`, `$$…$$`, `\[…\]` or `\(…\)`
///     delimiters — which is exactly how equations arrive from an import that
///     writes them into Markdown text
///
/// Every rewrite below maps one of those onto a construct the sweep proved
/// renders (`aligned`, `array`, `\vphantom`, plain braces). `\begin{cases}`
/// itself was never the problem: it renders correctly today, and is covered by
/// a test here so a future dependency bump can't quietly take it away.
///
/// Anything not listed passes through untouched — this must never be the reason
/// a correct equation stops working.
library;

/// LaTeX that says the same thing, in the dialect the renderer speaks.
String renderableLatex(String tex) {
  var s = tex.trim();
  if (s.isEmpty) return s;
  s = _unwrapDelimiters(s);
  s = _rewriteEnvironments(s);
  s = _rewriteControlSequences(s);
  s = _wrapTopLevelBreaks(s);
  return s.trim();
}

/// Strip the maths-mode delimiters. `Math.tex` is already *in* maths mode, so a
/// leading `$` is read as the function `$` and rejected outright ("Can't use
/// function '$' in math mode") — the whole equation is lost over its own
/// punctuation.
String _unwrapDelimiters(String s) {
  for (final (open, close) in const [
    (r'$$', r'$$'),
    (r'\[', r'\]'),
    (r'\(', r'\)'),
    (r'$', r'$'),
  ]) {
    if (s.length > open.length + close.length &&
        s.startsWith(open) &&
        s.endsWith(close)) {
      final inner = s.substring(open.length, s.length - close.length);
      // Only when the delimiters actually wrap the WHOLE thing. `$a$ + $b$`
      // starts and ends with `$` but unwrapping it would splice two separate
      // equations into one malformed string.
      if (!inner.contains(open) && !inner.contains(close)) {
        return _unwrapDelimiters(inner.trim());
      }
    }
  }
  return s;
}

/// Environments the renderer lacks, and the one it has that looks the same.
///
/// Keys carry the closing brace so the starred forms can never be mistaken for
/// the plain ones: `\begin{align*}` and `\begin{align}` are distinct literals,
/// with no regex to get the ordering wrong.
const _envRewrites = <String, String>{
  // Multi-line equations aligned on `&`. `aligned` is the renderer's own
  // spelling of all of these and accepts any number of `&` columns (proved:
  // `a &=& b` lays out).
  'align': 'aligned',
  'align*': 'aligned',
  'split': 'aligned',
  'eqnarray': 'aligned',
  'eqnarray*': 'aligned',
  'flalign': 'aligned',
  'flalign*': 'aligned',
  'alignat': 'alignedat',
  'alignat*': 'alignedat',
  // Centred rows, no alignment column. `gathered` is present in the package
  // source but commented out, so it fails like the rest; `array` with a
  // centred column spec is the working equivalent.
  'gather': 'array{c}',
  'gather*': 'array{c}',
  'gathered': 'array{c}',
  'multline': 'array{c}',
  'multline*': 'array{c}',
  // A wrapper that only ever meant "this is a numbered display equation".
  // There is no numbering here, so the wrapper is pure noise.
  'equation': '',
  'equation*': '',
  'displaymath': '',
  'math': '',
};

String _rewriteEnvironments(String s) {
  var out = s;
  for (final e in _envRewrites.entries) {
    final target = e.value;
    if (target.isEmpty) {
      out = out
          .replaceAll('\\begin{${e.key}}', '')
          .replaceAll('\\end{${e.key}}', '');
      continue;
    }
    // `array{c}` means the environment `array` plus its required column
    // argument; `\end` must name only the environment or the parser reports a
    // mismatch ("\begin{darray} matched by \end{array}").
    final brace = target.indexOf('{');
    final name = brace < 0 ? target : target.substring(0, brace);
    final args = brace < 0 ? '' : target.substring(brace);
    out = out
        .replaceAll('\\begin{${e.key}}', '\\begin{$name}$args')
        .replaceAll('\\end{${e.key}}', '\\end{$name}');
  }
  return out;
}

String _rewriteControlSequences(String s) {
  var out = s;
  // Numbering and cross-referencing commands. Nothing in a note is numbered,
  // so the honest rendering of `\nonumber` is nothing at all — far better than
  // losing the whole equation to "Undefined control sequence".
  //
  // The lookahead is what stops this from eating the front of a longer name: a
  // TeX control word runs to the first non-letter, and `\newcommand` DOES work
  // in this renderer, so `\notagline` is a name a user can really define.
  for (final dead in const ['notag', 'nonumber']) {
    out = out.replaceAll(RegExp('\\\\$dead(?![a-zA-Z])'), '');
  }
  out = _dropCall(out, r'\label');
  // A strut is an invisible spacer. `\vphantom{(}` is the renderer's supported
  // way to say the same height-without-ink.
  out = out.replaceAll(r'\mathstrut', r'\vphantom{(}');
  // `\smash{x}` prints x with its height ignored; without vertical-spacing
  // control the honest approximation is x itself.
  out = _unwrapCall(out, r'\smash', keepArg: 0, argCount: 1);
  // `\href{url}{label}` — a PDF or a note page has nowhere to click, so keep
  // the label and drop the address.
  out = _unwrapCall(out, r'\href', keepArg: 1, argCount: 2);
  // `\tag{1}` labels a display equation. Show the label rather than lose the
  // equation to it.
  out = _unwrapCall(out, r'\tag', keepArg: 0, argCount: 1, wrap: r'\quad\text');
  return out;
}

/// Delete `name{…}` entirely, argument included.
String _dropCall(String s, String name) =>
    _unwrapCall(s, name, keepArg: -1, argCount: 1);

/// Replace `name{a}{b}…` with the [keepArg]-th argument (or nothing when
/// [keepArg] is negative), optionally re-wrapped in [wrap].
String _unwrapCall(String s, String name,
    {required int keepArg, required int argCount, String? wrap}) {
  var out = s;
  var from = 0;
  while (true) {
    final i = out.indexOf(name, from);
    if (i < 0) return out;
    final after = i + name.length;
    // No control-word boundary check is needed here: `\tagged{x}` puts a
    // letter where an argument brace must be, so the argument scan below
    // rejects it and the text is left alone. (Pinned by a test — the same
    // guarantee, without a second rule that could disagree with the first.)
    //
    // An optional `[…]` argument (`\smash[t]{x}`) sits before the braces.
    var cursor = _skipSpace(out, after);
    if (cursor < out.length && out[cursor] == '[') {
      final close = out.indexOf(']', cursor);
      if (close < 0) return out;
      cursor = _skipSpace(out, close + 1);
    }
    final args = <String>[];
    for (var a = 0; a < argCount; a++) {
      if (cursor >= out.length || out[cursor] != '{') break;
      final end = _matchBrace(out, cursor);
      if (end < 0) break;
      args.add(out.substring(cursor + 1, end));
      cursor = _skipSpace(out, end + 1);
    }
    if (args.length < argCount) {
      // Malformed — leave it alone and let the fallback show the source, which
      // is more use to the reader than a half-applied rewrite.
      from = after;
      continue;
    }
    final kept = keepArg < 0 ? '' : '{${args[keepArg]}}';
    out = out.replaceRange(i, cursor, kept.isEmpty ? '' : '${wrap ?? ''}$kept');
    from = i;
  }
}

/// A `\\` outside every environment parses, then throws at layout time. Wrapping
/// the expression in a centred `array` gives those rows somewhere to live —
/// which is what the author meant by writing a line break in the first place.
String _wrapTopLevelBreaks(String s) =>
    _hasTopLevelBreak(s) ? '\\begin{array}{c}$s\\end{array}' : s;

bool _hasTopLevelBreak(String s) {
  var brace = 0;
  var env = 0;
  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (c == r'\') {
      if (i + 1 < s.length && s[i + 1] == r'\') {
        if (brace == 0 && env == 0) return true;
        i += 2;
        continue;
      }
      // Consume the control word so `\begin`/`\end` are counted and an escaped
      // brace (`\left\{`) never disturbs the brace depth.
      var j = i + 1;
      while (j < s.length && _isLetter(s.codeUnitAt(j))) {
        j++;
      }
      final word = s.substring(i + 1, j);
      if (word == 'begin') env++;
      if (word == 'end') env--;
      i = j == i + 1 ? i + 2 : j;
      continue;
    }
    if (c == '{') brace++;
    if (c == '}') brace--;
    i++;
  }
  return false;
}

int _matchBrace(String s, int openIdx) {
  var depth = 0;
  for (var k = openIdx; k < s.length; k++) {
    if (s[k] == r'\') {
      k++; // an escaped `\{` is content, not nesting
      continue;
    }
    if (s[k] == '{') depth++;
    if (s[k] == '}') {
      depth--;
      if (depth == 0) return k;
    }
  }
  return -1;
}

int _skipSpace(String s, int i) {
  var k = i;
  while (k < s.length && (s[k] == ' ' || s[k] == '\n' || s[k] == '\t')) {
    k++;
  }
  return k;
}

bool _isLetter(int c) =>
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

/// What to tell a student when an equation still can't be drawn.
///
/// Never the raw exception: "Parser Error: Undefined control sequence:
/// \sideset" tells a 15-year-old nothing except that something is broken. The
/// point of the message is to say the maths is SAFE and only the picture is
/// missing, so nobody retypes an equation that was stored perfectly.
String mathDisplayProblem(Object error) {
  final raw = error is Exception ? error.toString() : '$error';
  final message = _errorMessage(error) ?? raw;

  final env = RegExp(r'No such environment:\s*(\S+)').firstMatch(message);
  if (env != null) {
    return "Openote can't lay this equation out as “${env.group(1)}” yet. "
        'The maths below is saved exactly as it was written.';
  }
  final cmd =
      RegExp(r'Undefined control sequence:\s*(\\?\S+)').firstMatch(message);
  if (cmd != null) {
    return "Openote doesn't know the command ${cmd.group(1)} yet. "
        'The maths below is saved exactly as it was written.';
  }
  return "Openote can't draw this equation yet. "
      'The maths below is saved exactly as it was written.';
}

String? _errorMessage(Object error) {
  try {
    // FlutterMathException, without importing the widget layer into a file
    // that is otherwise pure Dart and testable without a binding.
    return (error as dynamic).message as String?;
  } catch (_) {
    return null;
  }
}
