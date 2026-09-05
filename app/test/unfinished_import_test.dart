// An import that stopped early, and picking it up later.
//
// The owner, on a throttled import: "Even if they dismiss this warning i want
// a partial import warning to stay visible … Make sure it will still try to
// import again if they close the app before it finishes the import, and
// ensure that when importing we dont overwrite anything that the user has
// done." And, on a cancelled one: "although if manually stoped never
// automatically attempt to finish it".
//
// Those are three separate rules and they pull against each other:
//
//   1. An unfinished import must be remembered, including across a restart.
//   2. Finishing it must never re-import a page that is already here, because
//      somebody may have edited it — that is the one way this feature could
//      destroy work instead of protecting it.
//   3. Something stopped ON PURPOSE is never picked up on its own. Stop is an
//      instruction, not an interruption.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/onenote/unfinished_import.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  UnfinishedImport rec({
    UnfinishedReason reason = UnfinishedReason.throttled,
    int done = 152,
    int total = 332,
    List<String> ids = const ['g1', 'g2'],
    int? lastTryMs,
  }) =>
      UnfinishedImport(
        graphNotebookId: 'NB-GRAPH',
        notebookName: 'Computing Science',
        pagesDone: done,
        pagesTotal: total,
        donePageIds: ids,
        linkMap: const {'one-note-guid': 'page-id'},
        reason: reason,
        lastTryMs: lastTryMs ?? DateTime.now().millisecondsSinceEpoch,
      );

  group('the record itself', () {
    test('survives a round trip through storage', () {
      final back = UnfinishedImport.fromJson(rec().toJson())!;
      expect(back.graphNotebookId, 'NB-GRAPH');
      expect(back.notebookName, 'Computing Science');
      expect(back.pagesDone, 152);
      expect(back.pagesTotal, 332);
      expect(back.donePageIds, ['g1', 'g2']);
      expect(back.linkMap, {'one-note-guid': 'page-id'});
      expect(back.reason, UnfinishedReason.throttled);
    });

    test('anything that is not one of ours reads as nothing', () {
      // It comes off disk and may have been written by an older build. A
      // malformed record must read as "no unfinished import", never crash the
      // app on startup.
      expect(UnfinishedImport.fromJson(null), isNull);
      expect(UnfinishedImport.fromJson('nonsense'), isNull);
      expect(UnfinishedImport.fromJson({}), isNull);
      expect(UnfinishedImport.fromJson({'graphNotebookId': ''}), isNull);
      // A record missing everything optional still loads, at its defaults.
      final thin = UnfinishedImport.fromJson({'graphNotebookId': 'x'})!;
      expect(thin.pagesDone, 0);
      expect(thin.donePageIds, isEmpty);
      expect(thin.reason, UnfinishedReason.interrupted);
    });

    test('pagesLeft never goes negative', () {
      expect(rec(done: 400, total: 332).pagesLeft, 0);
      expect(rec(done: 152, total: 332).pagesLeft, 180);
    });
  });

  group('when it may try again on its own', () {
    final now = DateTime(2026, 1, 1, 12);
    final anHourAgo = now.subtract(const Duration(hours: 1, minutes: 1));

    test('a throttled import waits, then becomes eligible', () {
      final fresh = rec(lastTryMs: now.millisecondsSinceEpoch);
      expect(fresh.mayRetryAt(now), isFalse,
          reason: 'trying again immediately is how an account stays throttled');

      final old = rec(lastTryMs: anHourAgo.millisecondsSinceEpoch);
      expect(old.mayRetryAt(now), isTrue);
    });

    test('an interrupted one behaves the same', () {
      final old = rec(
          reason: UnfinishedReason.interrupted,
          lastTryMs: anHourAgo.millisecondsSinceEpoch);
      expect(old.mayRetryAt(now), isTrue);
    });

    test('one somebody STOPPED is never picked up, however long it waits', () {
      // The rule that matters most here. An app that quietly restarts the
      // thing you just stopped is worse than one that forgets you stopped it.
      final old = rec(
          reason: UnfinishedReason.stopped,
          lastTryMs: anHourAgo.millisecondsSinceEpoch);
      expect(old.stoppedByUser, isTrue);
      expect(old.retryAfter, isNull);
      expect(old.mayRetryAt(now), isFalse);
      expect(old.mayRetryAt(now.add(const Duration(days: 365))), isFalse,
          reason: 'not ever');
    });
  });

  group('kept against the notebook', () {
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

    test('written, read back, and cleared', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (_, app) = await fixture('onote_unfinished_');
      final ref = await app.importCreateNotebook('Computing Science');

      expect(app.unfinishedImportFor(ref.id), isNull);

      app.recordUnfinishedImport(ref.id, rec());
      expect(app.unfinishedImportFor(ref.id)!.pagesDone, 152);
      expect(app.unfinishedImports().map((e) => e.$1), [ref.id]);

      app.clearUnfinishedImport(ref.id);
      expect(app.unfinishedImportFor(ref.id), isNull);
      expect(app.unfinishedImports(), isEmpty);
    });

    test('nothing is resumed automatically without a sign-in', () async {
      // Resuming must never pop a Microsoft login window at somebody in the
      // middle of writing. With no stored credential the reminder simply
      // stays, waiting to be pressed.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (_, app) = await fixture('onote_unfinished_nosignin_');
      final ref = await app.importCreateNotebook('Computing Science');
      app.recordUnfinishedImport(
          ref.id,
          rec(
              lastTryMs: DateTime.now()
                  .subtract(const Duration(hours: 2))
                  .millisecondsSinceEpoch));

      expect(await app.maybeResumeUnfinishedImport(), isNull);
      expect(app.unfinishedImportFor(ref.id), isNotNull,
          reason: 'and the record is left alone for the button to use');
    });

    test('one somebody stopped is never resumed automatically', () async {
      // Belt and braces over the unit test above: even with everything else
      // in place, a stopped record is not a candidate.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (_, app) = await fixture('onote_unfinished_stopped_');
      final ref = await app.importCreateNotebook('Computing Science');
      app.recordUnfinishedImport(
          ref.id,
          rec(
              reason: UnfinishedReason.stopped,
              lastTryMs: DateTime.now()
                  .subtract(const Duration(days: 30))
                  .millisecondsSinceEpoch));

      expect(await app.maybeResumeUnfinishedImport(), isNull);
    });

    test('it is still there after the workspace is reopened', () async {
      // The case somebody would otherwise never be told about: an import
      // interrupted by closing the app.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final tmp = Directory.systemTemp.createTempSync('onote_unfinished_reopen_');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final repo1 = await Repository.openAt(tmp);
      final app1 = AppState(repo1);
      final ref = await app1.importCreateNotebook('Computing Science');
      app1.recordUnfinishedImport(ref.id, rec());
      await repo1.flushWorkspace();
      repo1.dispose();

      final repo2 = await Repository.openAt(tmp);
      addTearDown(repo2.dispose);
      final app2 = AppState(repo2);
      final back = app2.unfinishedImportFor(ref.id);
      expect(back, isNotNull, reason: 'closing the app must not forget');
      expect(back!.pagesDone, 152);
      expect(back.graphNotebookId, 'NB-GRAPH');
    });
  });
}
