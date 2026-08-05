// THROWAWAY probe — delete after running.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/block_view.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  group('keyboard-only reachability', () {
    late Repository repo;
    late Directory tmp;
    late AppState app;

    setUp(() async {
      if (!haveSqlite) return;
      tmp = Directory.systemTemp.createTempSync('onote_kbd_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('KB');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      await app.selectPage(
          app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
      app.addBlock(Block(
          type: BlockType.text,
          x: 40,
          y: 40,
          w: 240,
          h: 80,
          content: {'text': 'first para'}));
      app.addBlock(Block(
          type: BlockType.text,
          x: 40,
          y: 200,
          w: 240,
          h: 80,
          content: {'text': 'second para'}));
      app.select(null);
    });

    tearDown(() {
      if (!haveSqlite) return;
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    testWidgets('Tab / arrows / Enter never reach a block', (t) async {
      if (!haveSqlite) return markTestSkipped('no sqlite');
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: app,
            builder: (_, __) => Stack(children: [
              for (final b in app.blocks)
                BlockView(block: b, app: app, controller: app.canvas),
            ]),
          ),
        ),
      ));
      await t.pump();

      // ignore: avoid_print
      print('blocks=${app.blocks.length} editing=${app.editingBlockId} '
          'selected=${app.selectedIds}');

      for (final key in [
        LogicalKeyboardKey.tab,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.f2,
        LogicalKeyboardKey.f6,
      ]) {
        for (var i = 0; i < 5; i++) {
          await t.sendKeyEvent(key);
          await t.pump();
        }
      }
      app.cancelPendingSave();

      // ignore: avoid_print
      print('AFTER KEYBOARD-ONLY NAVIGATION:');
      // ignore: avoid_print
      print('  editingBlockId = ${app.editingBlockId}');
      // ignore: avoid_print
      print('  selectedIds    = ${app.selectedIds}');
      // ignore: avoid_print
      print('  activeEditor   = ${app.activeEditor}');
      // ignore: avoid_print
      print('  focus ctx      = '
          '${FocusManager.instance.primaryFocus?.context?.widget.runtimeType}');
      // ignore: avoid_print
      print('  EditableTexts  = ${find.byType(EditableText).evaluate().length}');

      // Contrast: one tap.
      await t.tap(find.text('first para').first);
      await t.pump();
      app.cancelPendingSave();
      // ignore: avoid_print
      print('AFTER ONE MOUSE TAP: editingBlockId = ${app.editingBlockId}');
      app.cancelPendingSave();
    });
  });
}
