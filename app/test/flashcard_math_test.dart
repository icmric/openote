// Flashcards hold maths (finding open since v0.18 §13.6).
//
// The deck reader always tolerated `$…$` — `inlineCardRe` passes dollars
// straight through — but every card face was drawn with a plain `Text`, so a
// maths card showed the student raw backslashes on the one surface built for
// remembering maths. These tests pin the fix: each face goes through the
// shared inline renderer (markdown/md_render.dart `inlineSpans`), so `$…$`
// draws as an equation, on the card itself AND in the study panel's review —
// while a plain card renders exactly as before.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/flashcard_view.dart';
import 'package:openote/math/math_view.dart';
import 'package:openote/model/models.dart';
import 'package:openote/model/tags.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/study_panel.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  group('the card', () {
    Future<void> show(WidgetTester t,
        {required String front, required String back}) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 220,
              child: FlipCard(front: front, back: back),
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('maths on the front draws as an equation', (t) async {
      await show(t,
          front: r'What is $\frac{1}{2}+\frac{1}{2}$?', back: 'One');
      expect(find.byType(OnoteMath), findsOneWidget,
          reason: 'the defect: the face was a plain Text, so \$…\$ printed '
              'its raw LaTeX on the card');
      expect(find.byType(MathSourceFallback), findsNothing,
          reason: 'drawn as maths, not as the could-not-draw notice');
      expect(find.textContaining(r'\frac', findRichText: true), findsNothing,
          reason: 'no visible backslashes anywhere on the face');
      expect(find.textContaining('What is ', findRichText: true),
          findsOneWidget,
          reason: 'the words around the equation stay words');
    });

    testWidgets('and on the back, once the card is turned over', (t) async {
      await show(t,
          front: 'Formula for kinetic energy?',
          back: r'$E_k = \frac{1}{2}mv^2$');
      expect(find.byType(OnoteMath), findsNothing,
          reason: 'the plain question side has no equation to draw');
      await t.tap(find.byType(FlipCard));
      await t.pumpAndSettle();
      expect(find.byType(OnoteMath), findsOneWidget,
          reason: 'the answer side is where the maths usually lives');
      expect(find.textContaining(r'\frac', findRichText: true), findsNothing,
          reason: 'no visible backslashes on the answer either');
    });

    testWidgets('a plain card is untouched by the maths path', (t) async {
      await show(t, front: 'Capital of France?', back: 'Paris');
      expect(find.text('Capital of France?'), findsOneWidget,
          reason: 'exact-text lookups must keep working — the words are the '
              'whole face, and the block tests find them this way');
      expect(find.byType(OnoteMath), findsNothing);
      await t.tap(find.byType(FlipCard));
      await t.pumpAndSettle();
      expect(find.text('Paris'), findsOneWidget);
    });
  });

  group('the study panel', () {
    /// A notebook whose one page holds one Question card built from [text]
    /// (line 0 is the front; the indented line below is the back) — the same
    /// harness study_panel_test.dart uses.
    Future<AppState> newApp(WidgetTester tester, {required String text}) async {
      late AppState app;
      late Repository repo;
      final tmp = Directory.systemTemp.createTempSync('onote_cardmath_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      await tester.runAsync(() async {
        repo = await Repository.openAt(tmp);
        final nb = await repo.createNotebook('Maths');
        app = AppState(repo)..notebookId = nb.id;
        app.reloadNodes();
        final section =
            app.nodes.firstWhere((n) => n.kind == NodeKind.section).id;
        final page = app.importNode(
            nb.id,
            TreeNode(
                kind: NodeKind.page,
                parentId: section,
                title: 'Calculus',
                position: 'a001'));
        final b = Block(
            type: BlockType.text, x: 0, y: 0, content: {'text': text});
        NoteTag.writeInto(
            b.content, [NoteTag(kind: TagKind.question, line: 0)]);
        app.importPage(nb.id, page.id, [b], PageProps());
        app.reloadNodes();
        await app.selectPage(page.id);
      });
      return app;
    }

    Widget host(AppState app) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 720,
              child: ListenableBuilder(
                listenable: app,
                builder: (_, __) => Row(children: [StudyPanel(app: app)]),
              ),
            ),
          ),
        );

    // One equation per note box in these fixtures, deliberately: page open
    // runs the Rust needless-math repair, which today mispairs a kept
    // equation's closing dollar with the NEXT dollar in the box and eats
    // both. That is a separate, pre-existing defect (flagged for its own
    // fix); these tests pin the drawing, not the repair.
    testWidgets('a maths question reads as maths during review',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = await newApp(tester,
          text: 'What is \$\\frac{1}{2}+\\frac{1}{2}\$?\n'
              '  It adds up to one.');
      await tester.pumpWidget(host(app));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Review 1'));
      await tester.pumpAndSettle();

      expect(find.byType(OnoteMath), findsOneWidget,
          reason: 'the defect: the review face was a plain SelectableText, '
              'so the front showed raw backslashes mid-study');
      expect(find.textContaining(r'\frac', findRichText: true), findsNothing,
          reason: 'no visible backslashes on the question');
      expect(find.textContaining('What is ', findRichText: true),
          findsOneWidget,
          reason: 'the words around the equation stay words');
    });

    testWidgets('and a maths answer is revealed as maths', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = await newApp(tester,
          text: 'What do two halves make?\n  They make \$\\frac{2}{2} = 1\$.');
      await tester.pumpWidget(host(app));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Review 1'));
      await tester.pumpAndSettle();
      expect(find.byType(OnoteMath), findsNothing,
          reason: 'the answer stays hidden until asked for');

      await tester.tap(find.textContaining('Show answer'));
      await tester.pumpAndSettle();

      expect(find.byType(OnoteMath), findsOneWidget,
          reason: 'the revealed answer draws its equation, where the maths '
              'usually lives');
      expect(find.textContaining(r'\frac', findRichText: true), findsNothing,
          reason: 'no visible backslashes on the answer');
      expect(find.textContaining('They make ', findRichText: true),
          findsOneWidget,
          reason: 'the answer prose survives around the equation');
    });

    testWidgets('a cloze front keeps its blank and its maths', (tester) async {
      // A `==highlight==` in a tagged line becomes a fill-in-the-blank card.
      // Its front is stitched from parts around the blank, so this is a
      // separate code path from the plain front — one that used to hold raw
      // dollars just the same.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = await newApp(tester,
          text: 'The derivative of \$x^2\$ is ==2x==\n  see the lecture.');
      await tester.pumpWidget(host(app));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Review 1'));
      await tester.pumpAndSettle();

      expect(find.byType(OnoteMath), findsOneWidget,
          reason: 'the maths outside the blank draws as an equation');
      expect(find.textContaining(r'x^2', findRichText: true), findsNothing,
          reason: 'no raw caret-notation source on the face');

      await tester.tap(find.textContaining('Show answer'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2x', findRichText: true), findsWidgets,
          reason: 'the answer drops into the blank on reveal');
    });
  });
}
