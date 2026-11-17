@Timeout(Duration(minutes: 3))
library;

// Putting a notebook that lives on the phone into a Drive folder: a folder for
// it is made inside the one that was picked and filled once; nothing already
// there is replaced; another device opens it from there and sees the notebook;
// and what the phone writes afterwards goes up the ordinary way.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/notebook_writer.dart' show sha256Hex;
import 'package:openote/store/repository.dart';
import 'package:openote/sync/folder_publish.dart';

import 'support/dir_folder.dart';
import 'support/sqlite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('onote_publish_'));
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('the folder name', () {
    test('is safe wherever the folder goes', () {
      expect(safeFolderName('Honours'), 'Honours');
      expect(safeFolderName('a/b\\c:d*e?f"g<h>i|j'), 'a b c d e f g h i j');
      expect(safeFolderName('  ..hidden.. '), 'hidden');
      expect(safeFolderName(''), 'Notebook');
      expect(safeFolderName('???'), 'Notebook');
      expect(safeFolderName('CON'), 'CON notebook');
      expect(safeFolderName('x' * 200).length, 80);
    });
  });

  /// A directory laid out like a notebook's own folder on the phone: a log, two
  /// pictures (one whose bytes are not its name), a manifest.
  (Directory, String, Uint8List) localLogDir() {
    final dir = Directory(p.join(root.path, 'local', 'Study.onotebook'))
      ..createSync(recursive: true);
    Directory(p.join(dir.path, 'ops')).createSync();
    File(p.join(dir.path, 'ops', 'dev-a.oplog'))
        .writeAsStringSync('{"op":"one"}\n{"op":"two"}\n');
    Directory(p.join(dir.path, 'blobs')).createSync();
    final bytes = Uint8List.fromList(List<int>.generate(64, (i) => i * 3 % 251));
    final hash = sha256Hex(bytes);
    File(p.join(dir.path, 'blobs', '$hash.blob')).writeAsBytesSync(bytes);
    final fake = 'a' * 64;
    File(p.join(dir.path, 'blobs', '$fake.blob'))
        .writeAsBytesSync(Uint8List.fromList([1, 2, 3]));
    return (dir, hash, bytes);
  }

  Map<String, dynamic> manifestFor(String id, String title) => {
        'format': {'major': 1, 'minor': 0},
        'notebookId': id,
        'title': title,
      };

  Directory picked() => Directory(p.join(root.path, 'drive'))..createSync();

  test('a folder is made and filled: manifest, log, picture, pointer', () async {
    final (local, hash, bytes) = localLogDir();
    final drive = picked();
    final folder = DirFolder(drive, allowWrites: true);

    final stages = <String>[];
    final r = await publishNotebookToFolder(folder,
        logDir: local,
        title: 'Study',
        notebookId: 'nb-1',
        manifest: manifestFor('nb-1', 'Study'),
        onStage: stages.add);

    expect(r.name, 'Study.onotebook');
    expect(r.alreadyThere, isFalse);
    final made = Directory(p.join(drive.path, r.root));
    expect(jsonDecode(File(p.join(made.path, 'manifest.json')).readAsStringSync())['notebookId'],
        'nb-1');
    expect(File(p.join(made.path, 'ops', 'dev-a.oplog')).readAsStringSync(),
        '{"op":"one"}\n{"op":"two"}\n');
    expect(File(p.join(made.path, 'blobs', '$hash.blob')).readAsBytesSync(), bytes);
    expect(File(p.join(made.path, 'blobs', '${'a' * 64}.blob')).existsSync(), isFalse,
        reason: 'a picture whose bytes are not its name is not sent');
    expect(File(p.join(made.path, 'Open this notebook.onotelink')).existsSync(), isTrue);
    expect(stages, contains('Making the notebook folder…'));
  });

  test('a second try finds its own folder and only fills in what is missing',
      () async {
    final (local, hash, _) = localLogDir();
    final drive = picked();
    final folder = DirFolder(drive, allowWrites: true);
    Future<PublishedFolder> go() => publishNotebookToFolder(folder,
        logDir: local,
        title: 'Study',
        notebookId: 'nb-1',
        manifest: manifestFor('nb-1', 'Study'));

    final first = await go();
    // An interrupted try: the picture never arrived.
    File(p.join(drive.path, first.root, 'blobs', '$hash.blob')).deleteSync();
    folder.writes.clear();

    final second = await go();
    expect(second.root, first.root, reason: 'the same folder, not a second copy');
    expect(second.alreadyThere, isTrue);
    expect(folder.writes.map((w) => p.basename(w)), ['$hash.blob'],
        reason: 'only the missing picture was written; the rest was left alone');
    expect(drive.listSync().whereType<Directory>(), hasLength(1));
  });

  test('another notebook with the same name gets its own name; nothing there '
      'is touched', () async {
    final (local, _, _) = localLogDir();
    final drive = picked();
    // Somebody else's folder with the same name.
    final other = Directory(p.join(drive.path, 'Study.onotebook'))..createSync();
    File(p.join(other.path, 'manifest.json'))
        .writeAsStringSync(jsonEncode(manifestFor('someone-else', 'Study')));
    File(p.join(other.path, 'note.txt')).writeAsStringSync('mine');
    final folder = DirFolder(drive, allowWrites: true);

    final r = await publishNotebookToFolder(folder,
        logDir: local,
        title: 'Study',
        notebookId: 'nb-1',
        manifest: manifestFor('nb-1', 'Study'));

    expect(r.name, 'Study (2).onotebook');
    expect(other.listSync().map((e) => p.basename(e.path)).toSet(),
        {'manifest.json', 'note.txt'},
        reason: 'the other folder has exactly what it had');
    expect(File(p.join(other.path, 'note.txt')).readAsStringSync(), 'mine');
  });

  test('a folder that is itself a notebook is refused, and nothing is written',
      () async {
    final (local, _, _) = localLogDir();
    final drive = picked();
    Directory(p.join(drive.path, 'ops')).createSync();
    final folder = DirFolder(drive, allowWrites: true);

    await expectLater(
        publishNotebookToFolder(folder,
            logDir: local,
            title: 'Study',
            notebookId: 'nb-1',
            manifest: manifestFor('nb-1', 'Study')),
        throwsA(isA<PublishProblem>()));
    expect(folder.writes, isEmpty);
    expect(drive.listSync().map((e) => p.basename(e.path)), ['ops']);
  });

  // ── In the app ──────────────────────────────────────────────────────────

  Future<(Repository, AppState, String, String, Uint8List)> phoneNotebook(
      [String name = 'phone']) async {
    final dir = Directory(p.join(root.path, name))..createSync(recursive: true);
    final repo = await Repository.openAt(dir);
    final app = AppState(repo)..spellCheckEnabled = false;
    addTearDown(() {
      app.cancelPendingSave();
      repo.dispose();
    });
    final nb = await repo.createNotebook('Study notes');
    app.notebookId = nb.id;
    app.reloadNodes();
    final pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
    app.pageId = pageId;
    app.renameNode(pageId, 'Week one');
    final bytes = Uint8List.fromList(List<int>.generate(90, (i) => (i * 13) % 251));
    final hash = repo.putBlob(nb.id, bytes, 'image/png');
    app.blocks = [
      Block(id: 't', type: BlockType.text, x: 0, y: 0, content: {'text': 'made on the phone'}),
      Block(
          id: 'i',
          type: BlockType.image,
          x: 0,
          y: 100,
          content: {'hash': hash, 'mime': 'image/png'}),
    ];
    app.markDirty();
    await app.flushSave();
    return (repo, app, nb.id, hash, bytes);
  }

  Future<String?> putIn(AppState app, Directory drive,
          {DirFolder? at, void Function(String)? onProgress}) =>
      app.putNotebookInFolder('tree',
          onProgress: onProgress,
          pickedForTest: at ?? DirFolder(drive, allowWrites: true),
          atRootForTest: (r) =>
              DirFolder(Directory(p.join(drive.path, r)), allowWrites: true));

  test('a notebook made on the phone is put in Drive, and a computer opens it',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, nb, hash, bytes) = await phoneNotebook();
    final drive = picked();
    expect(app.isFolderNotebook(nb), isFalse);

    final problem = await putIn(app, drive);
    expect(problem, isNull, reason: 'put in Drive failed: $problem');

    expect(app.isFolderNotebook(nb), isTrue);
    expect(app.folderName(nb), 'Study notes.onotebook');
    final s = app.syncStatus(nb);
    expect(s.isSynced, isTrue);
    expect(s.where, 'Google Drive');
    expect(app.folderSendFailed(nb), isFalse);
    expect(app.folderCheckedAt(nb), isNotNull);

    // The phone's own notebook is as it was.
    expect(repo.notebooks.single.title, 'Study notes');
    expect(repo.readPage(nb, app.pageId!).blocks.map((b) => b.content['text']),
        contains('made on the phone'));

    // Another device opens that folder, as the computer's Open does.
    final made = Directory(p.join(drive.path, 'Study notes.onotebook'));
    expect(made.existsSync(), isTrue);
    final (repo2, app2) = await _device(root, 'computer');
    final opened = await app2.joinNotebookFromFolder('tree',
        folderForTest: DirFolder(made));
    expect(opened, isNull, reason: 'the other device could not open it: $opened');
    expect(repo2.notebooks.single.title, 'Study notes');
    final page2 = app2.nodes.firstWhere((n) => n.kind == NodeKind.page);
    expect(page2.title, 'Week one');
    expect(repo2.readPage(app2.notebookId!, page2.id).blocks.map((b) => b.content['text']),
        contains('made on the phone'));
    // Pictures come on demand: ask, and it lands, whole.
    final seen = app2.blobRevision;
    expect(app2.blob(hash), isNull, reason: 'not here until asked for');
    for (var i = 0; i < 100 && app2.blobRevision == seen; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(app2.blob(hash), bytes, reason: 'the picture was sent with it');
  });

  test('what the phone writes next goes into that folder, and only its own log '
      'and new pictures', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, nb, _, _) = await phoneNotebook();
    final drive = picked();
    expect(await putIn(app, drive), isNull);
    final made = Directory(p.join(drive.path, 'Study notes.onotebook'));
    Map<String, int> snap() => {
          for (final e in made.listSync(recursive: true).whereType<File>())
            p.relative(e.path, from: made.path): e.lengthSync()
        };
    final before = snap();

    app.renameNode(app.pageId!, 'Week one, edited');
    final bytes = Uint8List.fromList(List<int>.generate(70, (i) => (i * 5 + 1) % 251));
    final hash = repo.putBlob(nb, bytes, 'image/png');
    app.blocks = [
      ...app.blocks,
      Block(id: 'n', type: BlockType.image, x: 0, y: 300,
          content: {'hash': hash, 'mime': 'image/png'}),
    ];
    app.markDirty();
    await app.flushSave();
    await app.pushFolderNow();

    final after = snap();
    final changed = {
      for (final e in after.entries)
        if (before[e.key] != e.value) e.key.replaceAll('\\', '/')
    };
    expect(changed, {
      'ops/${app.localDeviceId()}.oplog',
      'blobs/${hash.replaceFirst('sha256:', '')}.blob',
    });
    expect(File(p.join(made.path, 'manifest.json')).readAsStringSync(),
        contains('"title": "Study notes"'),
        reason: 'the manifest is written once and left alone');
  });

  test('a folder that cannot be reached leaves the notebook as it was; trying '
      'again carries on in the same folder', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (_, app, nb, _, _) = await phoneNotebook();
    final drive = picked();
    final broken = DirFolder(drive, allowWrites: true)..failWrites = true;

    final problem = await putIn(app, drive, at: broken);
    expect(problem, isNotNull);
    expect(problem, isNot(contains('StateError')),
        reason: 'words, not an exception');
    expect(app.isFolderNotebook(nb), isFalse, reason: 'not linked to anything');

    // Half made, as a lost connection leaves it.
    final f = DirFolder(drive, allowWrites: true);
    Directory(p.join(drive.path, 'Study notes.onotebook')).createSync();
    File(p.join(drive.path, 'Study notes.onotebook', 'manifest.json'))
        .writeAsStringSync(jsonEncode({'notebookId': await _manifestIdOf(app, nb)}));

    expect(await putIn(app, drive, at: f), isNull);
    expect(app.isFolderNotebook(nb), isTrue);
    expect(drive.listSync().whereType<Directory>(), hasLength(1),
        reason: 'carried on in the folder that was there');
    expect(
        File(p.join(drive.path, 'Study notes.onotebook', 'ops',
                '${app.localDeviceId()}.oplog'))
            .existsSync(),
        isTrue);
  });

  test('a notebook that is already in Drive is not put there twice', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (_, app, _, _, _) = await phoneNotebook();
    final drive = picked();
    expect(await putIn(app, drive), isNull);
    final again = await putIn(app, drive);
    expect(again, contains('already'));
    expect(drive.listSync().whereType<Directory>(), hasLength(1));
  });

  /// The app started again on the workspace [phoneNotebook] made.
  Future<AppState> relaunch(Repository old, AppState oldApp, String nb) async {
    old.setSetting('lastNotebook', nb);
    await old.flushWorkspace();
    oldApp.cancelPendingSave();
    old.dispose();
    final repo2 = await Repository.openAt(Directory(p.join(root.path, 'phone')));
    final launched = AppState(repo2)..spellCheckEnabled = false;
    addTearDown(() async {
      // The background work a launch starts, finished before the workspace goes.
      await launched.settleBackgroundWork();
      launched.cancelPendingSave();
      repo2.dispose();
    });
    return launched;
  }

  const saf = MethodChannel('org.openote/saf');
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(saf, null));

  test('on launch a Drive notebook is marked as opening while the folder is '
      'looked at, and that clears', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, nb, _, _) = await phoneNotebook();
    expect(await putIn(app, picked()), isNull);
    final launched = await relaunch(repo, app, nb);

    // Drive is slow to answer: the folder is not reached until this opens.
    final gate = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(saf, (call) async {
      await gate.future;
      return <Object?>[];
    });

    await launched.init();
    expect(launched.notebookId, nb);
    expect(launched.openingNotebook, isTrue,
        reason: 'the screens say "opening" while the folder is looked at');
    expect(launched.pageLoading, isFalse,
        reason: 'a notebook already read in all the way shows its page at once');

    gate.complete();
    for (var i = 0; i < 400 && launched.openingNotebook; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(launched.openingNotebook, isFalse, reason: 'and it clears');
  });

  test('on launch a Drive notebook that Drive never answers still stops saying '
      'it is opening', () async {
    // The pull has a time limit, so this is only checked up to the limit's
    // existence: a provider that answers with an error ends the opening too.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, nb, _, _) = await phoneNotebook();
    expect(await putIn(app, picked()), isNull);
    final launched = await relaunch(repo, app, nb);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(saf, (call) async {
      throw PlatformException(code: 'gone', message: 'provider is away');
    });
    await launched.init();
    for (var i = 0; i < 400 && launched.openingNotebook; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(launched.openingNotebook, isFalse);
  });

  test('on launch a notebook that is not in a Drive folder is not marked as '
      'opening', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, nb, _, _) = await phoneNotebook();
    final launched = await relaunch(repo, app, nb);
    await launched.init();
    expect(launched.openingNotebook, isFalse);
  });
}

Future<(Repository, AppState)> _device(Directory root, String name) async {
  final dir = Directory(p.join(root.path, name))..createSync(recursive: true);
  final repo = await Repository.openAt(dir);
  final app = AppState(repo)..spellCheckEnabled = false;
  addTearDown(() {
    app.cancelPendingSave();
    repo.dispose();
  });
  return (repo, app);
}

/// The id the notebook's own manifest gives it, which is what a folder made for
/// it carries.
Future<String> _manifestIdOf(AppState app, String nb) async {
  final m = File(p.join(app.notebookLogDir(nb)!, 'manifest.json'));
  return (jsonDecode(m.readAsStringSync()) as Map)['notebookId'] as String;
}
