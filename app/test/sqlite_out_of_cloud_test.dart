// v0.17 plan, Step 4 — "Get SQLite out of the cloud folder".
//
// ADR-0006 §2 says a WAL SQLite database replicated by a consumer sync client
// "can produce a torn database. This is a live risk today, not a future one."
// It was not a warning, it was a description: the owner's Google Drive was
// replicating an open notebook's container, its `-wal` and its `-shm` —
// 31,954,368 bytes of live database — because `Repository.moveNotebookTo`
// copied the container into the target folder for a notebook this device had
// created. The JOINED branch twelve lines above it already refused to do
// exactly that, with a comment explaining why. Half the fix was present and
// correct; the other half was never wired up.
//
// The sweep below is the plan's own proof obligation: perform every notebook
// operation, then assert that no path SQLite can write exists anywhere under a
// configured sync location. Companion cells live in `cloud_sync_test.dart`
// (the move itself, and the `-wal` fold on the way out of Drive).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/sync/cloud_folders.dart';
import 'package:openote/sync/mirrors.dart';
import 'package:openote/ui/sync_dialog.dart' show findExistingNotebooks;

import 'support/sqlite.dart';

/// Anything SQLite writes: the container and the two sidecars it keeps beside
/// it. Matched as a shape rather than as three literal paths so a rename cannot
/// slip past — and deliberately NOT matching the `.onotebook` DIRECTORY, which
/// is the append-only half and belongs in the folder.
final _sqliteName = RegExp(r'\.onote(-wal|-shm)?$');

List<String> _sqliteUnder(Directory d) => d
    .listSync(recursive: true)
    .whereType<File>()
    .map((f) => p.relative(f.path, from: d.path))
    .where((n) => _sqliteName.hasMatch(n))
    .toList();

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  test('NO SQLITE IN THE SYNC FOLDER, AFTER EVERY OPERATION THERE IS',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final root = Directory.systemTemp.createTempSync('onote_nosqlite_');
    final ws = Directory(p.join(root.path, 'ws'))..createSync();
    final cloud = Directory(p.join(root.path, 'FakeDrive'))..createSync();
    final backups = Directory(p.join(root.path, 'Backups'))..createSync();
    final repo = await Repository.openAt(ws);
    addTearDown(() {
      repo.dispose();
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });

    // create
    final nb = await repo.createNotebook('Everything');
    final app = AppState(repo)..notebookId = nb.id;
    addTearDown(app.dispose);
    app.reloadNodes();

    // save, including a blob, so `blobs/` is populated too
    app.pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
    app.importBlob(nb.id, Uint8List.fromList(List.generate(512, (i) => i & 255)),
        'image/png');
    app.blocks = [
      Block(type: BlockType.text, x: 0, y: 0, content: {'text': 'hello'})
    ];
    app.markDirty();
    await app.flushSave();

    // move-to-folder
    final logDir = await app.moveNotebookToFolder(nb.id, cloud.path);
    expect(p.isWithin(cloud.path, logDir), isTrue);

    // save again, now that it is shared
    app.blocks = [
      Block(type: BlockType.text, x: 0, y: 0, content: {'text': 'hello again'})
    ];
    app.markDirty();
    await app.flushSave();
    await app.awaitBlobBackfill(nb.id);

    // mirror — a plain mirror copies the `.onotebook`, and a mirror of a
    // container would put one in a second replicated place.
    app.addMirror(nb.id, MirrorTarget(path: backups.path, keepVersions: 0));
    await app.awaitMirrorRun(nb.id);

    // join, from a second workspace, exactly as a second machine would
    final ws2 = Directory(p.join(root.path, 'ws2'))..createSync();
    final repo2 = await Repository.openAt(ws2);
    addTearDown(repo2.dispose);
    final app2 = AppState(repo2);
    addTearDown(app2.dispose);
    // The second device finds it by LOOKING — and what is there to find is a
    // directory, because Step 4 left the container behind.
    final found = findExistingNotebooks(searchIn: [
      CloudFolder(name: 'FakeDrive', path: cloud.path, kind: CloudKind.other)
    ]);
    expect(found.map((f) => f.path), [logDir],
        reason: 'a folder holding only logs is still a notebook to join');
    await app2.openExistingNotebook(found.single.path);
    expect(repo2.notebooks, hasLength(1));
    expect(repo2.notebooks.single.logDir, logDir,
        reason: 'the joining device shares the logs and keeps its own cache');
    expect(p.isWithin(ws2.path, repo2.notebooks.single.file), isTrue);
    // And it actually got the notes, not an empty husk.
    expect(repo2.loadNodes(repo2.notebooks.single.id)
        .where((n) => n.kind == NodeKind.page), isNotEmpty);

    // THE ASSERTION OF RECORD, over both replicated locations.
    expect(_sqliteUnder(cloud), isEmpty,
        reason: 'a WAL database in a replicated folder is ADR-0006 §2');
    expect(_sqliteUnder(backups), isEmpty,
        reason: 'a mirror is a second replicated place, with the same rule');
    // MUTATION: put the container copy back into `moveNotebookTo` and the first
    // of these turns red with three entries — the `.onote`, its `-wal` and its
    // `-shm`.

    // …and both devices still have a container, on their own disks.
    expect(_sqliteUnder(ws), isNotEmpty);
    expect(_sqliteUnder(ws2), isNotEmpty);
  });

  test('A LENGTH CHECK IS NOT A COPY CHECK', () {
    // The check `moveNotebookTo` used to do — `lengthSync() != lengthSync()` —
    // and the check it does now, on the one input that separates them: two
    // files of exactly the same length holding different bytes. That is what a
    // copy torn in the middle looks like, and the old check called it perfect
    // and then deleted the original.
    final d = Directory.systemTemp.createTempSync('onote_hashcheck_');
    addTearDown(() {
      try {
        d.deleteSync(recursive: true);
      } catch (_) {}
    });
    final a = File(p.join(d.path, 'a'))
      ..writeAsBytesSync(List.generate(4096, (i) => i & 255));
    final b = File(p.join(d.path, 'b'))
      ..writeAsBytesSync(List.generate(4096, (i) => i & 255)..[2048] = 0xFF);
    final same = File(p.join(d.path, 'c'))
      ..writeAsBytesSync(List.generate(4096, (i) => i & 255));

    expect(a.lengthSync(), b.lengthSync(),
        reason: 'the old check saw two identical numbers here');
    // MUTATION: make `Repository.sameBytes` compare lengths and this fails.
    expect(Repository.sameBytes(a.path, b.path), isFalse);
    // NEGATIVE CONTROL: an intact copy must still pass, or every move breaks.
    expect(Repository.sameBytes(a.path, same.path), isTrue);
  });

  test('A COPY THAT CANNOT BE MADE DELETES NOTHING', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final root = Directory.systemTemp.createTempSync('onote_movefail_');
    final ws = Directory(p.join(root.path, 'ws'))..createSync();
    final drive = Directory(p.join(root.path, 'Drive'))..createSync();
    final repo1 = await Repository.openAt(ws);
    addTearDown(() {
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });
    final made = await repo1.createNotebook('Fragile');
    await repo1.flushWorkspace();
    repo1.dispose();

    // The state a pre-v0.17 build left behind: the container living in the
    // cloud folder, with the registry naming it there.
    final inDrive = p.join(drive.path, 'Fragile.onote');
    File(made.file).renameSync(inDrive);
    final wsFile = File(p.join(ws.path, 'workspace.json'));
    final j = jsonDecode(wsFile.readAsStringSync()) as Map<String, dynamic>;
    ((j['notebooks'] as List).single as Map)['file'] = inDrive;
    wsFile.writeAsStringSync(jsonEncode(j));

    final repo = await Repository.openAt(ws);
    addTearDown(repo.dispose);
    // Length, not bytes: the mover checkpoints the WAL before it copies, and a
    // clean open legitimately bumps SQLite's change counter in the header. What
    // must not happen is the file being shortened, replaced or removed.
    final before = File(inDrive).lengthSync();

    // Occupy the destination with a DIRECTORY, so the copy fails rather than
    // producing a short file. The rule under test is the ORDERING — nothing is
    // removed until a copy has been made and verified — not the particular way
    // the copy failed.
    Directory(p.join(ws.path, 'Fragile.onote')).createSync();
    await expectLater(
        repo.moveContainerOutOfSyncFolder(made.id), throwsA(isA<Object>()));

    expect(File(inDrive).existsSync(), isTrue);
    expect(File(inDrive).lengthSync(), before,
        reason: 'the original was neither shortened nor replaced');
    expect(repo.notebooks.single.file, inDrive,
        reason: 'and the registry still points at it');
    expect(repo.loadNodes(made.id).where((n) => n.kind == NodeKind.page),
        isNotEmpty,
        reason: 'and it is still a notebook that opens');
  });
}
