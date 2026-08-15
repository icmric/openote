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
  if (freshFile) {
    _seedNotebook(db, notebookId: notebookId, title: title);
  }
  return db;
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
    CREATE TABLE IF NOT EXISTS blob_refs (
      page_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
      hash TEXT NOT NULL REFERENCES blobs(hash),
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
