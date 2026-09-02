// UI-layer half of the navigation-speed probe: the state layer measured
// 3–7ms per switch, so the half-second lives in widget builds. This times
// whole-shell interactions on a big notebook. Debug-mode numbers run
// 2–3× release, but they say WHERE the time goes.
//
// `notify=` is the keystroke-shaped one, and the reason the command bar and
// the object row are memoised (`lib/ui/memo.dart`): the single frame after a
// `markDirty()` measured 62.7 ms here before that and 18.7 ms after. This
// probe prints, it does not assert — `test/chrome_memo_test.dart` is what
// holds the memo to its promises.
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

  testWidgets('shell interaction timings on a big notebook', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    AppState.syncLogEnabled = false;
    // Real disk I/O must run OUTSIDE the fake-async test zone.
    late Directory tmp;
    late Repository repo;
    late AppState app;
    late NotebookRef nb;
    await tester.runAsync(() async {
      tmp = Directory.systemTemp.createTempSync('onote_uiperf_');
      repo = await Repository.openAt(tmp);
      nb = await repo.createNotebook('Perf');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
    });

    // 3 sections × 30 pages; pages hold 40 realistic blocks.
    final first = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
    final sectionIds = <String>[first.id];
    for (var s = 1; s < 3; s++) {
      sectionIds.add(app
          .importNode(
              nb.id,
              TreeNode(
                  kind: NodeKind.section,
                  title: 'Section $s',
                  position: 's${s.toString().padLeft(4, '0')}'))
          .id);
    }
    final pageIds = <String>[];
    for (final sid in sectionIds) {
      for (var p = 0; p < 30; p++) {
        final page = app.importNode(
            nb.id,
            TreeNode(
                kind: NodeKind.page,
                parentId: sid,
                title: 'Page $p of $sid',
                position: 'a${p.toString().padLeft(6, '0')}'));
        pageIds.add(page.id);
        if (p < 3) {
          // Only a few pages need real content — we open those.
          app.importPage(nb.id, page.id, [
            for (var i = 0; i < 40; i++)
              Block(type: BlockType.text, x: 40, y: 100.0 + i * 60, w: 500,
                  content: {
                    'text': 'Block $i with **bold**, a '
                        '[link](https://e.com), `code`, and prose that '
                        'is long enough to wrap a couple of lines.\nMore.'
                  }),
          ], PageProps());
        }
      }
    }
    app.reloadNodes();
    await tester.runAsync(() => app.selectPage(pageIds[0]));
    app.markOnboardingSeen();

    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var sw = Stopwatch()..start();
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      theme: onoteTheme(Brightness.light),
      home: AppShell(app: app),
    ));
    // ignore: avoid_print
    print('UIPERF firstBuild=${sw.elapsedMilliseconds}ms');
    sw = Stopwatch()..start();
    await tester.pump(const Duration(milliseconds: 900));
    // ignore: avoid_print
    print('UIPERF secondPump=${sw.elapsedMilliseconds}ms');
    sw = Stopwatch()..start();
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    // ignore: avoid_print
    print('UIPERF settle=${sw.elapsedMilliseconds}ms');

    Future<int> timedPump(Future<void> Function() act) async {
      final sw = Stopwatch()..start();
      await tester.runAsync(act);
      await tester.pumpAndSettle();
      return sw.elapsedMilliseconds;
    }

    // Page switch (content-bearing → content-bearing).
    final sw1 = await timedPump(() => app.selectPage(pageIds[1]));
    final sw2 = await timedPump(() => app.selectPage(pageIds[2]));
    // Page switch to an EMPTY page (isolates canvas cost from content).
    final swEmpty = await timedPump(() => app.selectPage(pageIds[10]));
    final swBack = await timedPump(() => app.selectPage(pageIds[0]));
    // Section change (sidebar action).
    final sec = await timedPump(() async => app.activateSection(sectionIds[2]));
    // A plain notify with nothing changed (keystroke-shaped cost).
    final notify = await timedPump(() async => app.markDirty());
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();

    // ignore: avoid_print
    print('UIPERF pageSwitch=[$sw1,$sw2]ms empty=${swEmpty}ms '
        'back=${swBack}ms section=${sec}ms notify=${notify}ms');

    await tester.runAsync(() async {
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    AppState.syncLogEnabled = true;
  }, timeout: const Timeout(Duration(minutes: 3)));
}
