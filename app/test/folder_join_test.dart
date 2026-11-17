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
import 'package:openote/sync/saf_folder.dart';

import 'support/sqlite.dart';

/// A directory on disk served the way the picker serves a Drive folder: by
/// document id (here, the path relative to the root).
class DirFolder implements FolderApi {
  DirFolder(this.root);
  final Directory root;
  final List<String> reads = [];

  String _abs(String? doc) => doc == null || doc.isEmpty ? root.path : p.join(root.path, doc);

  @override
  Future<List<SafEntry>> list({String? doc}) async {
    final dir = Directory(_abs(doc));
    return [
      for (final e in dir.listSync())
        SafEntry(
          id: p.relative(e.path, from: root.path),
          name: p.basename(e.path),
          dir: e is Directory,
          size: e is File ? e.lengthSync() : -1,
          modified: 0,
        )
    ];
  }

  @override
  Future<Uint8List> read(String doc) async {
    reads.add(doc);
    return File(_abs(doc)).readAsBytesSync();
  }

  @override
  Future<String> write(
          {String? parent, required String name, required Uint8List bytes}) =>
      throw StateError('the bridge must never write to the folder');
}

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

  Future<(Repository, AppState)> phone() async {
    final dir = Directory('${root.path}/phone')..createSync(recursive: true);
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

  test('a notebook read from a folder is viewing-only, and says so', () async {
    if (skip()) return markTestSkipped('sqlite or git unavailable');
    final (logDir, _, _) = await source();
    final (repo, app) = await phone();
    await app.joinNotebookFromFolder('tree', folderForTest: DirFolder(logDir));
    final id = repo.notebooks.single.id;
    expect(app.isFolderNotebook(id), isTrue);
    expect(app.notebookIsReadOnly(id), isTrue);
    expect(app.saveError?.short, 'Viewing only');
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
}
