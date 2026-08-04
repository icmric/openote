// Smoke tests for the three dialogs that had none.
//
// The v0.3 plan lists `sync_dialog`, `onboarding` and the notebook manager
// among "the surfaces with no tests", and the last review made the case for why
// that is worth more than it looks: BOTH bugs that shipped in the command bar
// were layout failures — a `Spacer` under an unbounded constraint, and a `Row`
// overflowing at 560px — and neither was visible to any state test or to
// reading the code. A dialog is exactly the same shape of risk: it is built
// once, in a window size the author happened to have.
//
// So these are deliberately shallow. They mount each dialog for real, at a
// couple of window sizes, and assert it lays out and shows its own name. That
// is the whole class of bug they exist to catch.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/notebook_manager.dart';
import 'package:openote/ui/onboarding.dart';
import 'package:openote/ui/sync_dialog.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Future<AppState> newApp(WidgetTester tester) async {
    late AppState app;
    late Repository repo;
    final tmp = Directory.systemTemp.createTempSync('onote_dialogs_');
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await tester.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Smoke');
      app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      await app.selectPage(
          app.nodes.where((n) => n.kind == NodeKind.page).first.id);
    });
    return app;
  }

  /// Mount a host whose button opens [open], tap it, and settle.
  Future<void> openDialog(
    WidgetTester tester,
    AppState app,
    Future<void> Function(BuildContext, AppState) open, {
    required Size window,
  }) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => open(context, app),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    // The debounced workspace write (400ms) is drained too, so a dialog that
    // touches settings doesn't leave a pending timer behind.
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
  }

  // A laptop with the navigator open, and a small window. Both are ordinary,
  // and the second is where the command bar's overflow bug lived.
  const sizes = [Size(1280, 800), Size(900, 620)];

  for (final size in sizes) {
    final label = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('the notebook manager opens and lists notebooks ($label)',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = await newApp(tester);
      await openDialog(tester, app, (c, a) => showNotebookManager(c, a),
          window: size);

      expect(tester.takeException(), isNull);
      expect(find.text('Notebooks'), findsOneWidget);
      expect(find.text('Smoke'), findsWidgets, reason: 'the notebook is listed');
      // Every action it offers must be reachable, not clipped off the edge.
      for (final label in ['New', 'Import', 'Get started', 'Done']) {
        expect(find.text(label), findsOneWidget, reason: '"$label" is missing');
      }
    });

    testWidgets('the sync dialog opens ($label)', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = await newApp(tester);
      await openDialog(tester, app, (c, a) => showSyncDialog(c, a),
          window: size);

      expect(tester.takeException(), isNull,
          reason: 'the sync dialog failed to lay out at $label');
      expect(find.byType(AlertDialog), findsOneWidget);
      // Reported as hard to find: this dialog is where people are thinking
      // about where notebooks live, so adding one belongs here too.
      expect(find.text('Add a notebook…'), findsOneWidget);
    });

    testWidgets('the welcome flow opens ($label)', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = await newApp(tester);
      await openDialog(tester, app, (c, a) => showOnboarding(c, a),
          window: size);

      expect(tester.takeException(), isNull,
          reason: 'onboarding failed to lay out at $label');
      expect(find.byType(Dialog), findsWidgets);
    });
  }
}
