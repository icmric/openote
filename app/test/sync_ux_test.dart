// Sync setup: opening a notebook that already exists, and the mirror/backup
// copies.
//
// The reported bug these come from: after picking a cloud folder the chip
// still read "not syncing", and clicking it re-offered the same folder
// chooser as if nothing had happened. Both were symptoms of the app not
// actually knowing where the notebook lived.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openote/store/repository.dart';
import 'package:openote/sync/mirrors.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  test('a notebook that already exists on disk can just be opened', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // The second-device flow: the file is already in the shared folder, and
    // the point of syncing through one is that the other machine FINDS it
    // rather than being handed a copy.
    final tmp = Directory.systemTemp.createTempSync('onote_open_a_');
    final shared = Directory.systemTemp.createTempSync('onote_shared_');
    final repo = await Repository.openAt(tmp);
    addTearDown(() {
      repo.dispose();
      for (final d in [tmp, shared]) {
        try {
          d.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    final made = await repo.createNotebook('Lectures');
    // What lands in the shared folder is the `.onotebook` and nothing else —
    // v0.17 Step 4. The container is a WAL SQLite database and stays here.
    final moved = await repo.moveNotebookTo(made.id, shared.path);
    expect(Directory(moved).existsSync(), isTrue);
    expect(
        shared
            .listSync(recursive: true)
            .whereType<File>()
            .map((f) => p.basename(f.path))
            .where((n) => RegExp(r'\.onote(-wal|-shm)?$').hasMatch(n)),
        isEmpty);

    // A second workspace, as a second machine would have.
    final tmp2 = Directory.systemTemp.createTempSync('onote_open_b_');
    final repo2 = await Repository.openAt(tmp2);
    addTearDown(() {
      repo2.dispose();
      try {
        tmp2.deleteSync(recursive: true);
      } catch (_) {}
    });
    // The join path for a folder that holds only logs — the same one a git
    // clone uses. `openExistingNotebook` byte-copies a container and there is
    // deliberately no container to copy.
    final ref = await repo2.adoptLogDirectory(moved, title: 'Lectures');
    expect(ref.title, 'Lectures');
    expect(repo2.notebooks.any((n) => n.id == ref.id), isTrue);

    // THE SAFETY PROPERTY. The `.onote` is a WAL SQLite database rewritten on
    // every save; two machines writing one copy of it through a cloud client
    // is the corruption case ADR-0006 §3 designs against. So the joining
    // device must take its OWN container and share only the append-only logs,
    // where one-writer-per-file makes a conflict structurally impossible.
    expect(ref.file, isNot(moved),
        reason: 'the second device must not open the shared container');
    expect(p.isWithin(tmp2.path, ref.file), isTrue,
        reason: 'its container belongs in its own workspace');
    expect(File(ref.file).existsSync(), isTrue);
    expect(ref.logDir, moved,
        reason: 'the logs, and only the logs, are shared');

    // Joining twice must not fork the registry into two devices for one
    // machine — matched on the shared log dir, not the path.
    final again = await repo2.adoptLogDirectory(moved, title: 'Lectures');
    expect(again.id, ref.id);
    expect(repo2.notebooks.length, 1);
  });

  test('a notebook outside the workspace survives a restart', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // The registry stored a BASENAME and re-joined it against the workspace
    // folder on load, so a notebook moved into a cloud folder resolved to a
    // file that isn't there and silently vanished from the list on the next
    // start. The file was never lost — but the notebook was, as far as the
    // user could tell.
    final tmp = Directory.systemTemp.createTempSync('onote_restart_');
    final shared = Directory.systemTemp.createTempSync('onote_restart_cloud_');
    addTearDown(() {
      for (final d in [tmp, shared]) {
        try {
          d.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    final repo = await Repository.openAt(tmp);
    final made = await repo.createNotebook('Moved');
    final moved = await repo.moveNotebookTo(made.id, shared.path);
    await repo.flushWorkspace();
    repo.dispose();

    final reopened = await Repository.openAt(tmp);
    addTearDown(reopened.dispose);
    expect(reopened.notebooks.length, 1, reason: 'the notebook disappeared');
    // Since v0.17 Step 4 the path that points OUT of the workspace is the log
    // directory rather than the container, and it is the one the registry has
    // to write absolutely. Written as a basename it would re-join against the
    // workspace folder on load, resolve to a directory that is not there, and
    // the notebook would silently stop syncing.
    expect(reopened.notebooks.single.logDir, moved);
    expect(File(reopened.notebooks.single.file).existsSync(), isTrue);
  });

  test('opening a path with nothing there fails loudly', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final tmp = Directory.systemTemp.createTempSync('onote_open_missing_');
    final repo = await Repository.openAt(tmp);
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    expect(
      () => repo.openExistingNotebook('${tmp.path}/nope.onote'),
      throwsA(isA<StateError>()),
    );
  });

  test('purging a notebook reclaims its logs too', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // Purge deleted only the .onote and left the .onotebook behind — logs and
    // every blob they held, stranded somewhere the app would never look
    // again. On a synced notebook that is hundreds of megabytes of cloud
    // quota, permanently.
    final tmp = Directory.systemTemp.createTempSync('onote_purge_');
    final repo = await Repository.openAt(tmp);
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    final made = await repo.createNotebook('Doomed');
    final logs = Directory('${p.withoutExtension(made.file)}.onotebook');
    logs.createSync(recursive: true);
    File('${logs.path}/manifest.json').writeAsStringSync('{}');

    await repo.createNotebook('Keeper'); // never the only notebook
    await repo.trashNotebook(made.id);
    await repo.purgeNotebook(made.id);

    expect(File(made.file).existsSync(), isFalse);
    expect(logs.existsSync(), isFalse, reason: 'the log directory leaked');
  });

  test('purge never deletes logs another notebook still shares', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // A device that joined a shared folder keeps a private container and
    // points logDir at the shared logs, so two entries can legitimately name
    // the same directory. Purging one must not take the other's data.
    final tmp = Directory.systemTemp.createTempSync('onote_purge_shared_');
    final shared = Directory.systemTemp.createTempSync('onote_purge_cloud_');
    final repo = await Repository.openAt(tmp);
    addTearDown(() {
      repo.dispose();
      for (final d in [tmp, shared]) {
        try {
          d.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    final sharedLogs = Directory('${shared.path}/Shared.onotebook')
      ..createSync(recursive: true);
    File('${sharedLogs.path}/manifest.json').writeAsStringSync('{}');

    final a = await repo.createNotebook('A');
    final b = await repo.createNotebook('B');
    a.logDir = sharedLogs.path;
    b.logDir = sharedLogs.path;

    await repo.trashNotebook(a.id);
    await repo.purgeNotebook(a.id);
    expect(sharedLogs.existsSync(), isTrue,
        reason: "purging one device's entry must not delete shared logs");
  });

  test('re-joining a trashed notebook restores it instead of copying',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // The dedupe check looked only at LIVE notebooks, so trash-then-rejoin
    // copied the container again under a fresh id — which is how a workspace
    // ends up holding five ~95MB copies of one notebook.
    final tmp = Directory.systemTemp.createTempSync('onote_rejoin_');
    final shared = Directory.systemTemp.createTempSync('onote_rejoin_cloud_');
    final repo = await Repository.openAt(tmp);
    addTearDown(() {
      repo.dispose();
      for (final d in [tmp, shared]) {
        try {
          d.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    final made = await repo.createNotebook('Shared');
    await repo.createNotebook('Other'); // so trashing is allowed
    final moved = await repo.moveNotebookTo(made.id, shared.path);

    final joined = await repo.adoptLogDirectory(moved, title: 'Shared');
    final countAfterJoin = repo.notebooks.length;
    await repo.trashNotebook(joined.id);
    final again = await repo.adoptLogDirectory(moved, title: 'Shared');

    expect(again.id, joined.id, reason: 'the same notebook, not a new copy');
    expect(repo.notebooks.length, countAfterJoin);
    expect(repo.trashedNotebooks.any((n) => n.id == joined.id), isFalse,
        reason: 'and it came back out of the bin');
  });

  group('mirrors and backups', () {
    late Directory src, dest;

    setUp(() {
      src = Directory.systemTemp.createTempSync('onote_mirror_src_');
      dest = Directory.systemTemp.createTempSync('onote_mirror_dst_');
      // A notebook is a directory of append-only logs plus content-addressed
      // blobs, which is exactly why copying it is correct by construction.
      Directory('${src.path}/ops').createSync();
      File('${src.path}/ops/dev-a.oplog').writeAsStringSync('{"op":"one"}\n');
      Directory('${src.path}/blobs').createSync();
      File('${src.path}/blobs/aa11').writeAsStringSync('bytes');
    });

    tearDown(() {
      for (final d in [src, dest]) {
        try {
          d.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('a mirror copies the logs and the blobs', () async {
      final out = await mirrorNotebook(
          src.path, MirrorTarget(path: dest.path, keepVersions: 0));
      expect(out, isNotNull);
      expect(File('$out/ops/dev-a.oplog').existsSync(), isTrue);
      expect(File('$out/blobs/aa11').readAsStringSync(), 'bytes');
    });

    test('a backup keeps dated snapshots and prunes the oldest', () async {
      final target = MirrorTarget(path: dest.path, keepVersions: 2);
      // Distinct timestamps, passed in rather than slept for.
      for (var i = 0; i < 4; i++) {
        await mirrorNotebook(src.path, target,
            now: DateTime(2026, 8, 3, 12, i));
      }
      final snaps = Directory('${dest.path}/${src.path.split(Platform.pathSeparator).last}')
          .listSync()
          .whereType<Directory>()
          .toList();
      expect(snaps.length, 2, reason: 'keepVersions: 2');
      // Newest kept: the names sort lexicographically, which is what makes
      // pruning a sort-and-drop rather than a date parse.
      final names = snaps.map((d) => d.path.split(Platform.pathSeparator).last).toList()
        ..sort();
      expect(names.last, contains('1203'));
    });

    test('a mirror of a missing source is a no-op, not a crash', () async {
      expect(
        await mirrorNotebook(
            '${src.path}-gone', MirrorTarget(path: dest.path, keepVersions: 0)),
        isNull,
      );
    });

    test('a mirror skips the container but a backup contains it', () async {
      // The container is a SIBLING of the log directory, never inside it, so
      // walking the source alone could never pick it up — which meant a
      // "backup" held no notebook at all, only the logs it would have to be
      // rebuilt from. It has to be passed in explicitly.
      // In a directory this test OWNS, not in the shared temp root.
      // `dest.parent` is systemTemp itself, so the old path was a fixed
      // `<systemTemp>/Notes.onote` — two concurrent `flutter test` runs on one
      // machine would fight over it, and the loser fails on the existsSync
      // below with nothing to suggest why.
      final holder = Directory.systemTemp.createTempSync('onote_mirror_ctr_');
      addTearDown(() {
        try {
          holder.deleteSync(recursive: true);
        } catch (_) {}
      });
      final container = p.join(holder.path, 'Notes.onote');
      File(container).writeAsStringSync('sqlite');

      final out = await mirrorNotebook(
          src.path, MirrorTarget(path: dest.path, keepVersions: 0),
          containerPath: container);
      expect(File('$out/Notes.onote').existsSync(), isFalse,
          reason: 'a mirror skips it: rebuildable, largest, rewritten hourly');

      final backup = await mirrorNotebook(
          src.path, MirrorTarget(path: dest.path, keepVersions: 3),
          containerPath: container, now: DateTime(2026, 8, 3));
      expect(File('$backup/Notes.onote').existsSync(), isTrue,
          reason: 'a snapshot you must rebuild before reading is not a backup');
      expect(File('$backup/ops/dev-a.oplog').existsSync(), isTrue);
    });
  });
}
