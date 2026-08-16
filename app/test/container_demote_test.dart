// v0.17 plan, Step 8 — the rename to `cache.onote`, and the way back.
//
// Steps 1–7 and 8a/8b left the container a normal `.onote` in the workspace
// with a `.onotebook` beside it. This is the step that says out loud what the
// container has already become: a local, rebuildable working copy. It moves to
// `<workspace>/.cache/<notebook-id>/cache.onote`, is stamped `user_version = 2`,
// and loses `page_versions` on the way.
//
// **Three claims are under test, and each of them has already destroyed a real
// notebook somewhere in this plan's history:**
//
//  1. **A notebook must never become unreachable.** `_loadWorkspace` drops any
//     entry whose file is missing and `_saveWorkspace` then rewrites the
//     registry from what survived, so a kill inside a one-write-wide window used
//     to prune a notebook permanently. The migration writes `workspace.json`
//     BEFORE it deletes anything, and `_settleDemotion` settles every leftover
//     by looking at the disk rather than at a marker — which is what the spike
//     that destroyed a 329-page notebook got wrong.
//  2. **The stamp has to be real.** `isOpenoteWorkingCopy` refuses a file both
//     by name and by `user_version`, and until this step nothing ever wrote a 2,
//     so the second half of that test had never fired on anything.
//  3. **`undemote` has to run, not merely exist.** Part 6 of the plan makes the
//     inverse a release blocker for the release that ships the rename.
//
// Two negative controls, as the brief requires: the migration REFUSES when the
// log cannot supply the whole notebook, and an un-migrated notebook opens,
// reads and saves exactly as before.
//
// Every test names the mutation that turns it red, because a cell that cannot
// fail is not a cell (plan §5.1 rule 3).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:openote/core/open_target.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/database.dart';
import 'package:openote/store/free_space.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());
  tearDown(() => FreeSpace.overrideForTest = null);

  /// A workspace with one furnished notebook, opened through [AppState] so that
  /// every node and every page really has ops behind it.
  ///
  /// Going through `Repository` alone would not do: `createNotebook` writes its
  /// seed section and page straight into the container with no op at all, and
  /// `AppState._backfillTree` is what records them. A fixture that skipped this
  /// would be testing the migration's gate 3 against a notebook whose log is a
  /// fiction — and gate 3 is the whole reason this call is allowed to call the
  /// container a cache.
  Future<(Repository, AppState, String, Directory)> fixture(String name) async {
    final tmp = Directory.systemTemp.createTempSync(name);
    final repo = await Repository.openAt(tmp);
    late AppState created;
    addTearDown(() async {
      try {
        await created.settleBackgroundWork();
        await repo.flushWorkspace();
      } catch (_) {
        // A test that deliberately removes a container lands here, and that is
        // the point of it.
      }
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final nb = await repo.createNotebook('Demotable');
    final app = created = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    final pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
    await app.selectPage(pageId);
    FreeSpace.overrideForTest = (_) => 8 * 1024 * 1024 * 1024;

    // Content, and specifically content with a picture in it: gate 4's
    // successor in this call is `AppState.proveBlobBytes`, and a notebook with
    // no blobs would clear the strictest gate by having nothing to check.
    final hash = app.importBlob(nb.id, picture(1), 'image/png');
    app.blocks = [
      Block(
          id: 'b-text',
          type: BlockType.text,
          x: 12,
          y: 34,
          w: 400,
          h: 60,
          content: {'text': 'A paragraph that has to survive all of this.'}),
      Block(
          id: 'b-image',
          type: BlockType.image,
          x: 200,
          y: 220,
          w: 320,
          h: 200,
          content: {'blob': 'sha256:$hash'}),
    ];
    app.markDirty();
    await app.flushSave();
    await app.settleBackgroundWork();
    return (repo, app, nb.id, tmp);
  }

  String fileOf(Repository repo, String nb) =>
      repo.notebooks.firstWhere((n) => n.id == nb).file;

  /// Everything the container holds that a student could notice, read straight
  /// out of SQLite through a SECOND connection so the comparison cannot be
  /// fooled by the repository's own cache.
  Map<String, Object?> snapshot(String file) {
    final db = sqlite3.open(file);
    try {
      return {
        'nodes': [
          for (final r in db.select('SELECT id,kind,parent_id,title,position,'
              'color,level,created_at,updated_at,deleted_at FROM nodes '
              'ORDER BY id'))
            {
              for (final k in const [
                'id', 'kind', 'parent_id', 'title', 'position', 'color',
                'level', 'created_at', 'updated_at', 'deleted_at'
              ])
                k: r[k]
            }
        ],
        'pages': {
          for (final r in db
              .select('SELECT page_id,json FROM page_mirror ORDER BY page_id'))
            r['page_id'] as String: r['json']
        },
        'blobRefs': [
          for (final r in db.select(
              'SELECT page_id,hash FROM blob_refs ORDER BY page_id,hash'))
            '${r['page_id']}/${r['hash']}'
        ],
      };
    } finally {
      db.dispose();
    }
  }

  /// The container's `user_version`, asked of SQLite.
  int userVersionOf(String file) {
    final db = sqlite3.open(file);
    try {
      return db.select('PRAGMA user_version;').first.columnAt(0) as int;
    } finally {
      db.dispose();
    }
  }

  /// Fold the write-ahead log back into the main file.
  ///
  /// **Not decoration.** `PRAGMA user_version` is a field in the 100-byte file
  /// header, and in WAL mode a changed header lives in the `-wal` until
  /// something checkpoints it — so a raw read of a live container answers 0,
  /// which is the same reason `notebookFileProblem` has an
  /// `application_id == 0`-with-a-`-wal` concession. The migration ends with
  /// `checkpointAndClose`, so a working copy at rest is stamped in the file
  /// itself; this is here for the tests that copy one while the app still has
  /// it open.
  void settle(String file) {
    final db = sqlite3.open(file);
    try {
      db.execute('PRAGMA wal_checkpoint(TRUNCATE);');
    } finally {
      db.dispose();
    }
  }

  Map<String, dynamic> registry(Directory tmp) =>
      jsonDecode(File(p.join(tmp.path, 'workspace.json')).readAsStringSync())
          as Map<String, dynamic>;

  int registryFormat(Directory tmp) =>
      ((registry(tmp)['format'] as Map)['major'] as num).toInt();

  Map<String, dynamic> registryEntry(Directory tmp, String nb) =>
      ((registry(tmp)['notebooks'] as List)
              .cast<Map<String, dynamic>>()
              .firstWhere((m) => m['id'] == nb))
          .cast<String, dynamic>();

  group('the rename', () {
    test('the working file moves into the cache, stamped and cut down',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, tmp) = await fixture('onote_step8_demote_');
      final was = fileOf(repo, nb);
      final logs = repo.notebooks.firstWhere((n) => n.id == nb).logDirPath;
      await app.settleBackgroundWork();
      final before = snapshot(was);
      expect(userVersionOf(was), onoteFormatMajor,
          reason: 'a notebook file starts as v1');
      expect(registryFormat(tmp), 1,
          reason: 'nothing is demoted yet, so the guard is off and an older '
              'build can still write this registry');

      // At the repository, so the comparison below is of storage rather than of
      // the editor — see the note on the round-trip test.
      final out = await repo.demoteContainerToCache(nb);
      expect(out.refusal, isNull,
          reason: 'refused: ${out.refusal} // ${out.details}');
      expect(out.done, isTrue);

      final now = fileOf(repo, nb);
      // MUTATION: point `cachePathFor` at the `.onotebook` — the layout
      // ADR-0006 §3 draws and the plan's §1.2 forbids — and this fails, because
      // the notes folder is the one directory a cloud client replicates.
      expect(p.basename(now), workingCopyFileName);
      expect(p.equals(p.dirname(now), p.join(tmp.path, '.cache', nb)), isTrue,
          reason: 'one level down, keyed by the notebook id');
      expect(p.isWithin(logs, now), isFalse,
          reason: 'NEVER inside the notes folder: that folder IS the Drive '
              'folder for a shared notebook');
      expect(File(was).existsSync(), isFalse, reason: 'the original is gone');
      expect(File('$was-wal').existsSync(), isFalse);

      // MUTATION: delete the `PRAGMA user_version` line and this fails — and so
      // does the renamed-copy test below, which is the one that matters.
      expect(userVersionOf(now), onoteWorkingCopyVersion);

      final raw = sqlite3.open(now);
      try {
        expect(
            raw.select("SELECT name FROM sqlite_master WHERE type='table' "
                "AND name='block_authors'"),
            isNotEmpty,
            reason: "8a's replacement is still there");
      } finally {
        raw.dispose();
      }

      // Not one page, block, node or blob reference moved.
      expect(snapshot(now)['nodes'], before['nodes']);
      expect(snapshot(now)['pages'], before['pages']);
      expect(snapshot(now)['blobRefs'], before['blobRefs']);
    });

    test('an OLD notebook loses its page snapshots, and is told how many',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, _) = await fixture('onote_step8_old_versions_');
      final was = fileOf(repo, nb);

      // A notebook made by a build that still had `page_versions`. The schema no
      // longer creates the table, so it has to be put there by hand through a
      // second connection — which is exactly what every notebook on a real disk
      // looks like today.
      repo.closeNotebook(nb);
      final pages = [
        for (final r in sqlite3.open(was).select('SELECT page_id FROM page_mirror'))
          r['page_id'] as String
      ];
      final raw = sqlite3.open(was);
      raw.execute('''
        CREATE TABLE page_versions (
          page_id TEXT NOT NULL, version_at INTEGER NOT NULL,
          snapshot BLOB NOT NULL, label TEXT,
          PRIMARY KEY (page_id, version_at));''');
      for (var i = 0; i < 3; i++) {
        raw.execute(
            'INSERT INTO page_versions(page_id,version_at,snapshot,label) '
            'VALUES(?,?,?,NULL)',
            [pages.first, 1000 + i, Uint8List.fromList(utf8.encode('{"old":$i}'))]);
      }
      raw.dispose();

      final out = await app.demoteContainerToCache(nb);
      expect(out.refusal, isNull, reason: '${out.refusal} // ${out.details}');
      // MUTATION: delete the `DROP TABLE IF EXISTS page_versions` line and this
      // is 3-with-the-table-still-there. Counting BEFORE the drop is what lets
      // the app say how much was removed instead of only that something was.
      expect(out.snapshotsDropped, 3);
      final after = sqlite3.open(fileOf(repo, nb));
      try {
        expect(
            after.select("SELECT name FROM sqlite_master WHERE type='table' "
                "AND name='page_versions'"),
            isEmpty,
            reason: 'the one irreversible half of this migration');
      } finally {
        after.dispose();
      }
    });

    test('the registry records a relative path, a notes folder and format 2',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, tmp) = await fixture('onote_step8_registry_');
      final logs = repo.notebooks.firstWhere((n) => n.id == nb).logDirPath;
      expect((await app.demoteContainerToCache(nb)).done, isTrue);
      await repo.flushWorkspace();

      final e = registryEntry(tmp, nb);
      // MUTATION: put `p.basename` back in `_registryPath` and this reads
      // `cache.onote` — which resolves to the workspace root, where nothing is,
      // so the entry is dropped at the next start and the notebook is gone.
      expect(e['file'], p.join('.cache', nb, workingCopyFileName));
      // MUTATION: stop recording `logDir` and `logDirPath` derives
      // `.cache/<id>/cache.onotebook` — this device's notes written into the one
      // directory the app is allowed to throw away.
      expect(e['logDir'], isNotNull);
      expect(p.equals(e['logDir'] as String, logs), isTrue);

      // MUTATION: hard-code `workspaceFormat` into `_saveWorkspace` again and
      // the un-migrated case above goes to 2, locking an older build out of a
      // registry it could have written perfectly safely.
      expect(registryFormat(tmp), 2,
          reason: 'the guard switches on with the thing it guards');
    });

    test('a working copy is recognised as one — by name AND by the stamp',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, tmp) = await fixture('onote_step8_sniff_');
      final was = fileOf(repo, nb);
      // MUTATION: this is the assertion that made the second half of
      // `isOpenoteWorkingCopy` real. Before the stamp existed it could only ever
      // fire by NAME.
      expect(isOpenoteWorkingCopy(was), isFalse,
          reason: 'an ordinary notebook file is not a working copy');

      expect((await app.demoteContainerToCache(nb)).done, isTrue);
      final now = fileOf(repo, nb);
      expect(isOpenoteWorkingCopy(now), isTrue, reason: 'by name');

      // The renamed copy: a student drags `cache.onote` onto a USB stick and
      // calls it `Physics.onote`. The name test is defeated; the stamp is not.
      // MUTATION: delete the `PRAGMA user_version` line in
      // `demoteContainerToCache` and this fails — after which double-clicking
      // that file adopts a cache as a notebook, whose `blobs` table Step 7 has
      // already emptied.
      final disguised = p.join(tmp.path, 'Physics.onote');
      settle(now);
      File(now).copySync(disguised);
      expect(p.basename(disguised).toLowerCase(), isNot(workingCopyFileName));
      expect(isOpenoteWorkingCopy(disguised), isTrue, reason: 'by user_version');
    });

    test('duplicating a migrated notebook does not mint a second working copy',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, _) = await fixture('onote_step8_dup_');
      expect((await app.demoteContainerToCache(nb)).done, isTrue);

      final copy = await repo.duplicateNotebook(nb, title: 'A duplicate');
      // MUTATION: remove the `PRAGMA user_version = onoteFormatMajor` line from
      // `duplicateNotebook` and this fails: the duplicate is a v2 file that is
      // NOT a cache, so `isOpenoteWorkingCopy` calls a real notebook a working
      // copy and refuses to open it — and a build that predates v0.17 refuses it
      // outright.
      expect(userVersionOf(copy.file), onoteFormatMajor);
      expect(isOpenoteWorkingCopy(copy.file), isFalse);
    });
  });

  group('the negative controls', () {
    test('it REFUSES when the history cannot supply the whole notebook',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, tmp) = await fixture('onote_step8_nc_ghost_');
      final was = fileOf(repo, nb);

      // A node written straight into the container, the way every build before
      // the op log existed wrote them, through a second connection so
      // `_backfillTree` cannot record it. This is the shape of a container
      // restored from a backup newer than its `ops/`.
      repo.closeNotebook(nb);
      final raw = sqlite3.open(was);
      final parent =
          repo.loadNodes(nb).firstWhere((n) => n.kind == NodeKind.section).id;
      raw.execute(
          'INSERT INTO nodes(id,kind,parent_id,title,position,level,'
          'created_at,updated_at) VALUES(?,?,?,?,?,?,?,?)',
          ['ghost', 'page', parent, 'Only in the notebook', 'zz', 1, 1, 1]);
      raw.dispose();
      final before = snapshot(was);

      final out = await app.demoteContainerToCache(nb);
      // MUTATION: delete the `_rebuildDifferences` gate from
      // `demoteContainerToCache` and this passes — after which the app has
      // promised it can rebuild a notebook that holds a page its history has
      // never heard of, and the next rebuild silently drops it.
      expect(out.done, isFalse);
      expect(out.refusal, isNotNull);
      expect(out.refusal, isNot(contains('ghost')),
          reason: 'the sentence a student reads carries no id, no path and no '
              'exception; those live in the Advanced fold');
      expect(out.details, contains('ghost'));
      expect(snapshot(was), before, reason: 'refused BEFORE anything moved');
      expect(fileOf(repo, nb), was);
      expect(repo.cacheDirFor(nb).existsSync(), isFalse,
          reason: 'not even the directory');
      expect(registryFormat(tmp), 1);
    });

    test('a notebook nobody migrated opens, reads and saves exactly as before',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, tmp) = await fixture('onote_step8_nc_plain_');
      final was = fileOf(repo, nb);
      final before = snapshot(was);
      await repo.flushWorkspace();
      await app.settleBackgroundWork();
      repo.dispose();

      // A whole second launch of the app over the same workspace, with nothing
      // migrated. MUTATION: make `_settleDemotion` delete on any mismatch
      // rather than only when the registry's own file is there, and a notebook
      // that has never been migrated still loads — but the crash tests below go
      // red, which is the point of splitting them.
      final again = await Repository.openAt(tmp);
      addTearDown(again.dispose);
      final ref = again.notebooks.firstWhere((n) => n.id == nb);
      expect(p.equals(ref.file, was), isTrue);
      expect(again.isDemoted(ref), isFalse);
      expect(userVersionOf(ref.file), onoteFormatMajor);
      expect(snapshot(ref.file), before);
      expect(registryFormat(tmp), 1,
          reason: 'and an older Openote can still write this registry');

      // It still saves.
      final app2 = AppState(again)
        ..notebookId = nb
        ..spellCheckEnabled = false;
      addTearDown(app2.cancelPendingSave);
      app2.reloadNodes();
      final pid = app2.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
      await app2.selectPage(pid);
      app2.blocks = [
        ...app2.blocks,
        Block(
            id: 'b-after',
            type: BlockType.text,
            x: 0,
            y: 500,
            content: {'text': 'written by the next launch'})
      ];
      app2.markDirty();
      await app2.flushSave();
      await app2.settleBackgroundWork();
      expect(snapshot(ref.file)['pages'].toString(),
          contains('written by the next launch'));
    });

    test('it refuses when this build may not write the list of notebooks',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, tmp) = await fixture('onote_step8_nc_ro_');
      final was = fileOf(repo, nb);
      await repo.flushWorkspace();
      await app.settleBackgroundWork();
      repo.dispose();

      // A registry from a build newer than this one. `_loadWorkspace` loads it
      // and never writes it back.
      final f = File(p.join(tmp.path, 'workspace.json'));
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      j['format'] = {'major': 99, 'minor': 0};
      f.writeAsStringSync(jsonEncode(j));

      final again = await Repository.openAt(tmp);
      addTearDown(again.dispose);
      expect(again.registryReadOnly, isNotNull);
      final app2 = AppState(again)
        ..notebookId = nb
        ..spellCheckEnabled = false;
      addTearDown(app2.cancelPendingSave);

      final out = await again.demoteContainerToCache(nb);
      // MUTATION: delete the `registryReadOnly` gate and this passes — the file
      // moves on disk, `_saveWorkspace` silently declines to record it, and the
      // next start looks for the container at the path it used to be. The
      // notebook is gone, and nothing said a word.
      expect(out.done, isFalse);
      expect(out.refusal, isNotNull);
      expect(File(was).existsSync(), isTrue);
      expect(again.cacheDirFor(nb).existsSync(), isFalse);
    });

    test('it refuses when there is not enough room, before touching anything',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, _) = await fixture('onote_step8_full_');
      final was = fileOf(repo, nb);
      final before = snapshot(was);
      final size = File(was).lengthSync() +
          (File('$was-wal').existsSync() ? File('$was-wal').lengthSync() : 0);

      // One byte short of 2.0 × (container + write-ahead log), which is the bar
      // Step 7 measured: `VACUUM` peaked at 1.98× on the owner's 97,542,144-byte
      // container.
      FreeSpace.overrideForTest = (_) => size * 2 - 1;
      final out = await app.demoteContainerToCache(nb);
      // MUTATION: drop the `free < need` branch and this passes — on a real
      // full disk the copy is torn, and a torn copy of a SQLite database still
      // passes `PRAGMA integrity_check`.
      expect(out.done, isFalse);
      expect(out.refusal, contains('not enough free space'));
      expect(out.details, contains('2.0 ×'));
      expect(snapshot(was), before);
      expect(repo.cacheDirFor(nb).existsSync(), isFalse);

      // Exactly on the bar, it goes.
      FreeSpace.overrideForTest = (_) => size * 2;
      expect((await app.demoteContainerToCache(nb)).done, isTrue);
    });
  });

  group('killed part-way through', () {
    // The three states the disk can be in when the process dies, plus the one
    // that must never end in a pruned registry entry. Each is CONSTRUCTED
    // rather than simulated with a marker, because the disk is what
    // `_settleDemotion` reads and the plan's own disaster was a recovery that
    // believed a marker instead.

    test('killed while copying: the half-written copy goes, the notebook stays',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, tmp) = await fixture('onote_step8_kill_copy_');
      final was = fileOf(repo, nb);
      final before = snapshot(was);
      await repo.flushWorkspace();
      await app.settleBackgroundWork();
      repo.dispose();

      // Stage 1: the marker is down, the destination directory exists, and the
      // copy stopped part-way. The registry still names the original.
      final half = File(repo.cachePathFor(nb));
      half.parent.createSync(recursive: true);
      half.writeAsBytesSync(
          File(was).readAsBytesSync().sublist(0, 4096), flush: true);

      final again = await Repository.openAt(tmp);
      addTearDown(again.dispose);
      final ref = again.notebooks.firstWhere((n) => n.id == nb);
      // MUTATION: remove the `_settleDemotion` call from `_loadWorkspace` and
      // the half-written copy survives for ever — and the next migration
      // attempt would copy onto it, which is the one thing this plan never
      // does.
      expect(again.cacheDirFor(nb).existsSync(), isFalse);
      expect(p.equals(ref.file, was), isTrue);
      expect(snapshot(ref.file), before, reason: 'nothing was lost');
    });

    test('killed after the copy, before the registry: the notebook stays put',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, tmp) = await fixture('onote_step8_kill_precommit_');
      final was = fileOf(repo, nb);
      final before = snapshot(was);
      await repo.flushWorkspace();
      await app.settleBackgroundWork();
      repo.dispose();

      // Stage 2: a COMPLETE, valid working copy in the cache, and a registry
      // that never heard about it. Both copies are good; the registry decides.
      final dest = File(repo.cachePathFor(nb));
      dest.parent.createSync(recursive: true);
      File(was).copySync(dest.path);
      final stamp = sqlite3.open(dest.path);
      stamp.execute('PRAGMA user_version = $onoteWorkingCopyVersion;');
      stamp.dispose();

      final again = await Repository.openAt(tmp);
      addTearDown(again.dispose);
      final ref = again.notebooks.firstWhere((n) => n.id == nb);
      expect(p.equals(ref.file, was), isTrue,
          reason: 'the registry never committed, so neither did the move');
      expect(again.cacheDirFor(nb).existsSync(), isFalse);
      expect(snapshot(ref.file), before);
      expect(registryFormat(tmp), 1);
    });

    test('killed after the registry, before the delete: the cache wins',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, tmp) = await fixture('onote_step8_kill_postcommit_');
      final was = fileOf(repo, nb);
      final before = snapshot(was);
      expect((await app.demoteContainerToCache(nb)).done, isTrue);
      final now = fileOf(repo, nb);
      await repo.flushWorkspace();
      await app.settleBackgroundWork();
      repo.dispose();

      // Stage 3: the registry committed and the old container was NOT removed —
      // an antivirus holding the handle, or a kill one line earlier.
      File(now).copySync(was);

      final again = await Repository.openAt(tmp);
      addTearDown(again.dispose);
      final ref = again.notebooks.firstWhere((n) => n.id == nb);
      // MUTATION: make `_settleDemotion` prefer the older path when both exist
      // and this fails; the app would go back to a container that is missing
      // every change made since the migration.
      expect(again.isDemoted(ref), isTrue);
      expect(p.equals(ref.file, now), isTrue);
      expect(snapshot(ref.file)['pages'], before['pages']);
      expect(File(was).existsSync(), isTrue,
          reason: 'the leftover is left alone — deleting a container on LOAD is '
              'not a thing this app gets to do; the leftovers scan reports it');
    });

    test('the notebook file is gone and only the working copy is left: adopted',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, tmp) = await fixture('onote_step8_kill_adopt_');
      expect((await app.demoteContainerToCache(nb)).done, isTrue);
      final cache = fileOf(repo, nb);
      final before = snapshot(cache);
      await repo.flushWorkspace();
      await app.settleBackgroundWork();
      repo.dispose();

      // The state a torn `.bak` recovery can leave: a registry that names the
      // container's OLD path — which is not there any more — while the working
      // copy is sitting in the cache. Without the adoption branch,
      // `_loadWorkspace`'s `existsSync` filter drops the entry and
      // `_saveWorkspace` writes the registry back without it. Permanently.
      final f = File(p.join(tmp.path, 'workspace.json'));
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      for (final e in (j['notebooks'] as List).cast<Map<String, dynamic>>()) {
        if (e['id'] == nb) e['file'] = 'Demotable.onote';
      }
      f.writeAsStringSync(jsonEncode(j));

      final again = await Repository.openAt(tmp);
      addTearDown(again.dispose);
      // MUTATION: delete the adoption branch from `_settleDemotion` and this
      // notebook is not in the list at all — which is the harm `workspaceFormat`
      // exists to prevent, reached by another road.
      expect(again.notebooks.where((n) => n.id == nb), hasLength(1));
      final ref = again.notebooks.firstWhere((n) => n.id == nb);
      expect(p.equals(ref.file, cache), isTrue);
      expect(snapshot(ref.file), before);
    });
  });

  group('undemote — the way back', () {
    // **Straight at the repository, both ways.** `AppState` reloads the open
    // notebook after each move and its editor re-lays a page out in memory as
    // it loads — a +58 px shift on every block, saved by the next flush — which
    // is ordinary app behaviour (`moveContainerOutOfSyncFolder` does the same)
    // and has nothing to do with storage. Comparing through it would be
    // measuring the editor. The AppState wrappers and their gates are exercised
    // by every other test in this file.
    test('it round-trips: the notebook comes back byte for byte', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, tmp) = await fixture('onote_step8_undemote_');
      final was = fileOf(repo, nb);
      await app.settleBackgroundWork();
      final before = snapshot(was);
      final logs = repo.notebooks.firstWhere((n) => n.id == nb).logDirPath;

      expect((await repo.demoteContainerToCache(nb)).done, isTrue);
      await repo.flushWorkspace();
      expect(registryFormat(tmp), 2);

      final back = await repo.undemoteContainerFromCache(nb);
      expect(back.refusal, isNull,
          reason: 'refused: ${back.refusal} // ${back.details}');
      expect(back.done, isTrue);

      final now = fileOf(repo, nb);
      expect(p.extension(now), '.onote');
      expect(p.equals(p.dirname(now), tmp.path), isTrue,
          reason: 'back in the workspace, where an older Openote looks');
      expect(p.equals(now, was), isTrue,
          reason: 'and under its own name again, because the demotion freed it');
      // MUTATION: delete the `PRAGMA user_version = onoteFormatMajor` line and
      // this fails — a build that predates v0.17 would refuse the file it has
      // just been handed back.
      expect(userVersionOf(now), onoteFormatMajor);
      expect(isOpenoteWorkingCopy(now), isFalse);
      expect(repo.cacheDirFor(nb).existsSync(), isFalse);

      // Every node, every page, every blob reference.
      expect(snapshot(now)['nodes'], before['nodes']);
      expect(snapshot(now)['pages'], before['pages']);
      expect(snapshot(now)['blobRefs'], before['blobRefs']);
      // The notes folder never moved and is still named.
      expect(p.equals(repo.notebooks.firstWhere((n) => n.id == nb).logDirPath,
              logs),
          isTrue);

      // MUTATION: hard-code `workspaceFormat` in `_saveWorkspace` and this
      // fails — the whole point of `undemote` is handing the workspace back to
      // an older build, and a registry stamped 2 is one that build will not
      // write.
      await repo.flushWorkspace();
      expect(registryFormat(tmp), 1);
    });

    test('the pictures go back into the notebook file', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, _) = await fixture('onote_step8_undemote_blobs_');
      // Step 7 first: this is the shape a user who took the whole plan is in,
      // and it is the only shape where `refillContainerBlobs` has work to do.
      final tidy = await app.reclaimContainerBlobs(nb);
      expect(tidy.refusal, isNull, reason: '${tidy.refusal} // ${tidy.details}');
      expect((await app.demoteContainerToCache(nb)).done, isTrue);

      final back = await app.undemoteContainerFromCache(nb);
      expect(back.done, isTrue);
      // MUTATION: drop the `refillContainerBlobs` call from
      // `undemoteContainerFromCache` and this is 0 — an older build follows
      // `blob_refs` into `blobs` to draw a picture, finds no row, and the page
      // comes up with a hole in it.
      expect(back.blobsRestored, greaterThan(0));
      final raw = sqlite3.open(fileOf(repo, nb));
      try {
        final rows = raw.select('SELECT COUNT(*) AS c FROM blobs').first['c'];
        expect(rows, back.blobsRestored);
      } finally {
        raw.dispose();
      }
    });

    test('undemoting a notebook that was never migrated changes nothing',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, _) = await fixture('onote_step8_undemote_noop_');
      final was = fileOf(repo, nb);
      final before = snapshot(was);
      final out = await app.undemoteContainerFromCache(nb);
      expect(out.done, isFalse);
      expect(out.refusal, isNotNull);
      expect(fileOf(repo, nb), was);
      expect(snapshot(was), before);
    });
  });

  group('nothing is left pointing at a table that is gone', () {
    // Matrix row B7's source assertion. The plan names six prune sites for
    // `page_versions` and gets two of them wrong — the "delete-notebook clear"
    // at `repository.dart:1253` does not exist, and `media_reclaim_test`'s
    // reclaim story is a seventh it never mentions — so the check that is worth
    // having is not a list of line numbers but the absence of the name itself.
    test('no code in lib/ reads or writes page_versions', () {
      final hits = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (!line.contains('page_versions')) continue;
          // Prose is allowed and is most of the value in this codebase: every
          // one of these lines has to explain what used to be there. Only SQL
          // counts.
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('//') ||
              trimmed.startsWith('///') ||
              trimmed.startsWith('--') ||
              trimmed.startsWith('*')) {
            continue;
          }
          hits.add('${f.path}:${i + 1}: $line');
        }
      }
      // MUTATION: put `maybeSnapshotVersion`'s INSERT back, or `purgeNode`'s
      // DELETE, or `everyStoredPageText`'s second SELECT, and this fails naming
      // the file and line. The table is not created any more, so a read left
      // behind would not merely be dead — it would throw on every notebook made
      // from here on.
      //
      // The migration is the one place the name may still appear in code, and it
      // appears there to DESTROY the table. Matched on what the line DOES rather
      // than on where it is, so the assertion survives an edit above it.
      final survivors = [
        for (final h in hits)
          if (!h.contains('DROP TABLE IF EXISTS page_versions') &&
              !h.contains("_count(fresh, 'page_versions')"))
            h
      ];
      expect(survivors, isEmpty,
          reason: 'a prune site or a read of the dropped table survived');
      expect(hits, hasLength(2),
          reason: 'and the migration still both counts and drops it');
    });

    test('a fresh notebook has no page_versions table at all', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, _, nb, _) = await fixture('onote_step8_no_table_');
      final raw = sqlite3.open(fileOf(repo, nb));
      try {
        expect(
            raw.select("SELECT name FROM sqlite_master WHERE type='table' "
                "AND name='page_versions'"),
            isEmpty);
      } finally {
        raw.dispose();
      }
    });
  });
}

Uint8List picture(int i, {int size = 2048}) => Uint8List.fromList(
    [for (var b = 0; b < size; b++) (b * 37 + i * 101) & 0xff]);
