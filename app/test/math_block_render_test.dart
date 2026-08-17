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
import 'package:openote/math/math_view.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

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
