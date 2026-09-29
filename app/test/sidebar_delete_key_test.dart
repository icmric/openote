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
      // the failure mode the snackbar exists for. It says what went and
      // offers to put it back — it used to spend its words sending you to
      // the recycle bin instead, which is a errand, not an answer.
      expect(find.text('Deleted page “Chapter 3”'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
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

    testWidgets('clicking the bar background takes the aim off a section',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The reported bug: "if i click a page it deletes that page, but if i
      // click elsewhere (i.e. in the bar not on a page ...) it will delete the
      // section". Clicking a row focused it and nothing ever took that focus
      // back, so a click on empty space left the keyboard pointed at a section
      // the user had stopped thinking about — with no highlight to say so.
      await tester.pumpWidget(host(app));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Term 2'));
      await tester.pumpAndSettle();
      await app.selectPage(chapter3.id);
      await tester.pumpAndSettle();

      // Empty space in the navigator, below the last row.
      final bar = tester.getRect(find.byType(Sidebar));
      await tester.tapAt(Offset(bar.center.dx, bar.bottom - 60));
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.delete);
      expect(app.node(term2.id), isNotNull,
          reason: 'a section goes only when its own row was clicked');
      expect(app.node(chapter3.id), isNull,
          reason: 'the page you are on is what a bare Del means here');
      await quiesce(tester);
    });

    testWidgets('a focused navigator row is recognisable as one', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The shell stands a navigator row down when you click the toolbar, so
      // that reaching up for Bold cannot leave a section armed for the next
      // Del. It must recognise a row WITHOUT recognising a text field: a
      // toolbar button that took focus from the paragraph would close the
      // editor it was about to format. [NavRowFocus] is that discriminator,
      // so it is worth one test that it is really what holds the keyboard.
      await tester.pumpWidget(host(app));
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, isNot(isA<NavRowFocus>()),
          reason: 'nothing is armed before a row is clicked');

      await tester.tap(find.text('Term 2'));
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, isA<NavRowFocus>());
      await quiesce(tester);
    });

    testWidgets('and a section still goes when its own row IS the one clicked',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await tester.pumpWidget(host(app));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Term 2'));
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.delete);
      expect(app.node(term2.id), isNull);
      await quiesce(tester);
    });

    testWidgets('the snackbar Undo button puts it straight back', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await tester.pumpWidget(host(app));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Term 2'));
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.delete);
      expect(app.node(term2.id), isNull);
      expect(find.text('Deleted section “Term 2”'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(app.node(term2.id), isNotNull,
          reason: 'one click, no trip to the recycle bin');
      await quiesce(tester);
    });

    testWidgets('Ctrl+Z restores it too, which is the key people reach for',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // "ctrl + z did not undo it and the whole section at the moment appears
      // to be gone." Undo was page-scoped — it snapshots the open page's
      // blocks — so the one action that takes a whole section away was the
      // one action outside it.
      await tester.pumpWidget(host(app));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Term 2'));
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.delete);
      expect(app.node(term2.id), isNull);

      app.undo();
      await tester.pumpAndSettle();
      expect(app.node(term2.id), isNotNull);

      // And redo takes it away again, so the pair stays symmetric — then
      // undo AGAIN, because deleting switches page and switching page used to
      // clear the very step redo had just pushed.
      app.redo();
      await tester.pumpAndSettle();
      expect(app.node(term2.id), isNull);

      app.undo();
      await tester.pumpAndSettle();
      expect(app.node(term2.id), isNotNull,
          reason: 'undo/redo has to survive being used more than once');
      await quiesce(tester);
    });

    testWidgets('deleting a page keeps you in the section, one page up',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // Reported: "if it is the last one in a section ... rather than keeping
      // me within the section and just bumping me up one, it instead bumps me
      // out of the section group entirely". It was landing on the first page
      // of the whole notebook, which is only the right answer by accident.
      final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
      final other = app.nodes.firstWhere(
          (n) => n.kind == NodeKind.section && n.id != section.id);
      // A second section EARLIER in the tree, so "the first page in the
      // notebook" and "a page in my section" are different answers.
      final stray = app.importNode(
          app.notebookId!,
          TreeNode(
              kind: NodeKind.page,
              parentId: other.id,
              title: 'Somewhere else',
              position: 'a0'));
      app.reloadNodes();

      await app.addPage(sectionId: section.id);
      await app.addPage(sectionId: section.id);
      app.reloadNodes();
      final pages = app.pagesOf(section.id);
      expect(pages.length, greaterThanOrEqualTo(3), reason: 'precondition');
      final last = pages.last;
      final above = pages[pages.length - 2];
      await app.selectPage(last.id);

      await app.deleteNode(last.id);
      expect(app.pageId, above.id,
          reason: 'the page above, in the same section');
      expect(app.sectionOf(app.pageId), section.id);
      expect(app.pageId, isNot(stray.id),
          reason: 'and specifically not the first page in the notebook');
      await quiesce(tester);
    });

    testWidgets('deleting the TOP page of a section moves down, not away',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
      await app.addPage(sectionId: section.id);
      app.reloadNodes();
      final pages = app.pagesOf(section.id);
      expect(pages.length, greaterThanOrEqualTo(2), reason: 'precondition');
      final first = pages.first;
      final next = pages[1];
      await app.selectPage(first.id);

      await app.deleteNode(first.id);
      expect(app.pageId, next.id);
      expect(app.sectionOf(app.pageId), section.id);
      await quiesce(tester);
    });

    testWidgets('deleting a page you are NOT on leaves you where you are',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
      await app.addPage(sectionId: section.id);
      app.reloadNodes();
      final pages = app.pagesOf(section.id);
      await app.selectPage(pages.first.id);

      await app.deleteNode(pages.last.id);
      expect(app.pageId, pages.first.id,
          reason: 'nothing about the open page changed');
      await quiesce(tester);
    });

    testWidgets('a deleted section brings its pages back with it',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await tester.pumpWidget(host(app));
      await tester.pumpAndSettle();
      final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
      final pages = app.nodes
          .where((n) => n.parentId == section.id)
          .map((n) => n.id)
          .toList();
      expect(pages, isNotEmpty, reason: 'precondition');

      await app.deleteNode(section.id);
      await tester.pumpAndSettle();
      expect(pages.every((p) => app.node(p) == null), isTrue);

      app.undo();
      await tester.pumpAndSettle();
      expect(app.node(section.id), isNotNull);
      expect(pages.every((p) => app.node(p) != null), isTrue,
          reason: 'a section without its pages is not a restore');
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
