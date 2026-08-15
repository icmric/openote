// Noticing that another device wrote — the part that silently did not work.
//
// Reported: "If i make an edit on one machine it seems like that change doesnt
// really ever get reflected on the other machine … For a change to be
// reflected i have to press the little sync button."
//
// Writing was fine and the manual pull was fine; only the notification was
// missing, and nothing in the suite covered it. The watcher's own doc comment
// said a cloud client "often renames a temp file over it" — and the filter then
// dropped exactly that, because a temp name does not end in `.oplog` and
// `FileSystemMoveEvent.path` is the SOURCE, not the destination.
//
// So these tests write logs the way a cloud client actually writes them.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/sync/folder_watch.dart';
import 'package:openote/sync/op.dart';
import 'package:openote/sync/op_log.dart';

void main() {
  late Directory ops;
  const own = 'device-mine';
  const other = 'device-theirs';

  setUp(() => ops = Directory.systemTemp.createTempSync('onote_watch_'));
  tearDown(() {
    try {
      ops.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// A watcher whose poll is fast enough to test, wired to a counter.
  ({OpFolderWatcher w, List<int> fired}) watcher({
    Duration settle = const Duration(milliseconds: 20),
    Duration poll = const Duration(milliseconds: 40),
  }) {
    final fired = <int>[];
    final w = OpFolderWatcher(
      opsDir: ops,
      ownDevice: own,
      settle: settle,
      pollEvery: poll,
      onForeignChange: () => fired.add(1),
    );
    return (w: w, fired: fired);
  }

  /// Long enough for a debounce, a poll tick and a filesystem event to land.
  Future<void> settleAll() =>
      Future<void>.delayed(const Duration(milliseconds: 400));

  test('a plain write to a foreign log is noticed', () async {
    final (w: w, fired: fired) = watcher();
    w.start();
    addTearDown(w.stop);
    await settleAll();
    fired.clear();

    File('${ops.path}/$other.oplog').writeAsStringSync('{"op":"x"}\n');
    await settleAll();
    expect(fired, isNotEmpty);
  });

  test('A CLOUD CLIENT\'S TEMP-FILE RENAME IS NOTICED', () async {
    // The actual failure. OneDrive and Drive write `<name>.oplog~RF1a2b.TMP`
    // and rename it into place: every event before the rename names a file
    // that does not end in `.oplog`, and the rename event itself carries the
    // TEMP path in `.path` with the real target in `.destination`.
    final (w: w, fired: fired) = watcher();
    w.start();
    addTearDown(w.stop);
    await settleAll();
    fired.clear();

    final tmp = File('${ops.path}/$other.oplog~RF1a2b3c.TMP')
      ..writeAsStringSync('{"op":"x"}\n');
    tmp.renameSync('${ops.path}/$other.oplog');
    await settleAll();

    expect(fired, isNotEmpty,
        reason: 'this is exactly how the sync folder receives a log, and it '
            'produced nothing at all before');
  });

  test('a log that appears while nothing is watching is still noticed',
      () async {
    // A network share, a container, a platform whose notifications do not
    // arrive: the poll is the floor and has to catch it on its own.
    final (w: w, fired: fired) = watcher();
    w.start();
    addTearDown(w.stop);
    await settleAll();
    fired.clear();

    // Same length, different content and mtime — a cloud client can replace a
    // file with one of the same size, which a size-only check would miss.
    final f = File('${ops.path}/$other.oplog')
      ..writeAsStringSync('{"op":"aaa"}\n');
    await settleAll();
    fired.clear();
    f.writeAsStringSync('{"op":"bbb"}\n');
    f.setLastModifiedSync(
        DateTime.now().add(const Duration(seconds: 5)));
    await settleAll();
    expect(fired, isNotEmpty, reason: 'a same-size replacement still counts');
  });

  test('our own writes do not trigger a pull', () async {
    // Otherwise every save schedules a re-read of what was just written.
    final (w: w, fired: fired) = watcher();
    w.start();
    addTearDown(w.stop);
    await settleAll();
    fired.clear();

    File('${ops.path}/$own.oplog').writeAsStringSync('{"op":"mine"}\n');
    await settleAll();
    expect(fired, isEmpty);
  });

  test('arming the watcher does not itself fire', () async {
    // The poll takes a baseline on start; without that, opening any notebook
    // would pull immediately and the freeze would look like part of opening.
    File('${ops.path}/$other.oplog').writeAsStringSync('{"op":"already"}\n');
    final (w: w, fired: fired) = watcher();
    w.start();
    addTearDown(w.stop);
    await settleAll();
    // Darwin gets one firing of grace: FSEvents can deliver an event for a
    // file written just before the stream started listening — the write above
    // is microseconds old when start() runs, and a slow runner sees it echo.
    // In the product that echo costs one pull that finds nothing (the open
    // path folds anyway, and the poll's baseline makes it a no-op), so the
    // claim this test protects — "arming is not a pull storm" — allows it.
    // Windows and Linux watchers do not replay the past, and stay at zero.
    expect(fired.length, lessThanOrEqualTo(Platform.isMacOS ? 1 : 0),
        reason: 'existing logs are the baseline, not news');
  });

  test('a burst of writes produces one pull, not one per write', () async {
    final (w: w, fired: fired) = watcher();
    w.start();
    addTearDown(w.stop);
    await settleAll();
    fired.clear();

    final f = File('${ops.path}/$other.oplog');
    for (var i = 0; i < 8; i++) {
      f.writeAsStringSync('{"op":"$i"}\n', mode: FileMode.append);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await settleAll();
    // Strictly fewer than the eight writes — NOT a pinned coalescing factor.
    // The old `<= 2` encoded an assumption about how the OS batches file
    // events, and macOS FSEvents delivered the same burst as three groups on
    // a slow runner: red CI, working code. The claim this test owns is only
    // that the settle window coalesces AT ALL — one event per write is
    // exactly what a regression to no-debounce produces, and any grouping
    // below that proves the window exists.
    expect(fired.length, lessThan(8),
        reason: 'the settle window exists to coalesce a burst');
  });

  _incremental();

  test('stopping really stops', () async {
    final (w: w, fired: fired) = watcher();
    w.start();
    await settleAll();
    await w.stop();
    fired.clear();

    File('${ops.path}/$other.oplog').writeAsStringSync('{"op":"after"}\n');
    await settleAll();
    expect(fired, isEmpty);
    expect(w.isWatching, isFalse);
  });
}

// ── Reading a foreign log without re-reading all of it ──────────────────

void _incremental() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('onote_incr_'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('resuming from an offset returns only what is new', () async {
    // The cost this removes: `pendingForeignOps` ran `readDevice`, parsing the
    // whole file to discard everything under the watermark — 1,977 ms for one
    // real 64.6 MB log, on the UI thread, on every single pull.
    final store = OpLogStore.forNotebook('${dir.path}/N.onote');
    store.ensureInitialised(notebookId: 'nb', title: 'N');
    Op op(int seq) => Op(
        device: 'them',
        seq: seq,
        lamport: seq,
        timestamp: 1000 + seq,
        kind: OpKind.blockSet,
        data: {'pageId': 'p', 'block': {'id': 'b$seq'}});

    store.append('them', [op(1), op(2)]);
    final first = await store.readDeviceFrom('them', 0);
    expect(first.ops.map((o) => o.seq), [1, 2]);
    expect(first.next, greaterThan(0));

    store.append('them', [op(3)]);
    final second = await store.readDeviceFrom('them', first.next);
    expect(second.ops.map((o) => o.seq), [3],
        reason: 'only the appended op is parsed');

    // Idempotent: nothing new means nothing returned and no movement.
    final third = await store.readDeviceFrom('them', second.next);
    expect(third.ops, isEmpty);
    expect(third.next, second.next);
  });

  test('a torn final line is left for next time, not lost', () async {
    // A cloud client's file routinely ends mid-line. Resuming inside that line
    // would drop the op it belongs to for good.
    final store = OpLogStore.forNotebook('${dir.path}/N.onote');
    store.ensureInitialised(notebookId: 'nb', title: 'N');
    final f = File('${store.opsDir.path}/them.oplog');
    f.writeAsStringSync('{"v":1,"dev":"them","seq":1,"lc":1,"ts":1,'
        '"enc":"none","op":"block.set","d":{"pageId":"p","block":{"id":"b1"}}}\n'
        '{"v":1,"dev":"them","seq":2,"lc":2,"ts":2,"enc":"none","op":"blo');

    final r = await store.readDeviceFrom('them', 0);
    expect(r.ops.map((o) => o.seq), [1], reason: 'only the complete line');

    // The rest arrives; resuming must produce op 2 whole.
    f.writeAsStringSync(
        'ck.set","d":{"pageId":"p","block":{"id":"b2"}}}\n',
        mode: FileMode.append);
    final r2 = await store.readDeviceFrom('them', r.next);
    expect(r2.ops.map((o) => o.seq), [2],
        reason: 'the torn op is recovered, not skipped');
  });

  test('an op bigger than one parse window survives being split across it',
      () async {
    // The parse reads in half-megabyte windows now, and a window that contains
    // no newline at all is NOT a torn tail — it is the middle of one enormous
    // line. Ink is exactly that: `OpKind.inkStrokes` exists because the
    // importer puts a whole page's strokes in one block, "up to several MB
    // serialized". Treating that window as tail would silently drop the op and
    // leave a page of handwriting behind on the other device.
    final store = OpLogStore.forNotebook('${dir.path}/N.onote');
    store.ensureInitialised(notebookId: 'nb', title: 'N');
    final huge = Op(
        device: 'them',
        seq: 1,
        lamport: 1,
        timestamp: 1,
        kind: OpKind.blockSet,
        data: {
          'pageId': 'p',
          'block': {
            'id': 'ink',
            'type': 'ink',
            'content': {'blob': 'z' * (3 * 1024 * 1024)}
          }
        });
    final after = Op(
        device: 'them',
        seq: 2,
        lamport: 2,
        timestamp: 2,
        kind: OpKind.blockSet,
        data: {
          'pageId': 'p',
          'block': {'id': 'small'}
        });
    store.append('them', [huge, after]);

    final r = await store.readDeviceFrom('them', 0);
    expect(r.ops.map((o) => o.seq), [1, 2],
        reason: 'a multi-window line is one op, not a torn tail');
    expect(
        ((r.ops.first.map['block'] as Map)['content'] as Map)['blob'],
        hasLength(3 * 1024 * 1024),
        reason: 'and it came back whole, not spliced at a window boundary');
    expect(r.next, store.logFor('them').lengthSync(),
        reason: 'the resume offset must clear both ops');
  });

  test('THE PARSE YIELDS INSTEAD OF BLOCKING', () async {
    // The offset alone did not make the FIRST read cheap. A git join, a
    // restored offset, a device that just appeared: `from` is 0 and this reads
    // the whole log. Measured on a generated 64.6 MB log, 138,657 ops — 1,008
    // ms in ONE uninterrupted block on the UI thread (read 30 ms, utf8 26 ms,
    // line split 206 ms, `Op.decode` 764 ms). That is the freeze 7851c3d left
    // behind when it paced everything downstream of the parse.
    //
    // **Counted, never clocked**, for the same reason as
    // `cloud_sync_test`'s fold test: a wall-clock bar here measures the
    // runner's weather. What the pacing changes is whether the parse is ONE
    // turn of the event loop or many, so that is what is asserted. Unpaced,
    // a timer running alongside cannot fire at all.
    final store = OpLogStore.forNotebook('${dir.path}/N.onote');
    store.ensureInitialised(notebookId: 'nb', title: 'N');
    final f = File('${store.opsDir.path}/them.oplog');
    final sink = f.openWrite();
    final filler = 'x' * 400;
    for (var seq = 1; seq <= 8000; seq++) {
      sink.write('${Op(
        device: 'them',
        seq: seq,
        lamport: seq,
        timestamp: seq,
        kind: OpKind.blockSet,
        data: {
          'pageId': 'p${seq % 50}',
          'block': {'id': 'b$seq', 'type': 'text', 'content': {'text': filler}}
        },
      ).encode()}\n');
    }
    await sink.flush();
    await sink.close();
    // Several parse windows' worth, or the test proves nothing.
    expect(f.lengthSync(), greaterThan(3 * 1024 * 1024));

    var turns = 0;
    final t = Timer.periodic(const Duration(milliseconds: 1), (_) => turns++);
    final r = await store.readDeviceFrom('them', 0);
    t.cancel();

    expect(r.ops, hasLength(8000), reason: 'and it still parsed everything');
    expect(turns, greaterThan(3),
        reason: 'the parse must give the window turns to paint and type in, '
            'not run as one block');
  });

  test('a log that shrank is re-read from the start', () async {
    // A fresh clone, a restore, a future compaction: an old offset points at
    // a meaningless position and must not be trusted.
    final store = OpLogStore.forNotebook('${dir.path}/N.onote');
    store.ensureInitialised(notebookId: 'nb', title: 'N');
    final f = File('${store.opsDir.path}/them.oplog');
    f.writeAsStringSync('{"v":1,"dev":"them","seq":9,"lc":9,"ts":9,'
        '"enc":"none","op":"block.set","d":{"pageId":"p","block":{"id":"x"}}}\n');
    final r = await store.readDeviceFrom('them', 9000000);
    expect(r.ops.map((o) => o.seq), [9],
        reason: 'an offset past the end means start over, not read nothing');
  });
}
