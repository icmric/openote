// Picking up the pen puts the keyboard down.
//
// The owner: *"if i taped on the screen previously so there is the cursor but
// no text in the box, if i start drawing the cursor stays flashing and the
// outline of the box goes dashed for some reason. Doesnt affect drawing, but
// still annoying."*
//
// One cause, both symptoms. `AppState.setTool` clears the selection — which
// is what ends editing — only on a tool the user CHOSE:
//
//     if (t != Tool.select && !automatic) select(null);
//
// A pen announces itself by hovering, and `PageCanvas._stylusProximity`
// answers with `setTool(Tool.pen, automatic: true)` so that the pen means ink
// with no trip to the toolbar. That path skipped the clear deliberately — an
// automatic switch must not take away a selection somebody made — but it took
// the editor with it, so:
//
//  * `editingBlockId` survived, the field kept focus, and the caret went on
//    blinking in a box nobody could type into; and
//  * the box stayed in `selectedIds`, and `PageCanvas` deliberately draws a
//    dashed box round EVERYTHING selected while a drawing tool is in hand
//    (a block's own chrome is suppressed then, so the dashes are the only
//    thing left saying what a drag would pick up). Hence the outline.
//
// `AppState.inkToolInHand` already states the rule this broke, in its own
// doc: *"a block goes inert and loses its bar while one of these is held, so
// that the pen can write over it."* A box with a live caret is not inert.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_penbox_');
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

  Future<void> pumpShell(WidgetTester t,
      {List<Block> preseeded = const []}) async {
    final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
    if (preseeded.isNotEmpty) {
      app.importPage(app.notebookId!, page.id, preseeded, PageProps());
      app.reloadNodes();
    }
    await app.selectPage(page.id);
    app.markOnboardingSeen();
    t.view.physicalSize = const Size(1500, 950);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      theme: onoteTheme(Brightness.light),
      home: AppShell(app: app),
    ));
    await t.pump(const Duration(milliseconds: 900));
    await t.pumpAndSettle();
  }

  /// The exact sequence `PageCanvas._createTextAt` runs on a tap on empty
  /// canvas, which is what leaves a caret with no box drawn round it.
  Block tapOnEmptyCanvas() {
    final b = app.addBlock(Block(
      type: BlockType.text,
      x: 260,
      y: 320,
      w: 320,
      content: {'text': '', 'autoWidth': false},
    ));
    app.pendingEmptyBlockId = b.id;
    app.select(b.id, edit: true);
    return b;
  }

  /// A block with a stroke in it, so there is something a selection can
  /// legitimately be holding when the pen arrives.
  Block ink() => Block(
      type: BlockType.ink,
      x: 700,
      y: 300,
      w: 200,
      h: 100,
      content: {
        'strokes': [
          Stroke(
            tool: 'pen',
            colorHex: '#211F1B',
            size: 3,
            x: const [710, 790, 880],
            y: const [320, 350, 380],
            p: const [1, 1, 1],
            t: const [0, 1, 2],
          ).toJson(),
        ]
      });

  testWidgets('the pen arriving closes a box you only tapped into', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pumpShell(t);
    final box = tapOnEmptyCanvas();
    await t.pumpAndSettle();
    expect(app.editingBlockId, box.id, reason: 'precondition: caret is in it');

    // What a pen hovering over the digitiser does — see
    // `PageCanvas._stylusProximity`.
    app.setTool(Tool.pen, automatic: true);
    await t.pumpAndSettle();

    expect(app.editingBlockId, isNull, reason: 'the caret stops blinking');
    expect(app.blocks.any((b) => b.id == box.id), isFalse,
        reason: 'an empty box removes itself on the way out, as it always has');
    expect(app.selectedIds, isEmpty,
        reason: 'and so there is nothing left to draw a dashed box round');
    app.cancelPendingSave();
  });

  testWidgets('a box you had written in is closed but kept', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final written = Block(
        type: BlockType.text,
        x: 260,
        y: 320,
        w: 320,
        content: {'text': 'osmosis', 'autoWidth': false});
    await pumpShell(t, preseeded: [written]);
    app.select(written.id, edit: true);
    await t.pumpAndSettle();
    expect(app.editingBlockId, written.id, reason: 'precondition');

    app.setTool(Tool.pen, automatic: true);
    await t.pumpAndSettle();

    expect(app.editingBlockId, isNull);
    expect(app.blocks.any((b) => b.id == written.id), isTrue,
        reason: 'it has words in it; only an empty one clears itself away');
    expect(app.selectedIds, isEmpty,
        reason: 'the box was in `selectedIds` because the EDITOR put it '
            'there, not because anybody picked it up — and leaving it there '
            'would make the first stroke drawn inside the paragraph drag the '
            'paragraph (PageCanvas._selectionTakes), not draw');
    app.cancelPendingSave();
  });

  testWidgets('NEGATIVE CONTROL: an automatic switch keeps a selection',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // The rule the `automatic` branch exists for, and which this must not
    // undo: *"a tool somebody CHOSE is never taken off them"* — and neither
    // is a selection they made. Only the EDITOR goes, because that is the one
    // thing a pen in the hand contradicts.
    final strokes = ink();
    await pumpShell(t, preseeded: [strokes]);
    app.select(strokes.id);
    await t.pumpAndSettle();
    expect(app.selectedIds, contains(strokes.id), reason: 'precondition');

    app.setTool(Tool.pen, automatic: true);
    await t.pumpAndSettle();

    expect(app.selectedIds, contains(strokes.id),
        reason: 'the pen coming near must not drop what you picked up');
    app.cancelPendingSave();
  });

  testWidgets('NEGATIVE CONTROL: choosing the pen by hand still clears all',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final strokes = ink();
    await pumpShell(t, preseeded: [strokes]);
    app.select(strokes.id);
    await t.pumpAndSettle();

    app.setTool(Tool.pen);
    await t.pumpAndSettle();

    expect(app.selectedIds, isEmpty, reason: 'unchanged behaviour');
    expect(app.editingBlockId, isNull);
    app.cancelPendingSave();
  });

  testWidgets('NEGATIVE CONTROL: going back to Select leaves editing alone',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // The pen leaving reverts the tool automatically, and that must not be a
    // second way to close a box: by then the pen is gone and the keyboard is
    // the thing in hand again.
    final written = Block(
        type: BlockType.text,
        x: 260,
        y: 320,
        w: 320,
        content: {'text': 'osmosis', 'autoWidth': false});
    await pumpShell(t, preseeded: [written]);
    app.select(written.id, edit: true);
    await t.pumpAndSettle();

    app.setTool(Tool.select, automatic: true);
    await t.pumpAndSettle();

    expect(app.editingBlockId, written.id, reason: 'still typing in it');
    app.cancelPendingSave();
  });
}
