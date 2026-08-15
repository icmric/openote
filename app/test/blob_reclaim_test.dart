// Step 7 of the v0.17 storage plan: empty the container's `blobs` table.
//
// **This is the first step in the plan that destroys bytes.** Everything before
// it can be undone by reverting a commit; this one deletes the container's copy
// of every picture, drawing and attachment and leaves exactly one copy, in
// `<notebook>.onotebook/blobs/`. Measured prize on the owner's real notebooks:
// the Drive notebook 63,193,548 → 32,578,572 B (48.4%), Honours-4 11.1%.
//
// So this file is mostly refusals, and that is the design rather than an
// accident. A spike ran the migration without them, printed `MIGRATION
// COMPLETE`, left a container whose `PRAGMA integrity_check` said `ok` and a
// page-level comparison that said `same=329 differing=0` — while 278 blob
// hashes had no bytes anywhere on disk and 193 image blocks across 40 pages
// were permanently broken. Page JSON names a picture by hash, so a page whose
// bytes are gone is byte-identical to one whose bytes are fine. Only re-hashing
// the files can tell them apart, and only before the delete.
//
// The five gates, and the test that shows each one refusing:
//
//   1  the log's own blobs are proved      — `a picture the folder cannot
//      (`SyncRecorder.proveBlobs`, which     supply stops it` /
//      repairs from the container first,     `a picture with the wrong bytes
//      hence "before the delete")            stops it`
//   2  every hash the CONTAINER knows      — `a hash the log has never heard
//      has a byte-identical file             of stops it`
//   3  nothing was served from the         — `a picture already read out of
//      container this session                the notes file stops it`
//   4  free space ≥ 2.0× the container     — `not enough room stops it` /
//                                            `not being able to measure stops
//                                            it`
//   5  no reclaim is already running,      — `a marker stops it` /
//      the file checkpoints with nothing     `a second connection holding the
//      else holding it, and Step 6's         file stops it` / `an old foreign
//      foreign key really is gone            key stops it`
//
// And the inverse, `refillContainerBlobs`, is exercised in the same file as a
// real round trip — reclaim, refill, compare bytes — because a rollback that
// has never been executed is a paragraph, not a rollback.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/free_space.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/sync/op_log.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());
  tearDown(() => FreeSpace.overrideForTest = null);

  /// A workspace with one notebook, one page, and plenty of imaginary disk.
  ///
  /// The free-space probe is stubbed by default so that every OTHER test is
  /// measuring the gate it is about, not the state of the machine the suite
  /// happens to run on. The two tests that are about the probe set their own.
  Future<(Repository, AppState, String, String, Directory)> fixture(
      String name) async {
    final tmp = Directory.systemTemp.createTempSync(name);
    final repo = await Repository.openAt(tmp);
    late AppState created;
    addTearDown(() async {
      await created.settleBackgroundWork();
      await repo.flushWorkspace();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final nb = await repo.createNotebook('Pictures');
    final app = created = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    final pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
    app.pageId = pageId;
    FreeSpace.overrideForTest = (_) => 8 * 1024 * 1024 * 1024;
    return (repo, app, nb.id, pageId, tmp);
  }

  OpLogStore logOf(Repository repo, String nb) {
    final ref = repo.notebooks.firstWhere((n) => n.id == nb);
    return OpLogStore.forNotebook(ref.file, logDir: ref.logDir);
  }

  Uint8List picture(int i, {int size = 4096}) => Uint8List.fromList(
      [for (var b = 0; b < size; b++) (b * 37 + i * 101) & 0xff]);

  Block imageBlock(String id, String hash) => Block(
      id: id,
      type: BlockType.image,
      x: 10,
      y: 20,
      w: 320,
      h: 200,
      content: {'blob': 'sha256:$hash'});

  int blobRows(Repository repo, String nb) => repo.blobIndex(nb).length;

  /// The state every notebook on disk today is in: bytes in the container's
  /// `blobs` table, pages declaring them, and `blobs/` filled in afterwards by
  /// Step 5's backfill. Returns the hashes in page order.
  ///
  /// Built this way and not with `importBlob` because after Step 6 `putBlob`
  /// writes to `blobs/` alone — there would be nothing in the table to reclaim,
  /// and every gate below would pass vacuously.
  Future<List<String>> legacyNotebook(Repository repo, AppState app, String nb,
      String pageId, int count) async {
    final hashes = [
      for (var i = 0; i < count; i++)
        repo.putContainerBlobForTest(nb, picture(i), 'image/png')
    ];
    repo.writePage(
        nb,
        pageId,
        [for (var i = 0; i < count; i++) imageBlock('i$i', hashes[i])],
        PageProps());
    await app.syncBackfillBlobs(nb);
    return hashes;
  }

  group('the reclaim, when everything is in order', () {
    test('empties the table, shrinks the file, and no picture goes blank',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, _) = await fixture('onote_step7_ok_');
      final hashes = await legacyNotebook(repo, app, nb, pageId, 12);
      final path = repo.notebooks.firstWhere((n) => n.id == nb).file;
      // Container **plus** write-ahead log, and compacted first, so the two
      // numbers are like for like. A WAL-mode container is 4,096 bytes with
      // everything still in its `-wal`, and comparing the bare `.onote` before
      // and after a checkpoint reports a 22× GROWTH for a step that shrank the
      // notebook.
      int total() => [path, '$path-wal', '$path-shm']
          .map((f) => File(f).existsSync() ? File(f).lengthSync() : 0)
          .reduce((a, b) => a + b);
      await app.reclaimFreeSpace(nb);
      final before = total();

      expect(blobRows(repo, nb), 12,
          reason: 'the fixture has to actually have something to reclaim');

      final out = await app.reclaimContainerBlobs(nb);
      expect(out.refusal, isNull, reason: 'refused: ${out.refusal}');
      expect(out.done, isTrue);
      expect(out.rowsRemoved, 12);
      expect(out.checked, 12,
          reason: 'every blob was re-hashed, not counted — `hasBlob` passes '
              'against a file whose bytes were swapped for the same number of '
              'different ones');
      expect(blobRows(repo, nb), 0);
      expect(total(), lessThan(before),
          reason: 'the VACUUM really ran; a delete alone leaves the file at '
              'its high-water mark and the user sees no space come back');
      expect(out.freed, greaterThan(0));
      expect(out.afterBytes, lessThan(out.beforeBytes));

      // The point of the whole exercise: the pictures still read.
      // MUTATION: delete the `blobs/` write from `SyncRecorder.blob` and the
      // fixture's backfill copies nothing, so this is where it shows.
      for (var i = 0; i < hashes.length; i++) {
        expect(app.blob(hashes[i]), picture(i),
            reason: 'picture $i went blank when its container copy went');
      }
      expect(repo.blobsWithNoBytes(nb), isEmpty);
      expect(repo.reclaimInProgress, isFalse,
          reason: 'the marker is cleared on the way out, or the leftovers scan '
              'stays silent for ever');
    });

    // Matrix cell C6, and the half of the plan's item 4 that survives Step 6.
    test('leaves the garbage-collection root set byte-identical', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, _) = await fixture('onote_step7_refs_');
      final hashes = await legacyNotebook(repo, app, nb, pageId, 6);
      final refsBefore = repo.blobRefsForTest(nb, pageId)..sort();

      expect((await app.reclaimContainerBlobs(nb)).done, isTrue);

      // The plan proposed repairing the `blob_refs.hash REFERENCES blobs(hash)`
      // constraint with `ON DELETE CASCADE`. That would empty `blob_refs` —
      // ADR-0007's reachability root set — and the next housekeeping run would
      // then classify every file in `blobs/` as unreferenced and delete the
      // lot. MUTATION: add `db.execute('DELETE FROM blob_refs;')` beside the
      // delete and this fails, as does the round-trip test below.
      expect(repo.blobRefsForTest(nb, pageId)..sort(), refsBefore);
      expect(refsBefore.toSet(), hashes.toSet());
    });

    test('a hole the container can still repair is repaired, then reclaimed',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, _) = await fixture('onote_step7_repair_');
      final hashes = await legacyNotebook(repo, app, nb, pageId, 4);
      final store = logOf(repo, nb);

      // Wrong bytes in `blobs/`, with the container still holding the truth.
      // This is the ONLY window in which that is repairable, and it is why the
      // proof has to run before the delete rather than after it.
      store.discardBlob(hashes[1]);
      store.writeBlob(hashes[1], Uint8List.fromList([1, 2, 3, 4]));

      final out = await app.reclaimContainerBlobs(nb);
      expect(out.done, isTrue, reason: 'refused: ${out.refusal}');
      expect(store.readBlob(hashes[1]), picture(1),
          reason: 'the damaged file was rewritten from the container BEFORE '
              'the container was emptied — afterwards there is nowhere left '
              'to rewrite it from');
    });
  });

  group('the round trip — reclaim, then put it back', () {
    test('refillContainerBlobs restores every reachable blob byte for byte',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, _) = await fixture('onote_step7_refill_');
      final hashes = await legacyNotebook(repo, app, nb, pageId, 8);

      // One row nothing points at — the shape §1.6 measured at 18 blobs on
      // Honours-2, 3 on Honours-4, 2 on My Notebook. It is deliberately NOT
      // restored, and the assertion below pins that down so the asymmetry is a
      // decision rather than a surprise.
      final orphan = repo.putContainerBlobForTest(nb, picture(99), 'image/png');
      await app.syncBackfillBlobs(nb);

      final wanted = {
        for (final h in [...hashes]) h: repo.containerBlob(nb, h)!
      };
      expect(wanted.length, 8);

      expect((await app.reclaimContainerBlobs(nb)).done, isTrue);
      expect(blobRows(repo, nb), 0);

      final back = await app.refillContainerBlobs(nb);
      expect(back.ok, isTrue, reason: 'could not restore ${back.missing}');
      expect(back.restored, 8);

      // MUTATION: drop the `sha256Hex(bytes) != hash` check in
      // `refillContainerBlobs` and this still passes — so the negative control
      // for it is `a damaged file is never laundered back in`, below.
      for (final e in wanted.entries) {
        expect(repo.containerBlob(nb, e.key), e.value,
            reason: 'blob ${e.key} did not come back with its own bytes');
      }
      expect(repo.containerBlob(nb, orphan), isNull,
          reason: 'a row no page reaches is not restored, deliberately: '
              "nothing can read it, so putting it back would be re-inflating "
              'the file with garbage');

      // And the notebook is a working v1 container again: reclaim can run a
      // second time on the restored rows.
      expect((await app.reclaimContainerBlobs(nb)).done, isTrue);
      expect(blobRows(repo, nb), 0);
    });

    test('a damaged file is never laundered back into the container', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, _) = await fixture('onote_step7_refill_bad_');
      final hashes = await legacyNotebook(repo, app, nb, pageId, 3);
      expect((await app.reclaimContainerBlobs(nb)).done, isTrue);

      // Damage one file AFTER the container copy is gone — the state a bad
      // disk or a half-finished cloud download leaves, and the state in which
      // there is nothing left to repair from.
      final store = logOf(repo, nb);
      store.discardBlob(hashes[0]);
      store.writeBlob(hashes[0], Uint8List.fromList(List.filled(4096, 7)));

      // MUTATION: remove the hash check in `refillContainerBlobs` and this
      // reports ok — the container is handed 4 KB of sevens under the name of
      // a picture, and from then on it is the authoritative copy.
      final back = await app.refillContainerBlobs(nb);
      expect(back.ok, isFalse);
      expect(back.missing, contains(hashes[0]));
      expect(back.restored, 2);
      expect(repo.containerBlob(nb, hashes[0]), isNull);
    });
  });

  group('negative control 1 — blobs/ is incomplete', () {
    test('a picture the folder cannot supply stops it', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, _) = await fixture('onote_step7_nc1_');
      final hashes = await legacyNotebook(repo, app, nb, pageId, 5);

      // A blob written AFTER Step 6 exists in exactly one place. Delete its
      // file and there is no second copy to repair from — which is precisely
      // the notebook state the plan says Step 7 must never proceed through.
      final only = app.importBlob(nb, picture(50), 'image/png');
      repo.writePage(
          nb,
          pageId,
          [
            for (var i = 0; i < hashes.length; i++) imageBlock('i$i', hashes[i]),
            imageBlock('new', only),
          ],
          PageProps());
      await app.settleBackgroundWork();
      logOf(repo, nb).discardBlob(only);

      final rows = blobRows(repo, nb);
      final out = await app.reclaimContainerBlobs(nb);

      // MUTATION: change `if (!proof.ok)` to `if (false)` in
      // `AppState.reclaimContainerBlobs` and this passes silently — which is
      // the spike's `MIGRATION COMPLETE` over 193 destroyed image blocks.
      expect(out.done, isFalse);
      expect(out.refusal, isNotNull);
      expect(blobRows(repo, nb), rows,
          reason: 'not one row may go when the answer is no');
      expect(out.refusal, isNot(contains('sha256')),
          reason: 'the sentence a student reads carries no hash, no path and '
              'no exception; those live in the Advanced fold');
      expect(out.details, contains(only));
    });

    // The mirror image of the test below, and the one that shows gate 1 doing
    // something gate 2 cannot: a hash the LOG names that the container has
    // never heard of. It is in neither `blobs` nor `blob_refs`, so the
    // container-side sweep is blind to it, and only `SyncRecorder.proveBlobs`
    // — which walks the log's own blob set — can see the hole.
    //
    // Not a contrived state: `importBlob` records the `blob.put` before
    // anything writes the page, so every paste, every import and every crash
    // between the two leaves exactly this.
    test('a picture only the log knows about stops it', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, _) = await fixture('onote_step7_nc1c_');
      await legacyNotebook(repo, app, nb, pageId, 3);

      final unreferenced = app.importBlob(nb, picture(70), 'image/png');
      await app.settleBackgroundWork();
      expect(repo.blobRefsForTest(nb, pageId), isNot(contains(unreferenced)));
      logOf(repo, nb).discardBlob(unreferenced);

      final out = await app.reclaimContainerBlobs(nb);
      // MUTATION: change `if (!proof.ok)` in `AppState.reclaimContainerBlobs`
      // to something that never fires and this passes — the container-side
      // gates below never look at this hash.
      expect(out.done, isFalse);
      expect(out.details, contains(unreferenced));
      expect(blobRows(repo, nb), 3);
    });

    test('a hash the log has never heard of stops it', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, _) = await fixture('onote_step7_nc1b_');
      await legacyNotebook(repo, app, nb, pageId, 3);

      // Container row + page reference, and NO backfill: the hash is in
      // `blobs` and in `blob_refs`, but never in the log's blob set, so
      // `proveBlobs` has literally nothing to say about it. Gate 1 passes and
      // gate 2 is the only thing between this notebook and a deleted picture.
      final unlogged =
          repo.putContainerBlobForTest(nb, picture(77), 'image/png');
      repo.writePage(nb, pageId, [imageBlock('u', unlogged)], PageProps());
      await app.settleBackgroundWork();
      expect(logOf(repo, nb).hasBlob(unlogged), isFalse);

      final rows = blobRows(repo, nb);
      final out = await app.reclaimContainerBlobs(nb);

      // MUTATION: build the gate's set from `SELECT hash FROM blobs` only, or
      // skip the `absent` check, and this passes — deleting the only copy of a
      // picture the page still shows.
      expect(out.done, isFalse);
      expect(out.details, contains(unlogged));
      expect(blobRows(repo, nb), rows);
    });
  });

  group('negative control 2 — a blob is present with the wrong bytes', () {
    test('a picture with the wrong bytes stops it', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, _) = await fixture('onote_step7_nc2_');
      final hashes = await legacyNotebook(repo, app, nb, pageId, 4);

      // Post-Step-6 blob again, so the repair has no source: `writeBlob`
      // refuses to overwrite, so the file has to be discarded first — which is
      // exactly the sequence `proveBlobs`' own repair uses.
      final only = app.importBlob(nb, picture(60), 'image/png');
      repo.writePage(
          nb,
          pageId,
          [
            for (var i = 0; i < hashes.length; i++) imageBlock('i$i', hashes[i]),
            imageBlock('new', only),
          ],
          PageProps());
      await app.settleBackgroundWork();
      final store = logOf(repo, nb);
      store.discardBlob(only);
      store.writeBlob(only, picture(61));

      expect(store.hasBlob(only), isTrue,
          reason: 'the file is THERE — this is the case a file count, a length '
              'check and `existsSync` all report as healthy');

      final rows = blobRows(repo, nb);
      final out = await app.reclaimContainerBlobs(nb);
      expect(out.done, isFalse);
      expect(blobRows(repo, nb), rows);
      expect(out.details, contains(only));
    });

    test('wrong bytes the log never named stop it too', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, _) = await fixture('onote_step7_nc2b_');
      await legacyNotebook(repo, app, nb, pageId, 3);

      final unlogged =
          repo.putContainerBlobForTest(nb, picture(88), 'image/png');
      repo.writePage(nb, pageId, [imageBlock('u', unlogged)], PageProps());
      // A file under the right NAME holding the wrong bytes. Only re-hashing
      // can see this; the gate re-hashes.
      logOf(repo, nb).writeBlob(unlogged, picture(89));
      await app.settleBackgroundWork();

      final out = await app.reclaimContainerBlobs(nb);
      // MUTATION: replace the hash comparison in `reclaimContainerBlobs` with
      // `store.hasBlob(...)` and this passes.
      expect(out.done, isFalse);
      expect(out.details, contains(unlogged));
    });
  });

  group('negative control 3 — something is still served from the container',
      () {
    test('a picture already read out of the notes file stops it', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, _) = await fixture('onote_step7_nc3_');
      await legacyNotebook(repo, app, nb, pageId, 3);

      // The sequence a real upgraded notebook goes through: the page paints
      // before the backfill has reached that blob, so the read falls back to
      // the container and Step 6 registers it. The backfill then writes the
      // file — via `containerBlob`, which does not clear the register, because
      // only a real read through `getBlob` proves the file works.
      final late0 = repo.putContainerBlobForTest(nb, picture(31), 'image/png');
      repo.writePage(nb, pageId, [imageBlock('late', late0)], PageProps());
      expect(app.blob(late0), picture(31));
      expect(repo.blobsServedFromContainer(nb), contains(late0));
      await app.syncBackfillBlobs(nb);
      expect(logOf(repo, nb).hasBlob(late0), isTrue,
          reason: 'the file is there, so gates 1 and 2 are satisfied and this '
              'test is about gate 3 alone');

      final rows = blobRows(repo, nb);
      final out = await app.reclaimContainerBlobs(nb);

      // MUTATION: delete the `served.isNotEmpty` check and this passes — and
      // nothing else in the suite notices, because the bytes happen to exist
      // in both places by then.
      expect(out.done, isFalse);
      expect(blobRows(repo, nb), rows);
      expect(out.details, contains(late0));

      // And the gate is not a life sentence. One read that comes out of
      // `blobs/` clears the register, and the reclaim proceeds — without this,
      // a notebook that had one early fallback could never be reclaimed until
      // the app was restarted.
      expect(app.blob(late0), picture(31));
      expect(repo.blobsServedFromContainer(nb), isEmpty);
      expect((await app.reclaimContainerBlobs(nb)).done, isTrue);
    });
  });

  group('the 2.0× free-space precheck', () {
    test('not enough room stops it, before anything is touched', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, _) = await fixture('onote_step7_space_');
      await legacyNotebook(repo, app, nb, pageId, 6);
      final file = File(repo.notebooks.firstWhere((n) => n.id == nb).file);
      final before = file.lengthSync();

      // Just under the bar. VACUUM is not a shrink in place — it writes a
      // second copy of the database and swaps it — and the measured peak on
      // the owner's 97,542,144-byte container was 192,787,184 B, 1.98×.
      FreeSpace.overrideForTest = (_) => (before * 2) - 1;

      final rows = blobRows(repo, nb);
      final out = await app.reclaimContainerBlobs(nb);

      // MUTATION: drop the `free < need` branch and this passes on a full disk.
      expect(out.done, isFalse);
      expect(out.refusal, contains('not enough free space'));
      expect(blobRows(repo, nb), rows, reason: 'refused BEFORE the delete');
      expect(file.lengthSync(), before);
      expect(repo.reclaimInProgress, isFalse,
          reason: 'the marker is only written once the answer is yes; a '
              'refusal must not leave the leftovers scan disabled');
    });

    test('not being able to measure stops it', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, _) = await fixture('onote_step7_space_x_');
      await legacyNotebook(repo, app, nb, pageId, 4);
      FreeSpace.overrideForTest = (_) => null;

      final out = await app.reclaimContainerBlobs(nb);
      // MUTATION: treat null as "plenty" and this passes. That is the plan's
      // own headline hazard one layer up — a check that quietly degrades to no
      // check, on the one step that deletes data.
      expect(out.done, isFalse);
      expect(out.refusal, contains('could not check'));
      expect(blobRows(repo, nb), 4);
    });

    test('the real probe answers something plausible on this machine',
        () async {
      // Not a mock. `GetDiskFreeSpaceExW` on Windows and `df -Pk` elsewhere are
      // the only parts of this gate that cannot be unit-tested by construction,
      // and a probe that always returned null would make every refusal above
      // pass for the wrong reason.
      FreeSpace.overrideForTest = null;
      final free = FreeSpace.bytesFor(Directory.systemTemp.path);
      expect(free, isNotNull, reason: 'the platform call did not work here');
      expect(free, greaterThan(1024 * 1024));
    });
  });

  group('the marker file', () {
    test('a marker stops it, and silences the leftovers scan', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, tmp) = await fixture('onote_step7_marker_');
      await legacyNotebook(repo, app, nb, pageId, 3);

      // Something to find, so "nothing found" below is a real silence rather
      // than an empty workspace.
      File(p.join(tmp.path, 'Leftover.onote')).writeAsStringSync('x');
      expect(await app.findOrphanFiles(), isNotEmpty);

      File(p.join(tmp.path, 'reclaim-in-progress.json')).writeAsStringSync(
          jsonEncode({'step': 'empty-blobs-table', 'notebookId': nb}));
      expect(repo.reclaimInProgress, isTrue);

      final out = await app.reclaimContainerBlobs(nb);
      expect(out.done, isFalse);
      expect(out.refusal, contains('already tidying'));
      expect(blobRows(repo, nb), 3);

      // `findOrphanFiles` marks an unclaimed workspace `.onote`
      // `safeToDelete: true` and treats a `-wal` without its `.onote` as an
      // orphan — which is the state a migration creates for its own duration.
      // MUTATION: delete the `reclaimInProgress` early return and this comes
      // back with a notebook the student is invited to delete.
      expect(await app.findOrphanFiles(), isEmpty);
    });

    test('a marker left by a killed process is cleared at the next open',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final tmp = Directory.systemTemp.createTempSync('onote_step7_stale_');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      final marker = File(p.join(tmp.path, 'reclaim-in-progress.json'))
        ..writeAsStringSync(jsonEncode({'step': 'empty-blobs-table'}));

      final repo = await Repository.openAt(tmp);
      addTearDown(repo.dispose);

      // Both crash outcomes of this step are states a normal open settles —
      // the DELETE is one transaction that rolls back, and VACUUM either
      // completes or leaves the original — so the marker is a record, never a
      // repair instruction. MUTATION: delete `_clearStaleReclaimMarker()` from
      // `openAt` and the leftovers scan is disabled for ever, on a notebook
      // that is perfectly fine.
      expect(marker.existsSync(), isFalse);
      expect(repo.reclaimInProgress, isFalse);
    });
  });

  test('a second connection holding the file stops it', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, nb, pageId, _) = await fixture('onote_step7_busy_');
    await legacyNotebook(repo, app, nb, pageId, 3);
    final file = repo.notebooks.firstWhere((n) => n.id == nb).file;

    // The container must never be emptied while a `-wal` still holds pages: on
    // the owner's My Notebook that `-wal` was 2 whole pages plus newer
    // revisions of 6 more, and the damaged result still passed
    // `PRAGMA integrity_check`. A reader holding an open snapshot is exactly
    // what stops the checkpoint folding those pages in, so `TRUNCATE` answers
    // busy and the reclaim stops rather than deleting rows the other
    // connection can still see.
    final other = sqlite3.open(file);
    other.execute('BEGIN;');
    other.select('SELECT count(*) FROM nodes;');
    try {
      final out = await repo.reclaimContainerBlobs(nb);
      // MUTATION: drop the `busy == 1` branch and this passes.
      expect(out.done, isFalse);
      expect(out.details, contains('busy'));
      expect(blobRows(repo, nb), 3);
    } finally {
      other.execute('ROLLBACK;');
      other.dispose();
    }
  });

  group('Step 6 is a precondition, not an assumption', () {
    test('an old foreign key stops it', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, _) = await fixture('onote_step7_fk_');
      await legacyNotebook(repo, app, nb, pageId, 3);
      final file = repo.notebooks.firstWhere((n) => n.id == nb).file;

      // Put the constraint back the way every pre-Step-6 container has it —
      // through a SECOND connection, leaving the repository's handle open.
      // `openOnote` rewrites `blob_refs` on every open (that is Step 6), so a
      // fixture that closes the notebook is undone by the reopen the gate
      // itself performs, and the gate would be untestable.
      final raw = sqlite3.open(file);
      raw.execute('PRAGMA foreign_keys=OFF;');
      raw.execute('ALTER TABLE blob_refs RENAME TO blob_refs_old;');
      raw.execute('CREATE TABLE blob_refs ('
          'page_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE, '
          'hash TEXT NOT NULL REFERENCES blobs(hash), '
          'PRIMARY KEY (page_id, hash));');
      raw.execute('INSERT INTO blob_refs SELECT * FROM blob_refs_old;');
      raw.execute('DROP TABLE blob_refs_old;');
      raw.dispose();

      // The gate reads the DDL SQLite itself recorded, so it cannot be fooled
      // by what the code believes it wrote.
      final out = await repo.reclaimContainerBlobs(nb);
      expect(out.done, isFalse);
      expect(out.details, contains('REFERENCES blobs'));
      expect(blobRows(repo, nb), 3);
    });
  });

  group('reclaimFreeSpace stops reporting failure as success', () {
    // Matrix cell D6, and the plan's Step 7 item 5.
    test('"could not run" is no longer spelled the same as "nothing to do"',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, _) = await fixture('onote_step7_d6_');
      await legacyNotebook(repo, app, nb, pageId, 3);

      // "Nothing to do" — a second compaction on an already-compacted file.
      expect((await app.reclaimFreeSpace(nb)).ran, isTrue);
      final quiet = await app.reclaimFreeSpace(nb);
      expect(quiet.ran, isTrue);
      expect(quiet.problem, isNull);

      // "Could not run" — a directory where the container belongs makes
      // `sqlite3.open` fail deterministically on every platform, where making
      // a file read-only is flaky on Windows (the same trick Step 1's proof
      // settled on).
      final file = repo.notebooks.firstWhere((n) => n.id == nb).file;
      repo.closeNotebook(nb);
      File(file).deleteSync();
      Directory(file).createSync();

      final broken = await app.reclaimFreeSpace(nb);
      // MUTATION: put `return 0;` back in `Repository.reclaimFreeSpace`'s
      // catch and this is indistinguishable from `quiet` above — which is how
      // an out-of-disk VACUUM was reported to the user as a tidy notebook.
      expect(broken.ran, isFalse);
      expect(broken.freed, 0);
      expect(broken.problem, isNotNull);
      expect(broken.problem, isNot(contains('SqliteException')),
          reason: 'plain words for the user; the exception is in details');
      expect(broken.details, isNotNull);
    });
  });

  test('a notebook whose log will not open is refused, not waved through',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, nb, pageId, _) = await fixture('onote_step7_nolog_');
    await legacyNotebook(repo, app, nb, pageId, 3);

    // `proveBlobBytes` answers `checked: 0` with empty sets when there is no
    // recorder, and `BlobProof.ok` on that is TRUE — so a notebook whose log
    // is unopenable would otherwise clear the strictest gate in the plan by
    // having nothing to check.
    //
    // A file where the `ops` directory belongs, and **not** where the whole
    // `.onotebook` belongs: that makes `opsDir.createSync(recursive: true)`
    // fail deterministically on every platform (Step 1's proof settled on the
    // same trick, where "make the folder unwritable" is flaky on Windows)
    // while leaving `blobs/` perfectly intact — so every other gate is
    // satisfied and this test is about the missing recorder alone.
    final ref = repo.notebooks.firstWhere((n) => n.id == nb);
    await app.settleBackgroundWork();
    repo.closeNotebook(nb);
    final ops = Directory(p.join(ref.logDirPath, 'ops'));
    ops.deleteSync(recursive: true);
    File(ops.path).writeAsStringSync('not a directory');

    final app2 = AppState(repo)..notebookId = nb;
    addTearDown(app2.settleBackgroundWork);
    final out = await app2.reclaimContainerBlobs(nb);

    // MUTATION: delete the `if (r == null)` branch from
    // `AppState.reclaimContainerBlobs` and a zero-blob proof waves this
    // through, deleting every byte the container holds for a notebook whose
    // folder does not exist.
    expect(out.done, isFalse);
    expect(out.refusal, isNotNull);
    expect(blobRows(repo, nb), 3);
  });
}
