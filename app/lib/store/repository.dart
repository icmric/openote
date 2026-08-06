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
import 'notebook_writer.dart';

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
          // `.path`, not the `File` objects. `_workspaceFile` is a getter that
          // returns a NEW `File` each call, and `dart:io`'s File does not
          // override `==` — so comparing the objects was always true, and the
          // "recovered from the backup" note was shown on every single launch,
          // including every successful one. A recovery notice that appears
          // when nothing was recovered is worse than none.
          if (candidate.path != _workspaceFile.path) {
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
            id: m['id'] as String,
            file: file,
            title: m['title'] as String? ?? 'Notebook',
            logDir: m['logDir'] as String?));
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
            logDir: m['logDir'] as String?,
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

  /// The last workspace-write failure, if there has been one.
  ///
  /// Recorded rather than thrown, because the debounced path has nobody to
  /// throw to. `AppState` already surfaces `saveError` for page saves; this is
  /// the registry's equivalent and exists so a swallowed failure is still
  /// *discoverable*.
  Object? lastWorkspaceWriteError;

  /// Put one workspace write on the shared chain.
  ///
  /// **Returns a future that reports failure; leaves behind one that cannot.**
  /// That split is the whole point, and it fixes two distinct faults:
  ///
  /// *A failed write used to poison every later one.* `_writeChain.then(...)`
  /// on an already-errored future skips the callback entirely and
  /// re-propagates the old error for ever — so a single transient failure
  /// (antivirus holding the file, a redirected folder, a full disk) meant
  /// `workspace.json` was never written again for the lifetime of the process,
  /// and every subsequent `createNotebook` / `trashNotebook` threw someone
  /// else's stale exception. `_writeChain` is now the *recovered* future, so
  /// ordering is still guaranteed but failure does not accumulate.
  ///
  /// *A failed write used to escape into nowhere.* The debounced path awaits
  /// nothing, so an error there becomes an unhandled async error — which
  /// `flutter test` charges to whichever test happens to be running when it
  /// lands. That is precisely how a 400 ms registry write racing a temp
  /// directory's teardown produced an intermittent failure in an *unrelated*
  /// test, on the slowest CI runner and only there.
  Future<void> _enqueueWorkspaceWrite() {
    final result = _writeChain.then((_) => _saveWorkspace());
    _writeChain = result.catchError((Object e) {
      lastWorkspaceWriteError = e;
    });
    return result;
  }

  /// Queue an atomic workspace write. Coalesces bursts; returns immediately.
  void _scheduleSaveWorkspace() {
    _writePending = true;
    _writeDebounce?.cancel();
    _writeDebounce = Timer(const Duration(milliseconds: 400), () {
      // `.ignore()` rather than a bare call: it marks the future handled, so a
      // failure is recorded in `lastWorkspaceWriteError` and goes no further.
      // Dropping the future on the floor instead is what made this an
      // unhandled error.
      _enqueueWorkspaceWrite().ignore();
    });
  }

  /// Write any pending workspace state now and wait for it (called on
  /// shutdown, and by any test that is about to delete the directory it lives
  /// in).
  ///
  /// **This one throws**, unlike the debounced path — a caller that asked to
  /// wait has somewhere to put the answer.
  Future<void> flushWorkspace() async {
    _writeDebounce?.cancel();
    if (_writePending) {
      await _enqueueWorkspaceWrite();
      return;
    }
    // Nothing pending: still wait for anything already in flight, but do not
    // resurrect an old failure that `_enqueueWorkspaceWrite` already recorded.
    await _writeChain;
  }

  /// Chain a write and wait for it — for structural changes (notebook created,
  /// renamed, trashed, purged) that must be durable before we report success.
  /// Goes through the same chain as the debounced writes so the two can never
  /// interleave on the file.
  Future<void> _saveNow() {
    _writeDebounce?.cancel();
    _writePending = true;
    return _enqueueWorkspaceWrite();
  }

  Future<void> _saveWorkspace() async {
    if (_disposed) return; // the workspace may no longer exist
    _writePending = false;
    await _writeAtomic(const JsonEncoder.withIndent('  ').convert({
      'format': {'major': 1, 'minor': 0},
      'workspace_id': _workspaceId ??= newId(),
      'notebooks': [
        for (final n in notebooks)
          {
            'id': n.id,
            // Basename for a notebook that lives in the workspace, so the
            // whole folder stays movable — but the FULL path for one that
            // doesn't. `_loadWorkspace` re-joins against the workspace dir, so
            // a basename for a notebook that had been moved into a cloud
            // folder resolved to a file that isn't there, and the notebook
            // silently disappeared from the list on the next start.
            'file': p.isWithin(workspaceDir.path, n.file)
                ? p.basename(n.file)
                : n.file,
            'title': n.title,
            // Always absolute: the shared folder is by definition outside the
            // workspace, so a basename would be meaningless.
            if (n.logDir != null) 'logDir': n.logDir,
          }
      ],
      'trashed': [
        for (final n in trashedNotebooks)
          {
            'id': n.id,
            // Same rules as the live list above. `trashNotebook` moves the
            // very same NotebookRef between the two, so a notebook deleted
            // after being moved to a cloud folder kept its absolute path and
            // was then written as a bare basename — dropped at the next load,
            // unrecoverable, and its file orphaned. The 30-day retention
            // promise quietly became "until you restart".
            'file': p.isWithin(workspaceDir.path, n.file)
                ? p.basename(n.file)
                : n.file,
            'title': n.title,
            if (n.logDir != null) 'logDir': n.logDir,
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
      // Re-checked here, not only at the top of `_saveWorkspace`. Every line
      // above this one is an `await`, and the workspace can be disposed — or,
      // in a test, have its whole directory deleted — during any of them. The
      // top-of-function guard cannot see that; it already ran. Bailing quietly
      // is right because a disposed repository has, by definition, nobody left
      // who wants this file.
      if (_disposed) {
        try {
          if (tmp.existsSync()) await tmp.delete();
        } catch (_) {/* best effort */}
        return;
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

  /// The container-level writer for [notebookId]. Built per call rather than
  /// cached beside `_open`: [NotebookWriter] is a stateless wrapper over the
  /// handle, so a second cache to keep in step would be pure risk.
  NotebookWriter _writer(String notebookId) => NotebookWriter(_db(notebookId));

  /// Write a **consistent** copy of a notebook's container to [destPath].
  ///
  /// Not `File.copy`. The container is open in WAL mode, so recent commits
  /// live in the `-wal` sidecar rather than the main file: copying the file
  /// alone can produce a database missing the last however-many saves, or —
  /// mid-checkpoint — a torn one. `VACUUM INTO` asks SQLite itself to
  /// serialise a complete, self-contained database at a consistent point,
  /// which is exactly what a backup has to be.
  ///
  /// Returns false if it couldn't (locked, out of disk); a backup that failed
  /// must never look like one that worked.
  bool snapshotContainer(String notebookId, String destPath) {
    try {
      final out = File(destPath);
      if (out.existsSync()) out.deleteSync();
      _db(notebookId).execute('VACUUM INTO ?', [destPath]);
      return out.existsSync() && out.lengthSync() > 0;
    } catch (_) {
      return false;
    }
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

    // A notebook this device JOINED already keeps its container locally and
    // shares only the logs, so "move it somewhere else" means moving the log
    // directory — moving the container would drag a private cache into a
    // shared folder and undo the very thing that keeps two devices apart.
    if (ref.logDir != null) {
      final from = Directory(ref.logDirPath);
      if (!from.existsSync()) throw StateError('the shared folder is missing');
      final name = p.basename(from.path);
      final to = Directory(p.join(targetDir, name));
      if (p.equals(from.path, to.path)) return to.path;
      if (to.existsSync()) throw StateError('$name is already in that folder');
      await _copyDirectory(from, to);
      try {
        from.deleteSync(recursive: true);
      } catch (_) {
        // Same reasoning as below: the data has landed, and a stale original
        // is far better than failing after the fact.
      }
      ref.logDir = to.path;
      _scheduleSaveWorkspace();
      return to.path;
    }

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
    _decodedPages.remove(notebookId);

    await src.copy(destFile);
    if (File(destFile).lengthSync() != src.lengthSync()) {
      throw StateError('copy did not complete — the notebook was NOT moved');
    }

    // The log directory travels with the container, or the notebook arrives
    // without the very thing that makes it syncable.
    final srcLog = Directory(ref.logDirPath);
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

  /// Join a notebook that already exists in a shared folder.
  ///
  /// **This device takes its own copy of the container and shares only the
  /// logs**, which is the whole safety argument for folder sync. The `.onote`
  /// is a WAL SQLite database rewritten on every save; two machines writing
  /// one copy of it through a cloud client is precisely the corruption case
  /// ADR-0006 §3 designs against — *"cache.onote ← local-only SQLite; never
  /// synced"*. The op logs are the opposite: append-only, one file per device,
  /// so concurrent writers are structurally impossible.
  ///
  /// So: copy the container into the workspace as a starting point (faster and
  /// safer than replaying the whole log), and point [NotebookRef.logDir] at
  /// the shared `.onotebook`. From then on this device writes its own
  /// container locally and its own op log into the shared folder, and picks up
  /// the other device's ops through the normal pull.
  ///
  /// Joining twice is a no-op that returns the existing entry, matched on the
  /// shared log directory rather than the path, so a second click can't fork
  /// the registry into two devices for one machine.
  Future<NotebookRef> openExistingNotebook(String path, {String? title}) async {
    final file = File(path);
    if (!file.existsSync()) throw StateError('no notebook at $path');
    final sharedLog = '${p.withoutExtension(path)}.onotebook';

    bool sameNotebook(NotebookRef n) =>
        p.equals(n.file, path) ||
        (n.logDir != null && p.equals(n.logDir!, sharedLog));

    final already = notebooks.where(sameNotebook).firstOrNull;
    if (already != null) return already;

    // The recycle bin counts. Joining a notebook you had deleted used to skip
    // this check entirely and copy the container again under a fresh id —
    // which is how a workspace ends up holding five ~95MB copies of one
    // notebook, each with its own review history and favourites. Restoring
    // the entry you already have is both cheaper and what the user meant.
    final trashed = trashedNotebooks.where(sameNotebook).firstOrNull;
    if (trashed != null) {
      await restoreNotebook(trashed.id);
      return trashed;
    }

    final name = title ?? p.basenameWithoutExtension(path);
    final local = _freeNotebookPath(name);
    await file.copy(local);
    if (File(local).lengthSync() != file.lengthSync()) {
      throw StateError('could not copy the notebook into this workspace');
    }

    final id = newId();
    final ref =
        NotebookRef(id: id, file: local, title: name, logDir: sharedLog);
    notebooks.add(ref);
    _open[id] = openOnote(local, notebookId: id, title: name);
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
    _decodedPages.remove(id);
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

  /// Permanently delete a trashed notebook: its container AND its op logs.
  ///
  /// The log directory used to be left behind — purge deleted `ref.file` and
  /// nothing else — so every emptied notebook stranded its `.onotebook`
  /// (logs, and every blob it ever held) somewhere the app would never look
  /// again. On a synced notebook that is hundreds of megabytes of the user's
  /// cloud quota, permanently, with no way to find it except by hand.
  ///
  /// The one thing it must never do is delete a log directory another
  /// notebook still writes to: a device that joined a shared folder points
  /// its `logDir` there while keeping a private container, so two entries can
  /// legitimately name the same logs.
  Future<void> purgeNotebook(String id) async {
    final i = trashedNotebooks.indexWhere((n) => n.id == id);
    if (i < 0) return;
    final ref = trashedNotebooks.removeAt(i);
    _open.remove(id)?.dispose();
    _decodedPages.remove(id);
    try {
      final f = File(ref.file);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {/* best-effort; the workspace entry is already gone */}
    try {
      final logs = Directory(ref.logDirPath);
      if (logs.existsSync() && !_logDirIsShared(ref)) {
        logs.deleteSync(recursive: true);
      }
    } catch (_) {/* a lock or a permission must not fail the purge */}
    await _saveNow();
  }

  /// Does any OTHER registry entry (live or trashed) use this notebook's log
  /// directory? Shared logs belong to whoever is still using them.
  bool _logDirIsShared(NotebookRef ref) {
    final mine = ref.logDirPath;
    for (final n in [...notebooks, ...trashedNotebooks]) {
      if (n.id == ref.id) continue;
      if (p.equals(n.logDirPath, mine)) return true;
    }
    return false;
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

  List<TreeNode> loadNodes(String notebookId) =>
      _writer(notebookId).loadNodes();

  TreeNode upsertNode(String notebookId, TreeNode n) =>
      _writer(notebookId).upsertNode(n);

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
    _writer(notebookId).purgeNode(nodeId);
    // A purged page must not survive in the decoded cache: a page recreated
    // later under the same id (a restore, a sync replay) would read as its
    // dead predecessor.
    _decodedPages[notebookId]?.remove(nodeId);
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
    return _decodePage(rows.first['json'] as String);
  }

  static PageData _decodePage(String json) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    return PageData(
      [
        for (final b in (j['blocks'] as List? ?? const []))
          Block.fromJson((b as Map).cast<String, dynamic>())
      ],
      PageProps.fromJson((j['page'] as Map?)?.cast<String, dynamic>()),
    );
  }

  // ── Read-only page access for the summary surfaces ────────────────────
  //
  // The tags rollup, the planner's agenda and the flashcard deck all derive
  // from "every tagged line in the notebook". Deriving that by decoding every
  // page's JSON on the UI thread is what made opening the study tab on a big
  // imported notebook a multi-second freeze — reported directly: "opening the
  // tab is very slow… there has to be a more efficient way".
  //
  // Two layers fix it without introducing a maintained index that could
  // drift (the reasoning at `allTags` still holds — one source of truth):
  //
  //  1. **A SQL prefilter.** Tags live in block content as a `"tags"` key, so
  //     `json LIKE '%"tags":%'` finds every page that could possibly matter —
  //     inside SQLite, in C, without decoding anything. False positives (a
  //     page whose *text* contains the literal string) merely get decoded and
  //     contribute nothing; false negatives are impossible because
  //     `NoteTag.writeInto` writes exactly that key. Most pages carry no tags,
  //     so this alone cuts the work by an order of magnitude.
  //  2. **A decoded-page cache**, invalidated per page on write. `docRevision`
  //     bumps on ANY page save, so the callers' own memos rebuild from scratch
  //     after every keystroke-debounce — with this cache a rebuild re-decodes
  //     only the pages that actually changed.

  final Map<String, Map<String, PageData>> _decodedPages = {};
  static const _decodedPagesMax = 600;

  /// [readPage], through the cache. **The result is shared and must be
  /// treated as read-only** — mutating a block from it would corrupt what
  /// every later caller sees. Editors go through [readPage], which hands out
  /// fresh objects.
  PageData readPageShared(String notebookId, String pageId) {
    final perNb = _decodedPages.putIfAbsent(notebookId, () => {});
    final hit = perNb[pageId];
    if (hit != null) return hit;
    if (perNb.length >= _decodedPagesMax) perNb.clear();
    return perNb[pageId] = readPage(notebookId, pageId);
  }

  /// Ids of pages whose stored JSON can contain tags, cheaply.
  List<String> pageIdsWithTags(String notebookId) => [
        for (final r in _db(notebookId).select(
            'SELECT page_id FROM page_mirror WHERE json LIKE ?',
            const ['%"tags":%']))
          r['page_id'] as String
      ];

  /// Every block id in [notebookId], from the raw JSON, without decoding it.
  ///
  /// `jsonEncode` writes a block's identity as exactly `"id":"<uuid>"`, so a
  /// string scan recovers all of them at a fraction of the cost of
  /// materialising every page. It can also pick up a lookalike from note
  /// *text* — accepted, because the one consumer (card-state pruning) treats
  /// membership as "do not prune", where an extra id is harmless and a missing
  /// one destroys review history.
  Set<String> allBlockIds(String notebookId) {
    final out = <String>{};
    for (final r in _db(notebookId).select('SELECT json FROM page_mirror')) {
      for (final m in _blockIdRe.allMatches(r['json'] as String)) {
        out.add(m.group(1)!);
      }
    }
    return out;
  }

  static final _blockIdRe = RegExp(r'"id":"([0-9a-f-]{36})"');

  /// Run [fn] in ONE transaction on [notebookId]'s database. [writePage] uses
  /// savepoints so it nests; imports batch hundreds of page writes into a
  /// single commit instead of paying per-page transaction overhead.
  T runInTransaction<T>(String notebookId, T Function() fn) =>
      _writer(notebookId).runInTransaction(fn);

  void writePage(
      String notebookId, String pageId, List<Block> blocks, PageProps props) {
    // The write is the single funnel every page change goes through — saves,
    // imports, sync pulls, restores — so evicting here is what makes the
    // shared decoded-page cache above trustworthy.
    _decodedPages[notebookId]?.remove(pageId);
    _writer(notebookId).writePage(pageId, blocks, props);
  }

  // ── Blobs (content-addressed) ──────────────────────────────────────────

  String putBlob(String notebookId, Uint8List bytes, String mime) =>
      _writer(notebookId).putBlob(bytes, mime);

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
        final content = (b as Map)['content'] as Map?;
        // `sourceText` is an imported PDF slide's hidden text layer, so a
        // lecture deck is findable by its words even though the page shows a
        // picture (see export/pdf_import.dart).
        final text = content?['text'] ?? content?['sourceText'];
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
