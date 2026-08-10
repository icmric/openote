// Where does page-switch time actually go? (Eric: "about half a second or
// so very consistently to change pages … feels like some bottle neck".)
// A probe, not a regression test: builds a realistic notebook and prints
// the cost of each stage of selectPage so the fix aims at the right part.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  test('stage timings for page navigation', () async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    final tmp = Directory.systemTemp.createTempSync('onote_perf_');
    final repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Perf');
    final app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();

    // A term's worth of notes: 40 pages, 30 text blocks + 2 tables each.
    final pageIds = <String>[];
    final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
    for (var p = 0; p < 40; p++) {
      final page = app.importNode(
          nb.id,
          TreeNode(
            kind: NodeKind.page,
            parentId: section.id,
            title: 'Page $p',
            position: 'a${p.toString().padLeft(6, '0')}',
          ));
      pageIds.add(page.id);
      final blocks = <Block>[
        for (var i = 0; i < 30; i++)
          Block(type: BlockType.text, x: 40, y: 100.0 + i * 60, w: 500,
              content: {
                'text': 'Line one of block $i with **bold** and a '
                    '[link](https://example.com) and some more prose to '
                    'be realistic about content size.\nSecond line.'
              }),
        for (var t = 0; t < 2; t++)
          Block(type: BlockType.table, x: 600, y: 100.0 + t * 400, w: 400,
              content: {
                'cells': [
                  for (var r = 0; r < 8; r++)
                    [for (var c = 0; c < 4; c++) 'r$r c$c']
                ]
              }),
      ];
      app.importPage(nb.id, page.id, blocks, PageProps());
    }
    app.reloadNodes();

    Future<int> time(Future<void> Function() f) async {
      final sw = Stopwatch()..start();
      await f();
      return sw.elapsedMilliseconds;
    }

    // Cold first open.
    final cold = await time(() => app.selectPage(pageIds[0]));
    // Clean switches (nothing dirty).
    final clean = <int>[];
    for (var i = 1; i <= 5; i++) {
      clean.add(await time(() => app.selectPage(pageIds[i])));
    }
    // Dirty switch: touch the page, then navigate (flush inline today).
    app.markDirty();
    final dirty = await time(() => app.selectPage(pageIds[10]));
    // flushSave alone, clean vs dirty.
    final flushClean = await time(() => app.flushSave());
    app.markDirty();
    final flushDirty = await time(() => app.flushSave());
    // loadPage alone.
    final load = await time(() async {
      await app.engine.loadPage(nb.id, pageIds[20]);
    });

    // ignore: avoid_print
    print('PERF cold=${cold}ms clean=${clean}ms dirty=${dirty}ms '
        'flushClean=${flushClean}ms flushDirty=${flushDirty}ms '
        'loadPage=${load}ms');

    app.cancelPendingSave();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
    AppState.syncLogEnabled = true;
  }, timeout: const Timeout(Duration(minutes: 3)));
}
