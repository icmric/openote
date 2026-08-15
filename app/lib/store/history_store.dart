/// Where the derived history index lives, and how it is kept up to date.
///
/// Two tables in the container (v0.17 plan, Step 8a) — `block_authors`, one row
/// per block that currently exists, and `recent_deletions`, ten rows and never
/// eleven. **Both are derived and neither is synced.** They live in the file
/// that decision 3 says no third party should read, they can be dropped at any
/// time, and the cost of dropping them is a rebuild from the log.
///
/// The maintenance is deliberately incremental. A full re-derive on every save
/// would be correct and would also be the thing this whole design exists to
/// avoid: work proportional to the notebook's editing history rather than to
/// what just changed. [HistoryCatchUp] reads only the log bytes that were
/// appended since last time, which on an ordinary autosave is one line.
library;

import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../model/history.dart';
import '../sync/op.dart';
import '../sync/op_log.dart';

class HistoryStore {
  HistoryStore(this.db);
  final Database db;

  /// Read the index back, plus the node shadow it needs to name a section in
  /// plain words and to collapse a subtree into one entry.
  NotebookHistory load() {
    final h = NotebookHistory();
    h.seed(
      authors: [
        for (final r in db.select('SELECT page_id,block_id,device,lamport,seq,'
            'changed_at,block_kind,chars,pins FROM block_authors'))
          BlockAuthor(
            pageId: r['page_id'] as String,
            blockId: r['block_id'] as String,
            device: r['device'] as String,
            lamport: r['lamport'] as int,
            seq: r['seq'] as int,
            changedAt: r['changed_at'] as int,
            blockKind: r['block_kind'] as String,
            chars: r['chars'] as int,
            pins: _pins(r['pins']),
          )
      ],
      deletions: [
        for (final r in db.select('SELECT device,seq,lamport,deleted_at,kind,'
            'target_id,page_id,what,pins FROM recent_deletions'))
          NotableDeletion(
            kind: DeletionKind.values.firstWhere((k) => k.name == r['kind'],
                orElse: () => DeletionKind.block),
            targetId: r['target_id'] as String,
            pageId: r['page_id'] as String?,
            what: r['what'] as String,
            device: r['device'] as String,
            lamport: r['lamport'] as int,
            seq: r['seq'] as int,
            deletedAt: r['deleted_at'] as int,
            pins: _pins(r['pins']),
          )
      ],
      nodes: [
        for (final r
            in db.select('SELECT id,kind,parent_id,title FROM nodes'))
          HistoryNode(r['id'] as String)
            ..kind = r['kind'] as String
            ..parentId = r['parent_id'] as String?
            ..title = r['title'] as String
      ],
    );
    return h;
  }

  static List<String> _pins(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      return [for (final e in jsonDecode(raw) as List) e as String];
    } catch (_) {
      // A derived column. An unreadable one costs this entry its garbage-
      // collection pins and nothing else, which is a rebuild rather than a
      // loss — so it must never stop the notebook opening.
      return const [];
    }
  }

  /// Write what changed since the last flush. Returns rows touched.
  int flush(NotebookHistory h) {
    final pending = h.takePending();
    if (pending.upserts.isEmpty &&
        pending.deletes.isEmpty &&
        !pending.deletions) {
      return 0;
    }
    var rows = 0;
    db.execute('SAVEPOINT history_flush');
    try {
      if (pending.upserts.isNotEmpty) {
        // **`WHERE EXISTS`, not a bare INSERT**, for the reason
        // `NotebookWriter.writePage` gives its `blob_refs` insert: `page_id`
        // is a foreign key onto `nodes`, and a sync pull legitimately delivers
        // a page's blocks before the node that holds them. A constraint
        // violation there would abort the pull's whole transaction — one
        // shared notebook would stop syncing entirely — where a missing row
        // costs one line of attribution that the next save puts back.
        final up = db.prepare(
            'INSERT INTO block_authors(page_id,block_id,device,lamport,seq,'
            'changed_at,block_kind,chars,pins) '
            'SELECT ?,?,?,?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM nodes WHERE id=?) '
            'ON CONFLICT(page_id,block_id) DO UPDATE SET device=excluded.device,'
            'lamport=excluded.lamport,seq=excluded.seq,'
            'changed_at=excluded.changed_at,block_kind=excluded.block_kind,'
            'chars=excluded.chars,pins=excluded.pins');
        try {
          for (final a in pending.upserts) {
            up.execute([
              a.pageId, a.blockId, a.device, a.lamport, a.seq, a.changedAt,
              a.blockKind, a.chars, jsonEncode(a.pins), a.pageId,
            ]);
            rows++;
          }
        } finally {
          up.dispose();
        }
      }
      if (pending.deletes.isNotEmpty) {
        final del = db.prepare(
            'DELETE FROM block_authors WHERE page_id=? AND block_id=?');
        try {
          for (final a in pending.deletes) {
            del.execute([a.pageId, a.blockId]);
            rows++;
          }
        } finally {
          del.dispose();
        }
      }
      if (pending.deletions) {
        // Ten rows. Rewritten whole because ten is smaller than the code that
        // would work out which of them moved, and because the cap IS the
        // prune — there is no retention sweep here to get wrong.
        db.execute('DELETE FROM recent_deletions');
        final ins = db.prepare(
            'INSERT INTO recent_deletions(device,seq,lamport,deleted_at,kind,'
            'target_id,page_id,what,pins) VALUES(?,?,?,?,?,?,?,?,?)');
        try {
          for (final d in h.deletions) {
            ins.execute([
              d.device, d.seq, d.lamport, d.deletedAt, d.kind.name,
              d.targetId, d.pageId, d.what, jsonEncode(d.pins),
            ]);
            rows++;
          }
        } finally {
          ins.dispose();
        }
      }
      db.execute('RELEASE history_flush');
    } catch (_) {
      db.execute('ROLLBACK TO history_flush');
      db.execute('RELEASE history_flush');
      rethrow;
    }
    NotebookHistory.debugRowWrites += rows;
    return rows;
  }
}

/// Fold the ops appended since last time into [NotebookHistory].
abstract final class HistoryCatchUp {
  /// Read every device's log **from where this index last got to** and fold
  /// the result.
  ///
  /// The byte offsets are safe for the same reason `pendingForeignOps`' are:
  /// a device's log is append-only with exactly one writer, so bytes below an
  /// offset can never change. A stale or missing offset costs re-reading,
  /// never a wrong answer — folding an op twice lands on the same state,
  /// because every rule here is "the latest op in total order wins" rather
  /// than "apply the difference".
  ///
  /// **The whole batch is sorted before any of it is applied**, exactly as
  /// `SyncRecorder.pendingForeignOps` does and for the identical reason: a
  /// foreign log that arrives late can carry a lower Lamport than something
  /// this device wrote a minute ago, and applying in arrival order would give
  /// this device a different answer from every other one.
  static Future<int> run({
    required OpLogStore store,
    required NotebookHistory history,
    required int Function(String device) offsetOf,
    required void Function(String device, int at) remember,
  }) async {
    final batch = <Op>[];
    final ends = <String, int>{};
    for (final dev in store.deviceIds()) {
      final r = await store.readDeviceFrom(dev, offsetOf(dev));
      ends[dev] = r.next;
      batch.addAll(r.ops);
    }
    if (batch.isEmpty) {
      ends.forEach(remember);
      return 0;
    }
    batch.sort(Op.compare);
    history.applyAll(batch);
    ends.forEach(remember);
    return batch.length;
  }
}
