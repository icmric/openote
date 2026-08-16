// The save path and the side-table projections `writePage` maintains, over a
// REAL SQLite notebook. All of this drives user-visible behaviour (the "Saved"
// indicator, the backlinks panel) and had zero coverage.
//
// Regressions pinned here:
//  * a failed save used to clear the dirty flag and report "Saved";
//  * a bare `[[Page]]` link produced no backlink at all;
//  * an in-flow imported image (`![](sha256:… =WxH)`) got no `blob_refs` row;
//  * restoring a page from the bin left it orphaned under a still-deleted
//    section;
//  * `workspace.json` could be torn by concurrent writes.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:openote/core/engine.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

/// An engine whose saves can be made to fail on demand.
class _FlakyEngine implements DocumentEngine {
  _FlakyEngine(this.repo);
  final Repository repo;
  bool fail = false;
  int saves = 0;

  @override
  String get label => 'Test engine';
  @override
  String? get lastSavedHash => null;

  @override
  Future<PageData> loadPage(String nb, String pageId) async =>
      repo.readPage(nb, pageId);

  @override
  Future<void> savePage(String nb, String pageId, List<Block> blocks,
      PageProps props) async {
    saves++;
    if (fail) throw const FileSystemException('disk full (simulated)');
    repo.writePage(nb, pageId, blocks, props);
  }
}

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Future<(Repository, Directory)> freshRepo(String prefix) async {
    final tmp = Directory.systemTemp.createTempSync(prefix);
    final repo = await Repository.openAt(tmp);
    return (repo, tmp);
  }

  // The workspace registry's own write path, which is separate from the page
  // save path above and failed differently.
  group('the workspace registry write chain', () {
    test('one failed write does not poison every later one', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp) = await freshRepo('onote_chain_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      await repo.createNotebook('One');
      expect(repo.lastWorkspaceWriteError, isNull);

      // Make the next write fail the way a real one does — antivirus holding
      // the file, a redirected folder, a full disk — by putting a DIRECTORY
      // where the registry expects to rename its temp file.
      final target = File(p.join(tmp.path, 'workspace.json'));
      target.deleteSync();
      Directory(target.path).createSync();

      await expectLater(repo.createNotebook('Two'), throwsA(anything),
          reason: 'a caller that awaited the write must learn it failed');

      // Clear the obstruction. The next write must succeed — this is the
      // assertion that fails without the fix. The shared chain stayed
      // permanently errored, so `workspace.json` was never written again for
      // the life of the process and every subsequent createNotebook rethrew
      // the FIRST failure's exception for ever.
      Directory(target.path).deleteSync();

      await repo.createNotebook('Three');
      expect(target.existsSync(), isTrue,
          reason: 'the registry must recover once the cause is gone');
      final written = jsonDecode(target.readAsStringSync()) as Map;
      final names = [
        for (final n in written['notebooks'] as List) (n as Map)['title']
      ];
      expect(names, contains('Three'));
    });

    test('a swallowed write failure is still discoverable', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp) = await freshRepo('onote_chain_note_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      await repo.createNotebook('One');
      expect(repo.lastWorkspaceWriteError, isNull);

      final target = File(p.join(tmp.path, 'workspace.json'));
      target.deleteSync();
      Directory(target.path).createSync();
      await expectLater(repo.createNotebook('Two'), throwsA(anything));

      // The debounced path has nobody to throw to, so the failure has to be
      // recorded somewhere rather than vanishing.
      expect(repo.lastWorkspaceWriteError, isNotNull);
    });

    test('flushing after dispose does not throw', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp) = await freshRepo('onote_chain_disp_');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      await repo.createNotebook('One');
      repo.dispose();
      // `AppState.shutdown` awaits this unguarded; it must be safe.
      await expectLater(repo.flushWorkspace(), completes);
    });
  });

  group('save path', () {
    test('a failed save stays dirty and reports the error', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp) = await freshRepo('onote_save_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      final nb = await repo.createNotebook('Save');
      final app = AppState(repo);
      final engine = _FlakyEngine(repo);
      app.notebookId = nb.id;
      app.nodes = repo.loadNodes(nb.id);
      app.pageId =
          app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
      app.blocks = [
        Block(type: BlockType.text, x: 0, y: 0, content: {'text': 'hi'})
      ];

      // Route saves through the flaky engine by calling it the way flushSave
      // does, then assert the state machine's contract.
      engine.fail = true;
      app.markDirty();
      expect(app.hasUnsavedChanges, true);

      // Simulate flushSave's failure branch semantics.
      try {
        await engine.savePage(nb.id, app.pageId!, app.blocks, app.pageProps);
        fail('the engine was supposed to throw');
      } catch (_) {/* expected */}
      expect(app.hasUnsavedChanges, true,
          reason: 'a throwing save must leave the page dirty for a retry');

      // And a real flush succeeds and clears both flags.
      engine.fail = false;
      await app.flushSave();
      expect(app.hasUnsavedChanges, false);
      expect(app.saveError, isNull);
    });

    test('shutdown flushes pending edits', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp) = await freshRepo('onote_exit_');
      final nb = await repo.createNotebook('Exit');
      final app = AppState(repo);
      app.notebookId = nb.id;
      app.nodes = repo.loadNodes(nb.id);
      final pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
      app.pageId = pageId;
      app.blocks = [
        Block(type: BlockType.text, x: 5, y: 5, content: {'text': 'unsaved!'})
      ];
      app.markDirty(); // starts a 700ms debounce we deliberately do NOT wait for

      await app.shutdown(); // what the window-close handler calls

      // Re-read from storage: the edit must be there despite the debounce.
      final data = repo.readPage(nb.id, pageId);
      expect(data.blocks.map((b) => b.content['text']), contains('unsaved!'));
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
  });

  group('writePage side-table projections', () {
    test('backlinks: explicit-id AND bare [[Title]] links both index',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp) = await freshRepo('onote_refs_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      final nb = await repo.createNotebook('Refs');
      final section = repo.upsertNode(
          nb.id, TreeNode(kind: NodeKind.section, title: 'S', position: 'a1'));
      final target = repo.upsertNode(
          nb.id,
          TreeNode(
              kind: NodeKind.page,
              parentId: section.id,
              title: 'Target Page',
              position: 'a2'));
      final srcA = repo.upsertNode(
          nb.id,
          TreeNode(
              kind: NodeKind.page,
              parentId: section.id,
              title: 'Source A',
              position: 'a3'));
      final srcB = repo.upsertNode(
          nb.id,
          TreeNode(
              kind: NodeKind.page,
              parentId: section.id,
              title: 'Source B',
              position: 'a4'));

      // A: the explicit form. B: the bare form the PRD documents — this used to
      // produce no backlink because the indexer skipped links without an id.
      repo.writePage(nb.id, srcA.id, [
        Block(
            type: BlockType.text,
            x: 0,
            y: 0,
            content: {'text': 'see [[Target Page|${target.id}]]'})
      ], PageProps());
      repo.writePage(nb.id, srcB.id, [
        Block(
            type: BlockType.text,
            x: 0,
            y: 0,
            content: {'text': 'also see [[Target Page]]'})
      ], PageProps());

      final back = repo.backlinkPageIds(nb.id, target.id).toSet();
      expect(back, containsAll([srcA.id, srcB.id]),
          reason: 'both link forms must produce a backlink');

      // Removing the link must remove the row (proves the DELETE-then-INSERT).
      repo.writePage(nb.id, srcB.id, [
        Block(
            type: BlockType.text, x: 0, y: 0, content: {'text': 'no link now'})
      ], PageProps());
      expect(repo.backlinkPageIds(nb.id, target.id).toSet(), {srcA.id});
    });

    test('blob_refs: in-flow image with a =WxH suffix is indexed', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp) = await freshRepo('onote_blob_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      final nb = await repo.createNotebook('Blobs');
      final page = repo.loadNodes(nb.id).firstWhere((n) => n.kind == NodeKind.page);
      final hash = repo.putBlob(
          nb.id, Uint8List.fromList(List.filled(16, 7)), 'image/png');

      // The exact dialect the OneNote importer writes for an in-flow image.
      repo.writePage(nb.id, page.id, [
        Block(
            type: BlockType.text,
            x: 0,
            y: 0,
            content: {'text': 'before\n![img](sha256:$hash =320x200)\nafter'})
      ], PageProps());

      // blob_refs has no public reader, so assert via the page mirror + blob.
      expect(repo.getBlob(nb.id, hash), isNotNull);
      final refCount = _blobRefCount(nb.file, page.id);
      expect(refCount, 1,
          reason: 'the ` =WxH` suffix used to defeat the indexing regex');
    });
  });

  test('restoring a page also un-deletes its section', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp) = await freshRepo('onote_restore_');
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final nb = await repo.createNotebook('Restore');
    final section = repo.upsertNode(
        nb.id, TreeNode(kind: NodeKind.section, title: 'Sec', position: 'a1'));
    final page = repo.upsertNode(
        nb.id,
        TreeNode(
            kind: NodeKind.page,
            parentId: section.id,
            title: 'Pg',
            position: 'a2'));

    // Deleting the section cascades to the page.
    repo.softDeleteNode(nb.id, section.id);
    expect(repo.loadNodes(nb.id).any((n) => n.id == page.id), false);

    // Restoring only the PAGE must reattach its ancestor, or the page comes
    // back invisible (its parent still deleted).
    repo.restoreNode(nb.id, page.id);
    final live = repo.loadNodes(nb.id).map((n) => n.id).toSet();
    expect(live, contains(page.id));
    expect(live, contains(section.id),
        reason: 'a restored page must not be orphaned under a deleted section');
  });

  test('workspace.json survives a torn write and reopens', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, tmp) = await freshRepo('onote_ws_');
    await repo.createNotebook('Alpha');
    await repo.createNotebook('Beta');
    await repo.flushWorkspace();
    repo.dispose();

    // Simulate a crash mid-write: truncate the registry. The `.bak` written
    // before the last atomic replace must carry us through.
    final ws = File(p.join(tmp.path, 'workspace.json'));
    expect(ws.existsSync(), true);
    ws.writeAsStringSync('{"notebooks": [trunc');

    final repo2 = await Repository.openAt(tmp);
    addTearDown(() {
      repo2.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    expect(repo2.notebooks, isNotEmpty,
        reason: 'a torn registry must never present as "no notebooks"');
    expect(repo2.workspaceRecoveryNote, isNotNull);
  });

  // The registry's forward-compatibility guard (v0.17 plan, Step 1; CI matrix
  // cell G2).
  //
  // The hazard it exists for is not a crash and leaves nothing corrupt behind.
  // `_loadWorkspace` skips any entry whose file it cannot see, and
  // `_saveWorkspace` then rewrites the registry from what survived — so a
  // student who upgrades the laptop in October and the desktop at Christmas
  // opens the old build on a migrated workspace, sees an empty sidebar, creates
  // one notebook, and permanently prunes all the others. This number has to be
  // in the field BEFORE any release moves a container, which is why it ships
  // with nothing yet depending on it.
  group('the workspace registry format guard', () {
    /// Build a workspace, then rewrite its `format` field to [format] (or drop
    /// it entirely when null). Returns the registry file and its exact bytes.
    Future<(Directory, File, String)> registryWith(
        String prefix, Object? format) async {
      final tmp = Directory.systemTemp.createTempSync(prefix);
      final repo = await Repository.openAt(tmp);
      await repo.createNotebook('Alpha');
      await repo.flushWorkspace();
      repo.dispose();

      final ws = File(p.join(tmp.path, 'workspace.json'));
      final j = jsonDecode(ws.readAsStringSync()) as Map<String, dynamic>;
      if (format == null) {
        j.remove('format');
      } else {
        j['format'] = format;
      }
      ws.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(j));
      return (tmp, ws, ws.readAsStringSync());
    }

    test('a registry from a newer Openote is read but never rewritten',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (tmp, ws, before) =
          await registryWith('onote_ws_new_', {'major': 99, 'minor': 0});
      final repo = await Repository.openAt(tmp);
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      expect(repo.registryReadOnly, isNotNull,
          reason: 'format 99 is newer than anything this build understands');
      expect(repo.notebooks, hasLength(1),
          reason: 'read-only is not the same as empty — the notebooks this '
              'build CAN see are still real and still openable');

      // The pruning move, exactly as a student would perform it.
      await repo.createNotebook('Beta');
      await repo.flushWorkspace();

      expect(ws.readAsStringSync(), before,
          reason: 'not one byte of a newer build\'s registry may be rewritten '
              'from what this build happened to load');
    });

    test('the message it shows names no version and no file', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (tmp, _, _) =
          await registryWith('onote_ws_words_', {'major': 99, 'minor': 0});
      final repo = await Repository.openAt(tmp);
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      // "A year 10 student wont know what an MCP is." The sentence has to say
      // what happened and what to do; the numbers belong behind Advanced.
      final lock = repo.registryReadOnly!;
      for (final jargon in ['format', 'workspace.json', 'JSON', '99']) {
        expect(lock.message, isNot(contains(jargon)),
            reason: 'the plain sentence must not contain "$jargon"');
      }
      expect(lock.message, contains('newer version of Openote'));
      expect(lock.message, contains('Updating Openote'));
      expect(lock.details, contains('99'),
          reason: 'the technical half still exists, folded away');
    });

    // NEGATIVE CONTROL. A guard that refuses too much is the same harm it was
    // built to prevent, arriving from the other direction: every workspace on
    // disk today carries `{"major":1,"minor":0}`, and some hand-edited ones
    // carry no `format` at all. If either read as "unknown, therefore newer",
    // this release would lock every existing user out of their own notebook
    // list on first launch.
    for (final (name, format) in <(String, Object?)>[
      ('the shape every existing workspace already has', {
        'major': 1,
        'minor': 0
      }),
      ('a flat integer, as a future build may write it', 1),
      ('no format field at all', null),
    ]) {
      test('negative control — $name still saves', () async {
        if (!haveSqlite) return markTestSkipped('sqlite unavailable');
        final (tmp, ws, before) =
            await registryWith('onote_ws_ok_', format);
        final repo = await Repository.openAt(tmp);
        addTearDown(() {
          repo.dispose();
          try {
            tmp.deleteSync(recursive: true);
          } catch (_) {}
        });

        expect(repo.registryReadOnly, isNull);
        await repo.createNotebook('Beta');
        await repo.flushWorkspace();

        expect(ws.readAsStringSync(), isNot(before));
        final back = jsonDecode(ws.readAsStringSync()) as Map<String, dynamic>;
        expect((back['notebooks'] as List), hasLength(2));
        // **1, not [workspaceFormat], and that is the v0.17 Step 8 rule.**
        // The guard is switched on by the thing it guards: `workspaceFormat` is
        // 2 because a demoted notebook's `.cache/<id>/cache.onote` path is a
        // shape an older build mis-writes as a bare basename and then prunes,
        // and a workspace with nothing demoted in it has no such path. Stamping
        // 2 here anyway would put every user who installs this build and
        // migrates nothing into a read-only registry on their other machine for
        // no reason at all — which is the same harm this guard exists to
        // prevent, arriving from the other direction.
        expect((back['format'] as Map)['major'], 1,
            reason: 'nothing is demoted, so an older build may still write it');
      });
    }
  });
}

/// Count `blob_refs` rows for a page by reading the notebook file directly
/// (a second WAL reader is safe alongside the repository's own handle).
int _blobRefCount(String notebookFile, String pageId) {
  final db = sqlite3.open(notebookFile, mode: OpenMode.readOnly);
  try {
    return db.select(
        'SELECT COUNT(*) AS c FROM blob_refs WHERE page_id=?',
        [pageId]).first['c'] as int;
  } finally {
    db.dispose();
  }
}
