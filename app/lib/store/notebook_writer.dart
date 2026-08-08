/// Everything that writes into ONE `.onote` container, against a bare
/// [Database] handle.
///
/// **Why this is not simply part of `Repository`.** Repository owns a
/// *workspace*: the registry, the trash, file watchers, the decoded-page cache,
/// the debounced `workspace.json` write. None of that is meaningful to the
/// import writer isolate, which owns exactly one brand-new notebook file that
/// nothing else has open — and which could not have a Repository anyway, since
/// a spawned isolate has no `path_provider` and no business touching the user's
/// registry.
///
/// The alternative was to reimplement these writes inside the isolate. That
/// would have duplicated `writePage`'s `blob_refs` and `refs` projections — the
/// two pieces of maintained state whose drift is silent, and whose repair (per
/// ADR-0007) is a full rescan. One implementation, two owners: Repository holds
/// one of these per open notebook and layers its caches on top; the writer
/// isolate constructs one directly.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import '../ink/ink_storage.dart';
import '../model/models.dart';

class NotebookWriter {
  NotebookWriter(this.db);

  /// The container. Owned by whoever constructed this — [NotebookWriter] never
  /// opens or closes it, because the two owners disagree about lifetime
  /// (Repository pools handles for the session; the isolate opens one and
  /// exits).
  final Database db;

  List<TreeNode> loadNodes() {
    final rows = db.select(
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

  TreeNode upsertNode(TreeNode n) {
    n.updatedAt = nowMs();
    db.execute(
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
        n.parentId,
        n.title,
        n.position,
        n.color,
        n.level,
        n.createdAt,
        n.updatedAt,
      ],
    );
    return n;
  }

  /// Hard-delete one node. Callers that hold caches keyed by node id must
  /// evict alongside this — a page recreated later under the same id (a
  /// restore, a sync replay) would otherwise read as its dead predecessor.
  void purgeNode(String nodeId) =>
      db.execute('DELETE FROM nodes WHERE id=?', [nodeId]);

  T runInTransaction<T>(T Function() fn) {
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

  /// The single funnel every page change goes through — saves, imports, sync
  /// pulls, restores. Callers holding a decoded-page cache evict here.
  void writePage(String pageId, List<Block> blocks, PageProps props) {
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
      //
      // **Only for blobs this container actually holds**, hence the SELECT
      // rather than VALUES. `blob_refs.hash` is a foreign key onto `blobs`, and
      // a page referencing bytes we do not have is a legitimate, ordinary
      // state: a cloud client copies the op log and the content-addressed blob
      // files independently, so the reference routinely lands first. With a
      // plain INSERT that raised a constraint violation *inside the sync
      // pull's transaction* — so one shared notebook with one image in it
      // stopped that device syncing at all, and not merely for the page with
      // the picture.
      //
      // Under-recording is safe here in a way that over-recording would not
      // be: this table is a projection of "which stored blobs does this page
      // reach", and a blob we do not store cannot be reached. Garbage
      // collection deliberately does not trust it either — ADR-0007 chose
      // recompute-by-scanning precisely because one missed mutation path in a
      // maintained count silently deletes someone's content.
      db.execute('DELETE FROM blob_refs WHERE page_id=?', [pageId]);
      for (final b in blocks) {
        final hash = b.content['blob'];
        if (hash is String) {
          db.execute(
              'INSERT OR IGNORE INTO blob_refs(page_id,hash) '
              'SELECT ?, hash FROM blobs WHERE hash=?',
              [pageId, hash.replaceFirst('sha256:', '')]);
        }
        // Ink now lives in blobs too, and a page that does not declare its
        // handwriting here is a page whose handwriting a scanning garbage
        // collector cannot see. ADR-0007's GC recomputes what is reachable, so
        // a missing row would collect the entire notebook's ink.
        for (final ref in InkStorage.refsOf(b.content)) {
          db.execute(
              'INSERT OR IGNORE INTO blob_refs(page_id,hash) '
              'SELECT ?, hash FROM blobs WHERE hash=?',
              [pageId, ref.replaceFirst('sha256:', '')]);
        }
        final text = b.content['text'];
        if (text is String && text.contains('](sha256:')) {
          for (final m in _inlineImgRe.allMatches(text)) {
            db.execute(
                'INSERT OR IGNORE INTO blob_refs(page_id,hash) '
                'SELECT ?, hash FROM blobs WHERE hash=?',
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
              dst = db.select(
                  "SELECT id FROM nodes WHERE kind='page' "
                  'AND deleted_at IS NULL AND lower(trim(title))=? LIMIT 1',
                  [label]).firstOrNull?['id'] as String?;
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

  String putBlob(Uint8List bytes, String mime) {
    final hash = sha256Hex(bytes);
    db.execute(
        'INSERT OR IGNORE INTO blobs(hash,bytes,mime,size,created_at) VALUES(?,?,?,?,?)',
        [hash, bytes, mime, bytes.length, nowMs()]);
    return hash;
  }
}

/// SHA-256 (FIPS 180-4), vendored rather than taking a dependency on
/// `package:crypto` for one function. This is the notebook's content-addressing
/// primitive: the same bytes must produce the same name on every device, which
/// is what lets blobs skip merging entirely (ADR-0006 §3).
String sha256Hex(Uint8List data) => _Sha256.hex(data);

/// Compact SHA-256 (FIPS 180-4). Vendored to avoid an extra dependency;
/// replace with package:crypto if preferred.
class _Sha256 {
  static const _k = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];

  static String hex(Uint8List data) {
    final h = [
      0x6a09e667,
      0xbb67ae85,
      0x3c6ef372,
      0xa54ff53a,
      0x510e527f,
      0x9b05688c,
      0x1f83d9ab,
      0x5be0cd19,
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
        hh = g;
        g = f;
        f = e;
        e = (d + t1) & 0xffffffff;
        d = c;
        c = b;
        b = a;
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
