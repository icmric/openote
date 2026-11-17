// A picture copied in one notebook and pasted into another keeps its bytes.
//
// Found on #39: blobs are per notebook, and a copied box carries its
// picture's hash rather than the picture. Pasted into a different notebook it
// named bytes that notebook did not have — a blank box here, and on every
// device the notebook syncs to. Paste now carries the bytes across.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

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
  late String first, second;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_paste_across_');
    repo = await Repository.openAt(tmp);
    first = (await repo.createNotebook('First')).id;
    second = (await repo.createNotebook('Second')).id;
    app = AppState(repo)..spellCheckEnabled = false;
    await app.selectNotebook(first);
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

  Uint8List bytes(int seed) =>
      Uint8List.fromList([for (var i = 0; i < 300; i++) (i * seed) & 0xff]);

  test('a picture box pasted into another notebook brings its picture',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final hash = app.addBlob(bytes(7), 'image/png');
    final pic = Block(
        type: BlockType.image,
        x: 40,
        y: 40,
        w: 120,
        h: 120,
        content: {'blob': hash, 'mime': 'image/png'});
    app.addBlock(pic, recordUndo: false);
    app.select(pic.id);
    app.copySelectedBlocks();
    await app.settleBlockClipboard();

    await app.selectNotebook(second);
    expect(app.notebookId, second);
    expect(app.blob(hash), isNull, reason: 'not there before the paste');

    app.pasteBlocks();
    final pasted = app.blocks.where((b) => b.type == BlockType.image).single;
    expect(pasted.content['blob'], hash, reason: 'the same reference');
    expect(app.blob(hash), bytes(7), reason: 'and the bytes behind it');
  });

  test('a picture inside text comes across too', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final hash = app.addBlob(bytes(11), 'image/png');
    final box = Block(
        type: BlockType.text,
        x: 40,
        y: 40,
        content: {'text': 'see ![a](sha256:$hash) here'});
    app.addBlock(box, recordUndo: false);
    app.select(box.id);
    app.copySelectedBlocks();
    await app.settleBlockClipboard();

    await app.selectNotebook(second);
    app.pasteBlocks();
    expect(app.blob(hash), bytes(11));
  });

  test('pasting back into the same notebook copies nothing', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final hash = app.addBlob(bytes(13), 'image/png');
    final pic = Block(
        type: BlockType.image,
        x: 40,
        y: 40,
        w: 120,
        h: 120,
        content: {'blob': hash, 'mime': 'image/png'});
    app.addBlock(pic, recordUndo: false);
    app.select(pic.id);
    app.copySelectedBlocks();
    await app.settleBlockClipboard();
    app.pasteBlocks();
    expect(app.blocks.where((b) => b.type == BlockType.image), hasLength(2));
    expect(repo.getBlob(second, hash), isNull,
        reason: 'nothing written anywhere else');
  });
}
