// Equations, using the markup OneNote actually sends.
//
// Every sample here was taken off the wire by `test/manual/graph_probe2_test`,
// not invented. Six pages in sixty carried a `<math>`, and the shape of it is
// the reason the owner saw "text inside a maths equation is being new lined
// after every char": OneNote emits **one `<mi>` per letter**, so `sin` arrives
// as three elements and `Floor` as five.
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/onenote/graph_pages.dart';
import 'package:openote/onenote/mathml_latex.dart';

String wrap(String body) =>
    '<html><head><title>T</title></head><body data-absolute-enabled="true">'
    '<div style="position:absolute;left:48px;top:90px;width:624px">$body</div>'
    '</body></html>';

/// Verbatim from a real page.
const realFloor = '''
<math display="block" xmlns="http://www.w3.org/1998/Math/MathML">
  <mfenced open="&#8970;" close="&#8971;"><mrow /></mfenced>
  <mo>&#160;</mo>
  <mi>F</mi><mi>l</mi><mi>o</mi><mi>o</mi><mi>r</mi>
  <mo>&#160;</mo>
  <mfenced><mrow>
    <mi>R</mi><mi>o</mi><mi>u</mi><mi>n</mi><mi>d</mi>
    <mo>&#160;</mo>
    <mi>d</mi><mi>o</mi><mi>w</mi><mi>n</mi>
  </mrow></mfenced>
</math>''';

/// Also verbatim: `|sin θ| = sin α`, with the invisible-times operator.
const realSine = '''
<math display="block" xmlns="http://www.w3.org/1998/Math/MathML">
  <mfenced open="|" close="|"><mrow>
    <mi>s</mi><mi>i</mi><mi>n</mi><mo>&#8289;</mo><mo>&#160;</mo>
    <mi>&#120579;</mi>
  </mrow></mfenced>
  <mo>=</mo>
  <mrow><mrow><mi>s</mi><mi>i</mi><mi>n</mi></mrow><mo>&#8289;</mo>
  <mrow /></mrow>
  <mi>&#120572;</mi>
</math>''';

void main() {
  group('the shape OneNote sends', () {
    test('an equation is ONE line, not one line per letter', () {
      final r = readGraphPage(wrap('<p>before</p>$realFloor<p>after</p>'),
          title: 'Page');
      final md = (r.page['boxes'] as List).first['markdown'] as String;
      // The regression, stated as the thing a reader would notice: no line in
      // the box is a single character.
      for (final line in md.split('\n')) {
        expect(line.trim().length, isNot(1),
            reason: 'a line holding one letter means the equation exploded:\n'
                '$md');
      }
    });

    test('letters split across <mi> are joined back into words', () {
      final r = readGraphPage(wrap(realFloor), title: 'Page');
      final md = (r.page['boxes'] as List).first['markdown'] as String;
      expect(md, contains('Floor'));
      expect(md, contains('Round down'));
    });

    test('an equation becomes inline maths the app can render', () {
      // `$…$` is the app's own inline-maths syntax, so an equation imported
      // from the internet is the same object as one typed by hand rather than
      // a picture of one.
      final r = readGraphPage(wrap(realSine), title: 'Page');
      final md = (r.page['boxes'] as List).first['markdown'] as String;
      expect(md, contains(r'$'));
      expect(md, contains('sin'));
    });

    test('the surrounding paragraphs keep their own lines', () {
      final r = readGraphPage(wrap('<p>before</p>$realFloor<p>after</p>'),
          title: 'Page');
      final md = (r.page['boxes'] as List).first['markdown'] as String;
      final lines = md.split('\n');
      expect(lines.first, 'before');
      expect(lines.last, 'after');
    });
  });

  group('MathML to LaTeX', () {
    test('an operator arrives as a command, not as a lookalike character', () {
      // Reported: "what i wrote originally with \times is imported as *
      // rather than the x symbol". MathML sends the operator as the CHARACTER,
      // so a bare U+00D7 was landing inside the maths and the renderer was
      // left to guess at it.
      expect(
        mathmlToLatex('<math><mrow><mi>a</mi><mo>\u00d7</mo><mi>b</mi>'
            '</mrow></math>'),
        'a\\times b',
        reason: 'the command, and a space so it cannot run into the next letter',
      );
    });

    test('an operator with no command keeps its character', () {
      // The list is deliberately short. Plus, equals and brackets are already
      // exactly what LaTeX wants, and rewriting them would be churn.
      expect(
        mathmlToLatex('<math><mrow><mi>a</mi><mo>+</mo><mi>b</mi>'
            '</mrow></math>'),
        'a+b',
      );
    });

    test('fractions, powers and roots', () {
      const m = '<math><mfrac><mn>1</mn><mn>2</mn></mfrac>'
          '<msup><mi>x</mi><mn>2</mn></msup>'
          '<msqrt><mi>y</mi></msqrt></math>';
      final r = readGraphPage(wrap(m), title: 'Page');
      final md = (r.page['boxes'] as List).first['markdown'] as String;
      expect(md, contains(r'\frac{1}{2}'));
      expect(md, contains('x^{2}'));
      expect(md, contains(r'\sqrt{y}'));
    });

    test('subscripts', () {
      const m = '<math><msub><mi>a</mi><mn>1</mn></msub></math>';
      final r = readGraphPage(wrap(m), title: 'Page');
      expect((r.page['boxes'] as List).first['markdown'],
          contains('a_{1}'));
    });

    test('fences become the brackets they say they are', () {
      const m = '<math><mfenced open="[" close="]"><mi>x</mi></mfenced></math>';
      final r = readGraphPage(wrap(m), title: 'Page');
      final md = (r.page['boxes'] as List).first['markdown'] as String;
      expect(md, contains('['));
      expect(md, contains(']'));
    });

    test('a fence with no brackets given defaults to round ones', () {
      const m = '<math><mfenced><mi>x</mi></mfenced></math>';
      final r = readGraphPage(wrap(m), title: 'Page');
      final md = (r.page['boxes'] as List).first['markdown'] as String;
      expect(md, contains('('));
      expect(md, contains(')'));
    });

    test('the invisible operators OneNote sprinkles about are dropped', () {
      // U+2061 FUNCTION APPLICATION and friends carry no meaning to read and
      // would render as a missing glyph.
      final r = readGraphPage(wrap(realSine), title: 'Page');
      final md = (r.page['boxes'] as List).first['markdown'] as String;
      expect(md, isNot(contains('⁡')));
      expect(md, isNot(contains(' ')));
    });

    test('mathematical italic letters become plain ones', () {
      // OneNote writes theta as U+1D703 MATHEMATICAL ITALIC SMALL THETA, which
      // most fonts do not have; the equation renderer italicises for itself.
      final r = readGraphPage(wrap(realSine), title: 'Page');
      final md = (r.page['boxes'] as List).first['markdown'] as String;
      expect(md, isNot(contains('\u{1D703}')));
      expect(md, anyOf(contains(r'\theta'), contains('theta')));
    });

    test('an empty equation contributes nothing rather than empty maths', () {
      final r = readGraphPage(wrap('<math><mrow /></math>'), title: 'Page');
      final boxes = r.page['boxes'] as List;
      if (boxes.isNotEmpty) {
        expect(boxes.first['markdown'], isNot(contains(r'$$')));
      }
    });
  });
}
