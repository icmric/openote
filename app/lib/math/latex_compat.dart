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

import 'math_parse.dart';
import 'math_tree.dart';

/// LaTeX that says the same thing, in the dialect the renderer speaks.
String renderableLatex(String tex, {String? answerFill}) {
  var s = tex.trim();
  if (s.isEmpty) return s;
  s = _unwrapDelimiters(s);
  // AFTER the delimiters come off: a wrapped equation would fail the parse
  // and keep its holes.
  s = _withEmptySlotMarkers(s);
  if (answerFill != null) s = _paintAnswerBoxes(s, answerFill);
  s = _rewriteEnvironments(s);
  s = _rewriteControlSequences(s);
  s = _wrapTopLevelBreaks(s);
  s = _groupDelimiterBodies(s);
  return s.trim();
}

/// **A large operator at the END of a `\left…\right` body is not drawn.**
///
/// Not on the list at the top of this file, and narrower than it first looks.
/// Measured against the raw renderer, with this rewrite switched off:
///
/// ```
/// \left( \sum \right)                 FAIL
/// \left( a+\sum \right)               FAIL
/// \left( \frac{1}{2}\sum \right)      FAIL
/// \left( \sum _{x}^{y}\right)         FAIL
/// \left( \lim _{x}\right)             FAIL
/// \left( \sum +a\right)               OK
/// \left( \sum a\right)                OK
/// \left( \sum \frac{1}{2}\right)      OK
/// \left( a+\sum _{x}^{y}+b\right)     OK
/// ```
///
/// So it is not the empty script group, not the limits, and not "an operator
/// inside a grower" — it is an operator, with whatever scripts it carries,
/// being the LAST thing before `\right`. The renderer appears to go looking
/// for the operand an operator should have and find a delimiter instead. One
/// layer of braces round the body is enough to stop it.
///
/// Reachable before this existed — insert a grower from the palette, then a
/// summation inside it — and reachable in **one keystroke** now that
/// highlighting a run and pressing `(` wraps it
/// ([MathEditor.wrapSelection]), which is how it was found.
///
/// ## Why only then, and why the body rather than the operator
///
/// Only then because this must not touch LaTeX that already draws. Bracing
/// every body broke two existing expectations in this file's own tests,
/// including the `cases` rewrite's `\left\{\begin{array}…\right.` — harmless
/// as far as rendering goes, but a rewrite that reaches equations it has no
/// business in is how a compatibility layer becomes the bug.
///
/// The BODY rather than the operator because bracing the operator alone
/// changes spacing: `{\sum _{x}^{y}}` measures pixel-identical on its own but
/// takes `a+\sum _{x}^{y}+b` from **112.2 px to 121.1 px**, since a group is
/// an ordinary atom where an operator is not. A group boundary placed where
/// there is already a delimiter costs nothing, and the ordinary cases
/// measured — `a+b`, `x`, a fraction, square and curly brackets — come out
/// pixel-identical.
///
/// ## Why here and not in `MDelim.texOf`
///
/// Because this fixes equations that are **already written**. The stored form
/// is ordinary LaTeX and stays that way — it is what an importer or another
/// tool reads — and a renderer's shortcoming has no business in it. A
/// notebook written last month gets this too.
String _groupDelimiterBodies(String s) {
  if (!s.contains(r'\left')) return s;
  // Every pair's body gets braces, innermost included: an outer body's
  // braces do not help the `\left` nested inside it.
  final opens = <int>[];
  final marks = <(int, String)>[];
  var i = 0;
  while (i < s.length) {
    if (s.startsWith(r'\left', i)) {
      final after = _afterDelimiter(s, i + 5);
      if (after < 0) return s; // malformed — leave it exactly as it is
      // Past the space the writer put after the delimiter, so the brace
      // reads `\left( {…` rather than `\left({ …`. Cosmetic, and the stored
      // form is read by people.
      var body = after;
      while (body < s.length && s[body] == ' ') {
        body++;
      }
      opens.add(body);
      i = after;
      continue;
    }
    if (s.startsWith(r'\right', i)) {
      final after = _afterDelimiter(s, i + 6);
      if (after < 0 || opens.isEmpty) return s; // malformed or unbalanced
      final open = opens.removeLast();
      // Only the bodies that actually fail. Anything that draws today must
      // come through this function untouched.
      if (_endsWithLargeOperator(s.substring(open, i))) {
        marks
          ..add((open, '{'))
          ..add((i, '}'));
      }
      i = after;
      continue;
    }
    i++;
  }
  // A `\left` with no `\right` is not ours to repair.
  if (opens.isNotEmpty || marks.isEmpty) return s;
  marks.sort((a, b) => b.$1.compareTo(a.$1)); // back to front
  var out = s;
  for (final (at, brace) in marks) {
    out = out.substring(0, at) + brace + out.substring(at);
  }
  return out;
}

/// The large operators — the ones KaTeX sets limits above and below.
///
/// Everything the palette can build, plus the rest of the standard set, so an
/// imported equation is covered as well as a written one. The generated sweep
/// in `math_tex_safety_test.dart` wraps every structure the palette offers and
/// checks it draws, which is what would catch an omission here.
const Set<String> _largeOperators = {
  'sum', 'prod', 'coprod',
  'int', 'iint', 'iiint', 'oint', 'oiint', 'intop', 'smallint',
  'lim', 'liminf', 'limsup', 'injlim', 'projlim',
  'varinjlim', 'varprojlim', 'varliminf', 'varlimsup',
  'bigcup', 'bigcap', 'bigsqcup', 'biguplus',
  'bigvee', 'bigwedge', 'bigodot', 'bigoplus', 'bigotimes',
  'max', 'min', 'sup', 'inf', 'det', 'gcd', 'Pr', 'arg',
};

/// Whether [body] finishes with a large operator and nothing but its own
/// scripts — the shape the renderer cannot draw against a `\right`.
///
/// Read from the END, skipping whitespace and any `_{…}` / `^{…}` the
/// operator carries, because `\sum _{i=1}^{n}` has to count and a regular
/// expression cannot be trusted with the nested braces in `^{n^{2}}`.
bool _endsWithLargeOperator(String body) {
  var i = body.length;
  bool skipSpace() {
    while (i > 0 && body[i - 1] == ' ') {
      i--;
    }
    return true;
  }

  skipSpace();
  // Peel off trailing script groups, innermost brace matching done properly.
  while (i > 0 && body[i - 1] == '}') {
    var depth = 0;
    var j = i;
    while (j > 0) {
      final c = body[j - 1];
      if (c == '}') depth++;
      if (c == '{') {
        depth--;
        if (depth == 0) break;
      }
      j--;
    }
    if (depth != 0 || j < 2) return false; // unbalanced
    final marker = body[j - 2];
    if (marker != '_' && marker != '^') break; // a group, not a script
    i = j - 2;
    skipSpace();
  }
  // What is left must end with one of the commands.
  if (i == 0) return false;
  var k = i;
  while (k > 0 && _isLetter(body.codeUnitAt(k - 1))) {
    k--;
  }
  if (k == i || k == 0 || body[k - 1] != '\\') return false;
  return _largeOperators.contains(body.substring(k, i));
}

/// The index just past the delimiter token that follows `\left` or `\right`.
///
/// One character (`(`, `[`, `|`, `.`, `<`) or a command (`\{`, `\lfloor`,
/// `\langle`, `\vert`). Returns -1 when there is no token at all, which means
/// the LaTeX is malformed and nothing here should touch it.
int _afterDelimiter(String s, int from) {
  var i = from;
  while (i < s.length && s[i] == ' ') {
    i++;
  }
  if (i >= s.length) return -1;
  if (s[i] != '\\') return i + 1;
  var j = i + 1;
  if (j < s.length && !_isLetter(s.codeUnitAt(j))) return j + 1; // `\{`, `\|`
  while (j < s.length && _isLetter(s.codeUnitAt(j))) {
    j++;
  }
  return j == i + 1 ? -1 : j;
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

/// A saved equation with EMPTY slots gets its squares back (v0.18 5.3).
///
/// `\frac{}{2}` is the canonical storage for a half-filled fraction, and TeX
/// draws the empty group as NOTHING - a bar over a hole, in read mode and in
/// the PDF, with no sign anything is unfinished. Re-serialising through the
/// tree with [MathTexCtx.showEmptySlots] puts the same small dim square there
/// that the editor shows. Guarded three ways: only strings that carry an
/// empty group are touched, a parse failure leaves the string exactly as it
/// was (the editor's decorated strings land here too and must pass through),
/// and a small cache keeps the parse off the paint path.
String _withEmptySlotMarkers(String s) {
  if (!s.contains('{}')) return s;
  final hit = _emptySlotCache[s];
  if (hit != null) return hit;
  final r = parseLatex(s);
  // Only strings the tree provably ROUND-TRIPS are transformed. The parser
  // reads the script-separator `{}` as an empty group and drops it, so
  // re-serialising `x^{2}{}^{\circ}` would emit the double superscript the
  // separator exists to prevent - the renderer refuses it and the equation
  // vanishes. Editor-canonical strings round-trip by construction; anything
  // else passes through exactly as it was.
  final out = r.supported &&
          r.root != null &&
          rowToTex(r.root!, kStoreCtx) == s
      ? rowToTex(r.root!, _kEmptySlotCtx)
      : s;
  if (_emptySlotCache.length > 256) _emptySlotCache.clear();
  return _emptySlotCache[s] = out;
}

const MathTexCtx _kEmptySlotCtx = MathTexCtx(showEmptySlots: true);
final Map<String, String> _emptySlotCache = {};

/// Repaint every `\boxed{…}` as a soft filled panel in [fill].
///
/// The owner, on seeing the default: *"rather than the white outline like
/// that, could we maybe do a more subtle grey background?"* `\boxed` draws a
/// RULE in the current colour, which is a hard line; `\fcolorbox` with the same
/// colour for border and fill is a panel with no line at all, and it is the
/// one fill flutter_math actually paints (`\colorbox` lays out and paints
/// nothing — measured, and the reason the caret's own slot chip uses
/// `\fcolorbox` too).
///
/// The colour arrives as an argument rather than living here because STORAGE
/// must stay theme-free: the note holds `\boxed{5}`, which is real LaTeX and
/// exports as a boxed number, and only the renderer — which alone knows
/// whether it is drawing on paper or in the dark — turns it into a grey
/// panel. One rewrite, so read mode, edit mode and print agree.
String _paintAnswerBoxes(String s, String fill) {
  const marker = r'\boxed{';
  if (!s.contains(marker)) return s;
  final out = StringBuffer();
  var i = 0;
  while (i < s.length) {
    final at = s.indexOf(marker, i);
    if (at < 0) {
      out.write(s.substring(i));
      break;
    }
    out.write(s.substring(i, at));
    // Walk the braces, so an answer holding a fraction keeps its own.
    var depth = 1;
    var j = at + marker.length;
    while (j < s.length && depth > 0) {
      if (s[j] == '{') depth++;
      if (s[j] == '}') depth--;
      j++;
    }
    if (depth != 0) {
      // Unbalanced: leave the rest exactly as it came.
      out.write(s.substring(at));
      break;
    }
    final inner = s.substring(at + marker.length, j - 1);
    out.write(r'\fcolorbox{');
    out.write(fill);
    out.write('}{');
    out.write(fill);
    // `\\displaystyle` INSIDE the panel: a `\\$` re-enters maths in TEXT
    // style, which set the answer smaller than the working three
    // characters to its left (measured 37.4px against 53.7px for the same
    // fraction). The selection highlight carries the same token for the
    // same reason.
    out.write('}{\$\\displaystyle ');
    out.write(inner);
    out.write('\$}');
    i = j;
  }
  return out.toString();
}
