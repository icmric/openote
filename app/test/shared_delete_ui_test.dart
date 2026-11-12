// Deleting a notebook that lives in a shared folder, as a person meets it.
//
// Reported: "deleting one in a drive just removes it from the machine rather
// than deleting it" — true, and nothing said so; and for the device that owned
// the notebook the same click quietly took it out of the Drive. Now the first
// question names both choices, "Remove from this computer" is the default, and
// "Delete everywhere" asks a second time before anything leaves the folder.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/notebook_manager.dart';

import 'support/app.dart';
import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory root;
  late Directory drive;
  late Repository repo;
  late AppState app;
  late String sharedId;

  Future<void> build(WidgetTester tester) async {
    root = Directory.systemTemp.createTempSync('onote_shared_delete_');
    drive = Directory(p.join(root.path, 'FakeDrive'))..createSync();
    addTearDown(() {
      repo.dispose();
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });
    await tester.runAsync(() async {
      repo = await Repository.openAt(
          Directory(p.join(root.path, 'ws'))..createSync());
      await repo.createNotebook('Spare');
      final nb = await repo.createNotebook('Shared');
      sharedId = nb.id;
      app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      await app.selectPage(
          app.nodes.where((n) => n.kind == NodeKind.page).first.id);
      await app.moveNotebookToFolder(nb.id, drive.path);
      // The spare is the one that stays open, so the shared one may go.
      app.notebookId = repo.notebooks.firstWhere((n) => n.title == 'Spare').id;
    });
  }

  Future<void> openManager(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testApp(Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showNotebookManager(context, app),
          child: const Text('open'),
        ),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 450));
  }

  /// Let real file work finish, then redraw. Waits for [done] (up to three
  /// seconds of real time) instead of guessing how long a disk takes.
  ///
  /// It pumps as it waits: the button's handler runs in the test's fake-async
  /// zone, so its continuations only move when a frame is pumped; a plain
  /// real-time wait would sit on a half-finished delete.
  Future<void> work(WidgetTester tester, [bool Function()? done]) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 50));
      if (i >= 1 && (done == null || done())) break;
    }
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
  }

  /// Everything in the folder, by relative path. Compared as "nothing that was
  /// there has gone": a background sync may legitimately ADD a file while the
  /// dialog is open, and counting files blamed the dialog for that.
  Set<String> filesInDrive() => {
        for (final f in drive.listSync(recursive: true))
          p.relative(f.path, from: drive.path)
      };

  testWidgets('a shared notebook is asked about in two choices, not one',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await build(tester);
    await openManager(tester);

    // The Shared notebook is the second row.
    await tester.tap(find.byTooltip('Move to recycle bin').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('shared folder'), findsOneWidget,
        reason: 'it says where the notebook lives');
    expect(find.text('Remove from this computer'), findsOneWidget);
    expect(find.text('Delete everywhere…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the default only removes it from this computer', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await build(tester);
    final before = filesInDrive();
    expect(before, isNotEmpty);
    await openManager(tester);

    await tester.tap(find.byTooltip('Move to recycle bin').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from this computer'));
    await work(tester, () => repo.trashedNotebooks.isNotEmpty);

    expect(repo.notebooks.map((n) => n.title), ['Spare']);
    expect(repo.trashedNotebooks.map((n) => n.id), [sharedId],
        reason: 'still in the recycle bin, so it can come back');
    expect(filesInDrive().containsAll(before), isTrue,
        reason: 'the folder is untouched');
  });

  testWidgets('"Delete everywhere" asks again, and Cancel keeps everything',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await build(tester);
    final before = filesInDrive();
    await openManager(tester);

    await tester.tap(find.byTooltip('Move to recycle bin').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete everywhere…'));
    await tester.pumpAndSettle();

    expect(find.text('Delete “Shared” everywhere?'), findsOneWidget);
    expect(find.textContaining("can't be undone"), findsOneWidget);
    final dialog = find.byType(AlertDialog).last;
    await tester.tap(find.descendant(of: dialog, matching: find.text('Cancel')));
    await work(tester);

    expect(repo.notebooks.map((n) => n.title), contains('Shared'));
    expect(filesInDrive().containsAll(before), isTrue,
        reason: 'nothing left the folder');
  });

  testWidgets('confirming "Delete everywhere" empties the folder',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await build(tester);
    await openManager(tester);

    await tester.tap(find.byTooltip('Move to recycle bin').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete everywhere…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete everywhere'));
    await work(tester,
        () => repo.trashedNotebooks.isEmpty && repo.notebooks.length == 1);

    expect(repo.notebooks.map((n) => n.title), ['Spare']);
    expect(repo.trashedNotebooks, isEmpty, reason: 'not left in the bin');
    expect(drive.listSync(), isEmpty);
  });
}
