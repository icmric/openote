// The Sync dialog on a phone: the cloud is a folder in Google Drive, reached
// through Android's folder picker, so that is what it offers, in one tap. The
// computer's folder chooser, git and extra copies, which a phone cannot use, are
// not shown.
//
// The native half (`MainActivity.kt`) is replaced by a handler that serves a
// folder on disk by document id, so the real `SafFolder` wrapper, the real
// publish and the real card are all in the loop.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/device_class.dart' show debugTouchPlatform;
import 'package:openote/ui/sync_dialog.dart';

import 'support/dir_folder.dart';
import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  const saf = MethodChannel('org.openote/saf');

  Future<AppState> newApp(WidgetTester tester) async {
    late AppState app;
    late Repository repo;
    final tmp = Directory.systemTemp.createTempSync('onote_drivecard_');
    addTearDown(() {
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await tester.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Progress');
      app = AppState(repo)
        ..spellCheckEnabled = false
        ..notebookId = nb.id;
      app.reloadNodes();
      await app.selectPage(
          app.nodes.where((n) => n.kind == NodeKind.page).first.id);
    });
    return app;
  }

  /// Android's folder picker, and the folder it hands out, served from [drive].
  void fakeAndroid(Directory drive, {bool failMakingFolders = false}) {
    final folder = DirFolder(drive, allowWrites: true);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(saf, (call) async {
      final a = call.arguments as Map<Object?, Object?>? ?? const {};
      switch (call.method) {
        case 'pickTree':
          return 'content://tree/drive';
        case 'list':
          return [
            for (final e in await folder.list(doc: a['doc'] as String?))
              {
                'id': e.id,
                'name': e.name,
                'dir': e.dir,
                'size': e.size,
                'modified': e.modified,
              }
          ];
        case 'read':
          return folder.read(a['doc'] as String);
        case 'write':
          return folder.write(
              parent: a['parent'] as String?,
              name: a['name'] as String,
              bytes: a['bytes'] as Uint8List);
        case 'mkdir':
          if (failMakingFolders) {
            throw PlatformException(code: 'denied', message: 'no access');
          }
          return folder.makeDir(
              parent: a['parent'] as String?, name: a['name'] as String);
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(saf, null));
  }

  Future<void> openDialog(WidgetTester tester, AppState app,
      {Size size = const Size(390, 844)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSyncDialog(context, app),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
  }

  Future<void> waitFor(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 200 && f.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump();
    }
  }

  testWidgets('a phone offers one thing: keep this notebook in Google Drive, and '
      'one tap does it', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    debugTouchPlatform = true;
    addTearDown(() => debugTouchPlatform = null);
    final app = await newApp(tester);
    final drive = Directory.systemTemp.createTempSync('onote_drive_');
    addTearDown(() {
      try {
        drive.deleteSync(recursive: true);
      } catch (_) {}
    });
    fakeAndroid(drive);
    await openDialog(tester, app);

    expect(find.text('Keep this notebook in Google Drive'), findsOneWidget);
    expect(find.text('Choose a Drive folder'), findsOneWidget);
    for (final gone in [
      'Choose a folder…',
      'Sync with git',
      'Extra copies',
      'No cloud folders detected.',
    ]) {
      expect(find.textContaining(gone), findsNothing,
          reason: '"$gone" is for a computer and is not shown here');
    }
    expect(tester.takeException(), isNull, reason: 'it fits a phone');

    await tester.tap(find.text('Choose a Drive folder'));
    await tester.pump();
    await waitFor(tester, find.text('In Google Drive'));

    expect(find.text('In Google Drive'), findsOneWidget);
    expect(find.text('Progress.onotebook'), findsOneWidget,
        reason: 'it says where the notebook went');
    expect(find.text('Check Drive now'), findsOneWidget);
    expect(find.text('Choose a Drive folder'), findsNothing,
        reason: 'done is done: the offer is gone');
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'nothing is still turning');
    final made = Directory(p.join(drive.path, 'Progress.onotebook'));
    expect(File(p.join(made.path, 'manifest.json')).existsSync(), isTrue);
    expect(Directory(p.join(made.path, 'ops')).existsSync(), isTrue);
    expect(tester.takeException(), isNull);

    // The half-minute look at Drive and the settings write are timers in a fake
    // clock: let them go before the test ends.
    app.cancelPendingSave();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a folder that cannot be used says so in words, and the offer is '
      'still there to try again', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    debugTouchPlatform = true;
    addTearDown(() => debugTouchPlatform = null);
    final app = await newApp(tester);
    final drive = Directory.systemTemp.createTempSync('onote_drive_');
    addTearDown(() {
      try {
        drive.deleteSync(recursive: true);
      } catch (_) {}
    });
    fakeAndroid(drive, failMakingFolders: true);
    await openDialog(tester, app);

    await tester.tap(find.text('Choose a Drive folder'));
    await tester.pump();
    await waitFor(tester, find.textContaining('Could not put the notebook'));

    expect(find.textContaining('Could not put the notebook'), findsOneWidget);
    expect(find.text('Choose a Drive folder'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'the spinner does not outlive the work');
    expect(app.isFolderNotebook(app.notebookId!), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a computer the dialog is as it was: the folder chooser, no Drive '
      'card', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(tester);
    await openDialog(tester, app, size: const Size(1280, 800));
    expect(find.text('Keep this notebook in Google Drive'), findsNothing);
    expect(find.text('Choose a folder…'), findsOneWidget);
  });
}
