// Step 6 of the v0.17 storage plan: the container stops writing blob bytes,
// and every read passes through `.onotebook/blobs/`.
//
// **This step buys nothing on disk, deliberately.** Step 7 is what deletes the
// container's copy of every picture; this one puts the read path that Step 7
// depends on into the field for a whole release while those old bytes are
// still sitting there as a safety net. Renaming and de-duplicating in one
// release would be two irreversible changes sharing one crash window.
//
// **So the fallback is the feature, not a leftover.** Step 5 measured the
// owner's own notebooks: 378 of 488 blobs had no file in `blobs/` and are
// copied out in the background on first open. For the seconds — on a real
// notebook, three of them — that copy is running, a read that finds no file is
// NORMAL and the bytes are still in the container. A file-only read path would
// blank 271 image blocks across 44 pages for the duration; a table-first one
// would leave the file path untested in the field, which is the one thing this
// step exists to do. Hence file first, container second, and every fallback
// recorded, because the day Step 7 runs each one is a picture that would come
// up blank.
//
// The two negative controls the plan asks for are `only in the container` and
// `in both`. The first is the whole point of the fallback. The second is the
// precedence rule, and it has to be asserted with the two copies DISAGREEING,
// or "it came from the file" is indistinguishable from "it came from the
// table".

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:openote/ink/ink_codec.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/notebook_writer.dart' show sha256Hex;
import 'package:openote/store/repository.dart';
import 'package:openote/sync/op_log.dart';

import 'support/sqlite.dart';

/// The `blob_refs` DDL as SQLite itself records it, read straight from the
/// notebook file. The one honest way to ask whether the foreign key is there.
String _blobRefsDdl(String notebookFile) {
  final db = sqlite3.open(notebookFile, mode: OpenMode.readOnly);
  try {
    return db.select("SELECT sql FROM sqlite_master WHERE type='table' "
        "AND name='blob_refs'").first['sql'] as String;
  } finally {
    db.dispose();
  }
}

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Future<(Repository, AppState, String, String)> fixture(String name) async {
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
    final nb = await repo.createNotebook('Reads');
    final app = created = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    final pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
    app.pageId = pageId;
    return (repo, app, nb.id, pageId);
  }

  OpLogStore logOf(Repository repo, String nb) {
    final ref = repo.notebooks.firstWhere((n) => n.id == nb);
    return OpLogStore.forNotebook(ref.file, logDir: ref.logDir);
  }

  Uint8List picture(int i, {int size = 512}) =>
      Uint8List.fromList([for (var b = 0; b < size; b++) (b * 31 + i * 7) & 0xff]);

  Block imageBlock(String id, String hash) => Block(
      id: id,
      type: BlockType.image,
      x: 10,
      y: 20,
      w: 320,
      h: 200,
      content: {'blob': 'sha256:$hash'});

  List<Stroke> handwriting({int count = 12, int seed = 5}) {
    final rnd = Random(seed);
    return [
      for (var s = 0; s < count; s++)
        () {
          final xs = <double>[], ys = <double>[], ps = <double>[];
          var x = 120 + rnd.nextDouble() * 700;
          var y = 90 + rnd.nextDouble() * 500;
          for (var i = 0; i < 16; i++) {
            x += rnd.nextDouble() * 5 - 2.5;
            y += rnd.nextDouble() * 5 - 2.5;
            xs.add(x);
            ys.add(y);
            ps.add(0.2 + rnd.nextDouble() * 0.8);
          }
          return Stroke(
              id: 'w$s',
              tool: 'pen',
              colorHex: '#211F1B',
              size: 2.5,
              x: xs,
              y: ys,
              p: ps);
        }()
    ];
  }

  group('a notebook made after Step 6', () {
    // Matrix cell B1: brand-new notebook, zero `blobs` rows, and every
    // `blob_refs` hash resolves to a file whose SHA-256 is its own name.
    test('keeps its pictures in blobs/ and nothing at all in the blobs table',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId) = await fixture('onote_step6_fresh_');

      final hashes = [
        for (var i = 0; i < 4; i++) app.importBlob(nb, picture(i), 'image/png')
      ];
      repo.writePage(
          nb,
          pageId,
          [for (var i = 0; i < hashes.length; i++) imageBlock('i$i', hashes[i])],
          PageProps());

      // MUTATION: put the `INSERT INTO blobs` back in `Repository.putBlob`
      // and this fails.
      expect(repo.blobIndex(nb), isEmpty,
          reason: 'the container stopped taking blob bytes at Step 6; a row '
              'here means Step 7 would still have something to reclaim, and '
              'that the read path below is not being exercised at all');

      // The other half of B1, and the half that catches the mistake this step
      // could most easily make. `blob_refs` is ADR-0007's garbage-collection
      // root set and it USED to be filled by `SELECT hash FROM blobs`, which
      // after this change would select nothing for ever: an empty root set,
      // silently, and a future collector that frees the whole notebook.
      // MUTATION: restore `SELECT ?, hash FROM blobs WHERE hash=?` in
      // `NotebookWriter._addBlobRef` and this comes back empty.
      final refs = repo.blobRefsForTest(nb, pageId);
      expect(refs.toSet(), hashes.toSet(),
          reason: 'every picture the page reaches must still be declared, '
              'even though the container holds none of their bytes');
      final store = logOf(repo, nb);
      for (final h in refs) {
        expect(store.hasBlob(h), isTrue, reason: 'no file for $h');
        expect(sha256Hex(store.readBlob(h)!), h,
            reason: 'a file named by its content must hold that content');
      }
    });

    test('handwriting still reads back, and it comes out of blobs/', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, pageId) = await fixture('onote_step6_ink_');

      // Ink was the one blob kind ALWAYS written to `blobs/` — `SyncRecorder`
      // exempts `inkMimeType` from the deferral, because an ink block holds a
      // reference and a log that cannot supply the bytes cannot rebuild the
      // handwriting. But it was only ever WRITTEN through; every read still
      // came out of the container's table via `Repository.readPage`. So this
      // is the one place Step 6 could regress something that already worked.
      final strokes = handwriting();
      app.blocks = [
        Block(
            id: 'ink-1',
            type: BlockType.ink,
            x: 100,
            y: 80,
            w: 800,
            h: 600,
            content: {'strokes': [for (final s in strokes) s.toJson()]})
      ];
      app.markDirty();
      await app.flushSave();

      final back = repo.readPage(nb, pageId);
      final got = back.blocks.single.content['strokes'] as List;
      expect(got, hasLength(strokes.length));
      expect(Stroke.fromJson((got.first as Map).cast<String, dynamic>()).x.first,
          closeTo(strokes.first.x.first, 1 / (2 * kInkScale)),
          reason: 'the strokes themselves came back, not just a count');

      final refs = repo.blobRefsForTest(nb, pageId);
      expect(refs, hasLength(1), reason: 'the page declares its ink');
      expect(logOf(repo, nb).hasBlob(refs.single), isTrue);
      expect(repo.blobIndex(nb), isEmpty,
          reason: 'and the container has no copy to have read it from');
    });
  });

  test('a notebook made BEFORE Step 6 loses the foreign key on first open',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, nb, pageId) = await fixture('onote_step6_legacy_fk_');
    final file = repo.notebooks.firstWhere((n) => n.id == nb).file;

    // Put the container back the way every notebook on disk today is written:
    // `blob_refs.hash REFERENCES blobs(hash)`, which meant "blobs this page
    // reaches THAT THIS CONTAINER HOLDS". `CREATE TABLE IF NOT EXISTS` cannot
    // change a table that exists, so changing the schema fixes new notebooks
    // and nobody else's — this is the only shape that proves the rewrite.
    repo.closeNotebook(nb);
    var db = sqlite3.open(file);
    db.execute('PRAGMA foreign_keys=OFF;');
    db.execute('DROP TABLE blob_refs;');
    db.execute('CREATE TABLE blob_refs ('
        'page_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE, '
        'hash TEXT NOT NULL REFERENCES blobs(hash), '
        'PRIMARY KEY (page_id, hash));');
    db.dispose();
    expect(_blobRefsDdl(file), contains('REFERENCES blobs'),
        reason: 'the fixture has to actually be the old shape');

    // Any read reopens it, and the open is where the rewrite happens.
    final hash = app.importBlob(nb, picture(6), 'image/png');
    repo.writePage(nb, pageId, [imageBlock('i0', hash)], PageProps());

    // MUTATION: delete the `_dropBlobRefsBlobsFk(db)` call from `openOnote`
    // and both of these fail — the first outright, the second because
    // `_addBlobRef`'s fallback records what the old schema can, which is
    // nothing.
    expect(_blobRefsDdl(file), isNot(contains('REFERENCES blobs')),
        reason: 'the key is gone, so a page can declare bytes the container '
            'does not hold — which after Step 6 is every page');
    expect(repo.blobRefsForTest(nb, pageId), [hash],
        reason: 'and the reference really is recorded. Without the rewrite '
            'the INSERT raises a constraint violation, the fallback records '
            "what the old schema can — nothing — and ADR-0007's garbage "
            'collection root set is empty for every picture from here on');
  });

  group('the two negative controls', () {
    // **Negative control one.** A picture whose bytes are only in the container
    // is every picture in every notebook that existed before Step 5 ran, for as
    // long as the backfill takes. It must render.
    test('a blob present ONLY in the container still renders, and says so',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, _) = await fixture('onote_step6_container_only_');

      final bytes = picture(9, size: 700);
      final hash = repo.putContainerBlobForTest(nb, bytes, 'image/png');
      expect(logOf(repo, nb).hasBlob(hash), isFalse,
          reason: "Honours-4's exact shape: bytes in the container, no file");

      // MUTATION: delete the container fallback from `Repository.getBlob`
      // (return null when `blobs/` has no file) and this fails.
      expect(app.blob(hash), bytes,
          reason: 'a read that fell back to nothing would be 26.3 MB of the '
              "owner's pictures blank for the length of a backfill");

      // Falling back is correct today and fatal the day Step 7 empties that
      // table, so it is never silent: the hash is on the register a migration
      // has to consult before it deletes anything.
      expect(repo.blobsServedFromContainer(nb), contains(hash));
      expect(repo.blobsWithNoBytes(nb), isEmpty);
    });

    // **Negative control two.** With a copy in both places the answer must come
    // from the file — asserted with the two copies deliberately disagreeing,
    // because two identical copies cannot tell you which one was read.
    test('a blob present in BOTH is answered from blobs/', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, _) = await fixture('onote_step6_both_');

      final container = picture(2, size: 300);
      final hash = repo.putContainerBlobForTest(nb, container, 'image/png');
      final file = Uint8List.fromList([for (final b in container) b ^ 0xff]);
      // `writeBlob` does not check the bytes against the name, and that is not
      // an oversight — re-hashing costs 2.8 s across a real notebook and cannot
      // be paid per read. `SyncRecorder.proveBlobs` is the verifier, at open;
      // the sync pull checks each newly arrived file. Here it is simply the one
      // way to make the two copies distinguishable.
      logOf(repo, nb).writeBlob(hash, file);

      // MUTATION: read the container first in `Repository.getBlob` and this
      // fails — and nothing else in the suite would notice.
      expect(app.blob(hash), file,
          reason: 'file first. If this returns the container copy the read '
              'path is untested by every other test in this suite, because '
              'both copies normally agree — and Step 7 would then be deleting '
              'the bytes the app is actually reading');
      expect(repo.blobsServedFromContainer(nb), isEmpty,
          reason: 'nothing fell back, so nothing is registered');
    });

    test('bytes in neither place return null, and are reported', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, _) = await fixture('onote_step6_nowhere_');

      // The ordinary shape of a shared notebook: a cloud client copies the log
      // and the blob files independently, so a reference routinely arrives
      // first. Not an error — but never silent either, which is the failure a
      // spike already reproduced at scale (MIGRATION COMPLETE over 193
      // destroyed image blocks).
      const absent =
          'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
      expect(app.blob(absent), isNull);
      expect(repo.blobsWithNoBytes(nb), contains(absent));
      expect(repo.blobsServedFromContainer(nb), isEmpty);
    });
  });

  test('reads are right DURING the backfill, not only after it', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, nb, _) = await fixture('onote_step6_during_');

    // 30 pictures in the container and none in `blobs/` — the state Step 5
    // found 378 of the owner's 488 blobs in. The backfill is paced at a real
    // millisecond per blob so the app stays usable, which means there is a
    // stretch of tens of milliseconds where SOME of these have files and the
    // rest do not, and the read path has to be right at every instant of it.
    final bytes = [for (var i = 0; i < 30; i++) picture(i, size: 1024)];
    final hashes = [
      for (final b in bytes) repo.putContainerBlobForTest(nb, b, 'image/png')
    ];
    await app.settleBackgroundWork();

    final app2 = AppState(repo)..notebookId = nb;
    addTearDown(app2.settleBackgroundWork);
    final store = logOf(repo, nb);

    // Start the open — and do NOT wait for it. Reading only after the backfill
    // has finished is the assertion that would have passed for a file-only
    // read path, which is exactly the bug this is written against.
    final warm = app2.warmRecorder(nb);
    var sawMixed = false;
    for (var turn = 0; turn < 400; turn++) {
      final withFile = [for (final h in hashes) if (store.hasBlob(h)) h].length;
      if (withFile > 0 && withFile < hashes.length) sawMixed = true;
      for (var i = 0; i < hashes.length; i++) {
        expect(app2.blob(hashes[i]), bytes[i],
            reason: 'blob $i read wrong on turn $turn, with $withFile of '
                '${hashes.length} files written');
      }
      if (withFile == hashes.length) break;
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await warm;
    await app2.settleBackgroundWork();

    expect(sawMixed, isTrue,
        reason: 'the half-materialised window is the thing under test; if the '
            'backfill finished in one turn this proved nothing');
    for (var i = 0; i < hashes.length; i++) {
      expect(store.readBlob(hashes[i]), bytes[i]);
      expect(app2.blob(hashes[i]), bytes[i]);
    }
    // And once every file is there the register empties itself, so a Step 7
    // gate reading it does not refuse for ever on a notebook that has since
    // been put right.
    expect(repo.blobsServedFromContainer(nb), isEmpty);
  });
}
