// What this file pins is the RENDERER's real coverage, measured rather than
// read off a README. Every `renders` case below was verified to fail before
// `renderableLatex` existed (see the failure quoted beside it); every
// `passesThrough` case guards the opposite risk — that the rewriter starts
// damaging LaTeX that was already fine.
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/math/latex_compat.dart';
import 'package:openote/math/math_view.dart';

/// True when `flutter_math_fork` draws [tex] rather than falling back.
Future<bool> _draws(WidgetTester t, String tex) async {
  var ok = true;
  await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
    home: Scaffold(
      // Unbounded width: a wide equation must not be counted as a failure.
      body: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Math.tex(
          tex,
          textStyle: const TextStyle(fontSize: 18),
          onErrorFallback: (_) {
            ok = false;
            return const Text('fallback');
          },
        ),
      ),
    ),
  ));
  await t.pump();
  t.takeException();
  return ok;
}

void main() {
  group('renderableLatex makes ordinary LaTeX drawable', () {
    // key => (source the user wrote, the renderer's complaint about it raw)
    const broken = <String, String>{
      // "No such environment: …" — the renderer is a KaTeX subset and these
      // eight environments are simply absent from it.
      'align': r'\begin{align} a &= b \\ c &= d \end{align}',
      'align star': r'\begin{align*} a &= b \\ c &= d \end{align*}',
      'split': r'\begin{split} a &= b \\ &= c \end{split}',
      'eqnarray': r'\begin{eqnarray} a &=& b \\ c &=& d \end{eqnarray}',
      'flalign': r'\begin{flalign} a &= b \end{flalign}',
      'alignat star': r'\begin{alignat*}{2} a &= b & c &= d \end{alignat*}',
      'gather': r'\begin{gather} a = b \\ c = d \end{gather}',
      'gathered': r'\begin{gathered} a = b \\ c = d \end{gathered}',
      'multline': r'\begin{multline} a + b \\ + c \end{multline}',
      'equation': r'\begin{equation} E = mc^2 \end{equation}',
      // Parsed fine, then threw at LAYOUT time:
      // "Unsupported operation: Temporary node CrNode encountered".
      'top-level line break': r'a = b \\ c = d',
      // "Can't use function '$' in math mode" — an equation arriving with its
      // own delimiters still attached, which is how they come out of an import
      // that writes maths into Markdown.
      r'$…$ wrapper': r'$\frac{n}{2}$',
      r'$$…$$ wrapper': r'$$\sum_{i=1}^n i$$',
      r'\[…\] wrapper': r'\[ x^2 + y^2 = z^2 \]',
      r'\(…\) wrapper': r'\( a + b \)',
      // "Undefined control sequence: …"
      'nonumber': r'a = b \nonumber',
      'notag': r'a = b \notag',
      'label': r'a = b \label{eq:one}',
      'mathstrut': r'\mathstrut a',
      'smash': r'\smash{\int} x',
      'smash with optional arg': r'\smash[t]{\int} x',
      'href': r'\href{https://a.test}{the proof}',
      'tag': r'a = b \tag{7}',
    };

    for (final e in broken.entries) {
      testWidgets('${e.key} draws after rewriting', (t) async {
        expect(await _draws(t, e.value), isFalse,
            reason: 'PRE-CONDITION: ${e.key} was supposed to be a renderer '
                'gap. If this now passes raw, the dependency gained support '
                'and the rewrite for it can be dropped.');
        expect(await _draws(t, renderableLatex(e.value)), isTrue,
            reason: 'renderableLatex left ${e.key} unrenderable: '
                '${renderableLatex(e.value)}');
      });
    }
  });

  group('LaTeX the renderer already handles is left alone', () {
    // The product owner's actual complaint was a piecewise equation. `cases`
    // was never the broken part — this pins that, so a dependency bump cannot
    // take it away silently, and pins that the rewriter does not touch it.
    const fine = <String, String>{
      'cases (the OneNote equation)':
          r'f(n) = \begin{cases} \frac{n}{2} & \text{if } (2 \mid n) \\ '
              r'-\left(\frac{n+1}{2}\right) & \text{if } (2 \nmid n) \end{cases}',
      'cases minimal': r'\begin{cases} x & x>0 \\ -x & x \le 0 \end{cases}',
      'aligned': r'\begin{aligned} a &= b \\ c &= d \end{aligned}',
      'pmatrix': r'\begin{pmatrix} a & b \\ c & d \end{pmatrix}',
      'bmatrix': r'\begin{bmatrix} a & b \\ c & d \end{bmatrix}',
      'vmatrix': r'\begin{vmatrix} a & b \\ c & d \end{vmatrix}',
      'array': r'\begin{array}{c|c} a & b \\ c & d \end{array}',
      'left brace right dot':
          r'\left\{\begin{array}{l} a \\ b \end{array}\right.',
      'sqrt with degree': r'\sqrt[3]{x}',
      'sum with limits': r'\sum_{n=1}^{\infty} \frac{1}{n^2}',
      'integral': r'\int_0^1 x\,\mathrm{d}x',
      'substack': r'\sum_{\substack{0<i<m \\ 0<j<n}} P(i,j)',
      'binom': r'\binom{n}{k}',
      'overset and underset': r'\overset{def}{=} \underset{n}{\min}',
      'accents': r'\hat{x} \bar{y} \vec{v} \widehat{abc}',
      'text': r'\text{if } x > 0',
      'divides': r'2 \mid n \quad 2 \nmid n',
      'blackboard': r'\mathbb{N} \subseteq \mathbb{Z}',
    };

    for (final e in fine.entries) {
      testWidgets('${e.key} still draws', (t) async {
        expect(renderableLatex(e.value), e.value.trim(),
            reason: 'renderableLatex must not rewrite LaTeX that already '
                'works — that is how a correct equation stops working.');
        expect(await _draws(t, renderableLatex(e.value)), isTrue);
      });
    }
  });

  group('the rewriter does not overreach', () {
    test(r'a \\ inside an environment is that environment’s break', () {
      // Wrapping here would nest cases inside an array and change the layout.
      const cases = r'\begin{cases} a \\ b \end{cases}';
      expect(renderableLatex(cases), cases);
    });

    test(r'a \\ inside braces belongs to the enclosing command', () {
      const sub = r'\sum_{\substack{i \\ j}} x';
      expect(renderableLatex(sub), sub);
    });

    test(r'\left\{ does not disturb the brace depth', () {
      // If the scanner counted the escaped `{` in `\left\{`, it would think
      // this `\\` was nested and leave the layout crash in place.
      expect(renderableLatex(r'\left\{ a \right. \\ b'),
          startsWith(r'\begin{array}{c}'));
    });

    test(r'a longer command is not mistaken for a shorter one', () {
      // A TeX control word runs to the first non-letter, and `\newcommand`
      // works in this renderer — so these are names a user can really define.
      // Matching on the prefix would eat the wrong command.
      expect(renderableLatex(r'\tagged{x}'), r'\tagged{x}');
      expect(renderableLatex(r'\smashing{x}'), r'\smashing{x}');
      expect(renderableLatex(r'\notagline'), r'\notagline');
      expect(renderableLatex(r'\nonumberic'), r'\nonumberic');
    });

    test('two separate inline equations are not spliced together', () {
      // `$a$ + $b$` begins and ends with `$` but is two equations; unwrapping
      // it would silently join them.
      expect(renderableLatex(r'$a$ + $b$'), r'$a$ + $b$');
    });

    test('an unbalanced brace is left for the fallback to show', () {
      expect(renderableLatex(r'\smash{a'), r'\smash{a');
    });

    test(r'\end names only the environment, never its column argument', () {
      // `\begin{darray}` closed by `\end{array}` is a parser error; the same
      // mistake with the array rewrite would break every `gather`.
      final out = renderableLatex(r'\begin{gather} a \\ b \end{gather}');
      expect(out, contains(r'\begin{array}{c}'));
      expect(out, contains(r'\end{array}'));
      expect(out, isNot(contains(r'\end{array}{c}')));
    });

    test('empty input stays empty', () {
      expect(renderableLatex(''), '');
      expect(renderableLatex('   '), '');
    });
  });

  group('an equation that cannot be drawn says so in plain words', () {
    testWidgets('unknown command: the note names it and the source is shown',
        (t) async {
      // `\sideset` is a genuine gap with no equivalent to rewrite it to — the
      // case this fallback exists for.
      const tex = r'\sideset{_a^b}{_c^d}\sum';
      await t.pumpWidget(const MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: OnoteMath(tex, textStyle: TextStyle(fontSize: 18)),
        ),
      ));
      await t.pump();
      // The WHOLE source, verbatim — `find.textContaining(r'\sideset')` would
      // be satisfied by the note alone, which names the command it choked on.
      expect(find.text(tex), findsOneWidget,
          reason: 'the student must be able to read and copy their equation');
      expect(find.textContaining('saved exactly as it was written'),
          findsOneWidget);
      // No jargon on the page: a student must not be shown the parser's own
      // vocabulary, which is what the old grey-monospace fallback amounted to.
      expect(find.textContaining('Parser Error'), findsNothing);
      expect(find.textContaining('control sequence'), findsNothing);
    });

    testWidgets('OnoteMath applies the rewrite, not just Math.tex', (t) async {
      // The wiring, not the function: a rewriter nothing calls fixes nothing.
      await t.pumpWidget(const MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: OnoteMath(r'\begin{align} a &= b \\ c &= d \end{align}',
                textStyle: TextStyle(fontSize: 18)),
          ),
        ),
      ));
      await t.pump();
      expect(find.textContaining('saved exactly'), findsNothing,
          reason: 'an align equation must draw, not fall back');
    });

    testWidgets('a drawable equation shows no notice at all', (t) async {
      await t.pumpWidget(const MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: OnoteMath(r'\begin{cases} a \\ b \end{cases}',
              textStyle: TextStyle(fontSize: 18)),
        ),
      ));
      await t.pump();
      expect(find.textContaining('saved exactly'), findsNothing);
    });

    test('the plain-words note never quotes the parser at the reader', () {
      final note = mathDisplayProblem(
          const BuildException('Unsanitized build exception detected'));
      expect(note, isNot(contains('Exception')));
      expect(note, contains('saved exactly as it was written'));
    });
  });
}
