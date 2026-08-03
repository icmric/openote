// Sync setup: opening a notebook that already exists, and the mirror/backup
// copies.
//
// The reported bug these come from: after picking a cloud folder the chip
// still read "not syncing", and clicking it re-offered the same folder
// chooser as if nothing had happened. Both were symptoms of the app not
// actually knowing where the notebook lived.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
    final moved = await repo.moveNotebookTo(made.id, shared.path);
    expect(File(moved).existsSync(), isTrue);

    // A second workspace, as a second machine would have.
    final tmp2 = Directory.systemTemp.createTempSync('onote_open_b_');
    final repo2 = await Repository.openAt(tmp2);
    addTearDown(() {
      repo2.dispose();
      try {
        tmp2.deleteSync(recursive: true);
      } catch (_) {}
    });
    final ref = await repo2.openExistingNotebook(moved);
    expect(ref.title, 'Lectures');
    expect(repo2.notebooks.any((n) => n.id == ref.id), isTrue);

    // Opening the same file twice must not fork the registry.
    final again = await repo2.openExistingNotebook(moved);
    expect(again.id, ref.id);
    expect(repo2.notebooks.where((n) => n.file == moved).length, 1);
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

    test('a mirror skips the rebuildable container', () async {
      // The `.onote` is a cache of the logs, it is the largest file, and it is
      // rewritten on every save — copying it every time is pure waste.
      File('${src.path}/Notes.onote').writeAsStringSync('sqlite');
      final out = await mirrorNotebook(
          src.path, MirrorTarget(path: dest.path, keepVersions: 0));
      expect(File('$out/Notes.onote').existsSync(), isFalse);

      // A BACKUP does take it: a snapshot you have to rebuild before you can
      // read it is not the thing you want in an emergency.
      final backup = await mirrorNotebook(
          src.path, MirrorTarget(path: dest.path, keepVersions: 3),
          now: DateTime(2026, 8, 3));
      expect(File('$backup/Notes.onote').existsSync(), isTrue);
    });
  });
}
