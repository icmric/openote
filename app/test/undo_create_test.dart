// Ctrl+Z takes back making a page, a section or a group; Ctrl+Y brings it back.
import 'dart:io';

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

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_undo_create_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('T');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    await app.selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
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

  int count(NodeKind k) => app.nodes.where((n) => n.kind == k).length;

  /// Undo or redo, then wait for the tree step (it finishes after a page switch).
  Future<void> step(void Function() f) async {
    f();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  test('a new page: undo removes it, redo brings it back', () async {
    if (!haveSqlite) return;
    final before = count(NodeKind.page);
    await app.addPage();
    final made = app.pageId!;
    expect(count(NodeKind.page), before + 1);

    await step(app.undo);
    expect(count(NodeKind.page), before);
    expect(app.nodes.any((n) => n.id == made), isFalse);
    expect(app.canRedo, isTrue, reason: 'redo is there after undo');

    await step(app.redo);
    expect(count(NodeKind.page), before + 1);
    expect(app.pageId, made, reason: 'and it opens on it');
    expect(app.canUndo, isTrue, reason: 'and can be undone again');
  });

  test('a new section goes with its first page, in one step', () async {
    if (!haveSqlite) return;
    final sections = count(NodeKind.section);
    final pages = count(NodeKind.page);
    await app.addSection();
    expect(count(NodeKind.section), sections + 1);

    await step(app.undo);
    expect(count(NodeKind.section), sections);
    expect(count(NodeKind.page), pages, reason: 'its page went with it');

    await step(app.redo);
    expect(count(NodeKind.section), sections + 1);
    expect(count(NodeKind.page), pages + 1, reason: 'and came back with it');
  });

  test('a new group, undone and redone', () async {
    if (!haveSqlite) return;
    final groups = count(NodeKind.sectionGroup);
    app.addSectionGroup();
    expect(count(NodeKind.sectionGroup), groups + 1);
    await step(app.undo);
    expect(count(NodeKind.sectionGroup), groups);
    await step(app.redo);
    expect(count(NodeKind.sectionGroup), groups + 1);
  });

  test('two creations in a row undo one at a time, newest first', () async {
    if (!haveSqlite) return;
    final groups = count(NodeKind.sectionGroup);
    app.addSectionGroup();
    app.addSectionGroup();
    await step(app.undo);
    expect(count(NodeKind.sectionGroup), groups + 1);
    await step(app.undo);
    expect(count(NodeKind.sectionGroup), groups);
    await step(app.redo);
    await step(app.redo);
    expect(count(NodeKind.sectionGroup), groups + 2);
  });

  // Found in the owner's 16 November trial: tree steps were cleared with the
  // page snapshots whenever another page opened, so a section made on one
  // page could not be taken back from the next.
  test('making something survives opening another page', () async {
    if (!haveSqlite) return;
    final groups = count(NodeKind.sectionGroup);
    final first = app.pageId!;
    app.addSectionGroup();
    expect(count(NodeKind.sectionGroup), groups + 1);

    // Wander off to a new page, and back again.
    await app.addPage();
    final elsewhere = app.pageId!;
    await app.selectPage(first);
    expect(app.canUndo, isTrue);

    await step(app.undo); // the page made while wandering
    expect(app.nodes.any((n) => n.id == elsewhere), isFalse);
    await step(app.undo); // and the group, made before any of it
    expect(count(NodeKind.sectionGroup), groups);
  });

  test("a page's own edits stay with that page", () async {
    if (!haveSqlite) return;
    final first = app.pageId!;
    await app.addPage();
    final other = app.pageId!;
    await app.selectPage(first);
    app.addBlock(
        Block(type: BlockType.text, x: 0, y: 0, content: {'text': 'kept'}));
    await app.flushSave();

    await app.selectPage(other);
    // The edit on the first page is not on this one, so the next step back
    // is making this page — not the first page's text poured into it.
    await step(app.undo);
    expect(app.nodes.any((n) => n.id == other), isFalse);
    await app.selectPage(first);
    expect(app.blocks.map((b) => b.content['text']), contains('kept'));
  });

  test('another notebook takes nothing with it', () async {
    if (!haveSqlite) return;
    app.addSectionGroup();
    final nb2 = await repo.createNotebook('Other');
    await app.selectNotebook(nb2.id);
    expect(app.canUndo, isFalse,
        reason: "the first notebook's group is not this one's to take back");
  });
}
