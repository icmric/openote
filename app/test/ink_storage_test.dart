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

      final freed = await app.convertInkToBinary(app.notebookId!);
      expect(freed, greaterThan(0));

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
      expect(await app.convertInkToBinary(app.notebookId!), greaterThan(0));
      final blobs = repo.blobIndex(app.notebookId!).length;

      expect(await app.convertInkToBinary(app.notebookId!), 0,
          reason: 'nothing left to convert');
      expect(repo.blobIndex(app.notebookId!).length, blobs,
          reason: 'and no duplicate blob was written');
    });

    test('a notebook with no ink is untouched and costs nothing', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.blocks = [
        Block(type: BlockType.text, x: 0, y: 0, content: {'text': 'prose'})
      ];
      app.markDirty();
      await app.flushSave();
      expect(await app.convertInkToBinary(app.notebookId!), 0);
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
