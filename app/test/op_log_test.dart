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

  group('log store', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('onote_oplog'));
    tearDown(() => tmp.deleteSync(recursive: true));

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
    tearDown(() => tmp.deleteSync(recursive: true));

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
}
