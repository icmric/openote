// Cloud sync via a synced folder: moving a notebook, and noticing another
// device's changes.
//
// The move is the risky operation — it relocates a user's whole notebook
// across volumes — so it is copy, verify, then delete, and these tests pin
// that a failure at any step leaves the notebook intact somewhere.
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
    test('moves the container AND its op log, and repoints the registry',
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

      expect(p.isWithin(cloud.path, newPath), isTrue);
      expect(File(newPath).existsSync(), isTrue);
      expect(File(oldPath).existsSync(), isFalse, reason: 'original removed');
      // The log must travel too, or the notebook arrives without the very
      // thing that makes it syncable.
      expect(Directory('${p.withoutExtension(newPath)}.onotebook').existsSync(),
          isTrue);
      expect(oldLog.existsSync(), isFalse);
      // Registry repointed, and the content still reads.
      expect(repo.notebooks.firstWhere((n) => n.id == nb.id).file, newPath);
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
}
