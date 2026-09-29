// Dragging a page out of the navigator and onto the open one.
//
// The owner: *"If i drag and drop a page from the page list onto the
// currently active page, it should create a page window (and right clicking
// this should provide the option to change this to a page link)"*.
//
// Insert ▸ Page window already made one, through a dialog that asks you to
// find the page in a list — while the page is right there in the navigator,
// and dragging it onto the canvas did nothing at all.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/canvas/portal_view.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/app_shell.dart';
import 'package:openote/ui/sidebar.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;
  late String otherId;

  /// Enough frames for a drop, a menu or a rebuild, and never more.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> shell(WidgetTester tester) async {
    AppState.syncLogEnabled = false;
    await tester.runAsync(() async {
      tmp = Directory.systemTemp.createTempSync('onote_portal_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('P');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
      await app.addPage(sectionId: section.id);
      app.renameNode(app.pageId!, 'Kinematics');
      otherId = app.pageId!;
      await app.addPage(sectionId: section.id);
      app.renameNode(app.pageId!, 'Open one');
      app.reloadNodes();
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
    await tester.pumpAndSettle();
  }

  /// Drag the navigator row for [label] onto the middle of the canvas.
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
    await g.moveBy(const Offset(1, 0)); // a move while over the target
    await tester.pump();
    await g.up();
    // Bounded pumps, not `pumpAndSettle`: once a page window is on the canvas
    // it draws another page's content, and anything in there that is still
    // arriving spins — which `pumpAndSettle` waits for for ever.
    await settle(tester);
  }

  testWidgets('a page dropped on the canvas becomes a window onto it',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(tester);
    expect(app.blocks, isEmpty);

    await dragOntoCanvas(tester, 'Kinematics');

    final made = app.blocks.single;
    expect(made.type, BlockType.embed);
    final ref = PortalRef.parse(made.content);
    expect(ref?.pageId, otherId);
    expect(ref?.wholePage, isTrue,
        reason: 'the whole page — choosing a region of it is what the Insert '
            'dialog is for, and a drag has no way to say');
    app.cancelPendingSave();
  });

  testWidgets('and right-clicking it offers a page link instead',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(tester);
    await dragOntoCanvas(tester, 'Kinematics');
    final window = app.blocks.single;

    await tester.tapAt(tester.getCenter(find.byType(PageCanvas)),
        buttons: kSecondaryButton);
    await settle(tester);

    final entry = find.text('Change to a page link');
    expect(entry, findsOneWidget,
        reason: 'the two are the same intention at different sizes, and '
            'which one you want is often clear only once the window is '
            'taking up a third of the page');
    await tester.tap(entry);
    await settle(tester);

    final now = app.blocks.single;
    expect(now.id, isNot(window.id), reason: 'Block.type is final');
    expect(now.type, BlockType.text);
    expect(now.content['text'], '[Kinematics](onote://page/$otherId)',
        reason: 'the one spelling of a page link the rest of the app already '
            'reads — the live editor draws it as a chip and the exporter '
            'carries it out');
    expect(now.x, window.x, reason: 'and it stays where the window was');
    expect(now.y, window.y);
    app.cancelPendingSave();
  });

  testWidgets('dropping the page you are already on does nothing',
      (tester) async {
    // A window onto the page it is drawn on is a mirror pointed at a mirror.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(tester);
    await dragOntoCanvas(tester, 'Open one');
    expect(app.blocks, isEmpty);
    app.cancelPendingSave();
  });
}
