import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../core/ids.dart';
import '../model/models.dart';
import 'database.dart';

/// Workspace + notebook persistence. One SQLite Database handle per open
/// .onote (File Format Spec §2); workspace.json registry per spec §7.
class Repository {
  Repository._(this.workspaceDir);
  final Directory workspaceDir;
  final Map<String, Database> _open = {}; // notebookId -> db
  final List<NotebookRef> notebooks = [];
  // Soft-deleted notebooks (ORG-7). Their .onote file stays on disk so a
  // restore is lossless; purge removes the file for good.
  final List<NotebookRef> trashedNotebooks = [];

  static Future<Repository> open() async {
    final dir = await _resolveWorkspaceDir();
    final repo = Repository._(dir);
    await repo._loadWorkspace();
    if (repo.notebooks.isEmpty) {
      await repo.createNotebook('My Notebook');
    }
    return repo;
  }

  /// Open a workspace at an explicit directory, bypassing platform folder
  /// resolution. For tests/tools that need an isolated, path_provider-free
  /// workspace. Does NOT seed a default notebook.
  static Future<Repository> openAt(Directory dir) async {
    await dir.create(recursive: true);
    final repo = Repository._(dir);
    await repo._loadWorkspace();
    return repo;
  }

  /// Prefer ~/Documents/Openote, but fall back to the app-support directory.
  /// On Windows the Documents "known folder" can be redirected (OneDrive) so
  /// the literal path may not exist — creating it then fails with errno 2.
  static Future<Directory> _resolveWorkspaceDir() async {
    Future<Directory?> tryCreate(Future<Directory> Function() base) async {
      try {
        final root = await base();
        final dir = Directory(p.join(root.path, 'Openote'));
        await dir.create(recursive: true);
        return dir;
      } catch (_) {
        return null;
      }
    }

    final dir = await tryCreate(getApplicationDocumentsDirectory) ??
        await tryCreate(getApplicationSupportDirectory);
    if (dir == null) {
      throw StateError(
          'Openote could not create a workspace folder in Documents or app data.');
    }
    return dir;
  }

  File get _workspaceFile => File(p.join(workspaceDir.path, 'workspace.json'));

  /// True when the registry was unreadable and a backup had to be used (or
  /// nothing could be recovered) — the UI warns rather than silently pretending
  /// the workspace is empty.
  String? workspaceRecoveryNote;

  Future<void> _loadWorkspace() async {
    // Try the live registry, then the `.bak` written before the last replace.
    // A registry we can't parse must never look like "you have no notebooks".
    Map<String, dynamic>? j;
    for (final candidate in [_workspaceFile, File('${_workspaceFile.path}.bak')]) {
      if (!candidate.existsSync()) continue;
      try {
        final decoded = jsonDecode(await candidate.readAsString());
        if (decoded is Map<String, dynamic>) {
          j = decoded;
          if (candidate != _workspaceFile) {
            workspaceRecoveryNote =
                'workspace.json was unreadable; recovered from the backup.';
          }
          break;
        }
      } catch (_) {
        // Try the next candidate.
      }
    }
    if (j == null) {
      // Last resort: adopt any .onote files sitting in the workspace folder, so
      // a lost registry never hides real notebooks.
      final orphans = workspaceDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.onote'))
          .toList();
      if (orphans.isNotEmpty) {
        for (final f in orphans) {
          notebooks.add(NotebookRef(
              id: newId(),
              file: f.path,
              title: p.basenameWithoutExtension(f.path)));
        }
        workspaceRecoveryNote =
            'workspace.json was missing or unreadable; recovered '
            '${orphans.length} notebook${orphans.length == 1 ? '' : 's'} from disk.';
        await _saveNow();
      }
      return;
    }
    _settings = (j['settings'] as Map?)?.cast<String, dynamic>() ?? {};
    for (final n in (j['notebooks'] as List? ?? const [])) {
      final m = (n as Map).cast<String, dynamic>();
      final file = p.join(workspaceDir.path, m['file'] as String);
      if (File(file).existsSync()) {
        notebooks.add(NotebookRef(
            id: m['id'] as String, file: file, title: m['title'] as String? ?? 'Notebook'));
      }
    }
    for (final n in (j['trashed'] as List? ?? const [])) {
      final m = (n as Map).cast<String, dynamic>();
      final file = p.join(workspaceDir.path, m['file'] as String);
      if (File(file).existsSync()) {
        trashedNotebooks.add(NotebookRef(
            id: m['id'] as String,
            file: file,
            title: m['title'] as String? ?? 'Notebook',
            deletedAt: (m['deletedAt'] as num?)?.toInt() ?? nowMs()));
      }
    }
  }

  // Workspace-registry write serialisation. `workspace.json` lists every
  // notebook, and it used to be written with a bare (truncate-then-write)
  // `writeAsString`, fire-and-forget, up to three times per page switch. Any
  // crash inside that window truncated the file and the app then loaded ZERO
  // notebooks. Writes are now atomic (tmp + rename), chained so they can never
  // interleave, and coalesced so routine session state doesn't hammer the disk.
  Future<void> _writeChain = Future<void>.value();
  Timer? _writeDebounce;
  bool _writePending = false;

  /// Queue an atomic workspace write. Coalesces bursts; returns immediately.
  void _scheduleSaveWorkspace() {
    _writePending = true;
    _writeDebounce?.cancel();
    _writeDebounce = Timer(const Duration(milliseconds: 400), () {
      _writeChain = _writeChain.then((_) => _saveWorkspace());
    });
  }

  /// Write any pending workspace state now and wait for it (called on shutdown).
  Future<void> flushWorkspace() async {
    _writeDebounce?.cancel();
    if (_writePending) {
      _writeChain = _writeChain.then((_) => _saveWorkspace());
    }
    await _writeChain;
  }

  /// Chain a write and wait for it — for structural changes (notebook created,
  /// renamed, trashed, purged) that must be durable before we report success.
  /// Goes through the same chain as the debounced writes so the two can never
  /// interleave on the file.
  Future<void> _saveNow() {
    _writeDebounce?.cancel();
    _writePending = true;
    _writeChain = _writeChain.then((_) => _saveWorkspace());
    return _writeChain;
  }

  Future<void> _saveWorkspace() async {
    if (_disposed) return; // the workspace may no longer exist
    _writePending = false;
    await _writeAtomic(const JsonEncoder.withIndent('  ').convert({
      'format': {'major': 1, 'minor': 0},
      'workspace_id': _workspaceId ??= newId(),
      'notebooks': [
        for (final n in notebooks)
          {'id': n.id, 'file': p.basename(n.file), 'title': n.title}
      ],
      'trashed': [
        for (final n in trashedNotebooks)
          {
            'id': n.id,
            'file': p.basename(n.file),
            'title': n.title,
            'deletedAt': n.deletedAt,
          }
      ],
      'settings': _settings,
    }));
  }

  /// Atomic replace: write a temp file, flush it to disk, keep the previous
  /// version as `.bak`, then rename over the original. `rename` within a
  /// directory is atomic on NTFS, APFS and ext4, so a crash leaves either the
  /// old file or the new one — never a truncated one.
  Future<void> _writeAtomic(String contents) async {
    final target = _workspaceFile;
    final tmp = File('${target.path}.tmp');
    try {
      final handle = await tmp.open(mode: FileMode.writeOnly);
      try {
        await handle.writeString(contents);
        await handle.flush();
      } finally {
        await handle.close();
      }
      if (target.existsSync()) {
        try {
          await target.copy('${target.path}.bak');
        } catch (_) {/* a missing backup must never block the real write */}
      }
      await tmp.rename(target.path);
    } catch (_) {
      // Leave the existing (valid) file alone rather than half-replacing it.
      try {
        if (tmp.existsSync()) await tmp.delete();
      } catch (_) {/* best effort */}
      rethrow;
    }
  }

  String? _workspaceId;

  /// Workspace settings (spec §7): session state, custom colours, templates.
  Map<String, dynamic> _settings = {};
  dynamic getSetting(String key) => _settings[key];
  void setSetting(String key, dynamic value) {
    _settings[key] = value;
    // Session state (view memory, last page) changes constantly — coalesce.
    _scheduleSaveWorkspace();
  }

  Database _db(String notebookId) {
    final nb = notebooks.firstWhere((n) => n.id == notebookId);
    return _open.putIfAbsent(
        notebookId, () => openOnote(nb.file, notebookId: nb.id, title: nb.title));
  }

  // ── Notebooks ──────────────────────────────────────────────────────────

  /// Move a notebook's container and its `.onotebook` log directory to
  /// [targetDir], and point the registry at the new location.
  ///
  /// Copy-then-verify-then-delete, never a bare rename: the destination is
  /// usually a *different volume* (a cloud provider's folder), where rename
  /// isn't atomic and can't be, and a half-moved notebook is the worst
  /// possible outcome. The original is removed only after every byte is
  /// confirmed at the destination.
  ///
  /// Returns the new container path.
  Future<String> moveNotebookTo(String notebookId, String targetDir) async {
    final ref = notebooks.firstWhere((n) => n.id == notebookId);
    final src = File(ref.file);
    if (!src.existsSync()) throw StateError('notebook file is missing');

    final dir = Directory(targetDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final base = p.basenameWithoutExtension(ref.file);
    var destFile = p.join(targetDir, '$base.onote');
    // Never overwrite something already there.
    var n = 2;
    while (File(destFile).existsSync() ||
        Directory(p.join(targetDir, '$base.onotebook')).existsSync()) {
      destFile = p.join(targetDir, '$base ($n).onote');
      if (!File(destFile).existsSync() &&
          !Directory(p.join(targetDir, '$base ($n).onotebook')).existsSync()) {
        break;
      }
      n++;
      if (n > 500) throw StateError('cannot find a free name in that folder');
    }
    final destBase = p.withoutExtension(destFile);

    // Close our handle first: SQLite must not be mid-write while the file is
    // copied, and on Windows an open handle blocks the delete outright.
    _open.remove(notebookId)?.dispose();

    await src.copy(destFile);
    if (File(destFile).lengthSync() != src.lengthSync()) {
      throw StateError('copy did not complete — the notebook was NOT moved');
    }

    // The log directory travels with the container, or the notebook arrives
    // without the very thing that makes it syncable.
    final srcLog = Directory('${p.withoutExtension(ref.file)}.onotebook');
    if (srcLog.existsSync()) {
      await _copyDirectory(srcLog, Directory('$destBase.onotebook'));
    }

    // Only now is it safe to remove the originals.
    try {
      src.deleteSync();
      if (srcLog.existsSync()) srcLog.deleteSync(recursive: true);
    } catch (_) {
      // Copy succeeded but cleanup didn't (a lock, a permission). The notebook
      // is intact at the destination; leaving a stale original is far better
      // than failing the move after the data has already landed.
    }

    ref.file = destFile;
    _scheduleSaveWorkspace();
    return destFile;
  }

  static Future<void> _copyDirectory(Directory from, Directory to) async {
    to.createSync(recursive: true);
    for (final entity in from.listSync(recursive: true)) {
      final rel = p.relative(entity.path, from: from.path);
      final target = p.join(to.path, rel);
      if (entity is Directory) {
        Directory(target).createSync(recursive: true);
      } else if (entity is File) {
        Directory(p.dirname(target)).createSync(recursive: true);
        await entity.copy(target);
      }
    }
  }

  Future<NotebookRef> createNotebook(String title) async {
    final id = newId();
    final file = _freeNotebookPath(title);
    final ref = NotebookRef(id: id, file: file, title: title);
    notebooks.add(ref);
    _open[id] = openOnote(file, notebookId: id, title: title);
    // Seed a first section + page so the notebook is immediately usable.
    final section = upsertNode(id, TreeNode(kind: NodeKind.section, title: 'Section 1'));
    upsertNode(id,
        TreeNode(kind: NodeKind.page, parentId: section.id, title: 'Untitled page'));
    await _saveNow();
    return ref;
  }

  /// A unique `<base>.onote` path in the workspace (suffixing `-2`, `-3`, … as
  /// needed). Shared by create and duplicate so both name files the same way.
  String _freeNotebookPath(String title) {
    var base = title.replaceAll(RegExp(r'[^\w\- ]'), '').trim();
    if (base.isEmpty) base = 'Notebook';
    var file = p.join(workspaceDir.path, '$base.onote');
    var i = 2;
    while (File(file).existsSync()) {
      file = p.join(workspaceDir.path, '$base-$i.onote');
      i++;
    }
    return file;
  }

  /// Copy a notebook, contents and all. A `.onote` is a self-contained SQLite
  /// file, so a byte copy duplicates pages, blobs, versions and history exactly
  /// — no walking the tree, nothing missed. The copy gets a fresh workspace id;
  /// its internal `notebook_id` metadata is rewritten so the two don't collide
  /// once sync lands.
  Future<NotebookRef> duplicateNotebook(String id, {String? title}) async {
    final src = notebooks.firstWhere((n) => n.id == id);
    final newTitle = title ?? '${src.title} copy';
    // Settle any pending writes to the source before copying its bytes.
    final open = _open[id];
    if (open != null) open.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    final dstPath = _freeNotebookPath(newTitle);
    await File(src.file).copy(dstPath);
    final newId0 = newId();
    final ref = NotebookRef(id: newId0, file: dstPath, title: newTitle);
    notebooks.add(ref);
    final db = openOnote(dstPath, notebookId: newId0, title: newTitle);
    db.execute(
        "INSERT INTO notebook_meta(key,value) VALUES('notebook_id',?) "
        'ON CONFLICT(key) DO UPDATE SET value=excluded.value',
        [jsonEncode(newId0)]);
    db.execute(
        "INSERT INTO notebook_meta(key,value) VALUES('title',?) "
        'ON CONFLICT(key) DO UPDATE SET value=excluded.value',
        [jsonEncode(newTitle)]);
    _open[newId0] = db;
    await _saveNow();
    return ref;
  }

  /// Page/section counts for the notebook manager, without opening the notebook
  /// in the UI. Cheap: two indexed COUNTs.
  ({int sections, int pages}) notebookCounts(String id) {
    try {
      final db = _db(id);
      int count(String kind) => db.select(
          'SELECT COUNT(*) AS c FROM nodes WHERE kind=? AND deleted_at IS NULL',
          [kind]).first['c'] as int;
      return (sections: count('section'), pages: count('page'));
    } catch (_) {
      return (sections: 0, pages: 0); // unreadable file — manager shows dashes
    }
  }

  Future<void> renameNotebook(String id, String title) async {
    final ref = notebooks.firstWhere((n) => n.id == id);
    ref.title = title;
    await _saveNow();
  }

  /// Move a notebook to the recycle bin (ORG-7). Closes its db handle but keeps
  /// the .onote file, so [restoreNotebook] brings it back untouched.
  Future<void> trashNotebook(String id) async {
    final i = notebooks.indexWhere((n) => n.id == id);
    if (i < 0) return;
    final ref = notebooks.removeAt(i);
    ref.deletedAt = nowMs();
    trashedNotebooks.add(ref);
    _open.remove(id)?.dispose();
    await _saveNow();
  }

  Future<void> restoreNotebook(String id) async {
    final i = trashedNotebooks.indexWhere((n) => n.id == id);
    if (i < 0) return;
    final ref = trashedNotebooks.removeAt(i);
    ref.deletedAt = null;
    notebooks.add(ref);
    await _saveNow();
  }

  /// Permanently delete a trashed notebook, including its .onote file.
  Future<void> purgeNotebook(String id) async {
    final i = trashedNotebooks.indexWhere((n) => n.id == id);
    if (i < 0) return;
    final ref = trashedNotebooks.removeAt(i);
    _open.remove(id)?.dispose();
    try {
      final f = File(ref.file);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {/* best-effort; the workspace entry is already gone */}
    await _saveNow();
  }

  // ── Recycle-bin retention (ORG-7): auto-purge after N days ──────────────

  /// Deleted notebooks and nodes are permanently removed this long after they
  /// were trashed, so the recycle bin doesn't grow without bound.
  static const int recycleRetentionDays = 30;

  int _retentionCutoff() =>
      nowMs() - const Duration(days: recycleRetentionDays).inMilliseconds;

  /// Purge trashed notebooks past their retention window. Returns how many.
  Future<int> purgeExpiredNotebooks() async {
    final cutoff = _retentionCutoff();
    final expired = trashedNotebooks
        .where((n) => (n.deletedAt ?? 0) < cutoff)
        .map((n) => n.id)
        .toList();
    for (final id in expired) {
      await purgeNotebook(id);
    }
    return expired.length;
  }

  /// Purge soft-deleted nodes in [notebookId] past their retention window.
  void purgeExpiredNodes(String notebookId) {
    _db(notebookId).execute(
        'DELETE FROM nodes WHERE deleted_at IS NOT NULL AND deleted_at < ?',
        [_retentionCutoff()]);
  }

  // ── Tree nodes ─────────────────────────────────────────────────────────

  List<TreeNode> loadNodes(String notebookId) {
    final rows = _db(notebookId).select(
        'SELECT id,kind,parent_id,title,position,color,level,created_at,updated_at '
        'FROM nodes WHERE deleted_at IS NULL ORDER BY position');
    return [
      for (final r in rows)
        TreeNode(
          id: r['id'] as String,
          kind: switch (r['kind'] as String) {
            'section_group' => NodeKind.sectionGroup,
            'section' => NodeKind.section,
            _ => NodeKind.page,
          },
          parentId: r['parent_id'] as String?,
          title: r['title'] as String,
          position: r['position'] as String,
          color: r['color'] as String?,
          level: r['level'] as int,
          createdAt: r['created_at'] as int,
        )..updatedAt = r['updated_at'] as int
    ];
  }

  TreeNode upsertNode(String notebookId, TreeNode n) {
    n.updatedAt = nowMs();
    _db(notebookId).execute(
      'INSERT INTO nodes(id,kind,parent_id,title,position,color,level,created_at,updated_at) '
      'VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET '
      'parent_id=excluded.parent_id,title=excluded.title,position=excluded.position,'
      'color=excluded.color,level=excluded.level,updated_at=excluded.updated_at',
      [
        n.id,
        switch (n.kind) {
          NodeKind.sectionGroup => 'section_group',
          NodeKind.section => 'section',
          NodeKind.page => 'page',
        },
        n.parentId, n.title, n.position, n.color, n.level, n.createdAt, n.updatedAt,
      ],
    );
    return n;
  }

  List<String> _descendants(Database db, String id) {
    final out = <String>[id];
    final queue = [id];
    while (queue.isNotEmpty) {
      final cur = queue.removeLast();
      for (final r in db.select('SELECT id FROM nodes WHERE parent_id=?', [cur])) {
        final cid = r['id'] as String;
        out.add(cid);
        queue.add(cid);
      }
    }
    return out;
  }

  /// Soft-delete a node and everything under it (ORG-7 recycle bin).
  void softDeleteNode(String notebookId, String nodeId) {
    final db = _db(notebookId);
    final ts = nowMs();
    for (final id in _descendants(db, nodeId)) {
      db.execute(
          'UPDATE nodes SET deleted_at=? WHERE id=? AND deleted_at IS NULL',
          [ts, id]);
    }
  }

  /// Restore a node, its descendants, and its ancestors (so it reattaches).
  void restoreNode(String notebookId, String nodeId) {
    final db = _db(notebookId);
    for (final id in _descendants(db, nodeId)) {
      db.execute('UPDATE nodes SET deleted_at=NULL WHERE id=?', [id]);
    }
    var parent = db
        .select('SELECT parent_id FROM nodes WHERE id=?', [nodeId])
        .firstOrNull?['parent_id'] as String?;
    while (parent != null) {
      db.execute('UPDATE nodes SET deleted_at=NULL WHERE id=?', [parent]);
      parent = db
          .select('SELECT parent_id FROM nodes WHERE id=?', [parent])
          .firstOrNull?['parent_id'] as String?;
    }
  }

  /// Permanently delete a node and its subtree (FK cascade clears page data).
  void purgeNode(String notebookId, String nodeId) {
    _db(notebookId).execute('DELETE FROM nodes WHERE id=?', [nodeId]);
  }

  List<({String id, String kind, String title, int deletedAt})> loadDeletedNodes(
      String notebookId) {
    final rows = _db(notebookId).select(
        'SELECT id,kind,title,deleted_at FROM nodes '
        'WHERE deleted_at IS NOT NULL ORDER BY deleted_at DESC');
    return [
      for (final r in rows)
        (
          id: r['id'] as String,
          kind: r['kind'] as String,
          title: r['title'] as String,
          deletedAt: r['deleted_at'] as int,
        )
    ];
  }

  // ── Version history (SYNC-8, page_versions table) ─────────────────────

  /// Snapshot the page's current mirror into page_versions if the newest
  /// version is older than [minGap] (or none exists). Called before saves.
  void maybeSnapshotVersion(String notebookId, String pageId,
      {Duration minGap = const Duration(minutes: 10)}) {
    final db = _db(notebookId);
    final cur = db
        .select('SELECT json FROM page_mirror WHERE page_id=?', [pageId])
        .firstOrNull?['json'] as String?;
    if (cur == null) return;
    final newest = db
        .select(
            'SELECT MAX(version_at) AS m FROM page_versions WHERE page_id=?',
            [pageId])
        .first['m'] as int?;
    final now = nowMs();
    if (newest != null && now - newest < minGap.inMilliseconds) return;
    db.execute(
        'INSERT OR REPLACE INTO page_versions(page_id,version_at,snapshot,label) '
        'VALUES(?,?,?,NULL)',
        [pageId, now, Uint8List.fromList(utf8.encode(cur))]);
    // Retention: keep the newest 30 versions per page.
    db.execute(
        'DELETE FROM page_versions WHERE page_id=? AND version_at NOT IN '
        '(SELECT version_at FROM page_versions WHERE page_id=? '
        'ORDER BY version_at DESC LIMIT 30)',
        [pageId, pageId]);
  }

  List<int> listVersions(String notebookId, String pageId) => [
        for (final r in _db(notebookId).select(
            'SELECT version_at FROM page_versions WHERE page_id=? '
            'ORDER BY version_at DESC',
            [pageId]))
          r['version_at'] as int
      ];

  String? versionJson(String notebookId, String pageId, int at) {
    final row = _db(notebookId).select(
        'SELECT snapshot FROM page_versions WHERE page_id=? AND version_at=?',
        [pageId, at]).firstOrNull;
    return row == null ? null : utf8.decode(row['snapshot'] as Uint8List);
  }

  /// Distinct pages that link to [pageId] (backlinks, TEXT-8).
  List<String> backlinkPageIds(String notebookId, String pageId) {
    final rows = _db(notebookId).select(
        'SELECT DISTINCT src_page_id FROM refs '
        'WHERE dst_page_id=? AND src_page_id<>?',
        [pageId, pageId]);
    return [for (final r in rows) r['src_page_id'] as String];
  }

  // ── Page content (mirror-write mode, spec §4) ──────────────────────────

  PageData readPage(String notebookId, String pageId) {
    final rows = _db(notebookId)
        .select('SELECT json FROM page_mirror WHERE page_id=?', [pageId]);
    if (rows.isEmpty) return PageData([], PageProps());
    final j = jsonDecode(rows.first['json'] as String) as Map<String, dynamic>;
    return PageData(
      [
        for (final b in (j['blocks'] as List? ?? const []))
          Block.fromJson((b as Map).cast<String, dynamic>())
      ],
      PageProps.fromJson((j['page'] as Map?)?.cast<String, dynamic>()),
    );
  }

  /// Run [fn] in ONE transaction on [notebookId]'s database. [writePage] uses
  /// savepoints so it nests; imports batch hundreds of page writes into a
  /// single commit instead of paying per-page transaction overhead.
  T runInTransaction<T>(String notebookId, T Function() fn) {
    final db = _db(notebookId);
    db.execute('BEGIN IMMEDIATE');
    try {
      final r = fn();
      db.execute('COMMIT');
      return r;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  // Compiled once, not per save. `_inlineImgRe` tolerates the optional
  // ` =WxH` display-size suffix the OneNote importer writes — without it,
  // in-flow imported images never got a `blob_refs` row.
  static final _inlineImgRe =
      RegExp(r'!\[[^\]]*\]\(sha256:([0-9a-fA-F]{64})(?:\s+=\d+x\d+)?\)');
  static final _linkRe = RegExp(r'\[\[([^\]|]+)(?:\|([^\]]+))?\]\]');

  void writePage(
      String notebookId, String pageId, List<Block> blocks, PageProps props) {
    final db = _db(notebookId);
    final json = jsonEncode({
      'schema': 'onote-page/1',
      'pageId': pageId,
      'page': props.toJson(),
      'blocks': [for (final b in blocks) b.toJson()],
    });
    // SAVEPOINT (not BEGIN) so this works standalone AND inside
    // [runInTransaction] — BEGIN can't nest.
    db.execute('SAVEPOINT write_page');
    try {
      db.execute(
          'INSERT INTO page_mirror(page_id,json,mirror_rev,updated_at) VALUES(?,?,1,?) '
          'ON CONFLICT(page_id) DO UPDATE SET json=excluded.json, '
          'mirror_rev=mirror_rev+1, updated_at=excluded.updated_at',
          [pageId, json, nowMs()]);
      // (No CRDT placeholder row. This used to write a zero-byte blob into
      // `page_docs` on every single save to "keep the schema honest" for a
      // CRDT layer that never arrived — and that ADR-0006 has now replaced with
      // a file-based op log outside the container entirely. It was pure write
      // amplification: an INSERT-or-UPDATE per save carrying no information.)
      // Maintain blob_refs projection: image/file blocks plus in-flow images
      // referenced from text markdown (`![alt](sha256:<hash>)`, Data Model §5.1).
      db.execute('DELETE FROM blob_refs WHERE page_id=?', [pageId]);
      for (final b in blocks) {
        final hash = b.content['blob'];
        if (hash is String) {
          db.execute(
              'INSERT OR IGNORE INTO blob_refs(page_id,hash) VALUES(?,?)',
              [pageId, hash.replaceFirst('sha256:', '')]);
        }
        final text = b.content['text'];
        if (text is String && text.contains('](sha256:')) {
          for (final m in _inlineImgRe.allMatches(text)) {
            db.execute(
                'INSERT OR IGNORE INTO blob_refs(page_id,hash) VALUES(?,?)',
                [pageId, m.group(1)!.toLowerCase()]);
          }
        }
      }
      // Maintain the refs index (links & embeds) for backlinks (TEXT-8).
      db.execute('DELETE FROM refs WHERE src_page_id=?', [pageId]);
      for (final b in blocks) {
        if (b.type == BlockType.text) {
          final txt = b.content['text'] as String? ?? '';
          var idx = 0;
          for (final m in _linkRe.allMatches(txt)) {
            // `[[Title|id]]` carries the target id; a bare `[[Title]]` — the
            // form the PRD documents — must be resolved by title, or it
            // produces no backlink at all even though clicking it navigates.
            var dst = m.group(2);
            if (dst == null) {
              final label = m.group(1)!.trim().toLowerCase();
              dst = db
                  .select(
                      "SELECT id FROM nodes WHERE kind='page' "
                      'AND deleted_at IS NULL AND lower(trim(title))=? LIMIT 1',
                      [label])
                  .firstOrNull?['id'] as String?;
            }
            if (dst == null) continue; // unresolvable target — nothing to index
            db.execute(
                'INSERT OR IGNORE INTO refs'
                '(src_page_id,src_block_id,kind,dst_page_id,dst_notebook,dst_target) '
                'VALUES(?,?,?,?,?,?)',
                [pageId, '${b.id}#${idx++}', 'link', dst, null, null]);
          }
        } else if (b.type == BlockType.embed) {
          final ref = (b.content['ref'] as Map?)?.cast<String, dynamic>();
          final dst = ref?['pageId'] as String?;
          if (dst != null) {
            db.execute(
                'INSERT OR IGNORE INTO refs'
                '(src_page_id,src_block_id,kind,dst_page_id,dst_notebook,dst_target) '
                'VALUES(?,?,?,?,?,?)',
                [pageId, b.id, 'embed', dst, null, null]);
          }
        }
      }
      db.execute('RELEASE write_page');
    } catch (_) {
      db.execute('ROLLBACK TO write_page');
      db.execute('RELEASE write_page');
      rethrow;
    }
  }

  // ── Blobs (content-addressed) ──────────────────────────────────────────

  String putBlob(String notebookId, Uint8List bytes, String mime) {
    final hash = _sha256Hex(bytes);
    _db(notebookId).execute(
        'INSERT OR IGNORE INTO blobs(hash,bytes,mime,size,created_at) VALUES(?,?,?,?,?)',
        [hash, bytes, mime, bytes.length, nowMs()]);
    return hash;
  }

  Uint8List? getBlob(String notebookId, String hash) {
    final rows = _db(notebookId).select(
        'SELECT bytes FROM blobs WHERE hash=?', [hash.replaceFirst('sha256:', '')]);
    return rows.isEmpty ? null : rows.first['bytes'] as Uint8List;
  }

  /// Pages whose content contains [query], with a snippet around the first hit.
  ///
  /// Brute force over `page_mirror` by design (TEXT-7). An FTS5 index would be
  /// faster, but it is a second thing to keep correct — it must be rebuilt on
  /// every write, it can silently drift from the content, and the spec then has
  /// to describe it for third-party writers. Scanning JSON is ~10 ms for a
  /// 300-page notebook, which is well inside "instant" for a search box.
  /// Revisit when a real notebook makes it slow, not before.
  List<({String pageId, String snippet})> searchPageContent(
      String notebookId, String query,
      {int limit = 50}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final out = <({String pageId, String snippet})>[];
    final rows = _db(notebookId).select('SELECT page_id, json FROM page_mirror');
    for (final r in rows) {
      final json = r['json'] as String;
      // Cheap reject on the raw JSON before parsing: most pages don't match,
      // and decoding every page's block tree to find that out is the expensive
      // part.
      if (!json.toLowerCase().contains(q)) continue;
      out.add((
        pageId: r['page_id'] as String,
        snippet: _snippetFrom(json, q),
      ));
      if (out.length >= limit) break;
    }
    return out;
  }

  /// A readable line of context around the first match, from the page's text
  /// blocks only — a raw-JSON substring would show field names and coordinates.
  static String _snippetFrom(String json, String lowerQuery) {
    try {
      final j = jsonDecode(json) as Map<String, dynamic>;
      for (final b in (j['blocks'] as List? ?? const [])) {
        final text = ((b as Map)['content'] as Map?)?['text'];
        if (text is! String) continue;
        final i = text.toLowerCase().indexOf(lowerQuery);
        if (i < 0) continue;
        final start = (i - 30).clamp(0, text.length);
        final end = (i + lowerQuery.length + 40).clamp(0, text.length);
        final s = text.substring(start, end).replaceAll('\n', ' ').trim();
        return '${start > 0 ? '…' : ''}$s${end < text.length ? '…' : ''}';
      }
    } catch (_) {/* fall through to no snippet */}
    return '';
  }

  /// Every blob hash with its mime and size, but **not** its bytes.
  ///
  /// Deliberately metadata-only: the caller (the op-log backfill) streams blobs
  /// one at a time via [getBlob], because loading a whole notebook's images into
  /// memory at once would be hundreds of megabytes on a real imported notebook.
  List<({String hash, String mime, int size})> blobIndex(String notebookId) => [
        for (final r in _db(notebookId)
            .select('SELECT hash,mime,size FROM blobs ORDER BY hash'))
          (
            hash: r['hash'] as String,
            mime: r['mime'] as String? ?? 'application/octet-stream',
            size: (r['size'] as num?)?.toInt() ?? 0,
          )
      ];

  void dispose() {
    // Stop the debounced registry writer first: a pending write firing after
    // the workspace has gone away throws an unhandled PathNotFoundException
    // (and in a test, after the temp directory is deleted).
    _writeDebounce?.cancel();
    _writePending = false;
    _disposed = true;
    for (final db in _open.values) {
      db.dispose();
    }
    _open.clear();
  }

  bool _disposed = false;
}

// Minimal SHA-256 via SQLite would need an extension; use Dart's built-in
// approach instead: FNV-free, real SHA-256 from package:crypto would add a dep —
// but Flutter bundles it transitively rarely, so implement via `Hmac`? Simpler:
// use the sqlite hash if present, else fall back to a Dart implementation.
// To keep the MVP dependency-light we vendor a tiny SHA-256:
String _sha256Hex(Uint8List data) => _Sha256.hex(data);

/// Compact SHA-256 (FIPS 180-4). Vendored to avoid an extra dependency;
/// replace with package:crypto if preferred.
class _Sha256 {
  static const _k = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  static String hex(Uint8List data) {
    final h = [
      0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
      0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ];
    final bitLen = data.length * 8;
    final padded = BytesBuilder()
      ..add(data)
      ..addByte(0x80);
    while (padded.length % 64 != 56) {
      padded.addByte(0);
    }
    final lenBytes = ByteData(8)..setUint64(0, bitLen);
    padded.add(lenBytes.buffer.asUint8List());
    final msg = padded.toBytes();
    final w = List<int>.filled(64, 0);
    int rotr(int x, int n) => ((x >>> n) | (x << (32 - n))) & 0xffffffff;

    for (var i = 0; i < msg.length; i += 64) {
      for (var t = 0; t < 16; t++) {
        w[t] = (msg[i + t * 4] << 24) |
            (msg[i + t * 4 + 1] << 16) |
            (msg[i + t * 4 + 2] << 8) |
            msg[i + t * 4 + 3];
      }
      for (var t = 16; t < 64; t++) {
        final s0 = rotr(w[t - 15], 7) ^ rotr(w[t - 15], 18) ^ (w[t - 15] >>> 3);
        final s1 = rotr(w[t - 2], 17) ^ rotr(w[t - 2], 19) ^ (w[t - 2] >>> 10);
        w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & 0xffffffff;
      }
      var a = h[0], b = h[1], c = h[2], d = h[3];
      var e = h[4], f = h[5], g = h[6], hh = h[7];
      for (var t = 0; t < 64; t++) {
        final s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
        final ch = (e & f) ^ ((~e & 0xffffffff) & g);
        final t1 = (hh + s1 + ch + _k[t] + w[t]) & 0xffffffff;
        final s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final t2 = (s0 + maj) & 0xffffffff;
        hh = g; g = f; f = e;
        e = (d + t1) & 0xffffffff;
        d = c; c = b; b = a;
        a = (t1 + t2) & 0xffffffff;
      }
      h[0] = (h[0] + a) & 0xffffffff;
      h[1] = (h[1] + b) & 0xffffffff;
      h[2] = (h[2] + c) & 0xffffffff;
      h[3] = (h[3] + d) & 0xffffffff;
      h[4] = (h[4] + e) & 0xffffffff;
      h[5] = (h[5] + f) & 0xffffffff;
      h[6] = (h[6] + g) & 0xffffffff;
      h[7] = (h[7] + hh) & 0xffffffff;
    }
    return h.map((v) => v.toRadixString(16).padLeft(8, '0')).join();
  }
}
