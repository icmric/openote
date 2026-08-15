// v0.17 plan, Step 3 — "Say `section_group`, and gate the envelope".
//
// Two holes in the op log's vocabulary and forward compatibility, both merely
// cosmetic while the container is authoritative and both data-losing the moment
// the log becomes the format.
//
//  1. **The writer used Dart's word, not the spec's.** `SyncRecorder.node`
//     wrote `n.kind.name`, which spells a section group `sectionGroup`. The CC0
//     spec §3 documents only `section_group`, the container's own DDL is
//     `CHECK (kind IN ('section_group','section','page'))`, and the reader's
//     `orElse: () => NodeKind.page` then turned every one of them into a PAGE.
//     Measured on all four of the owner's real notebooks: 6 nodes each.
//
//  2. **Nothing looked at the envelope.** `Op.decode` reads `v` and `enc` and
//     nothing ever compared them to what this build can apply. A hand-written
//     `{"v":2,…}` op was applied as if it were v1 with `skipped=0`; an
//     `{"enc":"aes-gcm"}` op decoded to an empty map and was dropped, also with
//     `skipped=0`.
//
// Every test below names the mutation that turns it red, because a cell that
// cannot fail is not a cell (plan §5.1 rule 3).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/sync/materializer.dart';
import 'package:openote/sync/op.dart';
import 'package:openote/sync/op_log.dart';
import 'package:openote/sync/sync_recorder.dart';

import 'support/sqlite.dart';

Op _nodeUpsert(String id, String kind,
        {int version = opFormatVersion, String encryption = 'none', int seq = 1}) =>
    Op(
      device: 'dev-a',
      seq: seq,
      lamport: seq,
      timestamp: 1,
      kind: OpKind.nodeUpsert,
      version: version,
      encryption: encryption,
      data: {'id': id, 'kind': kind, 'title': 'Term 1', 'position': 'a0'},
    );

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  group('the word for a section group', () {
    test('the WRITER uses the spec spelling, and no other', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final ws = Directory.systemTemp.createTempSync('onote_kind_write_');
      final repo = await Repository.openAt(ws);
      addTearDown(() {
        repo.dispose();
        try {
          ws.deleteSync(recursive: true);
        } catch (_) {}
      });
      final nb = await repo.createNotebook('Kinds');
      final app = AppState(repo)..notebookId = nb.id;
      addTearDown(app.dispose);
      app.reloadNodes();
      app.addSectionGroup();

      final store = OpLogStore.forNotebook(nb.file);
      final kinds = store
          .readAll()
          .where((o) => o.kind == OpKind.nodeUpsert)
          .map((o) => o.map['kind'])
          .toSet();
      // MUTATION: put `n.kind.name` back in `SyncRecorder.node` and this fails
      // on both counts — `section_group` is absent and `sectionGroup` appears.
      expect(kinds, contains('section_group'));
      expect(kinds, isNot(contains('sectionGroup')),
          reason: 'that word appears nowhere in the published spec');
    });

    test('the READER accepts the spec spelling', () {
      final m = Materializer()..apply(_nodeUpsert('n1', 'section_group'));
      expect(m.nodes['n1']!.kind, 'section_group');
      expect(nodeKindFromWire(m.nodes['n1']!.kind), NodeKind.sectionGroup);
      expect(m.skipped, isEmpty);
    });

    // NEGATIVE CONTROL. Every log written before this fix says `sectionGroup`,
    // and §4.1 of the plan is absolute that nothing rewrites a log line — so
    // dropping the old word would silently re-break the six nodes per notebook
    // the fix exists to repair.
    test('the READER STILL accepts the OLD spelling, and must for ever', () {
      final m = Materializer()..apply(_nodeUpsert('n1', 'sectionGroup'));
      expect(nodeKindFromWire(m.nodes['n1']!.kind), NodeKind.sectionGroup,
          reason: 'a log written by any build before v0.17 says this');
      // MUTATION: delete the `|| 'sectionGroup'` arm of `nodeKindFromWire` and
      // this fails while everything else here stays green.
      expect(m.skipped, isEmpty,
          reason: 'the old spelling is understood, not merely tolerated');
    });

    test('an UNKNOWN kind is skipped and kept verbatim — never a page', () {
      final m = Materializer()..apply(_nodeUpsert('n1', 'wormhole'));
      // Not coerced. A page has a `page_mirror` foreign key and a `level`.
      expect(nodeKindFromWire(m.nodes['n1']!.kind), isNull);
      expect(m.nodes['n1']!.kind, 'wormhole',
          reason: 'preserved verbatim so a round trip through us is lossless');
      // MUTATION: restore `orElse: () => NodeKind.page` and this reads `page`.
      expect(m.skipped.single.map['id'], 'n1');
      // …and an unknown KIND is not an unknown ENVELOPE: it does not lock the
      // notebook, because skipping op kinds is exactly what `OpKind.unknown`
      // was designed for.
      expect(m.unsupported, isEmpty);
    });

    test('section and page are unaffected in both directions', () {
      expect(nodeKindWire(NodeKind.section), 'section');
      expect(nodeKindWire(NodeKind.page), 'page');
      expect(nodeKindFromWire('section'), NodeKind.section);
      expect(nodeKindFromWire('page'), NodeKind.page);
    });
  });

  group('the envelope gate', () {
    // NEGATIVE CONTROL, and the most important test in this file: the entire
    // population of every log on disk today is v1 with `enc: 'none'`, and a
    // gate that rejected one of those would lock every user out of their own
    // notes on the day it shipped.
    test('A VALID v1 OP IS NOT REJECTED', () {
      final m = Materializer()..apply(_nodeUpsert('n1', 'page'));
      expect(m.nodes['n1'], isNotNull, reason: 'it was applied');
      expect(m.skipped, isEmpty);
      // MUTATION: change `op.version > opFormatVersion` to `>=` and this fails
      // while the two below still pass — which is the whole point of having it.
      expect(m.unsupported, isEmpty);
    });

    test('a NEWER envelope version is skipped, not applied', () {
      final m = Materializer()..apply(_nodeUpsert('n1', 'page', version: 2));
      // Measured before the gate existed: applied, with `skipped=0`.
      expect(m.nodes['n1'], isNull, reason: 'a v2 payload is not a v1 payload');
      expect(m.unsupported.single.version, 2);
      expect(m.skipped, hasLength(1),
          reason: "verifyPage's 'inconclusive' escape hatch keys off this");
    });

    test('an ENCRYPTED payload is skipped, not silently dropped', () {
      final m = Materializer()
        ..apply(_nodeUpsert('n1', 'page', encryption: 'aes-gcm'));
      expect(m.nodes['n1'], isNull);
      expect(m.unsupported.single.encryption, 'aes-gcm');
      expect(m.skipped, hasLength(1),
          reason: 'it used to decode to an empty map and vanish');
    });

    test('the gate stops at the envelope — the ops around it still apply', () {
      final m = Materializer()
        ..apply(_nodeUpsert('a', 'section'))
        ..apply(_nodeUpsert('b', 'page', version: 2, seq: 2))
        ..apply(_nodeUpsert('c', 'page', seq: 3));
      expect(m.nodes.keys, containsAll(['a', 'c']));
      expect(m.nodes['b'], isNull);
    });
  });

  group('a log we cannot fully read makes the notebook read-only', () {
    /// A workspace whose notebook's log has had [ops] planted in it by another
    /// device, opened fresh so the recorder replays them on the way in.
    Future<(Repository, AppState, String)> withPlantedOps(
        String prefix, List<Op> ops) async {
      final ws = Directory.systemTemp.createTempSync(prefix);
      final repo = await Repository.openAt(ws);
      addTearDown(() {
        repo.dispose();
        try {
          ws.deleteSync(recursive: true);
        } catch (_) {}
      });
      final nb = await repo.createNotebook('Locked');
      final store = OpLogStore.forNotebook(nb.file);
      store.ensureInitialised(notebookId: nb.id, title: 'Locked');
      store.append('another-device', ops);
      final app = AppState(repo)..notebookId = nb.id;
      addTearDown(app.dispose);
      app.reloadNodes();
      await app.warmRecorder(nb.id);
      return (repo, app, nb.id);
    }

    test('a v2 op locks it, and the sentence has no jargon in it', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (_, app, nb) =
          await withPlantedOps('onote_gate_v2_', [_nodeUpsert('x', 'page', version: 2)]);

      expect(app.notebookIsReadOnly(nb), isTrue);
      final problem = app.saveError;
      expect(problem, isNotNull);
      // The no-jargon bar, asserted the same way `open_notice_dialog.dart` and
      // `save_problem_dialog.dart` are: the sentence a year 10 student reads
      // carries no version number, no format word and no file extension. All of
      // that lives in `details`, behind the Advanced fold.
      final said = '${problem!.short} ${problem.message}'.toLowerCase();
      for (final jargon in [
        'envelope',
        'op ',
        'oplog',
        'v2',
        'format',
        'sqlite',
        'encrypt',
        'aes',
        '.onote',
        'exception',
      ]) {
        expect(said, isNot(contains(jargon)), reason: 'jargon: "$jargon"');
      }
      expect(problem.message, contains('newer version of Openote'));
      expect(problem.details, contains('envelope version'),
          reason: 'the technical half exists — it is just folded away');
    });

    test('an encrypted op locks it too', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (_, app, nb) = await withPlantedOps('onote_gate_enc_',
          [_nodeUpsert('x', 'page', encryption: 'aes-gcm')]);
      expect(app.notebookIsReadOnly(nb), isTrue);
    });

    test('READ-ONLY MEANS NO NEW OPS AND NO CONTAINER WRITE', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb) = await withPlantedOps(
          'onote_gate_write_', [_nodeUpsert('x', 'page', version: 2)]);

      final store = OpLogStore.forNotebook(repo.notebooks.single.file);
      final before = store.readAll().length;
      final pagesBefore =
          repo.loadNodes(nb).where((n) => n.kind == NodeKind.page).length;

      // Every user-driven write path, one after the other.
      app.addSectionGroup();
      app.pageId = app.nodes.where((n) => n.kind == NodeKind.page).first.id;
      app.blocks = [];
      app.markDirty();
      await app.flushSave();
      await app.deleteNode(app.pageId!);

      // Nothing appended on top of a history we have only half read: an op
      // written here would be a diff against a replay missing whatever the
      // unreadable op did — an "edit" that is really an undo of changes the
      // user never asked to lose.
      expect(store.readAll().length, before);
      expect(repo.loadNodes(nb).where((n) => n.kind == NodeKind.sectionGroup),
          isEmpty,
          reason: 'and nothing reached the container either');
      expect(repo.loadNodes(nb).where((n) => n.kind == NodeKind.page).length,
          pagesBefore,
          reason: 'the delete was refused too');
      // MUTATION: drop the `if (logIsAhead) return;` from `SyncRecorder._commit`
      // and the op count grows; drop the `notebookIsReadOnly` guards in
      // `AppState` and the node counts move.
    });

    test('THE RECORDER ITSELF REFUSES — the backstop under the app gates',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The `AppState` guards cover every path a user drives. This covers the
      // ones nobody has thought of yet — importers, future call sites, a gate
      // somebody forgets to add — by putting the refusal in the one funnel
      // every op passes through on its way to disk. Tested directly because
      // with the app-level guards in place it is unreachable from above, and
      // an untested backstop is a comment.
      final ws = Directory.systemTemp.createTempSync('onote_gate_rec_');
      addTearDown(() {
        try {
          ws.deleteSync(recursive: true);
        } catch (_) {}
      });
      final store = OpLogStore.forNotebook(p.join(ws.path, 'Locked.onote'));
      store.ensureInitialised(notebookId: 'nb-1', title: 'Locked');
      store.append('another-device', [_nodeUpsert('x', 'page', version: 2)]);

      final settings = <String, Object?>{};
      final rec = SyncRecorder.open(
        notebookId: 'nb-1',
        notebookPath: p.join(ws.path, 'Locked.onote'),
        title: 'Locked',
        readSetting: (k) => settings[k],
        writeSetting: (k, v) => settings[k] = v,
      );
      expect(rec.logIsAhead, isTrue);

      final before = store.readAll().length;
      rec.node(TreeNode(kind: NodeKind.section, title: 'New'));
      rec.notebookMeta({'title': 'Renamed'});
      // MUTATION: drop `if (logIsAhead) return;` from `SyncRecorder._commit`
      // and this grows.
      expect(store.readAll().length, before);
      expect(rec.opsWritten, 0);
    });

    // NEGATIVE CONTROL for the whole group. An ordinary notebook must not go
    // read-only, or this feature is a bug that locks everybody out.
    test('AN ORDINARY NOTEBOOK IS NOT READ-ONLY', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb) =
          await withPlantedOps('onote_gate_ok_', [_nodeUpsert('x', 'page')]);
      expect(app.notebookIsReadOnly(nb), isFalse);
      expect(app.saveError, isNull);
      app.addSectionGroup();
      expect(repo.loadNodes(nb).where((n) => n.kind == NodeKind.sectionGroup),
          hasLength(1),
          reason: 'a normal notebook still takes edits');
    });
  });
}
