// Version history must die with the page, and only with the page.
//
// `page_versions` is the one page-scoped table that never declared
// `REFERENCES nodes(id) ON DELETE CASCADE`. `page_mirror` and `blob_refs` both
// do, so a purge emptied them and left up to thirty full page snapshots behind
// per purged page — for ever, because the retention cap in
// `maybeSnapshotVersion` only runs when a NEW snapshot is written for that same
// page id, which for a purged page can never happen again. `listVersions` went
// on returning all thirty for a page that no longer existed, and the video
// sweep reads every snapshot as a live reference, so an orphan naming a video
// pinned that file on disk permanently.
//
// Measured before the fix, on pages built to the shape of the owner's imported
// notebook (204 KB of page JSON each, its real average across 328 pages):
// purging one page left 30 rows / 6,012,145 bytes; purging one SECTION of two
// pages left 90 rows / 18,036,435 bytes, because `nodes.parent_id` cascades and
// those page ids are never named to `purgeNode`.
//
// So half this file is the deleting, and half is the far more important half:
// that a page in the recycle bin, and a page that was merely edited beside the
// purged one, keep every snapshot they had. The sweep deletes by "no matching
// `nodes` row", and a trashed page keeps its `nodes` row — if that ever stops
// being true, this file is what says so before thirty days of restorable
// history goes.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:openote/model/models.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late String nb;
  late String notebookFile;
  late String section;

  setUp(() async {
    if (!haveSqlite) return;
    tmp = Directory.systemTemp.createTempSync('onote_versions_');
    repo = await Repository.openAt(tmp);
    final created = await repo.createNotebook('History');
    nb = created.id;
    notebookFile = created.file;
    section =
        repo.loadNodes(nb).firstWhere((n) => n.kind == NodeKind.section).id;
  });

  tearDown(() {
    if (!haveSqlite) return;
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  String newSection(String title) => repo
      .upsertNode(nb,
          TreeNode(kind: NodeKind.section, title: title, position: title))
      .id;

  String newPage(String parent, String title) => repo
      .upsertNode(
          nb,
          TreeNode(
              kind: NodeKind.page,
              parentId: parent,
              title: title,
              position: title))
      .id;

  /// Save [pid] [times] over, snapshotting each time. `minGap: Duration.zero`
  /// defeats the ten-minute throttle so a history accumulates inside a test
  /// rather than over an afternoon.
  ///
  /// The spin is not padding. `page_versions` is keyed `(page_id, version_at)`
  /// at millisecond resolution and the insert is `INSERT OR REPLACE`, so two
  /// snapshots taken inside one millisecond silently become one row — which had
  /// this file asserting 5 and getting 4, i.e. measuring the clock rather than
  /// the purge. One snapshot per millisecond makes the counts mean what they
  /// say.
  void accumulate(String pid, int times) {
    for (var i = 0; i < times; i++) {
      final t = DateTime.now().millisecondsSinceEpoch;
      while (DateTime.now().millisecondsSinceEpoch == t) {/* next ms */}
      repo.writePage(
          nb,
          pid,
          [Block(type: BlockType.text, x: 0, y: 0, content: {'md': 'v$i'})],
          PageProps());
      repo.maybeSnapshotVersion(nb, pid, minGap: Duration.zero);
    }
  }

  /// Rows in `page_versions` naming a page that has no `nodes` row — the leak
  /// itself, counted the way the sweep defines it.
  int orphanRows() {
    final db = sqlite3.open(notebookFile);
    try {
      return db.select('SELECT COUNT(*) AS c FROM page_versions '
          'WHERE page_id NOT IN (SELECT id FROM nodes)').first['c'] as int;
    } finally {
      db.dispose();
    }
  }

  test('purging a page deletes its version history and leaves no orphans', () {
    if (!haveSqlite) return;
    final page = newPage(section, 'doomed');
    final survivor = newPage(section, 'survivor');
    accumulate(page, 4);
    accumulate(survivor, 3);
    expect(repo.listVersions(nb, page), hasLength(4));

    repo.purgeNode(nb, page);

    expect(repo.listVersions(nb, page), isEmpty,
        reason: 'a purged page must have no history left to list');
    expect(orphanRows(), 0);
    // The point of the whole exercise: the page NEXT to it is untouched.
    expect(repo.listVersions(nb, survivor), hasLength(3));
  });

  test('purging a section takes its pages history with it', () {
    if (!haveSqlite) return;
    // `nodes.parent_id` is ON DELETE CASCADE, so these two page rows vanish
    // without either id ever being passed to purgeNode. Deleting only the
    // named node's snapshots would leave both pages' history behind — and this
    // is the common case, not the rare one: the recycle bin purges sections,
    // and every import purges the seeded starter section.
    final doomed = newSection('doomed section');
    final a = newPage(doomed, 'a');
    final b = newPage(doomed, 'b');
    final elsewhere = newPage(section, 'elsewhere');
    accumulate(a, 3);
    accumulate(b, 2);
    accumulate(elsewhere, 2);

    repo.purgeNode(nb, doomed);

    expect(repo.listVersions(nb, a), isEmpty);
    expect(repo.listVersions(nb, b), isEmpty);
    expect(orphanRows(), 0);
    expect(repo.listVersions(nb, elsewhere), hasLength(2));
  });

  test('a page in the recycle bin keeps every snapshot', () {
    if (!haveSqlite) return;
    // The check the sweep stands or falls on. `softDeleteNode` stamps
    // `deleted_at` and leaves the `nodes` row in place, so a trashed page is
    // NOT an orphan — it is restorable for thirty days, and its history has to
    // be there when it comes back.
    final trashed = newPage(section, 'trashed');
    accumulate(trashed, 5);
    repo.softDeleteNode(nb, trashed);

    expect(orphanRows(), 0,
        reason: 'a trashed page still has its nodes row; it is not an orphan');
    expect(repo.listVersions(nb, trashed), hasLength(5));

    repo.restoreNode(nb, trashed);
    expect(repo.listVersions(nb, trashed), hasLength(5),
        reason: 'restoring a page must restore its history with it');
  });

  test('a trashed SECTION keeps its pages history', () {
    if (!haveSqlite) return;
    final s = newSection('trashed section');
    final page = newPage(s, 'inside');
    accumulate(page, 4);
    repo.softDeleteNode(nb, s);

    expect(orphanRows(), 0);
    expect(repo.listVersions(nb, page), hasLength(4));
  });

  test('retention purge of expired nodes leaves no orphans', () {
    if (!haveSqlite) return;
    // The other of the only two places a `nodes` row is hard-deleted, and it
    // runs by itself at startup — so it leaked without anyone pressing
    // anything.
    final expired = newPage(section, 'expired');
    final fresh = newPage(section, 'fresh');
    accumulate(expired, 3);
    accumulate(fresh, 2);
    repo.softDeleteNode(nb, expired);
    // Backdate past the 30-day window the retention sweep uses.
    final db = sqlite3.open(notebookFile);
    db.execute('UPDATE nodes SET deleted_at=? WHERE id=?', [
      DateTime.now()
          .subtract(const Duration(days: Repository.recycleRetentionDays + 10))
          .millisecondsSinceEpoch,
      expired
    ]);
    db.dispose();

    repo.purgeExpiredNodes(nb);

    expect(repo.listVersions(nb, expired), isEmpty);
    expect(orphanRows(), 0);
    expect(repo.listVersions(nb, fresh), hasLength(2));
  });

  test('opening a notebook sweeps orphans an older build left behind', () async {
    if (!haveSqlite) return;
    // The reason the explicit delete above is not enough on its own. Every
    // notebook already on disk has a `page_versions` table with no foreign
    // key, carrying whatever a previous build orphaned;
    // `CREATE TABLE IF NOT EXISTS` will never alter it. This writes that state
    // directly — a snapshot for a page id no node has ever had — and asserts
    // the next open repairs it.
    final live = newPage(section, 'live');
    final trashed = newPage(section, 'trashed');
    accumulate(live, 3);
    accumulate(trashed, 2);
    repo.softDeleteNode(nb, trashed);
    repo.dispose();

    final raw = sqlite3.open(notebookFile);
    raw.execute(
        'INSERT INTO page_versions(page_id,version_at,snapshot,label) '
        "VALUES('ghost-page-id', 1, X'7B7D', NULL)");
    raw.execute(
        'INSERT INTO page_versions(page_id,version_at,snapshot,label) '
        "VALUES('ghost-page-id', 2, X'7B7D', NULL)");
    expect(
        raw.select('SELECT COUNT(*) AS c FROM page_versions '
            'WHERE page_id NOT IN (SELECT id FROM nodes)').first['c'],
        2);
    raw.dispose();

    repo = await Repository.openAt(tmp);
    // Touching the notebook is what opens it, and the open is what sweeps.
    expect(repo.listVersions(nb, live), hasLength(3));
    expect(orphanRows(), 0, reason: 'the open should have swept the ghost');
    // …and swept only the ghost. The trashed page is still restorable.
    expect(repo.listVersions(nb, trashed), hasLength(2));
  });
}
