// Consistency pass (PLANNING "Consistency/UX"): a code block behaves like
// a text block at the pointer. Read view is SELECTABLE (drag highlights,
// Ctrl+C copies, no editor needed); a plain tap opens the editor with the
// caret AT THE TAP — "it doesnt respect click position" was the report.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/code_block_view.dart';
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
    tmp = Directory.systemTemp.createTempSync('onote_codeview_');
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

  Future<Block> pump(WidgetTester tester) async {
    final b = Block(type: BlockType.code, x: 0, y: 0, w: 420, content: {
      'language': 'text',
      'source': 'hello world, a longer line of code',
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: app,
          builder: (_, __) => Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 420, child: CodeBlockView(block: b, app: app)),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return b;
  }

  testWidgets('the read view is selectable text, not a dead label',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(tester);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.byType(TextField), findsNothing,
        reason: 'no editor until a tap asks for one');
  });

  testWidgets('a tap opens the editor with the caret AT the tap',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final b = await pump(tester);

    // Tap just inside the first character.
    final origin = tester.getTopLeft(find.byType(SelectableText));
    await tester.tapAt(origin + const Offset(3, 8));
    await tester.pumpAndSettle();

    expect(app.editingBlockId, b.id, reason: 'tap-to-edit survives');
    final tf = tester.widget<TextField>(find.byType(TextField));
    final caret = tf.controller!.selection.baseOffset;
    expect(caret, lessThanOrEqualTo(1),
        reason: 'clicked the first character; caret must not jump to the '
            'end (offset ${'hello world, a longer line of code'.length})');
  });

  testWidgets('a tap further along the line lands further along the text',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(tester);

    final origin = tester.getTopLeft(find.byType(SelectableText));
    await tester.tapAt(origin + const Offset(150, 8));
    await tester.pumpAndSettle();

    final tf = tester.widget<TextField>(find.byType(TextField));
    final caret = tf.controller!.selection.baseOffset;
    expect(caret, greaterThan(3));
    expect(caret, lessThan('hello world, a longer line of code'.length),
        reason: 'somewhere in the middle — neither start nor end');
  });
}
