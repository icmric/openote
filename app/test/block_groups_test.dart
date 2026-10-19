// Grouping things that are not ink, which is most things.
//
// The owner: *"I want to be able to select multiple items (of any kind,
// whether it be content boxes, graphs, ink, any thing and any combination of
// anything), right click on the selection area and be able to press 'group'
// (or be able to right click on any individual grouped item and see
// 'ungroup') which will group them all together. This basically makes them
// behave as if ive gone through and selected them all even if ive only
// selected one. It should be non descructive and reversable."*
//
// A group is therefore a *relationship* and not a container: one string on
// each member, every block keeping its own geometry and type, and the only
// thing it asserts is that selecting one selects the rest. Nothing moves when
// a group is made or taken apart, which is what makes both directions free.
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
    tmp = Directory.systemTemp.createTempSync('onote_groups_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Groups');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    await app
        .selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
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

  /// One of everything, because "any combination of anything" is the ask.
  Block add(BlockType type, double x, double y,
          {Map<String, dynamic>? content}) =>
      app.addBlock(Block(
        type: type,
        x: x,
        y: y,
        w: 120,
        content: content ?? {'text': 'x'},
      ))
        ..x = x
        ..y = y;

  test('SELECTING ONE OF A GROUP SELECTS ALL OF IT', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final text = add(BlockType.text, 0, 0);
    final graph = add(BlockType.graph, 200, 0, content: {'expr': 'x'});
    final ink = add(BlockType.ink, 400, 0, content: {'strokes': const []});
    final loner = add(BlockType.text, 600, 0);

    app.selectMany([text.id, graph.id, ink.id]);
    expect(app.groupSelected(), isTrue);
    app.select(null); // put it down, the way anybody would

    app.select(graph.id);
    expect(app.selectedIds, {text.id, graph.id, ink.id},
        reason: 'one click, three blocks, three different kinds');
    expect(app.selectedIds, isNot(contains(loner.id)));
    app.cancelPendingSave();
  });

  test('AND IT MOVES AS ONE, WITHOUT HAVING BECOME ONE', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final a = add(BlockType.text, 0, 0);
    final b = add(BlockType.image, 200, 100, content: {'hash': 'sha256:x'});
    app.selectMany([a.id, b.id]);
    app.groupSelected();
    app.select(null);

    app.select(a.id);
    app.moveSelectedBy(10, 20);

    expect([a.x, a.y], [10.0, 20.0]);
    expect([b.x, b.y], [210.0, 120.0],
        reason: 'the other one came along, keeping its own geometry');
    expect(b.type, BlockType.image, reason: 'and its own type');
    app.cancelPendingSave();
  });

  test('UNGROUPING LEAVES EVERYTHING EXACTLY WHERE IT IS', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final a = add(BlockType.text, 0, 0);
    final b = add(BlockType.text, 200, 100);
    app.selectMany([a.id, b.id]);
    app.groupSelected();
    final where = [a.x, a.y, b.x, b.y];

    app.select(null);
    app.select(a.id);
    expect(app.ungroupSelected(), isTrue);

    expect([a.x, a.y, b.x, b.y], where, reason: 'non-destructive, both ways');
    expect(a.group, isNull);
    expect(b.group, isNull);
    app.select(a.id);
    expect(app.selectedIds, {a.id}, reason: 'and selecting one is one again');
    app.cancelPendingSave();
  });

  test('an undo puts the group back, because it is just a field', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final a = add(BlockType.text, 0, 0);
    final b = add(BlockType.text, 200, 0);
    app.selectMany([a.id, b.id]);
    app.groupSelected();
    final g = a.group;
    expect(g, isNotNull);

    app.ungroupSelected();
    expect(app.blockById(a.id)!.group, isNull);
    app.undo();
    expect(app.blockById(a.id)!.group, g);
    app.cancelPendingSave();
  });

  group('what the menu offers', () {
    test('nothing to group when only one thing is held', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final a = add(BlockType.text, 0, 0);
      app.select(a.id);
      expect(app.groupSelected(), isFalse);
      expect(app.selectionIsOneGroup, isFalse);
      app.cancelPendingSave();
    });

    test('and nothing to group when they already are one', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final a = add(BlockType.text, 0, 0);
      final b = add(BlockType.text, 200, 0);
      app.selectMany([a.id, b.id]);
      app.groupSelected();
      app.select(null);
      app.select(a.id);

      expect(app.selectionIsOneGroup, isTrue,
          reason: 'which is what hides the row, leaving Ungroup');
      app.cancelPendingSave();
    });

    test('nothing to ungroup when nothing is grouped', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final a = add(BlockType.text, 0, 0);
      app.select(a.id);
      expect(app.ungroupSelected(), isFalse);
      app.cancelPendingSave();
    });
  });

  group('a grouped box can still be typed in', () {
    test('THE SECOND CLICK GOES INTO THE ONE YOU CLICKED', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final a = add(BlockType.text, 0, 0);
      final b = add(BlockType.text, 200, 0);
      app.selectMany([a.id, b.id]);
      app.groupSelected();
      app.select(null);

      // First click: the group.
      app.select(a.id, edit: true);
      expect(app.selectedIds, {a.id, b.id});
      expect(app.editingBlockId, isNull,
          reason: 'a group that opened an editor on the first click would '
              'never be a group');

      // Second click, on the same block: into it.
      app.select(a.id, edit: true);
      expect(app.editingBlockId, a.id);
      expect(app.selectedIds, {a.id},
          reason: 'and the group lets go while you are in one of them');
      app.cancelPendingSave();
    });
  });

  test('a member copied to another page is a group of one', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // The cost of a field on the member rather than a list on the page, and
    // the reason it is the cheaper of the two: a dangling group id selects
    // itself and is indistinguishable from not being grouped.
    final a = add(BlockType.text, 0, 0);
    final b = add(BlockType.text, 200, 0);
    app.selectMany([a.id, b.id]);
    app.groupSelected();

    final nb = app.notebookId!;
    final other = app.importNode(
        nb,
        TreeNode(
            kind: NodeKind.page, title: '2', position: 'a000000000000002'));
    app.importPage(nb, other.id, [a], PageProps());
    final there = app.readPage(other.id).blocks.single;
    expect(there.group, isNotNull, reason: 'the id travels with it');

    app.cancelPendingSave();
  });
}
