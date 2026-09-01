// Step 5 of the v0.17 storage plan: blob bytes are always materialised, and
// coverage is PROVED.
//
// **The hole this closes, measured on the owner's real notebooks.** Blob bytes
// used to be written into `.onotebook/blobs/` only when the notebook "looked
// shared" (`AppState.notebookIsShared`). On the owner's post-Phase-1 import of
// his Honours notebook that left **378 of the 488 blobs its log names with no
// bytes on disk — every one of them an `image/png`, 26,325,596 B**, so a
// rebuild from the log produced a structurally perfect notebook (same=329
// differing=0) with 271 of 271 image blocks broken across 44 pages. Nothing
// said so, because a page references a picture by hash: a page whose bytes are
// gone is byte-identical to the same page with its bytes intact.
//
// **Why a count is not a proof, which is what these tests are really about.**
// `SyncRecorder.missingBlobs()` asks `File.existsSync`, and
// `OpLogStore.writeBlob` skips any hash that already has a file. So a blob that
// a full disk truncated, or that a cloud client copied in half, is reported
// COMPLETE by every check Openote had and is never repaired by re-running
// anything. Step 7 deletes the container's copy on the strength of that answer.
// Hence `proveBlobs`, and hence the negative control below: the proof has to go
// red for a file that is *present with the wrong bytes*, not only for one that
// is absent.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openote/state/app_state.dart';
import 'package:openote/store/notebook_writer.dart' show sha256Hex;
import 'package:openote/store/repository.dart';
import 'package:openote/sync/op_log.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Future<(Repository, AppState, String)> fixture(String name) async {
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
    final nb = await repo.createNotebook('Blobs');
    final app = created = AppState(repo)..notebookId = nb.id;
    app.reloadNodes();
    return (repo, app, nb.id);
  }

  OpLogStore logOf(Repository repo, String nb) =>
      OpLogStore.forNotebook(repo.notebooks.firstWhere((n) => n.id == nb).file);

  /// A distinct, compressible-looking PNG-ish payload per index. Content, not
  /// shape, is what matters here — every assertion is about bytes.
  Uint8List picture(int i, {int size = 512}) =>
      Uint8List.fromList([for (var b = 0; b < size; b++) (b * 31 + i * 7) & 0xff]);

  group('bytes are materialised whether or not anything syncs', () {
    test('a notebook that syncs nowhere still writes its picture bytes out',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb) = await fixture('onote_blob_local_');

      // No mirror, no git remote, no cloud folder: `notebookIsShared` is false,
      // which is the state 378 of the owner's 488 blobs were deferred in.
      expect(app.notebookIsShared(nb), isFalse,
          reason: 'the local-only case is the one Step 5 is about; if this '
              'fixture looked shared the test would prove nothing');

      final bytes = picture(1);
      final hash = app.importBlob(nb, bytes, 'image/png');
      await app.settleBackgroundWork();

      final f = logOf(repo, nb).blobFile(hash);
      expect(f.existsSync(), isTrue,
          reason: 'the bytes must be in `blobs/`, not only in the container');
      expect(f.readAsBytesSync(), bytes);
      expect(app.syncMissingBlobs(nb), isEmpty);
      expect(app.saveError, isNull);
    });

    test('a notebook whose bytes are only in the container is healed on open',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb) = await fixture('onote_blob_heal_');

      // Honours-4's exact shape, in miniature: pictures in the container that
      // the log has never been told about and that `blobs/` does not hold.
      // Written straight through Repository so no op is recorded either.
      final hashes = [
        for (var i = 0; i < 6; i++)
          repo.putContainerBlobForTest(nb, picture(i), 'image/png')
      ];
      final store = logOf(repo, nb);
      for (final h in hashes) {
        expect(store.hasBlob(h), isFalse);
      }

      // A second session: opening the notebook is what runs the backfill.
      final app2 = AppState(repo)..notebookId = nb;
      addTearDown(app2.settleBackgroundWork);
      await app2.warmRecorder(nb);
      await app2.settleBackgroundWork();

      for (var i = 0; i < hashes.length; i++) {
        expect(store.blobFile(hashes[i]).readAsBytesSync(), picture(i),
            reason: 'the backfill must copy the real bytes, not merely make a '
                'file of the right name');
      }
      expect(app2.syncMissingBlobs(nb), isEmpty);
      final proof = await app2.proveBlobBytes(nb);
      expect(proof.ok, isTrue, reason: '$proof');
      expect(proof.checked, hashes.length);
    });
  });

  group('the proof re-hashes, so wrong bytes cannot pass as right ones', () {
    test('the Step 5 invariant: every hash the log names re-hashes to its name',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb) = await fixture('onote_blob_invariant_');

      final hashes = [
        for (var i = 0; i < 5; i++)
          app.importBlob(nb, picture(i, size: 300 + i), 'image/png')
      ];
      await app.settleBackgroundWork();

      // Stated the way the plan states it, and checked by reading the folder
      // rather than by asking the recorder what it believes.
      final store = logOf(repo, nb);
      for (final h in hashes) {
        final f = store.blobFile(h);
        expect(f.existsSync(), isTrue);
        expect(sha256Hex(f.readAsBytesSync()), h);
      }
      expect(app.syncMissingBlobs(nb), isEmpty);
      expect((await app.proveBlobBytes(nb)).ok, isTrue);
    });

    // ── THE NEGATIVE CONTROL ────────────────────────────────────────────
    //
    // Same file name, same file LENGTH, different bytes — the shape a
    // half-finished cloud download or a bad sector leaves. Everything Openote
    // had before this step reports the notebook complete, and Step 7 would then
    // delete the last good copy out of the container.
    test('a blob present with the WRONG bytes fails the proof and is repaired',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb) = await fixture('onote_blob_wrongbytes_');

      final good = picture(3, size: 400);
      final hash = app.importBlob(nb, good, 'image/png');
      // The container's copy, put there explicitly. Until v0.17 Step 6 every
      // `importBlob` wrote one as a side effect; now the container takes no
      // blob bytes at all, so the second copy this repair reads from has to be
      // built on purpose. A blob with NO second copy is a different outcome —
      // `damaged`, not `repaired` — and `blob_read_through_test.dart` proves
      // that one.
      repo.putContainerBlobForTest(nb, good, 'image/png');
      await app.settleBackgroundWork();

      final f = logOf(repo, nb).blobFile(hash);
      final wrong = Uint8List.fromList([for (final b in good) b ^ 0xff]);
      expect(wrong.length, good.length, reason: 'same length on purpose');
      f.writeAsBytesSync(wrong, flush: true);

      // The old checks are blind to this, and that is the point of the step.
      expect(app.syncMissingBlobs(nb), isEmpty,
          reason: 'an existsSync — and equally a file count, or a length '
              'comparison — passes against a corrupt blob. Only re-hashing '
              'can tell the difference');

      final proof = await app.proveBlobBytes(nb);
      expect(proof.checked, 1, reason: 'the bytes were actually read');
      expect(proof.missing, isEmpty, reason: 'the file was never absent');
      expect(proof.repaired, {hash},
          reason: 'wrong bytes must be caught and put right from the '
              'container, which is still authoritative at Step 5');
      expect(proof.damaged, isEmpty);
      expect(proof.ok, isTrue);
      expect(f.readAsBytesSync(), good,
          reason: 'repaired means byte-identical, not merely present');
    });

    // ── A SECOND NEGATIVE CONTROL: no file at all, not merely a corrupt one ──
    //
    // Reported in the field: a notebook's Advanced diagnostics named one
    // blob "missing" — checked, but with the container never asked — after
    // the notebook had already been open (and its own on-open backfill
    // already run) for a while. An antivirus quarantine, a cloud client
    // evicting a file it thinks it can re-fetch, a person tidying the folder
    // by hand: any of them deletes a file from `blobs/` well after the
    // notebook's own backfill already finished, and nothing re-ran it for
    // just that one hash — `missingBlobs()` used to trust that backfill had
    // already tried and skip straight to reporting a hole a fresh copy
    // would have closed for free.
    test('a blob missing from blobs/ but present in the container is '
        'repaired, not just reported', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb) = await fixture('onote_blob_missingfile_');

      final good = picture(4, size: 400);
      final hash = app.importBlob(nb, good, 'image/png');
      repo.putContainerBlobForTest(nb, good, 'image/png');
      await app.settleBackgroundWork();

      final f = logOf(repo, nb).blobFile(hash);
      expect(f.existsSync(), isTrue);
      f.deleteSync();

      final proof = await app.proveBlobBytes(nb);
      expect(proof.missing, isEmpty,
          reason: 'the container could still supply it — a hole a fresh '
              'copy closes for free must not be reported as one, and must '
              'not wait for the notebook to be closed and reopened');
      expect(proof.repaired, {hash},
          reason: 'the SAME repair a corrupted file gets, for a file that '
              'is simply not there at all');
      expect(proof.damaged, isEmpty);
      expect(proof.ok, isTrue);
      expect(f.existsSync(), isTrue);
      expect(f.readAsBytesSync(), good,
          reason: 'repaired means the file exists again with the right '
              'bytes, not just a clean report');
      expect(app.saveError, isNull,
          reason: 'a fully repaired notebook must not still show a save '
              'problem — the whole point of self-healing is that the user '
              'never sees this one');
    });

    test('wrong bytes that cannot be repaired are reported, not left looking ok',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb) = await fixture('onote_blob_damaged_');

      // A blob the LOG names but the container never held — the state a
      // notebook is in after Step 6 stops writing the table, and the state a
      // joined notebook whose peer never sent the bytes is in today. Recorded
      // through the recorder directly so nothing puts a row in `blobs`.
      final r = (await app.warmRecorder(nb))!;
      final bytes = picture(9, size: 256);
      final hash = sha256Hex(bytes);
      r.blob(hash, 'image/png', bytes.length, bytes);
      final f = logOf(repo, nb).blobFile(hash);
      expect(f.existsSync(), isTrue);
      f.writeAsBytesSync(Uint8List(bytes.length), flush: true);

      final proof = await app.proveBlobBytes(nb);
      expect(proof.damaged, {hash});
      expect(proof.repaired, isEmpty);
      expect(proof.ok, isFalse,
          reason: 'this is the answer Step 7 must refuse to proceed through');
      expect(proof.holes, 1);
    });

    test('bytes that are gone entirely are reported too', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb) = await fixture('onote_blob_gone_');

      final r = (await app.warmRecorder(nb))!;
      final bytes = picture(11, size: 128);
      final hash = sha256Hex(bytes);
      r.blob(hash, 'image/png', bytes.length, bytes);
      logOf(repo, nb).blobFile(hash).deleteSync();

      final proof = await app.proveBlobBytes(nb);
      expect(proof.missing, {hash});
      expect(proof.ok, isFalse);
    });
  });

  group('what the student is told, and how long the app is frozen for', () {
    test('the sentence is plain words, with the technical half folded away',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb) = await fixture('onote_blob_words_');

      final r = (await app.warmRecorder(nb))!;
      final bytes = picture(5, size: 64);
      final hash = sha256Hex(bytes);
      r.blob(hash, 'image/png', bytes.length, bytes);
      logOf(repo, nb).blobFile(hash).deleteSync();
      await app.proveBlobBytes(nb);

      final problem = app.saveError;
      expect(problem, isNotNull,
          reason: 'a hole in the second copy has to reach the status bar; '
              'silence here is exactly how 378 blobs went missing unnoticed');
      // Same bar as `save_problem_dialog.dart` and `open_notice_dialog.dart`:
      // a year-10 student reads this sentence.
      for (final jargon in const [
        'blob',
        'hash',
        'SHA',
        'sha256',
        'materialis',
        'backfill',
        'SQLite',
        'container',
        'op log',
        '.onotebook',
        'Exception',
      ]) {
        expect(problem!.message.toLowerCase(), isNot(contains(jargon.toLowerCase())),
            reason: 'the plain sentence must not contain "$jargon"');
        expect(problem.short.toLowerCase(), isNot(contains(jargon.toLowerCase())));
      }
      expect(problem!.message, contains('picture'));
      expect(problem.message, contains('could not find good bytes'),
          reason: 'it must say plainly that THIS computer does not have '
              'good bytes either — a hash reaches here only once the '
              'container has already been tried and failed, so telling the '
              'reader the picture is "still fine on this computer" would be '
              'false reassurance over an actually lost picture');
      expect(problem.message, contains('disk is not full'),
          reason: 'and what the reader can actually do');
      expect('$problem', problem.message,
          reason: 'interpolating a problem must not leak the technical detail '
              'onto the status bar');
      expect(problem.short.length, lessThan(40),
          reason: 'the status bar chip has room for a few words');
      // The technical half exists, and only behind Advanced.
      expect(problem.details, isNotNull);
      expect(problem.details, contains(nb));
      expect(problem.details, contains(hash));
    });

    test('proving coverage gives the app turns to paint and type in', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (_, app, nb) = await fixture('onote_blob_paced_');

      for (var i = 0; i < 20; i++) {
        app.importBlob(nb, picture(i, size: 4096), 'image/png');
      }
      // **One big one, and it is the whole cell.** Hashing is CPU, so a
      // per-file yield cannot divide a single large file: on the owner's
      // Honours-4 the worst blob is 1.8 MB of binary ink and re-hashing it on
      // the UI isolate is a 164 ms freeze by itself. Twenty small files would
      // pass whether or not the hashing runs off-thread.
      app.importBlob(nb, picture(99, size: 4 * 1024 * 1024), 'image/png');
      await app.settleBackgroundWork();

      // The measurement commits 7851c3d and 75e0380 established: a real timer,
      // and the longest gap between its ticks is the longest the window was
      // frozen for. `Duration.zero` would make this counter unable to move at
      // all on Windows, where a zero timer is posted work due immediately and
      // the Win32 message loop never goes idle.
      var ticks = 0;
      var worstMs = 0;
      var last = DateTime.now();
      final timer = Timer.periodic(const Duration(milliseconds: 1), (_) {
        final now = DateTime.now();
        final gap = now.difference(last).inMilliseconds;
        if (gap > worstMs) worstMs = gap;
        last = now;
        ticks++;
      });
      addTearDown(timer.cancel);

      final proof = await app.proveBlobBytes(nb);
      timer.cancel();

      expect(proof.checked, 21);
      expect(proof.ok, isTrue);
      expect(ticks, greaterThan(10),
          reason: 'the window has to get turns while the proof runs');
      expect(worstMs, lessThan(150),
          reason: 'worst single block. Hash the 4 MB blob on this isolate '
              'instead and this is ~360 ms — one visibly dropped frame per '
              'large drawing, at every open');
      // ignore: avoid_print
      print('[step5] proveBlobs 21 blobs (one 4 MB): ticks=$ticks '
          'worstBlockMs=$worstMs');
      // `retry`, because the meter is wall-clock: on an oversubscribed CI
      // runner the OS can starve this isolate long enough to blow the budget
      // with the code entirely correct. The mutation this test exists for —
      // hashing the 4 MB blob ON this isolate — blocks deterministically on
      // every attempt, so a retry cannot launder it.
    }, retry: 2);

    test('materialising a whole notebook of pictures does not freeze the app',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb) = await fixture('onote_blob_backfill_paced_');

      // Honours-4's shape: everything in the container, nothing in `blobs/`,
      // so the open has 40 files to write and then 40 to re-hash. On the real
      // notebook that is 378 files and 26.3 MB, all of it on the UI isolate.
      for (var i = 0; i < 40; i++) {
        repo.putContainerBlobForTest(nb, picture(i, size: 4096), 'image/png');
      }
      await app.settleBackgroundWork();

      var ticks = 0;
      var worstMs = 0;
      var last = DateTime.now();
      final timer = Timer.periodic(const Duration(milliseconds: 1), (_) {
        final now = DateTime.now();
        final gap = now.difference(last).inMilliseconds;
        if (gap > worstMs) worstMs = gap;
        last = now;
        ticks++;
      });
      addTearDown(timer.cancel);

      final app2 = AppState(repo)..notebookId = nb;
      addTearDown(app2.settleBackgroundWork);
      await app2.warmRecorder(nb);
      await app2.settleBackgroundWork();
      timer.cancel();

      expect(app2.syncMissingBlobs(nb), isEmpty);
      expect(ticks, greaterThan(20),
          reason: 'the backfill fsyncs once per blob; unpaced, a real '
              'notebook is hundreds of them in one turn of the event loop');
      expect(worstMs, lessThan(500),
          reason: 'worst single block, including the log replay the warm does '
              'before the backfill starts');
      // ignore: avoid_print
      print('[step5] backfill+prove 40 blobs: ticks=$ticks '
          'worstBlockMs=$worstMs');
      // Same rule as the meter above: wall-clock budgets retry, because an
      // oversubscribed runner can starve a correct implementation past them;
      // the unpaced-backfill mutation blocks on every attempt regardless.
    }, retry: 2);
  });

  group('the folder Openote writes is the folder it checks', () {
    test('an unreadable blob is not counted as matching', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb) = await fixture('onote_blob_unreadable_');

      final hash = app.importBlob(nb, picture(2), 'image/png');
      await app.settleBackgroundWork();
      final store = logOf(repo, nb);
      expect(store.blobBytesMatch(hash), isTrue);

      // A directory where the file belongs: `existsSync()` on a File is false
      // for a directory, so this is the "absent" answer, never "matched".
      store.blobFile(hash).deleteSync();
      Directory(p.join(store.blobsDir.path, hash)).createSync();
      expect(store.blobBytesMatch(hash), isFalse,
          reason: '"I could not check" must never read as "it matched"');
    });
  });

  group('the proof is background work, and background work must not throw', () {
    test('a notebook that leaves mid-proof is moot, not a crash', () async {
      // The backfill-then-prove chain `_startBlobBackfill` builds is awaited
      // by NOBODY unless a mirror happens to be waiting on it, and its proof
      // half used to have no handler: an error there was an unhandled async
      // error. Under `flutter test` that fails whichever test is running when
      // it lands — the Windows CI runner is slow enough that the chain lost
      // its race against test teardown on most pushes, turning six unrelated
      // tests red with "no notebook file at …" AFTER they had completed. In
      // the app the same throw is a crash report for background work against
      // a notebook the user had already deleted or moved.
      //
      // This is that race made DETERMINISTIC. The proof's repair read happens
      // strictly after its first `_hashFiles` batch, which is an isolate
      // round-trip away — so everything below the warm runs first, and the
      // container is reliably gone by the time the proof reaches for it.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb) = await fixture('onote_blob_gone_');
      final hash = app.importBlob(nb, picture(7), 'image/png');
      await app.settleBackgroundWork(); // blobs/ holds it; the log knows it

      // Wrong bytes under the right name: the proof MUST reach for the
      // container to repair. (Absent would be `missing`, which never reads.)
      final store = logOf(repo, nb);
      store.blobFile(hash).writeAsBytesSync(picture(8), flush: true);

      // A fresh session starts the chain. Its backfill half copies nothing —
      // the file exists — so the container is not touched until the proof.
      final app2 = AppState(repo)..notebookId = nb;
      addTearDown(app2.settleBackgroundWork);
      await app2.warmRecorder(nb);

      // The notebook leaves before the proof's read: handle closed, container
      // gone — a purge, a move in Explorer, or a teardown, mid-chain.
      final file = repo.notebooks.firstWhere((n) => n.id == nb).file;
      repo.closeNotebook(nb);
      File(file).deleteSync();

      // MUTATION: remove the try/catch around the proof stage in
      // `_startBlobBackfill` and the chain's NotebookFileMissing lands in
      // this test's zone as an unhandled error — red exactly as CI was.
      await app2.settleBackgroundWork();
      expect(app2.saveError, isNull,
          reason: 'a notebook that left mid-proof is moot: no report, and '
              'certainly no throw into the void');
    });
  });
}
