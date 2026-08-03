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
/// The LOGS are deliberately dumb file copies: append-only files plus
/// content-addressed blobs, so copying them is correct by construction. The
/// `.onote` container is not — it is an open WAL database, and a backup asks
/// SQLite itself for a consistent copy rather than copying the file behind its
/// back.
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
/// [containerPath] is the `.onote` beside (or, once a device joins a shared
/// folder, far from) the log directory. A **backup** copies it in; a mirror
/// does not — see below. [snapshot] is how to obtain a *consistent* copy of
/// it (SQLite's own `VACUUM INTO`); a plain file copy is the fallback.
Future<String?> mirrorNotebook(String sourceDir, MirrorTarget target,
    {String? containerPath,
    bool Function(String destPath)? snapshot,
    DateTime? now}) async {
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

  // A BACKUP takes the container too. The `.onote` is a sibling of the log
  // directory, never inside it, so walking the source alone could never pick
  // it up — which meant a "backup" contained no notebook at all, only the logs
  // it would have to be rebuilt from. A snapshot you have to reconstruct
  // before you can read it is not what anyone wants in an emergency.
  //
  // A MIRROR still skips it, on purpose: it is rebuildable, it is the largest
  // file, and it is rewritten on every single save.
  if (target.isBackup && containerPath != null) {
    final container = File(containerPath);
    if (container.existsSync()) {
      final dest = p.join(destPath, p.basename(containerPath));
      // Ask SQLite for the copy when we can. The container is open in WAL
      // mode, so recent commits live in the `-wal` sidecar and a plain file
      // copy can capture a database missing the last several saves — or, mid
      // checkpoint, a torn one. A backup that silently loses a week is worse
      // than no backup, because it is trusted.
      if (snapshot == null || !snapshot(dest)) {
        await container.copy(dest);
      }
    }
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
