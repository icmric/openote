// The grammar compiles to a closure (plan: v0.23, graphs).
//
// A curve is several hundred samples and the owner asked to see it change as
// they type, so the parse happens ONCE and the painter calls what it built.
// The calculator is the same code with nothing bound, which is the whole
// reason it is one grammar and not two.
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/math/evaluate.dart';

void main() {
  tearDown(() => mathAngleMode = AngleMode.degrees);

  group('what it compiles', () {
    test('a line, a parabola, a reciprocal', () {
      final line = compileFunction('3x+10');
      expect(line.isOk, isTrue);
      expect(line.at!(0), 10);
      expect(line.at!(2), 16);
      expect(line.at!(-4), -2);

      final quad = compileFunction('x^2-4');
      expect(quad.at!(0), -4);
      expect(quad.at!(3), 5);
      expect(quad.at!(-3), 5);

      final recip = compileFunction('1/x');
      expect(recip.at!(2), 0.5);
      expect(recip.at!(0).isInfinite, isTrue,
          reason: 'a pole is infinite, and the painter breaks the line there');
    });

    test('the whole grammar comes with it', () {
      expect(compileFunction('sqrt(x)').at!(9), 3);
      expect(compileFunction('|x|').at!(-3), 3);
      expect(compileFunction('2^x').at!(10), 1024);
      expect(compileFunction('x!').at!(5), 120);
      expect(compileFunction('gcd(x,18)').at!(12), 6);
      expect(compileFunction('x mod 5').at!(17), 2);
      expect(compileFunction('log2(x)').at!(8), 3);
      expect(compileFunction('pi*x').at!(2), closeTo(6.283185307, 1e-6));
    });

    test('and the angle rule comes with it too', () {
      mathAngleMode = AngleMode.degrees;
      expect(compileFunction('sin(x)').at!(30), closeTo(0.5, 1e-12));
      mathAngleMode = AngleMode.radians;
      expect(compileFunction('sin(x)').at!(30), closeTo(-0.988031624, 1e-9));
    });

    test('the mode is read when the curve is drawn, not when it is written',
        () {
      mathAngleMode = AngleMode.degrees;
      final f = compileFunction('sin(x)');
      expect(f.at!(30), closeTo(0.5, 1e-12));
      mathAngleMode = AngleMode.radians;
      expect(f.at!(30), closeTo(-0.988031624, 1e-9),
          reason: 'the same compiled curve, redrawn after the switch');
    });

    test('another letter is a variable if you name it', () {
      final f = compileFunction('2t+1', variable: 't');
      expect(f.isOk, isTrue);
      expect(f.variable, 't');
      expect(f.at!(3), 7);
    });
  });

  group('what it refuses, and when', () {
    test('a name nothing knows is refused UP FRONT, not silently drawn', () {
      final f = compileFunction('3z+1');
      expect(f.isOk, isFalse);
      expect(f.error, contains('z'),
          reason: 'the calculator would have said this, so the graph does too');
      expect(f.at, isNull);
    });

    test('a second unknown alongside the variable is still refused', () {
      final f = compileFunction('m*x+c');
      expect(f.isOk, isFalse);
      expect(f.error, anyOf(contains('m'), contains('c')));
    });

    test('an equation is not an expression', () {
      expect(compileFunction('y=3x').isOk, isFalse);
      expect(compileFunction('').isOk, isFalse);
    });

    test('nonsense is refused with the reason', () {
      expect(compileFunction('3x+').isOk, isFalse);
      expect(compileFunction('((x)').isOk, isFalse);
    });
  });

  group('a gap in a curve is a gap, not a failure', () {
    test('outside a root domain the value is NaN', () {
      final f = compileFunction('sqrt(x)');
      expect(f.isOk, isTrue);
      expect(f.at!(4), 2);
      expect(f.at!(-4).isNaN, isTrue);
    });

    test('a factorial of a half says nothing rather than throwing', () {
      final f = compileFunction('x!');
      expect(f.isOk, isTrue,
          reason: 'the probes at 0, 1 and -1 include a refusal at -1, and a '
              'refusal at ONE point is a gap rather than a broken curve');
      expect(f.at!(0.5).isNaN, isTrue);
      expect(f.at!(4), 24);
    });

    test('log of a negative is a gap', () {
      final f = compileFunction('ln(x)');
      expect(f.at!(1), 0);
      expect(f.at!(-1).isNaN, isTrue);
    });
  });

  group('the calculator is unchanged by any of it', () {
    test('everything still works out to the same number', () {
      for (final entry in {
        '2+3': '5',
        '1/2': '0.5',
        'sqrt(16)': '4',
        'sin(30)': '0.5',
        '5!': '120',
        '25%*80': '20',
        'gcd(12,18)': '6',
        '17 mod 5': '2',
        '2^10': '1024',
      }.entries) {
        expect(evaluateLinear(entry.key).display, entry.value,
            reason: entry.key);
      }
    });

    test('and an unknown name is still an error at the calculator', () {
      final r = evaluateLinear('2x+1');
      expect(r.isOk, isFalse);
      expect(r.error, contains('x'),
          reason: 'nothing is bound there, so x is unknown \u2014 exactly as '
              'before the grammar learned to compile');
    });
  });

  group('it is fast enough to redraw while typing', () {
    test('a thousand samples of a real curve', () {
      final f = compileFunction('sin(x)/x + x^2/10');
      expect(f.isOk, isTrue);
      final sw = Stopwatch()..start();
      var sum = 0.0;
      for (var k = 0; k < 1000; k++) {
        final v = f.at!(-10 + k * 0.02);
        if (v.isFinite) sum += v;
      }
      sw.stop();
      expect(sum.isFinite, isTrue);
      // Generous: the point is that it is microseconds per sample, not the
      // 33x-a-parse it replaces. A thousand samples inside a sixtieth of a
      // second leaves the rest of the frame for everything else.
      expect(sw.elapsedMilliseconds, lessThan(16),
          reason: 'took ${sw.elapsedMilliseconds}ms for 1000 samples');
    });
  });
}
