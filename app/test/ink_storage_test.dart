// Ink through a real save and load, and what the disk holds afterwards.
//
// The codec is tested in isolation in ink_codec_test.dart. This is the part
// that changes users' files: a page saved with handwriting must come back with
// the same handwriting, the container must be dramatically smaller, and — the
// finding that made this dangerous — the OPERATION LOG must be able to
// reconstruct it, which it can only do if the bytes were written there too.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/ink/ink_codec.dart';
import 'package:openote/ink/ink_storage.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/sync/op.dart';
import 'package:openote/sync/op_log.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Repository repo;
  late Directory tmp;
  late AppState app;
  late String pageId;

  setUp(() async {
    if (!haveSqlite) return;
    tmp = Directory.systemTemp.createTempSync('onote_inkstore_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Ink');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
    app.pageId = pageId;
  });

  tearDown(() {
    if (!haveSqlite) return;
    app.cancelPendingSave();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Handwriting shaped like real imported ink.
  List<Stroke> handwriting({int count = 60, int seed = 3}) {
    final rnd = Random(seed);
    return [
      for (var s = 0; s < count; s++)
        () {
          final n = 8 + rnd.nextInt(40);
          var x = 120 + rnd.nextDouble() * 700;
          var y = 90 + rnd.nextDouble() * 500;
          final xs = <double>[], ys = <double>[], ps = <double>[];
          for (var i = 0; i < n; i++) {
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

  Block inkBlock(List<Stroke> strokes) => Block(
        id: 'ink-1',
        type: BlockType.ink,
        x: 100,
        y: 80,
        w: 800,
        h: 600,
        content: {'strokes': [for (final s in strokes) s.toJson()]},
      );

  test('handwriting survives a save and a reload', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final strokes = handwriting();
    app.blocks = [inkBlock(strokes)];
    app.markDirty();
    await app.flushSave();

    // Out of the container, through the same path the editor uses.
    final back = repo.readPage(app.notebookId!, pageId);
    final b = back.blocks.single;
    expect(b.type, BlockType.ink);
    final list = b.content['strokes'] as List;
    expect(list.length, strokes.length, reason: 'every stroke comes back');

    for (var i = 0; i < strokes.length; i++) {
      final got = Stroke.fromJson((list[i] as Map).cast<String, dynamic>());
      expect(got.x.length, strokes[i].x.length);
      for (var k = 0; k < got.x.length; k++) {
        expect(got.x[k], closeTo(strokes[i].x[k], 1 / (2 * kInkScale)));
        expect(got.y[k], closeTo(strokes[i].y[k], 1 / (2 * kInkScale)));
      }
      expect(got.colorHex.toUpperCase(), '#211F1B');
      expect(got.size, closeTo(2.5, 1 / 64));
    }
  });

  test('THE PAGE JSON NO LONGER CONTAINS THE STROKES', () async {
    // The whole point. 63 MB of a real notebook was stroke arrays in this
    // column, and the same arrays again in the op log.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.blocks = [inkBlock(handwriting(count: 200))];
    app.markDirty();
    await app.flushSave();

    final row = repo
        .rawPageJsonForTest(app.notebookId!, pageId);
    expect(row, isNotNull);
    expect(row!, isNot(contains('"strokes"')),
        reason: 'the page mirror must hold a reference, not the geometry');
    expect(row, contains('"ink"'));
    expect(row, contains('"base"'));
    // A generous bound: 200 strokes of real geometry as JSON is hundreds of
    // kilobytes, and the reference form is a few hundred bytes.
    expect(row.length, lessThan(4000),
        reason: 'page JSON was ${row.length} bytes');
  });

  test('THE OP LOG CAN REBUILD IT — the bytes are in blobs/, not just SQLite',
      () async {
    // The trap this test exists for: `Repository.putBlob` writes only the
    // container's `blobs` table and emits no `blob.put` op. Ink written that
    // way is invisible to the log, so a notebook rebuilt from its log — which
    // is exactly what joining from a git URL does — would come back with the
    // handwriting missing. Locally everything would look fine.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.blocks = [inkBlock(handwriting(count: 40))];
    app.markDirty();
    await app.flushSave();

    final ref = repo.notebooks.firstWhere((n) => n.id == app.notebookId);
    final store = OpLogStore.forNotebook(ref.file, logDir: ref.logDir);

    // The op stream declares the blob…
    final puts = store
        .readAll()
        .where((o) => o.kind == OpKind.blobPut)
        .toList();
    expect(puts, isNotEmpty, reason: 'a blob.put must be recorded');
    expect(puts.any((o) => o.map['mime'] == inkMimeType), isTrue,
        reason: 'and it must be the ink blob');

    // …and the bytes are actually there, even though this notebook is in no
    // cloud folder and has no mirror, i.e. `materialiseBlobs` is false.
    expect(app.notebookIsShared(app.notebookId!), isFalse,
        reason: 'a local-only notebook is the case that used to defer bytes');
    final hashes = store.blobHashes();
    expect(hashes, isNotEmpty,
        reason: 'ink bytes must be written regardless of sharing — the log '
            'cannot rebuild a notebook whose handwriting it only references');

    // Prove it end to end: decode straight from the log's blob store.
    final blockJson = jsonDecode(
        repo.rawPageJsonForTest(app.notebookId!, pageId)!) as Map;
    final content = ((blockJson['blocks'] as List).single as Map)['content']
        as Map;
    final base = (content['ink'] as Map)['base'] as String;
    final bytes = store.readBlob(base.replaceFirst('sha256:', ''));
    expect(bytes, isNotNull, reason: 'the log holds the actual geometry');
    expect(InkCodec.decodeHeader(bytes!).strokeCount, 40);
  });

  test('a second save of unchanged ink adds no new blob', () async {
    // Encoding is deterministic, so the same handwriting hashes to the same
    // object. If it did not, every autosave would duplicate the page's ink.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.blocks = [inkBlock(handwriting())];
    app.markDirty();
    await app.flushSave();
    final first = repo.blobIndex(app.notebookId!).length;

    // Reload the way the editor does, then save again untouched.
    final reloaded = repo.readPage(app.notebookId!, pageId);
    app.blocks = reloaded.blocks;
    app.markDirty();
    await app.flushSave();

    expect(repo.blobIndex(app.notebookId!).length, first,
        reason: 'a round trip must be a fixed point, or ink accumulates');
  });

  test('the page declares its ink in blob_refs', () async {
    // ADR-0007's garbage collection recomputes what is reachable by scanning
    // pages. A page that does not declare its handwriting is a page whose
    // handwriting would be collected.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.blocks = [inkBlock(handwriting(count: 12))];
    app.markDirty();
    await app.flushSave();
    expect(repo.blobRefsForTest(app.notebookId!, pageId), isNotEmpty,
        reason: 'the ink blob must be reachable from the page');
  });

  group('converting a notebook that already has JSON ink', () {
    /// Write a page the way a pre-v0.11 build did: inline strokes straight
    /// into the mirror, bypassing the storage boundary entirely.
    void writeLegacyPage(String id, List<Stroke> strokes) {
      repo.writePageRawForTest(app.notebookId!, id, {
        'schema': 'onote-page/1',
        'pageId': id,
        'page': PageProps().toJson(),
        'blocks': [
          Block(
            id: 'legacy-ink',
            type: BlockType.ink,
            x: 100,
            y: 80,
            w: 800,
            h: 600,
            content: {'strokes': [for (final s in strokes) s.toJson()]},
          ).toJson()
        ],
      });
    }

    test('IT IS LOSSLESS, AND THE MIRROR SHRINKS', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final strokes = handwriting(count: 150, seed: 11);
      writeLegacyPage(pageId, strokes);
      final before = repo.pageJsonBytes(app.notebookId!, pageId);
      expect(before, greaterThan(50000),
          reason: 'the fixture must be big enough to be worth converting');

      final r = await app.convertInkToBinary(app.notebookId!);
      expect(r.converted, 1);
      expect(r.failed, 0);
      expect(r.freed, greaterThan(0));
      expect(r.didNothing, isFalse);

      final after = repo.pageJsonBytes(app.notebookId!, pageId);
      expect(after, lessThan(before ~/ 10),
          reason: 'page JSON $before -> $after bytes');
      expect(repo.rawPageJsonForTest(app.notebookId!, pageId),
          isNot(contains('"strokes"')));

      // Every stroke, every point, still there.
      final back = repo.readPage(app.notebookId!, pageId).blocks.single;
      final list = back.content['strokes'] as List;
      expect(list.length, strokes.length);
      for (var i = 0; i < strokes.length; i++) {
        final got = Stroke.fromJson((list[i] as Map).cast<String, dynamic>());
        expect(got.x.length, strokes[i].x.length, reason: 'stroke $i');
        for (var k = 0; k < got.x.length; k++) {
          expect(got.x[k], closeTo(strokes[i].x[k], 1 / (2 * kInkScale)));
          expect(got.y[k], closeTo(strokes[i].y[k], 1 / (2 * kInkScale)));
        }
      }
      // And the block's own geometry is untouched — a conversion that moved
      // the box would be a visible regression on every imported page.
      expect(back.x, 100);
      expect(back.y, 80);
      expect(back.w, 800);
    });

    test('running it twice does nothing the second time', () async {
      // The prefilter excludes converted pages, so a run interrupted halfway
      // can simply be run again.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      writeLegacyPage(pageId, handwriting(count: 20));
      expect((await app.convertInkToBinary(app.notebookId!)).converted,
          greaterThan(0));
      final blobs = repo.blobIndex(app.notebookId!).length;

      final again = await app.convertInkToBinary(app.notebookId!);
      expect(again.candidates, 0, reason: 'nothing left to convert');
      expect(again.didNothing, isFalse,
          reason: 'no candidates is success, not a silent failure');
      expect(repo.blobIndex(app.notebookId!).length, blobs,
          reason: 'and no duplicate blob was written');
    });

    test('IT IS NOT UNDONE BY A PULL — the reported silent failure', () async {
      // "it seemed to do something for about 45s before the spinner just went
      // away and the button returned back to saying 113 pages."
      //
      // The conversion worked perfectly on a copy and failed every time on the
      // real, SYNCING notebook. A pull rebuilds each changed page from the op
      // log, and the log still holds the pre-conversion giant inline-ink ops —
      // so unless the conversion also RECORDS the new shape, the next pull
      // materialises every page straight back. And `SyncRecorder.page` refuses
      // to record while `foreignPending` is true, which on a syncing notebook
      // it usually is.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      writeLegacyPage(pageId, handwriting(count: 30));

      // A second, real page for the foreign op to land on — page_mirror has a
      // foreign key onto nodes, so an op for a page that does not exist fails
      // the whole pull.
      final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
      final other = repo.upsertNode(app.notebookId!,
          TreeNode(kind: NodeKind.page, parentId: section.id, title: 'Other'));

      final r = await app.warmRecorder(app.notebookId!);
      expect(r, isNotNull);
      final ref = repo.notebooks.firstWhere((n) => n.id == app.notebookId);
      final store = OpLogStore.forNotebook(ref.file, logDir: ref.logDir);
      store.append('some-other-device', [
        Op(
            device: 'some-other-device',
            seq: 1,
            lamport: 900,
            timestamp: 1000,
            kind: OpKind.blockSet,
            data: {
              // A DIFFERENT page: the ink page was written straight into the
              // mirror by the fixture, so the log has never heard of it, and
              // a pull would materialise it as empty. That is a property of
              // the fixture, not of the product — the real notebook's ink IS
              // in its log. What matters here is only that a foreign op is
              // outstanding while the conversion runs.
              'pageId': other.id,
              'block': {'id': 'theirs', 'type': 'text', 'x': 0, 'y': 400,
                'content': {'text': 'from the other machine'}}
            })
      ]);

      // RAISE THE FLAG the way the running app does: the watcher fires a pull,
      // which asks pendingForeignOps, which sets foreignPending — and from
      // that moment SyncRecorder.page records nothing at all.
      expect(await r!.pendingForeignOps(repo.getSetting), isNotEmpty);
      expect(r.foreignPending, isTrue,
          reason: 'this is the state a syncing notebook is usually in');

      final result = await app.convertInkToBinary(app.notebookId!);
      // Either it folded their op first and converted, or it declined and
      // said why — never 45 seconds of work reported as nothing.
      expect(result.didNothing, isFalse,
          reason: 'a run that changes nothing must say so: '
              '${result.firstError}');
      expect(result.converted, greaterThan(0));

      // THE LOG LEARNED THE NEW SHAPE. Without this the next pull rebuilds
      // every page from the log's giant inline ops and undoes the lot.
      final logged = store
          .readAll()
          .where((o) => o.kind == OpKind.blockSet)
          .where((o) => (o.map['pageId']) == pageId)
          .toList();
      expect(logged, isNotEmpty,
          reason: 'the conversion was never recorded, so a pull will revert it');
      final lastContent = ((logged.last.map['block'] as Map)['content'] as Map)
          .cast<String, dynamic>();
      expect(InkStorage.isRefForm(lastContent), isTrue,
          reason: 'the log must hold the reference form, not the strokes');

      // And the conversion SURVIVES the next pull, which is the actual bug.
      await app.syncPull(app.notebookId!);
      expect(repo.pageIdsWithInlineInk(app.notebookId!), isEmpty,
          reason: 'a pull rebuilt the page from the log and put the inline '
              'strokes back — 45 seconds of work undone');
      expect(repo.rawPageJsonForTest(app.notebookId!, pageId),
          isNot(contains('"strokes"')));
    });

    test('a notebook with no ink is untouched and costs nothing', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.blocks = [
        Block(type: BlockType.text, x: 0, y: 0, content: {'text': 'prose'})
      ];
      app.markDirty();
      await app.flushSave();
      expect((await app.convertInkToBinary(app.notebookId!)).candidates, 0);
      expect(repo.readPage(app.notebookId!, pageId).blocks.single.content['text'],
          'prose');
    });

    test('the log learns the new shape too', () async {
      // Otherwise a rebuild would still produce the old giant blocks, and the
      // container and the log would disagree about the same page — which is
      // the divergence shadow mode exists to prevent.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      writeLegacyPage(pageId, handwriting(count: 25));
      await app.convertInkToBinary(app.notebookId!);

      final ref = repo.notebooks.firstWhere((n) => n.id == app.notebookId);
      final store = OpLogStore.forNotebook(ref.file, logDir: ref.logDir);
      final sets = store
          .readAll()
          .where((o) => o.kind == OpKind.blockSet)
          .toList();
      expect(sets, isNotEmpty);
      final content =
          ((sets.last.map['block'] as Map)['content'] as Map).cast<String, dynamic>();
      expect(content.containsKey('strokes'), isFalse,
          reason: 'the recorded block must carry the reference');
      expect(InkStorage.refsOf(content), isNotEmpty);
      // And the bytes it references are in the log's blob store.
      final hash = InkStorage.refsOf(content).first;
      expect(store.readBlob(hash.replaceFirst('sha256:', '')), isNotNull);
    });
  });

  group('unattended housekeeping', () {
    // The same feature run by a timer instead of a button, which changes the
    // safety contract entirely: the manual path is safe because the sync
    // dialog is MODAL — no editable surface is live during the run. Unattended
    // there is no modality, so the run must be a guest: never touch the open
    // page, never touch the editor's memory, and step aside the moment the
    // user does anything.

    void writeLegacyPage(String id, List<Stroke> strokes) {
      repo.writePageRawForTest(app.notebookId!, id, {
        'schema': 'onote-page/1',
        'pageId': id,
        'page': PageProps().toJson(),
        'blocks': [
          Block(
            id: 'legacy-ink',
            type: BlockType.ink,
            x: 100,
            y: 80,
            w: 800,
            h: 600,
            content: {'strokes': [for (final s in strokes) s.toJson()]},
          ).toJson()
        ],
      });
    }

    String otherPage(String title) {
      final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
      return repo
          .upsertNode(app.notebookId!,
              TreeNode(kind: NodeKind.page, parentId: section.id, title: title))
          .id;
    }

    test('TYPING AT THE WRONG MOMENT DEFERS — IT DOES NOT DISABLE', () async {
      // The shipped guard read `!_housekept.add(nb)` BEFORE checking
      // `_dirty`, so one keystroke at the twenty-second mark consumed the
      // session's only attempt and stamped nothing. The notebooks most in
      // need of tidying are the actively used ones — which are exactly the
      // ones where the user is mid-sentence when the timer fires.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      writeLegacyPage(otherPage('Other'), handwriting(count: 20, seed: 21));

      app.markDirty(); // the user is mid-sentence when the timer fires
      await app.runHousekeepingForTest(app.notebookId!);
      app.cancelPendingSave(); // drop the deferral retry the test won't wait for
      expect(repo.getSetting('tidiedAt:${app.notebookId}'), isNull,
          reason: 'busy is a deferral, not a completed pass');
      expect(repo.pageIdsWithInlineInk(app.notebookId!), isNotEmpty,
          reason: 'nothing was converted while the user was typing');

      await app.flushSave(); // the typing stopped
      await app.runHousekeepingForTest(app.notebookId!);
      app.cancelPendingSave();
      expect(repo.pageIdsWithInlineInk(app.notebookId!), isEmpty,
          reason: 'the same session finished the work once things went quiet');
      expect(repo.getSetting('tidiedAt:${app.notebookId}'), isNotNull);
    });

    test('THE OPEN PAGE AND THE EDITOR\'S MEMORY ARE NEVER TOUCHED', () async {
      // The manual path ends by re-reading the open page from disk into
      // `blocks`. Run from a timer, that discards whatever the user typed
      // during the run — unboundedly, if an earlier save failed and `blocks`
      // is holding unsaved work. Unattended, the open page is excluded from
      // the run entirely, so there is nothing to re-read and no way to lose.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      writeLegacyPage(pageId, handwriting(count: 15, seed: 22)); // OPEN page
      final other = otherPage('Other');
      writeLegacyPage(other, handwriting(count: 20, seed: 23));
      final editorBlocks = app.blocks;

      await app.runHousekeepingForTest(app.notebookId!);
      app.cancelPendingSave();

      expect(identical(app.blocks, editorBlocks), isTrue,
          reason: 'unattended must never swap the editor state from disk');
      expect(repo.rawPageJsonForTest(app.notebookId!, other),
          isNot(contains('"strokes":[{')),
          reason: 'every page the user is NOT looking at converts');
      expect(repo.rawPageJsonForTest(app.notebookId!, pageId),
          contains('"strokes":[{'),
          reason: 'the page on screen is not rewritten behind the user — '
              'its next ordinary save converts it through persistAll');
      expect(repo.getSetting('tidiedAt:${app.notebookId}'), isNotNull,
          reason: 'leaving the open page for its next save still completes '
              'the pass');
    });

    test('the vacuum is owed to shutdown, not run on the timer', () async {
      // reclaimFreeSpace is a synchronous whole-file rewrite whose own doc
      // comment says it "runs from an explicit user action rather than on a
      // timer". On a timer it froze the window for seconds with no dialog
      // explaining why. Deferred to shutdown, there is no interface to freeze.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      writeLegacyPage(otherPage('Other'), handwriting(count: 20, seed: 24));

      await app.runHousekeepingForTest(app.notebookId!);
      app.cancelPendingSave();
      expect(repo.getSetting('vacuumPending:${app.notebookId}'), isTrue,
          reason: 'the debt is recorded rather than paid mid-session');

      await app.shutdown();
      expect(repo.getSetting('vacuumPending:${app.notebookId}'), isNull,
          reason: 'shutdown pays it and clears the flag');
    });

    test('a keystroke mid-run stops the run where it stands', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      for (var i = 0; i < 3; i++) {
        writeLegacyPage(otherPage('P$i'), handwriting(count: 15, seed: 30 + i));
      }

      var fired = 0;
      final r = await app.convertInkToBinary(app.notebookId!,
          unattended: true,
          onProgress: (done, total) {
            if (++fired == 1) app.markDirty(); // keystroke after page one
          });
      app.cancelPendingSave();

      expect(r.deferred, isTrue,
          reason: 'stopping for the user is a deferral, not a failure');
      expect(r.converted, 1,
          reason: 'the page in flight finishes; nothing further starts');
      expect(repo.pageIdsWithInlineInk(app.notebookId!), hasLength(2),
          reason: 'the rest waits, durable exactly as it was');
    });

    test('a deferred result says why instead of "nothing left"', () {
      // The decline used to fall through to candidates == 0, which describe()
      // rendered as "Nothing left to shrink." beside a button still counting
      // 113 pages.
      const r = InkConversionResult(
          candidates: 0,
          converted: 0,
          failed: 0,
          freed: 0,
          firstError: 'there are changes from another device still to fold in',
          deferred: true);
      expect(r.describe((b) => '$b'), contains('another device'));
      expect(r.didNothing, isFalse,
          reason: 'deferral is not the silent-failure state');
    });
  });

  group('the storage boundary on its own', () {
    test('a missing blob leaves the reference alone', () {
      // A notebook joined from a remote can legitimately hold a ref whose
      // bytes have not arrived. Returning an empty stroke list would let the
      // next save overwrite the reference with nothing — losing the ink for
      // everyone, permanently.
      final content = <String, dynamic>{
        'ink': {'v': 1, 'base': 'sha256:deadbeef', 'n': 5, 'o': [0, 0]}
      };
      final out = InkStorage.toWorking(content, (_) => null);
      expect(out, same(content), reason: 'unchanged, ref intact');
      expect(InkStorage.strokeCount(out), 5,
          reason: 'and it still knows how much is missing');
    });

    test('an unparseable stroke stops the conversion rather than dropping it',
        () {
      final content = <String, dynamic>{
        'strokes': [
          {'nonsense': true}
        ]
      };
      var called = false;
      final out = InkStorage.toPersisted(content, (_) {
        called = true;
        return 'x';
      });
      expect(out, same(content),
          reason: 'left legacy: it still renders and still saves');
      expect(called, isFalse, reason: 'nothing was written');
    });

    test('A ROUND TRIP DOES NOT PUT THE STROKES BACK ON DISK', () {
      // The bug that made the whole feature a no-op, and it was invisible
      // because everything still WORKED — the strokes were simply written
      // twice. `toWorking` adds a decoded `strokes` list beside the `ink`
      // descriptor so the painter and the exporters see what they always saw;
      // `toPersisted` then returned that untouched because it was already a
      // reference, so a converted page grew its geometry straight back on the
      // next save. The notebook never actually shrank, and every page stayed a
      // candidate the conversion would then refuse:
      //
      //   "it could not shrink any of the 113 pages — a page matched the
      //    search but held no convertable handwriting"
      final strokes = [
        Stroke(
            id: 'a',
            tool: 'pen',
            colorHex: '#211F1B',
            size: 2,
            x: [1, 2, 3],
            y: [1, 2, 3])
      ];
      final store = <String, Uint8List>{};
      final persisted = InkStorage.toPersisted(
          <String, dynamic>{'strokes': [for (final s in strokes) s.toJson()]},
          (bytes) {
        const hash = 'sha256:aa';
        store[hash] = bytes;
        return hash;
      });
      expect(persisted.containsKey('strokes'), isFalse);

      // Read it the way the editor does…
      final working = InkStorage.toWorking(persisted, (h) => store[h]);
      expect(working['strokes'], isA<List>(),
          reason: 'consumers must still see strokes');

      // …and save it again. THIS is where the geometry used to come back.
      final again = InkStorage.toPersisted(working, (_) {
        fail('an unchanged reference must not write a second blob');
      });
      expect(again.containsKey('strokes'), isFalse,
          reason: 'the working strokes must not reach the disk');
      expect(InkStorage.refsOf(again), InkStorage.refsOf(persisted),
          reason: 'and it is still the same ink');
    });

    test('counting strokes never opens a blob', () {
      var opened = false;
      final content = <String, dynamic>{
        'ink': {'v': 1, 'base': 'sha256:aa', 'n': 4096, 'o': [0, 0]}
      };
      expect(InkStorage.strokeCount(content), 4096);
      expect(opened, isFalse);
    });

    test('an empty ink block round-trips without a blob', () {
      final out =
          InkStorage.toPersisted(<String, dynamic>{'strokes': []}, (_) {
        fail('an empty block must not write a blob');
      });
      expect(InkStorage.strokeCount(out), 0);
      expect(InkStorage.toWorking(out, (_) => null)['strokes'], isEmpty);
    });
  });
}
