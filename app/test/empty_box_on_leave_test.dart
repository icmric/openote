// Leaving a page while an empty text box is open must not save the box.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  test('an empty box is gone when the person moves to another page', () async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    final tmp = Directory.systemTemp.createTempSync('onote_empty_');
    final repo = await Repository.openAt(tmp);
    addTearDown(() {
      AppState.syncLogEnabled = true;
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final nb = await repo.createNotebook('T');
    final app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    await app.addPage();
    app.reloadNodes();
    final pages = app.nodes.where((n) => n.kind == NodeKind.page).toList();
    await app.selectPage(pages.first.id);

    final kept = Block(type: BlockType.text, x: 40, y: 100, w: 300, content: {'text': 'hello'});
    final empty = Block(type: BlockType.text, x: 40, y: 200, w: 300, content: {'text': ''});
    app.addBlock(kept, recordUndo: false);
    app.addBlock(empty, recordUndo: false);
    // Clicking the page opened a box, and the person went elsewhere.
    app.pendingEmptyBlockId = empty.id;
    app.select(empty.id, edit: true);

    await app.selectPage(pages.last.id);
    await app.selectPage(pages.first.id);
    expect(app.blocks.map((b) => b.id), [kept.id],
        reason: 'the box with words stays, the empty one never saved');
    app.cancelPendingSave();
  });
}
