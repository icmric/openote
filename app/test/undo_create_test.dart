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
}
