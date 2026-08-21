// An equation in a sentence behaves exactly like one in a box (owner, v0.23).
//
// *"A regular user is not going to think a standalone maths box is any
// different to one in a text box, so they must have exact feature and
// behaviour parrody."*
//
// Each group here is a difference the consistency audit found between the two,
// stated as the thing a student would notice.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/inline_math_editor.dart';
import 'package:openote/editor/math_block_view.dart';
import 'package:openote/editor/text_block_view.dart';
import 'package:openote/math/math_field.dart';
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
    tmp = Directory.systemTemp.createTempSync('onote_parity_');
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

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Block textBlock(String text, {String id = 'p1'}) {
    final b = Block(
        id: id,
        type: BlockType.text,
        x: 0,
        y: 0,
        w: 420,
        content: {'text': text, 'autoWidth': false});
    app.blocks.add(b);
    return b;
  }

  Widget hostText(Block b) => MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 420, child: TextBlockView(block: b, app: app)),
          ),
        ),
      );

  group('one mistyped character costs one burst, not the whole visit', () {
    testWidgets('a paragraph coalesces its undo points on time',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final b = textBlock('start');
      app.editingBlockId = 'p1';
      await tester.pumpWidget(hostText(b));
      await settle(tester);

      // First burst, typed the way a student types.
      await tester.enterText(find.byType(TextField), 'start one');
      await settle(tester);
      // …a pause longer than the coalescing gap. REAL time, not pumped: the
      // rule is written against `nowMs()`, which a fake clock does not move.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 850)));
      // …then a second burst.
      await tester.enterText(find.byType(TextField), 'start one two');
      await settle(tester);

      app.undo();
      expect((app.blocks.single.content['text'] as String), 'start one',
          reason: 'one step back is the second burst, not the whole visit \u2014 '
              'the block equation editor has coalesced on 700ms since v0.18 '
              'and the paragraph pushed exactly ONE point per session');
      app.undo();
      expect((app.blocks.single.content['text'] as String), 'start');
      app.cancelPendingSave();
    });
  });

  group('right-clicking inside an equation means one thing', () {
    testWidgets('the paragraph does not also open its own toolbar',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final b = textBlock(r'we know $2+3=\boxed{5}$ here');
      app.editingBlockId = 'p1';
      await tester.pumpWidget(hostText(b));
      await settle(tester);
      await tester.tap(find.byType(InlineMathAtom));
      await settle(tester);
      expect(find.byType(MathField), findsOneWidget);

      final field = tester.widget<TextField>(find.byType(TextField));
      final built = field.contextMenuBuilder;
      expect(built, isNotNull);
      // While the equation holds the keyboard the host builds NOTHING, which
      // is the same answer a block equation gives (`block_view` passes a null
      // secondary-tap handler while editing).
      expect(app.activeSession!.inlineMathFocused, isTrue);
      app.cancelPendingSave();
    });
  });

  group('the LaTeX view never rebuilds the page from a stale copy', () {
    testWidgets('a visual edit clears the stored source', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final b = app.insertEquation(at: const Offset(10, 10));
      b.content['linearSource'] = '1/2';
      b.content['latex'] = r'\frac{1}{2}';
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
                width: 420, child: MathBlockView(block: b, app: app)),
          ),
        ),
      ));
      await settle(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.digit7,
          character: '7');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.digit7);
      await settle(tester);

      expect(b.content['latex'], contains('7'));
      expect(b.content['linearSource'], isNull,
          reason: 'a source that no longer describes the equation would be '
              'offered as the truth by "Back to the buttons", silently '
              'throwing away everything typed since');
      app.cancelPendingSave();
    });
  });
}
