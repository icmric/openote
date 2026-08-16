// v0.17 plan, Step 8 items 1 and 2 — rebuild the working file from the log,
// and stop `openOnote` inventing a notebook where one is missing.
//
// **The claim under test is "the log is the notebook".** Three investigation
// passes measured it on the owner's real notebooks — 329 of 329 pages, 328 of
// 328, 14 of 14 — but nothing in the app could actually perform the rebuild:
// `SyncRecorder.pendingForeignOps` opens with `if (dev == device.id) continue`,
// so a single-device notebook's entire history lives in exactly the file the
// join path skips. `rebuildContainerFromLog` is the call that reads every
// device's log including this one's.
//
// **And the page-level comparison is not enough on its own**, which is the
// single most important thing this file encodes. `page_mirror` names a picture
// by hash, so a page whose blob bytes have been destroyed is byte-identical to
// the same page with its bytes intact: a spike ran a migration to completion
// over 278 hashes that had no bytes anywhere on disk, printed MIGRATION
// COMPLETE, left `integrity_check` saying `ok` and a comparison saying
// `same=329 differing=0`, and had permanently broken 193 image blocks across 40
// pages. So the round-trip test below compares **bytes**, not presence.
//
// The two negative controls the brief names are groups 2 and 3: the rebuild
// must refuse when the log cannot supply the whole notebook, and a notebook
// that has NOT been rebuilt must still open, read and save exactly as before.
//
// Every test names the mutation that turns it red, because a cell that cannot
// fail is not a cell (plan §5.1 rule 3).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/database.dart';
import 'package:openote/store/free_space.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/sync/op.dart';
import 'package:openote/sync/op_log.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());
  tearDown(() => FreeSpace.overrideForTest = null);

  /// A workspace with one notebook, opened through [AppState] so that every
  /// node and every page really has ops behind it.
  ///
  /// Going through `Repository` alone would not do: `createNotebook` writes its
  /// seed section and page straight into the container with no op at all, and
  /// `AppState._backfillTree` is what records them. A fixture that skipped this
  /// would be testing the rebuild against a notebook whose log is a fiction.
  Future<(Repository, AppState, String, String, Directory)> fixture(
      String name) async {
    final tmp = Directory.systemTemp.createTempSync(name);
    final repo = await Repository.openAt(tmp);
    late AppState created;
    addTearDown(() async {
      try {
        await created.settleBackgroundWork();
        await repo.flushWorkspace();
      } catch (_) {
        // A test that deliberately removes a container will land here, and
        // that is the point of it: a missing notebook file is now REPORTED
        // rather than papered over with a fabricated empty one.
      }
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final nb = await repo.createNotebook('Rebuildable');
    final app = created = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    final pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
    await app.selectPage(pageId);
    FreeSpace.overrideForTest = (_) => 8 * 1024 * 1024 * 1024;
    return (repo, app, nb.id, pageId, tmp);
  }

  Uint8List picture(int i, {int size = 2048}) => Uint8List.fromList(
      [for (var b = 0; b < size; b++) (b * 37 + i * 101) & 0xff]);

  /// Real handwriting in the model's own shape, so the save path's
  /// `InkStorage.persistAll` actually converts it to a blob. A hand-rolled
  /// stroke map that `Stroke.fromJson` cannot parse makes `toPersisted` bail
  /// and leave the block inline — which would silently make this fixture test
  /// no ink at all.
  ///
  /// `strokeStart: 0` on purpose: the field is encoded into the
  /// content-addressed blob, so stamping the clock would give byte-identical
  /// handwriting a different hash on every run.
  List<Map<String, dynamic>> strokes(int n) => [
        for (var s = 0; s < n; s++)
          Stroke(
            id: 'st$s',
            tool: 'pen',
            colorHex: '#211F1B',
            size: 2.0 + s,
            x: [for (var q = 0; q < 6; q++) 10.0 * q + s],
            y: [for (var q = 0; q < 6; q++) 20.0 * q - s],
            p: [for (var q = 0; q < 6; q++) 0.5],
            strokeStart: 0,
          ).toJson()
      ];

  String fileOf(Repository repo, String nb) =>
      repo.notebooks.firstWhere((n) => n.id == nb).file;

  OpLogStore logOf(Repository repo, String nb) {
    final ref = repo.notebooks.firstWhere((n) => n.id == nb);
    return OpLogStore.forNotebook(ref.file, logDir: ref.logDir);
  }

  /// Everything the container holds that a student could notice, read straight
  /// out of SQLite so the comparison cannot be fooled by a cache.
  ///
  /// Read through a SECOND connection on purpose: the repository's own handle
  /// is closed and replaced by the swap, and a snapshot taken through it would
  /// be comparing the rebuild against itself.
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
        // Blocks keyed by id rather than listed. The container stores whatever
        // order the editor's list happened to be in — render order is `z` and
        // flow order is `y` — and a replay can only reconstruct them in id
        // order, so comparing positions would report a difference that is not
        // one. Every other field is compared exactly, `updatedAt` included.
        'pages': {
          for (final r
              in db.select('SELECT page_id,json FROM page_mirror ORDER BY page_id'))
            r['page_id'] as String: () {
              final m = (jsonDecode(r['json'] as String) as Map)
                  .cast<String, dynamic>();
              return {
                'page': canonicalJson(m['page']),
                'blocks': {
                  for (final b in (m['blocks'] as List? ?? const []))
                    (b as Map)['id'] as String: canonicalJson(b)
                },
              };
            }()
        },
        'refs': [
          for (final r in db.select('SELECT src_page_id,src_block_id,kind,'
              'dst_page_id FROM refs ORDER BY src_page_id,src_block_id,kind'))
            '${r['src_page_id']}/${r['src_block_id']}/${r['kind']}/${r['dst_page_id']}'
        ],
        'blobRefs': [
          for (final r in db.select(
              'SELECT page_id,hash FROM blob_refs ORDER BY page_id,hash'))
            '${r['page_id']}/${r['hash']}'
        ],
        // There was a `versions` key here, over `page_versions`, asserting the
        // rebuild carried the table across. v0.17 decision 1 dropped the table
        // and the carry went with it; `Repository.demoteContainerToCache` is now
        // the one place its rows are destroyed, and it says so before it runs.
        'title': db
            .select("SELECT value FROM notebook_meta WHERE key='title'")
            .firstOrNull?['value'],
      };
    } finally {
      db.dispose();
    }
  }

  /// A notebook with one of everything a student can lose: writing, a picture,
  /// handwriting, a second page under a second section, a page in the recycle
  /// bin, page properties, a link between pages and a renamed notebook.
  ///
  /// Returns the blob hashes so the caller can compare BYTES afterwards.
  Future<List<String>> furnish(
      Repository repo, AppState app, String nb, String pageId) async {
    final imageHash = app.importBlob(nb, picture(1), 'image/png');
    final inlineHash = app.importBlob(nb, picture(2), 'image/png');

    // A second section with a page under it, so the tree has depth and the
    // rebuild has to get parents before children right. `addSection` seeds a
    // page of its own, so both ids come out of the difference.
    final had = {for (final n in app.nodes) n.id};
    await app.addSection();
    app.reloadNodes();
    final fresh = [for (final n in app.nodes) if (!had.contains(n.id)) n];
    final section2 = fresh.firstWhere((n) => n.kind == NodeKind.section).id;
    final page2 = fresh.firstWhere((n) => n.kind == NodeKind.page).id;

    await app.selectPage(pageId);
    app.blocks = [
      Block(
          id: 'b-text',
          type: BlockType.text,
          x: 12,
          y: 34,
          w: 400,
          h: 60,
          content: {'text': 'A paragraph, with a [[Second page]] link.'}),
      Block(
          id: 'b-inline',
          type: BlockType.text,
          x: 12,
          y: 120,
          w: 400,
          h: 60,
          content: {'text': 'inline ![pic](sha256:$inlineHash)'}),
      Block(
          id: 'b-image',
          type: BlockType.image,
          x: 200,
          y: 220,
          w: 320,
          h: 200,
          content: {'blob': 'sha256:$imageHash'}),
      // Inline strokes: the save path converts these through
      // `InkStorage.persistAll` and `importBlob`, which is the only way an ink
      // blob gets both its bytes and its `blob.put` op.
      Block(
          id: 'b-ink',
          type: BlockType.ink,
          x: 40,
          y: 400,
          w: 500,
          h: 300,
          content: {'strokes': strokes(24)}),
    ];
    app.pageProps = PageProps.fromJson({'sheet': 'a4', 'background': 'grid'});
    app.markDirty();
    await app.flushSave();

    await app.selectPage(page2);
    app.blocks = [
      Block(
          id: 'b2-text',
          type: BlockType.text,
          x: 0,
          y: 0,
          w: 300,
          h: 40,
          content: {'text': 'Second page body'})
    ];
    app.markDirty();
    await app.flushSave();

    // One page in the recycle bin, so `deletedAt` has to survive the rebuild at
    // the value the log recorded rather than being reset to today.
    final had2 = {for (final n in app.nodes) n.id};
    await app.addPage(sectionId: section2);
    app.reloadNodes();
    final doomed = app.nodes.firstWhere((n) => !had2.contains(n.id)).id;
    await app.selectPage(doomed);
    app.blocks = [
      Block(
          id: 'b3',
          type: BlockType.text,
          x: 0,
          y: 0,
          content: {'text': 'about to be trashed'})
    ];
    app.markDirty();
    await app.flushSave();
    await app.deleteNode(doomed);

    await app.renameNotebook(nb, 'Rebuildable — renamed');
    await app.selectPage(pageId);
    await app.settleBackgroundWork();
    await app.flushSave();

    // Read out of the STORED page, not out of `app.blocks`: `readPage`
    // deliberately inflates ink back to the working form on the way out, so the
    // in-memory block no longer carries the reference that was persisted.
    final stored = (jsonDecode(repo.rawPageJsonForTest(nb, pageId)!) as Map)
        .cast<String, dynamic>();
    final inkRefs = <String>[];
    for (final b in (stored['blocks'] as List? ?? const [])) {
      final ink = ((b as Map)['content'] as Map?)?['ink'];
      if (ink is Map && ink['base'] is String) {
        inkRefs.add((ink['base'] as String).replaceFirst('sha256:', ''));
      }
    }
    return [imageHash, inlineHash, ...inkRefs];
  }

  group('the rebuild reproduces the notebook', () {
    test('BYTE FOR BYTE: pages, blocks, ink, pictures, titles, order and dates',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, _) = await fixture('onote_step8_ok_');
      final hashes = await furnish(repo, app, nb, pageId);
      final file = fileOf(repo, nb);
      final store = logOf(repo, nb);

      expect(hashes.length, greaterThanOrEqualTo(3),
          reason: 'the fixture must really have a picture and handwriting');
      final bytesBefore = {
        for (final h in hashes) h: store.readBlob(h),
      };
      for (final e in bytesBefore.entries) {
        expect(e.value, isNotNull,
            reason: 'the fixture never wrote blob ${e.key}');
      }

      // Taken through a second connection, and only after the repository has
      // checkpointed: in WAL mode the `.onote` is not the notebook until
      // something folds the `-wal` back in.
      await app.reclaimFreeSpace(nb);
      final before = snapshot(file);
      expect((before['pages'] as Map).length, 3);
      expect((before['nodes'] as List).length, 5);

      final out = await app.rebuildContainerFromLog(nb);
      expect(out.refusal, isNull,
          reason: 'refused: ${out.refusal} // ${out.details}');
      expect(out.done, isTrue);
      expect(out.ops, greaterThan(0));

      final after = snapshot(file);

      // **The whole claim, in four lines.** MUTATION: delete the `writePage`
      // loop from `rebuildContainerFromLog` and `pages` comes back empty;
      // delete the `deleted_at` column from the node INSERT and `nodes`
      // differs on the trashed page.
      expect(after['nodes'], before['nodes'],
          reason: 'a node came back different — titles, order (position), '
              'level, colour and the created/updated/deleted dates are all in '
              'here');
      expect(after['pages'], before['pages'],
          reason: 'a page came back different — text, pictures and ink refs '
              'are all inside these blocks');
      expect(after['refs'], before['refs']);
      expect(after['blobRefs'], before['blobRefs'],
          reason: "ADR-0007's garbage-collection root set must survive, or the "
              'first collector run frees every picture in the notebook');
      // **The one field the rebuild deliberately does NOT reproduce, and it is
      // a correction rather than a loss.** `notebook_meta.title` is written
      // once, by `_seedNotebook`, and `Repository.renameNotebook` only touches
      // the registry — so the container's copy goes stale the moment a notebook
      // is renamed and nothing has ever noticed. The log carries the rename as
      // a `notebook.meta` op, which is why `SyncRecorder.notebookMeta` exists
      // at all ("a rename would be invisible to a second device"), and the
      // rebuild takes the live value.
      expect(before['title'], '"Rebuildable"',
          reason: 'the container really does still hold the pre-rename title');
      expect(after['title'], '"Rebuildable — renamed"',
          reason: 'the rebuild takes the name from the log, which is the one '
              'the student actually sees in the sidebar');

      // **And the bytes, not just the hashes.** This is the assertion the
      // spike's `same=329 differing=0` did not make.
      for (final e in bytesBefore.entries) {
        expect(store.readBlob(e.key), e.value,
            reason: 'blob ${e.key} lost its bytes in the rebuild');
      }

      // The notebook still works: it reads, and it still saves.
      await app.selectPage(pageId);
      expect(app.blocks.map((b) => b.id).toSet(),
          {'b-text', 'b-inline', 'b-image', 'b-ink'});
      expect(app.blob(hashes[0]), picture(1));
      app.blocks = [
        ...app.blocks,
        Block(
            id: 'b-after',
            type: BlockType.text,
            x: 0,
            y: 900,
            content: {'text': 'written after the rebuild'})
      ];
      app.markDirty();
      await app.flushSave();
      await app.selectPage(pageId);
      expect(app.blocks.any((b) => b.id == 'b-after'), isTrue);

      // Nothing left behind, and the leftovers scan is quiet again.
      expect(File('$file.rebuild').existsSync(), isFalse);
      expect(File('$file.previous').existsSync(), isFalse);
      expect(repo.reclaimInProgress, isFalse,
          reason: 'the marker is cleared on the way out, or the leftovers scan '
              'stays silent for ever');
    });

    test('rebuilding twice in a row is the same notebook again', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, _) = await fixture('onote_step8_twice_');
      await furnish(repo, app, nb, pageId);
      final file = fileOf(repo, nb);

      expect((await app.rebuildContainerFromLog(nb)).done, isTrue);
      await app.reclaimFreeSpace(nb);
      final once = snapshot(file);
      expect((await app.rebuildContainerFromLog(nb)).done, isTrue);
      await app.reclaimFreeSpace(nb);

      // Idempotence is the property that makes "run it again" a safe repair
      // instruction — which is the sentence that destroyed a 329-page notebook
      // in the spike, when it was NOT true.
      expect(snapshot(file), once);
    });
  });

  group('negative control 1 — the log cannot supply the whole notebook', () {
    test('a page the history has never seen stops it', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, _) = await fixture('onote_step8_nc1_');
      await furnish(repo, app, nb, pageId);
      final file = fileOf(repo, nb);

      // A node written straight into the container, the way every build before
      // the op log existed wrote them. `_backfillTree` would record it on the
      // next recorder install, so the notebook is closed and the write is made
      // through a second connection — which is exactly the shape of a container
      // restored from a backup newer than its `ops/`.
      repo.closeNotebook(nb);
      final raw = sqlite3.open(file);
      final parent = repo.loadNodes(nb).firstWhere((n) => n.kind == NodeKind.section).id;
      raw.execute(
          'INSERT INTO nodes(id,kind,parent_id,title,position,level,'
          'created_at,updated_at) VALUES(?,?,?,?,?,?,?,?)',
          ['ghost', 'page', parent, 'Only in the notebook', 'zz', 1, 1, 1]);
      raw.dispose();

      final before = snapshot(file);
      final out = await app.rebuildContainerFromLog(nb);

      // MUTATION: delete the `state.nodes[id] == null` branch from
      // `_rebuildDifferences` and this page is silently dropped — the notebook
      // opens, `integrity_check` says ok, and one page is simply gone.
      expect(out.done, isFalse);
      expect(out.refusal, isNotNull);
      expect(out.refusal, isNot(contains('sha256')),
          reason: 'the sentence a student reads carries no hash, no path and '
              'no exception; those live in the Advanced fold');
      expect(out.details, contains('ghost'));
      expect(snapshot(file), before, reason: 'refused BEFORE anything moved');
      expect(File('$file.rebuild').existsSync(), isFalse);
    });

    // The hole an id-only comparison would leave, and the reason
    // `_rebuildDifferences` compares CONTENT. `AppState._backfillTree` records
    // a `node.upsert` for every container node the log has never heard of — so
    // a notebook saved before the log existed has a log that NAMES every page
    // and holds not one of their blocks. Ids would match perfectly.
    test('a page whose blocks the history never recorded stops it', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, _) = await fixture('onote_step8_nc1b_');
      await furnish(repo, app, nb, pageId);
      final file = fileOf(repo, nb);

      // Straight through the repository, which is the funnel that bypasses the
      // recorder entirely: the container gains a block the log will never know
      // about.
      repo.writePage(
          nb,
          pageId,
          [
            Block(
                id: 'b-unlogged',
                type: BlockType.text,
                x: 0,
                y: 0,
                content: {'text': 'never recorded'})
          ],
          PageProps());
      await app.settleBackgroundWork();
      final before = snapshot(file);

      final out = await app.rebuildContainerFromLog(nb);
      // MUTATION: compare only ids in `_rebuildDifferences` — `containerNodes`
      // against `state.nodes.keys` — and this passes, replacing a page of
      // writing with an empty one.
      expect(out.done, isFalse);
      expect(out.details, contains(pageId));
      expect(snapshot(file), before);
    });

    test('a picture with no bytes in the folder stops it', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, _) = await fixture('onote_step8_nc1c_');
      final hashes = await furnish(repo, app, nb, pageId);
      final file = fileOf(repo, nb);
      final before = snapshot(file);

      // The state a half-finished cloud download leaves: the file is gone and
      // the page still names it. After Step 7 the container holds no second
      // copy, so this is the only copy there was.
      logOf(repo, nb).discardBlob(hashes[0]);

      final out = await app.rebuildContainerFromLog(nb);
      // MUTATION: change `if (!proof.ok)` in
      // `AppState.rebuildContainerFromLog` to something that never fires AND
      // drop gate 4's re-hash, and this passes — a rebuilt notebook whose
      // picture is gone, passing `integrity_check`.
      expect(out.done, isFalse);
      expect(out.refusal, isNotNull);
      expect(snapshot(file), before);
    });

    test('a picture whose bytes are wrong stops it', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, _) = await fixture('onote_step8_nc1d_');
      final hashes = await furnish(repo, app, nb, pageId);
      final store = logOf(repo, nb);

      // A file under the right NAME holding the wrong bytes. `existsSync`, a
      // file count and a length check all report this as healthy; only
      // re-hashing can see it.
      store.discardBlob(hashes[0]);
      store.writeBlob(hashes[0], picture(99));

      final out = await app.rebuildContainerFromLog(nb);
      // MUTATION: replace gate 4's hash comparison with `store.hasBlob(...)`
      // and this passes.
      expect(out.done, isFalse);
      expect(out.refusal, isNotNull);
    });

    test('an empty history stops it', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, _) = await fixture('onote_step8_nc1e_');
      await furnish(repo, app, nb, pageId);
      final file = fileOf(repo, nb);
      final before = snapshot(file);

      await app.settleBackgroundWork();
      final ops = logOf(repo, nb).opsDir;
      for (final f in ops.listSync()) {
        f.deleteSync(recursive: true);
      }

      // Straight at the repository, deliberately: going through `AppState`
      // would warm a recorder first, and warming one re-creates the log and
      // runs `_backfillTree`, so the notebook would no longer have an empty
      // history by the time the call ran. (That healing is itself worth
      // knowing about — an emptied `ops/` grows nodes back but never page
      // content, which is what the test above this one is about.)
      final out = await repo.rebuildContainerFromLog(nb);

      // MUTATION: drop the `ops.isEmpty` refusal and the notebook is replaced
      // by an empty container — 73,728 bytes, `integrity_check` ok, and
      // `notebookFileProblem` calls it "looks like a notebook". That is the
      // exact disaster the plan is written around.
      expect(out.done, isFalse);
      expect(out.refusal, contains('no history'));
      expect(snapshot(file), before);
    });

    test('an op from a newer Openote stops it', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, _) = await fixture('onote_step8_nc1f_');
      await furnish(repo, app, nb, pageId);
      final file = fileOf(repo, nb);
      final before = snapshot(file);
      await app.settleBackgroundWork();

      // An envelope this build cannot read. Not an unknown KIND — that is
      // designed to be skippable — but a record laid out differently, which
      // means this build cannot even tell what it touched.
      final store = logOf(repo, nb);
      final raw = File(p.join(store.opsDir.path, 'future-device.oplog'));
      raw.writeAsStringSync('${jsonEncode({
            'v': opFormatVersion + 1,
            'dev': 'future-device',
            'seq': 1,
            'lc': 99999,
            'ts': 1700000000000,
            'enc': 'none',
            'op': 'block.set',
            'd': {'pageId': pageId, 'block': {'id': 'x', 'type': 'text'}},
          })}\n');

      final app2 = AppState(repo)..notebookId = nb;
      addTearDown(app2.settleBackgroundWork);
      final out = await app2.rebuildContainerFromLog(nb);

      // MUTATION: delete the `state.unsupported.isNotEmpty` refusal and the
      // container is rewritten from a history this build has only half read.
      expect(out.done, isFalse);
      expect(out.refusal, contains('newer version'));
      expect(snapshot(file), before);
    });
  });

  group('negative control 2 — a notebook that has not been rebuilt', () {
    test('opens, reads and saves exactly as it did before', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, tmp) = await fixture('onote_step8_nc2_');
      final hashes = await furnish(repo, app, nb, pageId);
      final file = fileOf(repo, nb);
      await app.reclaimFreeSpace(nb);
      final before = snapshot(file);

      // Close it the way the app does at shutdown, and open the whole
      // workspace again from scratch — which is the path `_settleInterrupted-
      // Rebuild` and `openExistingOnote` were both added to.
      await app.settleBackgroundWork();
      await repo.flushWorkspace();
      // The handle, not the repository: the swap below renames the container,
      // and Windows raises ERROR_SHARING_VIOLATION on a file SQLite still has
      // open. The `Repository` itself stays alive so its teardown can tidy up.
      repo.closeNotebook(nb);

      final repo2 = await Repository.openAt(tmp);
      addTearDown(repo2.dispose);
      final app2 = AppState(repo2)
        ..notebookId = nb
        ..spellCheckEnabled = false;
      addTearDown(app2.settleBackgroundWork);

      expect(repo2.notebooks.map((n) => n.id), contains(nb),
          reason: 'a notebook nobody rebuilt must still be in the registry');
      app2.reloadNodes();
      await app2.selectPage(pageId);
      expect(app2.blocks.map((b) => b.id).toSet(),
          {'b-text', 'b-inline', 'b-image', 'b-ink'});
      expect(app2.blob(hashes[0]), picture(1));

      app2.blocks = [
        ...app2.blocks,
        Block(
            id: 'b-normal',
            type: BlockType.text,
            x: 0,
            y: 800,
            content: {'text': 'an ordinary save'})
      ];
      app2.markDirty();
      await app2.flushSave();
      await app2.selectPage(pageId);
      expect(app2.blocks.any((b) => b.id == 'b-normal'), isTrue);

      // MUTATION: make `_settleInterruptedRebuild` rename the container to
      // `.previous` unconditionally and this test loses the notebook — the
      // recovery must be inert on a workspace that never had a rebuild.
      expect(File('$file.previous').existsSync(), isFalse);
      expect(File('$file.rebuild').existsSync(), isFalse);
      // Page content is untouched; only the one new block was added.
      final now = snapshot(file);
      expect((now['nodes'] as List), before['nodes']);
      expect((now['blobRefs'] as List), before['blobRefs']);
    });
  });

  group('openOnote stops fabricating a notebook', () {
    test('a registered notebook whose file has gone is reported, not invented',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, _) = await fixture('onote_step8_ghost_');
      await furnish(repo, app, nb, pageId);
      final file = fileOf(repo, nb);
      await app.settleBackgroundWork();
      repo.closeNotebook(nb);
      for (final side in const ['', '-wal', '-shm']) {
        final f = File('$file$side');
        if (f.existsSync()) f.deleteSync();
      }

      // MUTATION: put `openOnote` back in `Repository._db` and this throws
      // nothing at all — it leaves a fresh 73,728-byte database on disk, which
      // `notebookFileProblem` then calls "looks like a notebook", and the real
      // one is no longer registered anywhere.
      expect(() => repo.loadNodes(nb), throwsA(isA<NotebookFileMissing>()));
      expect(File(file).existsSync(), isFalse,
          reason: 'refusing must not leave a fabricated container behind');
    });

    test('creating and joining a notebook still make one deliberately',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final tmp = Directory.systemTemp.createTempSync('onote_step8_make_');
      final repo = await Repository.openAt(tmp);
      addTearDown(() async {
        await repo.flushWorkspace();
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      // The three callers that really do mean "make me one" must be
      // unaffected: they call `openOnote` directly and seed `_open`
      // themselves. MUTATION: route `createNotebook` through
      // `openExistingOnote` and this throws on the first line.
      final made = await repo.createNotebook('Brand new');
      expect(repo.loadNodes(made.id), isNotEmpty);

      final folder = Directory(p.join(tmp.path, 'Joined.onotebook'))
        ..createSync(recursive: true);
      Directory(p.join(folder.path, 'ops')).createSync();
      File(p.join(folder.path, 'manifest.json'))
          .writeAsStringSync(jsonEncode({'notebookId': 'joined', 'title': 'Joined'}));
      final joined = await repo.adoptLogDirectory(folder.path, title: 'Joined');
      expect(File(joined.file).existsSync(), isTrue);
      expect(repo.loadNodes(joined.id), isEmpty,
          reason: 'a joined notebook starts empty and the first pull fills it');
    });
  });

  group('killed part-way through', () {
    /// Put a workspace back the way a fresh process start would find it.
    Future<Repository> reopen(Directory tmp) async {
      final repo = await Repository.openAt(tmp);
      addTearDown(repo.dispose);
      return repo;
    }

    test('killed while building: the notebook is untouched, the leftover goes',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, tmp) = await fixture('onote_step8_k1_');
      await furnish(repo, app, nb, pageId);
      final file = fileOf(repo, nb);
      await app.reclaimFreeSpace(nb);
      final before = snapshot(file);
      await app.settleBackgroundWork();
      await repo.flushWorkspace();
      // The handle, not the repository: the swap below renames the container,
      // and Windows raises ERROR_SHARING_VIOLATION on a file SQLite still has
      // open. The `Repository` itself stays alive so its teardown can tidy up.
      repo.closeNotebook(nb);

      // The state a kill during the build leaves: a half-written replacement
      // that was never in place and that nothing has ever read.
      File('$file.rebuild').writeAsBytesSync(
          File(file).readAsBytesSync().sublist(0, 4096));

      final repo2 = await reopen(tmp);
      expect(repo2.notebooks.map((n) => n.id), contains(nb));
      expect(File('$file.rebuild').existsSync(), isFalse,
          reason: 'the half-built file is dropped, not adopted');
      expect(snapshot(file), before);
    });

    test('KILLED BETWEEN THE TWO RENAMES: the notebook comes back', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, tmp) = await fixture('onote_step8_k2_');
      await furnish(repo, app, nb, pageId);
      final file = fileOf(repo, nb);
      await app.reclaimFreeSpace(nb);
      final before = snapshot(file);
      await app.settleBackgroundWork();
      await repo.flushWorkspace();
      // The handle, not the repository: the swap below renames the container,
      // and Windows raises ERROR_SHARING_VIOLATION on a file SQLite still has
      // open. The `Repository` itself stays alive so its teardown can tidy up.
      repo.closeNotebook(nb);

      // The one-rename-wide window: the notebook is at `.previous` and nothing
      // is at the registered path. This is the state the spike's "just run it
      // again" turned into 73,728 bytes.
      File(file).renameSync('$file.previous');
      expect(File(file).existsSync(), isFalse);

      final repo2 = await reopen(tmp);

      // **The registry must not have been pruned.** `_loadWorkspace` drops any
      // entry whose file is missing and `_saveWorkspace` then rewrites the file
      // from what survived — so without the recovery running BEFORE that
      // filter, one kill in this window loses the notebook permanently at the
      // next start, not at this one. MUTATION: move
      // `_settleInterruptedRebuild(file)` to after the `existsSync` check and
      // this fails.
      expect(repo2.notebooks.map((n) => n.id), contains(nb),
          reason: 'the notebook was pruned from the registry by a crash');
      expect(File(file).existsSync(), isTrue);
      expect(File('$file.previous').existsSync(), isFalse);
      expect(snapshot(file), before, reason: 'and it is the SAME notebook');

      // And it still opens and saves.
      final app2 = AppState(repo2)
        ..notebookId = nb
        ..spellCheckEnabled = false;
      addTearDown(app2.settleBackgroundWork);
      app2.reloadNodes();
      await app2.selectPage(pageId);
      expect(app2.blocks.map((b) => b.id), contains('b-image'));
    });

    test('killed after the swap: the new notebook stays and the old one goes',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, tmp) = await fixture('onote_step8_k3_');
      await furnish(repo, app, nb, pageId);
      final file = fileOf(repo, nb);
      await app.reclaimFreeSpace(nb);
      await app.settleBackgroundWork();
      await repo.flushWorkspace();
      // The handle, not the repository: the swap below renames the container,
      // and Windows raises ERROR_SHARING_VIOLATION on a file SQLite still has
      // open. The `Repository` itself stays alive so its teardown can tidy up.
      repo.closeNotebook(nb);

      // The swap finished and only the tidy-up was lost: the container in place
      // is the NEW one, and `.previous` is the superseded copy. Made visibly
      // different so "kept the right one" is a real assertion.
      File(file).copySync('$file.previous');
      final stale = sqlite3.open('$file.previous');
      stale.execute("UPDATE nodes SET title='STALE COPY'");
      stale.dispose();
      final live = snapshot(file);

      final repo2 = await reopen(tmp);
      expect(repo2.notebooks.map((n) => n.id), contains(nb));
      expect(File('$file.previous').existsSync(), isFalse);
      // MUTATION: make `_settleInterruptedRebuild` prefer `.previous` when both
      // exist and the notebook silently reverts to before the rebuild.
      expect(snapshot(file), live);
    });

    test('a failure part-way leaves no half-built container registered',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, _) = await fixture('onote_step8_k4_');
      await furnish(repo, app, nb, pageId);
      final file = fileOf(repo, nb);
      await app.reclaimFreeSpace(nb);
      final before = snapshot(file);

      // A directory where the replacement has to be written makes
      // `sqlite3.open` fail deterministically on every platform, where making a
      // file read-only is flaky on Windows (the trick Step 1's proof settled
      // on). It fires after every gate has passed, which is the window this
      // test is about.
      Directory('$file.rebuild').createSync();
      addTearDown(() {
        final d = Directory('$file.rebuild');
        if (d.existsSync()) d.deleteSync(recursive: true);
      });

      final out = await app.rebuildContainerFromLog(nb);
      expect(out.done, isFalse);
      expect(out.refusal, isNotNull);
      expect(out.refusal, isNot(contains('Sqlite')),
          reason: 'plain words for the user; the exception is in details');
      expect(snapshot(file), before, reason: 'the notebook is untouched');
      expect(repo.reclaimInProgress, isFalse,
          reason: 'a failure must not leave the leftovers scan disabled');
    });

    test('the leftovers scan is silent while a rebuild holds the workspace',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, tmp) = await fixture('onote_step8_scan_');
      await furnish(repo, app, nb, pageId);

      // Something to find, so "nothing found" below is a real silence rather
      // than an empty workspace.
      File(p.join(tmp.path, 'Leftover.onote')).writeAsStringSync('x');
      expect(await app.findOrphanFiles(), isNotEmpty);

      File(p.join(tmp.path, 'reclaim-in-progress.json')).writeAsStringSync(
          jsonEncode({'step': 'rebuild-from-log', 'notebookId': nb}));

      // `findOrphanFiles` marks an unclaimed workspace `.onote`
      // `safeToDelete: true` and treats a `-wal` without its `.onote` as an
      // orphan — which is the state the swap creates for two renames. A student
      // pressing "Find leftovers" at that second would be offered their own
      // notebook to delete.
      expect(await app.findOrphanFiles(), isEmpty);
      final out = await app.rebuildContainerFromLog(nb);
      expect(out.done, isFalse);
      expect(out.refusal, contains('already tidying'));
    });
  });

  group('the 2.0× free-space precheck', () {
    test('not enough room stops it, before anything is written', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, _) = await fixture('onote_step8_space_');
      await furnish(repo, app, nb, pageId);
      final file = fileOf(repo, nb);
      await app.reclaimFreeSpace(nb);
      final before = snapshot(file);
      final size = File(file).lengthSync();

      // Just under the bar. A rebuild writes a second whole copy of the
      // database beside the first and only removes the original once the
      // replacement is verified in place, so the transient peak really is both.
      FreeSpace.overrideForTest = (_) => (size * 2) - 1;

      final out = await app.rebuildContainerFromLog(nb);
      // MUTATION: drop the `free < need` branch and this runs on a full disk,
      // where the replacement is truncated and the original has already gone.
      expect(out.done, isFalse);
      expect(out.refusal, contains('not enough free space'));
      expect(snapshot(file), before);
      expect(File('$file.rebuild').existsSync(), isFalse);
      expect(repo.reclaimInProgress, isFalse,
          reason: 'the marker is only written once the answer is yes');
    });

    test('not being able to measure stops it', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId, _) = await fixture('onote_step8_space_x_');
      await furnish(repo, app, nb, pageId);
      final file = fileOf(repo, nb);
      await app.reclaimFreeSpace(nb);
      final before = snapshot(file);
      FreeSpace.overrideForTest = (_) => null;

      final out = await app.rebuildContainerFromLog(nb);
      // MUTATION: treat null as "plenty" and this passes. A check that quietly
      // degrades to no check, on the step that replaces the notebook.
      expect(out.done, isFalse);
      expect(out.refusal, contains('could not check'));
      expect(snapshot(file), before);
    });
  });
}
