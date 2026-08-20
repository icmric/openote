// Editing a sentence that has an equation in it (plan: v0.18 §7).
//
// Reading was already right — `bbe9d30` put inline maths on the sentence's own
// baseline. This is the other half: while the box is being EDITED the equation
// has to stay an equation, the caret has to cross it in one step, and there has
// to be a way back into it. The last of those is not a nicety: drawing the
// equation instead of its source is what stops the caret walking inside, so
// without a click-in path this change would have made inline maths read-only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/inline_math_editor.dart';
import 'package:openote/editor/live_markdown_controller.dart';
import 'package:openote/markdown/md_render.dart';
import 'package:openote/markdown/md_syntax.dart';
import 'package:openote/math/math_view.dart';

void main() {
  LiveMarkdownController make(String text) =>
      LiveMarkdownController(text: text, dark: false);

  Future<void> pump(WidgetTester tester, LiveMarkdownController c) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 600,
          child: TextField(controller: c, maxLines: null),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('an equation in a sentence stays an equation while editing',
      (tester) async {
    final c = make(r'We define $\frac{n}{2}$ here');
    await pump(tester, c);
    expect(find.byType(OnoteMath), findsOneWidget,
        reason: 'the reported defect: clicking the box turned the fraction '
            'back into backslashes');
    expect(find.byType(MathSourceFallback), findsNothing);
  });

  testWidgets('and the buffer is untouched — every caret offset survives',
      (tester) async {
    const src = r'We define $\frac{n}{2}$ here';
    final c = make(src);
    await pump(tester, c);
    // The placeholder stands for ONE code unit and the rest trails hidden, so
    // the paragraph has exactly as many code units as the text. If this ever
    // drifts, clicking lands the caret in the wrong place across the whole
    // block, which is invisible until a student loses a word.
    expect(c.text, src);
    expect(c.text.length, src.length);
  });

  testWidgets('the caret crosses the equation in ONE step', (tester) async {
    const src = r'a $x^2$ b';
    final c = make(src);
    await pump(tester, c);
    // `$` is at 2, the closing `$` at 6, so 3..7 is the invisible remainder.
    final hidden = c.hiddenMarkerRanges();
    expect(hidden.any((r) => r.start == 3 && r.end == 7), isTrue,
        reason: 'without this the arrow keys die twelve times inside a '
            'fraction nobody can see');
  });

  testWidgets('tapping the equation asks to edit it, with its own rect',
      (tester) async {
    final c = make(r'We define $\frac{n}{2}$ here');
    int? gotStart, gotEnd;
    String? gotLatex;
    Rect? gotRect;
    c.onMathTap = (s, e, latex, rect) {
      gotStart = s;
      gotEnd = e;
      gotLatex = latex;
      gotRect = rect;
    };
    await pump(tester, c);
    await tester.tap(find.byType(OnoteMath));
    await tester.pumpAndSettle();

    expect(gotLatex, r'\frac{n}{2}');
    expect(gotStart, 10, reason: 'the opening dollar');
    expect(gotEnd, 23, reason: 'one past the closing dollar');
    expect(c.text.substring(gotStart!, gotEnd!), r'$\frac{n}{2}$');
    expect(gotRect, isNotNull);
    expect(gotRect!.width, greaterThan(0),
        reason: 'the editor anchors to this rect — a zero rect puts the card '
            'in the corner of the screen');
  });

  group('writing an edit back into the sentence', () {
    test('replaces exactly the equation and nothing around it', () {
      final c = make(r'We define $\frac{n}{2}$ here');
      var saved = 0;
      c.onSelfEdit = () => saved++;
      c.replaceMathAt(10, 23, r'\frac{n+1}{2}');
      expect(c.text, r'We define $\frac{n+1}{2}$ here');
      expect(saved, 1, reason: 'a programmatic edit never fires onChanged, so '
          'without this the change draws and is then lost');
    });

    test('an emptied equation takes its dollars with it', () {
      final c = make(r'We define $x$ here');
      c.replaceMathAt(10, 13, '');
      expect(c.text, 'We define  here');
      expect(c.text, isNot(contains(r'$')),
          reason: 'a stray dollar left behind would start eating the sentence');
    });

    test('a nonsense range is ignored rather than corrupting the note', () {
      final c = make(r'$x$');
      c.replaceMathAt(-1, 99, 'y');
      expect(c.text, r'$x$');
    });
  });

  group('an equation you have started but not written', () {
    // The owner: "It shows the $$ around it while its in that mode ... id like
    // to make it super clean and not have random things popup as this would be
    // jarring to a user who doesnt know LaTeX or markdown."
    //
    // Alt+= writes `$$` at the caret so the equation has somewhere to live.
    // Without a grammar branch for it the live editor drew whatever it could
    // not classify as literal source — two dollar signs, mid-sentence.

    testWidgets('draws a box to type in, not two dollar signs', (tester) async {
      final c = make(r'the area is $$ here');
      await pump(tester, c);
      // ONE atom, drawn — not two dollars printed as text.
      expect(find.byType(OnoteMath), findsOneWidget);
      expect(find.byType(MathSourceFallback), findsNothing);
      // …and the buffer keeps every code unit, as ever.
      expect(c.text, r'the area is $$ here');
    });

    test('the grammar recognises the empty pair', () {
      final m = mdInlineRe.firstMatch(r'the area is $$ here');
      expect(m, isNotNull);
      expect(classifyInline(m!).kind, MdInline.mathEmpty);
      expect(classifyInline(m).inner, '');
    });

    test('and it declines where a real equation could match', () {
      // `$$x$$` is a DISPLAY equation now — both pairs one match (v0.20 D.5).
      // Before that grammar existed, the single-dollar form took the inner
      // pair and left a literal stray dollar on each side the moment the
      // caret entered the block.
      final m = mdInlineRe.firstMatch(r'$$x$$');
      final c = classifyInline(m!);
      expect(c.kind, MdInline.mathDisplay,
          reason: 'a display equation must be read whole, never as an empty '
              'pair plus scraps');
      expect(c.inner, 'x');
      expect(m.start, 0);
      expect(m.end, r'$$x$$'.length,
          reason: 'BOTH dollar pairs belong to the match');
    });

    test('an empty equation reads as NOTHING, never as dollars', () {
      // It should never survive to a saved note — the editor sweeps it on the
      // way out — but if one does, a reader sees nothing rather than `$$`.
      final spans =
          inlineSpans(r'a $$ b', const TextStyle(fontSize: 14), false);
      final text = spans.whereType<TextSpan>().map((s) => s.text ?? '').join();
      expect(text, isNot(contains(r'$$')));
    });
  });

  group('the dollar guard (§6.7)', () {
    test('two prices in one sentence stay a sentence', () {
      // Measured against the old pattern before it was changed: this matched
      // `$5 and lunch is $` and set a student's lunch order as an equation.
      const line = r'coffee is $5 and lunch is $10 today';
      expect(mdInlineRe.firstMatch(line), isNull);
    });

    testWidgets('…and it draws as prose, not as maths', (tester) async {
      final c = make(r'coffee is $5 and lunch is $10 today');
      await pump(tester, c);
      expect(find.byType(OnoteMath), findsNothing);
    });

    test('real maths still matches', () {
      for (final line in [r'$x^2$', r'a $\frac{1}{2}$ b', r'$2 \times 3$']) {
        expect(mdInlineRe.firstMatch(line), isNotNull, reason: line);
      }
    });

    test('a dollar with no partner is just a dollar', () {
      expect(mdInlineRe.firstMatch(r'the price is $5.'), isNull);
      expect(mdInlineRe.firstMatch(r'I paid $12. Then $3 more.'), isNull);
    });
  });

  testWidgets('InlineMathAtom without a tap handler is still just an equation',
      (tester) async {
    // Read-only surfaces pass no handler; the maths must still draw.
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: InlineMathAtom(
            latex: r'\frac{1}{2}', style: TextStyle(fontSize: 14)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(OnoteMath), findsOneWidget);
  });
}
