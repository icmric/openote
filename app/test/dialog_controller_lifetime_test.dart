// A TextEditingController must outlive every widget that can still build with
// it — and a popped dialog can still build for 150 ms.
//
// The report was "creating a notebook crashes the app": type a name into the
// New notebook prompt, press Enter, get a full-screen
// `'_dependents.isEmpty': is not true` from `InheritedElement.debugDeactivated`.
// That assertion is three exceptions downstream of the mistake. The prompt made
// its controller beside the await and disposed it in a `finally`; the dialog's
// future completes when the route is POPPED, and `showOnoteDialog`'s exit
// transition runs after that, so the field was still mounted. Its next rebuild
// re-subscribed to `Listenable.merge([focusNode, controller])`, `addListener`
// threw on the disposed controller, the framework abandoned that update
// half-done, and the route left the overlay with dependents still registered.
//
// The second group is the same shape one layer down: AppState registers the
// live editor's controller for the toolbar's caret state, and a page or
// notebook switch disposed that controller without ever telling AppState.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/app_shell.dart';
import 'package:openote/ui/onote_dialog.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  group('a text prompt survives its own closing animation', () {
    testWidgets('submitting with Enter raises nothing', (t) async {
      String? got;
      await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                got = await promptForText(context,
                    title: 'New notebook', okLabel: 'Create');
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Chemistry');
      // Enter, exactly as reported — not a tap on Create.
      await t.testTextInput.receiveAction(TextInputAction.done);
      // Through the whole 150 ms exit transition: the frames AFTER the pop are
      // the ones that used to build against a disposed controller.
      await t.pumpAndSettle();

      expect(got, 'Chemistry');
      expect(t.takeException(), isNull);
    });

    testWidgets('cancelling raises nothing either', (t) async {
      await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  promptForText(context, title: 'New', okLabel: 'Create'),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'discarded');
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  group('creating a notebook while a text box is being edited', () {
    late Repository repo;
    late Directory tmp;
    late AppState app;

    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_prompt_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('First');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false
        ..onboardingSeen = true;
      app.reloadNodes();
      app.activeSectionId =
          app.nodes.firstWhere((n) => n.kind == NodeKind.section).id;
      await app
          .selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
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

    Block editableBlock() => app.addBlock(Block(
        type: BlockType.text,
        x: 100,
        y: 200,
        w: 300,
        h: 120,
        content: {'text': 'hello', 'autoWidth': false}));

    // The reported crash, end to end through the real shell: notebook bar →
    // Notebooks → New → type → Enter, with a live editor on the canvas.
    testWidgets('the reported path raises nothing', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      final b = editableBlock();
      await t.pumpWidget(MaterialApp(
        localizationsDelegates: kOnoteLocalizations,
        supportedLocales: kOnoteLocales,
        home: AppShell(app: app),
      ));
      await t.pump();
      await t.pump();

      app.select(b.id, edit: true);
      await t.pumpAndSettle();
      expect(app.activeEditor, isNotNull,
          reason: 'precondition: a live editor is registered');

      await t.tap(find.text('First').first);
      await t.pumpAndSettle();
      await t.tap(find.text('New'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, 'Second');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      await t.pump(const Duration(milliseconds: 800));
      await t.pumpAndSettle();

      expect(t.takeException(), isNull);
      expect(app.notebooks.map((n) => n.title), contains('Second'));
    });

    // The half AppState owns: the editor registration must not outlive the
    // controller it points at. Insert ▸ Image and Insert ▸ Flashcard gate on
    // `activeEditor != null` alone and then WRITE through it, so a stale
    // registration is a use-after-dispose waiting for the next menu click.
    testWidgets('switching notebooks releases the registered editor',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final b = editableBlock();
      await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: app,
            builder: (_, __) => SizedBox(
                width: 800, height: 600, child: PageCanvas(state: app)),
          ),
        ),
      ));
      await t.pump();
      await t.pump();

      app.select(b.id, edit: true);
      await t.pump();
      await t.pump();
      expect(app.activeEditor, isNotNull);

      await t.runAsync(() => app.createNotebook('Second'));
      await t.pump();
      await t.pump();

      expect(app.activeEditor, isNull,
          reason: 'the controller behind it was disposed with the old page');
      expect(app.activeSession, isNull);
      expect(t.takeException(), isNull);
    });

    // Same for switching pages inside one notebook — the same element-replacing
    // mechanism (BlockView is keyed on docRevision), reached far more often.
    testWidgets('switching pages releases it too', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final first = app.pageId!;
      await t.runAsync(() => app.addPage());
      final other = app.pageId!;
      expect(other, isNot(first));
      await t.runAsync(() => app.selectPage(first));
      final b = editableBlock();
      await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: app,
            builder: (_, __) => SizedBox(
                width: 800, height: 600, child: PageCanvas(state: app)),
          ),
        ),
      ));
      await t.pump();
      await t.pump();

      app.select(b.id, edit: true);
      await t.pump();
      await t.pump();
      expect(app.activeEditor, isNotNull);

      await t.runAsync(() => app.selectPage(other));
      await t.pump();
      await t.pump();

      expect(app.activeEditor, isNull);
      expect(t.takeException(), isNull);
    });
  });
}
