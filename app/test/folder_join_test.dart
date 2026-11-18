@Timeout(Duration(minutes: 3))
library;

// Opening a notebook that lives in a folder reached by document id (a Drive
// folder through Android's folder picker): the logs come down, the text and the
// outline are there at once, the pictures come on demand and only if their bytes
// are what their names say, and the notebook is viewing-only for now.
//
// The "folder" is a real published notebook (device A, published through a bare
// git repository so that its log directory holds ops, blobs and a manifest) read
// through a fake of the folder API that serves it by document id.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/sync/folder_bridge.dart';
import 'package:openote/sync/git_sync.dart';
import 'package:openote/sync/notebook_scan.dart';

import 'support/dir_folder.dart';
import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  var haveGit = false;
  setUpAll(() async {
    haveSqlite = initSqliteForTests();
    haveGit = await GitSync.gitExecutable() != null;
  });

  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('onote_folder_'));
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  bool skip() => !haveSqlite || !haveGit;

  /// Device A: a notebook with a page, some words and a picture, published (so
  /// its log directory is the shared folder). Returns the folder's directory
  /// and the picture's hash and bytes.
  Future<(Directory, String, Uint8List)> source() async {
    final dirA = Directory('${root.path}/A')..createSync();
    final remote = Directory('${root.path}/remote.git')..createSync();
    final git = (await GitSync.gitExecutable())!;
    await Process.run(git, ['init', '--bare', '--initial-branch=main'],
        workingDirectory: remote.path);
    final repoA = await Repository.openAt(dirA);
    final appA = AppState(repoA)..spellCheckEnabled = false;
    addTearDown(() {
      appA.cancelPendingSave();
      repoA.dispose();
    });
    final nb = await repoA.createNotebook('Honours');
    appA.notebookId = nb.id;
    appA.reloadNodes();
    final pageId = appA.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
    appA.pageId = pageId;
    appA.renameNode(pageId, 'Complexity');
    final bytes =
        Uint8List.fromList(List<int>.generate(96, (i) => (i * 11) % 253));
    final hash = repoA.putBlob(nb.id, bytes, 'image/png');
    appA.blocks = [
      Block(id: 't', type: BlockType.text, x: 0, y: 0, content: {'text': 'big O'}),
      Block(
          id: 'i',
          type: BlockType.image,
          x: 0,
          y: 100,
          content: {'hash': hash, 'mime': 'image/png'}),
    ];
    appA.markDirty();
    await appA.flushSave();
    final logDir = Directory(appA.currentNotebook.logDirPath)..createSync(recursive: true);
    await Process.run(git, ['init', '--initial-branch=main'],
        workingDirectory: logDir.path);
    await appA.setGitEnabled(true, remote: remote.path);
    return (logDir, hash, bytes);
  }

  Future<(Repository, AppState)> phone([String name = 'phone']) async {
    final dir = Directory('${root.path}/$name')..createSync(recursive: true);
    final repo = await Repository.openAt(dir);
    final app = AppState(repo)..spellCheckEnabled = false;
    addTearDown(() {
      app.cancelPendingSave();
      repo.dispose();
    });
    return (repo, app);
  }

  test('the text and outline are there at once; pictures come on demand',
      () async {
    if (skip()) return markTestSkipped('sqlite or git unavailable');
    final (logDir, hash, bytes) = await source();
    final folder = DirFolder(logDir);
    final (repo, app) = await phone();

    final problem =
        await app.joinNotebookFromFolder('tree', folderForTest: folder);
    expect(problem, isNull, reason: 'join failed: $problem');

    expect(repo.notebooks.single.title, 'Honours');
    final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
    expect(page.title, 'Complexity', reason: 'the outline came from the logs');
    final stored = repo.readPage(app.notebookId!, page.id);
    expect(stored.blocks.map((b) => b.content['text']), contains('big O'));

    // No picture was read to open it.
    expect(folder.reads.where((r) => r.startsWith('blobs')), isEmpty,
        reason: 'pictures are not part of opening a notebook');
    final localBlobs = Directory(p.join(repo.notebooks.single.logDir!, 'blobs'));
    expect(localBlobs.existsSync() ? localBlobs.listSync() : const [], isEmpty);

    // Asking for the picture starts the fetch; it lands, and the app is told.
    final before = app.blobRevision;
    expect(app.blob(hash), isNull, reason: 'not here yet');
    for (var i = 0; i < 50 && app.blobRevision == before; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(app.blobRevision, greaterThan(before), reason: 'told it arrived');
    expect(app.blob(hash), bytes, reason: 'and now it is there, whole');
  });

  test('a notebook from a folder is edited on the phone, and shows as synced',
      () async {
    if (skip()) return markTestSkipped('sqlite or git unavailable');
    final (logDir, _, _) = await source();
    final (repo, app) = await phone();
    await app.joinNotebookFromFolder('tree', folderForTest: DirFolder(logDir));
    final id = repo.notebooks.single.id;
    expect(app.isFolderNotebook(id), isTrue);
    expect(app.notebookIsReadOnly(id), isFalse,
        reason: 'changes are kept, and sent');
    expect(app.saveError, isNull);
    final s = app.syncStatus(id);
    expect(s.isSynced, isTrue, reason: 'not "this computer only"');
    expect(s.where, 'Google Drive');
  });

  test('opening the same folder again opens the same notebook, not a second',
      () async {
    if (skip()) return markTestSkipped('sqlite or git unavailable');
    final (logDir, _, _) = await source();
    final (repo, app) = await phone();
    final folder = DirFolder(logDir);
    await app.joinNotebookFromFolder('tree', folderForTest: folder);
    await app.joinNotebookFromFolder('tree', folderForTest: folder);
    expect(repo.notebooks, hasLength(1));
  });

  test('a picture whose bytes are not its name is not kept', () async {
    if (skip()) return markTestSkipped('sqlite or git unavailable');
    final (logDir, hash, _) = await source();
    // Damage the picture in the folder, as a half download or a bad copy would.
    final bare = hash.replaceFirst('sha256:', '');
    final f = [
      for (final e in Directory(p.join(logDir.path, 'blobs')).listSync())
        if (p.basename(e.path).startsWith(bare)) e as File
    ].single;
    f.writeAsBytesSync(Uint8List.fromList(List<int>.filled(96, 7)));

    final (repo, app) = await phone();
    await app.joinNotebookFromFolder('tree', folderForTest: DirFolder(logDir));
    app.blob(hash);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(app.blob(hash), isNull, reason: 'a wrong picture is worse than none');
    final blobs = Directory(p.join(repo.notebooks.single.logDir!, 'blobs'));
    expect(blobs.existsSync() ? blobs.listSync() : const [], isEmpty);
  });

  test('a longer local log is never replaced by a shorter one from the folder',
      () async {
    if (skip()) return markTestSkipped('sqlite or git unavailable');
    final (logDir, _, _) = await source();
    final local = Directory('${root.path}/local')..createSync();
    final bridge = FolderBridge(
        folder: DirFolder(logDir), logDirPath: local.path);
    await bridge.pull();
    final ops = Directory(p.join(local.path, 'ops'))
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.oplog'))
        .toList();
    expect(ops, isNotEmpty);
    // Local gains lines the folder does not have yet.
    ops.first.writeAsStringSync('\nextra line\n', mode: FileMode.append);
    final grown = ops.first.lengthSync();
    final r = await bridge.pull();
    expect(ops.first.lengthSync(), grown, reason: 'not swapped for the shorter');
    expect(r.logs, 0, reason: 'and nothing was downloaded again');
  });

  test('the bridge never writes to the folder', () async {
    if (skip()) return markTestSkipped('sqlite or git unavailable');
    final (logDir, hash, _) = await source();
    final before = logDir
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => '${f.path}:${f.lengthSync()}')
        .toSet();
    final (_, app) = await phone();
    await app.joinNotebookFromFolder('tree', folderForTest: DirFolder(logDir));
    app.blob(hash);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final after = logDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => !f.path.contains('${p.separator}.git${p.separator}'))
        .map((f) => '${f.path}:${f.lengthSync()}')
        .toSet();
    expect(after.containsAll(before.where((e) => !e.contains('.git'))), isTrue,
        reason: 'nothing in the folder changed (DirFolder.write would throw)');
  });

  Map<String, int> snapshot(Directory d) => {
        for (final e in d.listSync(recursive: true).whereType<File>())
          if (!e.path.contains('${p.separator}.git${p.separator}'))
            p.relative(e.path, from: d.path): e.lengthSync()
      };

  test('an edit on the phone is sent: its own log and its new picture, nothing else',
      () async {
    if (skip()) return markTestSkipped('sqlite or git unavailable');
    final (logDir, _, _) = await source();
    final folder = DirFolder(logDir, allowWrites: true);
    final (repo, app) = await phone();
    await app.joinNotebookFromFolder('tree', folderForTest: folder);
    final nb = repo.notebooks.single.id;
    final before = snapshot(logDir);

    // Change a title, and add a picture the folder has never seen.
    final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
    app.renameNode(page.id, 'Edited on the phone');
    final bytes = Uint8List.fromList(List<int>.generate(80, (i) => (i * 7 + 3) % 251));
    final hash = repo.putBlob(nb, bytes, 'image/png');
    app.blocks = [
      ...app.blocks,
      Block(id: 'new', type: BlockType.image, x: 0, y: 300,
          content: {'hash': hash, 'mime': 'image/png'}),
    ];
    app.markDirty();
    await app.flushSave();
    await app.pushFolderNow();

    final after = snapshot(logDir);
    final changed = {
      for (final e in after.entries)
        if (before[e.key] != e.value) e.key
    };
    final own = 'ops/${app.localDeviceId()}.oplog';
    expect(changed.map((c) => c.replaceAll('\\', '/')).toSet(),
        {own, 'blobs/${hash.replaceFirst('sha256:', '')}.blob'},
        reason: 'only this phone\'s log and the new picture are new in the folder; '
            'nothing else was touched');
    // Nothing that was there before was changed or removed.
    for (final e in before.entries) {
      expect(after[e.key], e.value, reason: '${e.key} must be as it was');
    }

    // Asking again with nothing new sends nothing.
    folder.writes.clear();
    await app.pushFolderNow();
    expect(folder.writes, isEmpty);
  });

  test('another device sees the phone\'s edit, and a block type it does not know '
      'on that page comes through untouched', () async {
    if (skip()) return markTestSkipped('sqlite or git unavailable');
    final (logDir, _, _) = await source();
    final folder = DirFolder(logDir, allowWrites: true);
    final (repo, app) = await phone('phone1');
    await app.joinNotebookFromFolder('tree', folderForTest: folder);

    // A block from a later release sits on the page, as it would from a newer
    // desktop. The phone edits ANOTHER block on the same page and sends.
    final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
    final mystery = Block.fromJson({
      'id': 'mystery',
      'type': 'hologram',
      'x': 10.0,
      'y': 500.0,
      'content': {'depth': 3},
      'futureField': 'keep me',
    });
    app.blocks = [...app.blocks, mystery];
    app.markDirty();
    await app.flushSave();
    app.renameNode(page.id, 'Edited on the phone');
    app.blocks = [
      for (final b in app.blocks)
        if (b.id == 't')
          Block(id: 't', type: BlockType.text, x: 0, y: 0,
              content: {'text': 'big O, edited'})
        else
          b
    ];
    app.markDirty();
    await app.flushSave();
    await app.pushFolderNow();

    // A second device opens the same folder.
    final (repo2, app2) = await phone('phone2');
    final problem =
        await app2.joinNotebookFromFolder('tree', folderForTest: DirFolder(logDir));
    expect(problem, isNull, reason: '$problem');
    final page2 = app2.nodes.firstWhere((n) => n.kind == NodeKind.page);
    expect(page2.title, 'Edited on the phone');
    final blocks = repo2.readPage(app2.notebookId!, page2.id).blocks;
    expect(blocks.firstWhere((b) => b.id == 't').content['text'], 'big O, edited');
    final m = blocks.firstWhere((b) => b.id == 'mystery');
    expect(m.rawType, 'hologram', reason: 'the unknown type is kept by name');
    expect(m.unknownFields['futureField'], 'keep me');
    expect(m.content['depth'], 3);
  });

  test('a folder that cannot be reached: the edit is kept, a quiet note is shown, '
      'and it is sent when the folder is back', () async {
    if (skip()) return markTestSkipped('sqlite or git unavailable');
    final (logDir, _, _) = await source();
    final folder = DirFolder(logDir, allowWrites: true);
    final (_, app) = await phone();
    await app.joinNotebookFromFolder('tree', folderForTest: folder);
    final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);

    folder.failWrites = true;
    app.renameNode(page.id, 'Offline edit');
    await app.flushSave();
    await app.pushFolderNow();
    expect(app.saveError?.short, 'Not on Drive yet');
    expect(app.nodes.firstWhere((n) => n.id == page.id).title, 'Offline edit',
        reason: 'the phone kept it');

    folder.failWrites = false;
    await app.pushFolderNow();
    expect(app.saveError, isNull);
    expect(folder.writes.any((w) => w.endsWith('.oplog')), isTrue);
  });

  test('the folder\'s longer copy of this device\'s own log is never replaced',
      () async {
    if (skip()) return markTestSkipped('sqlite or git unavailable');
    final (logDir, _, _) = await source();
    final local = Directory('${root.path}/local')..createSync();
    Directory(p.join(local.path, 'ops')).createSync(recursive: true);
    File(p.join(local.path, 'ops', 'me.oplog')).writeAsStringSync('short\n');
    final theirs = File(p.join(logDir.path, 'ops', 'me.oplog'))
      ..writeAsStringSync('a much longer history than the phone has\n' * 5);
    final bridge = FolderBridge(
        folder: DirFolder(logDir, allowWrites: true),
        logDirPath: local.path,
        ownDevice: 'me');
    await expectLater(bridge.push(), throwsStateError);
    expect(theirs.readAsStringSync(), startsWith('a much longer history'));
  });

  test('only a picture whose bytes are its name is sent', () async {
    if (skip()) return markTestSkipped('sqlite or git unavailable');
    final (logDir, _, _) = await source();
    final local = Directory('${root.path}/local2')..createSync();
    final blobs = Directory(p.join(local.path, 'blobs'))..createSync(recursive: true);
    final fakeHash = 'ab' * 32;
    File(p.join(blobs.path, '$fakeHash.blob'))
        .writeAsBytesSync(Uint8List.fromList([1, 2, 3]));
    final folder = DirFolder(logDir, allowWrites: true);
    final bridge = FolderBridge(
        folder: folder, logDirPath: local.path, ownDevice: 'me');
    final r = await bridge.push();
    expect(r.blobs, 0);
    expect(folder.writes.where((w) => w.contains(fakeHash)), isEmpty);
  });

  test('a notebook folder with no container file beside it opens on a computer, '
      'and is found by looking in the folder above it', () async {
    if (skip()) return markTestSkipped('sqlite or git unavailable');
    final (logDir, _, _) = await source();
    // What a copy of just the logs, pictures and manifest looks like in a Drive
    // folder: a .onotebook directory and NO .onote container beside it.
    final drive = Directory('${root.path}/Drive/Openote test copy')
      ..createSync(recursive: true);
    final copy = Directory(p.join(drive.path, 'Honours (copy).onotebook'))
      ..createSync();
    for (final e in logDir.listSync(recursive: true).whereType<File>()) {
      if (e.path.contains('${p.separator}.git${p.separator}')) continue;
      final dest = File(p.join(copy.path, p.relative(e.path, from: logDir.path)));
      dest.parent.createSync(recursive: true);
      dest.writeAsBytesSync(e.readAsBytesSync());
    }
    expect(File('${copy.path.replaceAll('.onotebook', '')}.onote').existsSync(),
        isFalse,
        reason: 'no container beside it: the case that could not be opened');

    // Found from the Drive folder, two levels down, without choosing it.
    final found = await findNotebooksUnder(p.join(root.path, 'Drive'));
    expect(found.map((n) => n.name), ['Honours (copy)']);

    // And it opens.
    final (repo, app) = await phone('desktop');
    await app.openExistingNotebook(found.single.path);
    expect(repo.notebooks.single.title, 'Honours');
    expect(app.nodes.where((n) => n.kind == NodeKind.page).map((n) => n.title),
        contains('Complexity'));
  });

  test('the whole history is in before the notebook is shown, and marked as such',
      () async {
    if (skip()) return markTestSkipped('sqlite or git unavailable');
    final (logDir, _, _) = await source();
    final (repo, app) = await phone();
    await app.joinNotebookFromFolder('tree', folderForTest: DirFolder(logDir));
    final nb = repo.notebooks.single.id;
    final setting = repo.getSetting('folderSync:$nb') as Map;
    expect(setting['folded'], isTrue,
        reason: 'read in all the way: it may now be edited and sent');
    // The open-time check that follows has nothing left to fold and ends at once.
    for (var i = 0; i < 100 && app.openingNotebook; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(app.openingNotebook, isFalse);
    expect(app.pageLoading, isFalse);
    expect(app.blocks.map((b) => b.content['text']), contains('big O'),
        reason: 'the page shown is the finished one');
  });

  test('a notebook not read in all the way shows no page, and sends nothing',
      () async {
    if (skip()) return markTestSkipped('sqlite or git unavailable');
    final (logDir, _, _) = await source();
    final folder = DirFolder(logDir, allowWrites: true);
    final (repo, app) = await phone();
    await app.joinNotebookFromFolder('tree', folderForTest: folder);
    // Joining opens the notebook, and opening folds in the background and
    // ends by marking it folded: let that finish, or it lands after the line
    // below and undoes it (red on Windows, 17 November).
    await app.settleBackgroundWork();
    final nb = repo.notebooks.single.id;
    final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);

    // As if the app had been closed in the middle of the first read.
    repo.setSetting('folderSync:$nb', {'tree': 'tree', 'notebookId': null});
    app.renameNode(page.id, 'Edited before it was all in');
    await app.flushSave();
    folder.writes.clear();
    await app.pushFolderNow();
    expect(folder.writes, isEmpty, reason: 'nothing is sent from half a notebook');

    // And a page asked for while it is still being read in waits, saying so,
    // instead of opening an old one.
    app.debugSetOpening(true);
    final loading = app.selectPage(page.id);
    // It saves what is open before it moves; wait for it to reach the waiting
    // rather than guess how long that takes on a busy machine.
    for (var i = 0; i < 200 && !app.pageLoading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(app.pageLoading, isTrue);
    expect(app.blocks, isEmpty, reason: 'no old page on screen to repair');
    app.debugSetOpening(false);
    await loading;
    expect(app.pageLoading, isFalse);
    expect(app.blocks, isNotEmpty, reason: 'and then the page is there');
  });

  test('the phone own history comes back when a notebook is opened again, '
      'and a longer local log is never replaced', () async {
    if (skip()) return markTestSkipped('sqlite or git unavailable');
    final (logDir, _, _) = await source();
    File(p.join(logDir.path, 'ops', 'me.oplog'))
        .writeAsStringSync('{"line":1}${'\n'}{"line":2}${'\n'}');
    Directory localDir(String n) =>
        Directory('${root.path}/$n')..createSync();

    // No local copy of its own log: it is brought back.
    final fresh = localDir('fresh');
    final b1 = FolderBridge(
        folder: DirFolder(logDir), logDirPath: fresh.path, ownDevice: 'me');
    await b1.pull(includeOwn: true);
    expect(File(p.join(fresh.path, 'ops', 'me.oplog')).existsSync(), isTrue);

    // While the notebook is open it is not touched.
    final open = localDir('open');
    final b2 = FolderBridge(
        folder: DirFolder(logDir), logDirPath: open.path, ownDevice: 'me');
    await b2.pull();
    expect(File(p.join(open.path, 'ops', 'me.oplog')).existsSync(), isFalse);

    // A longer local log stays, even on the first pull.
    final longer = localDir('longer');
    Directory(p.join(longer.path, 'ops')).createSync(recursive: true);
    final mine = File(p.join(longer.path, 'ops', 'me.oplog'))
      ..writeAsStringSync('{"line":1}${'\n'}{"line":2}${'\n'}{"line":3}${'\n'}');
    final b3 = FolderBridge(
        folder: DirFolder(logDir), logDirPath: longer.path, ownDevice: 'me');
    await b3.pull(includeOwn: true);
    expect(mine.readAsStringSync(), contains('"line":3'));
  });
}
