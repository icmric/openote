// A substitute block: the graph's sibling for one point rather than a curve.
//
// *"would love a way to be able to sub in a value for x or whatever variable
// and get the result, this doesnt have to be linked to the graph though,
// however it needs to be thoughtfully implemented and be clean."* And on
// where the UI for it should live: *"Primarily a dedicated small block ...
// but also id love the ability to inline it too even if its just a
// shortcut."*
//
// This file mirrors `graph_block_test.dart` structure for structure — making
// one, following an equation, surviving a copy/cut/paste, and the widget on
// the page — because a substitute block IS the graph's sibling, built the
// same way for the same reasons.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/substitute_block_view.dart';
import 'package:openote/l10n/l10n.dart';
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
    tmp = Directory.systemTemp.createTempSync('onote_substitute_');
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

  Block equation(String latex) {
    final b = app.insertEquation(at: const Offset(40, 40));
    b.content['latex'] = latex;
    return b;
  }

  group('making one', () {
    test('lands BESIDE the equation, and does not touch it', () {
      if (!haveSqlite) return;
      final eq = equation('y=3x+10');
      final before = Map<String, dynamic>.from(eq.content);
      final s = app.insertSubstitute(latex: 'y=3x+10', from: eq.id);
      expect(s.type, BlockType.substitute);
      expect(s.x, greaterThan(eq.x), reason: 'beside, not on top');
      expect(eq.content, before, reason: 'the equation is untouched');
      expect(s.content['latex'], 'y=3x+10');
      expect(s.content['from'], eq.id);
      app.cancelPendingSave();
    });

    test('it carries its OWN copy of the equation', () {
      if (!haveSqlite) return;
      final eq = equation('y=x^2');
      final s = app.insertSubstitute(latex: 'y=x^2', from: eq.id);
      app.removeBlock(eq.id);
      expect(s.content['latex'], 'y=x^2',
          reason: 'a block that is only a pointer shows nothing the moment '
              'the equation is deleted');
      app.cancelPendingSave();
    });

    test('does not force a height a text field cannot outgrow', () {
      // Reported as its own report: a graph is a canvas and needs a fixed
      // height, but a substitute block is a line of text and a text field —
      // it should hug its content like a text block does, not be handed a
      // resize handle for a height nothing inside it uses.
      if (!haveSqlite) return;
      final eq = equation('y=x');
      final s = app.insertSubstitute(latex: 'y=x', from: eq.id);
      expect(s.h, isNull);
      app.cancelPendingSave();
    });
  });

  group('following', () {
    test('editing the equation updates the substitute block', () {
      if (!haveSqlite) return;
      final eq = equation('y=3x+10');
      final s = app.insertSubstitute(latex: 'y=3x+10', from: eq.id);
      expect(app.pushEquationToSubstitutes(eq.id, 'y=2x+6'), isTrue);
      expect(s.content['latex'], 'y=2x+6');
      app.cancelPendingSave();
    });

    test('a keystroke that changes nothing updates nothing', () {
      if (!haveSqlite) return;
      final eq = equation('y=3x+10');
      app.insertSubstitute(latex: 'y=3x+10', from: eq.id);
      expect(app.pushEquationToSubstitutes(eq.id, 'y=3x+10'), isFalse,
          reason: 'a rebuild of the whole page per keystroke, for nothing');
      app.cancelPendingSave();
    });

    test('a block whose equation is gone keeps showing what it was told', () {
      if (!haveSqlite) return;
      final eq = equation('y=x^2');
      final s = app.insertSubstitute(latex: 'y=x^2', from: eq.id);
      app.removeBlock(eq.id);
      expect(s.content['latex'], 'y=x^2');
      app.cancelPendingSave();
    });

    test('an equation in a SENTENCE is followed by what it says', () {
      if (!haveSqlite) return;
      final para = Block(
          id: 'p1',
          type: BlockType.text,
          x: 0,
          y: 0,
          w: 400,
          content: {'text': r'we know $y=3x$ here'});
      app.blocks.add(para);
      final s =
          app.insertSubstitute(latex: 'y=3x', from: 'p1', fromLatex: 'y=3x');
      expect(app.substitutesFollowingInline('p1', 'y=3x').single.id, s.id);
      expect(
          app.pushInlineEquationToSubstitutes('p1', 'y=3x', 'y=4x'), isTrue);
      expect(s.content['latex'], 'y=4x');
      expect(s.content['fromLatex'], 'y=4x',
          reason: 'the anchor moves with it, so the NEXT keystroke finds the '
              'same block again');
      app.cancelPendingSave();
    });

    test('two blocks following the same words are left alone, not guessed at',
        () {
      // Same ambiguity `pushInlineEquationToGraphs` refuses to resolve: two
      // substitute blocks anchored to the same equation text cannot be told
      // apart, so moving either would be a guess. Neither moves.
      if (!haveSqlite) return;
      final a = app.insertSubstitute(latex: 'y=x', from: 'p1', fromLatex: 'y=x');
      final b = app.insertSubstitute(latex: 'y=x', from: 'p1', fromLatex: 'y=x');
      expect(
          app.pushInlineEquationToSubstitutes('p1', 'y=x', 'y=2x'), isFalse);
      expect(a.content['latex'], 'y=x');
      expect(b.content['latex'], 'y=x');
      app.cancelPendingSave();
    });

    test('a block link and a sentence link never catch each other', () {
      if (!haveSqlite) return;
      final eq = equation('y=x');
      final blockSub = app.insertSubstitute(latex: 'y=x', from: eq.id);
      final inlineSub =
          app.insertSubstitute(latex: 'y=x', from: eq.id, fromLatex: 'y=x');
      expect(
          app.substitutesFollowing(eq.id).map((b) => b.id), [blockSub.id]);
      expect(
          app.substitutesFollowingInline(eq.id, 'y=x').map((b) => b.id),
          [inlineSub.id]);
      app.cancelPendingSave();
    });

    test('a graph and a substitute block on the same equation coexist', () {
      // They are siblings, not rivals: drawing the graph must not stop a
      // student from also plugging in a number, and vice versa.
      if (!haveSqlite) return;
      final eq = equation('y=3x+10');
      final g = app.insertGraph(latex: 'y=3x+10', from: eq.id);
      final s = app.insertSubstitute(latex: 'y=3x+10', from: eq.id);
      app.pushEquationToGraphs(eq.id, 'y=2x+6');
      app.pushEquationToSubstitutes(eq.id, 'y=2x+6');
      expect(g.content['latex'], 'y=2x+6');
      expect(s.content['latex'], 'y=2x+6');
      expect(app.substitutesFollowing(eq.id).map((b) => b.id), [s.id]);
      app.cancelPendingSave();
    });
  });

  group('copying an equation and its substitute block', () {
    test('the copy follows the copy, not the original', () {
      if (!haveSqlite) return;
      final eq = equation('y=3x+10');
      final s = app.insertSubstitute(latex: 'y=3x+10', from: eq.id);
      app.selectMany([eq.id, s.id]);
      app.copySelectedBlocks();
      app.pasteBlocks(at: const Offset(400, 400));

      final subs = app.blocks.where((b) => b.type == BlockType.substitute);
      expect(subs.length, 2);
      final copy = subs.firstWhere((b) => b.id != s.id);
      final copiedEq = app.blocks
          .firstWhere((b) => b.type == BlockType.math && b.id != eq.id);
      expect(copy.content['from'], copiedEq.id);
      expect(app.substitutesFollowing(eq.id).length, 1,
          reason: 'the original still has exactly its own');

      app.pushEquationToSubstitutes(copiedEq.id, 'y=2x+6');
      expect(copy.content['latex'], 'y=2x+6');
      expect(s.content['latex'], 'y=3x+10',
          reason: 'and the first worked example is left alone');
      app.cancelPendingSave();
    });

    test('cutting an equation and pasting it back keeps its block', () {
      if (!haveSqlite) return;
      final eq = equation('y=3x+10');
      final s = app.insertSubstitute(latex: 'y=3x+10', from: eq.id);
      app.selectMany([eq.id]);
      app.cutSelectedBlocks();
      app.pasteBlocks(at: const Offset(40, 40));

      final back = app.blocks.firstWhere((b) => b.type == BlockType.math);
      expect(back.id, isNot(eq.id));
      expect(s.content['from'], back.id);
      app.pushEquationToSubstitutes(back.id, 'y=99');
      expect(s.content['latex'], 'y=99');
      app.cancelPendingSave();
    });
  });

  group('the block on the page', () {
    Future<void> pump(WidgetTester tester, Block s) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: app,
            builder: (_, __) => Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                  width: 260, child: SubstituteBlockView(block: s, app: app)),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the equation and asks for a value', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final s = app.insertSubstitute(latex: 'y=3x+10');
      await pump(tester, s);
      expect(find.byType(TextField), findsOneWidget);
      // Names what it is waiting for rather than saying "enter a value",
      // which with several fields does not say WHICH.
      expect(find.text('enter x'), findsOneWidget);
      app.cancelPendingSave();
    });

    testWidgets('typing a value shows the worked-out result', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final s = app.insertSubstitute(latex: 'y=3x+10');
      await pump(tester, s);
      await tester.enterText(find.byType(TextField), '2');
      await tester.pump();
      // Named, not a bare `= 16`: *"ensure the answer is clear, as at the
      // moment its not super clear to me."*
      expect(find.text('y = 16'), findsOneWidget);
      app.cancelPendingSave();
    });

    testWidgets('the typed value is kept for next time', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final s = app.insertSubstitute(latex: 'y=3x+10');
      await pump(tester, s);
      await tester.enterText(find.byType(TextField), '2');
      await tester.pump();
      expect(s.content['values'], {'x': '2'},
          reason: 'keyed by name, because there can be more than one now');
      app.cancelPendingSave();
    });

    testWidgets('and one name keeps the old spelling in step', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The same notebook opened by a v1.0.1 build, which reads `value` and
      // knows nothing of `values`. Reading both spellings stops v1.0.2
      // losing what v1.0.1 wrote; this is the other direction.
      final s = app.insertSubstitute(latex: 'y=3x+10');
      await pump(tester, s);
      await tester.enterText(find.byType(TextField), '2');
      await tester.pump();
      expect(s.content['value'], '2',
          reason: 'a v1.0.1 build can still show this');
      expect(s.content['values'], {'x': '2'});
      app.cancelPendingSave();
    });

    testWidgets('and several names do not pretend to', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // `value` never recorded WHICH variable it was, and a v1.0.1 build
      // labels whatever it finds `x`. It cannot evaluate a formula with
      // several names anyway, so there is nothing to be in step with — and
      // writing one of them there would be a number under the wrong label.
      final s = app.insertSubstitute(latex: 'v=u+a*t');
      await pump(tester, s);
      await tester.enterText(find.byType(TextField).at(0), '2');
      await tester.pump();
      expect(s.content['value'], '',
          reason: 'left exactly as insertSubstitute made it');
      expect(s.content['values'], {'u': '2'});
      app.cancelPendingSave();
    });

    testWidgets('a value stored the pre-v1.0.2 way still shows', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // One string under `value`, which is all a block could hold before the
      // equation was allowed more than one name. Read, not rewritten — so a
      // v1.0.1 build opening the same notebook still shows it.
      final s = app.insertSubstitute(latex: 'y=3x+10');
      s.content.remove('values');
      s.content['value'] = '2';
      await pump(tester, s);
      expect(find.text('y = 16'), findsOneWidget);
      expect(s.content.containsKey('values'), isFalse,
          reason: 'reading a notebook is not editing it');
      app.cancelPendingSave();
    });

    testWidgets('and touching a field commits the migrated reading',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final s = app.insertSubstitute(latex: 'v=u+a*t');
      s.content.remove('values');
      s.content['value'] = '2';
      await pump(tester, s);
      // `2` was the only value an old block had, so it belongs to the first
      // name — u — and typing into `a` must not lose it.
      await tester.enterText(find.byType(TextField).at(1), '3');
      await tester.pump();
      expect(s.content['values'], {'u': '2', 'a': '3'});
      app.cancelPendingSave();
    });

    testWidgets('an invalid value is an error, not a crash', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final s = app.insertSubstitute(latex: 'y=3x+10');
      await pump(tester, s);
      await tester.enterText(find.byType(TextField), '+');
      await tester.pump();
      expect(find.text('y = 16'), findsNothing);
      expect(tester.takeException(), isNull);
      app.cancelPendingSave();
    });

    testWidgets('a formula with three names gets three fields', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The whole point: *"its unable to handle multi variable stuff at the
      // moment."* Before this, `v=u+a*t` showed one field labelled `x =` and
      // the error `unknown "u"` where the answer should be.
      final s = app.insertSubstitute(latex: 'v=u+a*t');
      await pump(tester, s);
      expect(find.byType(TextField), findsNWidgets(3));
      expect(find.text('u ='), findsOneWidget);
      expect(find.text('a ='), findsOneWidget);
      expect(find.text('t ='), findsOneWidget);
      expect(find.text('enter u, a and t'), findsOneWidget);
      app.cancelPendingSave();
    });

    testWidgets('filling them in works it out', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final s = app.insertSubstitute(latex: 'v=u+a*t');
      await pump(tester, s);
      await tester.enterText(find.byType(TextField).at(0), '2');
      await tester.enterText(find.byType(TextField).at(1), '3');
      await tester.enterText(find.byType(TextField).at(2), '4');
      await tester.pump();
      expect(find.text('v = 14'), findsOneWidget);
      expect(s.content['values'], {'u': '2', 'a': '3', 't': '4'});
      app.cancelPendingSave();
    });

    testWidgets('a partly filled block says what it is still waiting for',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The common state for a block with three fields, and not an error.
      final s = app.insertSubstitute(latex: 'v=u+a*t');
      await pump(tester, s);
      await tester.enterText(find.byType(TextField).at(1), '3');
      await tester.pump();
      expect(find.text('enter u and t'), findsOneWidget);
      app.cancelPendingSave();
    });

    testWidgets('editing the equation keeps the values that still apply',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // An equation can change under a block that is on screen — a graph and
      // a substitute both follow theirs live. Fields are keyed by name so the
      // ones that survive keep their numbers.
      final s = app.insertSubstitute(latex: 'A=l*w');
      await pump(tester, s);
      await tester.enterText(find.byType(TextField).at(0), '3');
      await tester.enterText(find.byType(TextField).at(1), '7');
      await tester.pump();
      expect(find.text('A = 21'), findsOneWidget);

      s.content['latex'] = 'A=l*w*h';
      app.refreshChrome();
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(3));
      expect(tester.widget<TextField>(find.byType(TextField).at(0)).controller
              ?.text, '3',
          reason: 'l kept what was typed into it');
      expect(find.text('enter h'), findsOneWidget);
      app.cancelPendingSave();
    });

    testWidgets('a formula needing nothing just shows its value',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // `x = 3` used to be refused with the GRAPHER's words — "a vertical
      // line has no value to work out" — because a substitute block borrowed
      // the grapher's reading whole. Read as a formula it has no names to
      // fill in and the answer is simply 3.
      final s = app.insertSubstitute(latex: 'x=3');
      await pump(tester, s);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('x = 3'), findsOneWidget);
      app.cancelPendingSave();
    });

    testWidgets('editing the followed equation updates the display live',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final eq = equation('y=3x+10');
      final s = app.insertSubstitute(latex: 'y=3x+10', from: eq.id);
      await pump(tester, s);
      await tester.enterText(find.byType(TextField), '2');
      await tester.pump();
      expect(find.text('y = 16'), findsOneWidget);

      app.pushEquationToSubstitutes(eq.id, 'y=2x+6');
      await tester.pump();
      expect(find.text('y = 10'), findsOneWidget);
      app.cancelPendingSave();
    });

    testWidgets('an equation whose block was removed says so', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final s = app.insertSubstitute(latex: '');
      await pump(tester, s);
      expect(find.textContaining('Nothing to evaluate'), findsOneWidget);
      app.cancelPendingSave();
    });
  });
}
