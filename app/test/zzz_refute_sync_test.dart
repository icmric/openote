// THROWAWAY probe — delete after use.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

class Rig {
  Rig(this.tmpA, this.tmpB, this.shared, this.repoA, this.repoB, this.a,
      this.b, this.nbA, this.nbB, this.pid);
  final Directory tmpA, tmpB, shared;
  final Repository repoA, repoB;
  final AppState a, b;
  final String nbA, nbB, pid;
}

Future<Rig> makeRig(String tag) async {
  final tmpA = Directory.systemTemp.createTempSync('onote_${tag}_a_');
  final tmpB = Directory.systemTemp.createTempSync('onote_${tag}_b_');
  final shared = Directory.systemTemp.createTempSync('onote_${tag}_s_');
  final repoA = await Repository.openAt(tmpA);
  final repoB = await Repository.openAt(tmpB);
  final made = await repoA.createNotebook('Shared');
  final moved = await repoA.moveNotebookTo(made.id, shared.path);
  final joined = await repoB.openExistingNotebook(moved);
  final a = AppState(repoA)..notebookId = made.id;
  final b = AppState(repoB)..notebookId = joined.id;
  a.reloadNodes();
  final pid = a.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
  await a.selectPage(pid);
  b.reloadNodes();
  return Rig(tmpA, tmpB, shared, repoA, repoB, a, b, made.id, joined.id, pid);
}

void cleanup(Rig r) {
  r.a.cancelPendingSave();
  r.b.cancelPendingSave();
  r.repoA.dispose();
  r.repoB.dispose();
  for (final d in [r.tmpA, r.tmpB, r.shared]) {
    try {
      d.deleteSync(recursive: true);
    } catch (_) {}
  }
}

String? textOf(Repository repo, String nb, String pid, String bid) {
  final blocks = repo.readPage(nb, pid).blocks;
  final b = blocks.where((x) => x.id == bid).firstOrNull;
  return b?.content['text'] as String?;
}

void main() {
  var have = false;
  setUpAll(() => have = initSqliteForTests());

  test('P3 same-block concurrent edit', () async {
    if (!have) return markTestSkipped('no sqlite');
    final r = await makeRig('p3');
    addTearDown(() => cleanup(r));

    final blk = Block(type: BlockType.text, x: 0, y: 0, content: {'text': 'base'});
    r.a.blocks = [blk];
    r.a.markDirty();
    await r.a.flushSave();

    expect(await r.b.syncPull(r.nbB), greaterThan(0));
    print('B after first pull: ${textOf(r.repoB, r.nbB, r.pid, blk.id)}');

    // both edit the SAME block offline
    await r.a.selectPage(r.pid);
    r.a.blocks.firstWhere((x) => x.id == blk.id).content['text'] = 'A typed';
    r.a.markDirty();
    await r.a.flushSave();

    await r.b.selectPage(r.pid);
    r.b.blocks.firstWhere((x) => x.id == blk.id).content['text'] = 'B typed';
    r.b.markDirty();
    await r.b.flushSave();

    final pa = await r.a.syncPull(r.nbA);
    final pb = await r.b.syncPull(r.nbB);
    print('pulled a=$pa b=$pb');
    final ta = textOf(r.repoA, r.nbA, r.pid, blk.id);
    final tb = textOf(r.repoB, r.nbB, r.pid, blk.id);
    print('P3 RESULT  A=$ta  B=$tb');

    // second round of pulls, does it heal?
    await r.a.syncPull(r.nbA);
    await r.b.syncPull(r.nbB);
    print('P3 after 2nd pull  A=${textOf(r.repoA, r.nbA, r.pid, blk.id)}'
        '  B=${textOf(r.repoB, r.nbB, r.pid, blk.id)}');
  });

  test('P4/P5 purge and restore', () async {
    if (!have) return markTestSkipped('no sqlite');
    final r = await makeRig('p45');
    addTearDown(() => cleanup(r));

    // A makes a second page so deleting the first is fine
    r.a.reloadNodes();
    final section = r.a.nodes.firstWhere((n) => n.kind == NodeKind.section);
    final extra = TreeNode(
        kind: NodeKind.page, parentId: section.id, title: 'Doomed',
        position: 'z9');
    r.a.importNode(r.nbA, extra);
    r.a.importPage(r.nbA, extra.id,
        [Block(type: BlockType.text, x: 0, y: 0, content: {'text': 'gone soon'})],
        PageProps());
    r.a.reloadNodes();

    await r.b.syncPull(r.nbB);
    print('B sees Doomed live: '
        '${r.repoB.loadNodes(r.nbB).any((n) => n.id == extra.id)}');

    // A soft-deletes then purges
    await r.a.deleteNode(extra.id);
    r.a.purgeDeleted(extra.id);

    final n = await r.b.syncPull(r.nbB);
    final liveOnB = r.repoB.loadNodes(r.nbB).any((x) => x.id == extra.id);
    final binOnB = r.repoB.loadDeletedNodes(r.nbB).any((x) => x.id == extra.id);
    print('P4 pulled=$n  liveOnB=$liveOnB  binOnB=$binOnB');

    // P5: delete another page, pull, restore, pull
    final extra2 = TreeNode(
        kind: NodeKind.page, parentId: section.id, title: 'Oops',
        position: 'z8');
    r.a.importNode(r.nbA, extra2);
    r.a.reloadNodes();
    await r.b.syncPull(r.nbB);
    await r.a.deleteNode(extra2.id);
    await r.b.syncPull(r.nbB);
    print('P5 after delete: binOnB='
        '${r.repoB.loadDeletedNodes(r.nbB).any((x) => x.id == extra2.id)}');
    await r.a.restoreDeleted(extra2.id);
    final n2 = await r.b.syncPull(r.nbB);
    print('P5 after restore pulled=$n2 liveOnB='
        '${r.repoB.loadNodes(r.nbB).any((x) => x.id == extra2.id)} binOnB='
        '${r.repoB.loadDeletedNodes(r.nbB).any((x) => x.id == extra2.id)}');
  });

  test('P1 blob arriving late', () async {
    if (!have) return markTestSkipped('no sqlite');
    final r = await makeRig('p1');
    addTearDown(() => cleanup(r));

    final bytes = Uint8List.fromList(List.generate(64, (i) => i));
    final hash = r.a.importBlob(r.nbA, bytes, 'image/png');
    final blk = Block(type: BlockType.image, x: 0, y: 0,
        content: {'blob': 'sha256:$hash'});
    r.a.blocks = [blk];
    r.a.markDirty();
    await r.a.flushSave();

    // simulate the .oplog syncing before the multi-MB blob file
    final blobFile = File(p.join(
        '${p.withoutExtension(r.repoA.notebooks.firstWhere((x) => x.id == r.nbA).file)}.onotebook',
        'blobs', hash));
    print('blob file exists before removal: ${blobFile.existsSync()}');
    final saved = blobFile.readAsBytesSync();
    blobFile.deleteSync();

    final n = await r.b.syncPull(r.nbB);
    print('P1 pulled=$n  bytesOnB=${r.repoB.getBlob(r.nbB, hash) != null}');

    // bytes land later
    blobFile.writeAsBytesSync(saved);
    final n2 = await r.b.syncPull(r.nbB);
    r.b.dropRecordersForTest();
    final n3 = await r.b.syncPull(r.nbB);
    final copied = await r.b.syncBackfillBlobs(r.nbB);
    print('P1 later pulls=$n2/$n3 backfill=$copied '
        'bytesOnB=${r.repoB.getBlob(r.nbB, hash) != null} '
        'missing=${r.b.syncMissingBlobs(r.nbB)}');
    // does the container even have a blob_refs row / does the page render?
    print('P1 page blocks on B: ${r.repoB.readPage(r.nbB, r.pid).blocks.length}');
  });

  test('P6 notebook rename', () async {
    if (!have) return markTestSkipped('no sqlite');
    final r = await makeRig('p6');
    addTearDown(() => cleanup(r));

    await r.b.syncPull(r.nbB);
    r.a.renameNotebook(r.nbA, 'Physics 101');
    final n = await r.b.syncPull(r.nbB);
    print('P6 pulled=$n  B title=${r.repoB.notebooks.firstWhere((x) => x.id == r.nbB).title}');

    int metaOps() {
      final dir = Directory(p.join(
          '${p.withoutExtension(r.repoA.notebooks.firstWhere((x) => x.id == r.nbA).file)}.onotebook',
          'ops'));
      var c = 0;
      for (final f in dir.listSync().whereType<File>()) {
        for (final l in f.readAsLinesSync()) {
          if (l.contains('notebook.meta')) c++;
        }
      }
      return c;
    }

    print('P6 meta ops now: ${metaOps()}');
    for (var i = 0; i < 3; i++) {
      r.a.dropRecordersForTest();
      r.b.dropRecordersForTest();
      await r.a.syncPull(r.nbA);
      await r.b.syncPull(r.nbB);
      print('P6 restart round $i meta ops: ${metaOps()}');
    }
  });
}
