// Templates: "clicking on any of these does nothing, even on a totally fresh
// page."
//
// They were not unimplemented and the list was not empty. The whole path was
// wired, and it died on `Block.fromJson`'s non-nullable `j['id'] as String`
// the first time it touched a built-in — whose blocks are hand-written JSON
// with no ids. The throw happened after an await, inside a Future nobody
// awaited, so it produced no dialog, no red screen and no log in release: the
// button simply did nothing, and had done nothing since the day it shipped.
//
// There was no test for templates at all. That is why. These run the REAL
// state function against the REAL built-in data, so a template that cannot be
// parsed fails here instead of on a page.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/state/builtin_templates.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Repository repo;
  late Directory tmp;
  late AppState app;

  setUp(() async {
    if (!haveSqlite) return;
    tmp = Directory.systemTemp.createTempSync('onote_tpl_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Templates');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    final section = app.importNode(
        nb.id, TreeNode(kind: NodeKind.section, title: 'S', position: 'a0'));
    final page = app.importNode(
        nb.id,
        TreeNode(
            kind: NodeKind.page,
            parentId: section.id,
            title: 'P',
            position: 'a1'));
    app.reloadNodes();
    await app.selectPage(page.id);
  });

  tearDown(() {
    if (!haveSqlite) return;
    app.cancelPendingSave();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('there are built-ins to offer in the first place', () {
    expect(builtinTemplates, isNotEmpty);
  });

  group('every built-in actually applies', () {
    // Parameterised over the real data rather than one sample: the bug was
    // uniform — no built-in carried ids — so a single-template test would have
    // caught it, but a per-template one is what stops the NEXT hand-written
    // template shipping malformed.
    for (final name in builtinTemplates.keys) {
      test('"$name" puts blocks on the page', () {
        if (!haveSqlite) return markTestSkipped('sqlite unavailable');
        expect(app.blocks, isEmpty, reason: 'precondition: a fresh page');
        app.applyTemplate(name);
        expect(app.blocks, isNotEmpty,
            reason: '"$name" applied silently and left the page empty');
        for (final b in app.blocks) {
          expect(b.id, isNotEmpty);
          expect(b.type, isNot(BlockType.unknown),
              reason: 'a built-in must not contain an unreadable block type');
        }
      });
    }
  });

  test('applying twice gives two independent copies, not shared ids', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final name = builtinTemplates.keys.first;
    app.applyTemplate(name);
    final firstIds = app.blocks.map((b) => b.id).toSet();
    app.applyTemplate(name);
    final all = app.blocks.map((b) => b.id).toList();
    expect(all.toSet().length, all.length, reason: 'ids must be unique');
    expect(app.blocks.length, firstIds.length * 2);
  });

  test('it is one undo away', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.applyTemplate(builtinTemplates.keys.first);
    expect(app.blocks, isNotEmpty);
    app.undo();
    expect(app.blocks, isEmpty,
        reason: 'a template drops content onto a page you own');
  });

  test('an unknown name changes nothing rather than throwing', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.applyTemplate('no such template');
    expect(app.blocks, isEmpty);
  });

  group('a user template round-trips', () {
    test('save then apply reproduces the blocks', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.blocks = [
        Block(type: BlockType.text, x: 10, y: 20, w: 300, content: {
          'text': 'Weekly review',
        }),
      ];
      app.markDirty();
      app.saveCurrentAsTemplate('Mine');
      expect(app.templateNames(), contains('Mine'));

      app.blocks = [];
      app.applyTemplate('Mine');
      expect(app.blocks.length, 1);
      expect(app.blocks.single.content['text'], 'Weekly review');
      expect(app.blocks.single.x, 10);
    });

    test('a block from a NEWER build survives the round trip', () {
      // The format-freeze promise. `rawType` and `unknownFields` carry a block
      // this build cannot interpret; applying a template used to drop both, so
      // a template saved from such a page destroyed the block's identity —
      // silently, permanently, on a path the user thinks is a copy.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.blocks = [
        Block.fromJson({
          'id': 'b-future',
          'type': 'hologram',
          'x': 5.0,
          'y': 6.0,
          'rotation': 0.25,
          'content': {'depth': 3},
          'somethingNewEntirely': {'k': 'v'},
        }),
      ];
      expect(app.blocks.single.type, BlockType.unknown,
          reason: 'precondition: this build cannot read it');
      app.markDirty();
      app.saveCurrentAsTemplate('Future');

      app.blocks = [];
      app.applyTemplate('Future');
      final b = app.blocks.single;
      expect(b.rawType, 'hologram',
          reason: 'the type name is what a newer build reads back');
      expect(b.unknownFields['somethingNewEntirely'], {'k': 'v'});
      expect(b.rotation, 0.25);
      expect(b.toJson()['type'], 'hologram');
    });
  });
}
