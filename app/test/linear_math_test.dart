import 'package:flutter_test/flutter_test.dart';
import 'package:openote/math/linear_math.dart';

void main() {
  group('linearToLatex (Math Input Spec §7 seed subset)', () {
    test('simple fraction', () {
      expect(linearToLatex('(x^2+4)/(x-3)'), r'\frac{x^2+4}{x-3}');
    });
    test('summation with limits', () {
      final out = linearToLatex(r'\sum_(n=1)^oo 1/n^2');
      expect(out, contains(r'\sum_{n=1}'));
      expect(out, contains(r'\infty'));
      expect(out, contains(r'\frac{1}{n^2}'));
    });
    test('unicode n-ary converts to LaTeX storage form', () {
      expect(linearToLatex('∑_(k=0)^(n) k'), contains(r'\sum'));
      expect(linearToLatex('∑_(k=0)^(n) k'), contains('_{k=0}^{n}'));
    });
    test('integral with differential sugar', () {
      final out = linearToLatex(r'\int_(0)^(1) x^2 \dx');
      expect(out, contains(r'\int_{0}^{1}'));
      expect(out, contains(r'\mathrm{d}x'));
    });
    test('matrix rows and columns', () {
      final out = linearToLatex('■(a&b@c&d)');
      expect(out, contains(r'\begin{pmatrix}'));
      expect(out, contains(r'a&b \\ c&d'));
    });
    test('cases', () {
      final out = linearToLatex(r'\cases(x&x>0@-x&x≤0)');
      expect(out, contains(r'\begin{cases}'));
    });
    test('root with degree', () {
      expect(linearToLatex('√(3&x+1)'), r'\sqrt[3]{x+1}');
    });
    test('abs/norm sugar', () {
      expect(linearToLatex(r'\abs(x)'), r'\lvert x\rvert');
      expect(linearToLatex(r'\norm(v)'), r'\lVert v\rVert');
    });
    test('plain LaTeX passes through', () {
      expect(linearToLatex(r'\frac{a}{b} + \alpha'), r'\frac{a}{b} + \alpha');
    });
  });
}
