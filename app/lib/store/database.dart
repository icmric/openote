/// The .onote container — File Format Spec (docs/specs/10-file-format-spec.md).
/// This file executes the spec's normative DDL (§3) verbatim in intent;
/// the app currently runs in mirror-write mode (§4): CRDT columns are
/// populated with placeholders and `dirty_mirror` is set in notebook_meta.
library;

import 'dart:convert';
import 'package:sqlite3/sqlite3.dart';

const onoteApplicationId = 0x4F4E4F54; // "ONOT"
const onoteFormatMajor = 1;

Database openOnote(String path, {required String notebookId, required String title}) {
  final db = sqlite3.open(path);
  db.execute('PRAGMA journal_mode=WAL;');
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
    CREATE TABLE IF NOT EXISTS page_docs (
      page_id TEXT PRIMARY KEY REFERENCES nodes(id) ON DELETE CASCADE,
      snapshot BLOB NOT NULL, snapshot_v INTEGER NOT NULL,
      updated_at INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS page_updates (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      page_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
      update_v INTEGER NOT NULL, bytes BLOB NOT NULL, created_at INTEGER NOT NULL);
    CREATE INDEX IF NOT EXISTS idx_updates_page ON page_updates(page_id, id);
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
  // FTS5 is present in sqlite3_flutter_libs bundles; degrade gracefully if not.
  try {
    db.execute(
        "CREATE VIRTUAL TABLE IF NOT EXISTS fts_pages USING fts5(title, body, content='', tokenize='unicode61 remove_diacritics 2');");
  } catch (_) {/* search degrades; never blocks notebooks */}
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
    'app': 'openote-mvp/0.1.0 (mirror-write mode)',
    'features': <String>[],
    'dirty_mirror': true, // spec §4: signals the future CRDT engine to reconcile
  };
  final stmt = db.prepare('INSERT OR REPLACE INTO notebook_meta(key,value) VALUES (?,?)');
  meta.forEach((k, v) => stmt.execute([k, jsonEncode(v)]));
  stmt.dispose();
}
