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

/// The result of evaluating an expression, or why it couldn't be.
class EvalResult {
  const EvalResult.ok(this.value)
      : error = null,
        isOk = true;
  const EvalResult.err(this.error)
      : value = 0,
        isOk = false;

  final double value;
  final String? error;
  final bool isOk;

  /// A human-facing rendering: integers without a decimal point, everything
  /// else trimmed of trailing zeros. `0.1+0.2` should read `0.3`, not
  /// `0.30000000000000004` — binary floating point is not the student's
  /// problem.
  String get display {
    if (!isOk) return error ?? 'error';
    if (value.isNaN) return 'undefined';
    if (value.isInfinite) return value.isNegative ? '-∞' : '∞';
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toStringAsFixed(0);
    }
    // 12 significant digits absorbs the usual binary-representation noise
    // without inventing precision the inputs didn't have.
    var s = value.toStringAsPrecision(12);
    if (s.contains('.') && !s.contains('e')) {
      s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
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
    final v = p.parseExpression();
    p.skipSpace();
    if (!p.atEnd) return EvalResult.err('unexpected "${p.rest}"');
    return EvalResult.ok(v);
  } on _EvalError catch (e) {
    return EvalResult.err(e.message);
  } catch (_) {
    return const EvalResult.err('could not evaluate');
  }
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

  double parseExpression() {
    var left = _parseTerm();
    while (true) {
      skipSpace();
      if (_eat('+')) {
        left += _parseTerm();
      } else if (_eat('−') || _eat('-')) {
        left -= _parseTerm();
      } else {
        return left;
      }
    }
  }

  double _parseTerm() {
    var left = _parseUnary();
    while (true) {
      skipSpace();
      if (_eat('*') || _eat('×') || _eat('·')) {
        left *= _parseUnary();
      } else if (_eat('/') || _eat('÷')) {
        final d = _parseUnary();
        left /= d; // ±∞ / NaN are reported by [EvalResult.display]
      } else if (_eat('%')) {
        left = left % _parseUnary();
      } else if (_startsImplicitProduct()) {
        // `2pi`, `3(x+1)`, `2sqrt(9)` — the way people actually write maths.
        left *= _parseUnary();
      } else {
        return left;
      }
    }
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

  double _parseUnary() {
    skipSpace();
    if (_eat('-') || _eat('−')) return -_parseUnary();
    if (_eat('+')) return _parseUnary();
    return _parsePower();
  }

  double _parsePower() {
    final base = _parsePostfix();
    skipSpace();
    if (_eat('^')) {
      // Right-associative: 2^3^2 is 2^(3^2) = 512.
      final exp = _parseUnary();
      return math.pow(base, exp).toDouble();
    }
    return base;
  }

  double _parsePostfix() {
    var v = _parseAtom();
    while (true) {
      skipSpace();
      if (i < s.length && s[i] == '!') {
        i++;
        v = _factorial(v);
      } else {
        return v;
      }
    }
  }

  double _parseAtom() {
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
      return v.abs();
    }
    if (_eat('√')) return math.sqrt(_parseUnary());

    final c = s[i];
    if (_isDigit(c) || c == '.') return _parseNumber();
    if (_isLetter(c)) return _parseNameOrCall();
    throw _EvalError('unexpected "$c"');
  }

  double _parseNumber() {
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
    return v;
  }

  double _parseNameOrCall() {
    final start = i;
    while (i < s.length && (_isLetter(s[i]) || _isDigit(s[i]))) {
      i++;
    }
    final name = s.substring(start, i).toLowerCase();

    // Constant?
    final k = _constants[name];
    if (k != null) return k;

    // Function call: name(...) or name x (as in `sin x`).
    skipSpace();
    final fn = _functions[name];
    if (fn == null) throw _EvalError('unknown "$name"');
    // log with an explicit base: log2(8), log10(100).
    final arg = _parseUnary();
    return fn(arg);
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
