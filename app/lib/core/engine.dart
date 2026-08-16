/// The document-engine seam (ADR-0002). The app depends ONLY on
/// [DocumentEngine]; swapping implementations must never touch UI or repository
/// call sites.
///
/// Two implementations exist:
/// * [MirrorEngine] — pure Dart, the always-available fallback. Persists a
///   page's mirror JSON via the repository ("mirror-write mode", File Format
///   Spec §4).
/// * [RustEngine] — used when the native `onote-core` library is linked (see
///   `core/onote_ffi.dart`). It routes persistence through the Rust core:
///   every page is content-hashed in Rust, and a save whose hash is unchanged
///   is skipped entirely (no redundant write, no version-history churn). The
///   Rust `merge` is linked and tested for the coming sync path but is
///   deliberately NOT on the local save path — a single-device save is
///   authoritative, and merging against the stored copy would resurrect blocks
///   the user just deleted (the merge is add-wins by design).
library;

import 'dart:convert';

import '../model/models.dart';
import '../store/repository.dart';
import 'onote_ffi.dart';

abstract interface class DocumentEngine {
  /// Human-readable engine name for the status bar.
  String get label;

  /// The content hash of the most recently saved page, if the engine computes
  /// one (Rust). Null for the pure-Dart engine.
  String? get lastSavedHash;

  Future<PageData> loadPage(String notebookId, String pageId);

  Future<void> savePage(
      String notebookId, String pageId, List<Block> blocks, PageProps props);
}

/// Build the canonical page-mirror JSON (identical shape to
/// [Repository.writePage], so hashes computed here match what's persisted).
String pageMirrorJson(String pageId, List<Block> blocks, PageProps props) =>
    jsonEncode({
      'schema': 'onote-page/1',
      'pageId': pageId,
      'page': props.toJson(),
      'blocks': [for (final b in blocks) b.toJson()],
    });

class MirrorEngine implements DocumentEngine {
  MirrorEngine(this.repo);
  final Repository repo;

  @override
  String get label => 'Dart engine';

  @override
  String? get lastSavedHash => null;

  @override
  Future<PageData> loadPage(String notebookId, String pageId) async =>
      repo.readPage(notebookId, pageId);

  @override
  Future<void> savePage(String notebookId, String pageId, List<Block> blocks,
      PageProps props) async {
    // **No snapshot before the write** (v0.17 plan, decision 1). This used to
    // copy the whole page's JSON into `page_versions` every ten minutes of
    // editing, in the save path, and the table it wrote to is gone. Losing the
    // write is part of the point: it was a full page INSERT on the hot path.
    repo.writePage(notebookId, pageId, blocks, props);
  }
}

/// The Rust-backed engine. Active whenever [OnoteCore] loaded; every persistence
/// op flows Dart → Rust (hash) → Dart → SQLite.
class RustEngine implements DocumentEngine {
  RustEngine(this.repo, this.core);
  final Repository repo;
  final OnoteCore core;

  /// pageId → last content hash we know is persisted, so a save that didn't
  /// change anything is a no-op (cheap; keyed per session).
  final Map<String, String> _hashes = {};
  String? _lastSavedHash;

  late final String _label = 'Rust core v${core.version()}';

  @override
  String get label => _label;

  @override
  String? get lastSavedHash => _lastSavedHash;

  @override
  Future<PageData> loadPage(String notebookId, String pageId) async {
    final data = repo.readPage(notebookId, pageId);
    // Seed the hash from what's on disk so an immediate, change-free save is
    // recognised as a no-op.
    _hashes[pageId] =
        core.pageHash(pageMirrorJson(pageId, data.blocks, data.props));
    return data;
  }

  @override
  Future<void> savePage(String notebookId, String pageId, List<Block> blocks,
      PageProps props) async {
    final mirror = pageMirrorJson(pageId, blocks, props);
    final hash = core.pageHash(mirror);
    _lastSavedHash = hash;
    // Unchanged since the last persisted state → skip the write entirely.
    if (_hashes[pageId] == hash) return;
    _hashes[pageId] = hash;
    // See [MirrorEngine.savePage]: the ten-minute page snapshot is gone with
    // `page_versions` (v0.17 plan, decision 1).
    repo.writePage(notebookId, pageId, blocks, props);
  }
}
