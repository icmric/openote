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
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/state/builtin_templates.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/study/flashcards.dart';

import 'support/sqlite.dart';

/// How many blocks a built-in template contains, without applying it.
int _blockCount(AppState app, String name) {
  final raw = builtinTemplates[name];
  if (raw == null) return 0;
  return ((jsonDecode(raw) as Map)['blocks'] as List).length;
}

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

  group('it respects the page it lands on', () {
    // "They dont respect the current layout of the page (with the title and
    // stuff), they just go over it all." Templates are authored on an empty
    // page, so their blocks carry coordinates that sit over the title band and
    // over whatever you had already written.

    Block existing({double y = 200, double h = 120}) => Block(
        type: BlockType.text,
        x: 44,
        y: y,
        w: 300,
        h: h,
        content: {'text': 'My own notes'});

    test('on an empty page it starts below the title band', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.applyTemplate(builtinTemplates.keys.first);
      final top = app.blocks.map((b) => b.y).reduce((a, b) => a < b ? a : b);
      expect(top, greaterThanOrEqualTo(AppState.contentTop),
          reason: 'nothing may sit over the title and date');
    });

    test('on a page with content it lands underneath, touching nothing',
        () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final mine = existing();
      app.blocks = [mine];
      final wasY = mine.y;

      app.applyTemplate(builtinTemplates.keys.first);

      expect(mine.y, wasY, reason: 'my block did not move');
      expect(mine.content['text'], 'My own notes');
      final added = app.blocks.where((b) => b.id != mine.id);
      expect(added, isNotEmpty);
      for (final b in added) {
        expect(b.y, greaterThan(wasY + 120),
            reason: 'every template block is below what was already there');
        expect(b.z, greaterThan(mine.z),
            reason: 'and on top of the stack, not buried under it');
      }
    });

    test('the template keeps its own shape when it is moved', () {
      // Translated as one piece: the blocks' positions RELATIVE to each other
      // are what makes a template look like a template.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final name = builtinTemplates.keys
          .firstWhere((n) => _blockCount(app, n) > 1, orElse: () => '');
      if (name.isEmpty) return markTestSkipped('no multi-block built-in');

      app.applyTemplate(name);
      final onEmpty = [for (final b in app.blocks) (b.x, b.y)];

      app.blocks = [existing()];
      app.applyTemplate(name);
      final onBusy = [
        for (final b in app.blocks.where((b) => b.content['text'] != 'My own notes'))
          (b.x, b.y)
      ];

      expect(onBusy.length, onEmpty.length);
      final shift = onBusy.first.$2 - onEmpty.first.$2;
      for (var i = 0; i < onEmpty.length; i++) {
        expect(onBusy[i].$1, onEmpty[i].$1, reason: 'x is unchanged');
        expect(onBusy[i].$2 - onEmpty[i].$2, closeTo(shift, 0.01),
            reason: 'every block shifted by the same amount');
      }
    });

    test('it does not rewrite the page settings of a page in use', () {
      // Applying a template to a page you have been working on must not
      // silently change its background or its grid.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.blocks = [existing()];
      app.pageProps.background = 'grid';
      app.applyTemplate(builtinTemplates.keys.first);
      expect(app.pageProps.background, 'grid');
    });
  });

  group('they teach the study loop by using it', () {
    // The one thing a template can do that a blank page cannot. A Question or
    // Definition tag on an EMPTY line makes no card — so a template can mark
    // the line in advance and the card appears the moment the student writes
    // on it, which is how someone discovers the feature exists.
    test('Revision sheet brings real flashcards with it', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.applyTemplate('Revision sheet');
      expect(app.blocks.where((b) => b.type == BlockType.flashcard),
          isNotEmpty);
    });

    test('a tagged template line becomes a card once it is written on', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.applyTemplate('Revision sheet');
      final tagged = app.blocks.firstWhere(
          (b) => (b.content['tags'] as List?)?.isNotEmpty ?? false);
      expect(cardsFromBlock(tagged, 'p', 't'), isEmpty,
          reason: 'an empty tagged line is not a card yet');

      const nl = '\n';
      final lines = (tagged.content['text'] as String).split(nl);
      lines[1] = 'Derivative — the rate at which a function changes';
      tagged.content['text'] = lines.join(nl);

      final cards = cardsFromBlock(tagged, 'p', 't');
      expect(cards, hasLength(1),
          reason: 'writing on the line is all it takes');
      expect(cards.single.front, 'Derivative');
    });

    test('no built-in puts a card in the deck before you write anything', () {
      // The tags are an invitation, not content. A template that quietly added
      // cards would have you revising its own placeholder text.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      for (final name in builtinTemplates.keys) {
        app.blocks = [];
        app.applyTemplate(name);
        for (final b in app.blocks) {
          expect(cardsFromBlock(b, 'p', 't'), isEmpty,
              reason: '"$name" arrived with a card already in it');
        }
      }
    });
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
