// Consistency pass: copy/paste must carry EVERY block faithfully — the
// clone goes through toJson/fromJson now, because the hand-built copy
// dropped rotation and, worse, rawType + unknownFields: pasting a block a
// newer build had written destroyed its type on the spot.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/core/ids.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_paste_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('T');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
    await app.selectPage(page.id);
  });

  tearDown(() {
    AppState.syncLogEnabled = true;
    if (!haveSqlite) return;
    app.cancelPendingSave();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a from-the-future block survives copy → paste whole', () {
    if (!haveSqlite) return;
    // A block type this build has never heard of, with a field it has
    // never heard of — exactly what a newer Openote would write.
    final exotic = Block.fromJson({
      'id': newId(),
      'type': 'hologram',
      'x': 10.0,
      'y': 200.0,
      'w': 300.0,
      'rotation': 45.0,
      'content': {'beam': 3},
      'future_field': 'kept',
    });
    app.addBlock(exotic, recordUndo: false);

    app.selectMany([exotic.id]);
    app.copySelectedBlocks();
    app.pasteBlocks();

    final pasted = app.blocks.firstWhere((b) => b.id != exotic.id);
    expect(pasted.id, isNot(exotic.id), reason: 'fresh identity');
    final j = pasted.toJson();
    expect(j['type'], 'hologram',
        reason: 'rawType carries the unknown type — paste must not '
            'flatten it to "unknown"');
    expect(j['future_field'], 'kept',
        reason: 'unknownFields ride along');
    expect(pasted.rotation, 45.0);
    expect(pasted.x, exotic.x + 28, reason: 'offset placement still applies');
    expect(pasted.content['beam'], 3);
  });

  test('ink still re-anchors: stroke ids fresh, coordinates offset', () {
    if (!haveSqlite) return;
    final ink = Block.fromJson({
      'id': newId(),
      'type': 'ink',
      'x': 50.0,
      'y': 300.0,
      'w': 100.0,
      'content': {
        'strokes': [
          {
            'id': 'stroke-1',
            'x': [50.0, 60.0],
            'y': [300.0, 310.0],
          }
        ]
      },
    });
    app.addBlock(ink, recordUndo: false);
    app.selectMany([ink.id]);
    app.copySelectedBlocks();
    app.pasteBlocks();

    final pasted = app.blocks.firstWhere((b) => b.id != ink.id);
    final stroke = (pasted.content['strokes'] as List).first as Map;
    expect(stroke['id'], isNot('stroke-1'));
    expect((stroke['x'] as List).first, 50.0 + 28);
    expect((stroke['y'] as List).first, 300.0 + 28);
  });
}
