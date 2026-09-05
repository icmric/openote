// The keyboard map (docs/planning/v0.16-keyboard-control.md §1): one table,
// two consumers. These tests pin the table's invariants, that the Ctrl+/
// overlay renders ALL of it (the documentation cannot silently show less
// than the map), and that the chord works from the real shell — including
// while a text field is focused, which is the whole point of it.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/app_shell.dart';
import 'package:openote/ui/keyboard_map.dart';
import 'package:openote/ui/shortcut_overlay.dart';

import 'support/sqlite.dart';

void main() {
  group('the map itself', () {
    test('every binding is complete: keys and a real description', () {
      for (final s in keyboardMap) {
        expect(s.title.trim(), isNotEmpty);
        expect(s.bindings, isNotEmpty,
            reason: 'section "${s.title}" documents nothing');
        for (final b in s.bindings) {
          expect(b.keys.trim(), isNotEmpty);
          expect(b.action.trim().length, greaterThanOrEqualTo(3),
              reason: '"${b.keys}" in "${s.title}" has no description');
        }
      }
    });

    test('no duplicate keys inside a section, no duplicate section titles',
        () {
      final titles = keyboardMap.map((s) => s.title).toList();
      expect(titles.toSet().length, titles.length);
      for (final s in keyboardMap) {
        final keys = s.bindings.map((b) => b.keys).toList();
        expect(keys.toSet().length, keys.length,
            reason: 'duplicate keys in "${s.title}"');
      }
    });

    test('canonical rows exist — deleting one is a decision, not an accident',
        () {
      final all = [
        for (final s in keyboardMap)
          for (final b in s.bindings) b.keys
      ];
      for (final pinned in [
        'Ctrl+/', // the reference itself
        'Ctrl+Z', // undo
        'Ctrl+N', // new page
        'Tab / Shift+Tab', // table cells
        'Ctrl+Enter', // run a code cell
        'Space', // study reveal
      ]) {
        expect(all, contains(pinned));
      }
    });
  });

  group('the overlay renders the whole map', () {
    testWidgets('every section title and every binding appears',
        (tester) async {
      // Tall surface so the whole list materialises — the claim is "the
      // overlay shows ALL of the map", not "scrolling works".
      //
      // It has to stay taller than the map: the list is lazy, so a row below
      // the fold is never built and `find.text` reports it missing. At 3000
      // the marker-chord rows pushed the very last binding ("Close it") off
      // the bottom and this test failed for a row that renders perfectly
      // well. Grow this number when the map grows, or the test starts
      // measuring the viewport instead of the overlay.
      tester.view.physicalSize = const Size(1000, 4200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        theme: onoteTheme(Brightness.light),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showShortcutOverlay(context),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      for (final s in keyboardMap) {
        expect(find.text(s.title), findsOneWidget);
        for (final b in s.bindings) {
          expect(find.text(b.action), findsWidgets,
              reason: '"${b.keys}" is in the map but not on screen');
        }
      }
    });
  });

  group('Ctrl+/ from the shell', () {
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());

    late Directory tmp;
    late Repository repo;
    late AppState app;

    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_keys_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Study');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      await app.selectPage(
          app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
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

    Future<void> chord(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyUpEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    testWidgets('opens the overlay, Escape closes it, and it toggles',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(tester);
      expect(find.text('Keyboard shortcuts'), findsNothing);

      await chord(tester, LogicalKeyboardKey.slash);
      expect(find.text('Keyboard shortcuts'), findsOneWidget);

      // Escape closes the overlay — and ONLY the overlay: the global
      // handler must not fall through to clear-selection underneath.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Keyboard shortcuts'), findsNothing);

      // Toggle: open, then the same chord closes instead of stacking.
      await chord(tester, LogicalKeyboardKey.slash);
      expect(find.text('Keyboard shortcuts'), findsOneWidget);
      await chord(tester, LogicalKeyboardKey.slash);
      expect(find.text('Keyboard shortcuts'), findsNothing);
    });

    testWidgets('works while a text field has focus', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(tester);

      // Focus the page title — a real EditableText owning the keyboard.
      final title = find.byType(EditableText).first;
      await tester.tap(title);
      await tester.pumpAndSettle();

      await chord(tester, LogicalKeyboardKey.slash);
      expect(find.text('Keyboard shortcuts'), findsOneWidget);
    });
  });

  group('block traversal (v0.16 phase 2)', () {
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());

    late Directory tmp;
    late Repository repo;
    late AppState app;
    // Reading order is y-then-x: a (top-left), b (top-right), c (below a).
    late Block a, b, c;

    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_trav_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Study');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
      a = Block(
          type: BlockType.text, x: 40, y: 120, w: 200, h: 60,
          content: {'markdown': 'alpha'});
      b = Block(
          type: BlockType.text, x: 420, y: 130, w: 200, h: 60,
          content: {'markdown': 'beta'});
      c = Block(
          type: BlockType.text, x: 40, y: 340, w: 200, h: 60,
          content: {'markdown': 'gamma'});
      app.importPage(nb.id, page.id, [a, b, c], PageProps());
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
        {bool ctrl = false, bool shift = false}) async {
      if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(k);
      await tester.sendKeyUpEvent(k);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    testWidgets('Tab walks reading order, Shift+Tab walks it backwards',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(tester);
      expect(app.selectedBlockId, isNull);

      await key(tester, LogicalKeyboardKey.tab);
      expect(app.selectedBlockId, a.id, reason: 'first Tab → first in order');
      await key(tester, LogicalKeyboardKey.tab);
      expect(app.selectedBlockId, b.id, reason: 'y ties broken by x');
      await key(tester, LogicalKeyboardKey.tab);
      expect(app.selectedBlockId, c.id);
      await key(tester, LogicalKeyboardKey.tab);
      expect(app.selectedBlockId, a.id, reason: 'wraps');
      await key(tester, LogicalKeyboardKey.tab, shift: true);
      expect(app.selectedBlockId, c.id, reason: 'Shift+Tab reverses');
    });

    testWidgets('arrows select spatially; Enter edits; Escape climbs out',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(tester);

      await key(tester, LogicalKeyboardKey.tab); // a
      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(app.selectedBlockId, b.id, reason: 'b is to a\'s right');
      await key(tester, LogicalKeyboardKey.arrowLeft);
      expect(app.selectedBlockId, a.id);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(app.selectedBlockId, c.id, reason: 'c is below a');
      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(app.selectedBlockId, a.id,
          reason: 'and back up — this is the press that caught the '
              'framework focus walk running in parallel');

      await key(tester, LogicalKeyboardKey.enter);
      expect(app.editingBlockId, a.id, reason: 'Enter edits the selection');
      await key(tester, LogicalKeyboardKey.escape);
      expect(app.editingBlockId, isNull, reason: 'Escape exits the editor');

      // Flush the autosave debounce the edit session armed, or the binding
      // fails the test for pending timers.
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
    });

    testWidgets('Ctrl+arrows nudge, clamp to the page, and undo as one step',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(tester);

      // The app's blocks are its own decoded instances, not the ones the
      // seed handed to importPage — read positions from the live one.
      Block live() => app.blocks.firstWhere((x) => x.id == a.id);

      await key(tester, LogicalKeyboardKey.tab); // a
      final x0 = live().x, y0 = live().y;

      await key(tester, LogicalKeyboardKey.arrowRight, ctrl: true);
      await key(tester, LogicalKeyboardKey.arrowRight, ctrl: true);
      await key(tester, LogicalKeyboardKey.arrowDown, ctrl: true);
      expect(live().x, greaterThan(x0));
      expect(live().y, greaterThan(y0));

      // Fine nudge: exactly one pixel.
      final xBefore = live().x;
      await key(tester, LogicalKeyboardKey.arrowRight,
          ctrl: true, shift: true);
      expect(live().x, xBefore + 1);

      // The burst is ONE undo entry: a single undo restores the start.
      app.undo();
      expect(live().x, x0, reason: 'one burst, one undo step');
      expect(live().y, y0);

      // Clamp: nudging left forever stops at the page edge, never negative.
      for (var i = 0; i < 30; i++) {
        await key(tester, LogicalKeyboardKey.arrowLeft, ctrl: true);
      }
      expect(live().x, greaterThanOrEqualTo(0));

      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
    });

    testWidgets('traversal keys stop at an open dialog', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(tester);

      await key(tester, LogicalKeyboardKey.tab);
      expect(app.selectedBlockId, a.id);

      // Open the shortcut overlay — a route on top of the shell.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.slash);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.slash);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('Keyboard shortcuts'), findsOneWidget);

      await key(tester, LogicalKeyboardKey.tab);
      expect(app.selectedBlockId, a.id,
          reason: 'Tab must not move selection behind a dialog');
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(app.selectedBlockId, a.id);
    });
  });
}
