// Switching degrees and radians works the page out again (v0.23, audit).
//
// It used to leave every answer alone. What that actually leaves behind is a
// number that is simply WRONG, in a grey panel that says the app worked it
// out, directly under a button that now says the opposite: `sin(30)= ` reads
// 0.5, you press RAD, and the panel still reads 0.5.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/editor/inline_math_editor.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/markdown/md_syntax.dart';
import 'package:openote/math/evaluate.dart';
import 'package:openote/math/math_editor.dart';
import 'package:openote/math/math_field.dart';
import 'package:openote/math/math_tree.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/command_bar.dart';
import 'package:openote/ui/object_row.dart';

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
    mathAngleMode = AngleMode.degrees;
    tmp = Directory.systemTemp.createTempSync('onote_rework_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('T');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
  });

  tearDown(() {
    AppState.syncLogEnabled = true;
    mathAngleMode = AngleMode.degrees;
    if (!haveSqlite) return;
    app.cancelPendingSave();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Block mathBlock(String latex) {
    final b = app.insertEquation(at: const Offset(20, 20));
    b.content['latex'] = latex;
    app.editingBlockId = null;
    return b;
  }

  group('the page is worked out again', () {
    test('an answer that depends on the mode follows the button', () {
      if (!haveSqlite) return;
      final b = mathBlock(r'\sin (30)=\boxed{0.5}');
      app.setAngleMode(AngleMode.radians);
      expect(b.content['latex'], contains('-0.9880316241'),
          reason: 'sin 30 RADIANS is -0.988, and the panel said 0.5');
      app.setAngleMode(AngleMode.degrees);
      expect(b.content['latex'], contains(r'\boxed{0.5}'),
          reason: 'and back again');
      app.cancelPendingSave();
    });

    test('an answer that does not depend on it is left exactly alone', () {
      if (!haveSqlite) return;
      final b = mathBlock(r'2+3=\boxed{5}');
      final before = b.content['latex'];
      final updated = b.updatedAt;
      app.setAngleMode(AngleMode.radians);
      expect(b.content['latex'], before);
      expect(b.updatedAt, updated,
          reason: 'an untouched block must not be marked as changed, or every '
              'mode press would sync the whole page');
      app.cancelPendingSave();
    });

    test('an equation inside a SENTENCE is worked out too', () {
      if (!haveSqlite) return;
      final b = app.addBlock(Block(
          type: BlockType.text,
          x: 0,
          y: 200,
          w: 400,
          content: {'text': r'so $\cos (60)=\boxed{0.5}$ then'}));
      app.setAngleMode(AngleMode.radians);
      expect(b.content['text'], contains('-0.9524129804'));
      expect(b.content['text'], startsWith('so '),
          reason: 'and the sentence around it is untouched');
      expect(b.content['text'], endsWith(' then'));
      app.cancelPendingSave();
    });

    test('two equations in one paragraph both follow', () {
      if (!haveSqlite) return;
      final b = app.addBlock(Block(
          type: BlockType.text,
          x: 0,
          y: 200,
          w: 400,
          content: {
            'text': r'$\sin (30)=\boxed{0.5}$ and $\cos (60)=\boxed{0.5}$'
          }));
      app.setAngleMode(AngleMode.radians);
      final t = b.content['text'] as String;
      expect(t, contains('-0.9880316241'));
      expect(t, contains('-0.9524129804'));
      expect(t, contains(' and '));
      app.cancelPendingSave();
    });

    test('it is one undo step, whatever it touched', () {
      if (!haveSqlite) return;
      final b = mathBlock(r'\sin (30)=\boxed{0.5}');
      app.setAngleMode(AngleMode.radians);
      expect(b.content['latex'], contains('-0.988'));
      app.undo();
      final after = app.blocks.firstWhere((x) => x.id == b.id);
      expect(after.content['latex'], contains(r'\boxed{0.5}'),
          reason: 'one press, one step back');
      app.cancelPendingSave();
    });

    test('pressing the button it is already on does nothing at all', () {
      if (!haveSqlite) return;
      final b = mathBlock(r'\sin (30)=\boxed{0.5}');
      final updated = b.updatedAt;
      app.setAngleMode(AngleMode.degrees);
      expect(b.updatedAt, updated);
      app.cancelPendingSave();
    });
  });

  group('the equation being written is not rewritten from outside', () {
    testWidgets('it re-works itself, and keeps the caret', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      tester.view.physicalSize = const Size(2600, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final b = app.insertEquation(at: const Offset(20, 20));
      await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: app,
            builder: (_, __) => Column(children: [
              CommandBar(app: app),
              ObjectRow(app: app),
              Expanded(child: PageCanvas(state: app)),
            ]),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Write sin(30)= and a space, the ordinary way.
      for (final ch in [r'\', 's', 'i', 'n', '(', '3', '0', ')', '=', ' ']) {
        final key = switch (ch) {
          '(' => LogicalKeyboardKey.digit9,
          ')' => LogicalKeyboardKey.digit0,
          '=' => LogicalKeyboardKey.equal,
          ' ' => LogicalKeyboardKey.space,
          r'\' => LogicalKeyboardKey.backslash,
          _ => LogicalKeyboardKey(ch.codeUnitAt(0)),
        };
        await tester.sendKeyDownEvent(key, character: ch);
        await tester.sendKeyUpEvent(key);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(b.content['latex'], contains(r'\boxed{0.5}'));

      await tester.tap(find.text('DEG'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(app.angleMode, AngleMode.radians);
      expect(b.content['latex'], contains('-0.9880316241'),
          reason: 'the OPEN equation works itself out, because the page-wide '
              'pass deliberately skips it');
      expect(find.byType(MathField), findsOneWidget,
          reason: 'and the editor is still there');

      // The proof the caret survived: the next keystroke lands in it.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.digit7,
          character: '7');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.digit7);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(b.content['latex'], endsWith('7'));
      app.cancelPendingSave();
    });
  });

  group('the scanner the page-wide pass uses', () {
    test('finds every equation in a line, and only equations', () {
      final runs = mathRunsIn(r'a $x$ b $y=2$ c **bold** $$').toList();
      expect(runs.length, greaterThanOrEqualTo(2));
      expect(runs.map((r) => r.latex), containsAll(['x', 'y=2']));
    });

    test('and puts one back exactly where it was', () {
      const text = r'so $x+1$ then';
      final run = mathRunsIn(text).single;
      expect(replaceMathRun(text, run, 'y+2'), r'so $y+2$ then');
    });

    test('a display equation keeps its two dollars', () {
      const text = r'$$x+1$$';
      final run = mathRunsIn(text).single;
      expect(replaceMathRun(text, run, 'y'), r'$$y$$');
    });
  });

  group('and the figures the student chose survive it', () {
    // The pass that keeps the page honest used to throw away the one thing
    // on the page the student had chosen by hand. It recognises "three
    // figures" by asking the working what the answer comes to and seeing
    // which rounding matches the digits — and it was asking in the NEW mode
    // about digits written in the old one, so nothing ever matched.
    test('three figures stays three figures, there and back', () {
      if (!haveSqlite) return;
      final ed = MathEditor.open(r'\cos (45)=\boxed{0.7071067812}')!;
      expect(
          ed.setAnswerSigFigs(
              ed.root.children.whereType<MAnswer>().first, 3),
          isTrue);
      final b = mathBlock(ed.latex);
      expect(b.content['latex'], contains(r'\boxed{0.707}'));

      app.setAngleMode(AngleMode.radians);
      expect(b.content['latex'], contains(r'\boxed{0.525}'),
          reason: 'cos 45 RADIANS to three figures — the number changes, '
              'the number of figures does not');

      app.setAngleMode(AngleMode.degrees);
      expect(b.content['latex'], contains(r'\boxed{0.707}'),
          reason: 'and back to where it started, still three figures');
      app.cancelPendingSave();
    });

    test('an answer left at its own precision is not given one', () {
      if (!haveSqlite) return;
      final b = mathBlock(r'\cos (45)=\boxed{0.7071067812}');
      app.setAngleMode(AngleMode.radians);
      expect(b.content['latex'], contains(r'\boxed{0.5253219888}'),
          reason: 'ten figures, as a school calculator shows it');
      app.cancelPendingSave();
    });
  });


  group('an equation in a sentence, with company', () {
    // The page-wide pass skips the block being edited, and for a sentence
    // "the block" is the whole paragraph. Every OTHER answered equation in it
    // was left showing the old mode's number, in a grey panel that says the
    // app worked it out, under a button that now says the opposite — which is
    // the exact failure this feature exists to prevent.
    testWidgets('every equation in the paragraph follows the button',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      tester.view.physicalSize = const Size(2600, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final b = Block(
          id: 'p1',
          type: BlockType.text,
          x: 20,
          y: 20,
          w: 600,
          content: {
            'text': r'first $\sin (30)=\boxed{0.5}$ then $\cos (60)=\boxed{0.5}$ end',
            'autoWidth': false,
          });
      app.blocks.add(b);
      app.editingBlockId = 'p1';

      await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: app,
            builder: (_, __) => Column(children: [
              CommandBar(app: app),
              ObjectRow(app: app),
              Expanded(child: PageCanvas(state: app)),
            ]),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Into the SECOND equation, so the first is a sibling of the open one.
      await tester.tap(find.byType(InlineMathAtom).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('DEG'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(app.angleMode, AngleMode.radians);
      final text = b.content['text'] as String;
      expect(text, contains(r'\sin (30)=\boxed{-0.9880316241}'),
          reason: 'the OTHER equation in the same sentence, which nothing '
              'used to reach');
      expect(text, contains(r'\cos (60)=\boxed{-0.9524129804}'),
          reason: 'and the open one, which does its own');
      app.cancelPendingSave();
    });

    testWidgets('and a sibling keeps the figures it was showing',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      tester.view.physicalSize = const Size(2600, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final b = Block(
          id: 'p2',
          type: BlockType.text,
          x: 20,
          y: 20,
          w: 600,
          content: {
            'text': r'first $\cos (45)=\boxed{0.707}$ then $2+3=\boxed{5}$ end',
            'autoWidth': false,
          });
      app.blocks.add(b);
      app.editingBlockId = 'p2';

      await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: app,
            builder: (_, __) => Column(children: [
              CommandBar(app: app),
              ObjectRow(app: app),
              Expanded(child: PageCanvas(state: app)),
            ]),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(InlineMathAtom).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('DEG'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(b.content['text'], contains(r'\boxed{0.525}'),
          reason: 'cos 45 in RADIANS, still to three figures — the pass that '
              'rewrites it has to READ it in the mode it was written in');
      app.cancelPendingSave();
    });
  });

}
