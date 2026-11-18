// Finding the notebooks in a folder, on a computer and through Android's picker,
// and opening one whose folder has no container file beside it. See
// `lib/sync/notebook_scan.dart`.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openote/l10n/l10n.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/sync/cloud_folders.dart' show detectCloudFolders;
import 'package:openote/sync/notebook_scan.dart';
import 'package:openote/sync/saf_folder.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/notebook_manager.dart';
import 'package:openote/ui/open_notebook.dart';

import 'support/sqlite.dart';
import 'support/wait.dart';

/// A directory served by document id, read-only (the finder must never write).
class _Dir implements FolderApi {
  _Dir(this.root);
  final Directory root;
  final List<String?> listed = [];

  String _abs(String? doc) => doc == null ? root.path : p.join(root.path, doc);

  @override
  Future<List<SafEntry>> list({String? doc}) async {
    listed.add(doc);
    return [
      for (final e in Directory(_abs(doc)).listSync())
        SafEntry(
            id: p.relative(e.path, from: root.path),
            name: p.basename(e.path),
            dir: e is Directory,
            size: e is File ? e.lengthSync() : -1,
            modified: 0)
    ];
  }

  @override
  Future<Uint8List> read(String doc) => throw StateError('read');
  @override
  Future<String> write(
          {String? parent, required String name, required Uint8List bytes}) =>
      throw StateError('the finder must never write');
  @override
  Future<String> makeDir({String? parent, required String name}) =>
      throw StateError('the finder must never write');
}

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('onote_scan_'));
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  Directory notebook(String rel) =>
      Directory(p.join(root.path, rel, 'ops'))..createSync(recursive: true);

  group('on a computer', () {
    test('the folder itself, when it is a notebook', () async {
      notebook('Honours (copy).onotebook');
      final r = await findNotebooksUnder(p.join(root.path, 'Honours (copy).onotebook'));
      expect(r.map((n) => n.name), ['Honours (copy)']);
    });

    test('notebooks one and two folders down, whatever the nesting', () async {
      notebook('Openote/Maths.onotebook');
      notebook('Uni/Openote/Honours.onotebook');
      Directory(p.join(root.path, 'Photos', '2024')).createSync(recursive: true);
      final r = await findNotebooksUnder(root.path);
      expect(r.map((n) => n.name).toSet(), {'Maths', 'Honours'});
    });

    test('hidden folders and ordinary folders are not notebooks', () async {
      notebook('.trash/Old.onotebook');
      Directory(p.join(root.path, 'Docs', 'ops-not')).createSync(recursive: true);
      expect(await findNotebooksUnder(root.path), isEmpty);
    });

    test('it gives up rather than walk a whole drive', () async {
      // A notebook in every folder, so the answer does not depend on which
      // folders the budget reaches: a directory lists in the filesystem's
      // order, not by name, and that differs from one machine to the next.
      // (This used to hide one notebook in `f29` and expect it missed, which
      // failed on whichever runner happened to list `f29` early.)
      for (var i = 0; i < 30; i++) {
        notebook('f$i/N$i.onotebook');
      }
      final r = await findNotebooksUnder(root.path, budget: 5);
      // Five listings: the root, then four of the thirty folders.
      expect(r, hasLength(4), reason: 'it stopped at the budget');
    });

    test('a folder that is not there is nothing, not an error', () async {
      expect(await findNotebooksUnder(p.join(root.path, 'missing')), isEmpty);
    });
  });

  group('through the phone folder picker', () {
    test('the chosen folder is the notebook itself', () async {
      notebook('.');
      final r = await findNotebooksInFolder(_Dir(root));
      expect(r, hasLength(1));
      expect(r.single.root, isNull, reason: 'no sub-folder to open');
    });

    test('the notebooks inside it, each with its own folder id', () async {
      notebook('Maths.onotebook');
      notebook('Honours.onotebook');
      File(p.join(root.path, 'readme.txt')).writeAsStringSync('hi');
      final r = await findNotebooksInFolder(_Dir(root));
      expect({for (final n in r) n.name: n.root},
          {'Maths': 'Maths.onotebook', 'Honours': 'Honours.onotebook'});
    });

    test('and one folder further down', () async {
      notebook('Openote/Honours.onotebook');
      final r = await findNotebooksInFolder(_Dir(root));
      expect(r.single.name, 'Honours');
    });

    test('it stops after the listing budget', () async {
      for (var i = 0; i < 20; i++) {
        Directory(p.join(root.path, 'f$i')).createSync();
      }
      final folder = _Dir(root);
      await findNotebooksInFolder(folder, budget: 6);
      expect(folder.listed.length, lessThanOrEqualTo(6));
    });
  });

  group('opening on a computer', () {
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());

    testWidgets('Open in the notebook list offers to choose a folder',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      AppState.syncLogEnabled = false;
      late Repository repo;
      late AppState app;
      await t.runAsync(() async {
        repo = await Repository.openAt(root);
        final nb = await repo.createNotebook('Mine');
        app = AppState(repo)
          ..notebookId = nb.id
          ..spellCheckEnabled = false;
        app.reloadNodes();
      });
      addTearDown(() {
        AppState.syncLogEnabled = true;
        app.cancelPendingSave();
        repo.dispose();
      });
      // The test machine's own Drive is none of this test's business.
      cloudFoldersToSearch = () => const [];
      addTearDown(() => cloudFoldersToSearch = detectCloudFolders);
      t.view.physicalSize = const Size(1200, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        localizationsDelegates: kOnoteLocalizations,
        supportedLocales: kOnoteLocales,
        theme: onoteTheme(Brightness.light),
        home: Builder(
            builder: (c) => Scaffold(
                body: TextButton(
                    onPressed: () => showNotebookManager(c, app),
                    child: const Text('go')))),
      ));
      await t.tap(find.text('go'));
      await pumpUntil(
          t, () => find.widgetWithText(TextButton, 'Open').evaluate().isNotEmpty,
          what: 'the notebook list');
      await t.pumpAndSettle();
      // One tap, on a button that is there on every page, not only the first run.
      await t.tap(find.widgetWithText(TextButton, 'Open'));
      await pumpUntil(
          t,
          () => find.text('Open a notebook from a folder').evaluate().isNotEmpty,
          what: 'the open-from-folder dialog');
      await t.pumpAndSettle();
      expect(find.text('Open a notebook from a folder'), findsOneWidget);
      expect(find.text('Choose a folder…'), findsOneWidget);
      app.cancelPendingSave();
    });
  });
}
