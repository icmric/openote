// Display maths and padded maths in the live grammar (v0.20 D.5 / C.3).
//
// The measured defect: an equation written `$$E=mc^2$$` rendered as a 65px
// centred line at rest and collapsed to `$` + a 21px inline atom + `$` the
// moment the caret entered the block — the single-dollar grammar took only
// the INNER pair. And `$ x $` with padding spaces was refused outright even
// when the inner run was unmistakably maths.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/live_markdown_controller.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/markdown/md_syntax.dart';
import 'package:openote/math/latex_compat.dart';
import 'package:openote/math/math_editor.dart';
import 'package:openote/math/math_view.dart';

void main() {
  group('saved empty slots are VISIBLE in read mode (v0.18 5.3)', () {
    test('a half-filled fraction gets its square back', () {
      final out = renderableLatex(r'\frac{}{2}');
      expect(out, contains(r'\square'),
          reason: 'TeX draws an empty group as NOTHING — a bar over a hole, '
              'in read mode and in the PDF, with no sign anything is '
              'unfinished');
    });

    test('storage is untouched — the squares are render-time only', () {
      final e = MathEditor.empty()..insertSource(r'\frac{}{2}');
      expect(e.latex, isNot(contains(r'\square')),
          reason: 'canonical LaTeX keeps the bare braces');
    });

    test('a full equation passes through unchanged', () {
      expect(renderableLatex(r'\frac{1}{2}'), isNot(contains(r'\square')));
    });

    test('the script separator between two scripts is NOT a slot', () {
      // rowToTex writes x^{2}{}^{3} to keep TeX from refusing a double
      // script; that empty group is protocol, not an unfinished box.
      final out = renderableLatex(r'x^{2}{}^{3}');
      expect(out, isNot(contains(r'\square')));
    });
  });


  group('the grammar', () {
    test(r'$$…$$ is ONE match, both pairs included', () {
      final m = mdInlineRe.firstMatch(r'so $$E=mc^2$$ holds');
      expect(m, isNotNull);
      final c = classifyInline(m!);
      expect(c.kind, MdInline.mathDisplay);
      expect(c.inner, r'E=mc^2');
      expect(m.end - m.start, r'$$E=mc^2$$'.length);
    });

    test(r'$x$ is still the plain inline form', () {
      final c = classifyInline(mdInlineRe.firstMatch(r'a $x$ b')!);
      expect(c.kind, MdInline.math);
    });

    test('padded maths is accepted ONLY with a backslash inside', () {
      // The money rule (v0.20 D.5): prose turned into an equation is worse
      // than a refusal, and money never contains a backslash.
      final yes = mdInlineRe.firstMatch(r'so $ \frac{1}{2} $ then');
      expect(yes, isNotNull);
      final c = classifyInline(yes!);
      expect(c.kind, MdInline.mathPadded);
      expect(c.inner, r'\frac{1}{2}');

      expect(mdInlineRe.firstMatch(r'paid $ 5 $ then'), isNull,
          reason: 'no backslash, no equation — that is somebody\'s money');
    });

    test('the price pair stays prose, as ever', () {
      expect(mdInlineRe.firstMatch(r'coffee is $5 and lunch is $10 today'),
          isNull);
    });

    test('the empty pair still classifies as the chip', () {
      final c = classifyInline(mdInlineRe.firstMatch(r'area is $$ here')!);
      expect(c.kind, MdInline.mathEmpty);
      expect(c.inner, '');
    });
  });

  group('the live editor', () {
    LiveMarkdownController make(String text) =>
        LiveMarkdownController(text: text, dark: false);

    Future<void> pump(WidgetTester tester, LiveMarkdownController c) async {
      await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: TextField(controller: c, maxLines: null),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets(r'$$…$$ draws as ONE equation while editing — no stray dollars',
        (tester) async {
      final c = make(r'so $$E=mc^2$$ holds');
      await pump(tester, c);
      expect(find.byType(OnoteMath), findsOneWidget,
          reason: 'THE defect: the inner pair matched alone and a literal '
              'dollar stood on each side of the atom');
      final math = tester.widget<OnoteMath>(find.byType(OnoteMath));
      expect(math.tex, r'E=mc^2',
          reason: 'the atom carries the equation and nothing else — the '
              r'`\displaystyle` prefix this used to need is redundant now '
              'that every equation is set in display style, in a sentence '
              'exactly as in a box of its own');
      expect(c.text, r'so $$E=mc^2$$ holds',
          reason: 'the buffer keeps every code unit, as ever');
    });

    testWidgets('the caret crosses a display equation in ONE step',
        (tester) async {
      const src = r'a $$x^2$$ b';
      final c = make(src);
      await pump(tester, c);
      final hidden = c.hiddenMarkerRanges();
      // `$` at 2; the hidden remainder runs from 3 to one past the closing.
      expect(hidden.any((r) => r.start == 3 && r.end == 9), isTrue);
    });

    testWidgets('padded maths draws too', (tester) async {
      final c = make(r'half is $ \frac{1}{2} $ of it');
      await pump(tester, c);
      expect(find.byType(OnoteMath), findsOneWidget);
    });

    test('mathRunNear sheds the wrap, whichever width it is', () {
      final c = make(r'a $$x^2$$ b');
      final run = c.mathRunNear(2);
      expect(run, isNotNull);
      expect(run!.start, 2);
      expect(run.end, 9);
      expect(run.inner, r'x^2',
          reason: 'what reaches MathEditor.open must be LaTeX, never '
              'delimiters — a stray dollar here opened the editor on '
              'unparseable source');
    });

    test('replaceMathAt writes the wrap width it is told', () {
      final c = make(r'a $$x$$ b');
      c.replaceMathAt(2, 7, r'x+1', dollars: 2);
      expect(c.text, r'a $$x+1$$ b',
          reason: 'a display equation edited in place must stay display — '
              'writing one pair back silently demoted it');
    });
  });
}
