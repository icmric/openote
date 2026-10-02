// Formulas with more than one name in them.
//
// *"its unable to handle multi variable stuff at the moment, is this something
// that would be relativley trivial to add, or is that a bigger project?"*
//
// The answer was "moderate", because `MathExpr` was always
// `double Function(Map<String, double>)` — the evaluator core has taken a map
// of variables since the grapher was built. The single-variable restriction
// lived entirely in the wrapper: `compileFunction` binds exactly one name and
// has to be TOLD which, so a formula naming any other was refused when it was
// reached. Measured before writing a line: nothing but `x` worked.

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/math/evaluate.dart';
import 'package:openote/math/graph_plot.dart';
import 'package:openote/math/substitute.dart';

void main() {
  group('finding the names', () {
    test('one name, as before', () {
      expect(freeVariables('3x+10'), ['x']);
    });

    test('several, in the order they are written', () {
      // Not alphabetical, and not the order a Set would hand back. A student
      // reading `u + a*t` expects to be asked for u, then a, then t, and the
      // fields are built straight off this list.
      expect(freeVariables('u+a*t'), ['u', 'a', 't']);
      expect(freeVariables('l*w'), ['l', 'w']);
      expect(freeVariables('sqrt(a^2+b^2)'), ['a', 'b']);
    });

    test('a name used twice is asked for once', () {
      expect(freeVariables('x^2+2*x+1'), ['x']);
      expect(freeVariables('a*b+b*a'), ['a', 'b']);
    });

    test('functions and constants are not names to fill in', () {
      // The reason the names come from the parser rather than from a regular
      // expression over the letters: a third copy of this list would drift,
      // and start asking a student for the value of sin.
      expect(freeVariables('sin(t)+cos(t)'), ['t']);
      expect(freeVariables('2*pi*r'), ['r']);
      expect(freeVariables('e^k'), ['k']);
      expect(freeVariables('log10(n)'), ['n']);
      expect(freeVariables('sqrt(2)*h'), ['h']);
    });

    test('a formula that is just a number needs nothing', () {
      expect(freeVariables('2+3'), isEmpty);
    });

    test('case is kept', () {
      // `V = I*R` asking for `i` and `r` reads like a different formula from
      // the one the student wrote.
      expect(freeVariables('I*R'), ['I', 'R']);
      expect(freeVariables('3T+1'), ['T']);
    });
  });

  group('working it out', () {
    test('the formulas that used to be refused', () {
      // Every one of these was `unknown "<first name>"` before this change.
      final cases = {
        'F=m*a': ({'m': '10', 'a': '9.8'}, '98'),
        'v=u+a*t': ({'u': '2', 'a': '3', 't': '4'}, '14'),
        'A=l*w': ({'l': '3', 'w': '7'}, '21'),
        'c=sqrt(a^2+b^2)': ({'a': '3', 'b': '4'}, '5'),
        'y=3T+1': ({'T': '5'}, '16'),
      };
      cases.forEach((latex, expected) {
        final src = substituteSourceFromLinear(latex);
        expect(src.isOk, isTrue, reason: '$latex: ${src.error}');
        final answer = answerFor(src, expected.$1);
        expect(answer.missing, isEmpty, reason: latex);
        expect(answer.result?.display, expected.$2, reason: latex);
      });
    });

    test('the answer is named', () {
      // *"ensure the answer is clear, as at the moment its not super clear to
      // me"* — a bare `= 98` does not say what the 98 is.
      final src = substituteSourceFromLinear('F=m*a');
      expect(src.resultName, 'F');
      expect(answerFor(src, {'m': '2', 'a': '3'}).resultName, 'F');
    });

    test('f(x) names its answer f, not x', () {
      expect(substituteSourceFromLinear('f(x)=2x+1').resultName, 'f');
      expect(substituteSourceFromLinear('s(u,t)=u*t').variables, ['u', 't']);
      expect(substituteSourceFromLinear('s(u,t)=u*t').resultName, 's');
    });

    test('a bare expression names nothing and still works', () {
      final src = substituteSourceFromLinear('l*w');
      expect(src.resultName, isNull);
      expect(answerFor(src, {'l': '4', 'w': '5'}).result?.display, '20');
    });

    test('what is still missing is listed, in order', () {
      final src = substituteSourceFromLinear('v=u+a*t');
      expect(answerFor(src, {}).missing, ['u', 'a', 't']);
      expect(answerFor(src, {'a': '3'}).missing, ['u', 't']);
      expect(answerFor(src, {'u': '1', 'a': '2', 't': '3'}).missing, isEmpty);
      // Partly filled is the common case for a block with three fields, and
      // it is not an error.
      expect(answerFor(src, {'a': '3'}).result, isNull);
    });

    test('blank counts as not given, not as zero', () {
      final src = substituteSourceFromLinear('A=l*w');
      expect(answerFor(src, {'l': '3', 'w': '  '}).missing, ['w']);
    });

    test('a field can hold a sum, not just a number', () {
      // The same rule the one-variable block already followed: every value
      // goes through evaluateLinear, so `2+3` and `pi` are numbers here.
      final src = substituteSourceFromLinear('A=l*w');
      expect(answerFor(src, {'l': '2+3', 'w': '2'}).result?.display, '10');
      final circle = substituteSourceFromLinear('A=pi*r^2');
      expect(answerFor(circle, {'r': '1'}).result?.display, '3.141592654');
    });

    test('a bad value says WHICH field is bad', () {
      // With three fields, "not an expression" on its own leaves the student
      // hunting for the one that is wrong.
      final src = substituteSourceFromLinear('v=u+a*t');
      final answer = answerFor(src, {'u': '1', 'a': 'banana', 't': '3'});
      expect(answer.result?.isOk, isFalse);
      expect(answer.result?.error, contains('a'));
    });

    test('an equation that has not been rearranged is refused in words', () {
      // The grapher SOLVES `2y = 6x + 4`, because rearranging is the topic it
      // was built for. Substituting is a different question — is the answer
      // y, or 2y? — and guessing would be worse than asking.
      final src = substituteSourceFromLinear('2y=6x+4');
      expect(src.isOk, isFalse);
      expect(src.error, contains('rearrange'));
    });

    test('a formula with no value THERE is a gap, not a failure', () {
      final src = substituteSourceFromLinear('y=sqrt(x)');
      final answer = answerFor(src, {'x': '-1'});
      expect(answer.result!.value.isNaN, isTrue);
    });
  });

  group('what was already working still works', () {
    test('the grapher is untouched by the name change', () {
      // `CompiledFormula` is deliberately not an extension of `CompiledMath`:
      // a curve is a function of one variable by definition. These are the
      // cases that prove the shared parser change did not disturb it.
      final g = graphSourceFromLinear('y=3x+10');
      expect(g.isOk, isTrue);
      expect(g.fn!.at!(2), 16);
      expect(graphSourceFromLinear('x=3').verticalAt, 3);
      // Still solved, still for y.
      expect(graphSourceFromLinear('2y=6x+4').fn!.at!(1), 5);
      // And a curve still refuses a second name, because it has nowhere to
      // put one. The substitute block is the feature for that shape.
      expect(graphSourceFromLinear('y=3x+c').isOk, isFalse);
    });

    test('a capital still reaches a lower-case binding', () {
      // compileFunction folds the name it is given; the parser now keeps the
      // spelling. The fallback is what stops those two disagreeing.
      final f = compileFunction('3X+1');
      expect(f.isOk, isTrue);
      expect(f.at!(2), 7);
    });

    test('the calculator still refuses an unknown name in its own words',
        () {
      expect(evaluateLinear('3+c').error, 'unknown "c"');
    });
  });
}
