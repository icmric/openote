// A page window cannot be a way round a passcode.
//
// v1.0.2 bug 33, found while closing the same door for AI helpers. A window
// draws its source live, and nothing asked about the passcode: drag a locked
// page from the navigator onto another page and its contents were there; pick
// it in Insert ▸ Page window and the area picker drew it.
//
// The owner's rule: *"it requires a passcode to be able to view it before we
// insert/select a portion of the page to show, then require it again every
// time the page is opened to unlock the view."*
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/canvas/portal_view.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/state/page_protection.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/app_shell.dart';
import 'package:openote/ui/insert_portal_dialog.dart';
import 'package:openote/ui/sidebar.dart';

import 'support/sqlite.dart';

const _secret = 'the thing worth locking';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;
  late String diaryId, hostId, otherId;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// The whole shell, on "Open one", with "Diary" locked beside it.
  Future<void> shell(WidgetTester tester,
      {List<Block> Function()? hostBlocks}) async {
    AppState.syncLogEnabled = false;
    await tester.runAsync(() async {
      tmp = Directory.systemTemp.createTempSync('onote_portal_lock_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('P');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
      await app.addPage(sectionId: section.id);
      app.renameNode(app.pageId!, 'Diary');
      diaryId = app.pageId!;
      await app.addPage(sectionId: section.id);
      app.renameNode(app.pageId!, 'Kinematics');
      otherId = app.pageId!;
      await app.addPage(sectionId: section.id);
      app.renameNode(app.pageId!, 'Open one');
      hostId = app.pageId!;
      app.importPage(nb.id, diaryId,
          [Block(type: BlockType.text, x: 60, y: 140, w: 300, content: {'text': _secret})],
          PageProps());
      app.importPage(nb.id, otherId,
          [Block(type: BlockType.text, x: 60, y: 140, w: 300, content: {'text': 'velocity'})],
          PageProps());
      if (hostBlocks != null) {
        app.importPage(nb.id, hostId, hostBlocks(), PageProps());
      }
      app.reloadNodes();
      app.reloadProtection();
      app.protectNode(diaryId, '2468', UnlockPolicy.session);
      await app.selectPage(hostId);
    });
    app.markOnboardingSeen();
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() {
      AppState.syncLogEnabled = true;
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      theme: onoteTheme(Brightness.light),
      home: AppShell(app: app),
    ));
    await tester.pump(const Duration(milliseconds: 900));
    await settle(tester);
  }

  Future<void> dragOntoCanvas(WidgetTester tester, String label) async {
    final row =
        find.descendant(of: find.byType(Sidebar), matching: find.text(label));
    expect(row, findsOneWidget, reason: label);
    final canvas = tester.getRect(find.byType(PageCanvas));
    final g = await tester.startGesture(tester.getCenter(row));
    await g.moveBy(const Offset(20, 10));
    await tester.pump();
    await g.moveTo(canvas.center);
    await tester.pump();
    await g.moveBy(const Offset(1, 0));
    await tester.pump();
    await g.up();
    await settle(tester);
  }

  Finder inPrompt(Finder f) =>
      find.descendant(of: find.byType(AlertDialog), matching: f);

  Future<void> answer(WidgetTester tester, String passcode) async {
    await tester.enterText(inPrompt(find.byType(TextField)), passcode);
    await tester.tap(inPrompt(find.text('Unlock')));
    await settle(tester);
  }

  Finder secretInAWindow() =>
      find.descendant(of: find.byType(PortalContent), matching: find.textContaining(_secret));

  Block window(String onto) => Block(
      type: BlockType.embed,
      x: 80,
      y: 140,
      w: 380,
      content: PortalRef.contentFor(onto));

  group('making a window onto a locked page', () {
    testWidgets('a drag asks for the passcode first, and Cancel makes nothing',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await shell(tester);

      await dragOntoCanvas(tester, 'Diary');
      expect(inPrompt(find.textContaining('is locked')), findsOneWidget,
          reason: 'asked before anything is made');
      await tester.tap(inPrompt(find.text('Cancel')));
      await settle(tester);
      expect(app.blocks, isEmpty, reason: 'cancelled: no window');

      await dragOntoCanvas(tester, 'Diary');
      await answer(tester, 'wrong');
      expect(inPrompt(find.text('That is not the passcode.')), findsOneWidget);
      await answer(tester, '2468');
      expect(app.blocks.single.type, BlockType.embed);
      expect(secretInAWindow(), findsOneWidget,
          reason: 'given the passcode, the new window shows the page');
      expect(app.isLocked(diaryId), isTrue,
          reason: 'and the page itself stays locked in the navigator');
      app.cancelPendingSave();
    });

    testWidgets('NEGATIVE CONTROL: a page without one is not asked about',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await shell(tester);
      await dragOntoCanvas(tester, 'Kinematics');
      expect(find.byType(AlertDialog), findsNothing);
      expect(app.blocks.single.type, BlockType.embed);
      app.cancelPendingSave();
    });

    testWidgets('Insert ▸ Page window asks before it draws the page to pick from',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await shell(tester);
      unawaited(showInsertPortalDialog(
          tester.element(find.byType(PageCanvas)), app, const Offset(80, 140)));
      await settle(tester);
      final row = find.descendant(
          of: find.byType(Dialog), matching: find.text('Diary'));
      expect(
          find.descendant(
              of: find.ancestor(of: row, matching: find.byType(ListTile)),
              matching: find.byIcon(Icons.lock_outline)),
          findsOneWidget,
          reason: 'the list says which pages have a passcode');

      await tester.tap(row);
      await settle(tester);
      await tester.tap(inPrompt(find.text('Cancel')));
      await settle(tester);
      expect(secretInAWindow(), findsNothing,
          reason: 'cancelled: the page is not drawn to pick from');

      await tester.tap(row);
      await settle(tester);
      await answer(tester, '2468');
      expect(secretInAWindow(), findsOneWidget,
          reason: 'given the passcode, the area picker draws it');
      app.cancelPendingSave();
    });
  });

  group('a window onto a locked page', () {
    testWidgets('shows a lock, not the page, until the passcode is given',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await shell(tester, hostBlocks: () => [window(diaryId)]);
      expect(find.text('This page has a passcode.'), findsOneWidget);
      expect(find.textContaining(_secret), findsNothing);
      expect(find.text('Diary'), findsWidgets,
          reason: 'its title stays on the badge, as the navigator shows it');

      await tester.tap(find.widgetWithText(OutlinedButton, 'Unlock'));
      await settle(tester);
      await answer(tester, '2468');
      expect(secretInAWindow(), findsOneWidget);
      app.cancelPendingSave();
    });

    testWidgets('and asks again on the next visit to its page', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await shell(tester, hostBlocks: () => [window(diaryId)]);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Unlock'));
      await settle(tester);
      await answer(tester, '2468');
      expect(secretInAWindow(), findsOneWidget, reason: 'precondition');

      await tester.runAsync(() => app.selectPage(otherId));
      await settle(tester);
      await tester.runAsync(() => app.selectPage(hostId));
      await settle(tester);
      expect(find.text('This page has a passcode.'), findsOneWidget,
          reason: '"require it again every time the page is opened"');
      expect(find.textContaining(_secret), findsNothing);
      app.cancelPendingSave();
    });

    testWidgets('even when the page is unlocked in the navigator',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // Two doors: unlocking the page to read it does not open the windows
      // onto it elsewhere, and opening a window does not unlock the page.
      await shell(tester, hostBlocks: () => [window(diaryId)]);
      expect(app.unlockNode(diaryId, '2468'), isTrue);
      await settle(tester);
      expect(find.text('This page has a passcode.'), findsOneWidget);
      app.cancelPendingSave();
    });

    testWidgets('a window inside a window stays shut', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // Kinematics holds a window onto Diary; the open page holds a window
      // onto Kinematics. There is no unlocking from inside something
      // read-only, so the inner one is a lock and a title.
      await shell(tester, hostBlocks: () => [window(otherId)]);
      await tester.runAsync(() async {
        app.importPage(
            app.notebookId!,
            otherId,
            [
              Block(type: BlockType.text, x: 60, y: 140, w: 300, content: {'text': 'velocity'}),
              Block(
                  type: BlockType.embed,
                  x: 60,
                  y: 220,
                  w: 300,
                  content: PortalRef.contentFor(diaryId)),
            ],
            PageProps());
        await app.selectPage(otherId);
        await app.selectPage(hostId);
      });
      await settle(tester);
      expect(find.textContaining('velocity'), findsWidgets,
          reason: 'NEGATIVE CONTROL: the outer window shows its page');
      expect(find.textContaining(_secret), findsNothing);
      expect(
          find.descendant(
              of: find.byType(PortalContent),
              matching: find.byIcon(Icons.lock_outline)),
          findsOneWidget);
      app.cancelPendingSave();
    });
  });

  group('the rule itself', () {
    testWidgets('a window onto its own page shows, and Lock now shuts the rest',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await shell(tester);
      expect(app.windowShows(hostId), isTrue,
          reason: 'nothing there you cannot already see beside it');
      expect(app.windowShows(diaryId), isFalse);
      expect(app.unlockWindowsOnto(diaryId, 'nope'), isFalse);
      expect(app.windowShows(diaryId), isFalse, reason: 'wrong changes nothing');
      expect(app.unlockWindowsOnto(diaryId, '2468'), isTrue);
      expect(app.windowShows(diaryId), isTrue);
      app.lockAll();
      expect(app.windowShows(diaryId), isFalse, reason: 'Lock now means now');
      app.cancelPendingSave();
    });

    testWidgets('a window onto a page in the recycle bin shows nothing of it',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // Out of the tree, a deleted page cannot say which section it was in,
      // so where any passcode exists the window does not guess.
      await shell(tester, hostBlocks: () => [window(otherId)]);
      await tester.runAsync(() async {
        await app.deleteNode(otherId);
        await app.selectPage(hostId);
      });
      await settle(tester);
      expect(find.text('The page this window pointed at was deleted.'),
          findsOneWidget);
      expect(find.textContaining('velocity'), findsNothing);
      app.cancelPendingSave();
    });
  });
}
