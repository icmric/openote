/// The .onote container — File Format Spec (docs/specs/10-file-format-spec.md).
///
/// `page_mirror` holds page content and is **authoritative**, not a projection.
/// The spec originally layered a CRDT (`page_docs`/`page_updates`) underneath it
/// as the source of truth, with the mirror as the open-format window onto it;
/// that layer was never implemented, and [ADR-0006] replaced it with an
/// append-only operation log kept in files inside a `.onotebook` directory. So
/// there is exactly one copy of a page in this container, and once the op log
/// lands this whole container becomes a rebuildable local cache that is never
/// synced.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqlite3/sqlite3.dart';

const onoteApplicationId = 0x4F4E4F54; // "ONOT"
const onoteFormatMajor = 1;

/// Why a file handed to Openote from OUTSIDE the app — the command line, a
/// double-click in the file manager — cannot be opened as a notebook.
enum NotebookFileProblem {
  /// Nothing at that path.
  missing,

  /// A folder, or a device — not a file we can read.
  notAFile,

  /// It is there, but this process cannot read it.
  unreadable,

  /// Readable, and not one of ours.
  notANotebook,
}

/// Sniff [path] and say why it could not be a notebook, or null when it looks
/// like one.
///
/// **This runs BEFORE anything opens or copies the file, and that ordering is
/// the whole point.** [openOnote] treats an `application_id` of zero as "a
/// fresh file" and seeds a brand-new notebook into it, and
/// `Repository.openExistingNotebook` copies its argument into the workspace
/// *first* and opens it *second*. Point the two of them at a stray empty file
/// — trivially reachable, because Explorer will happily hand us anything the
/// user renamed to `.onote` — and the result is a mystery blank notebook
/// permanently in the sidebar. Point them at a `.txt` and the copy has already
/// landed in the workspace by the time SQLite objects.
///
/// The test is the container's own identity, and deliberately the SAME rule
/// `packaging/linux/openote.xml` gives the desktop: "SQLite format 3" at
/// offset 0 *and* `application_id` = "ONOT" at offset 68, which is where
/// SQLite keeps that field. Matching only the SQLite magic would claim every
/// database on the machine.
///
/// The one concession is an `application_id` of zero **with a `-wal` file
/// beside it**. Notebooks are opened `journal_mode=WAL`, so a container whose
/// header change has not been checkpointed back yet still reads as zeros here;
/// `checkpointAndClose` means that only survives a crash, but calling a real
/// notebook "not a notebook" because the app died once is the wrong way to be
/// wrong. The real open decides that case.
NotebookFileProblem? notebookFileProblem(String path) {
  final type = FileSystemEntity.typeSync(path, followLinks: true);
  if (type == FileSystemEntityType.notFound) return NotebookFileProblem.missing;
  if (type != FileSystemEntityType.file) return NotebookFileProblem.notAFile;

  Uint8List head;
  try {
    final handle = File(path).openSync();
    try {
      head = handle.readSync(_headerBytes);
    } finally {
      handle.closeSync();
    }
  } catch (_) {
    return NotebookFileProblem.unreadable;
  }
  if (head.length < _headerBytes) return NotebookFileProblem.notANotebook;
  for (var i = 0; i < _sqliteMagic.length; i++) {
    if (head[i] != _sqliteMagic[i]) return NotebookFileProblem.notANotebook;
  }
  // Big-endian, like every multi-byte field in a SQLite header.
  final appId = (head[68] << 24) | (head[69] << 16) | (head[70] << 8) | head[71];
  if (appId == onoteApplicationId) return null;
  if (appId == 0 && File('$path-wal').existsSync()) return null;
  return NotebookFileProblem.notANotebook;
}

/// Offset 68 holds `application_id`; 72 is the first byte past it.
const int _headerBytes = 72;

/// The 16 bytes every SQLite file starts with: `SQLite format 3` and a NUL.
/// Spelled as bytes rather than as a string literal because the sixteenth byte
/// is a zero — a literal is the one way to write this that either hides a real
/// NUL in the source or, worse, quietly puts a space there instead.
const List<int> _sqliteMagic = [
  0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66, // "SQLite f"
  0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00, // "ormat 3" + NUL
];

/// Thrown by [openExistingOnote] when the container it was told to open is not
/// there. Carries the path for the Advanced fold and nothing else.
class NotebookFileMissing implements Exception {
  const NotebookFileMissing(this.path);
  final String path;

  @override
  String toString() => 'no notebook file at $path';
}

/// [openOnote], for a container that is **expected to already exist**.
///
/// **The difference is that this one refuses to invent a notebook** (v0.17
/// plan, Step 8 item 2). [openOnote] treats an `application_id` of zero as "a
/// fresh file" and seeds a brand-new notebook into it — which is right for
/// `createNotebook` and `adoptLogDirectory`, the two callers that genuinely
/// mean "make me one", and catastrophic for every other caller, which means
/// "open the one that is there".
///
/// Reachable today, without any migration: `Repository._db` opened whatever
/// path the registry named with no existence check at all, so an unmounted
/// drive, a cloud client that had evicted the file, or a container the user
/// moved in Explorer produced a valid `Database` with 0 nodes and 0 pages and
/// left a 73,728-byte file behind — after which `notebookFileProblem` reports
/// it as *"looks like a notebook"* and the real one is no longer registered.
///
/// It is also the single hazard that turned a crash into a disaster in the
/// spike this whole plan is written around: killed immediately after a rename,
/// the obvious *"just run it again"* called `openOnote` on the now-missing old
/// path, fabricated an empty database, and renamed it over the real
/// container — which `File.renameSync` on Windows does silently. 329 pages
/// became 73,728 bytes with `integrity_check` reporting `ok`.
Database openExistingOnote(String path,
    {required String notebookId, required String title}) {
  // `typeSync`, not `existsSync`: a *directory* where the container belongs is
  // the state `reclaimFreeSpace`'s own test constructs deliberately, and
  // `sqlite3.open` on one fails with a platform-dependent message rather than
  // with the thing that is actually wrong.
  if (FileSystemEntity.typeSync(path, followLinks: true) !=
      FileSystemEntityType.file) {
    throw NotebookFileMissing(path);
  }
  return openOnote(path, notebookId: notebookId, title: title);
}

Database openOnote(String path, {required String notebookId, required String title}) {
  final db = sqlite3.open(path);
  // **Before `journal_mode`, and before any table exists.** `auto_vacuum` can
  // only be set on a database with no pages — after that it takes a full
  // `VACUUM` to change, which is why this line's position is load-bearing
  // rather than stylistic.
  //
  // INCREMENTAL rather than FULL: FULL repacks on every commit, moving pages
  // during ordinary saves. INCREMENTAL only records what is free, and
  // [reclaimFreeSpace] spends it when the user asks. Without either, the file
  // holds its high-water mark forever — a notebook that once contained a
  // 60-slide deck stays that size after the deck is deleted, which is the
  // shape of complaint that started this work.
  db.execute('PRAGMA auto_vacuum=INCREMENTAL;');
  db.execute('PRAGMA journal_mode=WAL;');
  // WAL's recommended durability level: commits don't each fsync (a power cut
  // can lose the last few commits but never corrupts). Import measured ~700
  // small transactions; FULL fsync'd every one.
  db.execute('PRAGMA synchronous=NORMAL;');
  db.execute('PRAGMA foreign_keys=ON;');

  final appId = db.select('PRAGMA application_id;').first.columnAt(0) as int;
  final freshFile = appId == 0;
  if (!freshFile && appId != onoteApplicationId) {
    db.dispose();
    throw StateError('Not an Openote notebook: $path');
  }
  if (!freshFile) {
    final ver = db.select('PRAGMA user_version;').first.columnAt(0) as int;
    if (ver > onoteFormatMajor) {
      db.dispose();
      throw StateError('Notebook format v$ver is newer than this app supports.');
    }
  }
  // Every table/index is created idempotently on EVERY open, so a notebook made
  // by an earlier build that predates a table (e.g. refs, fts_pages,
  // page_versions) gains it here rather than throwing on first write.
  _ensureSchema(db);
  _dropBlobRefsBlobsFk(db);
  if (freshFile) {
    _seedNotebook(db, notebookId: notebookId, title: title);
  }
  _sweepOrphanedVersions(db);
  return db;
}

/// Rewrite `blob_refs` without its foreign key onto `blobs(hash)`.
///
/// **The one schema change v0.17 Step 6 could not avoid**, and the plan says
/// this step needs no migration at all — it does. Step 6 stops the container
/// storing blob bytes, so from that release on there is no `blobs` row for any
/// new picture. `writePage` records the page's blob references unconditionally
/// now (it has to: `blob_refs` is ADR-0007's GC root set, and a root set that
/// can only name bytes the container holds names nothing once the container
/// holds nothing). With the key still present that INSERT raises a constraint
/// violation *inside `writePage`'s savepoint*, which fails the whole page save
/// — the same shape as the sync-pull failure `sync_blobs_test.dart` was
/// written for, but on every save of every page with an image.
///
/// `CREATE TABLE IF NOT EXISTS` does not alter a table that already exists, so
/// changing the DDL above fixes new notebooks only; every notebook already on
/// disk has to be rewritten here. SQLite cannot drop a constraint in place, so
/// this is the documented twelve-step procedure
/// (<https://sqlite.org/lang_altertable.html>) reduced to what applies: build
/// the replacement, copy, drop, rename.
///
/// **Not a format bump.** `user_version` stays 1 deliberately — v2 is Step 8's,
/// and a build that predates this one opens a rewritten container perfectly
/// well: its `writePage` uses the old `SELECT … FROM blobs` form, which simply
/// records fewer rows, exactly as it does today.
///
/// Best-effort by design. A read-only volume or a full disk must still open the
/// notebook and show it (matrix row D5), and [NotebookWriter.writePage] falls
/// back to the old conditional INSERT when it meets the key still in place, so
/// a container this could not rewrite keeps saving.
void _dropBlobRefsBlobsFk(Database db) {
  try {
    final rows = db.select(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='blob_refs'");
    final ddl = rows.isEmpty ? null : rows.first['sql'] as String?;
    if (ddl == null || !ddl.contains('REFERENCES blobs')) return;
    // Outside any transaction, and off while the table is swapped: with
    // enforcement ON, `DROP TABLE blob_refs` would be checked against the very
    // rows being carried across.
    db.execute('PRAGMA foreign_keys=OFF;');
    try {
      db.execute('BEGIN;');
      db.execute('''
        CREATE TABLE blob_refs_new (
          page_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
          hash TEXT NOT NULL,
          PRIMARY KEY (page_id, hash));
      ''');
      db.execute('INSERT OR IGNORE INTO blob_refs_new(page_id,hash) '
          'SELECT page_id,hash FROM blob_refs;');
      db.execute('DROP TABLE blob_refs;');
      db.execute('ALTER TABLE blob_refs_new RENAME TO blob_refs;');
      db.execute('COMMIT;');
    } catch (_) {
      try {
        db.execute('ROLLBACK;');
      } catch (_) {/* nothing was open */}
      rethrow;
    } finally {
      db.execute('PRAGMA foreign_keys=ON;');
    }
  } catch (e) {
    // Said out loud rather than swallowed: the fallback in `writePage` keeps
    // saves working, but a container stuck here has an under-recorded GC root
    // set, and Step 7 must not run against one.
    debugPrint('[openote/store] blob_refs could not be rewritten: $e');
  }
}

/// Drop `page_versions` rows whose page no longer exists.
///
/// **A repair, placed here because the schema above cannot perform it.**
/// `page_mirror` and `blob_refs` both declare
/// `REFERENCES nodes(id) ON DELETE CASCADE`, so a purged page takes them with
/// it; `page_versions` never declared one, so up to thirty full page snapshots
/// per purged page stayed for good. [NotebookWriter.purgeNode] now deletes them
/// as it goes, but that only helps from here on: `CREATE TABLE IF NOT EXISTS`
/// does not alter a table that already exists, so it is not enough to fix the
/// schema for new notebooks — the rows already sitting in every notebook on
/// disk have to be swept, and this is the one line every open of every notebook
/// goes through. The comment on [_ensureSchema] states the same principle for
/// tables; this is its equivalent for rows.
///
/// **Why "no matching node" is only ever "the page was purged".** This is the
/// check the sweep stands or falls on, because deleting a snapshot that is
/// still restorable would destroy history no undo can bring back:
///
///  * A `page_versions` row can only be CREATED by
///    [Repository.maybeSnapshotVersion], which requires a `page_mirror` row —
///    and `page_mirror.page_id` is itself a foreign key onto `nodes(id)` with
///    `foreign_keys=ON`. So a snapshot cannot exist before its node does.
///  * Version history is container-local. There is no `OpKind` for it, so it
///    never arrives from another device ahead of the node it belongs to, the
///    way a page written before its section can (see the ordering note in
///    `AppState`'s pull).
///  * A page in the recycle bin KEEPS its `nodes` row — `softDeleteNode` only
///    stamps `deleted_at` — so a trashed page is not an orphan and its thirty
///    days of restorable history are not touched here. This is the same
///    deliberate absence of a `deleted_at` filter that
///    [Repository.everyStoredPageText] documents for the video sweep.
///  * A `nodes` row is hard-deleted in exactly two places, both permanent and
///    both user-or-retention driven: [NotebookWriter.purgeNode] and
///    [Repository.purgeExpiredNodes].
///
/// **Probe first, and best-effort, for the reason [checkpointAndClose] is.**
/// The import isolate opens its own connection to this same file, so a write
/// lock can legitimately be held while the main isolate opens it. The probe is
/// a read, which never blocks a WAL database; the DELETE only runs when there
/// is something to delete, which after the first sweep is never. A container
/// that is busy right now is a deferral to the next open — never a notebook
/// that refuses to open, which would be a far worse bug than the one being
/// fixed.
///
/// Measured on a 322 MB container holding 9,840 snapshots, the worst shape the
/// owner's 328-page imported notebook could reach: 19.6 ms on the first open
/// and 0.06 ms warm with nothing to sweep — the steady state, paid for ever —
/// and 364 ms for the one pass that actually deletes all 9,840. Single
/// statements, so neither can interleave with a write or yield mid-way; both
/// are a different order of magnitude from the 3.2 s and 10–20 s freezes that
/// 7851c3d and 75e0380 fixed. `auto_vacuum=INCREMENTAL` is already on, so the
/// freed pages return to the file when the user next reclaims space.
void _sweepOrphanedVersions(Database db) {
  try {
    final any = db.select('SELECT EXISTS(SELECT 1 FROM page_versions '
        'WHERE page_id NOT IN (SELECT id FROM nodes)) AS x').first['x'] as int;
    if (any == 0) return;
    db.execute(
        'DELETE FROM page_versions WHERE page_id NOT IN (SELECT id FROM nodes)');
  } catch (_) {
    // Locked by the import isolate, most likely. The next open tries again,
    // and nothing is at risk in the meantime beyond the space itself.
  }
}

/// Fold the write-ahead log back into the database, then close.
///
/// **Measured, on a real workspace:** `My Notebook.onote` was 2.8 MB with a
/// **4.1 MB** `-wal` beside it, and a 94 MB container carried 7.4 MB. SQLite
/// only checkpoints automatically at a page threshold and never truncates the
/// file, so a session that ends between thresholds leaves the whole WAL on
/// disk — permanently, because the next open starts appending again rather
/// than reclaiming it.
///
/// `TRUNCATE` (not `PASSIVE` or `FULL`) is the mode that actually returns the
/// space: the other two fold the pages in and leave the file at its
/// high-water mark, which is exactly the state being fixed.
///
/// Best-effort. A checkpoint can legitimately fail — another connection is
/// mid-read, the volume is gone — and a failure here must never stop the app
/// closing. The data is already durable either way; this is about the file's
/// size, not its contents.
void checkpointAndClose(Database db) {
  try {
    db.execute('PRAGMA wal_checkpoint(TRUNCATE);');
  } catch (_) {
    // Nothing to do about it, and nothing at risk.
  }
  db.dispose();
}

/// Idempotent DDL — safe to run on every open (all `IF NOT EXISTS`).
void _ensureSchema(Database db) {
  db.execute('''
    CREATE TABLE IF NOT EXISTS notebook_meta (
      key TEXT PRIMARY KEY, value TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS nodes (
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL CHECK (kind IN ('section_group','section','page')),
      parent_id TEXT REFERENCES nodes(id) ON DELETE CASCADE,
      title TEXT NOT NULL DEFAULT '',
      position TEXT NOT NULL,
      color TEXT, level INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
      deleted_at INTEGER);
    CREATE INDEX IF NOT EXISTS idx_nodes_parent ON nodes(parent_id, position);
    -- NOTE: `page_docs` and `page_updates` (the CRDT-in-SQLite layer of File
    -- Format Spec §3/§5) are deliberately NOT created. They were never
    -- populated — `page_docs` took a zero-byte placeholder on every save and
    -- `page_updates` was never written at all — and ADR-0006 supersedes the
    -- design: the operation log lives in FILES inside a `.onotebook` directory,
    -- not in the container, precisely so that dumb file sync has one writer per
    -- file. Creating empty tables shaped like a superseded plan misleads
    -- third-party readers about where the data is. Existing notebooks keep
    -- whatever tables they already have; nothing reads or writes them, and the
    -- container is rebuildable from the log once that lands, so there is no
    -- migration worth paying for now.
    CREATE TABLE IF NOT EXISTS page_mirror (
      page_id TEXT PRIMARY KEY REFERENCES nodes(id) ON DELETE CASCADE,
      json TEXT NOT NULL, mirror_rev INTEGER NOT NULL, updated_at INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS blobs (
      hash TEXT PRIMARY KEY, bytes BLOB NOT NULL, mime TEXT NOT NULL,
      size INTEGER NOT NULL, created_at INTEGER NOT NULL);
    -- **No foreign key on `hash`.** It used to be
    -- `REFERENCES blobs(hash)`, which made this table mean "blobs this page
    -- reaches THAT THIS CONTAINER HOLDS". From v0.17 Step 6 the container
    -- holds none: bytes go to `.onotebook/blobs/<sha256>` and the `blobs`
    -- table is legacy-only. With the key still in place every page carrying a
    -- picture would fail its INSERT — inside `writePage`'s savepoint, so the
    -- whole save — and `blob_refs` would be permanently empty, which is
    -- ADR-0007's garbage-collection root set. Existing containers are
    -- rewritten by [_dropBlobRefsBlobsFk]; the meaning is now simply "blobs
    -- this page reaches".
    CREATE TABLE IF NOT EXISTS blob_refs (
      page_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
      hash TEXT NOT NULL,
      PRIMARY KEY (page_id, hash));
    CREATE TABLE IF NOT EXISTS refs (
      src_page_id TEXT NOT NULL, src_block_id TEXT NOT NULL,
      kind TEXT NOT NULL CHECK (kind IN ('link','embed')),
      dst_page_id TEXT NOT NULL, dst_notebook TEXT, dst_target TEXT,
      PRIMARY KEY (src_page_id, src_block_id, kind));
    CREATE INDEX IF NOT EXISTS idx_refs_dst ON refs(dst_page_id);
    CREATE TABLE IF NOT EXISTS page_versions (
      page_id TEXT NOT NULL,
      version_at INTEGER NOT NULL,
      snapshot BLOB NOT NULL,
      label TEXT,
      PRIMARY KEY (page_id, version_at));
    -- Simplified version history (v0.17 plan, Step 8a). Both tables are
    -- DERIVED from the op log and neither is synced: dropping them costs a
    -- rebuild, never a note. See `store/history_store.dart`.
    --
    -- `block_authors` holds ONE row per block that currently exists, which is
    -- the whole difference from `page_versions` above — that table is bounded
    -- by how long a notebook has been edited, i.e. by nothing, and this one by
    -- how big the notebook is. It declares the `ON DELETE CASCADE` that
    -- `page_versions` never did, so the orphan class commit 1be2d28 had to
    -- sweep up cannot recur here; the need for that repair is designed out
    -- rather than fixed again.
    --
    -- `block_kind`, `chars` and `pins` are not decoration. They are what makes
    -- a LATER `block.remove` classifiable: without them, a lecture recording
    -- deleted in a session after the one that added it is indistinguishable
    -- from a deleted comma, and the ten-deep list would fill with editing.
    CREATE TABLE IF NOT EXISTS block_authors (
      page_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
      block_id TEXT NOT NULL,
      device TEXT NOT NULL,
      lamport INTEGER NOT NULL,
      seq INTEGER NOT NULL,
      changed_at INTEGER NOT NULL,
      block_kind TEXT NOT NULL,
      chars INTEGER NOT NULL,
      pins TEXT NOT NULL,
      PRIMARY KEY (page_id, block_id));
    -- Deliberately NOT keyed on `nodes`: a purged page has no `nodes` row, and
    -- that is precisely the entry a student most needs back. Its cap of ten is
    -- its prune, so nothing here can leak the way `page_versions` did.
    CREATE TABLE IF NOT EXISTS recent_deletions (
      device TEXT NOT NULL,
      seq INTEGER NOT NULL,
      lamport INTEGER NOT NULL,
      deleted_at INTEGER NOT NULL,
      kind TEXT NOT NULL,
      target_id TEXT NOT NULL,
      page_id TEXT,
      what TEXT NOT NULL,
      pins TEXT NOT NULL,
      PRIMARY KEY (device, seq));
  ''');
  // `fts_pages` is likewise not created. It was created on every open and then
  // never written to or queried — sidebar search is a Dart `contains()` scan —
  // so its presence advertised a search index that held nothing. Notebook-wide
  // search (TEXT-7) should build it deliberately, as a derived index of the
  // materialised cache, at the point someone implements the feature.
}

/// First-create-only: stamp the format identity and seed notebook metadata.
void _seedNotebook(Database db, {required String notebookId, required String title}) {
  db.execute('PRAGMA application_id = $onoteApplicationId;');
  db.execute('PRAGMA user_version = $onoteFormatMajor;');
  final now = DateTime.now().millisecondsSinceEpoch;
  final meta = <String, Object?>{
    'format': {'major': onoteFormatMajor, 'minor': 0},
    'notebook_id': notebookId,
    'title': title,
    'created_at': now,
    'app': 'openote/0.1.0',
    'features': <String>[],
    // `page_mirror` is the authoritative store in this container, not a
    // projection of something else — so there is no CRDT state for a
    // `dirty_mirror` flag to mark as stale, and setting one would tell a
    // third-party reader the opposite of the truth. Declared as a capability
    // instead: a reader that understands SQLite + JSON has everything.
    'content': 'page_mirror',
  };
  final stmt = db.prepare('INSERT OR REPLACE INTO notebook_meta(key,value) VALUES (?,?)');
  meta.forEach((k, v) => stmt.execute([k, jsonEncode(v)]));
  stmt.dispose();
}
