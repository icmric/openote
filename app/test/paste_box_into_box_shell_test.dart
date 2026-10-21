// Ctrl+V inside a box, through the real shell.
//
// The decision — the boxes on our own clipboard, or whatever the system
// clipboard holds — needs an asynchronous clipboard read, by which time the
// keystroke is gone. So the shell swallows Ctrl+V whenever there are boxes
// that could be pasted, and either inserts their writing or hands the paste
// back to the field (`OnoteEditSession.pasteFromClipboard`), which is what
// keeps the input formatters — maths pasted into a paragraph arrives as
// maths — doing their job.
//
// That handing-back is the part worth a test through the whole shell: get it
// wrong and ordinary text paste is broken, which would be far worse than the
// bug being fixed.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/text_block_view.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/app_shell.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;

  Future<void> shell(WidgetTester t, List<Block> blocks) async {
    AppState.syncLogEnabled = false;
    await t.runAsync(() async {
      tmp = Directory.systemTemp.createTempSync('onote_boxpaste_shell_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('B');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.readSystemClipboardText = () async => null;
      app.reloadNodes();
      final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
      app.importPage(nb.id, page.id, blocks, PageProps());
      app.reloadNodes();
      await app.selectPage(page.id);
    });
    app.markOnboardingSeen();
    t.view.physicalSize = const Size(1400, 950);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    addTearDown(() {
      AppState.syncLogEnabled = true;
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      theme: onoteTheme(Brightness.light),
      home: AppShell(app: app),
    ));
    await t.pump(const Duration(milliseconds: 900));
    await t.pumpAndSettle();
  }

  Future<void> ctrl(WidgetTester t, LogicalKeyboardKey k) async {
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(k);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
    app.cancelPendingSave();
  }

  Block text(String s, {double y = 140}) =>
      Block(type: BlockType.text, x: 60, y: y, w: 320, content: {'text': s});

  /// The box's OWN field — not the navigator's search box, which is also a
  /// TextField and comes first in the tree.
  Finder boxField() => find.descendant(
      of: find.byType(TextBlockView), matching: find.byType(TextField));

  TextEditingController boxController(WidgetTester t) =>
      t.widget<TextField>(boxField().first).controller!;

  /// Open [b] for editing. A CLOSED box draws read-only Markdown and has no
  /// field at all, so there is nothing to paste into until it is open.
  Future<TextEditingController> openBox(WidgetTester t, Block b) async {
    app.select(b.id, edit: true);
    await t.pumpAndSettle();
    expect(boxField(), findsWidgets, reason: 'the box is open for editing');
    return boxController(t);
  }

  testWidgets('cut a box, click into another, Ctrl+V pastes its writing',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final source = text('osmosis is diffusion');
    final host = text('Notes: ', y: 400);
    await shell(t, [source, host]);

    // Cut the first box the way the canvas does.
    app.select(source.id);
    await ctrl(t, LogicalKeyboardKey.keyX);
    expect(app.blocks.any((b) => b.id == source.id), isFalse,
        reason: 'precondition: it is on the clipboard, not the page');

    // Open the other box and put the caret at the end.
    final c = await openBox(t, host);
    c.selection = TextSelection.collapsed(offset: c.text.length);
    await t.pump();

    await ctrl(t, LogicalKeyboardKey.keyV);

    expect(c.text, 'Notes: osmosis is diffusion');
    expect(app.blocks.where((b) => b.type == BlockType.text), hasLength(1),
        reason: 'pasted INTO the box, not back onto the canvas');
  });

  testWidgets('pasting into a box does not consume the clipboard', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // So the same cut can also go on the canvas afterwards, which is what
    // the canvas Ctrl+V then does (paste_box_into_box_test, and
    // canvas_math_paste_test for the canvas path itself).
    final source = text('osmosis');
    final host = text('Notes: ', y: 400);
    await shell(t, [source, host]);
    app.select(source.id);
    await ctrl(t, LogicalKeyboardKey.keyX);

    final c = await openBox(t, host);
    c.selection = TextSelection.collapsed(offset: c.text.length);
    await ctrl(t, LogicalKeyboardKey.keyV);

    expect(c.text, 'Notes: osmosis', reason: 'precondition');
    expect(app.canPasteBlocks, isTrue);
  });

  testWidgets('NEGATIVE CONTROL: with nothing cut, Ctrl+V is the field\'s own',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // Nothing on the block clipboard, so the keystroke must fall through
    // untouched — the field (and its formatters) own it. Under the harness
    // there is no system clipboard either, so nothing arrives; what matters
    // is that the box is not altered and nothing throws.
    final host = text('Notes: ');
    await shell(t, [host]);
    final c = await openBox(t, host);
    expect(app.canPasteBlocks, isFalse, reason: 'precondition');

    await ctrl(t, LogicalKeyboardKey.keyV);

    expect(c.text, 'Notes: ');
  });

  testWidgets('a box with no writing in it is not pasted into a box',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // Handwriting has no text form. The paste declines rather than dropping
    // it, so it is still on the clipboard for the canvas.
    final ink = Block(
        type: BlockType.ink,
        x: 60,
        y: 140,
        w: 200,
        h: 60,
        content: {'strokes': <dynamic>[]});
    final host = text('Notes: ', y: 400);
    await shell(t, [ink, host]);
    app.select(ink.id);
    await ctrl(t, LogicalKeyboardKey.keyX);

    final c = await openBox(t, host);
    c.selection = TextSelection.collapsed(offset: c.text.length);
    await ctrl(t, LogicalKeyboardKey.keyV);

    expect(c.text, 'Notes: ', reason: 'nothing was invented for it');
    expect(app.canPasteBlocks, isTrue, reason: 'still there for the canvas');
  });
}
