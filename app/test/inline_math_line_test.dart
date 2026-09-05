// Maths on the SAME LINE as words — what the product owner asked for after
// re-importing his OneNote page: "we cant have maths in the same box and on
// the same line as text… it will have to possibly change the line height of
// the line it is on (not all of them though, just increase the height of that
// one line as required)".
//
// Geometry, not a smoke test. Every assertion here is a measurement taken off
// the laid-out render tree, because the three defects this pins were all
// invisible to "does it render": the equation DID render, in the wrong place,
// at the wrong size.
//
// Ground truth for the numbers is OneNote's own PDF export of "Finite and
// Infinite Countable Sets", where the inline `f(n) = ⟨cases⟩` has
//
//   * prose baseline y = 407.69 pt, prose font 10.82 pt;
//   * the equation's glyphs spanning y 380.3 … 428.0, i.e. centred on 404.15;
//   * so the equation's centre sits 3.54 pt = **0.327 em** ABOVE the baseline
//     of the sentence it is part of — the TeX maths axis, not the middle of
//     the line box;
//   * fraction numerators and denominators at 7.87 pt against 10.82 pt prose,
//     a 0.727 ratio — script size, i.e. `\textstyle`, not `\displaystyle`.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';
import 'package:openote/markdown/md_render.dart';
import 'package:openote/math/math_view.dart';

/// The piecewise equation from the owner's page, as the importer emits it.
const _cases = r'f(n) = \begin{cases}\frac{n}{2} & \text{if } 2 \mid n \\ '
    r'-\frac{n+1}{2} & \text{if } 2 \nmid n\end{cases}';

void main() {
  const base = TextStyle(fontSize: 14, height: 1.2207, color: Colors.black);

  Future<void> pump(WidgetTester tester, String text,
      {double width = 900}) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: MarkdownView(text: text, baseStyle: base),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// A render-object measurement outside layout. `getDistanceToBaseline`
  /// refuses to answer between frames unless this is set, and asking after the
  /// frame is the only way to compare two subtrees against each other.
  T offLayout<T>(T Function() f) {
    RenderObject.debugCheckingIntrinsics = true;
    try {
      return f();
    } finally {
      RenderObject.debugCheckingIntrinsics = false;
    }
  }

  /// The paragraph whose text contains [needle], as laid out.
  RenderParagraph para(WidgetTester tester, String needle) =>
      tester.renderObjectList<RenderParagraph>(find.byType(RichText)).firstWhere(
          (p) => p.text.toPlainText().contains(needle),
          orElse: () => throw StateError('no paragraph containing "$needle"'));

  /// Top-of-paragraph → baseline of its FIRST line, in global coordinates.
  double baselineY(RenderParagraph p) =>
      p.localToGlobal(Offset.zero).dy +
      offLayout(() => p.getDistanceToBaseline(TextBaseline.alphabetic)!);

  /// The single laid-out equation on screen: its global rect and its own
  /// alphabetic baseline.
  ({Rect rect, double baselineY}) maths(WidgetTester tester) {
    final box = tester.renderObject<RenderBox>(find.byType(OnoteMath));
    final o = box.localToGlobal(Offset.zero);
    return (
      rect: o & box.size,
      baselineY:
          o.dy + offLayout(() => box.getDistanceToBaseline(TextBaseline.alphabetic)!),
    );
  }

  /// The LINES of [p], as vertical extents in paragraph-local coordinates.
  ///
  /// `getBoxesForSelection` returns one box per contiguous *run*, not per line
  /// — a sentence with an equation in the middle of it comes back as three
  /// boxes that share a top — so runs are merged by their top edge. Getting
  /// this wrong is how a one-line result reads as three.
  List<({double top, double bottom})> lines(RenderParagraph p) {
    final byTop = <String, ({double top, double bottom})>{};
    final boxes = p.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: p.text.toPlainText().length),
      boxHeightStyle: ui.BoxHeightStyle.max,
    );
    for (final b in boxes) {
      final key = b.top.toStringAsFixed(1);
      final cur = byTop[key];
      byTop[key] = (
        top: cur == null ? b.top : (cur.top < b.top ? cur.top : b.top),
        bottom: cur == null
            ? b.bottom
            : (cur.bottom > b.bottom ? cur.bottom : b.bottom),
      );
    }
    final out = byTop.values.toList()..sort((a, b) => a.top.compareTo(b.top));
    return out;
  }

  double lineHeight(RenderParagraph p) {
    final ls = lines(p);
    return ls.single.bottom - ls.single.top;
  }

  testWidgets('an inline equation sits on the sentence\'s baseline',
      (tester) async {
    // `$x^2$` is the discriminating case, and deliberately so: it is SHORTER
    // than the line, so "centre the box on the middle of the text" and "put
    // the equation on the baseline" give visibly different answers. With the
    // old PlaceholderAlignment.middle the `x` landed on y=31.50 while the
    // words sat on y=29.04 — the equation 0.18em below its own sentence, and
    // sinking further the taller the equation got.
    await pump(tester, r'alpha alpha' '\n' r'beta $x^2$ beta' '\n' 'gamma');
    final m = maths(tester);
    final line = baselineY(para(tester, 'beta'));
    expect((m.baselineY - line).abs(), lessThan(0.5),
        reason: 'the equation must sit ON the line of prose, not below it '
            '(maths baseline ${m.baselineY}, text baseline $line)');
  });

  testWidgets('a tall inline equation raises ONLY its own line', (tester) async {
    // The owner's exact request: "increase the height of that one line as
    // required" — and *not* the others.
    await pump(tester, 'alpha alpha\nbeta beta\ngamma gamma');
    final plainH = lineHeight(para(tester, 'beta'));
    final plainTop = para(tester, 'beta').localToGlobal(Offset.zero).dy;
    final aboveH = lineHeight(para(tester, 'alpha'));
    final belowH = lineHeight(para(tester, 'gamma'));

    await pump(tester, 'alpha alpha\nbeta \$$_cases\$ beta\ngamma gamma');
    final withMaths = para(tester, 'beta');
    final boxes = lines(withMaths);
    expect(boxes.length, 1,
        reason: 'the sentence and its equation must stay on ONE line — this '
            'is the whole complaint, that the equation "got broken out into '
            'its own thing"');
    final tallH = boxes.single.bottom - boxes.single.top;

    expect(tallH, greaterThan(plainH * 1.5),
        reason: 'the line carrying a two-row piecewise equation has to grow '
            'to hold it ($tallH vs $plainH)');
    // The neighbours keep their own heights, and the paragraph above keeps its
    // position: only the line that needed the room took any.
    expect(lineHeight(para(tester, 'alpha')), closeTo(aboveH, 0.01));
    expect(lineHeight(para(tester, 'gamma')), closeTo(belowH, 0.01));
    expect(para(tester, 'alpha').localToGlobal(Offset.zero).dy, 0.0);
    // The growth is taken WHERE IT IS NEEDED: the tall line's own top rises
    // above where a plain line would have started, rather than the equation
    // spilling out of the box and being clipped by it.
    expect(withMaths.localToGlobal(Offset.zero).dy, lessThan(plainTop + 0.01));
  });

  testWidgets('an inline column vector draws, and on the same line',
      (tester) async {
    // Not a hypothetical. Across the owner's 329-page notebook, the importer
    // change that stopped lifting a trailing equation out of its sentence
    // moved exactly six boxes, and five of them are on "M: Eigenvectors and
    // Eigenvalues" — sentences of the shape "so the eigenvector is
    // ⟨column vector⟩". A two-row `\begin{matrix}` inline is therefore the
    // common tall case, not `\begin{cases}`.
    await pump(
        tester,
        'so the eigenvector is '
        r'$\left(\begin{matrix}1 \\ 1\end{matrix}\right)$ here');
    expect(find.byType(MathSourceFallback), findsNothing,
        reason: 'a column vector in a sentence must be drawn, not printed as '
            'LaTeX source among the words');
    final p = para(tester, 'eigenvector');
    expect(lines(p).length, 1, reason: 'sentence and vector share one line');
    final m = maths(tester);
    expect((m.baselineY - baselineY(p)).abs(), lessThan(0.5));
  });

  testWidgets('a tall inline equation is centred on the maths axis',
      (tester) async {
    // 0.327 em above the baseline in OneNote's own export (see the file
    // header). This is what makes a `\begin{cases}` brace look like it belongs
    // to the sentence rather than hanging off it.
    await pump(tester, 'alpha\nbeta \$$_cases\$ beta\ngamma');
    final m = maths(tester);
    final em = base.fontSize!;
    final axisEm = (m.baselineY - m.rect.center.dy) / em;
    expect(axisEm, closeTo(0.327, 0.10),
        reason: 'the equation should straddle the maths axis the way OneNote '
            'sets it; measured ${axisEm}em above the baseline');
  });

  testWidgets('inline maths is set at FULL size — the owner overruled parity',
      (tester) async {
    // This test used to assert the opposite, and the reasoning was sound:
    // OneNote's own export puts inline fractions' numerators at 0.727 of the
    // prose size — script size, i.e. `	extstyle` — so matching it kept an
    // imported note looking like its source.
    //
    // The owner has overruled it on sight: *"everything has now gone to being
    // super small … i want it to still be full size even when inlined with
    // text, even if it ends up being taller than the text (which means we
    // need to account for the increased line height too)"*. Parity with
    // OneNote lost to legibility, which is the right way round for a student
    // reading their own notes.
    Future<double> heightOf({required bool compact}) async {
      await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: OnoteMath(r'rac{n}{2}',
                textStyle: base, compact: compact),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return tester.renderObject<RenderBox>(find.byType(OnoteMath)).size.height;
    }

    final inline = await heightOf(compact: true);
    final display = await heightOf(compact: false);
    expect(inline, display,
        reason: 'the same fraction is the same size wherever it sits '
            '(inline $inline, display $display)');
  });
}
