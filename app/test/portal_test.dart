// Live page embeds (EMBED-2…7): a portal is a pointer, never a copy.
//
// What matters here, in order: the reference round-trips in the spec's shape;
// the refs index sees an embed (backlinks, deletion warnings later); the
// window renders the SOURCE page's real content; an edit to the source is
// visible through the window without anything being stored twice; and the two
// classic failure modes — a deleted source and a circular embed — degrade to
// labelled chips instead of crashes.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/portal_view.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  group('the reference itself', () {
    test('round-trips through the spec shape', () {
      final content =
          PortalRef.contentFor('page-1', rect: const Rect.fromLTWH(10, 20, 300, 200));
      final ref = PortalRef.parse(content);
      expect(ref, isNotNull);
      expect(ref!.pageId, 'page-1');
      expect(ref.wholePage, isFalse);
      expect(ref.rect, const Rect.fromLTWH(10, 20, 300, 200));

      final whole = PortalRef.parse(PortalRef.contentFor('page-2'));
      expect(whole!.wholePage, isTrue);
      expect(whole.rect, isNull);
    });

    test('refuses what it cannot honour, rather than misrendering', () {
      expect(PortalRef.parse({}), isNull);
      expect(PortalRef.parse({'ref': {}}), isNull);
      // A later build's block/range/frame target: chip, not crash — and
      // never a rect guessed from half-parsed fields.
      expect(
          PortalRef.parse({
            'ref': {
              'pageId': 'p',
              'target': {'kind': 'frame', 'frameId': 'f'}
            }
          }),
          isNull);
      // Cross-notebook is not implemented; rendering another notebook's ids
      // against this one would show the wrong page's content.
      expect(
          PortalRef.parse({
            'ref': {
              'notebookId': 'other',
              'pageId': 'p',
              'target': {'kind': 'page'}
            }
          }),
          isNull);
    });
  });

  group('with a real notebook', () {
    late Repository repo;
    late Directory tmp;
    late AppState app;
    late String hostId;
    late String srcId;

    setUp(() async {
      if (!haveSqlite) return;
      // The op log's workspace debounce would be a pending timer inside
      // testWidgets' fake-async zone; it is not what these tests are about.
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_portal_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Portals');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      hostId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
      final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
      srcId = repo
          .upsertNode(app.notebookId!,
              TreeNode(kind: NodeKind.page, parentId: section.id, title: 'Source'))
          .id;
      app.reloadNodes();
      await app.selectPage(hostId);
    });

    tearDown(() {
      AppState.syncLogEnabled = true;
      if (!haveSqlite) return;
      app.cancelPendingSave();
      PortalSource.resetCache();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    void writeSource(String text) {
      repo.writePage(
        app.notebookId!,
        srcId,
        [
          Block(
              id: 'src-text',
              type: BlockType.text,
              x: 80,
              y: 60,
              w: 320,
              content: {'text': text, 'autoWidth': false})
        ],
        PageProps(),
      );
    }

    Block embedBlock({Rect? rect, String? page}) => Block(
          type: BlockType.embed,
          x: 40,
          y: 40,
          w: 380,
          content: PortalRef.contentFor(page ?? srcId, rect: rect),
        );

    Widget host(Block b) => MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: app,
              builder: (_, __) => SizedBox(
                width: 600,
                height: 700,
                child: PortalBlockView(block: b, app: app),
              ),
            ),
          ),
        );

    test('an embed shows up in the refs index — backlinks see it', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      writeSource('anything');
      repo.writePage(app.notebookId!, hostId, [embedBlock()], PageProps());
      expect(repo.backlinkPageIds(app.notebookId!, srcId), contains(hostId),
          reason: 'notebook_writer indexes embed refs like links');
    });

    test('the portal renders copies, never the shared page cache', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      writeSource('shared state is sacred');
      final src = PortalSource.of(app, srcId);
      final shared = app.readPageShared(srcId);
      expect(src.blocks.single.id, 'portal:src-text',
          reason: 'prefixed ids can never collide with editingBlockId');
      expect(identical(src.blocks.single.content, shared.blocks.single.content),
          isFalse,
          reason: 'a view that mutated its block must not corrupt the cache');
      // Same underlying page object → same derived object: no per-frame work.
      expect(identical(PortalSource.of(app, srcId), src), isTrue);
    });

    testWidgets('IT SHOWS THE SOURCE, AND IT KEEPS UP', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      writeSource('the mitochondria is the powerhouse');
      await t.pumpWidget(host(embedBlock()));
      await t.pump();

      expect(find.textContaining('mitochondria', findRichText: true),
          findsWidgets,
          reason: 'the window renders the real page content');
      expect(find.textContaining('Source', findRichText: true), findsWidgets,
          reason: 'the badge names where the content comes from (EMBED-3)');

      // The source page changes — a save, an undo, a sync pull all end in
      // writePage, which evicts the decoded-page cache. The next host
      // rebuild reads fresh. That is the entire liveness mechanism.
      writeSource('actually it is the ribosome');
      app.select(null); // any notification the host page already gets
      await t.pump();

      expect(find.textContaining('ribosome', findRichText: true), findsWidgets,
          reason: 'edits to the source are visible through the window');
      expect(find.textContaining('mitochondria', findRichText: true),
          findsNothing);
    });

    testWidgets('a region shows only what is inside it', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      repo.writePage(
        app.notebookId!,
        srcId,
        [
          Block(
              type: BlockType.text,
              x: 80,
              y: 60,
              w: 300,
              content: {'text': 'inside the window', 'autoWidth': false}),
          Block(
              type: BlockType.text,
              x: 80,
              y: 2000,
              w: 300,
              content: {'text': 'far below it', 'autoWidth': false}),
        ],
        PageProps(),
      );
      await t.pumpWidget(
          host(embedBlock(rect: const Rect.fromLTWH(60, 40, 360, 200))));
      await t.pump();

      expect(
          find.textContaining('inside the window', findRichText: true),
          findsWidgets);
      expect(find.textContaining('far below', findRichText: true), findsNothing,
          reason: 'blocks outside the region are not even built');
    });

    testWidgets('a circular embed chips instead of recursing', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // Host embeds Source; Source embeds Host. Rendering the first must not
      // recurse — EMBED-7, the Obsidian-PDF-infinite-loop class of bug.
      repo.writePage(app.notebookId!, srcId,
          [embedBlock(page: hostId, rect: const Rect.fromLTWH(0, 0, 400, 300))],
          PageProps());
      repo.writePage(app.notebookId!, hostId,
          [embedBlock(rect: const Rect.fromLTWH(0, 0, 400, 300))], PageProps());

      await t.pumpWidget(
          host(embedBlock(rect: const Rect.fromLTWH(0, 0, 400, 300))));
      await t.pump();

      expect(find.textContaining('circular', findRichText: true), findsWidgets,
          reason: 'the cycle is named, not followed');
    });

    testWidgets('a deleted source degrades to a tombstone', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await t.pumpWidget(host(embedBlock(page: 'no-such-page')));
      await t.pump();
      expect(find.textContaining('deleted', findRichText: true), findsWidgets,
          reason: 'EMBED-6: a broken ref is information, not an error');
    });

    testWidgets('a whole-page window onto its own page refuses politely',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await t.pumpWidget(host(embedBlock(page: hostId)));
      await t.pump();
      expect(
          find.textContaining('its own page', findRichText: true), findsWidgets,
          reason: 'a window whose extent includes itself recurses by '
              'construction');
    });
  });
}
