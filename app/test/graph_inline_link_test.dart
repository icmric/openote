// The link between an equation in a SENTENCE and its graph (v0.23, review).
//
// A link into a sentence is anchored to what the equation SAYS, because a
// paragraph's character offsets shift on every keystroke and an index into
// "the nth equation" drifts the moment one is added or removed. The price of
// that choice is the thing this file pins: two equations reading the same
// words are the same equation as far as the anchor can tell, and following
// the wrong one rewrites a graph the student never touched.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/inline_math_editor.dart';
import 'package:openote/editor/text_block_view.dart';
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
    tmp = Directory.systemTemp.createTempSync('onote_glink_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('G');
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

  Block para(String text) {
    final b = Block(
        id: 'p1',
        type: BlockType.text,
        x: 0,
        y: 0,
        w: 420,
        content: {'text': text, 'autoWidth': false});
    app.blocks.add(b);
    return b;
  }

  Widget host(Block b) => MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: app,
            builder: (_, __) =>
                SizedBox(width: 420, child: TextBlockView(block: b, app: app)),
          ),
        ),
      );

  testWidgets('typing in one equation cannot steal another one\'s graph',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final b = para(r'we know $y=x$ and also $y$ here');
    final g = app.insertGraph(latex: 'y=x', from: 'p1', fromLatex: 'y=x');

    app.editingBlockId = 'p1';
    await tester.pumpWidget(host(b));
    await tester.pump();

    // Into the SECOND equation, and type it up to the first one's text.
    final atoms = tester.widgetList(find.byType(InlineMathAtom)).toList();
    expect(atoms.length, 2, reason: 'two equations in the sentence');
    await tester.tap(find.byType(InlineMathAtom).last);
    await tester.pump();
    for (final ch in ['=', 'x', '+', '3']) {
      final key = switch (ch) {
        '=' => LogicalKeyboardKey.equal,
        '+' => LogicalKeyboardKey.equal,
        _ => LogicalKeyboardKey(ch.codeUnitAt(0)),
      };
      await tester.sendKeyDownEvent(key, character: ch);
      await tester.sendKeyUpEvent(key);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(b.content['text'], contains(r'$y=x+3$'),
        reason: 'the second equation really was typed into');

    expect(g.content['latex'], 'y=x',
        reason: 'the FIRST equation still owns its own graph');
    expect(g.content['fromLatex'], 'y=x',
        reason: 'and the link did not walk off with it either');
    app.editingBlockId = null;
    await tester.pumpWidget(const SizedBox());
    app.cancelPendingSave();
    await tester.pump(const Duration(seconds: 2));
  });

  group('the anchor, without the widgets', () {
    test('one graph following one equation moves with it', () {
      if (!haveSqlite) return;
      para(r'we know $y=3x$ here');
      final g = app.insertGraph(latex: 'y=3x', from: 'p1', fromLatex: 'y=3x');
      expect(app.pushInlineEquationToGraphs('p1', 'y=3x', 'y=4x'), isTrue);
      expect(g.content['latex'], 'y=4x');
      expect(g.content['fromLatex'], 'y=4x');
      app.cancelPendingSave();
    });

    test('two graphs following the same words move neither', () {
      // Which one is this equation's? Neither answer can be shown to be
      // right, so nothing moves rather than the wrong thing moving.
      if (!haveSqlite) return;
      para(r'we know $y=3x$ and $y=3x$ here');
      final a = app.insertGraph(latex: 'y=3x', from: 'p1', fromLatex: 'y=3x');
      final b2 = app.insertGraph(latex: 'y=3x', from: 'p1', fromLatex: 'y=3x');
      expect(app.pushInlineEquationToGraphs('p1', 'y=3x', 'y=4x'), isFalse);
      expect(a.content['latex'], 'y=3x');
      expect(b2.content['latex'], 'y=3x');
      app.cancelPendingSave();
    });

    test('a graph in another paragraph is never touched', () {
      if (!haveSqlite) return;
      para(r'we know $y=3x$ here');
      final other =
          app.insertGraph(latex: 'y=3x', from: 'p2', fromLatex: 'y=3x');
      expect(app.pushInlineEquationToGraphs('p1', 'y=3x', 'y=4x'), isFalse);
      expect(other.content['latex'], 'y=3x');
      app.cancelPendingSave();
    });
  });
}
