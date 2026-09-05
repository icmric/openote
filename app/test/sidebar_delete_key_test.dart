// Del / Backspace on a navigator row — Eric: "Pressing 'Del' when clicking on
// a page or group doesnt delete it - only way to delete is right click and
// press delete" (PLANNING.md).
//
// Every claim here is made by pressing a REAL key at a REAL [Sidebar] over a
// REAL repository. The change is entirely about focus and key dispatch, and
// reasoning about Flutter focus from source has been wrong in this codebase
// before — see the note at the top of keyboard_regions_test.dart, where a
// HardwareKeyboard handler's `true` turned out not to stop the framework's own
// Shortcuts.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/state/page_protection.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/sync/op.dart';
import 'package:openote/sync/op_log.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/app_shell.dart';
import 'package:openote/ui/sidebar.dart';

import 'support/sqlite.dart';

Widget host(AppState app) => MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      theme: onoteTheme(Brightness.light),
      home: Scaffold(
        body: ListenableBuilder(
          listenable: app,
          builder: (_, __) => Sidebar(app: app),
        ),
      ),
    );

/// True when the widget that owns the keyboard sits under a [T].
///
/// The same ancestor walk keyboard_regions_test.dart uses, and the same reason:
/// "where is focus" has to be asked of the widget tree, because the rows and
/// their focus nodes are private to the navigator.
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

Future<void> press(WidgetTester tester, LogicalKeyboardKey k) async {
  await tester.sendKeyDownEvent(k);
  await tester.sendKeyUpEvent(k);
  await tester.pumpAndSettle();
}

/// Run the autosave debounce and the snackbar's own dismissal timer out.
///
/// Not a wait on anything — [testWidgets] fails a test that ends with a timer
/// still pending, and both a delete (which marks the notebook dirty) and the
/// snackbar it shows leave one behind.
Future<void> quiesce(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  group('the row you clicked', () {
    late Directory tmp;
    late Repository repo;
    late AppState app;
    late TreeNode chapter3;
    late TreeNode term2;
    late TreeNode yearTwelve;

    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_delkey_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('T');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
      TreeNode add(NodeKind kind, String title,
          {String? parent, String position = 'b0'}) {
        final n = app.importNode(
            nb.id,
            TreeNode(
                kind: kind,
                parentId: parent,
                title: title,
                position: position));
        app.reloadNodes();
        return n;
      }

      chapter3 =
          add(NodeKind.page, 'Chapter 3', parent: section.id, position: 'b0');
      term2 = add(NodeKind.section, 'Term 2', position: 'c0');
      yearTwelve = add(NodeKind.sectionGroup, 'Year 12', position: 'd0');
      await app.selectPage(chapter3.id);
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

    testWidgets('Del deletes the page, and the snackbar names what went',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await tester.pumpWidget(host(app));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chapter 3'));
      await tester.pumpAndSettle();
      expect(app.pageId, chapter3.id);

      await press(tester, LogicalKeyboardKey.delete);
      expect(app.node(chapter3.id), isNull,
          reason: 'Del on the row you just clicked deletes that node');
      expect(find.text('Chapter 3'), findsNothing);

      // A whole page leaving the tree on one keystroke with nothing said is
      // the failure mode the snackbar exists for.
      expect(find.textContaining('Deleted “Chapter 3”'), findsOneWidget);
      expect(find.textContaining('recycle bin'), findsOneWidget,
          reason: 'it is a 30-day soft delete, so say where it went');
      await quiesce(tester);
    });

    testWidgets('Del deletes a section too', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await tester.pumpWidget(host(app));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Term 2'));
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.delete);
      expect(app.node(term2.id), isNull);
      expect(find.text('Term 2'), findsNothing);
      await quiesce(tester);
    });

    testWidgets('Del deletes a section group too', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await tester.pumpWidget(host(app));
      await tester.pumpAndSettle();

      // A group row's click TOGGLES it open/closed — it has no selected state
      // at all, which is why focus rather than a selection field had to be the
      // answer to "which node is the navigator on".
      await tester.tap(find.text('Year 12'));
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.delete);
      expect(app.node(yearTwelve.id), isNull);
      expect(find.text('Year 12'), findsNothing);
      await quiesce(tester);
    });

    testWidgets('Backspace deletes as well — a Mac laptop has no Del key',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await tester.pumpWidget(host(app));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chapter 3'));
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.backspace);
      expect(app.node(chapter3.id), isNull);
      await quiesce(tester);
    });

    testWidgets('a locked node is refused, and told why', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.protectNode(term2.id, 'pw', UnlockPolicy.session);
      await tester.pumpWidget(host(app));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Term 2'));
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.delete);
      expect(app.node(term2.id), isNotNull,
          reason: 'a passcode is a standing "not by accident" mark, and a bare '
              'Del is exactly the accident it exists to catch');
      expect(find.text('Term 2'), findsOneWidget);
      expect(find.textContaining('is locked'), findsOneWidget);
      expect(find.textContaining('Deleted'), findsNothing);
      await quiesce(tester);
    });

    testWidgets('the key belongs to the rename field, not to the tree',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await tester.pumpWidget(host(app));
      await tester.pumpAndSettle();

      // The double-click window is measured against wall-clock, which
      // `tester.pump(Duration)` does not advance — so the two clicks are put
      // 80 ms apart by DRIVING the clock (see [sidebarNow]). Left to real time
      // this would assert how fast the machine rebuilds the sidebar.
      var fake = DateTime(2026, 8, 22, 12);
      sidebarNow = () => fake;
      addTearDown(() => sidebarNow = DateTime.now);
      await tester.tap(find.text('Chapter 3'));
      await tester.pump(const Duration(milliseconds: 80));
      fake = fake.add(const Duration(milliseconds: 80));
      await tester.tap(find.text('Chapter 3'));
      await tester.pumpAndSettle();

      // The navigator always holds ONE TextField (the search box); the inline
      // rename editor makes it two.
      expect(
          find.descendant(
              of: find.byType(Sidebar), matching: find.byType(TextField)),
          findsNWidgets(2),
          reason: 'the rename editor is open and holds the keyboard');

      await press(tester, LogicalKeyboardKey.backspace);
      expect(app.node(chapter3.id), isNotNull,
          reason: 'the row sits ABOVE its own rename field in the focus chain '
              'and Flutter walks that chain upwards, so without the gate '
              'backspacing a typo out of a new name deleted the page');
      expect(find.byType(SnackBar), findsNothing);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await quiesce(tester);
    });

    testWidgets('the keyboard lands on a live row, never on the dead one',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await tester.pumpWidget(host(app));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Term 2'));
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.delete);
      expect(app.node(term2.id), isNull);

      // Focus falling back to the route's root scope would leave the navigator
      // keyboard-dead: the next Del reaches no row handler at all, and there is
      // nothing on screen saying where the keyboard went.
      expect(focusIsUnder<Sidebar>(), isTrue,
          reason: 'the dying row must hand the keyboard on before it goes');
      await quiesce(tester);
    });

    testWidgets('one Del deletes ONE thing, with a block still selected',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The whole shell, because the hazard lives between two handlers: the
      // shell's global Delete (app_shell.dart) runs BEFORE focus dispatch and
      // cannot see that the navigator now owns the key. Clicking a PAGE row
      // hides it — `selectPage` clears the block selection on the way past —
      // so the case that catches it is a section with no pages of its own,
      // which leaves the open page exactly where it was.
      final block = Block(
          type: BlockType.text,
          x: 40,
          y: 120,
          w: 320,
          h: 90,
          content: {'text': 'the note that must survive'});
      app.importPage(app.notebookId!, chapter3.id, [block], PageProps());
      await app.selectPage(chapter3.id);
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

      app.select(block.id);
      await tester.pumpAndSettle();
      expect(app.selectedIds, contains(block.id));

      await tester.tap(find.text('Term 2'));
      await tester.pumpAndSettle();
      expect(app.pageId, chapter3.id, reason: 'Term 2 has no page to jump to');

      await press(tester, LogicalKeyboardKey.delete);
      expect(app.node(term2.id), isNull, reason: 'the section still goes');
      expect(app.blocks.map((b) => b.id), contains(block.id),
          reason: 'and the block on the page it left behind does NOT');
      await quiesce(tester);
    });
  });

  testWidgets('a read-only notebook loses nothing, and is not told that it did',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    late Directory ws;
    late Repository repo;
    late AppState app;
    late TreeNode page;
    await tester.runAsync(() async {
      // A notebook is read-only when its log holds operations written under an
      // envelope this build cannot decode (AppState.notebookIsReadOnly), so the
      // fixture plants one rather than faking the flag.
      AppState.syncLogEnabled = true;
      ws = Directory.systemTemp.createTempSync('onote_delkey_ro_');
      repo = await Repository.openAt(ws);
      final nb = await repo.createNotebook('Read only');
      OpLogStore.forNotebook(nb.file)
        ..ensureInitialised(notebookId: nb.id, title: 'Read only')
        ..append('another-device', [
          Op(
            device: 'another-device',
            seq: 1,
            lamport: 1,
            timestamp: 1,
            kind: OpKind.nodeUpsert,
            version: opFormatVersion + 1,
            data: {
              'id': 'planted',
              'kind': 'page',
              'title': 'Term 1',
              'position': 'a0'
            },
          ),
        ]);
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      await app.warmRecorder(nb.id);
      page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
      await app.selectPage(page.id);
    });
    addTearDown(() {
      app.cancelPendingSave();
      repo.dispose();
      try {
        ws.deleteSync(recursive: true);
      } catch (_) {}
    });
    expect(app.notebookIsReadOnly(app.notebookId!), isTrue,
        reason: 'the fixture has to be genuinely read-only to prove anything');

    await tester.pumpWidget(host(app));
    await tester.pumpAndSettle();
    await tester.tap(find.text(page.title));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.delete);

    expect(app.node(page.id), isNotNull,
        reason: 'AppState.deleteNode declines on a read-only notebook');
    // "Deleted X" with X still sitting in the list is worse than silence — the
    // snackbar reports what the TREE says, not what the keypress asked for.
    expect(find.byType(SnackBar), findsNothing);
    await quiesce(tester);
  });
}
