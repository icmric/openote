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

  static Future<Repository> open() async {
    final dir = await _resolveWorkspaceDir();
    final repo = Repository._(dir);
    await repo._loadWorkspace();
    if (repo.notebooks.isEmpty) {
      await repo.createNotebook('My Notebook');
    }
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

  Future<void> _loadWorkspace() async {
    if (!_workspaceFile.existsSync()) return;
    final j = jsonDecode(await _workspaceFile.readAsString()) as Map<String, dynamic>;
    _settings = (j['settings'] as Map?)?.cast<String, dynamic>() ?? {};
    for (final n in (j['notebooks'] as List? ?? const [])) {
      final m = (n as Map).cast<String, dynamic>();
      final file = p.join(workspaceDir.path, m['file'] as String);
      if (File(file).existsSync()) {
        notebooks.add(NotebookRef(
            id: m['id'] as String, file: file, title: m['title'] as String? ?? 'Notebook'));
      }
    }
  }

  Future<void> _saveWorkspace() async {
    await _workspaceFile.writeAsString(const JsonEncoder.withIndent('  ').convert({
      'format': {'major': 1, 'minor': 0},
      'workspace_id': _workspaceId ??= newId(),
      'notebooks': [
        for (final n in notebooks)
          {'id': n.id, 'file': p.basename(n.file), 'title': n.title}
      ],
      'settings': _settings,
    }));
  }

  String? _workspaceId;

  /// Workspace settings (spec §7): session state, custom colours, templates.
  Map<String, dynamic> _settings = {};
  dynamic getSetting(String key) => _settings[key];
  void setSetting(String key, dynamic value) {
    _settings[key] = value;
    _saveWorkspace(); // fire-and-forget; small file
  }

  Database _db(String notebookId) {
    final nb = notebooks.firstWhere((n) => n.id == notebookId);
    return _open.putIfAbsent(
        notebookId, () => openOnote(nb.file, notebookId: nb.id, title: nb.title));
  }

  // ── Notebooks ──────────────────────────────────────────────────────────

  Future<NotebookRef> createNotebook(String title) async {
    final id = newId();
    var base = title.replaceAll(RegExp(r'[^\w\- ]'), '').trim();
    if (base.isEmpty) base = 'Notebook';
    var file = p.join(workspaceDir.path, '$base.onote');
    var i = 2;
    while (File(file).existsSync()) {
      file = p.join(workspaceDir.path, '$base-$i.onote');
      i++;
    }
    final ref = NotebookRef(id: id, file: file, title: title);
    notebooks.add(ref);
    _open[id] = openOnote(file, notebookId: id, title: title);
    // Seed a first section + page so the notebook is immediately usable.
    final section = upsertNode(id, TreeNode(kind: NodeKind.section, title: 'Section 1'));
    upsertNode(id,
        TreeNode(kind: NodeKind.page, parentId: section.id, title: 'Untitled page'));
    await _saveWorkspace();
    return ref;
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

  void writePage(
      String notebookId, String pageId, List<Block> blocks, PageProps props) {
    final db = _db(notebookId);
    final json = jsonEncode({
      'schema': 'onote-page/1',
      'pageId': pageId,
      'page': props.toJson(),
      'blocks': [for (final b in blocks) b.toJson()],
    });
    db.execute('BEGIN');
    try {
      db.execute(
          'INSERT INTO page_mirror(page_id,json,mirror_rev,updated_at) VALUES(?,?,1,?) '
          'ON CONFLICT(page_id) DO UPDATE SET json=excluded.json, '
          'mirror_rev=mirror_rev+1, updated_at=excluded.updated_at',
          [pageId, json, nowMs()]);
      // Placeholder CRDT row keeps the schema honest until onote-core lands.
      db.execute(
          'INSERT INTO page_docs(page_id,snapshot,snapshot_v,updated_at) VALUES(?,?,0,?) '
          'ON CONFLICT(page_id) DO UPDATE SET updated_at=excluded.updated_at',
          [pageId, Uint8List(0), nowMs()]);
      // Maintain blob_refs projection for image blocks.
      db.execute('DELETE FROM blob_refs WHERE page_id=?', [pageId]);
      for (final b in blocks) {
        final hash = b.content['blob'];
        if (hash is String) {
          db.execute(
              'INSERT OR IGNORE INTO blob_refs(page_id,hash) VALUES(?,?)',
              [pageId, hash.replaceFirst('sha256:', '')]);
        }
      }
      // Maintain the refs index (links & embeds) for backlinks (TEXT-8).
      db.execute('DELETE FROM refs WHERE src_page_id=?', [pageId]);
      final linkRe = RegExp(r'\[\[[^\]|]+(?:\|([^\]]+))?\]\]');
      for (final b in blocks) {
        if (b.type == BlockType.text) {
          final txt = b.content['text'] as String? ?? '';
          var idx = 0;
          for (final m in linkRe.allMatches(txt)) {
            final dst = m.group(1);
            if (dst == null) continue;
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
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
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

  void dispose() {
    for (final db in _open.values) {
      db.dispose();
    }
  }
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
