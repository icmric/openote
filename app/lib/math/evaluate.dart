/// Numeric evaluation of the linear-math input (the "compute" half of MATH-7).
///
/// **Why this exists, in one line:** OneNote charges a Microsoft 365 Education
/// subscription for math answers. We own the input grammar end to end, so
/// evaluating what the student typed costs us a few hundred lines and is free
/// forever.
///
/// Deliberately a **calculator, not a CAS**: arithmetic, powers, roots, trig,
/// logs, factorials, constants, and a few common functions. No symbolic
/// algebra, no step-by-step, no equation solving — those are a genuinely deep
/// well (Vision §9 keeps "a math solver" as a non-goal), and this is the
/// honest 80% for a first-year problem set at a fraction of the cost.
///
/// Operates on the **linear source** the user typed (`2+3*4`, `sqrt(16)`,
/// `sin(pi/2)`), not the LaTeX projection: the linear form is unambiguous and
/// already parsed by the same grammar the renderer uses.
library;

import 'dart:math' as math;

/// What an answer *is*, when it can only be one thing.
///
/// The owner: *"give units when it could only be that unit, like with
/// deg/rad"*. An inverse trig function hands back an ANGLE, and an angle with
/// no unit on it is ambiguous the moment the mode is switched -- 30 and
/// 0.5236 are the same answer written two ways, and nothing on the page says
/// which. Everything else is [EvalUnit.none]: a ratio, a length, a count.
/// `sin 30` is 0.5, and 0.5 of nothing in particular.
enum EvalUnit { none, degrees, radians }

/// The significant figures an answer carries when nobody has said otherwise.
///
/// Ten, which is what a Casio fx-82 shows. It used to be twelve, and twelve
/// is enough to leak the floating point underneath: `cos 45` came back as
/// `0.707106781187`, where the calculator on the desk beside it says
/// `0.7071067812`.
const int kDefaultSigFigs = 10;

/// The result of evaluating an expression, or why it couldn't be.
class EvalResult {
  const EvalResult.ok(this.value, {this.unit = EvalUnit.none})
      : error = null,
        isOk = true;
  const EvalResult.err(this.error)
      : value = 0,
        unit = EvalUnit.none,
        isOk = false;

  final double value;
  final String? error;
  final bool isOk;

  /// What the answer is, when it can only be one thing. See [EvalUnit].
  final EvalUnit unit;

  /// A human-facing rendering: integers without a decimal point, everything
  /// else trimmed of trailing zeros. `0.1+0.2` should read `0.3`, not
  /// `0.30000000000000004` — binary floating point is not the student's
  /// problem.
  String get display => _write(kDefaultSigFigs, pad: false);

  /// The answer at exactly [figures] significant figures, trailing zeros and
  /// all -- `0.500`, not `0.5`.
  ///
  /// The zeros are not decoration. They are how a calculator says "three
  /// figures", and they are how this app remembers the student's choice: the
  /// digits ARE the setting, so a 3 s.f. answer survives being saved, closed
  /// and reopened without a scrap of metadata riding alongside it.
  String displayAt(int figures) => _write(figures, pad: true);

  String _write(int figures, {required bool pad}) {
    if (!isOk) return error ?? 'error';
    if (value.isNaN) return 'undefined';
    // **Zero reads as zero.** `sin(180)` lands on 1.22e-16 and `cos(90)` on
    // 6.1e-17 — the answer is nought, and a student shown
    // "1.22464679915e-16" has been handed floating point as if it were
    // maths. Every school calculator does this, and the cost is that a real
    // answer below a millionth of a millionth is called zero, which is not a
    // number a notebook calculator is asked for.
    if (value != 0 && value.abs() < 1e-12) return '0';
    if (value.isInfinite) return value.isNegative ? '-∞' : '∞';
    final f = figures.clamp(1, 15);
    var s = value.toStringAsPrecision(f);
    if (s.contains('e')) {
      // Far too big or far too small to write out. The mantissa is trimmed
      // either way -- `6.02000000000e+23` is noise, not precision.
      final at = s.indexOf('e');
      var m = s.substring(0, at);
      if (m.contains('.') && !pad) {
        m = m.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
      }
      return m + s.substring(at);
    }
    if (!pad) {
      // A whole number reads as a whole number: `4`, never `4.000000000`.
      final rounded = double.parse(s);
      if (rounded == rounded.roundToDouble() && rounded.abs() < 1e15) {
        return rounded.toStringAsFixed(0);
      }
      if (s.contains('.')) {
        s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
      }
    }
    return s;
  }

  @override
  String toString() => isOk ? display : 'error: $error';
}

/// Evaluate a linear-math expression.
///
/// Returns an error result rather than throwing: this runs while the user is
/// typing, and half-written input is the normal case, not an exception.
EvalResult evaluateLinear(String input) {
  final src = input.trim();
  if (src.isEmpty) return const EvalResult.err('empty');
  // An equation, not an expression — we evaluate, we don't solve.
  if (src.contains('=')) {
    return const EvalResult.err('not an expression');
  }
  try {
    final p = _Parser(src);
    final expr = p.parseExpression();
    p.skipSpace();
    if (!p.atEnd) return EvalResult.err('unexpected "${p.rest}"');
    return EvalResult.ok(
      expr(const <String, double>{}),
      unit: !p.angleOut
          ? EvalUnit.none
          : mathAngleMode == AngleMode.degrees
              ? EvalUnit.degrees
              : EvalUnit.radians,
    );
  } on _EvalError catch (e) {
    return EvalResult.err(e.message);
  } catch (_) {
    return const EvalResult.err('could not evaluate');
  }
}

/// A compiled expression. Give it the variables it needs, get a number.
///
/// **Why the grammar builds one of these rather than a number.** A curve is
/// several hundred samples, redrawn on every keystroke because the owner
/// asked for exactly that: *"it would be cool to see the graph change as i
/// type."* Parsing the source once per sample was measured at 33 times the
/// cost of calling a closure — most of a frame for a single curve — so the
/// parse happens once and the closure is what the painter calls.
///
/// It costs the calculator nothing: [evaluateLinear] builds the same closure
/// and calls it once with no variables bound.
typedef MathExpr = double Function(Map<String, double> vars);

/// A function of one variable, ready to plot, or the reason there isn't one.
class CompiledMath {
  const CompiledMath.ok(this.at, {required this.variable})
      : error = null,
        isOk = true;
  const CompiledMath.err(this.error)
      : at = null,
        variable = 'x',
        isOk = false;

  /// The value at a point. Returns NaN where the curve has no value there —
  /// a gap the painter simply does not draw through, which is the honest
  /// picture of `1/x` at zero and of `sqrt(x)` to the left of it.
  final double Function(double)? at;

  /// The name the curve is a function OF.
  final String variable;

  final String? error;
  final bool isOk;
}

/// Compile `3x + 10` (or the right-hand side of `y = 3x + 10`) into something
/// a painter can call several hundred times without noticing.
///
/// [variable] is bound on every call; every OTHER name still has to be
/// something the calculator knows, so `3x + c` is refused with `unknown "c"`
/// rather than silently drawing the curve for c = 0.
CompiledMath compileFunction(String input, {String variable = 'x'}) {
  final src = input.trim();
  if (src.isEmpty) return const CompiledMath.err('empty');
  if (src.contains('=')) {
    return const CompiledMath.err('give me one side of the equals sign');
  }
  final MathExpr expr;
  try {
    final p = _Parser(src);
    expr = p.parseExpression();
    p.skipSpace();
    if (!p.atEnd) return CompiledMath.err('unexpected "${p.rest}"');
  } on _EvalError catch (e) {
    return CompiledMath.err(e.message);
  } catch (_) {
    return const CompiledMath.err('could not read that');
  }

  final vars = <String, double>{variable: 0};
  double at(double x) {
    vars[variable] = x;
    try {
      return expr(vars);
    } on _EvalError {
      // A factorial of a half, a log of a negative: no value HERE, which is
      // a gap in the curve rather than a failure of the whole thing.
      return double.nan;
    } catch (_) {
      return double.nan;
    }
  }

  // **Ask it a question before promising it works.** A name the calculator
  // has never heard of only complains when it is reached, so an expression
  // like `3z + 1` would compile happily and then draw nothing at all. Three
  // probes, and the message the student gets is the one the calculator would
  // have given them.
  try {
    for (final probe in const [0.0, 1.0, -1.0]) {
      vars[variable] = probe;
      expr(vars);
    }
  } on _EvalError catch (e) {
    if (e.message.startsWith('unknown')) return CompiledMath.err(e.message);
  } catch (_) {
    // Anything else is a gap at those particular points, not a refusal.
  }
  return CompiledMath.ok(at, variable: variable);
}

class _EvalError implements Exception {
  _EvalError(this.message);
  final String message;
}

/// Recursive-descent parser over the linear grammar's numeric subset.
///
/// Precedence, lowest first: `+ -` · `* / × ÷ ·` and implicit multiplication ·
/// unary `-` · `^` (right-associative) · postfix `!` · atoms.
class _Parser {
  _Parser(this.s);
  final String s;
  int i = 0;

  /// True when the value just produced is an ANGLE -- an inverse trig result,
  /// with nothing done to it since that would make it something else.
  ///
  /// Deliberately narrow. `asin(0.5)` is an angle; `asin(0.5)+1` is a number
  /// with an angle somewhere in its past, and labelling that "degrees" would
  /// be a guess. Every operation that combines two values clears it; a minus
  /// sign and a bracket do not, because neither changes what the thing IS.
  bool angleOut = false;

  bool get atEnd => i >= s.length;
  String get rest => s.substring(i);

  void skipSpace() {
    while (i < s.length && (s[i] == ' ' || s[i] == '\t')) {
      i++;
    }
  }

  bool _eat(String token) {
    skipSpace();
    if (s.startsWith(token, i)) {
      i += token.length;
      return true;
    }
    return false;
  }

  MathExpr parseExpression() {
    var left = _parseTerm();
    while (true) {
      skipSpace();
      if (_eat('+')) {
        final l = left, r = _parseTerm();
        left = (v) => l(v) + r(v);
        angleOut = false;
      } else if (_eat('−') || _eat('-')) {
        final l = left, r = _parseTerm();
        left = (v) => l(v) - r(v);
        angleOut = false;
      } else {
        return left;
      }
    }
  }

  MathExpr _parseTerm() {
    var left = _parseUnary();
    while (true) {
      skipSpace();
      if (_eat('*') || _eat('×') || _eat('·')) {
        final l = left, r = _parseUnary();
        left = (v) => l(v) * r(v);
        angleOut = false;
      } else if (_eat('/') || _eat('÷')) {
        final l = left, r = _parseUnary();
        // ±∞ / NaN are reported by [EvalResult.display]
        left = (v) => l(v) / r(v);
        angleOut = false;
      } else if (_eatWord('mod')) {
        // **A remainder, written between its two numbers**, which is how a
        // textbook writes it and what the palette's button inserts. Binds
        // like a multiplication, so `10 + 17 mod 5` is 10 + (17 mod 5) = 12.
        final l = left, r = _parseUnary();
        left = (v) {
          final a = l(v), b = r(v);
          return a - b * (a / b).floorToDouble();
        };
        angleOut = false;
      } else if (_startsImplicitProduct()) {
        // `2pi`, `3(x+1)`, `2sqrt(9)` — the way people actually write maths.
        final l = left, r = _parseUnary();
        left = (v) => l(v) * r(v);
        angleOut = false;
      } else {
        return left;
      }
    }
  }

  /// An operator spelled as a WORD, taken only when the whole word is there:
  /// `mod` in `17 mod 5`, never the `mod` at the front of a variable called
  /// `mode`.
  bool _eatWord(String word) {
    skipSpace();
    if (!s.startsWith(word, i)) return false;
    final after = i + word.length;
    if (after < s.length && _isLetter(s[after])) return false;
    i = after;
    return true;
  }

  /// True when the next token can only continue a product: a name, an opening
  /// bracket, or a constant. Deliberately NOT a digit — `2 3` is a typo, and
  /// silently reading it as 6 would hide it.
  bool _startsImplicitProduct() {
    skipSpace();
    if (atEnd) return false;
    final c = s[i];
    return c == '(' || _isLetter(c);
  }

  MathExpr _parseUnary() {
    skipSpace();
    if (_eat('-') || _eat('−')) {
      final r = _parseUnary();
      return (v) => -r(v);
    }
    if (_eat('+')) return _parseUnary();
    return _parsePower();
  }

  MathExpr _parsePower() {
    final base = _parsePostfix();
    skipSpace();
    if (_eat('^')) {
      // Right-associative: 2^3^2 is 2^(3^2) = 512.
      final exp = _parseUnary();
      angleOut = false;
      return (v) => _power(base(v), exp(v));
    }
    return base;
  }

  MathExpr _parsePostfix() {
    var v = _parseAtom();
    while (true) {
      skipSpace();
      if (i < s.length && s[i] == '!') {
        i++;
        angleOut = false;
        final inner = v;
        v = (e) => _factorial(inner(e));
      } else if (i < s.length && s[i] == '%') {
        // **A per cent, not a remainder.** `%` was an infix modulo, so a
        // student writing `25% of 80` got either an error or — worse, and
        // silently — `20 % 3 = 2`. Per cent is a year-7 operation on this
        // palette; the remainder is not on it at all.
        i++;
        angleOut = false;
        final inner = v;
        v = (e) => inner(e) / 100;
      } else if (i < s.length && s[i] == '°') {
        // `30°` IS an angle in degrees, whatever the surrounding rule — the
        // student said so. Converted here, once, so everything downstream
        // works in radians as the maths library does.
        i++;
        final inner = v;
        v = (e) => inner(e) * math.pi / 180;
      } else {
        return v;
      }
    }
  }

  MathExpr _parseAtom() {
    skipSpace();
    if (atEnd) throw _EvalError('unexpected end');

    if (_eat('(')) {
      final v = parseExpression();
      if (!_eat(')')) throw _EvalError('missing )');
      return v;
    }
    // |x| absolute value.
    if (_eat('|')) {
      final v = parseExpression();
      if (!_eat('|')) throw _EvalError('missing |');
      angleOut = false;
      return (e) => v(e).abs();
    }
    if (_eat('√')) {
      angleOut = false;
      final v = _parseUnary();
      return (e) => math.sqrt(v(e));
    }

    final c = s[i];
    if (_isDigit(c) || c == '.') return _parseNumber();
    if (_isLetter(c)) return _parseNameOrCall();
    throw _EvalError('unexpected "$c"');
  }

  MathExpr _parseNumber() {
    final start = i;
    while (i < s.length && (_isDigit(s[i]) || s[i] == '.')) {
      i++;
    }
    // Exponent form: 1e-3, 2.5E6.
    if (i < s.length && (s[i] == 'e' || s[i] == 'E')) {
      final save = i;
      i++;
      if (i < s.length && (s[i] == '+' || s[i] == '-')) i++;
      if (i < s.length && _isDigit(s[i])) {
        while (i < s.length && _isDigit(s[i])) {
          i++;
        }
      } else {
        i = save; // `2e` is 2 × e, not a malformed exponent
      }
    }
    final v = double.tryParse(s.substring(start, i));
    if (v == null) throw _EvalError('bad number "${s.substring(start, i)}"');
    angleOut = false;
    return (_) => v;
  }

  MathExpr _parseNameOrCall() {
    final start = i;
    while (i < s.length && (_isLetter(s[i]) || _isDigit(s[i]))) {
      i++;
    }
    final name = s.substring(start, i).toLowerCase();

    // Constant?
    final k = _constants[name];
    if (k != null) {
      angleOut = false;
      return (_) => k;
    }

    skipSpace();

    // **A function that needs more than one thing.** `gcd(12, 18)`,
    // `mod(7, 3)`, `nCr(5, 2)`. Commas exist in the grammar only here: an
    // argument list is the one place in school maths where a comma separates
    // two numbers rather than grouping the digits of one.
    final many = _callFunctions[name];
    if (many != null) {
      if (atEnd || s[i] != '(') {
        throw _EvalError('$name needs brackets: $name(a, b)');
      }
      i++;
      final parts = <MathExpr>[parseExpression()];
      skipSpace();
      while (!atEnd && s[i] == ',') {
        i++;
        parts.add(parseExpression());
        skipSpace();
      }
      if (!_eat(')')) throw _EvalError('missing )');
      if (parts.length < many.min) {
        throw _EvalError('$name needs ${many.min} numbers');
      }
      angleOut = false;
      final run = many.run;
      return (v) => run([for (final p in parts) p(v)]);
    }

    // A log to an explicit base: `log2(8)`, `log10(100)`, `log5(125)`.
    // Written as the name plus the base, which is what the subscript form
    // projects to — and what a Casio prints as log₅(125).
    final based = RegExp(r'^log([0-9]+)$').firstMatch(name);
    if (based != null) {
      final b = double.parse(based.group(1)!);
      if (b <= 0 || b == 1) throw _EvalError('a log needs a base above 1');
      final inner = _readOneArgument();
      angleOut = false;
      final lnb = math.log(b);
      return (v) => math.log(inner(v)) / lnb;
    }

    // Function call: name(...) or name x (as in `sin x`).
    final fn = _functions[name];
    if (fn == null) {
      // **A name the table has never heard of.** At the calculator it is an
      // error, exactly as it always was; while GRAPHING it is the variable —
      // `x` in `y = 3x + 10` — and is only known when the curve is drawn.
      // Deferring the complaint to that moment is what lets one grammar
      // serve both, and the message is unchanged either way.
      return (v) {
        final bound = v[name];
        if (bound == null) throw _EvalError('unknown "$name"');
        return bound;
      };
    }
    final givesAngle = _givesAngle.contains(name);

    // **A BRACKETED argument belongs to the function alone.** `sin(2)^2` was
    // reading as `sin(2^2)` = sin 4 = -0.7568, because the argument was taken
    // with `_parseUnary`, which swallows a following `^`. Returning the call's
    // value at atom level lets `_parsePower` apply the `^` to the ANSWER,
    // which is what every calculator and every textbook means.
    //
    // The bracket-LESS form keeps the old reading on purpose: `sin x^2` does
    // mean sin(x squared) in school notation, and there is no bracket there
    // to say otherwise.
    if (!atEnd && s[i] == '(') {
      i++;
      final from = i;
      final inner = parseExpression();
      if (!_eat(')')) throw _EvalError('missing )');
      final src = s.substring(from, i - 1);
      angleOut = givesAngle;
      return (v) => _outAngle(givesAngle, fn(_asAngle(name, inner(v), src)));
    }
    final from = i;
    final arg = _parseUnary();
    final src = s.substring(from, i);
    angleOut = givesAngle;
    return (v) => _outAngle(givesAngle, fn(_asAngle(name, arg(v), src)));
  }

  /// One argument, bracketed or not — the same rule the ordinary call path
  /// uses, lifted out so the based-log family can share it.
  MathExpr _readOneArgument() {
    if (!atEnd && s[i] == '(') {
      i++;
      final v = parseExpression();
      if (!_eat(')')) throw _EvalError('missing )');
      return v;
    }
    return _parseUnary();
  }

  /// **The functions that need more than one number.**
  ///
  /// Deliberately short, and each one is on a school calculator: a Casio
  /// fx-82 AU PLUS II or its fx-991 sibling has GCD, LCM, the remainder, and
  /// nCr and nPr. Anything a single argument can express is NOT here —
  /// `sin`, `log`, `sqrt` all take one thing and asking for a comma would be
  /// an invented ceremony.
  static final Map<String, ({int min, double Function(List<double>) run})>
      _callFunctions = {
    'gcd': (min: 2, run: (a) => a.reduce(_gcd)),
    'lcm': (min: 2, run: (a) => a.reduce(_lcm)),
    // The REMAINDER, and the sign follows the divisor the way it does in
    // every language a student is likely to meet next: mod(-7, 3) is 2.
    'mod': (min: 2, run: (a) => a[0] - a[1] * (a[0] / a[1]).floorToDouble()),
    'max': (min: 2, run: (a) => a.reduce((x, y) => x > y ? x : y)),
    'min': (min: 2, run: (a) => a.reduce((x, y) => x < y ? x : y)),
    'ncr': (min: 2, run: (a) => _choose(a[0], a[1])),
    'npr': (min: 2, run: (a) => _permute(a[0], a[1])),
  };

  static double _gcd(double a, double b) {
    var x = a.abs().roundToDouble(), y = b.abs().roundToDouble();
    while (y > 0.5) {
      final t = x % y;
      x = y;
      y = t;
    }
    return x;
  }

  static double _lcm(double a, double b) {
    final g = _gcd(a, b);
    if (g == 0) return 0;
    return (a.abs() * b.abs() / g).roundToDouble();
  }

  static double _choose(double n, double r) {
    if (n < 0 || r < 0 || r > n) return double.nan;
    final k = r.roundToDouble();
    var out = 1.0;
    for (var j = 0.0; j < k; j++) {
      out = out * (n - j) / (j + 1);
    }
    return out.roundToDouble();
  }

  static double _permute(double n, double r) {
    if (n < 0 || r < 0 || r > n) return double.nan;
    final k = r.roundToDouble();
    var out = 1.0;
    for (var j = 0.0; j < k; j++) {
      out *= n - j;
    }
    return out;
  }

  /// Trigonometry, and every function that takes an ANGLE.
  static const Set<String> _takesAngle = {
    'sin', 'cos', 'tan', 'sec', 'csc', 'cot',
  };

  /// Functions that hand an angle BACK.
  static const Set<String> _givesAngle = {'asin', 'acos', 'atan'};

  /// **An angle is in degrees unless it says otherwise.**
  ///
  /// The owner, on finding `sin(30)` answering -0.988: *"i dont think the sin
  /// and cosine … are calculating properly, they are definitley giving the
  /// wrong results. I also didnt test it, but id like it to be able to handle
  /// radians (i.e. being able to put \pi in there)."* A year-10 student
  /// writing `sin(30)` means thirty degrees, and every school calculator
  /// agrees; the maths library underneath means radians, and nothing said so.
  ///
  /// The rule is one sentence: **degrees, unless the angle contains π (or a
  /// degree sign, which has already converted itself, or the word `rad`).**
  /// Nobody writes `sin(π/6)` meaning degrees, so the π in the angle is the
  /// student telling us which they meant — which is exactly what was asked
  /// for. The inverses give an angle BACK in degrees, so `sin⁻¹(0.5)` is 30
  /// and `sin⁻¹(sin(30))` comes home.
  /// **Degrees out, because degrees go in.** `sin⁻¹(0.5)` is 30, and
  /// `sin⁻¹(sin(30))` comes home.
  ///
  /// Read when the answer is WORKED OUT rather than when the expression was
  /// read, so a graph compiled once and redrawn after a mode switch is drawn
  /// in the mode that is on now.
  static double _outAngle(bool givesAngle, double v) =>
      givesAngle && mathAngleMode == AngleMode.degrees
          ? v * 180 / math.pi
          : v;

  static double _asAngle(String fn, double value, String src) {
    if (!_takesAngle.contains(fn)) return value;
    if (mathAngleMode == AngleMode.radians) return value;
    if (src.contains('pi') ||
        src.contains('\u03c0') ||
        src.contains('°') ||
        src.contains('rad')) {
      return value; // the angle itself said radians
    }
    return value * math.pi / 180;
  }

  /// `x^y`, with the odd roots of negative numbers that `math.pow` refuses.
  ///
  /// `(-8)^(1/3)` returned NaN, so `y = x^(1/3)` — a standard curve-sketching
  /// exercise — showed `undefined` for every negative x. `math.pow` is right
  /// that there is no PRINCIPAL real root, but school maths means the real
  /// one: when the exponent is p/q with q odd, the odd root exists and its
  /// sign follows p. `cbrt` in the function table has had this branch all
  /// along (`x < 0 ? -pow(-x, 1/3) : …`); `^` never got it.
  static double _power(double base, double exp) {
    if (base >= 0 || exp == exp.roundToDouble()) {
      return math.pow(base, exp).toDouble();
    }
    final r = rationalOf(exp);
    if (r != null && r.den.isOdd) {
      final mag = math.pow(-base, exp).toDouble();
      return r.num.isOdd ? -mag : mag;
    }
    // A genuinely complex result. NaN reads as "undefined", which is honest.
    return double.nan;
  }

  static double _factorial(double v) {
    if (v < 0 || v != v.roundToDouble()) {
      throw _EvalError('factorial needs a non-negative whole number');
    }
    if (v > 170) return double.infinity; // beyond double range anyway
    var out = 1.0;
    for (var n = 2; n <= v.toInt(); n++) {
      out *= n;
    }
    return out;
  }

  static bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;
  static bool _isLetter(String c) {
    final u = c.codeUnitAt(0);
    return (u >= 0x41 && u <= 0x5A) ||
        (u >= 0x61 && u <= 0x7A) ||
        // Greek letters are variables in maths, but π and e are constants and
        // are handled by name; anything else here is an unknown symbol.
        u == 0x3C0;
  }

  static const Map<String, double> _constants = {
    'pi': math.pi,
    'π': math.pi,
    'e': math.e,
    'tau': math.pi * 2,
    'phi': 1.618033988749895,
    'inf': double.infinity,
  };

  static final Map<String, double Function(double)> _functions = {
    'sqrt': math.sqrt,
    'cbrt': (x) => x < 0 ? -math.pow(-x, 1 / 3).toDouble() : math.pow(x, 1 / 3).toDouble(),
    'abs': (x) => x.abs(),
    'sin': math.sin,
    'cos': math.cos,
    'tan': math.tan,
    'asin': math.asin,
    'acos': math.acos,
    'atan': math.atan,
    'sinh': (x) => (math.exp(x) - math.exp(-x)) / 2,
    'cosh': (x) => (math.exp(x) + math.exp(-x)) / 2,
    'tanh': (x) {
      final a = math.exp(x), b = math.exp(-x);
      return (a - b) / (a + b);
    },
    'ln': math.log,
    'log': (x) => math.log(x) / math.ln10, // log = base 10, as in school
    'log2': (x) => math.log(x) / math.ln2,
    'log10': (x) => math.log(x) / math.ln10,
    'exp': math.exp,
    'floor': (x) => x.floorToDouble(),
    'ceil': (x) => x.ceilToDouble(),
    'round': (x) => x.roundToDouble(),
    'sign': (x) => x.sign,
    // Degrees, because a first-year problem set is as likely to be in degrees
    // as radians and getting it silently wrong is worse than not offering it.
    'rad': (x) => x * math.pi / 180,
    'deg': (x) => x * 180 / math.pi,
  };
}

/// The fraction a decimal really is, or null when it is not a tidy one.
///
/// Continued fractions (the standard best-rational-approximation walk): each
/// step takes the whole part and recurses on the reciprocal of what is left,
/// which produces the convergents in order of increasing denominator. The
/// first convergent that reproduces [v] to within [eps] is the answer, and
/// the walk gives up past [maxDen].
///
/// Used for two things that turn out to be the same question: showing an
/// answer as `1/2` instead of `0.5`, and knowing whether a negative number
/// raised to a fractional power has a real odd root.
///
/// A WHOLE number returns null on purpose — `5` has no fraction worth
/// showing, and the answer chip uses that null to know it must not offer a
/// toggle that would do nothing.
({int num, int den})? rationalOf(double v,
    {int maxDen = 10000, double eps = 1e-9}) {
  if (!v.isFinite) return null;
  if (v == v.roundToDouble()) return null; // a whole number is not a fraction
  final mag = v.abs();
  // Outside this band there is no fraction worth showing: a millionth is
  // better read as a decimal, and above a billion the first convergent is
  // always floor(v)/1, which is not a fraction at all.
  if (mag < 1e-6 || mag > 1e9) return null;
  final neg = v < 0;
  var x = mag;
  // p/q are the convergents; the recurrence is the textbook one.
  var p0 = 0, q0 = 1, p1 = 1, q1 = 0;
  for (var step = 0; step < 40; step++) {
    final a = x.floor();
    final p2 = a * p1 + p0, q2 = a * q1 + q0;
    if (q2 > maxDen) break;
    p0 = p1;
    q0 = q1;
    p1 = p2;
    q1 = q2;
    // **A denominator of 1 is not an answer.** The FIRST convergent is
    // always floor(|v|)/1, so float noise — `1/6` six times lands on
    // 0.9999999999999999 — used to be accepted as `1/1`, and the student
    // read "one over one" where the answer is 1. The doc above promises a
    // whole number returns null; this is what keeps that promise for the
    // values that are only ALMOST whole.
    if (q1 > 1 && (p1 / q1 - mag).abs() <= eps * (mag < 1 ? 1 : mag)) {
      return (num: neg ? -p1 : p1, den: q1);
    }
    final frac = x - a;
    if (frac.abs() < 1e-12) break;
    x = 1 / frac;
  }
  return null;
}

/// Which way an angle is measured.
enum AngleMode {
  /// `sin(30)` is a half — what a school calculator does, and the default.
  /// An angle carrying a π (or a degree sign, or `rad`) is still read as
  /// radians, because nobody writes `sin(π/6)` meaning degrees.
  degrees,

  /// `sin(30)` is −0.988. What a university student, or anyone past the
  /// unit circle, expects. A degree sign still forces degrees.
  radians,
}

/// The mode in force, app-wide.
///
/// A global, deliberately, and it is the same call `OnoteEditors._active`
/// makes for the editor engine: the evaluator is a pure function reached
/// from a dozen places — the answer chip, the `= ` keystroke, the toggle,
/// and soon the grapher — and threading one setting through every one of
/// them would put a parameter in a dozen signatures to say a thing that is
/// true of the whole app at once. [AppState.setAngleMode] owns it.
AngleMode mathAngleMode = AngleMode.degrees;
