// The operation log (ADR-0006): envelope, ordering, replay semantics and
// device identity. These need no database and no Flutter binding — the whole
// point of the design is that merging is a pure function of an ordered op list,
// so it should be testable as one.
//
// Properties pinned here are the ones whose failure would be SILENT: a
// non-deterministic sort, a delete that a concurrent edit resurrects, or two
// installations sharing a device id. None of those produce an error; they
// produce replicas that quietly disagree.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openote/sync/device_identity.dart';
import 'package:openote/sync/device_seq.dart';
import 'package:openote/model/models.dart';
import 'package:openote/sync/materializer.dart';
import 'package:openote/sync/op.dart';
import 'package:openote/sync/op_log.dart';
import 'package:openote/sync/sync_recorder.dart';

Op _op(String dev, int seq, int lc, OpKind kind, Map<String, dynamic> d) =>
    Op(device: dev, seq: seq, lamport: lc, timestamp: 1000 + seq, kind: kind, data: d);

void main() {
  group('envelope', () {
    test('round-trips every field', () {
      final op = _op('devA', 7, 42, OpKind.blockSet, {
        'pageId': 'p1',
        'block': {'id': 'b1', 'type': 'text'}
      });
      final back = Op.decode(op.encode())!;
      expect(back.device, 'devA');
      expect(back.seq, 7);
      expect(back.lamport, 42);
      expect(back.timestamp, op.timestamp);
      expect(back.kind, OpKind.blockSet);
      // What this build WRITES, which is not the newest envelope it can read
      // — see `opWriteVersion`. Writing the newer one by default would make
      // every notebook unopenable on the release before this one.
      expect(back.version, opWriteVersion);
      expect(opWriteVersion, lessThan(opFormatVersion));
      expect(back.map['pageId'], 'p1');
    });

    test('reserves the encryption field without using it', () {
      // Nothing is encrypted, but the field must be on the wire from day one:
      // adding it later would mean rewriting every log on every device at once.
      final back = Op.decode(_op('d', 1, 1, OpKind.nodePurge, {'id': 'x'}).encode())!;
      expect(back.encryption, 'none');
    });

    test('a torn final line costs one op, not the file', () {
      // The normal case for an append-only log interrupted by a crash or by a
      // sync client copying mid-write.
      final good = [
        _op('d', 1, 1, OpKind.nodePurge, {'id': 'a'}),
        _op('d', 2, 2, OpKind.nodePurge, {'id': 'b'}),
      ].map((o) => o.encode()).join('\n');
      final torn = '$good\n{"v":1,"dev":"d","seq":3,"lc":3,"op":"node.pu';

      final parsed = [
        for (final line in torn.split('\n'))
          if (Op.decode(line) != null) Op.decode(line)!
      ];
      expect(parsed.length, 2);
      expect(parsed.last.map['id'], 'b');
    });

    test('an op from a newer version survives a round-trip verbatim', () {
      // Character-level text ops will arrive as NEW kinds (ADR-0006 §6a.1). An
      // old device must not corrupt them just because it cannot apply them.
      const line =
          '{"v":1,"dev":"d","seq":1,"lc":1,"ts":5,"enc":"none","op":"text.splice","d":{"at":3}}';
      final op = Op.decode(line)!;
      expect(op.kind, OpKind.unknown);
      expect(Op.decode(op.encode())!.map['at'], 3);
      expect(op.encode(), contains('text.splice'));
    });
  });

  group('ordering', () {
    test('is deterministic regardless of arrival order', () {
      final ops = [
        _op('devB', 1, 5, OpKind.nodePurge, {'id': '1'}),
        _op('devA', 1, 5, OpKind.nodePurge, {'id': '2'}),
        _op('devA', 2, 3, OpKind.nodePurge, {'id': '3'}),
      ];
      final one = [...ops]..sort(Op.compare);
      final two = [...ops.reversed]..sort(Op.compare);
      expect(one.map((o) => o.map['id']).toList(),
          two.map((o) => o.map['id']).toList());
      // Lamport first, then device id as the tie-break that makes it total.
      expect(one.map((o) => o.map['id']).toList(), ['3', '2', '1']);
    });
  });

  group('replay — delete wins (§6a.3)', () {
    test('an edit cannot resurrect a deleted node, whatever the order', () {
      final m = Materializer()
        ..applyAll([
          _op('a', 1, 1, OpKind.nodeUpsert,
              {'id': 'n1', 'kind': 'page', 'title': 'Notes'}),
          _op('a', 2, 2, OpKind.nodeDelete, {'id': 'n1', 'deletedAt': 900}),
          // Concurrent edit from another device that never saw the delete, and
          // which sorts AFTER it. Naive last-writer-wins would bring it back.
          _op('b', 1, 3, OpKind.nodeUpsert, {'id': 'n1', 'title': 'Renamed'}),
        ]);
      expect(m.nodes['n1']!.deletedAt, 900);
      expect(m.nodes['n1']!.title, 'Renamed', reason: 'the edit still applies');
      expect(m.liveNodes(), isEmpty);
    });

    test('only an explicit restore brings it back', () {
      final m = Materializer()
        ..applyAll([
          _op('a', 1, 1, OpKind.nodeUpsert, {'id': 'n1', 'title': 'x'}),
          _op('a', 2, 2, OpKind.nodeDelete, {'id': 'n1'}),
          _op('a', 3, 3, OpKind.nodeRestore, {'id': 'n1'}),
        ]);
      expect(m.nodes['n1']!.deletedAt, isNull);
      expect(m.liveNodes().single.id, 'n1');
    });

    test('purge removes the node and its page outright', () {
      final m = Materializer()
        ..applyAll([
          _op('a', 1, 1, OpKind.nodeUpsert, {'id': 'n1'}),
          _op('a', 2, 2, OpKind.blockSet, {
            'pageId': 'n1',
            'block': {'id': 'b1'}
          }),
          _op('a', 3, 3, OpKind.nodePurge, {'id': 'n1'}),
        ]);
      expect(m.nodes, isEmpty);
      expect(m.pages, isEmpty);
    });
  });

  group('replay — blocks', () {
    test('different blocks of one page merge; same block is last-writer-wins',
        () {
      // This is the case block-level ops exist to solve: two devices editing
      // different blocks of the same page must BOTH survive.
      final m = Materializer()
        ..applyAll([
          _op('a', 1, 1, OpKind.blockSet, {
            'pageId': 'p',
            'block': {'id': 'b1', 'content': 'from A'}
          }),
          _op('b', 1, 2, OpKind.blockSet, {
            'pageId': 'p',
            'block': {'id': 'b2', 'content': 'from B'}
          }),
        ]);
      expect(m.pages['p']!.blocks.keys.toSet(), {'b1', 'b2'});
      expect(m.pages['p']!.blocks['b1']!['content'], 'from A');
      expect(m.pages['p']!.blocks['b2']!['content'], 'from B');
    });

    test('a removed block can be re-added, because undo does exactly that', () {
      // Blocks are deliberately NOT tombstoned, unlike nodes — tombstoning
      // would make undo-after-delete impossible.
      final m = Materializer()
        ..applyAll([
          _op('a', 1, 1, OpKind.blockSet, {
            'pageId': 'p',
            'block': {'id': 'b1', 'content': 'v1'}
          }),
          _op('a', 2, 2, OpKind.blockRemove, {'pageId': 'p', 'blockId': 'b1'}),
          _op('a', 3, 3, OpKind.blockSet, {
            'pageId': 'p',
            'block': {'id': 'b1', 'content': 'v1'}
          }),
        ]);
      expect(m.pages['p']!.blocks['b1']!['content'], 'v1');
    });

    test('an unapplicable op is reported, not silently dropped', () {
      final m = Materializer()
        ..apply(Op.decode(
            '{"v":1,"dev":"d","seq":1,"lc":1,"op":"text.splice","d":{}}')!);
      expect(m.skipped, hasLength(1));
    });

    test('page mirror is emitted in the container\'s shape', () {
      final m = Materializer()
        ..applyAll([
          _op('a', 1, 1, OpKind.pageProps, {
            'pageId': 'p',
            'props': {'background': 'grid'}
          }),
          _op('a', 2, 2, OpKind.blockSet, {
            'pageId': 'p',
            'block': {'id': 'b2'}
          }),
          _op('a', 3, 3, OpKind.blockSet, {
            'pageId': 'p',
            'block': {'id': 'b1'}
          }),
        ]);
      final mirror = m.pageMirror('p');
      expect(mirror['schema'], 'onote-page/1');
      expect(mirror['pageId'], 'p');
      expect((mirror['page'] as Map)['background'], 'grid');
      // Sorted by id, so insertion order can't manufacture a false difference
      // in the rebuild-equals-container check.
      expect([for (final b in mirror['blocks'] as List) b['id']], ['b1', 'b2']);
    });
  });

  group('replay — ink.strokes (per-stroke ops)', () {
    Map<String, dynamic> stroke(String id, double x0) => {
          'id': id,
          'tool': 'pen',
          'x': [x0, x0 + 1],
          'y': [0.0, 1.0],
        };

    Op inkBlock(String dev, int seq, int lc, List<Map<String, dynamic>> ss) =>
        _op(dev, seq, lc, OpKind.blockSet, {
          'pageId': 'p',
          'block': {
            'id': 'ib',
            'type': 'ink',
            'x': 0,
            'y': 0,
            'content': {'strokes': ss}
          }
        });

    test('positional inserts reproduce a mid-list split exactly', () {
      // The eraser replaces one stroke with two fragments AT ITS POSITION.
      // Order is verified verbatim by the shadow check, so an append-only
      // replay would fail on every erase.
      final m = Materializer()
        ..applyAll([
          inkBlock('a', 1, 1, [stroke('s1', 0), stroke('s2', 10), stroke('s3', 20)]),
          _op('a', 2, 2, OpKind.inkStrokes, {
            'pageId': 'p',
            'blockId': 'ib',
            'del': ['s2'],
            'put': [
              {'i': 1, 's': stroke('s2a', 10)},
              {'i': 2, 's': stroke('s2b', 15)},
            ],
          }),
        ]);
      final strokes =
          ((m.pages['p']!.blocks['ib']!['content'] as Map)['strokes'] as List);
      expect([for (final s in strokes) (s as Map)['id']],
          ['s1', 's2a', 's2b', 's3']);
    });

    test('a put upserts: a changed stroke moves to its recorded index', () {
      final m = Materializer()
        ..applyAll([
          inkBlock('a', 1, 1, [stroke('s1', 0), stroke('s2', 10)]),
          _op('a', 2, 2, OpKind.inkStrokes, {
            'pageId': 'p',
            'blockId': 'ib',
            'del': const [],
            'put': [
              {'i': 0, 's': stroke('s2', 99)},
            ],
          }),
        ]);
      final strokes =
          ((m.pages['p']!.blocks['ib']!['content'] as Map)['strokes'] as List);
      expect([for (final s in strokes) (s as Map)['id']], ['s2', 's1']);
      expect(((strokes[0] as Map)['x'] as List).first, 99);
    });

    test('an ink op for a removed block is dropped, not resurrected', () {
      // Same rule as delete-wins: replaying an edit must never recreate what a
      // remove already took away, whatever order the devices' ops arrive in.
      final m = Materializer()
        ..applyAll([
          inkBlock('a', 1, 1, [stroke('s1', 0)]),
          _op('a', 2, 2, OpKind.blockRemove, {'pageId': 'p', 'blockId': 'ib'}),
          _op('b', 1, 3, OpKind.inkStrokes, {
            'pageId': 'p',
            'blockId': 'ib',
            'del': const [],
            'put': [
              {'i': 0, 's': stroke('s9', 5)}
            ],
          }),
        ]);
      expect(m.pages['p']!.blocks.containsKey('ib'), isFalse);
    });

    test('a later block.set fully clobbers earlier stroke ops', () {
      final m = Materializer()
        ..applyAll([
          inkBlock('a', 1, 1, [stroke('s1', 0)]),
          _op('a', 2, 2, OpKind.inkStrokes, {
            'pageId': 'p',
            'blockId': 'ib',
            'del': const [],
            'put': [
              {'i': 1, 's': stroke('s2', 10)}
            ],
          }),
          inkBlock('a', 3, 3, [stroke('s7', 70)]),
        ]);
      final strokes =
          ((m.pages['p']!.blocks['ib']!['content'] as Map)['strokes'] as List);
      expect([for (final s in strokes) (s as Map)['id']], ['s7']);
    });

    test('rect and updatedAt ride along', () {
      final m = Materializer()
        ..applyAll([
          inkBlock('a', 1, 1, [stroke('s1', 0)]),
          _op('a', 2, 2, OpKind.inkStrokes, {
            'pageId': 'p',
            'blockId': 'ib',
            'del': const [],
            'put': const [],
            'rect': {'x': 5, 'y': 6, 'w': 100, 'h': 40},
            'updatedAt': 12345,
          }),
        ]);
      final b = m.pages['p']!.blocks['ib']!;
      expect([b['x'], b['y'], b['w'], b['h']], [5, 6, 100, 40]);
      expect(b['updatedAt'], 12345);
    });
  });

  group('log store', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('onote_oplog'));
    // Guarded like the other ~90 delete sites in this suite. `tmp` is `late`,
    // so an unguarded teardown after a throwing setUp reports a
    // LateInitializationError and hides the real cause.
    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    OpLogStore store() =>
        OpLogStore.forNotebook(p.join(tmp.path, 'Book.onote'));

    test('lives beside the .onote, never replacing it', () {
      final s = store()..ensureInitialised(notebookId: 'nb1', title: 'Book');
      expect(p.basename(s.dir.path), 'Book.onotebook');
      expect(s.manifestFile.existsSync(), isTrue);
      final m = s.readManifest();
      expect(m['notebookId'], 'nb1');
      // Scope is an explicit object so section-level sharing is a new value,
      // not a new file layout.
      expect((m['scope'] as Map)['kind'], 'notebook');
    });

    test('appends and reads back in total order across devices', () {
      final s = store()..ensureInitialised(notebookId: 'nb1', title: 'Book');
      s.append('devB', [_op('devB', 1, 2, OpKind.nodePurge, {'id': 'b'})]);
      s.append('devA', [_op('devA', 1, 1, OpKind.nodePurge, {'id': 'a'})]);
      expect(s.deviceIds(), ['devA', 'devB']);
      expect([for (final o in s.readAll()) o.map['id']], ['a', 'b']);
      expect(s.highestLamport(), 2);
      expect(s.lastSeq('devA'), 1);
    });

    test('readBlob answers null, never a throw, for a file it cannot read',
        () {
      // `readBlob` sits on the paint path (`Repository.getBlob`), and the
      // image views chain every read behind the last through one shared
      // queue — so a single throw here used to blank every image loaded
      // after it. "Cannot read right now" — a cloud client's lock, a
      // dehydrated placeholder — must behave exactly like "absent", which
      // sends the caller to the container fallback.
      final s = store();
      final bytes = Uint8List.fromList(List.generate(256, (i) => i % 256));
      const h = 'deadbeef';
      s.writeBlob(h, bytes);
      expect(s.readBlob(h), bytes, reason: 'a healthy blob still reads');

      // Windows locks are mandatory across every handle — the same shape as
      // OneDrive holding the file. Elsewhere they are advisory and the
      // unreadable state cannot be constructed this way.
      if (!Platform.isWindows) return;
      final raf = s.blobFile(h).openSync(mode: FileMode.append);
      raf.lockSync();
      try {
        // MUTATION: remove readBlob's try/catch and this THROWS instead.
        expect(s.readBlob(h), isNull);
      } finally {
        raf.unlockSync();
        raf.closeSync();
      }
      expect(s.readBlob(h), bytes,
          reason: 'and once the lock lifts it reads normally again');
    });
  });

  // What "N devices" means, and why it stopped being a file count.
  //
  // `ops/` keeps every log any device ever wrote and nothing deletes one, so a
  // listing counts identities rather than devices: a reinstall, a restored
  // backup or an identity fork each add one for ever. The owner watched the
  // number climb to five on a notebook with two machines.
  group('counting devices that are actually in use', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('onote_count_'));
    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    /// A log for [dev] whose last op is [daysAgo] days old.
    void writeLog(OpLogStore s, String dev, int daysAgo) {
      final at = DateTime.now()
          .subtract(Duration(days: daysAgo))
          .millisecondsSinceEpoch;
      s.append(dev, [
        Op(
            device: dev,
            seq: 1,
            lamport: 1,
            timestamp: at,
            kind: OpKind.nodePurge,
            data: {'id': 'x'})
      ]);
    }

    test('an abandoned log stops counting, and replay still reads it', () {
      final s = OpLogStore.forNotebook(p.join(tmp.path, 'N.onote'))
        ..ensureInitialised(notebookId: 'nb1', title: 'N');
      writeLog(s, 'this-laptop', 0);
      writeLog(s, 'the-other-one', 3);
      writeLog(s, 'reinstalled-in-august', 70);
      writeLog(s, 'a-fork-nobody-asked-for', 40);

      expect(s.deviceIds(), hasLength(4),
          reason: 'every log is still there, and must be');
      expect(s.activeDeviceIds(), hasLength(2),
          reason: 'two of them have not written in over a month');
      expect(s.activeDeviceIds(),
          containsAll(<String>['this-laptop', 'the-other-one']));

      // The ops under an aged-out id are NOT dropped. Losing them would lose
      // content, which is a far worse bug than a wrong number.
      expect(s.readAll(), hasLength(4));
    });

    test('this installation counts even when its own log has gone quiet', () {
      final s = OpLogStore.forNotebook(p.join(tmp.path, 'S.onote'))
        ..ensureInitialised(notebookId: 'nb1', title: 'S');
      writeLog(s, 'me', 400);
      writeLog(s, 'the-other-laptop', 2);
      // Somebody reading the notebook is holding a device that has it. Before
      // this, a notebook whose every log was five weeks old answered "0".
      expect(s.activeDeviceIds(alsoCount: 'me'), hasLength(2));
      expect(s.activeDeviceIds(alsoCount: 'me'), contains('me'));
      // And our own id is not double-counted when it IS recent.
      writeLog(s, 'me', 0);
      expect(s.activeDeviceIds(alsoCount: 'me'), hasLength(2));
    });

    test('a log whose last write cannot be read counts as in use', () {
      final s = OpLogStore.forNotebook(p.join(tmp.path, 'M.onote'))
        ..ensureInitialised(notebookId: 'nb1', title: 'M');
      writeLog(s, 'known', 0);
      // A line that does not parse — a torn append, or a kind from a newer
      // build. Unknown must read as present: being told about a device that
      // went quiet is a much smaller problem than being told the device in
      // your hands does not exist.
      s.logFor('unreadable').writeAsStringSync('{not json\n');
      expect(s.lastWriteAt('unreadable'), isNull);
      expect(s.activeDeviceIds(), hasLength(2));
    });

    test('the timestamp comes from the op, not the file', () {
      final s = OpLogStore.forNotebook(p.join(tmp.path, 'T.onote'))
        ..ensureInitialised(notebookId: 'nb1', title: 'T');
      writeLog(s, 'old-writer', 200);
      // The file was just written — a sync client copying it, or a git pull,
      // does exactly this — so an mtime would say "today".
      expect(s.logFor('old-writer').lastModifiedSync().millisecondsSinceEpoch,
          greaterThan(
              DateTime.now().subtract(const Duration(minutes: 5)).millisecondsSinceEpoch));
      expect(s.activeDeviceIds(), isEmpty,
          reason: 'the op says 200 days ago, and the op is what travels');
    });
  });

  group('device identity (§6a.2)', () {
    late Directory tmp;
    late Map<String, Object?> settings;
    // The durable record lives in a LOCAL directory, never in the notebook —
    // see `sync/device_seq.dart`. Here that is a scratch dir beside the log.
    late DeviceSeqStore seqs;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('onote_dev');
      settings = {};
      seqs = DeviceSeqStore(Directory(p.join(tmp.path, 'local'))..createSync());
    });
    // Guarded like the other ~90 delete sites in this suite. `tmp` is `late`,
    // so an unguarded teardown after a throwing setUp reports a
    // LateInitializationError and hides the real cause.
    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    DeviceIdentity resolve(OpLogStore s) => DeviceIdentity.resolve(
          store: s,
          notebookId: 'nb1',
          readSetting: (k) => settings[k],
          writeSetting: (k, v) => settings[k] = v,
          seqOf: seqs.read,
          rememberSeq: seqs.write,
        );

    test('is stable across opens, and stored outside the notebook', () {
      final s = OpLogStore.forNotebook(p.join(tmp.path, 'B.onote'))
        ..ensureInitialised(notebookId: 'nb1', title: 'B');
      final first = resolve(s);
      expect(first.forked, isFalse);
      expect(resolve(s).id, first.id);
      // The id must not be discoverable from the notebook directory, or copying
      // a notebook would clone the identity and create two writers.
      expect(s.readManifest().toString(), isNot(contains(first.id)),
          reason: 'manifest records devices only once they write');
    });

    test('forks when another installation has written to our log', () {
      final s = OpLogStore.forNotebook(p.join(tmp.path, 'B.onote'))
        ..ensureInitialised(notebookId: 'nb1', title: 'B');
      final me = resolve(s);
      seqs.write(2); // we remember writing 2

      // A cloned/restored install writes as us and gets further ahead.
      s.append(me.id, [
        _op(me.id, 3, 3, OpKind.nodePurge, {'id': 'x'}),
      ]);

      final after = resolve(s);
      expect(after.forked, isTrue);
      expect(after.id, isNot(me.id));
      expect(seqs.read(), 0);
      // The other writer's ops stay valid and readable under the old id — we
      // abandon the identity, not the history.
      expect(s.readDevice(me.id), hasLength(1));
    });

    test('does not fork when our own writes are all accounted for', () {
      final s = OpLogStore.forNotebook(p.join(tmp.path, 'B.onote'))
        ..ensureInitialised(notebookId: 'nb1', title: 'B');
      final me = resolve(s);
      s.append(me.id, [_op(me.id, 1, 1, OpKind.nodePurge, {'id': 'x'})]);
      seqs.write(1);
      expect(resolve(s).forked, isFalse);
    });

    // THE CASE THAT ACTUALLY HAPPENED, driven through a real recorder because
    // that is the only thing that writes to our own log.
    //
    // Ops are appended and flushed immediately. The seq that says how far we
    // got used to go to `workspace.json` through `setSetting`, which coalesces
    // behind a 400 ms debounce and is forced only by a clean `shutdown()`. Any
    // exit that skipped shutdown therefore left the log ahead of the remembered
    // seq, which is indistinguishable from a second installation writing under
    // our id — so the device forked, and every fork orphans a log that nothing
    // ever deletes.
    //
    // Measured on the owner's own notebook before the fix: two ids minted 79
    // minutes apart on one day, both labelled "Windows computer", one machine.
    //
    // The fix is the ordering in `SyncRecorder._commit`: the record is written
    // BEFORE the ops it covers, so a crash in between leaves the record ahead
    // of the log, which reads as nothing unexpected.
    test('a crash mid-session does not fork the device id', () {
      final path = p.join(tmp.path, 'C.onote');
      SyncRecorder openRecorder() => SyncRecorder.open(
            notebookId: 'nb1',
            notebookPath: path,
            title: 'C',
            readSetting: (k) => settings[k],
            writeSetting: (k, v) => settings[k] = v,
            seqOf: seqs.read,
            rememberSeq: seqs.write,
            materialiseBlobs: false,
          );

      final first = openRecorder();
      final id = first.device.id;
      expect(first.device.forked, isFalse);
      // A session's worth of real work, recorded the way the app records it.
      for (var i = 0; i < 12; i++) {
        first.node(TreeNode(
            id: 'n'+i.toString(), kind: NodeKind.page, title: 'p'+i.toString(), position: 'a'+i.toString()));
      }
      // ...and then the process goes away without a clean shutdown. Nothing is
      // flushed, nothing is disposed; the next line is the next launch.

      // THE CRASH: `workspace.json` is what used to hold the remembered seq,
      // and it is written behind a 400 ms debounce that only a clean
      // `shutdown()` forces. Losing it is exactly what an unclean exit does.
      // Only the seq, not the whole file: the device id is written once at
      // first run and has long since been flushed. The seq is rewritten on
      // every save, so it is the one the debounce keeps losing.
      settings.remove(DeviceIdentity.seqKey('nb1'));

      final second = openRecorder();
      expect(second.device.forked, isFalse,
          reason: 'a lost workspace write is not a second writer');
      expect(second.device.id, id, reason: 'the identity must survive a crash');
      expect(OpLogStore.forNotebook(path).deviceIds(), hasLength(1),
          reason: 'and no orphan log is left behind');
    });

    // Upgrading onto this fix must not fork every device once. An install that
    // predates the durable record has a log full of its own ops and no record
    // at all, which is "I do not know" rather than "I have written nothing" —
    // and the old `?? 0` could not tell those apart.
    test('an install with no record at all adopts its log instead of forking',
        () {
      final s = OpLogStore.forNotebook(p.join(tmp.path, 'E.onote'))
        ..ensureInitialised(notebookId: 'nb1', title: 'E');
      // A device id from the old world, and a log it has been writing for
      // months. Nothing has ever written the durable record.
      settings[DeviceIdentity.settingsKey] = 'dev-from-before';
      s.append('dev-from-before', [
        for (var i = 1; i <= 40; i++)
          _op('dev-from-before', i, i, OpKind.nodePurge, {'id': 'z'})
      ]);
      expect(seqs.read(), isNull, reason: 'no record, by construction');

      final after = resolve(s);
      expect(after.forked, isFalse, reason: 'upgrading is not a second writer');
      expect(after.id, 'dev-from-before');
      expect(seqs.read(), 40,
          reason: 'and the log it adopted is now the record');
    });

    // The second half of the same bug, and the one an absent record does not
    // cover. A debounced write that DID land mid-session leaves a value that is
    // present and behind — `workspace.json` says 50 while the log says 90 —
    // which the old code read as a second writer just as readily as an absent
    // one. The record has to be written where it cannot fall behind.
    test('a stale workspace seq does not fork the device id either', () {
      final path = p.join(tmp.path, 'D.onote');
      SyncRecorder openRecorder() => SyncRecorder.open(
            notebookId: 'nb1',
            notebookPath: path,
            title: 'D',
            readSetting: (k) => settings[k],
            writeSetting: (k, v) => settings[k] = v,
            seqOf: seqs.read,
            rememberSeq: seqs.write,
            materialiseBlobs: false,
          );

      final first = openRecorder();
      final id = first.device.id;
      for (var i = 0; i < 12; i++) {
        first.node(TreeNode(
            id: 'm' + i.toString(),
            kind: NodeKind.page,
            title: 'q' + i.toString(),
            position: 'b' + i.toString()));
      }
      // The debounce landed early in the session and never again.
      settings[DeviceIdentity.seqKey('nb1')] = 1;

      final second = openRecorder();
      expect(second.device.forked, isFalse,
          reason: 'the durable record is the one that counts');
      expect(second.device.id, id);
    });
  });

  // A torn log is the NORMAL shape of an append-only file, not an exceptional
  // one: a crash, a cloud client copying mid-write, a laptop lid. `Op.decode`'s
  // doc comment states the promise these cells hold the reader to — **a torn
  // tail costs the last line and nothing else** — and two separate bugs broke
  // it in opposite directions. Both were silent: one stopped sync with an
  // exception nobody surfaced, the other quietly returned fewer ops.
  //
  // Cells F1, F2 and F3 of the v0.17 CI matrix.
  group('a torn log costs the last line and nothing else', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('onote_torn_'));
    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    OpLogStore storeAt(String name) =>
        OpLogStore.forNotebook(p.join(tmp.path, '$name.onote'))
          ..ensureInitialised(notebookId: 'nb1', title: name);

    /// Every op the format PROMISES back from a prefix of a log: one per
    /// complete, newline-terminated line. Counting terminators is the whole
    /// definition — it is what makes "one lost byte costs one op" checkable
    /// rather than a slogan.
    int completeLinesIn(Uint8List prefix) =>
        prefix.where((b) => b == 0x0A).length;

    void assertNoCompleteOpLost(OpLogStore s, Uint8List prefix) {
      final want = completeLinesIn(prefix);
      final got = s.readAll(); // never throws — that is half the assertion
      expect(got.length, greaterThanOrEqualTo(want),
          reason: '$want complete lines in the prefix, ${got.length} ops read');
      expect([for (final o in got.take(want)) o.seq],
          List.generate(want, (i) => i + 1),
          reason: 'ops before the cut must come back in order, none missing');
    }

    test('F1: truncated at every 1 KiB boundary, readAll never throws', () {
      final s = storeAt('kib');
      // Text the owner's notes are actually full of, so the 1 KiB boundaries
      // land inside multi-byte sequences the way they do on the real log.
      s.append('d', [
        for (var i = 1; i <= 400; i++)
          _op('d', i, i, OpKind.blockSet, {
            'pageId': 'p1',
            'block': {'id': 'b$i', 'text': 'let ℝ ∋ x ∃ y ∈ ℕ — note $i'}
          })
      ]);
      final f = s.logFor('d');
      final whole = f.readAsBytesSync();
      expect(whole.length, greaterThan(16 * 1024),
          reason: 'the cell is meaningless without several boundaries to cut');

      for (var cut = 1024; cut < whole.length; cut += 1024) {
        final prefix = Uint8List.sublistView(whole, 0, cut);
        f.writeAsBytesSync(prefix, flush: true);
        assertNoCompleteOpLost(s, prefix);
      }
    });

    test('F2: truncated inside a multi-byte character, at every byte', () {
      // The minimal reproduction. `readAsStringSync` decodes UTF-8 strictly and
      // throws `FileSystemException` on a partial sequence, and `readAll`,
      // `highestLamport` and `lastSeq` all routed through it. Measured on the
      // real 1,523,044-byte log, 2 of 1,487 1 KiB cuts threw; on a small log
      // this dense, 6 of 316 did. One half-written `ℝ` stopped sync outright.
      final s = storeAt('utf8');
      s.append('d', [
        for (var i = 1; i <= 4; i++)
          _op('d', i, i, OpKind.pageProps, {'title': 'ℝ ∃ ∈ ℕ ∀ ⊆ №$i'})
      ]);
      final f = s.logFor('d');
      final whole = f.readAsBytesSync();

      for (var cut = 1; cut < whole.length; cut++) {
        final prefix = Uint8List.sublistView(whole, 0, cut);
        f.writeAsBytesSync(prefix, flush: true);
        assertNoCompleteOpLost(s, prefix);
      }
    });

    test('F3: an append that lost only its newline loses no op at all', () {
      // `append` wrote `ops.join('\n') + '\n'` in one call, so a tear one byte
      // from the end left a COMPLETE record with no terminator — and the next
      // append welded its first record onto it, making one unparseable line out
      // of two valid ones. Measured before the fix: seqs [1, 2, 5]. Two ops
      // lost for one lost byte, where the format promises one.
      final s = storeAt('glue');
      s.append('d', [
        for (var i = 1; i <= 3; i++)
          _op('d', i, i, OpKind.nodePurge, {'id': 'n$i'})
      ]);
      final f = s.logFor('d');
      final bytes = f.readAsBytesSync();
      f.writeAsBytesSync(Uint8List.sublistView(bytes, 0, bytes.length - 1),
          flush: true);

      s.append('d', [
        for (var i = 4; i <= 5; i++)
          _op('d', i, i, OpKind.nodePurge, {'id': 'n$i'})
      ]);

      expect([for (final o in s.readDevice('d')) o.seq], [1, 2, 3, 4, 5],
          reason: 'the record that lost its newline was never damaged, only '
              'unterminated — gluing the terminator back on recovers it, and '
              'the record after it was never in danger');
    });
  });
}
