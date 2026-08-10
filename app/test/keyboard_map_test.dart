// The keyboard map (docs/planning/v0.16-keyboard-control.md §1): one table,
// two consumers. These tests pin the table's invariants, that the Ctrl+/
// overlay renders ALL of it (the documentation cannot silently show less
// than the map), and that the chord works from the real shell — including
// while a text field is focused, which is the whole point of it.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
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
}
