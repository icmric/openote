// v0.16 phase 3 — F6 region cycling and the dialog Enter/Escape audit.
//
// Everything here sends real key events at the real shell. Reasoning about
// Flutter focus from source has been wrong here before (phase 2's note: a
// HardwareKeyboard handler's `true` does not stop the framework's own
// Shortcuts), so the claims are made by pressing the keys.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/planner/alerts.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/alert_popup.dart';
import 'package:openote/ui/app_shell.dart';
import 'package:openote/ui/command_bar.dart';
import 'package:openote/ui/sidebar.dart';
import 'package:openote/ui/study_panel.dart';

import 'support/sqlite.dart';

/// True when the widget that owns the keyboard sits under a [T].
///
/// The same ancestor walk the shell itself uses to spot a focused text field
/// — the regions are private to the shell, so "where is focus" is asked of
/// the widget tree rather than of a field the test cannot see.
bool focusIsUnder<T extends Widget>() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  var found = false;
  ctx.visitAncestorElements((e) {
    if (e.widget is T) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;
  late Block a;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_regions_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Study');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
    // `'text'` is THE content key for a text block (block_view.dart §384).
    // Seeding `'markdown'` builds an EMPTY box that still passes any test
    // which only ever looks at which block is selected — and an empty box
    // cannot show you whether the caret moved.
    a = Block(
        type: BlockType.text,
        x: 40,
        y: 120,
        w: 320,
        h: 170,
        content: {'text': 'alpha\nsecond line'});
    app.importPage(nb.id, page.id, [a], PageProps());
    app.reloadNodes();
    await app.selectPage(page.id);
    app.markOnboardingSeen();
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

  Future<void> pumpShell(WidgetTester tester) async {
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

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k,
      {bool shift = false, bool ctrl = false}) async {
    if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(k);
    await tester.sendKeyUpEvent(k);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  group('F6 region cycling', () {
    testWidgets('walks sidebar → toolbar → page and back, both directions',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(tester);

      // The shell autofocuses the canvas, so the walk starts on the page.
      // Forward from the last region wraps to the first.
      await key(tester, LogicalKeyboardKey.f6);
      expect(focusIsUnder<Sidebar>(), isTrue,
          reason: 'F6 from the page wraps round to the sidebar');

      await key(tester, LogicalKeyboardKey.f6);
      expect(focusIsUnder<CommandBar>(), isTrue,
          reason: 'the toolbar was previously unreachable by any key');

      await key(tester, LogicalKeyboardKey.f6);
      expect(focusIsUnder<CommandBar>(), isFalse);
      expect(focusIsUnder<Sidebar>(), isFalse,
          reason: 'third stop is the page');

      // Backwards retraces exactly.
      await key(tester, LogicalKeyboardKey.f6, shift: true);
      expect(focusIsUnder<CommandBar>(), isTrue);
      await key(tester, LogicalKeyboardKey.f6, shift: true);
      expect(focusIsUnder<Sidebar>(), isTrue);
    });

    testWidgets('returning to the page turns block traversal back on',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(tester);

      await key(tester, LogicalKeyboardKey.f6); // sidebar
      expect(focusIsUnder<Sidebar>(), isTrue);
      // Tab in the sidebar must NOT move block selection — the canvas
      // shortcuts are gated on the canvas node holding focus.
      await key(tester, LogicalKeyboardKey.tab);
      expect(app.selectedBlockId, isNull);

      await key(tester, LogicalKeyboardKey.f6, shift: true); // back to page
      await key(tester, LogicalKeyboardKey.tab);
      expect(app.selectedBlockId, a.id,
          reason: 'F6 back to the page restores Tab-selects-a-block');
    });

    testWidgets('works while a text box is being edited', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(tester);

      await key(tester, LogicalKeyboardKey.tab); // select the block
      await key(tester, LogicalKeyboardKey.enter); // edit it
      expect(app.editingBlockId, a.id);

      await key(tester, LogicalKeyboardKey.f6);
      expect(focusIsUnder<Sidebar>(), isTrue,
          reason: 'getting out of the box you are in is the point of F6');

      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
    });

    testWidgets('an open panel joins the rotation, and F6 lands on its body',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.showPanel(SidePanelKind.study);
      await pumpShell(tester);

      // Page → panel is one step forward once a panel is open.
      await key(tester, LogicalKeyboardKey.f6);
      expect(focusIsUnder<StudyPanel>(), isTrue);

      // …and specifically on the node that OWNS Space and 1-4, not on the
      // header's Close button. Landing on Close would mean the first key a
      // student presses in the study panel shuts it.
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'study');
      await key(tester, LogicalKeyboardKey.space);
      expect(app.openPanel, SidePanelKind.study,
          reason: 'Space in the panel must not hit Close');

      await key(tester, LogicalKeyboardKey.f6);
      expect(focusIsUnder<Sidebar>(), isTrue, reason: 'then it wraps');
    });

    testWidgets('a reminder that has popped up joins the rotation',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The one popup in the app with no keyboard route of ANY kind: not a
      // route, so nothing in the framework dismissed it, and not in the Tab
      // order of anything reachable — so it sat there until a mouse arrived.
      app.planner.pendingAlerts.add(PlannerAlert(
        id: 'r1',
        source: AlertSource.event,
        title: 'Physics in 10 minutes',
        at: DateTime.now(),
      ));
      await pumpShell(tester);
      expect(find.text('Physics in 10 minutes'), findsOneWidget);

      // Page → (no panel) → alerts, so one F6 forward reaches it.
      await key(tester, LogicalKeyboardKey.f6);
      expect(focusIsUnder<AlertPopup>(), isTrue);

      // And the card's own buttons are now under the keyboard, which is the
      // point: Escape was rejected for this because dismissing a reminder
      // persists, so a stray keystroke would lose one unread.
      expect(app.planner.pendingAlerts, hasLength(1));
      await key(tester, LogicalKeyboardKey.f6);
      expect(focusIsUnder<Sidebar>(), isTrue, reason: 'then it wraps');
    });

    testWidgets('does nothing behind a dialog', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(tester);
      await key(tester, LogicalKeyboardKey.slash, ctrl: true);
      expect(find.text('Keyboard shortcuts'), findsOneWidget);

      await key(tester, LogicalKeyboardKey.f6);
      expect(focusIsUnder<Sidebar>(), isFalse,
          reason: 'F6 must not pull focus out from under a dialog');
      expect(find.text('Keyboard shortcuts'), findsOneWidget);
    });
  });

  group('an editor being typed in is never shadowed', () {
    // The field bug this pins: canvas-level Shortcuts sit between every
    // editor and the app root, and nearest-ancestor wins — so without the
    // `_CanvasAction` focus gate, arrows moved between BOXES instead of
    // moving the caret and Enter was eaten instead of making a new line.
    // Phase 3 added a second Focus node around the same subtree, which is
    // exactly the kind of change that reintroduces it.
    testWidgets('arrows move the caret, and never the block selection',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // A second block directly below, so a leaked _SpatialIntent has
      // somewhere obvious to jump to.
      app.addBlock(Block(
          type: BlockType.text,
          x: 40,
          y: 430,
          w: 320,
          h: 110,
          content: {'text': 'beta'}));
      await pumpShell(tester);

      await key(tester, LogicalKeyboardKey.tab);
      expect(app.selectedBlockId, a.id);
      await key(tester, LogicalKeyboardKey.enter);
      expect(app.editingBlockId, a.id);

      final ctl = app.activeEditor!.controller;
      ctl.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      expect(ctl.text, 'alpha\nsecond line', reason: 'the box really has text');

      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(ctl.selection.baseOffset, 1,
          reason: 'the caret moved one character, not one box');
      expect(app.selectedBlockId, a.id);
      expect(app.editingBlockId, a.id);

      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(ctl.selection.baseOffset, greaterThan(5),
          reason: 'Down moved the caret to the second LINE of this box');
      expect(app.selectedBlockId, a.id,
          reason: 'Down inside an editor must not select the block below');
      expect(app.editingBlockId, a.id);

      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(ctl.selection.baseOffset, lessThanOrEqualTo(5),
          reason: 'and back to the first line');
      expect(app.selectedBlockId, a.id);

      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
    });

    testWidgets('Enter reaches the editor and makes the next line',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // A bullet, because a plain newline cannot be asserted in a widget
      // test at all: on desktop the field inserts one via the platform text
      // input service, which does not run here. List continuation is the one
      // Enter behaviour that lives entirely in Dart key handling, so it is
      // the one that can prove Enter arrived.
      app.addBlock(Block(
          type: BlockType.text,
          x: 420,
          y: 120,
          w: 320,
          h: 110,
          content: {'text': '- milk'}));
      await pumpShell(tester);

      final list = app.blocks.firstWhere((b) => b.content['text'] == '- milk');
      app.select(list.id, edit: true);
      await tester.pumpAndSettle();
      final ctl = app.activeEditor!.controller;
      ctl.selection = const TextSelection.collapsed(offset: 6);
      await tester.pump();

      await key(tester, LogicalKeyboardKey.enter);
      expect(ctl.text, '- milk\n- ',
          reason: 'the canvas swallowed Enter instead of letting the list '
              'continue');
      expect(app.editingBlockId, list.id);

      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
    });

    testWidgets('a letter types instead of switching tool', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(tester);
      final tool = app.tool;
      await key(tester, LogicalKeyboardKey.tab);
      await key(tester, LogicalKeyboardKey.enter);
      expect(app.editingBlockId, a.id);

      // P is the pen, V is select, E is the eraser — all bare-letter tool
      // chords, and all of them must be inert while a box is being written
      // in. This is the bug that made those letters untypeable.
      for (final k in [
        LogicalKeyboardKey.keyP,
        LogicalKeyboardKey.keyV,
        LogicalKeyboardKey.keyE,
      ]) {
        await key(tester, k);
      }
      expect(app.tool, tool, reason: 'typing must not change the tool');
      expect(app.editingBlockId, a.id);

      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
    });
  });

  group('find on the page', () {
    testWidgets('Enter walks the matches forward, Shift+Enter back',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // A match is a BLOCK, not an occurrence (app_state `findMatches` is a
      // list of block ids), so three matches means three boxes.
      for (var i = 0; i < 3; i++) {
        app.addBlock(Block(
            type: BlockType.text,
            x: 420.0 + i * 340,
            y: 120,
            w: 320,
            h: 140,
            content: {'text': 'note $i'}));
      }
      await pumpShell(tester);

      await key(tester, LogicalKeyboardKey.keyF, ctrl: true);
      expect(app.findOpen, isTrue);
      await tester.enterText(
          find.widgetWithText(TextField, 'Find on this page…'), 'note');
      await tester.pumpAndSettle();
      expect(app.findMatches.length, greaterThanOrEqualTo(3));

      final n = app.findMatches.length;
      final start = app.findIndex;
      await key(tester, LogicalKeyboardKey.enter);
      expect(app.findIndex, (start + 1) % n, reason: 'Enter is the next match');

      // The second Enter is the one that used to do nothing: Enter arrived
      // as a submit action, which unfocused the field it came from.
      await key(tester, LogicalKeyboardKey.enter);
      expect(app.findIndex, (start + 2) % n,
          reason: 'Enter must keep cycling, not kill its own field');

      // And back — the direction that had no keyboard route at all, so
      // going up the page meant reaching for the little arrow with a mouse.
      await key(tester, LogicalKeyboardKey.enter, shift: true);
      expect(app.findIndex, (start + 1) % n,
          reason: 'Shift+Enter is the previous one');

      await key(tester, LogicalKeyboardKey.escape);
      expect(app.findOpen, isFalse);
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
    });
  });

  group('the focus ring', () {
    /// The ring is the only thing on screen drawn as a 2px box border in the
    /// primary colour, so counting those is how the test sees it.
    int rings(WidgetTester tester) {
      final scheme = onoteTheme(Brightness.light).colorScheme;
      return tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .where((d) {
        final dec = d.decoration;
        if (dec is! BoxDecoration) return false;
        final b = dec.border;
        return b is Border &&
            b.top.width == 2 &&
            b.top.color == scheme.primary &&
            b.isUniform;
      }).length;
    }

    testWidgets('appears on F6 and goes away on the next click',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(tester);
      expect(rings(tester), 0, reason: 'nothing marked before any F6');

      await key(tester, LogicalKeyboardKey.f6);
      expect(rings(tester), 1, reason: 'exactly one region is marked');

      // The status bar, not the canvas: a click on the page with the text
      // tool live makes a box and arms the autosave debounce, and this test
      // is about the marker, not about what the click did.
      await tester.tapAt(const Offset(700, 890));
      await tester.pumpAndSettle();
      expect(rings(tester), 0,
          reason: 'steering with the mouse retires the keyboard marker');
    });
  });
}
