// A graph on the page, and the equation it follows (owner, v0.23 B15-B18).
//
// *"have it insert a graph, not touching the written equation but inserting a
// new graph element on the page which i can move around seperatley but is
// still tied to that equation (so if i then update it to y = 2x+6 that change
// is reflected in the graph)."*
//
// And the rule for showing the link, which is the half most easily got wrong:
// *"should ONLY EVER be visible when one is clicked AND there is a linked
// graph, i dont want the highlighting to be always there."*
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/graph_block_view.dart';
import 'package:openote/math/graph_plot.dart';
import 'package:flutter/gestures.dart';
import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/tokens.dart';

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
    tmp = Directory.systemTemp.createTempSync('onote_graph_');
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

  group('reading an equation as something to draw', () {
    test('y = f(x) is the right hand side', () {
      final g = graphSourceFromLinear('y=3x+10');
      expect(g.isOk, isTrue);
      expect(g.fn!.at!(2), 16);
    });

    test('any name on the left works, because the name changes nothing', () {
      for (final left in ['y', 'h', 'f(x)', 'g(x)']) {
        final g = graphSourceFromLinear('$left=x^2');
        expect(g.isOk, isTrue, reason: left);
        expect(g.fn!.at!(3), 9, reason: left);
      }
    });

    test('an expression on its own is the curve itself', () {
      expect(graphSourceFromLinear('2x-1').fn!.at!(4), 7);
    });

    test('x = 3 is a vertical line, which is not a function of x', () {
      final g = graphSourceFromLinear('x=3');
      expect(g.isOk, isTrue);
      expect(g.verticalAt, 3);
      expect(g.fn, isNull);
    });

    test('x on both sides is an equation to solve, and says so', () {
      final g = graphSourceFromLinear('x^2+y=x');
      expect(g.isOk, isFalse);
      expect(g.error, contains('solve'));
    });

    test('and it reads the LaTeX the editor actually stores', () {
      final g = graphSourceFromLatex(r'y=3x+10');
      expect(g.isOk, isTrue);
      expect(g.fn!.at!(0), 10);
      final q = graphSourceFromLatex(r'y=\frac{1}{x}');
      expect(q.isOk, isTrue);
      expect(q.fn!.at!(4), 0.25);
    });

    test('nothing to graph says so in plain words', () {
      expect(graphSourceFromLatex('').error, 'nothing to graph yet');
      expect(graphSourceFromLatex(r'\begin{pmatrix}1\\2\end{pmatrix}').isOk,
          isFalse);
    });
  });

  group('making one', () {
    test('a graph lands BESIDE the equation, and does not touch it', () {
      if (!haveSqlite) return;
      final eq = equation('y=3x+10');
      final before = Map<String, dynamic>.from(eq.content);
      final g = app.insertGraph(latex: 'y=3x+10', from: eq.id);
      expect(g.type, BlockType.graph);
      expect(g.x, greaterThan(eq.x), reason: 'beside, not on top');
      expect(eq.content, before, reason: 'the equation is untouched');
      expect(g.content['latex'], 'y=3x+10');
      expect(g.content['from'], eq.id);
      app.cancelPendingSave();
    });

    test('it carries its OWN copy of the equation', () {
      if (!haveSqlite) return;
      final eq = equation('y=x^2');
      final g = app.insertGraph(latex: 'y=x^2', from: eq.id);
      app.removeBlock(eq.id);
      expect(g.content['latex'], 'y=x^2',
          reason: 'a graph that is only a pointer draws nothing the moment '
              'the equation is deleted, and exports as an empty box');
      app.cancelPendingSave();
    });
  });

  group('following', () {
    test('editing the equation redraws the graph', () {
      if (!haveSqlite) return;
      final eq = equation('y=3x+10');
      final g = app.insertGraph(latex: 'y=3x+10', from: eq.id);
      expect(app.pushEquationToGraphs(eq.id, 'y=2x+6'), isTrue);
      expect(g.content['latex'], 'y=2x+6');
      app.cancelPendingSave();
    });

    test('and a keystroke that changes nothing redraws nothing', () {
      if (!haveSqlite) return;
      final eq = equation('y=3x+10');
      app.insertGraph(latex: 'y=3x+10', from: eq.id);
      expect(app.pushEquationToGraphs(eq.id, 'y=3x+10'), isFalse,
          reason: 'a rebuild of the whole page per keystroke, for nothing');
      app.cancelPendingSave();
    });

    test('a graph whose equation is gone keeps drawing what it was told', () {
      if (!haveSqlite) return;
      final eq = equation('y=x^2');
      final g = app.insertGraph(latex: 'y=x^2', from: eq.id);
      app.removeBlock(eq.id);
      expect(app.graphLinkHighlight(g), isNull,
          reason: 'no link left, so nothing to show');
      expect(g.content['latex'], 'y=x^2');
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
      final g =
          app.insertGraph(latex: 'y=3x', from: 'p1', fromLatex: 'y=3x');
      expect(app.graphsFollowingInline('p1', 'y=3x').single.id, g.id);
      // The paragraph is edited: the equation becomes y=4x.
      expect(app.pushInlineEquationToGraphs('p1', 'y=3x', 'y=4x'), isTrue);
      expect(g.content['latex'], 'y=4x');
      expect(g.content['fromLatex'], 'y=4x',
          reason: 'the anchor moves with it, so the NEXT keystroke finds the '
              'same graph again');
      app.cancelPendingSave();
    });

    test('and a block link and a sentence link never catch each other', () {
      if (!haveSqlite) return;
      final eq = equation('y=x');
      final blockGraph = app.insertGraph(latex: 'y=x', from: eq.id);
      final inlineGraph =
          app.insertGraph(latex: 'y=x', from: eq.id, fromLatex: 'y=x');
      expect(app.graphsFollowing(eq.id).map((b) => b.id), [blockGraph.id]);
      expect(app.graphsFollowingInline(eq.id, 'y=x').map((b) => b.id),
          [inlineGraph.id]);
      app.cancelPendingSave();
    });
  });

  group('the link is shown only when it should be', () {
    test('never, when nothing is selected', () {
      if (!haveSqlite) return;
      final eq = equation('y=x');
      final g = app.insertGraph(latex: 'y=x', from: eq.id);
      app.select(null);
      expect(app.graphLinkHighlight(g), isNull);
      expect(app.graphLinkHighlight(eq), isNull);
      app.cancelPendingSave();
    });

    test('both ends light up when the GRAPH is selected', () {
      if (!haveSqlite) return;
      final eq = equation('y=x');
      final g = app.insertGraph(latex: 'y=x', from: eq.id);
      app.select(g.id);
      expect(app.graphLinkHighlight(g), kGraphLinkColour);
      expect(app.graphLinkHighlight(eq), kGraphLinkColour);
      app.cancelPendingSave();
    });

    test('and when the EQUATION is selected, which is the other way round', () {
      if (!haveSqlite) return;
      final eq = equation('y=x');
      final g = app.insertGraph(latex: 'y=x', from: eq.id);
      app.select(eq.id);
      expect(app.graphLinkHighlight(g), kGraphLinkColour);
      expect(app.graphLinkHighlight(eq), kGraphLinkColour);
      app.cancelPendingSave();
    });

    test('an equation with no graph never lights up', () {
      if (!haveSqlite) return;
      final eq = equation('y=x');
      app.select(eq.id);
      expect(app.graphLinkHighlight(eq), isNull,
          reason: 'there must be a link AND a selection; this has one');
      app.cancelPendingSave();
    });

    test('and a block that is neither is never asked to', () {
      if (!haveSqlite) return;
      final eq = equation('y=x');
      app.insertGraph(latex: 'y=x', from: eq.id);
      final other = app.addBlock(Block(
          type: BlockType.text, x: 0, y: 300, w: 200, content: {'text': 'hi'}));
      app.select(other.id);
      expect(app.graphLinkHighlight(other), isNull);
      app.cancelPendingSave();
    });

    test('an equation in a sentence lights up with its graph too', () {
      if (!haveSqlite) return;
      final g =
          app.insertGraph(latex: 'y=3x', from: 'p1', fromLatex: 'y=3x');
      app.select(g.id);
      expect(app.inlineGraphTint('p1', 'y=3x'), kGraphLinkColour);
      expect(app.inlineGraphTint('p1', 'y=9x'), isNull,
          reason: 'a different equation in the same paragraph is not this one');
      app.select(null);
      expect(app.inlineGraphTint('p1', 'y=3x'), isNull);
      expect(app.inlineGraphTint('p1', 'y=3x', editing: true),
          kGraphLinkColour,
          reason: 'the equation being written is the one being looked at');
      app.cancelPendingSave();
    });
  });

  group('the block on the page', () {
    Future<void> pump(WidgetTester tester, Block g) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: app,
            builder: (_, __) => Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                  width: 360,
                  height: 260,
                  child: GraphBlockView(block: g, app: app)),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('draws a curve', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final g = app.insertGraph(latex: 'y=x^{2}');
      await pump(tester, g);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.textContaining('cannot'), findsNothing);
      app.cancelPendingSave();
    });

    testWidgets('and says why when it cannot', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final g = app.insertGraph(latex: 'y=3z+1');
      await pump(tester, g);
      expect(find.textContaining('z'), findsOneWidget,
          reason: 'the calculator would have named the unknown, so this does');
      app.cancelPendingSave();
    });

    testWidgets('the window it is looking through survives being stored',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final g = app.insertGraph(latex: 'y=x');
      g.content['view'] =
          const GraphView(x0: -2, x1: 2, y0: -1, y1: 1).toJson();
      g.content['fitY'] = false;
      await pump(tester, g);
      expect(GraphView.fromJson(g.content['view']).x0, -2,
          reason: 'pan and zoom live in the content, not in the widget: an '
              'undo anywhere on the page rebuilds every block widget');
      app.cancelPendingSave();
    });

    testWidgets('a fitted graph does not WRITE the window it chose',
        (tester) async {
      // Looking at a graph is not editing it. The fit reads the samples and
      // the number of samples follows the canvas zoom, so storing the fitted
      // window turned scrolling around a page into an edit: a bumped
      // timestamp, a save, and a git commit for a change nobody made. The
      // window it drew in is remembered in the widget instead, which is all
      // the next drag needs.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final g = app.insertGraph(latex: 'y=x^{2}');
      app.cancelPendingSave();
      final stamp = g.updatedAt;
      expect(g.content['view'], isNull);

      await pump(tester, g);
      await tester.pump(const Duration(milliseconds: 20));

      expect(g.content['view'], isNull, reason: 'nothing was written');
      expect(g.updatedAt, stamp, reason: 'and nothing was timestamped');
      expect(g.content['fitY'], isNot(false),
          reason: 'fitting it is not the student saying where to look');
      app.cancelPendingSave();
    });

    // `AppState.graphLinkHighlight` already returns the link colour "when the
    // EQUATION is selected, which is the other way round" (see the state-level
    // group above) — that function was never wrong. This widget was: it
    // additionally required the GRAPH itself to be selected before it would
    // paint what `graphLinkHighlight` told it, so the border only ever lit up
    // in one of the two directions the owner asked for.
    Border borderOf(WidgetTester tester) => (tester
            .widget<Container>(find
                .descendant(
                    of: find.byType(GraphBlockView), matching: find.byType(Container))
                .first)
            .decoration as BoxDecoration)
        .border as Border;

    testWidgets('the border lights up when the GRAPH is selected',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final eq = equation('y=3x+10');
      final g = app.insertGraph(
          latex: 'y=3x+10', from: eq.id, at: const Offset(500, 40));
      await pump(tester, g);

      app.select(g.id);
      await tester.pump();
      expect(borderOf(tester).top.width, 2,
          reason: 'the direction this always worked in');
      expect(borderOf(tester).top.color, kGraphLinkColour);
      app.cancelPendingSave();
    });

    testWidgets(
        "the border lights up when the EQUATION is selected — the other way round",
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final eq = equation('y=3x+10');
      final g = app.insertGraph(
          latex: 'y=3x+10', from: eq.id, at: const Offset(500, 40));
      await pump(tester, g);

      app.select(eq.id);
      await tester.pump();
      expect(borderOf(tester).top.width, 2,
          reason: 'this is the direction the AND-with-local-selection bug '
              'broke: the graph never heard that its own equation was chosen');
      expect(borderOf(tester).top.color, kGraphLinkColour);
      app.cancelPendingSave();
    });

    testWidgets('and plain, no-link border otherwise', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final eq = equation('y=3x+10');
      final g = app.insertGraph(
          latex: 'y=3x+10', from: eq.id, at: const Offset(500, 40));
      await pump(tester, g);

      app.select(null);
      await tester.pump();
      expect(borderOf(tester).top.width, 1);
      expect(borderOf(tester).top.color, isNot(kGraphLinkColour));
      app.cancelPendingSave();
    });
  });

  group('copying an equation and its graph', () {
    // The copy has to follow the COPY. It used to follow the original, so
    // "now do the same one with different numbers" — select both, Ctrl+C,
    // Ctrl+V, change the numbers — moved nothing at all, and changing the
    // first worked example silently rewrote the second graph as well.
    test('the copy follows the copy, not the original', () {
      if (!haveSqlite) return;
      final eq = equation('y=3x+10');
      final g = app.insertGraph(latex: 'y=3x+10', from: eq.id);
      app.selectMany([eq.id, g.id]);
      app.copySelectedBlocks();
      app.pasteBlocks(at: const Offset(400, 400));

      final graphs = app.blocks.where((b) => b.type == BlockType.graph);
      expect(graphs.length, 2);
      final copy = graphs.firstWhere((b) => b.id != g.id);
      final copiedEq = app.blocks.firstWhere(
          (b) => b.type == BlockType.math && b.id != eq.id);
      expect(copy.content['from'], copiedEq.id);
      expect(app.graphsFollowing(eq.id).length, 1,
          reason: 'the original still has exactly its own');

      copiedEq.content['latex'] = 'y=2x+6';
      app.pushEquationToGraphs(copiedEq.id, 'y=2x+6');
      expect(copy.content['latex'], 'y=2x+6');
      expect(g.content['latex'], 'y=3x+10',
          reason: 'and the first worked example is left alone');
      app.cancelPendingSave();
    });

    test('cutting an equation and pasting it back keeps its graph', () {
      if (!haveSqlite) return;
      final eq = equation('y=3x+10');
      final g = app.insertGraph(latex: 'y=3x+10', from: eq.id);
      app.selectMany([eq.id]);
      app.cutSelectedBlocks();
      app.pasteBlocks(at: const Offset(40, 40));

      final back = app.blocks.firstWhere((b) => b.type == BlockType.math);
      expect(back.id, isNot(eq.id), reason: 'a paste is a new block');
      expect(g.content['from'], back.id,
          reason: 'the graph was pointing at an id that no longer exists');
      app.pushEquationToGraphs(back.id, 'y=99');
      expect(g.content['latex'], 'y=99');
      app.cancelPendingSave();
    });

    test('a graph copied on its own still follows the same equation', () {
      // Two windows onto one equation is a thing people want — one zoomed
      // in, one zoomed out — so this one is deliberately left alone.
      if (!haveSqlite) return;
      final eq = equation('y=3x+10');
      final g = app.insertGraph(latex: 'y=3x+10', from: eq.id);
      app.selectMany([g.id]);
      app.copySelectedBlocks();
      app.pasteBlocks(at: const Offset(400, 400));
      expect(app.graphsFollowing(eq.id).length, 2);
      app.cancelPendingSave();
    });
  });


  group('the wheel over a graph', () {
    // A wheel notch is delivered to every listener under the pointer, and the
    // page canvas has one of its own. One notch used to zoom the graph AND
    // scroll the page out from under it, so the thing being zoomed slid away
    // while it zoomed.
    testWidgets('zooms the graph and leaves the page where it is',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final g = app.insertGraph(latex: 'y=x^2', at: const Offset(120, 120));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: app,
            builder: (_, __) => PageCanvas(state: app),
          ),
        ),
      ));
      await tester.pump();

      final where = tester.getCenter(find.byType(GraphBlockView).first);
      final wasOffset = app.canvas.offset;
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      pointer.hover(where);
      await tester.sendEventToBinding(
          pointer.scroll(const Offset(0, 120)));
      await tester.pump();

      expect(GraphView.fromJson(g.content['view']).width,
          greaterThan(GraphView.initial.width),
          reason: 'the graph zoomed out');
      expect(app.canvas.offset, wasOffset,
          reason: 'and the page did not move an inch');
      app.cancelPendingSave();
    });
  });

}
