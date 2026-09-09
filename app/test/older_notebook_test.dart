// **A notebook written before 1.0 opens in 1.0 and is fully writable.**
//
// The owner, before the release went out: *"Is there any way we can update or
// clone a pre 1.0 notebook to make it useable? Im aware of some people already
// using it and i dont want them to be out of luck."*
//
// The concern is right and the direction is the other way round, which is
// worth a test rather than a reassurance. `block.patch` rides a `v: 2`
// envelope, and the envelope gate is one-sided: a reader refuses a record
// NEWER than it understands. A pre-1.0 notebook contains nothing but `v: 1`
// records, and `v: 1` is exactly what every build ever released can read — so
// there is no migration, no clone, and nothing for anybody to be out of luck
// about. Nobody's history is invalidated; nothing needs converting.
//
// What is real, and is the inverse: once a 1.0 device has written a patch into
// a notebook, a 0.9 device sharing it holds that notebook read-only until it
// is updated. It shows every page and refuses to add to it, which is the
// correct behaviour rather than a bug — writing on top of a history you have
// only half read is how notes get lost — and it is undone by updating, not by
// touching the data.
//
// Both halves are asserted here, because "the old one still works" is the
// half people need to be able to rely on.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/sync/materializer.dart';
import 'package:openote/sync/op.dart';
import 'package:openote/sync/op_log.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  /// One op exactly as a pre-1.0 build wrote it: `v: 1`, and no `block.patch`
  /// anywhere in its vocabulary.
  Op asZeroNine(int seq, OpKind kind, Map<String, dynamic> data) => Op(
        device: 'a-0-9-device',
        seq: seq,
        lamport: seq,
        timestamp: 1700000000000 + seq,
        kind: kind,
        data: data,
        version: 1,
      );

  List<Op> aNotebookFrom09(String pageId) => [
        asZeroNine(1, OpKind.nodeUpsert, {
          'id': pageId,
          'kind': 'page',
          'title': 'Lecture 3',
          'parentId': null,
          'position': 'a0',
        }),
        asZeroNine(2, OpKind.blockSet, {
          'pageId': pageId,
          'block': {
            'id': 'b1',
            'type': 'text',
            'x': 0,
            'y': 0,
            'w': 400,
            'content': {'text': 'Everything I wrote before 1.0 existed.'},
          },
        }),
      ];

  test('every record a pre-1.0 build wrote is one this build applies', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final m = Materializer()..applyAll(aNotebookFrom09('p1'));

    expect(m.unsupported, isEmpty,
        reason: 'v1 is not newer than v2 — the gate is one-sided, by design');
    expect(m.skipped, isEmpty);
    expect(
        ((m.pages['p1']!.blocks['b1']!['content'] as Map)['text']),
        'Everything I wrote before 1.0 existed.',
        reason: 'the page is there, in full');
  });

  test('and the notebook is WRITABLE, not merely readable', () async {
    // The half that matters to somebody who has been using this for months.
    // Opening is not enough: they have to be able to carry on.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final ws = Directory.systemTemp.createTempSync('onote_pre10_');
    final repo = await Repository.openAt(ws);
    addTearDown(() {
      repo.dispose();
      try {
        ws.deleteSync(recursive: true);
      } catch (_) {}
    });

    final nb = await repo.createNotebook('From 0.9');
    final store = OpLogStore.forNotebook(nb.file);
    store.ensureInitialised(notebookId: nb.id, title: 'From 0.9');
    final app = AppState(repo)..notebookId = nb.id;
    addTearDown(app.dispose);
    app.reloadNodes();
    final pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
    store.append('a-0-9-device', aNotebookFrom09(pageId));
    await app.warmRecorder(nb.id);

    expect(app.notebookIsReadOnly(nb.id), isFalse,
        reason: 'nothing in this log is ahead of this build');
    expect(app.saveError, isNull);

    // And a real edit actually lands.
    app.pageId = pageId;
    final before = store.readAll().length;
    app.blocks = [
      Block(
          type: BlockType.text,
          x: 0,
          y: 0,
          w: 400,
          content: {'text': 'and I can still add to it.'})
    ];
    app.markDirty();
    await app.flushSave();

    expect(store.readAll().length, greaterThan(before),
        reason: 'the edit reached the log');
  });

  test('the lock only ever points forwards', () {
    // Stated as an invariant rather than an example: what the gate refuses is
    // strictly NEWER than this build, so no past release can be locked out by
    // a future one's records already on disk.
    for (final v in [1, opFormatVersion]) {
      final m = Materializer()
        ..apply(Op(
          device: 'd',
          seq: 1,
          lamport: 1,
          timestamp: 0,
          kind: OpKind.nodeUpsert,
          data: const {'id': 'n', 'kind': 'page'},
          version: v,
        ));
      expect(m.unsupported, isEmpty, reason: 'v$v must apply');
    }
    final ahead = Materializer()
      ..apply(Op(
        device: 'd',
        seq: 1,
        lamport: 1,
        timestamp: 0,
        kind: OpKind.nodeUpsert,
        data: const {'id': 'n', 'kind': 'page'},
        version: opFormatVersion + 1,
      ));
    expect(ahead.unsupported, hasLength(1));
  });
}
