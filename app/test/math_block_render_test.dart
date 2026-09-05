// A math block on the page must draw the equation it stores — including the
// piecewise `\begin{cases}` layout from the imported OneNote note, and the
// multi-line environments the renderer lacks natively.
//
// This is the WIRING, tested through the real block widget: latex_compat_test
// proves the rewrite is correct, and this proves the block actually uses it.
// A rewriter nothing calls fixes nothing.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/math_block_view.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/markdown/md_render.dart';
import 'package:openote/math/math_view.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

/// The piecewise equation from "Finite and Infinite Countable Sets", exactly as
/// `dump_one --import` writes it: a deliberately MISMATCHED delimiter pair
/// (OneNote stores begChr '(' with endChr '|', which is why its own PDF prints
/// "(2 | n)"), a U+2212 minus rather than a hyphen, and a U+2224 "does not
/// divide".
const kImportedPiecewiseTex =
    r'\begin{cases}\frac{n}{2}\text{ if }\left(2\right| n) '
    r'\\ −\left(\frac{n+1}{2}\right)\text{if }(2∤n)'
    r'\end{cases}';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_mathview_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('T');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
  });

  tearDown(() {
    AppState.syncLogEnabled = true;
    if (!haveSqlite) return;
    app.cancelPendingSave();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pump(WidgetTester tester, String latex) async {
    final b = Block(
        type: BlockType.math,
        x: 0,
        y: 0,
        w: 420,
        content: {'latex': latex, 'display': true});
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 420, child: MathBlockView(block: b, app: app)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// The block fell back to showing source instead of drawing the equation.
  bool fellBack() => find.byType(MathSourceFallback).evaluate().isNotEmpty;

  testWidgets('the imported OneNote piecewise equation draws', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // The one from "Finite and Infinite Countable Sets": one tall brace, two
    // stacked rows. This is what the product owner reported as unrendered.
    await pump(
        tester,
        r'f(n) = \begin{cases} \frac{n}{2} & \text{if } (2 \mid n) \\ '
        r'-\left(\frac{n+1}{2}\right) & \text{if } (2 \nmid n) \end{cases}');
    expect(fellBack(), isFalse,
        reason: 'a cases equation must be drawn, not printed as source');
  });

  testWidgets('an align environment draws', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // `align` does not exist in this renderer; the block rewrites it first.
    await pump(tester, r'\begin{align} a &= b \\ c &= d \end{align}');
    expect(fellBack(), isFalse);
  });

  testWidgets(r'an equation stored with its $ delimiters still draws',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // How maths arrives from an import that writes it into Markdown text.
    await pump(tester, r'$\frac{n}{2}$');
    expect(fellBack(), isFalse);
  });

  testWidgets('the exact piecewise LaTeX the OneNote importer emits draws',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // The seam between two halves that were built separately: the importer
    // decodes OneNote's maths-object kinds into this string, and the renderer
    // has to take it. Neither side's own tests cross that line, and the
    // string carries three things worth pinning — a deliberately MISMATCHED
    // delimiter pair (OneNote really does store begChr '(' with endChr '|',
    // which is why its own PDF prints "(2 | n)"), a U+2212 minus rather than
    // a hyphen, and a U+2224 "does not divide". Copied verbatim from the
    // importer's output for the owner's "Finite and Infinite Countable Sets"
    // page, the equation that started this.
    await pump(tester, kImportedPiecewiseTex);
    expect(fellBack(), isFalse,
        reason: 'the importer and the renderer must meet: if this falls back, '
            'a student sees LaTeX source where OneNote showed a brace');
  });

  testWidgets('…and draws INLINE, in the sentence the importer now leaves it in',
      (tester) async {
    // **The seam moved, so this follows it.** The importer used to lift this
    // equation out of "We can define the bijection f(n) = …" into a maths
    // block of its own; measured against OneNote's own PDF export of the page
    // (prose baseline y=407.69 ending at x=246.3, equation glyphs starting at
    // x=252.9 on that same baseline) that was wrong, and the owner reported it
    // as "it got broken out into its own thing". The importer now emits the
    // whole paragraph as ONE text line with `$…$` in it, so the string above
    // has to survive the INLINE path too — a different code path in
    // md_render.dart, with a different `MathStyle`, which is exactly the kind
    // of gap the original seam test was written to close.
    //
    // Verbatim from `dump_one --import` on the owner's file, markers and all:
    // the bullet, the sentence, then the equation between two dollars.
    const markdown =
        '  - We can define the bijection f(n) = \$$kImportedPiecewiseTex\$';
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: const SizedBox(
            width: 900,
            child: MarkdownView(
              text: markdown,
              baseStyle: TextStyle(fontSize: 14, color: Colors.black),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(OnoteMath), findsOneWidget,
        reason: 'the `\$…\$` the importer writes has to be recognised as maths '
            'at all — raw dollars on the page is the reported defect');
    expect(fellBack(), isFalse,
        reason: 'inline is now where this equation LIVES; falling back here '
            'puts backslashes in the middle of the student\'s sentence');
  });

  testWidgets('an equation nothing can draw shows its source AND a reason',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    const tex = r'\sideset{_a^b}{_c^d}\sum';
    await pump(tester, tex);
    expect(fellBack(), isTrue);
    expect(find.text(tex), findsOneWidget,
        reason: 'the maths is stored fine — the student must still see it');
    expect(find.textContaining('saved exactly as it was written'),
        findsOneWidget,
        reason: 'silence here reads as "the app ate my equation"');
  });
}
