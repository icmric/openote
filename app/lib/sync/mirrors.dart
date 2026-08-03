/// Mirrors and backups: keeping a second copy of a notebook somewhere else.
///
/// **Mirror vs sync — the distinction that matters.** A *sync* folder is where
/// the notebook lives; other devices write their own logs into it and the
/// merge is two-way. A *mirror* is one-way and passive: after every save we
/// copy the notebook out to another location, and nothing is ever read back.
/// That makes a mirror safe to point anywhere — a second cloud provider, a
/// USB stick, a NAS — without any risk of two writers, because the mirror is
/// never a source.
///
/// A **backup** is a mirror with history: instead of overwriting one copy it
/// writes a timestamped snapshot and prunes old ones. Same one-way property.
///
/// Both are deliberately dumb file copies. A notebook is a directory of
/// append-only logs plus content-addressed blobs, so copying it is correct by
/// construction — there is no database to quiesce and no index to rebuild.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// A configured destination for one notebook.
class MirrorTarget {
  const MirrorTarget({
    required this.path,
    required this.keepVersions,
    this.label,
  });

  /// Directory to copy into. The notebook lands in a subdirectory named after
  /// itself, so one target can hold several notebooks.
  final String path;

  /// 0 = plain mirror (one copy, overwritten).
  /// >0 = backup: keep this many timestamped snapshots, oldest pruned first.
  final int keepVersions;

  final String? label;

  bool get isBackup => keepVersions > 0;

  Map<String, dynamic> toJson() => {
        'path': path,
        'keep': keepVersions,
        if (label != null) 'label': label,
      };

  static MirrorTarget? fromJson(Object? j) {
    if (j is! Map) return null;
    final path = j['path'];
    if (path is! String || path.isEmpty) return null;
    return MirrorTarget(
      path: path,
      keepVersions: (j['keep'] as num?)?.toInt() ?? 0,
      label: j['label'] as String?,
    );
  }
}

/// Copy [sourceDir] (a `.onotebook`) into [target].
///
/// Returns the directory written, or null if the source is missing.
///
/// Copies **newer-or-missing files only**. A notebook's logs are append-only
/// and its blobs are content-addressed and immutable, so an unchanged file is
/// byte-identical and re-copying it is pure waste — on a notebook with 372
/// images that is the difference between a mirror that runs in milliseconds
/// and one that stalls the app.
Future<String?> mirrorNotebook(String sourceDir, MirrorTarget target,
    {DateTime? now}) async {
  final src = Directory(sourceDir);
  if (!src.existsSync()) return null;
  final name = p.basename(sourceDir);

  final destPath = target.isBackup
      ? p.join(target.path, name, _stamp(now ?? DateTime.now()))
      : p.join(target.path, name);
  final dest = Directory(destPath);
  await dest.create(recursive: true);

  await for (final entity in src.list(recursive: true, followLinks: false)) {
    final rel = p.relative(entity.path, from: sourceDir);
    final outPath = p.join(destPath, rel);
    if (entity is Directory) {
      await Directory(outPath).create(recursive: true);
      continue;
    }
    if (entity is! File) continue;
    // Skip the local-only cache: it is rebuildable from the logs, it is the
    // largest file in the notebook, and it is the one file that is rewritten
    // on every single save.
    if (p.extension(entity.path) == '.onote' && !target.isBackup) continue;
    final outFile = File(outPath);
    if (!target.isBackup && outFile.existsSync()) {
      final srcStat = entity.statSync();
      final dstStat = outFile.statSync();
      if (dstStat.modified.isAfter(srcStat.modified) &&
          dstStat.size == srcStat.size) {
        continue;
      }
    }
    await Directory(p.dirname(outPath)).create(recursive: true);
    await entity.copy(outPath);
  }

  if (target.isBackup) await _prune(p.join(target.path, name), target.keepVersions);
  return destPath;
}

/// `2026-08-03_141530` — sorts lexicographically, which is what makes pruning
/// a sort-and-drop rather than a date parse.
String _stamp(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)}_'
      '${two(t.hour)}${two(t.minute)}${two(t.second)}';
}

/// Keep the newest [keep] snapshots under [dir].
Future<void> _prune(String dir, int keep) async {
  final root = Directory(dir);
  if (!root.existsSync()) return;
  final snaps = root
      .listSync()
      .whereType<Directory>()
      .map((d) => d.path)
      .toList()
    ..sort();
  if (snaps.length <= keep) return;
  for (final old in snaps.take(snaps.length - keep)) {
    try {
      await Directory(old).delete(recursive: true);
    } catch (_) {
      // A snapshot we can't delete (open in Explorer, permission) must not
      // fail the backup that just succeeded.
    }
  }
}
