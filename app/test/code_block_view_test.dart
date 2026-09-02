// Consistency pass (PLANNING "Consistency/UX"): a code block behaves like
// a text block at the pointer. Read view is SELECTABLE (drag highlights,
// Ctrl+C copies, no editor needed); a plain tap opens the editor with the
// caret AT THE TAP — "it doesnt respect click position" was the report.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/code_block_view.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/app_shell.dart';
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
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
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

  testWidgets('while editing, a drag across the text SELECTS it',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(tester);

    // Enter editing.
    final origin = tester.getTopLeft(find.byType(SelectableText));
    await tester.tapAt(origin + const Offset(3, 8));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    // Drag from the start of the line to well into it.
    final fieldTL = tester.getTopLeft(find.byType(TextField));
    final g = await tester.startGesture(fieldTL + const Offset(3, 8),
        kind: PointerDeviceKind.mouse);
    for (var i = 1; i <= 6; i++) {
      await g.moveTo(fieldTL + Offset(3.0 + i * 25, 8));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();

    final tf = tester.widget<TextField>(find.byType(TextField));
    final sel = tf.controller!.selection;
    expect(sel.isCollapsed, isFalse,
        reason: 'dragging across editing code must highlight, '
            'got $sel');
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

  // ── On the REAL canvas: the field reports (keys leaking out of the
  // editor, drags not selecting) all involve the layers around the field,
  // so these run through AppShell, not the bare view. ──────────────────
  group('inside the shell', () {
    late Block code;

    Future<void> pumpShell(WidgetTester tester) async {
      final nb = app.notebookId!;
      final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
      code = Block(type: BlockType.code, x: 60, y: 140, w: 420, content: {
        'language': 'text',
        'source': 'hello world, a longer line of code',
      });
      app.importPage(nb, page.id, [code], PageProps());
      app.reloadNodes();
      await app.selectPage(page.id);
      app.markOnboardingSeen();
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        theme: onoteTheme(Brightness.light),
        home: AppShell(app: app),
      ));
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
    }

    Future<void> edit(WidgetTester tester) async {
      final origin = tester.getTopLeft(find.descendant(of: find.byType(CodeBlockView), matching: find.byType(SelectableText)));
      await tester.tapAt(origin + const Offset(3, 8));
      await tester.pumpAndSettle();
      expect(app.editingBlockId, code.id);
    }

    Future<void> flush(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
    }

    testWidgets('arrows while editing move the CARET, not the selection',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(tester);
      await edit(tester);
      final tf = tester.widget<TextField>(find.descendant(of: find.byType(CodeBlockView), matching: find.byType(TextField)));
      final before = tf.controller!.selection.baseOffset;

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(app.editingBlockId, code.id,
          reason: 'arrow must NOT leave the editor');
      expect(tf.controller!.selection.baseOffset, before + 1,
          reason: 'arrow moves the caret inside the field');
      await flush(tester);
    });

    testWidgets('Enter while editing is NOT eaten by the canvas',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(tester);
      await edit(tester);

      // The real newline arrives via the platform's text input, which the
      // test harness doesn't synthesize — what CAN be pinned is the bug
      // itself: the canvas _EditIntent used to CONSUME the keystroke
      // (handled == true), which is what suppressed the newline in the
      // field. Unconsumed here means the platform's insertion goes ahead.
      final handled =
          await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(handled, isFalse,
          reason: 'Enter while editing belongs to the editor, not the '
              'canvas traversal');
      expect(app.editingBlockId, code.id, reason: 'still editing');
      await flush(tester);
    });

    testWidgets('a drag across editing code selects text on the canvas too',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(tester);
      await edit(tester);

      final fieldTL = tester.getTopLeft(find.descendant(of: find.byType(CodeBlockView), matching: find.byType(TextField)));
      final g = await tester.startGesture(fieldTL + const Offset(3, 8),
          kind: PointerDeviceKind.mouse);
      for (var i = 1; i <= 6; i++) {
        await g.moveTo(fieldTL + Offset(3.0 + i * 25, 8));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();

      final tf = tester.widget<TextField>(find.descendant(of: find.byType(CodeBlockView), matching: find.byType(TextField)));
      expect(tf.controller!.selection.isCollapsed, isFalse,
          reason: 'drag-select must survive the canvas layers, got '
              '${tf.controller!.selection}');
      await flush(tester);
    });

    testWidgets('typing on a SELECTED box starts editing at the end',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(tester);

      // Select without editing: Tab from the canvas.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(app.selectedBlockId, code.id);
      expect(app.editingBlockId, isNull);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyX,
          character: 'x');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyX);
      await tester.pumpAndSettle();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(app.editingBlockId, code.id,
          reason: 'a printable key on a selected box enters editing');
      final live = app.blocks.firstWhere((b) => b.id == code.id);
      expect(live.content['source'], endsWith('x'),
          reason: 'the typed character lands at the end');
      await flush(tester);
    });
  });
}
