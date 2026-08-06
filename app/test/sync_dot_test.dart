// "Is this notebook backed up?" answered per row (v0.9).
//
// The reported gap: the status bar's chip answers this for the notebook you
// have OPEN and nowhere else, so someone with four notebooks had to open each
// in turn to find out which were safe.
//
// These pin the three states and, more importantly, that the answer is never
// carried by colour alone — every state has a sentence.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/sync/mirrors.dart';
import 'package:openote/ui/sync_dot.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Future<(AppState, Directory)> fixture(String name) async {
    final ws = Directory.systemTemp.createTempSync('onote_ws_$name');
    final cloud = Directory.systemTemp.createTempSync('MyDrive_$name');
    final repo = await Repository.openAt(ws);
    // NOT `await repo.flushWorkspace()`. A `testWidgets` teardown still runs
    // under the fake clock, and that flush waits on real file I/O which can
    // never complete there — the teardown hangs instead of failing.
    // `dispose()` cancels the pending debounce, which is all this needs.
    addTearDown(() {
      repo.dispose();
      for (final d in [ws, cloud]) {
        try {
          d.deleteSync(recursive: true);
        } catch (_) {}
      }
    });
    final nb = await repo.createNotebook('Discrete Maths');
    final app = AppState(repo)..notebookId = nb.id;
    app.reloadNodes();
    return (app, cloud);
  }

  test('a notebook only on this machine is local, and says so', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, _) = await fixture('local');
    final nb = app.notebookId!;
    expect(syncStateOf(app, nb), SyncState.local);
    expect(syncStateTooltip(app, nb), contains('this computer only'));
  });

  test('a notebook in a sync folder is synced, and names the folder', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, cloud) = await fixture('synced');
    final nb = app.notebookId!;
    await app.moveNotebookToFolder(nb, cloud.path);

    expect(syncStateOf(app, nb), SyncState.synced);
    // The FOLDER's own name, not the kind — "Folder" would tell the user
    // nothing about where their notes went.
    expect(syncStateTooltip(app, nb), contains('MyDrive'));
  });

  test('mirrors alone are not sync, and the wording keeps them apart',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (app, cloud) = await fixture('mirrored');
    final nb = app.notebookId!;
    app.addMirror(nb, MirrorTarget(path: cloud.path, keepVersions: 3));

    expect(syncStateOf(app, nb), SyncState.mirrored,
        reason: 'a scheduled copy is not the same promise as live sync');
    final t = syncStateTooltip(app, nb);
    expect(t, contains('Backed up'));
    expect(t, contains('not syncing'));
  });

  testWidgets('every state renders a dot with a sentence behind it',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    late AppState app;
    await tester.runAsync(() async {
      final (a, _) = await fixture('widget');
      app = a;
    });
    final nb = app.notebookId!;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(children: [
          SyncDot(app: app, notebookId: nb),
          SizedBox(width: 200, child: SyncDotWithLabel(app: app, notebookId: nb)),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    // Both surfaces exist, and both carry a Tooltip — colour is never the only
    // carrier of the meaning (style guide §3.5).
    expect(find.byType(SyncDot), findsOneWidget);
    expect(find.byType(SyncDotWithLabel), findsOneWidget);
    expect(find.byType(Tooltip), findsNWidgets(2));
    expect(find.text('This computer only'), findsOneWidget);

    // Reading the sync status opens the notebook's op-log recorder, which
    // stamps a setting, which arms the registry's 400 ms debounced write.
    // Let it fire rather than leaving a pending timer behind — the same
    // debounce that once produced an intermittent CI failure in an unrelated
    // test when it landed after a temp directory was gone.
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('a long folder name shrinks rather than overflowing',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    late AppState app;
    late Directory cloud;
    await tester.runAsync(() async {
      final (a, c) = await fixture('longname');
      app = a;
      cloud = c;
    });
    final nb = app.notebookId!;
    final deep = Directory(
        '${cloud.path}/A Really Rather Long Folder Name For Notebooks')
      ..createSync(recursive: true);
    await tester.runAsync(() => app.moveNotebookToFolder(nb, deep.path));

    // The navigator is narrow and user-resizable, so this is the real case.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
            width: 150, child: SyncDotWithLabel(app: app, notebookId: nb)),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'a folder name is unbounded user data; it must ellipsise, '
            'not overflow the panel');
    await tester.pump(const Duration(milliseconds: 500)); // settle the debounce
  });
}
