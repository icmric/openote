// Cloud sync via a synced folder: moving a notebook, and noticing another
// device's changes.
//
// The move is the risky operation — it relocates a user's whole notebook
// across volumes — so it is copy, verify, then delete, and these tests pin
// that a failure at any step leaves the notebook intact somewhere.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/sync/cloud_folders.dart';
import 'package:openote/sync/folder_watch.dart';
import 'package:openote/sync/op.dart';
import 'package:openote/sync/op_log.dart';
import 'package:openote/sync/sync_recorder.dart';
import 'package:openote/ui/sync_dialog.dart' show findExistingNotebooks;

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  group('cloud folder detection', () {
    test('never returns a path that does not exist', () {
      // Detection is by well-known path, so every candidate must be checked
      // before it is offered — a "Use" button on a folder that isn't there is
      // worse than not listing it.
      for (final f in detectCloudFolders()) {
        expect(Directory(f.path).existsSync(), isTrue, reason: f.path);
        expect(f.exists, isTrue);
      }
    });

    test('does not list the same folder twice', () {
      final paths = detectCloudFolders().map((f) => f.path).toList();
      expect(paths.toSet().length, paths.length);
    });

    test('self-hosted options say so; cloud ones carry their caveat', () {
      // The caveats exist because providers evict files by default, which
      // looks exactly like data loss to a user.
      expect(cloudCaveat(CloudKind.googleDrive), contains('offline'));
      expect(cloudCaveat(CloudKind.oneDrive), contains('Always keep'));
      expect(cloudCaveat(CloudKind.syncthing), contains('control'));
      expect(cloudCaveat(CloudKind.other), isNull);
    });
  });

  group('moving a notebook into a synced folder', () {
    // v0.17 Step 4. This test used to be called "moves the container AND its op
    // log" and asserted the container had arrived in the cloud folder. That
    // was the bug: on the owner's real Drive it meant 31,954,368 bytes of live
    // WAL SQLite (`.onote` + `-wal` + `-shm`) being replicated file by file by
    // a client with no per-file ignore — ADR-0006 §2's torn-database hazard,
    // happening rather than threatened.
    test('SQLITE NEVER ENTERS THE SYNCED FOLDER — only the append-only half goes',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final tmp = Directory.systemTemp.createTempSync('onote_move_');
      final repo = await Repository.openAt(tmp);
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final nb = await repo.createNotebook('Moving');
      final app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      app.pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
      app.blocks = [
        Block(type: BlockType.text, x: 0, y: 0, content: {'text': 'before'})
      ];
      app.markDirty();
      await app.flushSave();

      final oldPath = repo.notebooks.firstWhere((n) => n.id == nb.id).file;
      final oldLog = Directory('${p.withoutExtension(oldPath)}.onotebook');
      expect(oldLog.existsSync(), isTrue, reason: 'log exists before the move');

      final cloud = Directory(p.join(tmp.path, 'FakeDrive'))..createSync();
      final newPath = await app.moveNotebookToFolder(nb.id, cloud.path);

      // The `.onotebook` went: append-only logs, one writer per file, plus
      // content-addressed blobs.
      expect(p.isWithin(cloud.path, newPath), isTrue);
      expect(Directory(newPath).existsSync(), isTrue);
      expect(oldLog.existsSync(), isFalse, reason: 'the logs really moved');
      expect(repo.notebooks.firstWhere((n) => n.id == nb.id).logDir, newPath);

      // THE ASSERTION OF RECORD. Nothing SQLite can write may exist anywhere
      // under the synced folder — not the container, not its `-wal`, not its
      // `-shm`, at any depth. Named as a shape rather than as three paths so a
      // future rename cannot slip past it.
      final sqliteInCloud = cloud
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => p.basename(f.path))
          .where((n) => RegExp(r'\.onote(-wal|-shm)?$').hasMatch(n))
          .toList();
      expect(sqliteInCloud, isEmpty,
          reason: 'a WAL database in a replicated folder is ADR-0006 §2');

      // The container stayed put, still open, still readable — this is a
      // notebook that syncs, not one that moved house.
      expect(File(oldPath).existsSync(), isTrue,
          reason: 'the working file belongs on this computer');
      expect(repo.notebooks.firstWhere((n) => n.id == nb.id).file, oldPath);
      final data = repo.readPage(nb.id, app.pageId!);
      expect(data.blocks.single.content['text'], 'before');
    });

    test('refuses to overwrite a notebook already in the target folder',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final tmp = Directory.systemTemp.createTempSync('onote_move_clash_');
      final repo = await Repository.openAt(tmp);
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final nb = await repo.createNotebook('Clash');
      final app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();

      final cloud = Directory(p.join(tmp.path, 'FakeDrive'))..createSync();
      // Something with the same name is already there.
      final existing = File(p.join(cloud.path, 'Clash.onote'))
        ..writeAsStringSync('not our notebook');

      final newPath = await app.moveNotebookToFolder(nb.id, cloud.path);
      expect(newPath, isNot(existing.path));
      expect(existing.readAsStringSync(), 'not our notebook',
          reason: 'the stranger file is untouched');
    });

    test('a notebook moved into a folder still records ops there', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final tmp = Directory.systemTemp.createTempSync('onote_move_ops_');
      final repo = await Repository.openAt(tmp);
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final nb = await repo.createNotebook('Ops');
      final app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      app.pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;

      final cloud = Directory(p.join(tmp.path, 'FakeDrive'))..createSync();
      final newPath = await app.moveNotebookToFolder(nb.id, cloud.path);

      // Editing after the move must write to the NEW log location, or this
      // device's changes go somewhere nobody is watching.
      app.blocks = [
        Block(type: BlockType.text, x: 0, y: 0, content: {'text': 'after move'})
      ];
      app.markDirty();
      await app.flushSave();

      final store = OpLogStore.forNotebook(newPath);
      expect(store.readAll(), isNotEmpty);
    });
  });

  group('watching for other devices', () {
    test('ignores our own log, reacts to a foreign one', () async {
      final tmp = Directory.systemTemp.createTempSync('onote_watch_');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      final ops = Directory(p.join(tmp.path, 'ops'))..createSync();

      var fired = 0;
      final w = OpFolderWatcher(
        opsDir: ops,
        ownDevice: 'me',
        onForeignChange: () => fired++,
        settle: const Duration(milliseconds: 60),
      )..start();
      addTearDown(w.stop);

      // Our own write must not trigger a pull, or every save schedules a
      // re-read of what we just wrote — a feedback loop.
      File(p.join(ops.path, 'me.oplog')).writeAsStringSync('{"seq":1}\n');
      await Future<void>.delayed(const Duration(milliseconds: 220));
      expect(fired, 0, reason: 'own-device writes are ignored');

      File(p.join(ops.path, 'them.oplog')).writeAsStringSync('{"seq":1}\n');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(fired, greaterThan(0), reason: 'a foreign log triggers a pull');
    });

    test('a burst of writes settles into a single pull', () async {
      final tmp = Directory.systemTemp.createTempSync('onote_watch_burst_');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      final ops = Directory(p.join(tmp.path, 'ops'))..createSync();

      var fired = 0;
      final w = OpFolderWatcher(
        opsDir: ops,
        ownDevice: 'me',
        onForeignChange: () => fired++,
        settle: const Duration(milliseconds: 120),
      )..start();
      addTearDown(w.stop);

      // A cloud client writes in chunks and often renames a temp file over the
      // target, so one remote edit produces many events.
      final f = File(p.join(ops.path, 'them.oplog'));
      for (var i = 0; i < 6; i++) {
        f.writeAsStringSync('{"seq":$i}\n');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(fired, 1, reason: 'debounced to one pull');
    });

    test('overlapping pulls do not apply remote ops twice', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final tmp = Directory.systemTemp.createTempSync('onote_pull_race_');
      final repo = await Repository.openAt(tmp);
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final nb = await repo.createNotebook('Race');
      final app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      final pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
      app.pageId = pageId;

      final ref = repo.notebooks.firstWhere((n) => n.id == nb.id);
      final store = OpLogStore.forNotebook(ref.file);
      store.append('other', [
        Op(
            device: 'other',
            seq: 1,
            lamport: 9,
            timestamp: 1,
            kind: OpKind.blockSet,
            data: {
              'pageId': pageId,
              'block': {
                'id': 'r1',
                'type': 'text',
                'x': 0,
                'y': 0,
                'w': 320,
                'content': {'text': 'remote'}
              }
            }),
      ]);

      // The watcher can fire again while a pull is still running; two
      // overlapping pulls would both read the same pending ops and both
      // advance the watermark.
      final results =
          await Future.wait([app.syncPull(nb.id), app.syncPull(nb.id)]);
      expect(results.where((n) => n > 0), hasLength(1),
          reason: 'exactly one pull does the work');
      final stored = repo.readPage(nb.id, pageId);
      expect(stored.blocks.where((b) => b.id == 'r1'), hasLength(1));
    });

    test('ops that arrive DURING a pull are not dropped', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final tmp = Directory.systemTemp.createTempSync('onote_pull_live_');
      final repo = await Repository.openAt(tmp);
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final nb = await repo.createNotebook('Live');
      final app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      final pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
      app.pageId = pageId;

      final ref = repo.notebooks.firstWhere((n) => n.id == nb.id);
      final store = OpLogStore.forNotebook(ref.file);
      Op remoteBlock(int seq, int lamport, String id) => Op(
              device: 'other',
              seq: seq,
              lamport: lamport,
              timestamp: 1,
              kind: OpKind.blockSet,
              data: {
                'pageId': pageId,
                'block': {
                  'id': id,
                  'type': 'text',
                  'x': 0,
                  'y': 0,
                  'w': 320,
                  'content': {'text': id}
                }
              });

      store.append('other', [remoteBlock(1, 9, 'r1')]);

      // Start a pull, and while it is in flight let a second change land and
      // the watcher fire again. The re-entrant call must not be swallowed: the
      // debounce has already fired, so if this request is dropped nothing will
      // ask again and `r2` sits unapplied indefinitely.
      final first = app.syncPull(nb.id);
      store.append('other', [remoteBlock(2, 10, 'r2')]);
      final reentrant = await app.syncPull(nb.id);
      await first;

      expect(reentrant, 0, reason: 'the re-entrant call itself does no work');
      final stored = repo.readPage(nb.id, pageId);
      expect(stored.blocks.where((b) => b.id == 'r1'), hasLength(1));
      expect(stored.blocks.where((b) => b.id == 'r2'), hasLength(1),
          reason: 'the change that arrived mid-pull must still be applied');
    });

    test('stop() is idempotent and safe before start', () {
      final tmp = Directory.systemTemp.createTempSync('onote_watch_stop_');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      final w = OpFolderWatcher(
        opsDir: Directory(p.join(tmp.path, 'nope')),
        ownDevice: 'me',
        onForeignChange: () {},
      );
      expect(w.start, returnsNormally); // missing directory
      expect(w.isWatching, isFalse);
      expect(w.stop, returnsNormally);
      expect(w.stop, returnsNormally);
    });
  });

  _pullStaysInteractive(() => haveSqlite);
  _deletingASharedNotebook(() => haveSqlite);
  _convergesWhateverOrderLogsArriveIn(() => haveSqlite);
  _oneFoldThatCreatesAndDeletes(() => haveSqlite);
}

// ── "the app to fully lock up for 10-20s as it works" ────────────────────

/// A pull writes the container in slices with the event loop let go between
/// them, so a big fold is a slow moment rather than a frozen window.
///
/// **Counted, never clocked.** A wall-clock threshold here would be measuring
/// the runner's weather; what the fix actually changes is whether the apply is
/// ONE turn of the event loop or many, so that is what is asserted. Before
/// pacing, a timer scheduled alongside the pull got 2 or 3 turns — the awaits
/// that already existed before the write — and the whole 2,000-page fold went
/// past in a single block. After, it gets one per chunk.
void _pullStaysInteractive(bool Function() haveSqlite) {
  group('a big pull stays interactive', () {
    late Directory tmp;
    late Repository repo;

    setUp(() async {
      if (!haveSqlite()) return;
      tmp = Directory.systemTemp.createTempSync('onote_pull_pace_');
      repo = await Repository.openAt(tmp);
    });
    tearDown(() {
      if (!haveSqlite()) return;
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    /// [pages] remote pages of [blocksPerPage] blocks each, appended as one
    /// foreign device's log.
    void seedForeign(String file, String sectionId,
        {required int pages,
        int blocksPerPage = 4,
        int firstSeq = 0,
        String idPrefix = 'rp'}) {
      final store = OpLogStore.forNotebook(file);
      final ops = <Op>[];
      var seq = firstSeq;
      for (var i = 0; i < pages; i++) {
        final pid = '$idPrefix$i';
        ops.add(Op(
            device: 'other',
            seq: ++seq,
            lamport: seq,
            timestamp: 1,
            kind: OpKind.nodeUpsert,
            data: {
              'id': pid,
              'kind': 'page',
              'parentId': sectionId,
              'title': 'Remote $i',
              'position': 'a${i.toString().padLeft(5, '0')}',
            }));
        for (var b = 0; b < blocksPerPage; b++) {
          ops.add(Op(
              device: 'other',
              seq: ++seq,
              lamport: seq,
              timestamp: 1,
              kind: OpKind.blockSet,
              data: {
                'pageId': pid,
                'block': {
                  'id': 'b$i-$b',
                  'type': 'text',
                  'x': 0,
                  'y': b * 30,
                  'w': 600,
                  'content': {'text': 'remote $i-$b'}
                }
              }));
        }
      }
      store.append('other', ops);
    }

    test('THE FOLD YIELDS INSTEAD OF BLOCKING', () async {
      if (!haveSqlite()) return markTestSkipped('sqlite unavailable');
      final nb = await repo.createNotebook('Big');
      final app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
      final ref = repo.notebooks.firstWhere((n) => n.id == nb.id);

      // A tiny fold FIRST, so the recorder is open and its background replay
      // is paid for. Without this the isolate spawn alone hands the counter
      // dozens of turns and the measurement says nothing about the apply —
      // which is exactly how the first version of this test passed against
      // the unpaced code.
      seedForeign(ref.file, section.id, pages: 1);
      await app.syncPull(nb.id);

      seedForeign(ref.file, section.id,
          pages: 400, firstSeq: 1000, idPrefix: 'q');
      var turns = 0;
      final t = Timer.periodic(const Duration(milliseconds: 1), (_) => turns++);
      final folded = await app.syncPull(nb.id);
      t.cancel();

      expect(folded, greaterThan(0));
      // 400 pages at eight per slice is ~50 yields, plus the node slices.
      // Unpaced, everything from `applyForeign` to the last `writePage` is one
      // turn of the event loop and this counter cannot move at all.
      expect(turns, greaterThan(20),
          reason: 'the apply must give the window turns to paint and type in, '
              'not run as one block');
      // …and it still applied everything.
      expect(repo.loadNodes(nb.id).where((n) => n.id.startsWith('q')).length,
          400);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('A REMOTE DELETE LANDS, AND TAKES NOTHING ELSE WITH IT', () async {
      if (!haveSqlite()) return markTestSkipped('sqlite unavailable');
      // The deletion phase used to share one transaction with the page
      // writes, which guaranteed it ran after them. It is now its own
      // transaction, so "deletes last" has to be re-proved — and with it the
      // two ways a delete can do damage: losing (the node stays) and
      // over-reaching (something unrelated goes too).
      final nb = await repo.createNotebook('Deletes');
      final app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
      final ref = repo.notebooks.firstWhere((n) => n.id == nb.id);
      // Enough pages to span several slices, so the delete phase really is a
      // separate transaction from the writes.
      seedForeign(ref.file, section.id, pages: 40);
      await app.syncPull(nb.id);
      expect(repo.loadNodes(nb.id).where((n) => n.id.startsWith('rp')).length,
          40);

      // The other device deletes ONE page, and — in the same batch, at a
      // HIGHER lamport than the delete — edits it again. Delete wins
      // (ADR-0006 §6a.3): a later edit must not resurrect it.
      final store = OpLogStore.forNotebook(ref.file);
      store.append('other', [
        Op(
            device: 'other',
            seq: 100000,
            lamport: 100000,
            timestamp: 9,
            kind: OpKind.nodeDelete,
            data: {'id': 'rp7', 'deletedAt': 9}),
        Op(
            device: 'other',
            seq: 100001,
            lamport: 100001,
            timestamp: 10,
            kind: OpKind.blockSet,
            data: {
              'pageId': 'rp7',
              'block': {
                'id': 'late',
                'type': 'text',
                'x': 0,
                'y': 0,
                'w': 600,
                'content': {'text': 'after the delete'}
              }
            }),
        // …and an unrelated page gets a genuine edit in the same pull.
        Op(
            device: 'other',
            seq: 100002,
            lamport: 100002,
            timestamp: 11,
            kind: OpKind.blockSet,
            data: {
              'pageId': 'rp8',
              'block': {
                'id': 'b8-0',
                'type': 'text',
                'x': 0,
                'y': 0,
                'w': 600,
                'content': {'text': 'edited by the other device'}
              }
            }),
      ]);
      await app.syncPull(nb.id);

      // `loadNodes` returns only what is live, so a soft-deleted page simply
      // is not in it.
      final nodes = repo.loadNodes(nb.id);
      expect(nodes.where((n) => n.id == 'rp7'), isEmpty,
          reason: 'the remote delete must reach the container — a delete that '
              'does not is "delete loses", and a later edit at a HIGHER '
              'lamport must not bring it back');
      // NOTHING ELSE. The whole reason this is worth a test: a delete phase
      // that over-reaches destroys notes on a device that never asked.
      expect(nodes.where((n) => n.id.startsWith('rp')).length, 39,
          reason: 'exactly one page went, and it was the one named');
      expect(
          repo
              .readPage(nb.id, 'rp8')
              .blocks
              .where((b) => b.content['text'] == 'edited by the other device'),
          hasLength(1),
          reason: "the unrelated page's edit survived the same pull");
      // The other 38 keep the content they were given.
      expect(repo.readPage(nb.id, 'rp0').blocks, hasLength(4));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('A SAVE MADE DURING A FOLD WAITS FOR IT', () async {
      if (!haveSqlite()) return markTestSkipped('sqlite unavailable');
      // Pacing hands the event loop back mid-fold, which is a window that did
      // not exist when the apply was one block: a save landing in it writes
      // this device's copy of a page the fold has ALREADY rewritten, and the
      // watermark then moves past the ops that would have fixed it — so that
      // page stays wrong until something rebuilds the container.
      final nb = await repo.createNotebook('Interleave');
      final app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
      final ref = repo.notebooks.firstWhere((n) => n.id == nb.id);
      seedForeign(ref.file, section.id, pages: 1);
      await app.syncPull(nb.id); // warm, as above
      seedForeign(ref.file, section.id,
          pages: 400, firstSeq: 1000, idPrefix: 'q');

      final pull = app.syncPull(nb.id);
      // Mid-fold, the user types on a page the other device also touched.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      app.pageId = 'q3';
      app.blocks = [
        Block(
            id: 'mine',
            type: BlockType.text,
            x: 0,
            y: 0,
            content: {'text': 'typed during the pull'})
      ];
      app.markDirty();
      final save = app.flushSave();
      // Many fold yields later, the save must still not have run: a save is
      // milliseconds of work and would otherwise have finished long ago.
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(app.hasUnsavedChanges, isTrue,
          reason: 'the save has to wait for the fold, not race it');

      await pull;
      await save;
      expect(app.hasUnsavedChanges, isFalse, reason: 'and then it happens');
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}

// ── "there were a bunch of files left over in the folder" ────────────────

void _deletingASharedNotebook(bool Function() haveSqlite) {
  group('deleting a notebook in a shared folder', () {
    late Directory root;
    late Directory shared;

    setUp(() {
      root = Directory.systemTemp.createTempSync('onote_purge_');
      shared = Directory(p.join(root.path, 'FakeDrive'))..createSync();
    });
    tearDown(() {
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });

    /// Device A: a notebook with a page, moved into the shared folder.
    Future<({Repository repo, AppState app, String id, String path})>
        deviceA() async {
      final repo = await Repository.openAt(
          Directory(p.join(root.path, 'wsA'))..createSync());
      final nb = await repo.createNotebook('Shared');
      final app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      app.pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
      app.blocks = [
        Block(type: BlockType.text, x: 0, y: 0, content: {'text': 'A wrote this'})
      ];
      app.markDirty();
      await app.flushSave();
      final path = await app.moveNotebookToFolder(nb.id, shared.path);
      return (repo: repo, app: app, id: nb.id, path: path);
    }

    test('PURGING A JOINED NOTEBOOK LEAVES THE OTHER DEVICE ALONE', () async {
      if (!haveSqlite()) return markTestSkipped('sqlite unavailable');
      final a = await deviceA();
      addTearDown(a.repo.dispose);
      addTearDown(a.app.dispose);
      final sharedLogs =
          Directory('${p.withoutExtension(a.path)}.onotebook');
      expect(File(p.join(sharedLogs.path, 'ops', _onlyLog(a.path))).existsSync(),
          isTrue,
          reason: "device A's log is there");

      // Device B joins the same folder: private container here, shared logs
      // there.
      final repoB = await Repository.openAt(
          Directory(p.join(root.path, 'wsB'))..createSync());
      addTearDown(repoB.dispose);
      final appB = AppState(repoB);
      addTearDown(appB.dispose);
      await appB.openExistingNotebook(a.path);
      await repoB.createNotebook('Somewhere else'); // deleting the last is refused
      final joined = repoB.notebooks.firstWhere((n) => n.title == 'Shared');
      appB.notebookId =
          repoB.notebooks.firstWhere((n) => n.title == 'Somewhere else').id;

      // Photograph the shared folder the instant before the purge, and compare
      // the instant after. Snapshotting earlier compares against the wrong
      // thing: both devices have background work in flight (the recorder warm
      // appends a manifest and back-fills the tree), so a log that legitimately
      // GREW between the two reads looked like the purge had touched it — the
      // first version of this test flaked under a full-suite run for exactly
      // that reason.
      Map<String, List<int>> photograph() => {
            for (final f in sharedLogs.listSync(recursive: true))
              if (f is File)
                p.relative(f.path, from: sharedLogs.path): f.readAsBytesSync()
          };
      // …and the photograph is only honest once every OTHER writer has put
      // its pen down. Byte equality is the right bar — a purge that APPENDED
      // so much as one op to a log in the shared folder would replicate the
      // deletion to every other device, which is the 320e0be disaster class —
      // but it means the two devices' watchers must be disarmed first: either
      // one can legitimately append at any moment (a foreign-change pull, the
      // warm's tree backfill), and on a starved machine (two cores, low
      // priority — the shape of a busy CI runner) one of those landed between
      // the two reads and the purge was blamed for it.
      a.app.setAutoSync(false);
      appB.setAutoSync(false);
      await a.app.settleBackgroundWork();
      await appB.settleBackgroundWork();
      final before = photograph();
      expect(before, isNotEmpty);
      // What the confirmation dialog says, asked when it asks — before the
      // click. Afterwards there is no registry entry left to ask about.
      final caveat = appB.purgeCaveat(joined.id);

      // …and deletes it for good.
      await appB.deleteNotebook(joined.id);
      await appB.purgeNotebook(joined.id);

      // THE POINT. This used to delete the whole `.onotebook` — device A's
      // log and every blob in it — because the only "is it shared?" test
      // asked this workspace, which cannot see another computer.
      expect(sharedLogs.existsSync(), isTrue,
          reason: "device B deleting its copy must not remove device A's ops");
      expect(photograph(), before,
          reason: 'not one byte of the shared folder changed');
      expect(File(a.repo.notebooks.firstWhere((n) => n.id == a.id).file)
              .existsSync(),
          isTrue,
          reason: "device A's own working file is not B's to delete");
      // B's own private copy is gone, which is what the user asked for.
      expect(File(joined.file).existsSync(), isFalse);
      expect(File('${joined.file}-wal').existsSync(), isFalse);
      expect(File('${joined.file}-shm').existsSync(), isFalse);
      // And device A can still read its own notebook.
      final nodes = a.repo.loadNodes(a.id);
      expect(nodes.where((n) => n.kind == NodeKind.page), isNotEmpty);
      // The confirmation said so before the click, in words with no jargon.
      expect(caveat, contains('other devices'));
    });

    test('purging the notebook this device OWNS removes both halves', () async {
      if (!haveSqlite()) return markTestSkipped('sqlite unavailable');
      // The complement, and the reason the rule is about ownership rather
      // than about the folder: device A put the pair in Drive itself, so
      // leaving either half behind is the leftover being fixed.
      final a = await deviceA();
      addTearDown(a.repo.dispose);
      await a.repo.createNotebook('Somewhere else');
      a.app.notebookId =
          a.repo.notebooks.firstWhere((n) => n.title == 'Somewhere else').id;
      expect(a.app.purgeKeepsSharedFolder(a.id), isFalse);
      expect(a.app.purgeCaveat(a.id), isNull);
      await a.app.deleteNotebook(a.id);
      await a.app.purgeNotebook(a.id);

      expect(shared.listSync(), isEmpty,
          reason: 'container, its -wal and -shm, and the logs all go together');
    });

    test('SETUP DOES NOT OFFER A LEFTOVER AS A NOTEBOOK TO JOIN', () {
      // "it thought there were several notebooks which didnt actually exist".
      // The real folder held a live notebook and, beside it under a name one
      // character different, a 35.9 MB container whose log directory had been
      // deleted out from under it — and setup offered both.
      final live = File(p.join(shared.path, 'Physics.onote'))
        ..writeAsStringSync('a notebook');
      Directory(p.join(shared.path, 'Physics.onotebook', 'ops'))
          .createSync(recursive: true);
      File(p.join(shared.path, 'Physics (2).onote'))
          .writeAsStringSync('a leftover');
      // The sidecars a deleted notebook strands are not notebooks either.
      File(p.join(shared.path, 'Physics.onote-wal')).writeAsStringSync('w');
      File(p.join(shared.path, 'Physics.onote-shm')).writeAsStringSync('s');

      final found = findExistingNotebooks(searchIn: [
        CloudFolder(
            name: 'FakeDrive', path: shared.path, kind: CloudKind.other)
      ]);
      expect(found.map((f) => f.path), [live.path],
          reason: 'a container with no `.onotebook` beside it was never put '
              'there by another device');
    });

    test('A PURGE TAKES THE WRITE-AHEAD FILES WITH THE CONTAINER', () async {
      if (!haveSqlite()) return markTestSkipped('sqlite unavailable');
      final repo = await Repository.openAt(
          Directory(p.join(root.path, 'ws'))..createSync());
      addTearDown(repo.dispose);
      await repo.createNotebook('Keep');
      final nb = await repo.createNotebook('Doomed');
      final ref = repo.notebooks.firstWhere((n) => n.id == nb.id);
      await repo.trashNotebook(nb.id); // closes the handle, as a real trash does
      // Exactly what an unclean shutdown leaves, and what the real workspace
      // was found holding: a 32 KB `-shm` and a `-wal` for a notebook that no
      // longer exists. The `-wal` is committed content nothing will ever open.
      File('${ref.file}-wal').writeAsStringSync('committed pages live here');
      File('${ref.file}-shm').writeAsStringSync('shared memory index');

      await repo.purgeNotebook(nb.id);

      expect(File(ref.file).existsSync(), isFalse);
      expect(File('${ref.file}-wal').existsSync(), isFalse,
          reason: 'a stranded -wal is real content in a file nothing reopens');
      expect(File('${ref.file}-shm').existsSync(), isFalse);
    });

    test('GETTING THE WORKING FILE OUT OF DRIVE FOLDS ITS -WAL IN FIRST',
        () async {
      if (!haveSqlite()) return markTestSkipped('sqlite unavailable');
      // v0.17 Step 4's second proof, on the one path that still copies a
      // container. In WAL mode the `.onote` is not the notebook: measured on a
      // freshly written one, the container was 4,096 bytes and all 238,992
      // bytes of content were in the `-wal`, and on the owner's real notebook
      // a 4,128,272-byte `-wal` held 2 whole pages and newer revisions of 6
      // more. A copy of the main file alone plus a delete of the sidecars is a
      // "successful" move that produces an empty notebook — and the result
      // passes `PRAGMA integrity_check`.
      final ws = Directory(p.join(root.path, 'ws'))..createSync();
      final repo = await Repository.openAt(ws);
      final nb = await repo.createNotebook('Mover');
      final app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      app.pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
      app.blocks = [
        Block(type: BlockType.text, x: 0, y: 0, content: {'text': 'in the wal'})
      ];
      app.markDirty();
      await app.flushSave();
      final ref = repo.notebooks.firstWhere((n) => n.id == nb.id);
      final logs = Directory(ref.logDirPath);

      // Take the un-checkpointed pair off disk exactly as it stands, then put
      // it back after a clean close has folded it in. That is the state the
      // bug needs and the state any real notebook is in between checkpoints:
      // a nearly empty container beside a `-wal` holding everything.
      final mainBytes = File(ref.file).readAsBytesSync();
      final walBytes = File('${ref.file}-wal').readAsBytesSync();
      expect(mainBytes.length, lessThan(walBytes.length),
          reason: 'the notebook is IN the wal, which is the whole point');
      await repo.flushWorkspace();
      repo.dispose();

      // **THE STATE A PRE-v0.17 BUILD LEFT ON DISK**, reproduced exactly:
      // container, `-wal` and `.onotebook` all sitting in the cloud folder,
      // with the registry pointing at the container there. This is the
      // notebook the owner has in `G:\My Drive\Openote` right now.
      final inDrive = p.join(shared.path, 'Mover.onote');
      File(inDrive).writeAsBytesSync(mainBytes);
      File('$inDrive-wal').writeAsBytesSync(walBytes);
      for (final f in [ref.file, '${ref.file}-wal', '${ref.file}-shm']) {
        try {
          File(f).deleteSync();
        } catch (_) {}
      }
      final logsInDrive = Directory(p.join(shared.path, 'Mover.onotebook'));
      logsInDrive.createSync(recursive: true);
      for (final e in logs.listSync(recursive: true).whereType<File>()) {
        final target = p.join(
            logsInDrive.path, p.relative(e.path, from: logs.path));
        Directory(p.dirname(target)).createSync(recursive: true);
        e.copySync(target);
      }
      logs.deleteSync(recursive: true);
      final wsFile = File(p.join(ws.path, 'workspace.json'));
      final j = jsonDecode(wsFile.readAsStringSync()) as Map<String, dynamic>;
      ((j['notebooks'] as List).single as Map)['file'] = inDrive;
      wsFile.writeAsStringSync(jsonEncode(j));

      // A session that has never opened this notebook — so `_open` holds no
      // handle for it and nothing has checkpointed.
      final repo2 = await Repository.openAt(ws);
      addTearDown(repo2.dispose);
      final app2 = AppState(repo2);
      addTearDown(app2.dispose);
      app2.rememberSyncRoot(shared.path);
      expect(app2.containerSyncFolder(nb.id)?.path, shared.path,
          reason: 'the app has to be able to SEE the problem before it offers '
              'to fix it');

      final moved = await app2.moveContainerOutOfSyncFolder(nb.id);

      // The file that arrived is the notebook, not an empty database.
      expect(p.isWithin(ws.path, moved), isTrue);
      expect(File(moved).lengthSync(), greaterThan(mainBytes.length),
          reason: 'a container the size it was is the WAL left behind');
      // Identical page count AND identical page content, which is the half a
      // size check cannot see.
      final pages =
          repo2.loadNodes(nb.id).where((n) => n.kind == NodeKind.page).toList();
      expect(pages, hasLength(1));
      expect(repo2.readPage(nb.id, pages.first.id).blocks.single
          .content['text'], 'in the wal');

      // Drive keeps the notes and loses the database. Nothing SQLite writes is
      // left there, at any depth; the `.onotebook` is untouched.
      expect(
          shared
              .listSync(recursive: true)
              .whereType<File>()
              .map((f) => p.basename(f.path))
              .where((n) => RegExp(r'\.onote(-wal|-shm)?$').hasMatch(n)),
          isEmpty);
      expect(logsInDrive.existsSync(), isTrue);
      expect(repo2.notebooks.single.logDir, logsInDrive.path,
          reason: 'the notebook still syncs through the same folder');
    });
  });
}

/// The single `.oplog` in a notebook's ops directory — this device's.
String _onlyLog(String container) => Directory(
        p.join('${p.withoutExtension(container)}.onotebook', 'ops'))
    .listSync()
    .map((e) => p.basename(e.path))
    .firstWhere((n) => n.endsWith('.oplog'));

// ── The fold parses across yields now. It must still SORT before it applies ──

/// Two devices holding the same logs must reach byte-identical content, no
/// matter which order the logs were read in.
///
/// **This is the guard on the pacing, and it is worth more than the speed.**
/// `pendingForeignOps` no longer parses the pending set in one block — the
/// read hands the event loop back every half megabyte. The tempting next step
/// is to cap how much is read per device per fold, and that step is a
/// convergence bug: ops would then be applied in ARRIVAL order (device by
/// device, whatever `deviceIds()` listed first) instead of Lamport order, and
/// `Materializer.apply` is last-writer-wins by application order. Two devices
/// whose logs happened to be listed differently would hold different text for
/// the same block, permanently, with nothing anywhere to notice it.
///
/// So the property under test is exactly that one: **arrival order must not
/// reach the materialiser.** The staging buffer is filled device by device,
/// then sorted once by [Op.compare], then applied as a single batch — so
/// permuting which log each op lands in cannot change the result.
///
/// What is deliberately NOT claimed here: that folding the same logs in
/// several separate PULLS converges. It does not, and never has — the
/// watermark makes a pull the unit, and an op that turns up in a later pull
/// carrying a LOWER Lamport than one already applied is applied after it.
/// That is a property of incremental sync predating all of this; pacing the
/// parse neither causes nor cures it, and a test asserting otherwise would be
/// asserting a bug.
void _convergesWhateverOrderLogsArriveIn(bool Function() haveSqlite) {
  group('CONVERGENCE: arrival order must not survive the fold', () {
    late Directory tmp;
    late Repository repo;

    setUp(() async {
      if (!haveSqlite()) return;
      tmp = Directory.systemTemp.createTempSync('onote_converge_');
      repo = await Repository.openAt(tmp);
    });
    tearDown(() {
      if (!haveSqlite()) return;
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    /// One shared history, spread over three foreign logs named [ids].
    ///
    /// Nine writes to the SAME block, round-robin: `ids[i % 3]` writes the
    /// i-th. Lamports are 20, 21, … 28 — strictly increasing and all distinct,
    /// so [Op.compare] never reaches its device-id tie-break and permuting
    /// [ids] changes ONLY which log each op lands in, never the order they
    /// sort into. The correct answer is always the last write, `v8`.
    ///
    /// Arrival order, by contrast, is `deviceIds()` order, which is
    /// alphabetical — so `['a', 'b', 'c']` reads the writer of `v8` last and
    /// `['c', 'b', 'a']` reads it FIRST. Applied unsorted those two give `v8`
    /// and `v6`. That is the divergence, and it is what the sort removes.
    void seedInterleaved(String file, String sectionId, List<String> ids) {
      final store = OpLogStore.forNotebook(file);
      final seq = <String, int>{for (final d in ids) d: 0};
      final ops = <String, List<Op>>{for (final d in ids) d: []};
      void add(String dev, int lamport, OpKind kind, Map<String, dynamic> d) {
        seq[dev] = seq[dev]! + 1;
        ops[dev]!.add(Op(
            device: dev,
            seq: seq[dev]!,
            lamport: lamport,
            timestamp: lamport,
            kind: kind,
            data: d));
      }

      // The tree first, from the log — a joined notebook has no container to
      // copy, so these rows are inserts and `page_mirror.page_id`'s foreign
      // key needs them before any page write.
      const pageIds = ['shared', 'quiet'];
      for (var i = 0; i < pageIds.length; i++) {
        add(ids[i], 10 + i, OpKind.nodeUpsert, {
          'id': pageIds[i],
          'kind': 'page',
          'parentId': sectionId,
          'title': 'Page ${pageIds[i]}',
          'position': 'a$i',
        });
      }
      // THE CONTESTED BLOCK. Nine last-writer-wins overwrites of one block.
      for (var i = 0; i < 9; i++) {
        add(ids[i % 3], 20 + i, OpKind.blockSet, {
          'pageId': 'shared',
          'block': {
            'id': 'blk',
            'type': 'text',
            'x': 0,
            'y': 0,
            'w': 600,
            'content': {'text': 'v$i'}
          }
        });
      }
      // Contested page PROPS too: a whole-map replace, so the loser leaves no
      // trace and a wrong order is visible in the container's mirror.
      const backgrounds = ['blank', 'grid', 'dotted'];
      for (var i = 0; i < 3; i++) {
        add(ids[i], 40 + i, OpKind.pageProps, {
          'pageId': 'shared',
          'props': {'background': backgrounds[i]}
        });
      }
      // And uncontested writes on a second page, one block per device, so the
      // comparison covers more than the single racing block.
      for (var i = 0; i < 3; i++) {
        add(ids[i], 50 + i, OpKind.blockSet, {
          'pageId': 'quiet',
          'block': {
            'id': 'q$i',
            'type': 'text',
            'x': 0,
            'y': 30.0 * i,
            'w': 600,
            'content': {'text': 'from slot $i'}
          }
        });
      }
      for (final d in ids) {
        store.append(d, ops[d]!);
      }
    }

    /// Everything the container holds for this notebook, canonically encoded.
    /// Key order and block order cannot make two equal notebooks look
    /// different — see [canonicalJson] — so a difference here is a real one.
    String contentOf(String nbId) => canonicalJson({
          for (final pid in const ['shared', 'quiet'])
            pid: {
              'blocks': [
                for (final b in repo.readPage(nbId, pid).blocks.toList()
                  ..sort((x, y) => x.id.compareTo(y.id)))
                  {'id': b.id, 'content': b.content}
              ],
              'props': repo.readPage(nbId, pid).props.toJson(),
            },
          // Only the nodes the LOG created. `createNotebook` also makes a
          // "Section 1" and an "Untitled page" whose ids are fresh uuidv7s per
          // notebook, so including them would make every snapshot differ for a
          // reason that has nothing to do with sync. The count goes in so a
          // fold that invented or lost a node still shows up.
          'nodes': [
            for (final n in repo.loadNodes(nbId))
              if (n.id == 'shared' || n.id == 'quiet') '${n.id}/${n.title}'
          ],
          'nodeCount': repo.loadNodes(nbId).length,
        });

    /// Create a notebook, give it the three logs under [ids], fold once.
    Future<({String id, List<Op> pending})> fold(
        String title, List<String> ids) async {
      final nb = await repo.createNotebook(title);
      final app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
      final ref = repo.notebooks.firstWhere((n) => n.id == nb.id);
      seedInterleaved(ref.file, section.id, ids);
      // The batch as the fold sees it, captured before the pull consumes it.
      // Reading it does not consume it: only `markForeignSeen` moves the
      // watermark, and only the pull calls that.
      final r = await app.warmRecorder(nb.id);
      final pending = await r!.pendingForeignOps(repo.getSetting);
      await app.syncPull(nb.id);
      return (id: nb.id, pending: pending);
    }

    test('THREE LOGS, EVERY READ ORDER, ONE RESULT', () async {
      if (!haveSqlite()) return markTestSkipped('sqlite unavailable');
      // Six notebooks, one per permutation of which device wrote which slot.
      // `deviceIds()` sorts, so the read order is always a→b→c and the
      // permutation is entirely a permutation of ARRIVAL.
      const perms = [
        ['a-dev', 'b-dev', 'c-dev'],
        ['a-dev', 'c-dev', 'b-dev'],
        ['b-dev', 'a-dev', 'c-dev'],
        ['b-dev', 'c-dev', 'a-dev'],
        ['c-dev', 'a-dev', 'b-dev'],
        ['c-dev', 'b-dev', 'a-dev'],
      ];
      final snapshots = <String, String>{};
      for (var i = 0; i < perms.length; i++) {
        final r = await fold('Perm$i', perms[i]);
        // The batch handed to `applyForeign` must already be in total order.
        // This is the guarantee itself, stated directly: whatever order the
        // logs were read in, the list that reaches the materialiser is sorted.
        final sorted = [...r.pending]..sort(Op.compare);
        expect(r.pending.map((o) => o.lamport), sorted.map((o) => o.lamport),
            reason: 'the staging buffer must be sorted before it is applied — '
                'arrival order reaching the materialiser is the divergence '
                'this whole design exists to prevent');
        snapshots['${perms[i]}'] = contentOf(r.id);
      }

      // BYTE-IDENTICAL, all six.
      final first = snapshots.values.first;
      for (final e in snapshots.entries) {
        expect(e.value, first,
            reason: 'two devices folding the same logs reached different '
                'content; the one that read ${snapshots.keys.first} and the '
                'one that read ${e.key} disagree');
      }
      // …and it is the RIGHT answer, not six copies of the same wrong one.
      // Unsorted, these come out as v8 or v6 depending on the permutation.
      expect(first, contains('"v8"'),
          reason: 'the highest-Lamport write to the contested block wins');
      expect(first, contains('dotted'),
          reason: 'and the highest-Lamport page.props with it');
      expect(first, contains('from slot 2'));
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}

// ── One fold that both creates and deletes ───────────────────────────────

/// A batch that creates something and then deletes it must not wedge sync.
///
/// **THE WEDGE, NOT THE EXCEPTION, IS THE BUG.** The pull applies in phases
/// and the node phase writes only LIVE nodes, so anything created and deleted
/// inside a single fold has no `nodes` row — while the page phase still holds
/// its page id and a live child still names it as a parent. Three foreign keys
/// point at `nodes(id)`, so the write failed with `SqliteException(787)`, the
/// slice rolled back, and the exception escaped `_syncPullLocked` BEFORE the
/// watermark advanced. The batch therefore stayed pending, and every later
/// pull replayed it and threw in exactly the same place: syncing stopped on
/// that device permanently, with nothing on screen to say why.
///
/// So each test here pulls TWICE. A fix that quietly dropped the whole batch
/// would pass "it did not throw"; it cannot pass "the watermark moved and the
/// next pull delivered the next edit".
void _oneFoldThatCreatesAndDeletes(bool Function() haveSqlite) {
  group('a fold that creates AND deletes leaves sync working', () {
    late Directory tmp;
    late Repository repo;

    setUp(() async {
      if (!haveSqlite()) return;
      tmp = Directory.systemTemp.createTempSync('onote_ghost_');
      repo = await Repository.openAt(tmp);
    });
    tearDown(() {
      if (!haveSqlite()) return;
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    Op op(int s, OpKind k, Map<String, dynamic> d) =>
        Op(device: 'other', seq: s, lamport: s, timestamp: s, kind: k, data: d);

    Map<String, dynamic> textBlock(String id, String text) => {
          'id': id,
          'type': 'text',
          'x': 0,
          'y': 0,
          'w': 600,
          'content': {'text': text}
        };

    int? watermark(String nb) =>
        (repo.getSetting(SyncRecorder.foreignSeqKey(nb, 'other')) as num?)
            ?.toInt();

    test('A PAGE CREATED AND DELETED IN ONE FOLD DOES NOT WEDGE SYNC',
        () async {
      if (!haveSqlite()) return markTestSkipped('sqlite unavailable');
      final nb = await repo.createNotebook('Ghost');
      final app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
      final ref = repo.notebooks.firstWhere((n) => n.id == nb.id);
      final store = OpLogStore.forNotebook(ref.file);

      store.append('other', [
        // A page that survives the batch, in the SAME page-phase slice as the
        // one that does not — the rollback took whatever it was sharing a
        // transaction with, so this is how "the exception dropped notes that
        // were nothing to do with it" gets pinned.
        op(1, OpKind.nodeUpsert, {
          'id': 'keep',
          'kind': 'page',
          'parentId': section.id,
          'title': 'Keep',
          'position': 'a0',
        }),
        op(2, OpKind.blockSet,
            {'pageId': 'keep', 'block': textBlock('k0', 'kept')}),
        // …and one created, written to, and deleted before we ever pulled.
        op(3, OpKind.nodeUpsert, {
          'id': 'ghost',
          'kind': 'page',
          'parentId': section.id,
          'title': 'Ghost',
          'position': 'a1',
        }),
        op(4, OpKind.blockSet,
            {'pageId': 'ghost', 'block': textBlock('g0', 'gone')}),
        op(5, OpKind.nodeDelete, {'id': 'ghost', 'deletedAt': 5}),
      ]);

      expect(await app.syncPull(nb.id), 5);
      expect(watermark(nb.id), 5,
          reason: 'the watermark MUST move: leaving it behind is what makes '
              'this permanent rather than a one-off failure');

      // DELETE WINS, and takes nothing else with it.
      expect(repo.loadNodes(nb.id).where((n) => n.id == 'ghost'), isEmpty,
          reason: 'a page deleted on the other device must not appear here');
      expect(repo.readPage(nb.id, 'ghost').blocks, isEmpty);
      expect(repo.loadNodes(nb.id).where((n) => n.id == 'keep'), hasLength(1),
          reason: 'the page that was NOT deleted must still be here');
      expect(repo.readPage(nb.id, 'keep').blocks.single.content['text'], 'kept',
          reason: 'and with its content — dropping the whole batch would also '
              'stop the exception, and would also be wrong');

      // THE SECOND PULL IS THE POINT. Against the wedge this replays the
      // poisoned batch and throws again, for ever.
      store.append('other', [
        op(6, OpKind.blockSet,
            {'pageId': 'keep', 'block': textBlock('k1', 'the next edit')}),
      ]);
      expect(await app.syncPull(nb.id), 1);
      expect(watermark(nb.id), 6);
      expect(
          repo
              .readPage(nb.id, 'keep')
              .blocks
              .where((b) => b.content['text'] == 'the next edit'),
          hasLength(1),
          reason: 'later edits keep arriving; sync did not stop at the batch '
              'it could not apply');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('A SECTION CREATED AND DELETED IN ONE FOLD TAKES ITS PAGES WITH IT',
        () async {
      if (!haveSqlite()) return markTestSkipped('sqlite unavailable');
      // The same fault one phase earlier, and the one that is easy to miss:
      // `nodeDelete` marks only the node it names, so the deleted section's
      // pages are still LIVE in the log's state — pointing at a parent the
      // node phase is not writing. `nodes.parent_id` is a foreign key too.
      final nb = await repo.createNotebook('Doomed section');
      final app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
      final ref = repo.notebooks.firstWhere((n) => n.id == nb.id);
      final store = OpLogStore.forNotebook(ref.file);

      store.append('other', [
        op(1, OpKind.nodeUpsert, {
          'id': 'sec',
          'kind': 'section',
          'title': 'Doomed',
          'position': 'b0',
          'level': 0,
        }),
        op(2, OpKind.nodeUpsert, {
          'id': 'child',
          'kind': 'page',
          'parentId': 'sec',
          'title': 'Child',
          'position': 'b1',
          'level': 1,
        }),
        op(3, OpKind.blockSet,
            {'pageId': 'child', 'block': textBlock('c0', 'inside the doomed')}),
        // Only the section is deleted. The child is never mentioned again.
        op(4, OpKind.nodeDelete, {'id': 'sec', 'deletedAt': 4}),
        // A page in a section that is NOT going anywhere, to prove the drop
        // is confined to the deleted subtree.
        op(5, OpKind.nodeUpsert, {
          'id': 'safe',
          'kind': 'page',
          'parentId': section.id,
          'title': 'Safe',
          'position': 'b2',
        }),
        op(6, OpKind.blockSet,
            {'pageId': 'safe', 'block': textBlock('s0', 'still here')}),
      ]);

      expect(await app.syncPull(nb.id), 6);
      expect(watermark(nb.id), 6);

      final ids = repo.loadNodes(nb.id).map((n) => n.id).toSet();
      expect(ids, isNot(contains('sec')));
      expect(ids, isNot(contains('child')),
          reason: 'deleting a section soft-deletes its whole subtree on the '
              'device that did it, so a page under a section that is gone '
              'must not surface here as a stray');
      expect(ids, contains('safe'));
      expect(repo.readPage(nb.id, 'safe').blocks.single.content['text'],
          'still here');

      // And the next batch still arrives.
      store.append('other', [
        op(7, OpKind.blockSet,
            {'pageId': 'safe', 'block': textBlock('s1', 'and still syncing')}),
      ]);
      expect(await app.syncPull(nb.id), 1);
      expect(watermark(nb.id), 7);
      expect(repo.readPage(nb.id, 'safe').blocks, hasLength(2));
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
