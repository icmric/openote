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
import 'package:openote/sync/materializer.dart';
import 'package:openote/sync/op.dart';
import 'package:openote/sync/op_log.dart';

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
      expect(back.version, opFormatVersion);
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
  });

  group('device identity (§6a.2)', () {
    late Directory tmp;
    late Map<String, Object?> settings;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('onote_dev');
      settings = {};
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
      settings[DeviceIdentity.seqKey('nb1')] = 2; // we remember writing 2

      // A cloned/restored install writes as us and gets further ahead.
      s.append(me.id, [
        _op(me.id, 3, 3, OpKind.nodePurge, {'id': 'x'}),
      ]);

      final after = resolve(s);
      expect(after.forked, isTrue);
      expect(after.id, isNot(me.id));
      expect(settings[DeviceIdentity.seqKey('nb1')], 0);
      // The other writer's ops stay valid and readable under the old id — we
      // abandon the identity, not the history.
      expect(s.readDevice(me.id), hasLength(1));
    });

    test('does not fork when our own writes are all accounted for', () {
      final s = OpLogStore.forNotebook(p.join(tmp.path, 'B.onote'))
        ..ensureInitialised(notebookId: 'nb1', title: 'B');
      final me = resolve(s);
      s.append(me.id, [_op(me.id, 1, 1, OpKind.nodePurge, {'id': 'x'})]);
      settings[DeviceIdentity.seqKey('nb1')] = 1;
      expect(resolve(s).forked, isFalse);
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
