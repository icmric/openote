/// **Plugging values into a formula.**
///
/// The reading a substitute block does, which until now was borrowed whole
/// from the grapher: `substituteInto(graphSourceFromLatex(latex), value)`.
/// Sharing it had one real virtue — a block and its sibling graph agreed
/// about what counted as one equation, right down to the error messages —
/// and one fatal consequence, which is that a `GraphSource` is a CURVE. A
/// curve is a function of one variable by definition, so everything a
/// student actually wants to substitute into was refused:
///
/// ```
/// F=m*a            -> unknown "m"
/// v=u+a*t          -> unknown "u"
/// A=l*w            -> unknown "l"
/// c=sqrt(a^2+b^2)  -> unknown "a"
/// ```
///
/// Measured, not guessed — and `y=3T+1` was refused too, despite a doc
/// comment claiming it read `T`. Nothing but `x` worked. The owner's report:
/// *"its unable to handle multi variable stuff at the moment."*
///
/// So the formula case gets its own reading. [CompiledFormula] is what makes
/// it possible: it finds its own names rather than being told one.
///
/// ## What it keeps from the grapher
///
/// The shape of an equation, and the words. `y = 3x + 10` names its answer
/// `y` and its formula is the right-hand side; a bare `3x + 10` is all
/// formula and names nothing. That is the same split [graphSourceFromLinear]
/// makes, and a `\frac` still reaches the calculator by the same
/// `parseLatex` → `rowToLinear` road.
///
/// What it does NOT do is rearrange. `2y = 6x + 4` is solved for y when it is
/// being GRAPHED, because rearranging is the topic that feature was built
/// for; substituting into it is a different question with a different answer
/// (what is y, or what is 2y?) and guessing would be worse than asking. It
/// is refused in words.
library;

import 'evaluate.dart';
import 'math_linear_projection.dart';
import 'math_parse.dart';

/// An equation read as something to put values into.
class SubstituteSource {
  const SubstituteSource.ok(this.formula, {this.resultName})
      : error = null,
        isOk = true;
  const SubstituteSource.failed(this.error)
      : formula = null,
        resultName = null,
        isOk = false;

  final CompiledFormula? formula;

  /// The name on the left of the equals sign — `y` in `y = 3x + 10`, `F` in
  /// `F = m*a` — or null for a bare expression, which names nothing.
  ///
  /// Shown beside the answer, and the point of carrying it at all: the owner
  /// on the old display, which was a bare `= 23`, *"ensure the answer is
  /// clear, as at the moment its not super clear to me."* `F = 23` says what
  /// the 23 IS.
  final String? resultName;

  final String? error;
  final bool isOk;

  /// Every name needing a value, in the order they are written.
  List<String> get variables => formula?.variables ?? const [];
}

/// Read [latex] as a formula to put values into.
SubstituteSource substituteSourceFromLatex(String latex) {
  final t = latex.trim();
  if (t.isEmpty) return const SubstituteSource.failed('nothing to work out yet');
  final parsed = parseLatex(t);
  if (!parsed.supported || parsed.root == null) {
    return const SubstituteSource.failed(
        'this equation uses something the calculator cannot read yet');
  }
  return substituteSourceFromLinear(rowToLinear(parsed.root!).trim());
}

/// The same reading, from the linear form the calculator speaks.
SubstituteSource substituteSourceFromLinear(String linear) {
  final t = linear.trim();
  if (t.isEmpty) return const SubstituteSource.failed('nothing to work out yet');
  final eq = t.indexOf('=');
  if (eq < 0) {
    final f = compileFormula(t);
    return f.isOk
        ? SubstituteSource.ok(f)
        : SubstituteSource.failed(f.error);
  }
  final left = t.substring(0, eq).trim();
  final right = t.substring(eq + 1).trim();
  if (right.contains('=')) {
    return const SubstituteSource.failed('one equals sign, please');
  }
  if (right.isEmpty) {
    return const SubstituteSource.failed('nothing to work out yet');
  }
  // A NAME on the left is what the answer is called. Only a name: `2y` is y
  // doubled, and treating it as a label would answer a question nobody
  // asked — the same rule, and the same reason, as the grapher's.
  final isName = RegExp(r'^[A-Za-z][A-Za-z0-9]*$').hasMatch(left) ||
      RegExp(r'^[A-Za-z][A-Za-z0-9]*\s*\(\s*[A-Za-z0-9,\s]*\s*\)$')
          .hasMatch(left);
  if (!isName) {
    return const SubstituteSource.failed(
        'rearrange it so one name is on the left before putting values in');
  }
  final f = compileFormula(right);
  if (!f.isOk) return SubstituteSource.failed(f.error);
  // `f(x)` and `s(u,t)` name their answer f and s — the brackets list what
  // goes IN, which the formula has already worked out for itself.
  final name = left.split('(').first.trim();
  return SubstituteSource.ok(f, resultName: name);
}

/// The answer to a substitution, or what is still needed for one.
class SubstituteAnswer {
  const SubstituteAnswer({
    required this.missing,
    required this.result,
    this.resultName,
  });

  /// Names with nothing typed in for them yet, in the order they are asked
  /// for. Non-empty means there is no answer YET, which is a different thing
  /// from a formula that cannot be read — and it is the common case, because
  /// a block with three fields spends most of its life partly filled.
  final List<String> missing;

  /// The answer, once every name has a value. Null while [missing] is not
  /// empty.
  final EvalResult? result;

  /// What the answer is called, from [SubstituteSource.resultName].
  final String? resultName;
}

/// **What a substitute block's `content` says the student typed.**
///
/// Reads both spellings. `values` is a map keyed by variable name, written
/// from v1.0.2; `value` was a single string, because a substitute block could
/// only ever have had one field. An older notebook's `value` belongs to the
/// first name [variables] asks for, because that is the only name it could
/// have been.
///
/// Read-only, on purpose: nothing rewrites `value` into `values` behind the
/// student's back. Opening a notebook is not editing it, and leaving the old
/// key alone means a v1.0.1 build opening the same notebook still shows the
/// number — the same two-spelling rule the `.blob` migration follows. The map
/// is written the moment a field is touched, which is also the moment the old
/// spelling stops being the truth.
Map<String, String> storedValues(
    Map<String, dynamic> content, List<String> variables) {
  final raw = content['values'];
  if (raw is Map && raw.isNotEmpty) {
    return {for (final e in raw.entries) '${e.key}': '${e.value}'};
  }
  final old = (content['value'] as String? ?? '').trim();
  if (old.isNotEmpty && variables.isNotEmpty) return {variables.first: old};
  return {};
}

/// **A substitute block in one line, for the exporters.**
///
/// Four of them print this — Markdown, two paths through the `.open` bundle,
/// and the PDF — and each used to build it from `outcome.variable` and the
/// one typed string. With several names that line has to list them, so it is
/// built once here rather than in four places that would have to be found
/// again next time.
///
/// Null when there is nothing to say yet, which is every exporter's cue to
/// print the equation alone, exactly as they already do.
///
/// [given] reads `u = 2, a = 3, t = 4`, in the order the formula asks; a
/// name still blank is simply left out, so a half-filled block exports what
/// it actually has rather than nothing at all.
({String given, String answer})? substituteProjection(
    Map<String, dynamic> content) {
  final latex = (content['latex'] as String? ?? '').trim();
  if (latex.isEmpty) return null;
  final source = substituteSourceFromLatex(latex);
  final values = storedValues(content, source.variables);
  final given = <String>[];
  for (final name in source.variables) {
    final text = values[name]?.trim() ?? '';
    if (text.isNotEmpty) given.add('$name = $text');
  }
  if (given.isEmpty) return null;
  final answer = answerFor(source, values);
  return (
    given: given.join(', '),
    answer: answer.result?.display ??
        // Some names filled and some not. Saying which are missing is more
        // use to a reader than an empty space where a number should be.
        'needs ${answer.missing.join(', ')}',
  );
}

/// Work [source] out from what the student has typed so far.
///
/// [typed] is keyed by variable name, and each value is run through
/// [evaluateLinear] rather than `double.parse` — so `2+3`, `pi` and `1/2`
/// work as inputs, the same as any other number anywhere in this app. A name
/// typed as blank counts as not yet given.
SubstituteAnswer answerFor(SubstituteSource source, Map<String, String> typed) {
  if (!source.isOk) {
    return SubstituteAnswer(
        missing: const [], result: EvalResult.err(source.error!));
  }
  final formula = source.formula!;
  final values = <String, double>{};
  final missing = <String>[];
  for (final name in formula.variables) {
    final text = typed[name]?.trim() ?? '';
    if (text.isEmpty) {
      missing.add(name);
      continue;
    }
    final v = evaluateLinear(text);
    if (!v.isOk) {
      // The bad field is named, because with several of them "not a number"
      // on its own leaves the student hunting for which one.
      return SubstituteAnswer(
          missing: const [],
          resultName: source.resultName,
          result: EvalResult.err('$name: ${v.error}'));
    }
    values[name] = v.value;
  }
  if (missing.isNotEmpty) {
    return SubstituteAnswer(
        missing: missing, result: null, resultName: source.resultName);
  }
  return SubstituteAnswer(
    missing: const [],
    resultName: source.resultName,
    result: EvalResult.ok(formula.call!(values)),
  );
}
