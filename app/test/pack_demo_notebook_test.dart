// Packing the browser demo, so its handwriting goes with it.
//
// Two things live here. A real test of the packer, which runs on every
// `flutter test`: handwriting saved the ordinary way is in the notebook's
// folder and not its file, so a file opened on its own — which is all the
// browser demo ever has — draws nothing; packed, it draws the strokes.
//
// And the tool itself, which runs only when you ask it to:
//
//     flutter test test/pack_demo_notebook_test.dart --dart-define=DEMO_FROM="<path to your edited demo .onote>"
//
// It writes `assets/demo/demo.onote`. Add `--dart-define=DEMO_FOLDER="<its
// .onotebook folder>"` if that folder is not beside the file (Sync ▸ Open
// folder shows where it is). The steps around it are in
// `assets/demo/README.md`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:openote/ink/ink_storage.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/pack_notebook.dart';
import 'support/sqlite.dart';

const _from = String.fromEnvironment('DEMO_FROM');
const _folder = String.fromEnvironment('DEMO_FOLDER');

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  group('the packer', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('onote_pack_test_'));
    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    /// A notebook with one drawing on its first page, saved the ordinary
    /// way, and closed — as you would leave the demo after editing it.
    Future<(String file, String pageId)> drawnNotebook() async {
      AppState.syncLogEnabled = false;
      addTearDown(() => AppState.syncLogEnabled = true);
      final repo = await Repository.openAt(Directory(p.join(tmp.path, 'mine')));
      final nb = await repo.createNotebook('Demo');
      final app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
      await app.selectPage(page.id);
      app.addBlock(
          Block(type: BlockType.ink, x: 100, y: 200, w: 80, h: 30, content: {
            'strokes': [
              {
                'id': 's1',
                'brush': {
                  'tool': 'pen',
                  'color': '#211F1B',
                  'size': 2.5,
                  'opacity': 1.0
                },
                'x': [100.0, 140.0, 180.0],
                'y': [200.0, 230.0, 210.0],
                'p': [0.5, 0.6, 0.5],
                'tx': <double>[],
                'ty': <double>[],
                't': [0, 8, 16],
                'strokeStart': 0,
              }
            ]
          }),
          recordUndo: false);
      await app.flushSave();
      app.cancelPendingSave();
      repo.dispose();
      return (nb.file, page.id);
    }

    /// How many strokes the page draws when its notebook is opened from
    /// [file] alone, with no folder beside it — the browser's situation.
    Future<int> strokesSeenFromFileAlone(String file, String pageId) async {
      final ws = Directory(p.join(tmp.path, 'browser-${file.hashCode}'))
        ..createSync(recursive: true);
      final repo = await Repository.openAt(ws);
      try {
        final copy = p.join(ws.path, 'Demo.onote');
        File(file).copySync(copy);
        final nb = await repo.adoptWorkspaceNotebook(copy);
        final ink = repo
            .readPage(nb.id, pageId)
            .blocks
            .firstWhere((b) => b.type == BlockType.ink);
        final working = InkStorage.toWorking(
            ink.content, (h) => repo.getBlob(nb.id, h));
        return InkStorage.strokesOf(working).length;
      } finally {
        repo.dispose();
      }
    }

    test('saved handwriting is in the folder, not the file', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (file, pageId) = await drawnNotebook();
      final db = sqlite3.open(file, mode: OpenMode.readOnly);
      try {
        expect(db.select('SELECT * FROM blob_refs'), isNotEmpty,
            reason: 'the page refers to its drawing');
        expect(db.select('SELECT * FROM blobs'), isEmpty,
            reason: 'and the bytes are not in the file');
      } finally {
        db.dispose();
      }
      // The demo's bug, reproduced: on its own, the file draws nothing.
      expect(await strokesSeenFromFileAlone(file, pageId), 0);
    });

    test('packed, the file draws it with no folder anywhere', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (file, pageId) = await drawnNotebook();
      final out = p.join(tmp.path, 'out', 'demo.onote');
      final r = packNotebook(fromOnote: file, toOnote: out);
      expect(r.ok, isTrue, reason: 'missing: ${r.missing}');
      expect(r.packed, 1);
      expect(await strokesSeenFromFileAlone(out, pageId), 1);
    });

    test('the notebook being packed is not changed', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (file, _) = await drawnNotebook();
      final before = File(file).readAsBytesSync();
      packNotebook(fromOnote: file, toOnote: p.join(tmp.path, 'o.onote'));
      expect(File(file).readAsBytesSync(), before);
    });

    test('a drawing whose bytes are gone stops it, and nothing is written',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (file, _) = await drawnNotebook();
      final blobs =
          Directory(p.join('${p.withoutExtension(file)}.onotebook', 'blobs'));
      for (final f in blobs.listSync()) {
        f.deleteSync();
      }
      final out = p.join(tmp.path, 'never.onote');
      final r = packNotebook(fromOnote: file, toOnote: out);
      expect(r.ok, isFalse);
      expect(r.missing, hasLength(1));
      expect(File(out).existsSync(), isFalse,
          reason: 'a demo that looks complete and is not is the failure');
    });

    test('it says what is in the recycle bin, which would ship too', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (file, _) = await drawnNotebook();
      final db = sqlite3.open(file);
      db.execute("UPDATE nodes SET deleted_at = 1 WHERE kind = 'page'");
      db.dispose();
      final r = packNotebook(fromOnote: file, toOnote: p.join(tmp.path, 'b.onote'));
      expect(r.binned, isNotEmpty);
    });
  });

  test('pack the browser demo', () {
    if (_from.isEmpty) {
      return markTestSkipped('Not asked to. To pack the demo after editing it: '
          'flutter test test/pack_demo_notebook_test.dart '
          '--dart-define=DEMO_FROM="<your edited demo .onote>" — see '
          'assets/demo/README.md');
    }
    if (!haveSqlite) fail('sqlite unavailable — build the desktop app first');
    final r = packNotebook(
        fromOnote: _from,
        notebookFolder: _folder.isEmpty ? null : _folder,
        toOnote: 'assets/demo/demo.onote');
    if (!r.ok) {
      fail('${r.missing.length} drawing(s) or picture(s) are not in the '
          "notebook's folder, so the demo would be missing them. Nothing was "
          'written. Missing: ${r.missing.take(5).join(', ')}');
    }
    // ignore: avoid_print
    print('Packed assets/demo/demo.onote: ${r.bytes ~/ 1024} KB, '
        '${r.packed} blob(s) put in, ${r.alreadyInside} already there.');
    if (r.binned.isNotEmpty) {
      // ignore: avoid_print
      print('In its recycle bin, and shipping with it — empty the bin and '
          'pack again if you would rather not:\n  ${r.binned.join('\n  ')}');
    }
  });
}
