// Joining things on the canvas so they stay joined (CANVAS-7).
//
// A stroke is its own block, so a written word is already several of them and
// the lasso is the only thing that gathers them — which meant the gathering
// lasted exactly as long as the selection. The owner, on strokes: *"unless
// they are grouped together, which from what i can see hasnt actually been
// implemented yet"*.
//
// The whole feature is one rule in one place: **a selection is closed over
// groups**. Everything that acts on a selection — the drag, Delete, copy, cut
// — already worked off `selectedIds`, so none of it needed to learn what a
// group is. Most of what is pinned here is that closure holding at each of the
// ways a selection can be made, and the identity rules that stop a copy
// joining the thing it was copied from.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/app_shell.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  // ── The envelope field, with no app around it ───────────────────────────

  group('groupId on the wire', () {
    test('round-trips', () {
      final b = Block(type: BlockType.text, x: 0, y: 0, groupId: 'g-1');
      final back = Block.fromJson(jsonDecode(jsonEncode(b.toJson())));
      expect(back.groupId, 'g-1');
    });

    test('is omitted entirely when there is none', () {
      final b = Block(type: BlockType.text, x: 0, y: 0);
      expect(b.toJson().containsKey('groupId'), isFalse,
          reason: 'an unconditional "groupId": null would change the JSON of '
              'every block ever written, so the next save of an untouched '
              'notebook would rewrite all of it (Data Model Spec §3.2 rule 4)');
    });

    test('a reader that does not know the field writes it back untouched', () {
      // What an older release does: `groupId` is not in ITS `_known` set, so
      // it arrives as an unknown field and leaves the same way. Simulated by
      // handing a block a key this build does not know either — the mechanism
      // is the same one, and it is what makes membership survive a round-trip
      // through a build that has never heard of groups (§3.2 rule 5).
      final j = Block(type: BlockType.text, x: 0, y: 0).toJson()
        ..['somethingLater'] = 'kept';
      final back = Block.fromJson(jsonDecode(jsonEncode(j)));
      expect(back.toJson()['somethingLater'], 'kept');
    });
  });

  // ── The rules, on a real page ──────────────────────────────────────────

  group('on a page', () {
    late Repository repo;
    late Directory tmp;
    late AppState app;

    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_group_');
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
      if (!haveSqlite) return;
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    Block add({double x = 100, double y = 100, bool locked = false}) =>
        app.addBlock(Block(
          type: BlockType.text,
          x: x,
          y: y,
          w: 120,
          h: 40,
          content: {'text': 'x', if (locked) 'locked': true},
        ));

    /// The group id every one of [ids] shares, or null if they do not share
    /// one. Written as a question about the set so a test never has to pick a
    /// member to speak for the rest.
    String? sharedGroup(Iterable<String> ids) {
      final gs = {
        for (final b in app.blocks)
          if (ids.contains(b.id)) b.groupId
      };
      return gs.length == 1 ? gs.single : null;
    }

    test('two selected blocks become one group', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final a = add(), b = add(y: 200);
      app.selectMany([a.id, b.id]);
      expect(app.canGroup, isTrue);

      app.groupSelected();

      expect(sharedGroup([a.id, b.id]), isNotNull);
      expect(app.canUngroup, isTrue);
      expect(app.canGroup, isFalse,
          reason: 'one whole group is already grouped — the answer is Ungroup');
    });

    test('one block is not a group', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final a = add();
      app.select(a.id);
      expect(app.canGroup, isFalse);
      app.groupSelected();
      expect(a.groupId, isNull);
    });

    test('ungroup puts them back', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final a = add(), b = add(y: 200);
      app.selectMany([a.id, b.id]);
      app.groupSelected();

      app.ungroupSelected();

      expect(a.groupId, isNull);
      expect(b.groupId, isNull);
      expect(app.canUngroup, isFalse);
    });

    test('clicking one member selects the whole group', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final a = add(), b = add(y: 200), loose = add(y: 400);
      app.selectMany([a.id, b.id]);
      app.groupSelected();

      app.select(a.id);

      expect(app.selectedIds, {a.id, b.id});
      expect(app.selectedIds, isNot(contains(loose.id)));
      expect(app.selectedBlockId, a.id,
          reason: 'the block under the pointer stays the primary one');
    });

    test('a marquee that catches half a group takes all of it', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final a = add(), b = add(y: 200);
      app.selectMany([a.id, b.id]);
      app.groupSelected();

      app.selectMany([a.id]); // what a marquee over `a` alone reports

      expect(app.selectedIds, {a.id, b.id});
    });

    test('shift-click toggles the group, not the member', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final a = add(), b = add(y: 200), loose = add(y: 400);
      app.selectMany([a.id, b.id]);
      app.groupSelected();

      app.select(loose.id);
      app.select(a.id, additive: true);
      expect(app.selectedIds, {loose.id, a.id, b.id});

      app.select(a.id, additive: true);
      expect(app.selectedIds, {loose.id},
          reason: 'taking a group out one member at a time would leave the '
              'partial selection the closure exists to prevent');
    });

    test('a group of strokes moves as one, ink coordinates and all', () {
      // The case the item exists for. A stroke is its own block, so a written
      // word is several of them and a marquee over the word is what gathers
      // them without the lasso's merge — Ctrl+G then makes that gathering
      // outlive the selection. Ink is the one type whose move does more than
      // shift x/y: stroke coordinates are page-absolute (Ink Spec §3) and have
      // to be translated too, per member.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      Block stroke(double x) => app.addBlock(Block(
            type: BlockType.ink,
            x: x,
            y: 140,
            w: 60,
            h: 50,
            content: {
              'strokes': [
                {
                  'id': 's${x.toInt()}',
                  'brush': {
                    'tool': 'pen',
                    'color': 'auto',
                    'size': 3.0,
                    'opacity': 1.0
                  },
                  'x': [x, x + 20],
                  'y': [150.0, 170.0],
                  'p': <double>[],
                }
              ]
            },
          ));
      final a = stroke(120), b = stroke(220);
      app.selectMany([a.id, b.id]);
      app.groupSelected();
      expect(sharedGroup([a.id, b.id]), isNotNull);

      double firstX(Block blk) =>
          ((blk.content['strokes'] as List).first as Map)['x'][0] as double;
      final ax = firstX(a), bx = firstX(b);

      app.select(a.id); // one stroke clicked — the word is picked up
      app.moveSelectedBy(40, 0);

      expect(firstX(a), ax + 40);
      expect(firstX(b), bx + 40,
          reason: 'the other stroke of the word came with it, ink and all');
    });

    test('a group moves as one', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final a = add(), b = add(y: 200);
      app.selectMany([a.id, b.id]);
      app.groupSelected();
      final ax = a.x, bx = b.x;

      app.select(a.id); // one member picked up
      app.moveSelectedBy(30, 0);

      expect(a.x, ax + 30);
      expect(b.x, bx + 30, reason: 'the other member came with it');
    });

    test('a group deletes as one', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final a = add(), b = add(y: 200), loose = add(y: 400);
      app.selectMany([a.id, b.id]);
      app.groupSelected();

      app.select(a.id);
      app.removeSelected();

      expect(app.blocks.map((e) => e.id), [loose.id]);
    });

    test('grouping across two groups merges them rather than nesting', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final a = add(), b = add(y: 200), c = add(y: 400), d = add(y: 600);
      app.selectMany([a.id, b.id]);
      app.groupSelected();
      final first = a.groupId;
      app.selectMany([c.id, d.id]);
      app.groupSelected();
      expect(c.groupId, isNot(first));

      app.selectMany([a.id, c.id]); // closure pulls in b and d
      expect(app.selectedIds, {a.id, b.id, c.id, d.id});
      app.groupSelected();

      expect(sharedGroup([a.id, b.id, c.id, d.id]), isNotNull,
          reason: 'one id per block — there is nowhere to nest');
    });

    test('a group of one is tidied away when the rest go', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final a = add(), b = add(y: 200);
      app.selectMany([a.id, b.id]);
      app.groupSelected();

      app.removeBlock(a.id);

      expect(b.groupId, isNull,
          reason: 'a lone survivor is not grouped with anything (§3.2 rule 2)');
      expect(app.canUngroup, isFalse);
    });

    test('a locked block does not join a group', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final slide = add(locked: true);
      final a = add(y: 200), b = add(y: 400);
      app.selectMany([slide.id, a.id, b.id]);
      app.groupSelected();

      expect(slide.groupId, isNull,
          reason: 'a member that refuses to move is a group that cannot be '
              'dragged');
      expect(sharedGroup([a.id, b.id]), isNotNull);
    });

    test('a duplicate does not join the original group', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final a = add(), b = add(y: 200);
      app.selectMany([a.id, b.id]);
      app.groupSelected();

      app.duplicateBlock(a.id);

      final copy = app.blocks.firstWhere((e) => e.id != a.id && e.id != b.id);
      expect(copy.groupId, isNull,
          reason: 'otherwise dragging the original would carry the copy off');
    });

    test('a pasted group is its own group', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final a = add(), b = add(y: 200);
      app.selectMany([a.id, b.id]);
      app.groupSelected();
      final original = a.groupId;

      app.select(a.id); // closure selects both
      app.copySelectedBlocks();
      app.pasteBlocks();

      expect(app.blocks, hasLength(4));
      final pasted = app.blocks.where((e) => e.id != a.id && e.id != b.id);
      expect(pasted, hasLength(2));
      final theirs = sharedGroup(pasted.map((e) => e.id));
      expect(theirs, isNotNull, reason: 'the copies are a group of their own');
      expect(theirs, isNot(original),
          reason: 'a groupId is a link within the selection, so rule 3 remaps '
              'it — carried over, the copies would join what they came from');
      expect(a.groupId, original, reason: 'the original is untouched');
    });

    test('pasting one member of a group is not a group', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final a = add(), b = add(y: 200);
      app.selectMany([a.id, b.id]);
      app.groupSelected();

      // Only `a` — selectMany would close over the group, so the clipboard is
      // loaded from a selection made deliberately narrow.
      app.selectedIds
        ..clear()
        ..add(a.id);
      app.copySelectedBlocks();
      app.pasteBlocks();

      final copy = app.blocks.firstWhere((e) => e.id != a.id && e.id != b.id);
      expect(copy.groupId, isNull);
    });
  });

  // ── Reaching inside a group with the pointer ────────────────────────────
  //
  // The one place grouping changes a gesture that already meant something. A
  // left click has opened a text box for editing since the beginning, so a
  // grouped text box has to answer for its group first and still be typeable
  // second: the first click picks the group up, and the next one — now that
  // the group is held — goes to the member under the pointer.

  group('clicking a grouped text box', () {
    late Repository repo;
    late Directory tmp;
    late AppState app;

    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_group_tap_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Groups');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
    });

    tearDown(() {
      if (!haveSqlite) return;
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    Block note(String text, double y) => Block(
          type: BlockType.text,
          x: 80,
          y: y,
          w: 300,
          h: 44,
          content: {'text': text, 'autoWidth': false},
        );

    Future<void> pumpShell(WidgetTester tester, List<Block> blocks) async {
      final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
      app.importPage(app.notebookId!, page.id, blocks, PageProps());
      app.reloadNodes();
      await app.selectPage(page.id);
      app.markOnboardingSeen();
      tester.view.physicalSize = const Size(1500, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: kOnoteLocalizations,
        supportedLocales: kOnoteLocales,
        theme: onoteTheme(Brightness.light),
        home: AppShell(app: app),
      ));
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
    }

    testWidgets('the first click takes the group, the second opens the box',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(tester, [note('alpha', 120), note('beta', 220)]);
      final alpha = app.blocks.firstWhere(
          (b) => (b.content['text'] as String?) == 'alpha');
      final beta = app.blocks.firstWhere(
          (b) => (b.content['text'] as String?) == 'beta');
      app.selectMany([alpha.id, beta.id]);
      app.groupSelected();
      app.select(null);
      await tester.pumpAndSettle();

      await tester.tap(find.text('alpha').first);
      await tester.pumpAndSettle();
      expect(app.selectedIds, {alpha.id, beta.id},
          reason: 'the group is what was picked up');
      expect(app.editingBlockId, isNull,
          reason: 'the first click must not open a member, or the gesture '
              'that selects the group would be ambiguous');

      await tester.tap(find.text('alpha').first);
      await tester.pumpAndSettle();
      expect(app.editingBlockId, alpha.id,
          reason: 'the group is already held, so now the click reaches in');
      app.cancelPendingSave();
    });

    testWidgets('the button above a selection joins it, then offers to undo it',
        (tester) async {
      // The same argument that put Delete up there: joining strokes is what
      // the lasso is for, and Ctrl+G is not on a tablet held in one hand with
      // a pen in the other.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(tester, [note('alpha', 120), note('beta', 220)]);
      app.selectMany(app.blocks.map((b) => b.id));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.group_work_outlined), findsOneWidget);
      expect(find.byIcon(Icons.scatter_plot_outlined), findsNothing,
          reason: 'nothing is grouped yet');

      await tester.tap(find.byIcon(Icons.group_work_outlined));
      await tester.pumpAndSettle();

      expect({for (final b in app.blocks) b.groupId}, hasLength(1),
          reason: 'both carry the one id');
      expect(app.blocks.first.groupId, isNotNull);
      expect(find.byIcon(Icons.group_work_outlined), findsNothing,
          reason: 'one whole group has nothing left to group');
      expect(find.byIcon(Icons.scatter_plot_outlined), findsOneWidget);
      app.cancelPendingSave();
    });

    testWidgets('an ungrouped box still opens on the first click',
        (tester) async {
      // The behaviour that has been there since the beginning, pinned here
      // because the group rule sits directly in front of it.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(tester, [note('alpha', 120)]);

      await tester.tap(find.text('alpha').first);
      await tester.pumpAndSettle();

      expect(app.editingBlockId, app.blocks.single.id);
      app.cancelPendingSave();
    });
  });
}
