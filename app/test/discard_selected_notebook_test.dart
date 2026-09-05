// Deleting the notebook somebody is currently looking at.
//
// Reported: an import that failed turned the sidebar into a red error box —
// "Bad state: No element", plus an overflow of ninety-odd thousand pixels —
// while the app carried on being interactive underneath.
//
// The chain:
//
//   1. A cloud import creates its notebook and OPENS it immediately, on
//      purpose: that is what lets somebody watch their pages arrive.
//   2. The import fails before any page lands, so the job tears the empty
//      notebook down.
//   3. `discardImportedNotebook` deleted it but left `notebookId` naming it.
//   4. The sidebar header ran `notebooks.firstWhere((n) => n.id ==
//      notebookId)` with no `orElse` and threw. An error widget inside a
//      stretched Column then reported the enormous overflow, which is the
//      part a person actually sees.
//
// The bug in (3) and (4) is as old as both methods. What made it reachable is
// (1): a `.onepkg` import never selects the notebook until Open is pressed, so
// a failed one had nothing to strand. Progressive import turned an unreachable
// bug into a crash on the ordinary failure path — which is worth remembering
// the next time something becomes visible "for no reason".

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Future<(Repository, AppState)> fixture(String name) async {
    final tmp = Directory.systemTemp.createTempSync(name);
    final repo = await Repository.openAt(tmp);
    addTearDown(() async {
      await repo.flushWorkspace();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    return (repo, AppState(repo));
  }

  test('the selection moves to another notebook before this one is deleted',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app) = await fixture('onote_discard_selected_');

    final keep = await app.importCreateNotebook('Keep me');
    final doomed = await app.importCreateNotebook('Half an import');
    await app.selectNotebook(doomed.id);
    expect(app.notebookId, doomed.id);

    await app.discardImportedNotebook(doomed.id);

    expect(repo.notebooks.map((n) => n.id), isNot(contains(doomed.id)));
    expect(app.notebookId, keep.id,
        reason: 'a dangling notebookId is what the sidebar crashed on');
    // And the selection is real, not merely non-null.
    expect(repo.notebooks.where((n) => n.id == app.notebookId), hasLength(1));
  });

  test('with nothing else to open, it lands on no notebook rather than a '
      'deleted one', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app) = await fixture('onote_discard_only_');

    final only = await app.importCreateNotebook('The only one');
    await app.selectNotebook(only.id);

    await app.discardImportedNotebook(only.id);

    expect(repo.notebooks.map((n) => n.id), isNot(contains(only.id)));
    expect(app.notebookId, isNull,
        reason: 'null is a state the app can draw; a dead id is not');
    expect(app.pageId, isNull);
    expect(app.nodes, isEmpty);
  });

  test('discarding a notebook nobody is looking at leaves the selection alone',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (_, app) = await fixture('onote_discard_other_');

    final mine = await app.importCreateNotebook('Mine');
    final other = await app.importCreateNotebook('Someone else');
    await app.selectNotebook(mine.id);

    await app.discardImportedNotebook(other.id);

    expect(app.notebookId, mine.id,
        reason: 'tearing down a background import must not move me');
  });
}
