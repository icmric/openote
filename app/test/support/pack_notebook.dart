// Pack a notebook into one `.onote` that carries its own handwriting and
// pictures — for the browser demo, which has no folder beside it.
//
// Since v0.17 Step 6 a notebook's blobs live in `<name>.onotebook/blobs/`, not
// in the container, so a container on its own arrives with references to
// nothing. That is how the demo lost all eight of its drawings
// (docs/planning/v1.0.2.md §12). The browser reads a blob from the container's
// own `blobs` table when there is no folder (`Repository.getBlob`), so a
// container with those rows put back is complete there.
//
// The same operation as `Repository.refillContainerBlobs`, applied to a COPY:
// the notebook being packed is never opened for writing, and the live one in
// your workspace keeps its blobs in the folder where they belong.
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:openote/store/notebook_writer.dart' show sha256Hex;
import 'package:openote/store/repository.dart' show Repository;
import 'package:openote/sync/op_log.dart' show OpLogStore;

class PackResult {
  PackResult({
    required this.packed,
    required this.alreadyInside,
    required this.missing,
    required this.binned,
    required this.bytes,
  });

  /// Blobs copied in from the folder.
  final int packed;

  /// Blobs the container already held.
  final int alreadyInside;

  /// Hashes a page refers to that could not be found, or whose file is not
  /// what its name says. Nothing is written while this is non-empty.
  final Set<String> missing;

  /// What is in the notebook's recycle bin — deleted pages and sections by
  /// title, and deleted blocks by kind — which would ship with it.
  final List<String> binned;

  /// Size of the packed container, or 0 when nothing was written.
  final int bytes;

  bool get ok => missing.isEmpty;
}

/// Pack [fromOnote] into [toOnote], taking blobs from [notebookFolder] — the
/// `.onotebook` directory, by default the one beside the container.
///
/// Refuses, and writes nothing, if any referenced blob is missing or damaged:
/// a demo that looks complete and is not is the failure this exists to stop.
/// The result is checked after it is written — every reference resolves to
/// bytes that hash to their name, and SQLite's own integrity check passes —
/// and only then moved over [toOnote].
PackResult packNotebook({
  required String fromOnote,
  String? notebookFolder,
  required String toOnote,
}) {
  final from = File(fromOnote);
  if (!from.existsSync()) throw StateError('no notebook at $fromOnote');
  final blobs = OpLogStore.forNotebook(fromOnote, logDir: notebookFolder);

  // Work on a copy, with its write-ahead log if there is one, so a save not
  // yet folded into the main file is not lost — and so the original is never
  // opened for writing at all.
  final work = Directory.systemTemp.createTempSync('onote_pack_');
  try {
    final copy = p.join(work.path, 'work.onote');
    from.copySync(copy);
    for (final side in ['-wal', '-shm']) {
      final f = File('$fromOnote$side');
      if (f.existsSync()) f.copySync('$copy$side');
    }

    final db = sqlite3.open(copy);
    final String packedPath;
    final List<String> binned;
    var packed = 0, alreadyInside = 0;
    final missing = <String>{};
    try {
      String bare(Object? h) => '$h'.replaceFirst('sha256:', '');
      final wanted = {
        for (final r in db.select('SELECT DISTINCT hash FROM blob_refs'))
          bare(r['hash'])
      };
      final have = {
        for (final r in db.select('SELECT hash FROM blobs')) bare(r['hash'])
      };
      final toAdd = <String, Uint8List>{};
      for (final hash in wanted) {
        if (have.contains(hash)) {
          alreadyInside++;
          continue;
        }
        final bytes = blobs.readBlob(hash);
        // Never pack bytes that are not what their name says.
        if (bytes == null || sha256Hex(bytes) != hash) {
          missing.add(hash);
        } else {
          toAdd[hash] = bytes;
        }
      }
      binned = _recycleBin(db);
      if (missing.isNotEmpty) {
        return PackResult(
            packed: 0,
            alreadyInside: alreadyInside,
            missing: missing,
            binned: binned,
            bytes: 0);
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final e in toAdd.entries) {
        db.execute(
            'INSERT OR IGNORE INTO blobs(hash,bytes,mime,size,created_at) '
            'VALUES(?,?,?,?,?)',
            [e.key, e.value, Repository.sniffMime(e.value), e.value.length, now]);
        packed++;
      }
      // One file, at a consistent point: no -wal or -shm to forget.
      packedPath = p.join(work.path, 'packed.onote');
      db.execute('VACUUM INTO ?', [packedPath]);
    } finally {
      db.dispose();
    }

    _verify(packedPath);
    final out = File(toOnote);
    out.parent.createSync(recursive: true);
    File(packedPath).copySync(toOnote);
    return PackResult(
        packed: packed,
        alreadyInside: alreadyInside,
        missing: const {},
        binned: binned,
        bytes: out.lengthSync());
  } finally {
    try {
      work.deleteSync(recursive: true);
    } catch (_) {}
  }
}

/// Every reference resolves inside the file, to bytes that hash to their name.
void _verify(String path) {
  final db = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    final check = db.select('PRAGMA integrity_check').first.values.first;
    if (check != 'ok') throw StateError('packed file failed integrity: $check');
    for (final r in db.select('SELECT DISTINCT hash FROM blob_refs')) {
      final hash = '${r['hash']}'.replaceFirst('sha256:', '');
      final row = db.select('SELECT bytes FROM blobs WHERE hash = ?', [hash]);
      if (row.isEmpty || sha256Hex(row.first['bytes'] as Uint8List) != hash) {
        throw StateError('packed file is missing $hash');
      }
    }
  } finally {
    db.dispose();
  }
}

/// What a visitor would find in the recycle bin.
List<String> _recycleBin(Database db) => [
      for (final r in db.select(
          "SELECT kind, title FROM nodes WHERE deleted_at IS NOT NULL"))
        '${r['kind']} "${r['title']}"',
      for (final r in db.select('SELECT kind, what FROM recent_deletions'))
        'deleted ${r['kind']}: ${r['what']}',
    ];
