// The OneNote-style pending caret (owner, verbatim): "when i click on the
// canvas somewhere it puts my cursor down and i can start typing, however it
// doesnt imedietley show the text box. In this state before ive started
// typing but after ive clicked the canvas, it otherwise behaves exactly like
// it does currently, except for that id like the arrow keys to allow me to
// navigate around the page."
//
// The first cut redirected arrow keys to the canvas's own block-to-BLOCK
// navigation (jumping selection to whichever existing block sits in that
// direction) — wrong, per the owner: "the box doesn't appear but arrow key
// navigation just switched between the existing boxes, doesnt move the
// cursor around the page." With no box drawn yet, the only thing on screen
// IS the blinking text caret, and "navigate around the page" means THAT
// slides around — the block's own position moves, the same way Ctrl+arrow
// already nudges a selected block, just without needing Ctrl since there is
// no text caret yet for a plain arrow to belong to instead.
//
// Three claims, each reproduced through the REAL shell (AppShell), because
// the whole point is arrow keys sent to a real focused text field that must
// NOT move a caret through content that doesn't exist:
//
//  (a) a click-created, still-empty block shows no chrome AND no hint text
//      — no move bar, no border, no resize handles, nothing describing
//      marks for a box the student cannot see — until the first keystroke;
//  (b) while it is pending, plain arrow keys slide the box's OWN position
//      around the page, exactly like Ctrl+arrow already does for a
//      selected block — never jumping editing away to a different one;
//  (c) the moment typing starts, arrow keys go back to moving the text caret
//      — this is a ONE-TIME window before the first character, not a
//      standing property of "the block happens to be empty right now".
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_pending_');
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

  Future<void> pumpShell(WidgetTester tester,
      {List<Block> preseeded = const []}) async {
    final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
    if (preseeded.isNotEmpty) {
      app.importPage(app.notebookId!, page.id, preseeded, PageProps());
      app.reloadNodes();
    }
    await app.selectPage(page.id);
    app.markOnboardingSeen();
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: onoteTheme(Brightness.light),
      home: AppShell(app: app),
    ));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
  }

  /// The exact sequence `PageCanvas._createTextAt` runs on a click on empty
  /// canvas — reproduced directly so these tests exercise the pending-caret
  /// machinery itself without needing real screen/page coordinate math.
  Block clickToCreate(double x, double y) {
    final b = app.addBlock(Block(
      type: BlockType.text,
      x: x,
      y: y,
      w: 320,
      content: {'text': '', 'autoWidth': false},
    ));
    app.pendingEmptyBlockId = b.id;
    app.select(b.id, edit: true);
    return b;
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k,
      {String? character}) async {
    await tester.sendKeyDownEvent(k, character: character);
    await tester.sendKeyUpEvent(k);
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Simulate the platform text-input connection reporting a new value —
  /// what an actual keystroke produces, once the OS/IME has composed it.
  /// Raw `sendKeyDownEvent(character: …)` does not reliably drive a real
  /// `TextField`'s `TextInputConnection` in this harness (arrow keys and
  /// other non-printable chords, which are `Actions`/`Shortcuts`-driven
  /// rather than IME-driven, are unaffected and still use `key` below).
  Future<void> type(WidgetTester tester, String text, int caretAt) async {
    tester.testTextInput.updateEditingValue(
        TextEditingValue(text: text, selection: TextSelection.collapsed(offset: caretAt)));
    await settle(tester);
  }

  testWidgets('a freshly clicked, still-empty block shows no chrome',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pumpShell(tester);

    final b = clickToCreate(200, 200);
    await settle(tester);

    expect(app.pendingEmptyBlockId, b.id,
        reason: 'a click-created, still-empty block is pending');
    expect(app.editingBlockId, b.id,
        reason: 'the caret is live — typing must work right away');
    expect(find.byIcon(Icons.drag_indicator), findsNothing,
        reason: 'no move bar — the box has not shown itself yet');
    expect(find.text('heading (#), list (-), task (- [ ]), bold (**)'),
        findsNothing,
        reason: 'no hint text either — nothing describes marks for a box '
            'the student cannot even see');

    // Typing ends the pending state and the box appears, exactly as today.
    await type(tester, 'a', 1);

    expect(app.pendingEmptyBlockId, isNull,
        reason: 'the first keystroke ends the pending window');
    expect(find.byIcon(Icons.drag_indicator), findsOneWidget,
        reason: 'the first keystroke reveals the box, as it always has');
    expect(app.blocks.firstWhere((x) => x.id == b.id).content['text'], 'a');
    app.cancelPendingSave();
  });

  testWidgets(
      'arrow keys slide the pending box around the page, never jumping '
      'editing to a different block', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // A neighbour is seeded to prove the arrow keys leave IT alone —
    // the previous (wrong) design jumped editing straight to it.
    final other = Block(
        id: 'other',
        type: BlockType.text,
        x: 200,
        y: 400,
        w: 320,
        content: {'text': 'existing', 'autoWidth': false});
    await pumpShell(tester, preseeded: [other]);

    final pending = clickToCreate(200, 200);
    await settle(tester);
    expect(app.editingBlockId, pending.id);
    final startX = pending.x, startY = pending.y;

    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.arrowRight);

    expect(app.editingBlockId, pending.id,
        reason: 'still editing the SAME block — the arrow keys must never '
            'jump editing to a different one, even one right there');
    expect(app.pendingEmptyBlockId, pending.id,
        reason: 'still pending — sliding it around is not typing into it');
    expect(pending.x, greaterThan(startX),
        reason: 'ArrowRight moved the box itself to the right');
    expect(pending.y, greaterThan(startY),
        reason: 'ArrowDown moved the box itself further down the page');
    expect(app.blocks.any((x) => x.id == 'other'), isTrue,
        reason: 'the neighbour was never touched');
    app.cancelPendingSave();
  });

  testWidgets(
      'once typing has started, arrow keys go back to moving the text '
      'caret, even though the box is empty again', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pumpShell(tester);

    final b = clickToCreate(200, 200);
    await settle(tester);

    await type(tester, 'ab', 2);
    expect(app.pendingEmptyBlockId, isNull,
        reason: 'the pending window ended the moment typing started');

    await key(tester, LogicalKeyboardKey.arrowLeft);

    expect(app.editingBlockId, b.id,
        reason: 'arrow keys no longer navigate away once typing has begun '
            '— this is a one-time window before the FIRST keystroke, not a '
            'standing property of an empty box');
    expect(app.activeEditor!.controller.selection.baseOffset, 1,
        reason: 'the arrow moved the TEXT caret backward one place, not '
            'the page selection — proof it was NOT redirected to '
            'block-to-block navigation');

    // The caret really is at 1: a keystroke there produces "axb".
    await type(tester, 'axb', 2);
    expect(app.blocks.firstWhere((x) => x.id == b.id).content['text'], 'axb');

    // And backspacing back to empty must not reopen the pending window.
    await type(tester, '', 0);
    expect(app.blocks.firstWhere((x) => x.id == b.id).content['text'], '');
    expect(app.pendingEmptyBlockId, isNull,
        reason: 'emptied by backspace, not by never having been typed into '
            '— the pending state does not come back');
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(app.editingBlockId, b.id,
        reason: 'an arrow key still must not navigate away from an '
            'emptied-by-backspace box');
    app.cancelPendingSave();
  });
}
