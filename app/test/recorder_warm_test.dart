// The lazy, background-opened sync recorder — the fix for "the app is locked
// up for the first few seconds after launching".
//
// **What was wrong.** `SyncRecorder.open` reads and JSON-decodes every op ever
// written and replays it — measured at ~0.5 s for a 2000-page imported
// notebook's 14 MB log, on a fast machine — and it ran synchronously on the UI
// thread in two innocent-looking places: `_startWatching` on the first frame
// after launch, and `syncDeviceCount`, which every sync dot's first paint
// calls. So launching froze, and finishing an import froze at the exact moment
// the card announced the result (the new dot's first paint replayed the giant
// log the import had just written).
//
// The shape now: status reads use a bare directory listing and never open a
// recorder; the replay runs in a background isolate (`warmRecorder`), started
// at launch, notebook selection and import completion; the synchronous open
// survives only as the mutation path's fallback, for a save that beats the
// warm.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/sync/op.dart';
import 'package:openote/sync/op_log.dart';
import 'package:openote/ui/sync_dot.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Future<(Repository, AppState, String, Directory)> fixture(String name) async {
    final tmp = Directory.systemTemp.createTempSync(name);
    final repo = await Repository.openAt(tmp);
    addTearDown(() async {
      await repo.flushWorkspace();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final nb = await repo.createNotebook('Warm');
    final app = AppState(repo)..notebookId = nb.id;
    app.reloadNodes();
    return (repo, app, nb.id, tmp);
  }

  OpLogStore logOf(Repository repo, String nb) =>
      OpLogStore.forNotebook(repo.notebooks.firstWhere((n) => n.id == nb).file);

  group('status reads pay a directory listing, not a replay', () {
    test('asking a fresh notebook its sync state creates NO log directory',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, _) = await fixture('onote_warm_fresh_');

      expect(syncStateOf(app, nb), SyncState.local);
      expect(syncStateTooltip(app, nb), contains('this computer only'));

      // The old path opened a recorder to count devices, and opening a
      // recorder CREATES `.onotebook/` — so merely painting a dot minted log
      // directories for notebooks that had never recorded anything.
      expect(logOf(repo, nb).dir.existsSync(), isFalse,
          reason: 'a status read must not write to disk');
    });

    test('the device count still comes from the real log files', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, _) = await fixture('onote_warm_count_');

      // Two devices' logs on disk, written directly — no recorder involved.
      final store = logOf(repo, nb);
      store.ensureInitialised(notebookId: nb, title: 'Warm');
      for (final dev in ['dev-a', 'dev-b']) {
        store.append(dev, [
          Op(
              device: dev,
              seq: 1,
              lamport: 1,
              timestamp: 1,
              kind: OpKind.notebookMeta,
              data: {'title': 'Warm'})
        ]);
      }

      expect(app.syncDeviceCount(nb), 2,
          reason: 'the cheap path must report the same truth the expensive '
              'one did — the log files themselves');
    });
  });

  group('warmRecorder', () {
    test('a warmed recorder continues the seq the log already reached',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, _) = await fixture('onote_warm_seq_');

      // Session one: record something, so the log has history to replay.
      app.importNode(
          nb, TreeNode(kind: NodeKind.page, title: 'First', position: 'a1'));
      final device = app.localDeviceId();
      final before = logOf(repo, nb)
          .readDevice(device)
          .map((o) => o.seq)
          .fold(0, (a, b) => a > b ? a : b);
      expect(before, greaterThan(0));

      // Session two: a fresh AppState (fresh recorder cache), warmed.
      final app2 = AppState(repo)..notebookId = nb;
      app2.reloadNodes();
      final r = await app2.warmRecorder(nb);
      expect(r, isNotNull);

      app2.importNode(
          nb, TreeNode(kind: NodeKind.page, title: 'Second', position: 'a2'));

      final seqs =
          logOf(repo, nb).readDevice(device).map((o) => o.seq).toList();
      expect(seqs.toSet().length, seqs.length,
          reason: 'a replay that missed history would re-issue sequence '
              'numbers — two ops claiming one (device, seq) is exactly the '
              'corruption one-writer-per-file exists to prevent');
      expect(seqs.reduce((a, b) => a > b ? a : b), greaterThan(before));
    });

    test('a mutation that beats the warm wins, and the warm is discarded',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, nb, _) = await fixture('onote_warm_race_');

      // Seed history so the warm has real work to do.
      app.importNode(
          nb, TreeNode(kind: NodeKind.page, title: 'P0', position: 'a0'));

      final app2 = AppState(repo)..notebookId = nb;
      app2.reloadNodes();
      // Fire the warm and IMMEDIATELY mutate: the mutation cannot wait, so it
      // opens synchronously while the background replay is still running.
      final warm = app2.warmRecorder(nb);
      app2.importNode(
          nb, TreeNode(kind: NodeKind.page, title: 'P1', position: 'a1'));
      await warm;
      // If the stale warm had been installed over the live recorder, its seq
      // counter would predate P1's op and this next write would collide.
      app2.importNode(
          nb, TreeNode(kind: NodeKind.page, title: 'P2', position: 'a2'));

      final device = app2.localDeviceId();
      final seqs =
          logOf(repo, nb).readDevice(device).map((o) => o.seq).toList();
      expect(seqs.toSet().length, seqs.length,
          reason: 'duplicate seqs mean the losing recorder wrote anyway');
      final sorted = [...seqs]..sort();
      expect(seqs, sorted, reason: 'appends must stay in seq order');
    });

    test('does not open a recorder for a notebook mid-import', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (_, app, nb, _) = await fixture('onote_warm_import_');

      app.beginExclusiveImport(nb);
      expect(await app.warmRecorder(nb), isNull,
          reason: 'the writer isolate owns the log; a recorder here would be '
              'a second writer on the same file');
      app.endExclusiveImport(nb);
    });
  });
}
