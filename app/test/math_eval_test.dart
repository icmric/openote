// Numeric evaluation of linear math (MATH-7) — a calculator, not a CAS.
//
// OneNote paywalls math answers behind an Education subscription; we own the
// grammar, so this is free. The bar is a first-year problem set: arithmetic,
// powers, roots, trig, logs — not symbolic algebra.
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/math/evaluate.dart';

String evalOf(String s) => evaluateLinear(s).display;
bool ok(String s) => evaluateLinear(s).isOk;

void main() {
  group('arithmetic and precedence', () {
    test('respects operator precedence', () {
      expect(evalOf('2+3*4'), '14');
      expect(evalOf('(2+3)*4'), '20');
      expect(evalOf('10-2-3'), '5', reason: 'subtraction is left-associative');
      expect(evalOf('100/10/2'), '5');
    });

    test('unary minus binds tighter than binary', () {
      expect(evalOf('-3+5'), '2');
      expect(evalOf('3*-2'), '-6');
      expect(evalOf('--4'), '4');
    });

    test('exponentiation is right-associative', () {
      // 2^(3^2) = 512, not (2^3)^2 = 64. Getting this wrong is the classic
      // calculator bug.
      expect(evalOf('2^3^2'), '512');
      expect(evalOf('2^10'), '1024');
    });

    test('unicode operators from the palette work', () {
      expect(evalOf('6×7'), '42');
      expect(evalOf('84÷2'), '42');
      expect(evalOf('5−3'), '2');
    });
  });

  group('display', () {
    test('whole results have no decimal point', () {
      expect(evalOf('8/2'), '4');
      expect(evalOf('2.5*2'), '5');
    });

    test('binary floating point noise is absorbed', () {
      // 0.30000000000000004 is not the student's problem.
      expect(evalOf('0.1+0.2'), '0.3');
    });

    test('division by zero reads as infinity, not a crash', () {
      expect(evalOf('1/0'), '∞');
      expect(evalOf('-1/0'), '-∞');
      expect(evalOf('0/0'), 'undefined');
    });
  });

  group('functions and constants', () {
    test('roots and powers', () {
      expect(evalOf('sqrt(16)'), '4');
      expect(evalOf('cbrt(27)'), '3');
      expect(evalOf('√81'), '9');
    });

    test('trig in radians, with degree helpers', () {
      expect(evaluateLinear('sin(0)').value, closeTo(0, 1e-12));
      expect(evaluateLinear('cos(pi)').value, closeTo(-1, 1e-12));
      expect(evaluateLinear('sin(rad(90))').value, closeTo(1, 1e-12));
      expect(evaluateLinear('deg(pi)').value, closeTo(180, 1e-9));
    });

    test('logs: log is base 10, as taught in school', () {
      expect(evalOf('log(1000)'), '3');
      expect(evalOf('log2(8)'), '3');
      expect(evaluateLinear('ln(e)').value, closeTo(1, 1e-12));
    });

    test('constants', () {
      expect(evaluateLinear('pi').value, closeTo(3.14159265, 1e-6));
      expect(evaluateLinear('π*2').value, closeTo(6.2831853, 1e-6));
    });

    test('factorial', () {
      expect(evalOf('5!'), '120');
      expect(evalOf('0!'), '1');
      expect(ok('2.5!'), isFalse, reason: 'not a whole number');
      expect(ok('(-1)!'), isFalse);
    });

    test('absolute value both ways', () {
      expect(evalOf('abs(-7)'), '7');
      expect(evalOf('|-7|'), '7');
    });

    test('rounding helpers', () {
      expect(evalOf('floor(2.7)'), '2');
      expect(evalOf('ceil(2.1)'), '3');
      expect(evalOf('round(2.5)'), '3');
    });
  });

  group('implicit multiplication', () {
    test('a number before a name or bracket multiplies', () {
      expect(evaluateLinear('2pi').value, closeTo(6.2831853, 1e-6));
      expect(evalOf('3(2+2)'), '12');
      expect(evalOf('2sqrt(9)'), '6');
    });

    test('two bare numbers are NOT multiplied', () {
      // `2 3` is a typo; silently reading it as 6 would hide it.
      expect(ok('2 3'), isFalse);
    });
  });

  group('refuses rather than guessing', () {
    test('an equation is not an expression', () {
      // We evaluate; we do not solve. Vision §9 keeps a solver as a non-goal.
      expect(ok('x = 2 + 2'), isFalse);
      expect(evaluateLinear('2x+1=7').error, contains('not an expression'));
    });

    test('unknown names and unbalanced brackets fail cleanly', () {
      expect(ok('sqrt(9'), isFalse);
      expect(ok('wibble(3)'), isFalse);
      expect(ok('2 +'), isFalse);
      expect(ok(''), isFalse);
    });

    test('a symbolic expression fails rather than inventing a value', () {
      expect(ok('x^2 + 1'), isFalse);
    });

    test('half-typed input never throws', () {
      // This runs on every keystroke, so partial input is the normal case.
      for (final s in ['(', '1+', 'sqrt(', '2^', '|', '5!!', '.', '1e']) {
        expect(() => evaluateLinear(s), returnsNormally, reason: s);
      }
    });
  });

  group('numbers', () {
    test('decimals and exponent notation', () {
      expect(evalOf('1.5+1.5'), '3');
      expect(evalOf('1e3'), '1000');
      expect(evalOf('2.5e-2*100'), '2.5');
    });

    test('a bare e is the constant, not a broken exponent', () {
      expect(evaluateLinear('e').value, closeTo(2.718281828, 1e-8));
    });
  });
}
