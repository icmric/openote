import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../core/ids.dart';
import '../core/open_target.dart' show workingCopyFileName;
import '../ink/ink_codec.dart' show inkMimeType;
import '../ink/ink_storage.dart';
import '../model/history.dart';
import '../model/models.dart';
import '../sync/device_identity.dart';
import '../sync/materializer.dart';
import '../sync/op.dart' show Op, canonicalJson;
import '../sync/op_log.dart';
import 'database.dart';
import 'free_space.dart';
import 'history_store.dart';
import 'notebook_writer.dart';

/// The `workspace.json` layout this build writes and understands (spec §7's
/// `format.major`).
///
/// **Why this number is now read and not merely written.** [_loadWorkspace]
/// skips any registry entry whose file is not there
/// (`if (File(file).existsSync())`), and [_saveWorkspace] then rewrites the
/// whole registry from whatever survived. So a student who upgrades the laptop
/// in October and the desktop at Christmas opens the old build on a migrated
/// workspace, sees an empty sidebar, creates one notebook — and *permanently
/// prunes all the others*. Nothing on disk was corrupt; the old build simply
/// wrote down what it could see.
///
/// This is the only mechanical guard against that, and it has to be shipped
/// and baked **before** any release moves a container (v0.17 plan, Step 8),
/// which is why it lands first with nothing yet depending on it.
///
/// **2 as of Step 8's migration, and what makes it necessary is one line of the
/// OLD build.** `_saveWorkspace` writes `p.basename(n.file)` for a notebook
/// inside the workspace; a demoted notebook's file is
/// `.cache/<id>/cache.onote`, and a build that predates this one would write it
/// back as the bare `cache.onote` and then look for it at the workspace root on
/// the next start, find nothing, and prune the entry. Every migrated notebook,
/// silently, on one launch of an old build. Reading this number is what stops
/// it: the old build sees a format it does not understand, loads the registry
/// read-only, and never rewrites it.
const int workspaceFormat = 2;

/// What a `VACUUM` did — **and whether it happened at all**.
///
/// A plain `int` could not say the second thing, which is v0.17 Step 7 item 5:
/// a compaction that failed on a full disk returned 0, the same as a notebook
/// with nothing to give back, and the button said *"Nothing to reclaim"* for
/// both.
class SpaceReclaim {
  const SpaceReclaim({required this.freed, this.problem, this.details});

  /// Bytes the container plus its write-ahead log gave back.
  final int freed;

  /// Plain words for why nothing ran, or null when it did. Never an exception.
  final String? problem;

  /// The exception, for the Advanced fold.
  final String? details;

  bool get ran => problem == null;
}

/// What emptying a container's `blobs` table did — or, far more often, the
/// reason it refused to.
///
/// Refusal is the normal outcome and is not an error: every gate exists because
/// something without it destroyed real data, so a `refusal` is the machinery
/// working. Only [details] may contain a path, a hash or an exception; the
/// [refusal] sentence itself is what a year 10 student reads.
class BlobReclaim {
  const BlobReclaim({
    this.done = false,
    this.rowsRemoved = 0,
    this.checked = 0,
    this.freed = 0,
    this.beforeBytes = 0,
    this.afterBytes = 0,
    this.refusal,
    this.details,
  });

  /// True only when the rows really are gone and the file really did shrink.
  final bool done;

  /// Rows removed from `blobs`.
  final int rowsRemoved;

  /// Blob files re-hashed by the gates. Not files seen — the number that
  /// separates this from a directory listing.
  final int checked;

  final int freed;
  final int beforeBytes;
  final int afterBytes;

  /// Why nothing was done, in plain words. Null when [done].
  final String? refusal;

  /// Hashes, counts and exceptions, for "Details (advanced)".
  final String? details;

  @override
  String toString() => done
      ? 'removed $rowsRemoved row(s), checked $checked blob file(s), '
          '$beforeBytes → $afterBytes bytes'
      : 'refused: $refusal';
}

/// What putting the container's copies back achieved (Step 7's inverse).
class BlobRefill {
  const BlobRefill({required this.restored, required this.missing});

  /// Rows written back into `blobs`.
  final int restored;

  /// Hashes `blob_refs` names that `blobs/` could not supply — no file, or a
  /// file whose bytes are not what its name says. A non-empty set here means
  /// the rollback is incomplete and the user must be told, not a number to be
  /// rounded off.
  final Set<String> missing;

  bool get ok => missing.isEmpty;

  @override
  String toString() => 'restored $restored, could not restore ${missing.length}';
}

/// What rebuilding a container out of its own op log did — or why it refused.
///
/// Same shape and the same reasoning as [BlobReclaim]: refusal is the normal
/// outcome, it is not an error, and only [details] may carry a path, an id or
/// an exception. [refusal] is the sentence a year 10 student reads.
class ContainerRebuild {
  const ContainerRebuild({
    this.done = false,
    this.ops = 0,
    this.nodes = 0,
    this.pages = 0,
    this.blobsChecked = 0,
    this.droppedNodes = 0,
    this.refusal,
    this.details,
  });

  /// True only when the replacement is verified and in place.
  final bool done;

  /// Ops replayed — **every device's, including this one's**, which is the
  /// whole point of this call existing.
  final int ops;

  final int nodes;
  final int pages;

  /// Blob files re-hashed before the swap. Not files seen: the number that
  /// separates this from a directory listing.
  final int blobsChecked;

  /// Nodes the log still lists under a parent that was purged. The container
  /// cascades a purge to the whole subtree and [Materializer] does not, so
  /// these are rows the container had already removed.
  final int droppedNodes;

  final String? refusal;
  final String? details;

  @override
  String toString() => done
      ? 'rebuilt from $ops op(s): $nodes node(s), $pages page(s), '
          '$blobsChecked blob file(s) checked, $droppedNodes node(s) dropped'
      : 'refused: $refusal';
}

/// What changing how a notebook is stored did — or why it refused
/// (v0.17 Step 8, both directions).
///
/// Same shape and the same reasoning as [BlobReclaim] and [ContainerRebuild]:
/// refusal is a normal outcome rather than an error, [refusal] is the sentence a
/// year 10 student reads, and only [details] may carry a path or an exception.
class ContainerDemotion {
  const ContainerDemotion({
    this.done = false,
    this.from,
    this.to,
    this.snapshotsDropped = 0,
    this.blobsRestored = 0,
    this.bytes = 0,
    this.refusal,
    this.details,
  });

  /// True only when the move is complete and recorded in the registry.
  final bool done;

  final String? from;
  final String? to;

  /// `page_versions` rows destroyed. The one part of this no inverse can undo,
  /// counted so the app can say how much rather than merely that it happened.
  final int snapshotsDropped;

  /// Pictures put back into the container's own table by the inverse, so an
  /// older Openote can render them.
  final int blobsRestored;

  /// The result file's size, for the sentence that reports it.
  final int bytes;

  final String? refusal;
  final String? details;

  @override
  String toString() => done
      ? 'moved to $to ($bytes B; $snapshotsDropped snapshot(s) dropped, '
          '$blobsRestored picture(s) restored)'
      : 'refused: $refusal';
}

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
    final dir = await resolveWorkspaceDir();
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
  ///
  /// Public because `main()` needs the answer *before* it opens anything: the
  /// single-instance lock lives in this folder, and a second Openote has to
  /// find it and step aside before it paints a window (see
  /// `core/single_instance.dart`).
  static Future<Directory> resolveWorkspaceDir() async {
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

  /// Non-null when `workspace.json` was written by a newer Openote than this
  /// one, in which case this build reads the registry and **never rewrites
  /// it** — see [workspaceFormat] for the notebook-pruning disaster that
  /// prevents.
  ///
  /// Two fields for the same reason `OpenNotebookResult` has two: `message` is
  /// plain sentences safe to put in front of anybody, `details` is the version
  /// numbers, which belong behind an Advanced fold and nowhere else.
  ({String message, String details})? registryReadOnly;

  /// The registry's layout number, tolerant of every shape this file has had.
  ///
  /// Before the guard existed the field was written — and documented in spec
  /// §7 — as `{"major": 1, "minor": 0}`, and that is what every workspace on
  /// disk today still carries. A bare integer is accepted too so that a future
  /// build which flattens the field is still guarded by this one. **An
  /// unrecognised shape means "written by a build that predates the guard",
  /// which is by definition not newer than us**: guessing "newer" there would
  /// lock every existing user out of their own notebook list, which is the
  /// exact harm the guard exists to prevent.
  static int _formatOf(Map<String, dynamic> j) {
    final f = j['format'];
    if (f is num) return f.toInt();
    if (f is Map && f['major'] is num) return (f['major'] as num).toInt();
    return workspaceFormat;
  }

  Future<void> _loadWorkspace() async {
    // One call site, and it is here rather than in the two `open*` factories so
    // that the production path and the test path cannot drift: a marker cleared
    // only in `openAt` would be proved by the suite and broken in the app.
    _clearStaleReclaimMarker();
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
    final found = _formatOf(j);
    if (found > workspaceFormat) {
      // Load everything below as usual — the entries this build CAN see are
      // still real notebooks and the user should be able to open them. What it
      // must not do is write the list back.
      registryReadOnly = (
        message: 'This list of notebooks was last used by a newer version of '
            'Openote, so Openote is only reading it, not changing it. '
            'Notebooks you add, rename or delete now will be forgotten when '
            'you next start up.\n\n'
            'Updating Openote to the latest version fixes this. Nothing '
            'already in the list can be lost in the meantime.',
        details: 'workspace.json is format $found; this build writes and '
            'understands format $workspaceFormat.',
      );
    }
    _settings = (j['settings'] as Map?)?.cast<String, dynamic>() ?? {};
    for (final n in (j['notebooks'] as List? ?? const [])) {
      final m = (n as Map).cast<String, dynamic>();
      // `p.join` with a RELATIVE path, which is what `_registryPath` writes: for
      // a notebook sitting directly in the workspace that is still the bare
      // basename every registry on disk holds today, and for a migrated one it
      // is `.cache/<id>/cache.onote`. An absolute path wins outright, which is
      // how a notebook moved into a cloud folder resolves.
      final id = m['id'] as String;
      final logDir = m['logDir'] as String?;
      // BOTH settles run before the `existsSync` filter below, and that ordering
      // is the whole point of them: the filter drops an entry whose file is
      // missing and `_saveWorkspace` then rewrites the registry from what
      // survived, so a kill inside either swap window would prune the notebook
      // permanently.
      final file = _settleDemotion(
          id, p.join(workspaceDir.path, m['file'] as String), logDir);
      _settleInterruptedRebuild(file);
      if (File(file).existsSync()) {
        notebooks.add(NotebookRef(
            id: id,
            file: file,
            title: m['title'] as String? ?? 'Notebook',
            logDir: logDir));
      }
    }
    for (final n in (j['trashed'] as List? ?? const [])) {
      final m = (n as Map).cast<String, dynamic>();
      final id = m['id'] as String;
      final logDir = m['logDir'] as String?;
      final file = _settleDemotion(
          id, p.join(workspaceDir.path, m['file'] as String), logDir);
      _settleInterruptedRebuild(file);
      if (File(file).existsSync()) {
        trashedNotebooks.add(NotebookRef(
            id: id,
            file: file,
            title: m['title'] as String? ?? 'Notebook',
            logDir: logDir,
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

  /// Drop a pending debounced workspace write without performing it.
  ///
  /// For `AppState.cancelPendingSave` — a widget test that navigates arms the
  /// 400 ms debounce inside testWidgets' fake-async zone, where the write's
  /// file I/O could never complete and the armed timer fails the framework's
  /// own no-pending-timers invariant. `_writePending` is left true, so a later
  /// [flushWorkspace] still writes everything that was owed.
  void cancelPendingWorkspaceWrite() => _writeDebounce?.cancel();

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

  /// Write the registry NOW and bring the `.bak` copy in line with it.
  ///
  /// For a caller that has just REMOVED a secret from the settings (the
  /// clear-text GitHub token scrub, task #73). The ordinary atomic write
  /// keeps the PREVIOUS file as `workspace.json.bak` — which, right after a
  /// scrub, is precisely the copy still carrying the secret. Copying the
  /// freshly written file over the backup keeps the recovery path intact and
  /// leaves the secret in no file this class writes.
  Future<void> flushSettingsScrub() async {
    await _saveNow();
    // A read-only registry (written by a newer build) is never rewritten, so
    // nothing was scrubbed and the backup must not be touched either.
    if (registryReadOnly != null || _disposed) return;
    try {
      final target = _workspaceFile;
      if (target.existsSync()) await target.copy('${target.path}.bak');
    } catch (_) {
      // The live registry is already clean; a backup that could not be
      // refreshed is replaced by the next routine write anyway.
    }
  }

  Future<void> _saveWorkspace() async {
    if (_disposed) return; // the workspace may no longer exist
    _writePending = false;
    // A registry written by a newer build is read, never rewritten. Rewriting
    // it from what THIS build managed to load is the pruning disaster
    // [workspaceFormat] documents, and it is one `createNotebook` away. Silent
    // here on purpose: the message is already on screen, via
    // `AppState.saveError`.
    if (registryReadOnly != null) return;
    await _writeAtomic(const JsonEncoder.withIndent('  ').convert({
      'format': {'major': _formatToWrite, 'minor': 0},
      'workspace_id': _workspaceId ??= newId(),
      'notebooks': [
        for (final n in notebooks)
          {
            'id': n.id,
            'file': _registryPath(n.file),
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
            'file': _registryPath(n.file),
            'title': n.title,
            if (n.logDir != null) 'logDir': n.logDir,
            'deletedAt': n.deletedAt,
          }
      ],
      'settings': _settings,
    }));
  }

  /// How a notebook's container path is recorded in `workspace.json`.
  ///
  /// **Relative to the workspace, not the basename** (v0.17 Step 8). The
  /// original rule was "basename for a notebook that lives in the workspace, so
  /// the whole folder stays movable; the full path for one that doesn't" — and
  /// the full path matters, because writing a basename for a notebook that had
  /// been moved into a cloud folder resolved to a file that isn't there and the
  /// notebook silently disappeared from the list on the next start.
  ///
  /// A demoted container is `<workspace>/.cache/<id>/cache.onote`, which *is*
  /// inside the workspace and whose basename is `cache.onote` for every
  /// notebook at once. `p.relative` keeps the movable-folder property and
  /// round-trips the old shape unchanged: `_loadWorkspace` re-joins against the
  /// workspace directory, and for a file sitting directly in it `p.relative`
  /// returns exactly the basename this used to write, byte for byte.
  String _registryPath(String file) => p.isWithin(workspaceDir.path, file)
      ? p.relative(file, from: workspaceDir.path)
      : file;

  /// The `format.major` this registry is written with.
  ///
  /// **The guard is switched on by the thing it guards**, rather than by the
  /// release. [workspaceFormat] is 2 because a demoted notebook's relative path
  /// is a shape older builds mis-write, but a workspace with nothing demoted in
  /// it has no such path, and stamping it 2 anyway would put every user who
  /// installs this build and migrates nothing into a read-only registry on
  /// their other machine for no reason at all. So the number goes up on the
  /// same atomic write that first records a cache path, and comes back down on
  /// the write that `undemoteContainerFromCache` performs — which is how
  /// `undemote` restores a workspace an older build can use again.
  int get _formatToWrite =>
      [...notebooks, ...trashedNotebooks].any((n) => isDemoted(n)) ? 2 : 1;

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

  /// Every settings key currently held. For callers that store a FAMILY of
  /// keys under a prefix (`protect:<notebook>:<node>`) and need to enumerate
  /// them without knowing the ids in advance.
  Iterable<String> settingKeys() => _settings.keys.toList(growable: false);

  void setSetting(String key, dynamic value) {
    // A null value REMOVES the key rather than storing a null. Without this a
    // "protected" flag could only ever be set, never taken off — the map would
    // keep the key and a prefix scan would still find it.
    if (value == null) {
      _settings.remove(key);
    } else {
      _settings[key] = value;
    }
    // Session state (view memory, last page) changes constantly — coalesce.
    _scheduleSaveWorkspace();
  }

  /// The open handle for [notebookId], opening it if this session has not yet.
  ///
  /// **[openExistingOnote], not [openOnote]** (v0.17 plan, Step 8 item 2). Every
  /// notebook reaching this line is one the registry already lists, so the file
  /// is *expected* to be there and a missing one is a fault to report, never a
  /// notebook to invent. Before this, a registered container whose path had gone
  /// — an unmounted drive, a cloud client that evicted the file, a user who
  /// moved it in Explorer — was silently re-seeded as an empty 73,728-byte
  /// notebook that `notebookFileProblem` then called *"looks like a notebook"*.
  /// The three callers that really do mean "make me one" ([createNotebook],
  /// [adoptLogDirectory], [adoptWorkspaceNotebook]) call [openOnote] directly
  /// and put the handle in `_open` themselves, so none of them comes through
  /// here.
  Database _db(String notebookId) {
    final nb = notebooks.firstWhere((n) => n.id == notebookId);
    return _open.putIfAbsent(notebookId,
        () => openExistingOnote(nb.file, notebookId: nb.id, title: nb.title));
  }

  /// The container-level writer for [notebookId]. Built per call rather than
  /// cached beside `_open`: [NotebookWriter] is a stateless wrapper over the
  /// handle, so a second cache to keep in step would be pure risk.
  NotebookWriter _writer(String notebookId) => NotebookWriter(_db(notebookId));

  /// Release this process's handle on a notebook's container.
  ///
  /// For handing the file to something else that will open it — today, the
  /// import writer isolate. Two connections to one WAL database is legal, but
  /// this one would sit on a stale page cache for the whole import and its
  /// decoded pages would describe a notebook that no longer exists. Closing is
  /// cheaper than reasoning about that, and the next read reopens.
  ///
  /// Safe to call for a notebook that was never opened.
  void closeNotebook(String notebookId) {
    _open.remove(notebookId)?.dispose();
    _decodedPages.remove(notebookId);
  }

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

  /// Move a notebook's `.onotebook` log directory into [targetDir] — a folder
  /// Drive, OneDrive, Dropbox, iCloud or Syncthing replicates — and point the
  /// registry at the new location.
  ///
  /// Copy-then-verify-then-delete, never a bare rename: the destination is
  /// usually a *different volume*, where rename isn't atomic and can't be, and
  /// a half-moved notebook is the worst possible outcome. The original is
  /// removed only after every byte is confirmed at the destination — by hash,
  /// see [_copyDirectory].
  ///
  /// **The container does NOT go.** It used to, for a notebook this device
  /// created, and that put a live WAL SQLite database into a directory four
  /// consumer sync clients copy file by file with no per-file ignore between
  /// them: 31,954,368 bytes of `.onote` + `-wal` + `-shm` were being replicated
  /// out of the owner's own Drive, measured. That is ADR-0006 §2's torn-database
  /// hazard happening rather than threatened, and it is the same shape as the
  /// two-devices-one-container corruption the joined branch below has always
  /// refused to create. Half the fix was present and correct; this is the other
  /// half (v0.17 plan, Step 4).
  ///
  /// What travels is the append-only half — one log file per device, plus
  /// content-addressed blobs — which is the only part of a notebook that is
  /// safe for a dumb file-copying service to replicate.
  ///
  /// Returns the new log directory path.
  Future<String> moveNotebookTo(String notebookId, String targetDir) async {
    final ref = notebooks.firstWhere((n) => n.id == notebookId);
    final src = File(ref.file);
    if (!src.existsSync()) throw StateError('notebook file is missing');

    final dir = Directory(targetDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    // A notebook whose log directory is named explicitly — one this device
    // JOINED, or one v0.17 Step 8 has migrated — already keeps its container
    // locally and shares only the logs, so "move it somewhere else" means moving
    // the log directory. Moving the container would drag a private cache into a
    // shared folder and undo the very thing that keeps two devices apart.
    //
    // A migrated notebook always takes this branch, which is what stops the
    // branch below naming the destination folder after `p.basename(ref.file)` —
    // it would create `cache.onotebook` in the user's Drive, once per notebook,
    // all colliding.
    if (ref.logDir != null) {
      final from = Directory(ref.logDirPath);
      if (!from.existsSync()) throw StateError('the shared folder is missing');
      final name = p.basename(from.path);
      final to = Directory(p.join(targetDir, name));
      if (p.equals(from.path, to.path)) return to.path;
      if (to.existsSync()) throw StateError('$name is already in that folder');
      await _copyDirectory(from, to);
      // Registry BEFORE the delete, durably — same commit order as
      // [demoteContainerToCache], for the same reason. Deleting first and
      // recording second (on a 400 ms debounce, at that) left a window in
      // which the only `.onotebook` this registry could find was the one just
      // deleted: a crash there re-derived the old location on the next start
      // and the recorder re-initialised an EMPTY log directory under the same
      // device id at seq 1 — a fork against the real log at the destination.
      final oldLogDir = ref.logDir;
      ref.logDir = to.path;
      try {
        await _saveNow();
      } catch (_) {
        // The registry could not record the move, so the move did not happen:
        // the entry goes back the way it was, the copy goes, the original is
        // untouched. Deleting the original on the strength of a registry
        // write that FAILED is the pruning window again, one step removed.
        ref.logDir = oldLogDir;
        try {
          to.deleteSync(recursive: true);
        } catch (_) {/* a stray copy; the original is still authoritative */}
        rethrow;
      }
      try {
        from.deleteSync(recursive: true);
      } catch (_) {
        // Best-effort, and last: the data has landed and the registry already
        // says so, so a stale original is far better than failing after the
        // fact. Same reasoning as the created branch below.
      }
      return to.path;
    }

    // A notebook this device CREATED. Same move as the joined branch above —
    // the logs go, the container stays — the only differences being that this
    // one may not have a log directory yet, and that its [NotebookRef.logDir]
    // has to start being set, because the container is about to stop being the
    // `.onotebook`'s neighbour.
    final srcLog = Directory(ref.logDirPath);
    // A notebook whose recorder has never run (sync log switched off, a
    // notebook created seconds ago) has nothing on disk to move. Create it
    // rather than refuse: the user has just said this notebook is shared, and
    // an empty `.onotebook` in the folder is exactly what the second device
    // joins — the ops arrive on the first save.
    if (!srcLog.existsSync()) srcLog.createSync(recursive: true);

    final base = p.basenameWithoutExtension(ref.file);
    var destLog = p.join(targetDir, '$base.onotebook');
    // Never overwrite something already there. Only the directory matters now:
    // a stray `.onote` left in the folder by an older build is somebody else's
    // leftover, not a name this notebook has to dodge.
    var n = 2;
    while (Directory(destLog).existsSync()) {
      destLog = p.join(targetDir, '$base ($n).onotebook');
      n++;
      if (n > 500) throw StateError('cannot find a free name in that folder');
    }

    await _copyDirectory(srcLog, Directory(destLog));
    // Registry BEFORE the delete, durably — not on the 400 ms debounce. The
    // reverse order had a window (seconds wide, thanks to the debounce) in
    // which the source `.onotebook` was gone while the registry on disk still
    // had no `logDir`. A crash there meant `logDirPath` derived the deleted
    // sibling, and the next recorder re-initialised an EMPTY `.onotebook`
    // there under the same device id starting at seq 1 — a fork against the
    // real log sitting in the sync folder, with every blob byte unreachable.
    // Same commit order as [demoteContainerToCache]: copy, verify (inside
    // [_copyDirectory], by hash), registry, delete.
    ref.logDir = destLog;
    try {
      await _saveNow();
    } catch (_) {
      // See the joined branch above: an unrecorded move did not happen.
      ref.logDir = null;
      try {
        Directory(destLog).deleteSync(recursive: true);
      } catch (_) {/* a stray copy; the original is still authoritative */}
      rethrow;
    }
    try {
      srcLog.deleteSync(recursive: true);
    } catch (_) {
      // Best-effort, and last: the copy is verified, complete and recorded; a
      // lock or a permission on the original must not fail the move after the
      // data has already landed.
    }
    return destLog;
  }

  /// Whether two files hold exactly the same bytes.
  ///
  /// **A length check is not a copy check, and this used to be one.**
  /// [moveNotebookTo] compared `lengthSync()` on the container and deleted the
  /// original when the numbers agreed. A copy torn in the middle — a crash, a
  /// full disk, a cloud client that grabbed the file — has exactly the right
  /// length and passes; a copy that stopped early because the destination
  /// filled up does not, but a copy of a file whose tail was never flushed
  /// does. That function's own comment already records a previous version of
  /// its check passing *while destroying the notebook*. Hashing is the only
  /// check that can tell a complete copy from a plausible one, and the
  /// primitive is already here for blobs (v0.17 plan, Step 4).
  ///
  /// Both files are read whole. That is a transient allocation the size of the
  /// largest blob (a video), paid once per move, and it buys the one guarantee
  /// that matters: nothing is deleted on the strength of a number a broken copy
  /// also produces.
  @visibleForTesting
  static bool sameBytes(String a, String b) =>
      sha256Hex(File(a).readAsBytesSync()) ==
      sha256Hex(File(b).readAsBytesSync());

  /// Copy [from] to [to], and prove every file arrived byte for byte before
  /// the caller deletes anything.
  ///
  /// Throws on the first file that does not match, before any deletion, so a
  /// failed move leaves the original where it was.
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
        if (!sameBytes(entity.path, target)) {
          throw StateError(
              '$rel did not copy completely — nothing has been deleted');
        }
      }
    }
  }

  /// Bring a notebook's container back out of a folder something else
  /// replicates, leaving its `.onotebook` exactly where it is.
  ///
  /// **For notebooks an older build already moved.** Until the fix in
  /// [moveNotebookTo], "share this notebook" copied the `.onote` into Drive
  /// alongside the logs, and it is still sitting there — a WAL SQLite database
  /// being replicated file by file, which ADR-0006 §2 calls a live risk and
  /// which measurably is one. Nothing calls this automatically: the file is in
  /// the user's own cloud folder, and moving or deleting anything there without
  /// being asked is not a thing this app gets to do. It is one button, and the
  /// user presses it.
  ///
  /// The notebook keeps syncing afterwards, unchanged: the logs never moved,
  /// and [NotebookRef.logDir] now names them explicitly instead of implying
  /// them from a container that is no longer their neighbour.
  ///
  /// Returns the container's new path.
  Future<String> moveContainerOutOfSyncFolder(String notebookId) async {
    final ref = notebooks.firstWhere((n) => n.id == notebookId);
    final src = File(ref.file);
    if (!src.existsSync()) throw StateError('notebook file is missing');
    // Captured BEFORE `ref.file` changes: with `logDir` unset, `logDirPath` is
    // derived from the container's path, so reading it afterwards would name a
    // directory in the workspace that has never existed.
    final logs = ref.logDirPath;
    // Already home. Idempotent on purpose: the button that calls this is driven
    // by a folder scan, and pressing it twice must not manufacture a second
    // container beside the first.
    if (p.isWithin(workspaceDir.path, ref.file)) return ref.file;
    final dest = _freeNotebookPath(ref.title);

    // **CHECKPOINTED, and opened in order to be checkpointed if it was
    // closed.** In WAL mode the `.onote` is not the notebook — the `-wal`
    // beside it is, until something folds it back in. Measured on the owner's
    // own notebooks: My Notebook's 4,128,272-byte `-wal` held 2 whole pages,
    // newer revisions of 6 more, and 1 of 5 blobs; the
    // Drive notebook's 247 KB `-wal` held newer revisions of 4 pages. Copying
    // the main file and deleting the sidecars without this throws all of that
    // away, and the result passes `PRAGMA integrity_check`. `_open` only holds
    // notebooks this session actually opened, so the notebook you had not
    // looked at yet is the one that gets destroyed.
    final open = _open.remove(notebookId);
    checkpointAndClose(open ??
        openOnote(ref.file, notebookId: notebookId, title: ref.title));
    _decodedPages.remove(notebookId);

    await src.copy(dest);
    // By hash, not by length. See [sameBytes] — and this is the copy that
    // matters most, because what follows it deletes the only other copy.
    if (!sameBytes(src.path, dest)) {
      try {
        File(dest).deleteSync();
      } catch (_) {/* best effort; the original is untouched either way */}
      throw StateError(
          'the copy did not complete — nothing was moved or deleted');
    }

    // ── Commit: the registry first, the deletion second. ─────────────────
    //
    // Same order as [demoteContainerToCache], and it used to be the reverse:
    // delete the container in Drive, THEN point the registry at the copy. A
    // kill between the two left `workspace.json` naming a file that was no
    // longer there — [_loadWorkspace]'s `existsSync` filter then pruned the
    // notebook from the list permanently, and the fresh copy sitting in the
    // workspace was unregistered, so `findOrphanFiles` offered it up as safe
    // to delete. Registry first, and a kill in any window costs at worst a
    // stale original in Drive — a leftover, not a lost notebook.
    final oldFile = ref.file;
    final oldLogDir = ref.logDir;
    ref.logDir = logs;
    ref.file = dest;
    try {
      await _saveNow();
    } catch (_) {
      // The registry could not record the move, so the move did not happen:
      // the entry goes back the way it was and the copy goes. Deleting the
      // original on the strength of a registry write that FAILED is the same
      // pruning disaster, one step removed.
      ref.file = oldFile;
      ref.logDir = oldLogDir;
      try {
        File(dest).deleteSync();
      } catch (_) {/* a stray copy; the original is still authoritative */}
      rethrow;
    }

    // Best-effort, and last — the container and the two sidecars SQLite keeps
    // beside it, and only inside the cloud folder's own name. The `.onotebook`
    // is untouched. A lock or a permission must not fail a move whose result
    // is already recorded: a stale original left in Drive is a leftover the
    // "Find leftovers…" scan already knows how to report.
    try {
      _deleteContainerFiles(oldFile);
    } catch (_) {/* see above */}
    return dest;
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

    bool sameNotebook(NotebookRef n) => _isNotebookAt(n, path);

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

  /// Does registry entry [n] describe the notebook stored at [path]?
  ///
  /// The path, or the shared log directory that would sit beside it — because
  /// a device that joined a notebook through a synced folder keeps its OWN
  /// container in the workspace, so the paths differ and the log directory is
  /// the only thing the two entries have in common.
  bool _isNotebookAt(NotebookRef n, String path) =>
      p.equals(n.file, path) ||
      (n.logDir != null &&
          p.equals(n.logDir!, '${p.withoutExtension(path)}.onotebook'));

  /// The registry entry for the notebook stored at [path] — live or in the
  /// recycle bin — or null when this workspace has never seen it.
  ///
  /// Exists for the *open this file* paths (the command line, a double-click
  /// in the file manager), which have to answer "do I already have this?"
  /// **before** deciding to copy anything. [openExistingNotebook] answers the
  /// same question internally, but only after it has committed to the
  /// copy-into-the-workspace semantics that folder sync needs and a plain
  /// double-click does not.
  NotebookRef? notebookAt(String path) =>
      notebooks.where((n) => _isNotebookAt(n, path)).firstOrNull ??
      trashedNotebooks.where((n) => _isNotebookAt(n, path)).firstOrNull;

  /// Register a `.onote` that is ALREADY sitting in the workspace folder,
  /// where it is, without copying it.
  ///
  /// The case is a file the user dropped into `Documents/Openote` by hand and
  /// then double-clicked. [openExistingNotebook] would answer it by copying —
  /// and since the obvious destination name is taken (by the source file
  /// itself) the copy lands as `Physics-1.onote`, leaving the workspace
  /// holding two containers for one notebook, the second of which is the one
  /// the user's edits go to. That is the same shape of mess as the five
  /// 95 MB copies described above, reached by an easier route.
  ///
  /// No [NotebookRef.logDir] either. A notebook in the workspace logs beside
  /// itself, and pointing `logDir` at the workspace folder would quietly
  /// declare the user's own notes directory a shared sync location.
  Future<NotebookRef> adoptWorkspaceNotebook(String path, {String? title}) async {
    if (!File(path).existsSync()) throw StateError('no notebook at $path');
    if (!p.isWithin(workspaceDir.path, path)) {
      throw StateError('$path is not inside the workspace');
    }
    final already = notebookAt(path);
    if (already != null) {
      if (trashedNotebooks.any((n) => n.id == already.id)) {
        await restoreNotebook(already.id);
      }
      return already;
    }
    final id = newId();
    final name = title ?? p.basenameWithoutExtension(path);
    final ref = NotebookRef(id: id, file: path, title: name);
    notebooks.add(ref);
    _open[id] = openOnote(path, notebookId: id, title: name);
    await _saveNow();
    return ref;
  }

  /// Register a notebook whose only copy is an op-log directory.
  ///
  /// This is what a notebook cloned from a git URL looks like: `ops/`,
  /// `blobs/` and a `manifest.json`, and no `.onote` at all, because the
  /// container is gitignored on purpose (ADR-0006 §3 — it is a local WAL cache
  /// and two machines sharing one is the corruption the logs exist to avoid).
  ///
  /// [openExistingNotebook] cannot serve this case: it takes the path of a
  /// container and byte-copies it, which is right for folder sync — where the
  /// first device physically moved its `.onote` into Drive — and impossible
  /// here.
  ///
  /// So the container is created EMPTY and the first pull fills it in. Empty
  /// really means empty: unlike [createNotebook] this seeds no section and no
  /// page. Those two rows have no ops behind them, so on a joined notebook
  /// they would be permanent ghosts — content the log has never heard of,
  /// which therefore never syncs anywhere and never goes away.
  Future<NotebookRef> adoptLogDirectory(String logDir,
      {required String title, String? notebookId}) async {
    final dir = Directory(logDir);
    if (!dir.existsSync()) throw StateError('nothing at $logDir');

    // Matched on the LOG directory, the one thing two entries for the same
    // notebook always share. The container path never matches — each device
    // makes its own.
    bool same(NotebookRef n) => n.logDir != null && p.equals(n.logDir!, logDir);
    final already = notebooks.where(same).firstOrNull;
    if (already != null) return already;
    // The recycle bin counts, for the same reason it counts in
    // [openExistingNotebook]: re-joining a notebook you had deleted must
    // restore the entry you already have rather than clone a second copy of
    // it beside the first.
    final trashed = trashedNotebooks.where(same).firstOrNull;
    if (trashed != null) {
      await restoreNotebook(trashed.id);
      return trashed;
    }

    // The workspace id, not the notebook's own id from the manifest. They are
    // different things: the manifest id identifies the NOTEBOOK across
    // devices, and this identifies the row in this workspace's registry, which
    // must stay unique even if the same notebook is somehow joined twice.
    final id = notebookId ?? newId();
    final local = _freeNotebookPath(title);
    final ref = NotebookRef(id: id, file: local, title: title, logDir: logDir);
    notebooks.add(ref);
    _open[id] = openOnote(local, notebookId: id, title: title);
    await _saveNow();
    return ref;
  }

  /// The page mirror's raw JSON, for tests that assert on what is actually
  /// stored rather than on what is read back.
  ///
  /// [readPage] deliberately inflates ink on the way out, so a test that only
  /// went through it could never tell whether the geometry was still in this
  /// column — which is the entire claim.
  @visibleForTesting
  String? rawPageJsonForTest(String notebookId, String pageId) =>
      _db(notebookId)
          .select('SELECT json FROM page_mirror WHERE page_id=?', [pageId])
          .firstOrNull?['json'] as String?;

  /// How many bytes of JSON the page mirror holds for [pageId].
  ///
  /// Measured in SQLite rather than in Dart: `LENGTH(json)` on a 3 MB row is
  /// free, and pulling the string out to call `.length` on it is not.
  int pageJsonBytes(String notebookId, String pageId) =>
      (_db(notebookId)
              .select('SELECT LENGTH(json) AS n FROM page_mirror WHERE page_id=?',
                  [pageId])
              .firstOrNull?['n'] as num?)
          ?.toInt() ??
      0;

  /// Write page JSON straight into the mirror, bypassing every projection.
  ///
  /// For tests that need to construct a page the way an OLDER build wrote it —
  /// inline ink strokes, for instance. Going through [writePage] would run it
  /// through today's code and produce today's shape, which is precisely what a
  /// migration test must not do.
  @visibleForTesting
  void writePageRawForTest(
          String notebookId, String pageId, Map<String, dynamic> json) =>
      _db(notebookId).execute(
          'INSERT INTO page_mirror(page_id,json,mirror_rev,updated_at) '
          'VALUES(?,?,1,?) ON CONFLICT(page_id) DO UPDATE SET '
          'json=excluded.json, mirror_rev=mirror_rev+1, '
          'updated_at=excluded.updated_at',
          [pageId, jsonEncode(json), nowMs()]);

  /// The blob hashes a page declares, for the garbage-collection reachability
  /// test.
  @visibleForTesting
  List<String> blobRefsForTest(String notebookId, String pageId) => [
        for (final r in _db(notebookId).select(
            'SELECT hash FROM blob_refs WHERE page_id=?', [pageId]))
          r['hash'] as String
      ];

  /// Hand back the space a notebook is holding but no longer using.
  ///
  /// Two distinct kinds of waste, and they need different instruments:
  ///
  /// * **Free pages inside the container.** Deleting a 60-slide deck frees
  ///   SQLite pages, but the FILE keeps its high-water mark and reuses them
  ///   internally. `VACUUM` rewrites the database without them. The real
  ///   workspace's 97 MB container was holding 742 free pages ≈ 3 MB.
  /// * **The write-ahead log.** See [checkpointAndClose] — measured at 4–8 MB
  ///   per notebook, and on one of them larger than the database itself.
  ///
  /// `VACUUM` and not `PRAGMA incremental_vacuum`: the incremental form only
  /// releases pages the auto-vacuum bookkeeping knows about, and every
  /// notebook that exists today was created before that pragma was set. A full
  /// VACUUM works on both, and this runs from an explicit user action rather
  /// than on a timer, so its cost is one the user asked for.
  ///
  /// Returns the bytes reclaimed, and — separately — whether it ran at all.
  ///
  /// **"Could not run" used to be spelled `0`** (v0.17 plan, Step 7 item 5).
  /// The bare `catch` below returned zero, so a `VACUUM` that died of a full
  /// disk, a read-only volume or a second process holding the file was
  /// indistinguishable from a tidy notebook with nothing to give back — and the
  /// button said *"Nothing to reclaim"* either way. That is the same failure
  /// this whole step is written against, one layer up: an operation that could
  /// not be performed reported to the user as a successful no-op.
  SpaceReclaim reclaimFreeSpace(String notebookId) {
    final ref = notebooks.where((n) => n.id == notebookId).firstOrNull ??
        trashedNotebooks.where((n) => n.id == notebookId).firstOrNull;
    if (ref == null) return const SpaceReclaim(freed: 0);
    final file = File(ref.file);
    final before = file.existsSync() ? file.lengthSync() : 0;
    final wal = File('${ref.file}-wal');
    final walBefore = wal.existsSync() ? wal.lengthSync() : 0;
    try {
      final db = _db(notebookId);
      // Checkpoint FIRST. VACUUM on a database with a large WAL rewrites the
      // pages it is about to fold in, so doing it the other way round does the
      // work twice and leaves the WAL behind anyway.
      db.execute('PRAGMA wal_checkpoint(TRUNCATE);');
      db.execute('VACUUM;');
      db.execute('PRAGMA wal_checkpoint(TRUNCATE);');
    } catch (e) {
      // Still not a data-loss path — VACUUM either completes or leaves the
      // original — but the user asked for something and did not get it, so
      // they are told, rather than being shown a cheerful zero.
      debugPrint('[openote/store] could not compact $notebookId: $e');
      return SpaceReclaim(
          freed: 0,
          problem: 'Openote could not tidy up this notebook just now. It is '
              'usually because the file is open somewhere else, or the disk '
              'is full. Nothing was lost — try again in a moment.',
          details: '$e');
    }
    final after = file.existsSync() ? file.lengthSync() : 0;
    final walAfter = wal.existsSync() ? wal.lengthSync() : 0;
    final freed = (before - after) + (walBefore - walAfter);
    return SpaceReclaim(freed: freed > 0 ? freed : 0);
  }

  // ── v0.17 Step 7: reclaim the container's copy of the blob bytes ──────

  /// The one file that says a reclaim is running, for the whole workspace.
  ///
  /// **Not inside the `.onotebook`**, which is the directory Drive/OneDrive/
  /// Syncthing replicate: a marker that syncs would tell every other device
  /// that *it* had a migration in flight. It sits beside `workspace.json`,
  /// where nothing replicates it and where [AppState.findOrphanFiles] — which
  /// already lists this directory — can see it for free.
  File get _reclaimMarkerFile =>
      File(p.join(workspaceDir.path, 'reclaim-in-progress.json'));

  /// True while a reclaim holds the workspace.
  ///
  /// Two jobs. It is the concurrency gate (a second window, a second reclaim),
  /// and it is what makes the leftovers scan go quiet: `findOrphanFiles` marks
  /// an unclaimed workspace `.onote` `safeToDelete: true` and treats a
  /// `-wal`/`-shm` without its `.onote` as an orphan — **which is a state a
  /// migration creates for its own duration**. A student pressing "Find
  /// leftovers" at the wrong second would be offered their own notebook to
  /// delete.
  bool get reclaimInProgress => _reclaimMarkerFile.existsSync();

  /// What the marker says, for a message or a log line. Empty when there is
  /// none, or when it cannot be read.
  Map<String, dynamic> readReclaimMarker() {
    try {
      final f = _reclaimMarkerFile;
      if (!f.existsSync()) return const {};
      final j = jsonDecode(f.readAsStringSync());
      return j is Map<String, dynamic> ? j : const {};
    } catch (_) {
      return const {};
    }
  }

  void _writeReclaimMarker(String notebookId, String step) {
    final tmp = File('${_reclaimMarkerFile.path}.tmp');
    tmp.writeAsStringSync(
        jsonEncode({
          'step': step,
          'notebookId': notebookId,
          'startedAt': nowMs(),
          'pid': pid,
        }),
        flush: true);
    tmp.renameSync(_reclaimMarkerFile.path);
  }

  void _clearReclaimMarker() {
    try {
      final f = _reclaimMarkerFile;
      if (f.existsSync()) f.deleteSync();
    } catch (_) {
      // Leaving it is survivable — the next process start clears it — where
      // throwing here would turn a completed reclaim into a reported failure.
    }
  }

  /// Drop a marker left behind by a process that was killed.
  ///
  /// **Deliberately unconditional, and this is the judgement call in the
  /// design.** A marker that outlives its process must not become a permanent
  /// refusal: it would disable the leftovers scan for ever and refuse every
  /// future reclaim, on a notebook that is *fine*. And it is safe to drop
  /// precisely because of what Step 7 does — the `DELETE` is one transaction
  /// that rolls back, and `VACUUM` either completes or leaves the original
  /// untouched, so both crash outcomes are states a normal open settles. The
  /// marker is a record and a lock, never a repair instruction.
  ///
  /// A `Repository` is constructed once per process, so anything here now was
  /// written by an earlier run.
  void _clearStaleReclaimMarker() {
    if (!_reclaimMarkerFile.existsSync()) return;
    debugPrint('[openote/store] clearing a reclaim marker left by an earlier '
        'run: ${readReclaimMarker()}');
    _clearReclaimMarker();
  }

  /// Empty this notebook's `blobs` table, having first proved that nothing in
  /// it is the only copy of anything (v0.17 Step 7).
  ///
  /// **This is the one operation in the storage plan that destroys bytes.**
  /// Everything before it can be undone by reverting a commit. So it is written
  /// as a wall of refusals with a small action at the end, and the refusals are
  /// the feature: a spike skipped them, printed `MIGRATION COMPLETE`, left a
  /// container whose `integrity_check` said `ok`, and had permanently broken
  /// 193 image blocks across 40 pages.
  ///
  /// The caller supplies the log-side half of the proof — see
  /// `AppState.reclaimContainerBlobs`, which runs `SyncRecorder.proveBlobs`
  /// first because that proof *repairs from the container*, and the container
  /// is what this deletes.
  ///
  /// Its inverse is [refillContainerBlobs], in this same file, because a
  /// rollback that ships a release later is not a rollback.
  Future<BlobReclaim> reclaimContainerBlobs(String notebookId) async {
    BlobReclaim refuse(String why, [String? details]) =>
        BlobReclaim(refusal: why, details: details);

    final ref = notebooks.where((n) => n.id == notebookId).firstOrNull;
    if (ref == null) {
      return refuse('That notebook is not open, so there is nothing to tidy.');
    }

    // ── Gate 5, first half: nothing else is doing this right now. ──────
    if (reclaimInProgress) {
      return refuse(
          'Openote is already tidying up a notebook. Let that finish first.',
          'marker: ${readReclaimMarker()}');
    }

    final db = _db(notebookId);
    final store = _blobStore(notebookId);

    // Everything this container knows a blob by. The `blobs` rows are the bytes
    // about to be deleted; the `blob_refs` rows are ADR-0007's reachability
    // root set — the hashes a page actually shows. Neither set contains the
    // other: a row with no ref is an orphan (measured: 18 on Honours-2, 3 on
    // Honours-4, 2 on My Notebook), and every blob written since Step 6 has a
    // ref and no row.
    final tableHashes = <String>{
      for (final r in db.select('SELECT hash FROM blobs'))
        (r['hash'] as String).replaceFirst('sha256:', '')
    };
    final refHashes = <String>{
      for (final r in db.select('SELECT DISTINCT hash FROM blob_refs'))
        (r['hash'] as String).replaceFirst('sha256:', '')
    };

    // ── Gates 2 and 3: every one of them has a byte-identical file. ────
    //
    // Re-hashed, not counted and not `existsSync`'d. `hasBlob` passes against a
    // file whose bytes were replaced by the same number of different ones,
    // which is what a half-finished cloud download leaves behind, and Step 5
    // found 378 of the owner's 488 blobs with no file at all. This is the last
    // moment either can be told from a healthy notebook.
    final all = <String>{...tableHashes, ...refHashes}.toList()..sort();
    final absent = <String>[];
    final wrong = <String>[];
    var checked = 0;
    for (var i = 0; i < all.length; i += _hashBatch) {
      final slice = all.sublist(i, math.min(i + _hashBatch, all.length));
      final actual =
          await _hashFiles([for (final h in slice) store.blobFile(h).path]);
      for (var j = 0; j < slice.length; j++) {
        checked++;
        if (!store.hasBlob(slice[j])) {
          absent.add(slice[j]);
        } else if (actual[j] != slice[j]) {
          wrong.add(slice[j]);
        }
      }
      // A real millisecond, never `Duration.zero`: on Windows a zero timer is
      // posted work due immediately, so the message loop never goes idle and
      // input starves for the whole run (same reasoning as `proveBlobs`).
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    if (absent.isNotEmpty || wrong.isNotEmpty) {
      return refuse(
          "Openote will not do this yet. ${absent.length + wrong.length} of "
          "this notebook's ${all.length} pictures and drawings do not have a "
          "good copy in the notebook's own folder, and that copy is the one "
          'that would be left. Open the notebook, leave it open for a minute '
          'so Openote can finish copying, then try again.',
          'no file: ${_fewHashes(absent)}\n'
          'wrong bytes: ${_fewHashes(wrong)}\n'
          'blobs rows ${tableHashes.length}, blob_refs hashes '
          '${refHashes.length}, checked $checked');
    }

    // ── Gate 4: nothing was read out of the container this session. ────
    //
    // Step 6's registers, and the only gate that can see the pictures the
    // *running app* has actually been serving from the table. A hash here is a
    // picture that would go blank the moment the rows are deleted.
    final served = blobsServedFromContainer(notebookId);
    final nowhere = blobsWithNoBytes(notebookId);
    if (served.isNotEmpty || nowhere.isNotEmpty) {
      return refuse(
          'Openote is still reading some of this notebook’s pictures out '
          'of the notes file rather than out of the folder beside it. Close '
          'the notebook and open it again, then try this once more.',
          'served from the container: ${_fewHashes(served.toList())}\n'
          'no bytes anywhere: ${_fewHashes(nowhere.toList())}');
    }

    // ── The 2.0× precheck, before anything is touched. ─────────────────
    final file = File(ref.file);
    final wal = File('${ref.file}-wal');
    final before = file.existsSync() ? file.lengthSync() : 0;
    final walBefore = wal.existsSync() ? wal.lengthSync() : 0;
    final need = (before + walBefore) * 2;
    final free = FreeSpace.bytesFor(ref.file);
    if (free == null) {
      return refuse(
          'Openote could not check how much room is left on this disk, and it '
          'will not delete anything without knowing. Nothing has been changed.',
          'FreeSpace.bytesFor returned null for ${p.dirname(ref.file)}; '
          'needed ${_mb(need)}');
    }
    if (free < need) {
      return refuse(
          'There is not enough free space to do this safely. Tidying up needs '
          '${_mb(need)} free for a moment while it works, and this disk has '
          '${_mb(free)}. Nothing has been changed — free up some room and '
          'try again.',
          'need ${need}B (2.0 × (${before}B container + ${walBefore}B '
          'write-ahead log)), free ${free}B');
    }

    // Past here we are going to write. The marker goes down first, so the
    // leftovers scan is silent for the duration and a second reclaim refuses.
    _writeReclaimMarker(notebookId, 'empty-blobs-table');
    try {
      // ── Gate 5, second half: the file is settled and ready. ──────────
      //
      // Checkpoint before touching a row: the container must never be emptied
      // while a `-wal` still holds pages. On the owner's My Notebook that
      // `-wal` was 2 whole pages plus newer revisions of 6 more, and the
      // damaged result still passed `PRAGMA integrity_check`.
      final cp = db.select('PRAGMA wal_checkpoint(TRUNCATE);').first;
      // Exactly 1 means "another connection is holding pages". A database that
      // is not in WAL mode answers -1, which is not a refusal.
      if ((cp['busy'] as int? ?? 0) == 1) {
        return refuse(
            'Something else is using this notebook at the moment. Close any '
            'other Openote window and try again.',
            'wal_checkpoint(TRUNCATE) busy=${cp['busy']}');
      }
      // Step 6 rewrote `blob_refs` to drop `REFERENCES blobs(hash)`, and this
      // asserts it rather than assuming it. The plan's own item 4 proposed
      // adding `ON DELETE CASCADE` here instead — which would silently empty
      // `blob_refs`, ADR-0007's garbage-collection root set, after which a
      // collector classifies every blob file as unreferenced and deletes the
      // lot. If the constraint is somehow still there, stop.
      final ddl = db.select("SELECT sql FROM sqlite_master WHERE type='table' "
          "AND name='blob_refs'").first['sql'] as String;
      if (ddl.contains('REFERENCES blobs')) {
        return refuse(
            'This notebook needs to be opened once by this version of Openote '
            'before it can be tidied up. Close it and open it again.',
            'blob_refs still declares REFERENCES blobs(hash); '
            '_dropBlobRefsBlobsFk has not run');
      }

      final refsBefore = _count(db, 'blob_refs');
      db.execute('BEGIN IMMEDIATE;');
      db.execute('DELETE FROM blobs;');
      db.execute('COMMIT;');

      // The root set is byte-identical, asserted. This is the half of the
      // plan's item 4 that survives Step 6.
      final refsAfter = _count(db, 'blob_refs');
      if (refsAfter != refsBefore) {
        throw StateError('blob_refs went from $refsBefore to $refsAfter rows; '
            'the garbage-collection root set must not move');
      }

      db.execute('VACUUM;');
      db.execute('PRAGMA wal_checkpoint(TRUNCATE);');

      // **A VACUUM that did not happen must not report success.** The plan's
      // own hazard list is headed by exactly this, and `VACUUM` on a full disk
      // raises SQLITE_FULL — caught below, never smoothed into a zero.
      final left = _count(db, 'blobs');
      if (left != 0) {
        throw StateError('$left blob row(s) survived the delete');
      }
      final after = file.existsSync() ? file.lengthSync() : 0;
      final walAfter = wal.existsSync() ? wal.lengthSync() : 0;
      final freed = (before - after) + (walBefore - walAfter);
      debugPrint('[openote/store] $notebookId: removed ${tableHashes.length} '
          'blob row(s), $before → $after bytes');
      return BlobReclaim(
        done: true,
        rowsRemoved: tableHashes.length,
        checked: checked,
        freed: freed > 0 ? freed : 0,
        beforeBytes: before + walBefore,
        afterBytes: after + walAfter,
      );
    } catch (e) {
      return refuse(
          'Openote could not finish tidying up this notebook. Your pictures '
          'and drawings are safe — they are all in the folder beside the '
          'notebook, and nothing was removed from there.',
          '$e');
    } finally {
      _clearReclaimMarker();
    }
  }

  /// Put the container's copy of every reachable blob back (v0.17 Step 7's
  /// inverse).
  ///
  /// **The rollback, shipped in the same change as the thing it rolls back**,
  /// because an inverse that has never been executed is a paragraph rather than
  /// a rollback. It is only *possible* because Step 5 proved coverage: the
  /// bytes come from `blobs/`, and every one is re-hashed on the way in so a
  /// damaged file cannot be laundered into the container and then trusted.
  ///
  /// Driven by `blob_refs`, which is the plan's own definition and the right
  /// one: an old build reads pictures by following `blob_refs` into `blobs`, so
  /// restoring that set is exactly what makes it work again. Rows with no
  /// `blob_refs` entry — orphans, measured at 18 / 3 / 2 on the owner's
  /// notebooks — are **not** restored, and that asymmetry is deliberate rather
  /// than an oversight: nothing can reach them.
  Future<BlobRefill> refillContainerBlobs(String notebookId) async {
    final ref = notebooks.where((n) => n.id == notebookId).firstOrNull;
    if (ref == null) return const BlobRefill(missing: {}, restored: 0);
    final db = _db(notebookId);
    final store = _blobStore(notebookId);
    final wanted = <String>{
      for (final r in db.select('SELECT DISTINCT hash FROM blob_refs'))
        (r['hash'] as String).replaceFirst('sha256:', '')
    };
    final have = <String>{
      for (final r in db.select('SELECT hash FROM blobs'))
        (r['hash'] as String).replaceFirst('sha256:', '')
    };
    var restored = 0;
    final missing = <String>{};
    for (final hash in wanted) {
      if (have.contains(hash)) continue;
      final bytes = store.readBlob(hash);
      if (bytes == null || sha256Hex(bytes) != hash) {
        // Never insert bytes that are not what their name says. A refill is a
        // rescue, and a rescue that copies rubbish into the authoritative store
        // is worse than one that reports the hole.
        missing.add(hash);
        continue;
      }
      db.execute(
          'INSERT OR IGNORE INTO blobs(hash,bytes,mime,size,created_at) '
          'VALUES(?,?,?,?,?)',
          [hash, bytes, _sniffMime(bytes), bytes.length, nowMs()]);
      restored++;
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    db.execute('PRAGMA wal_checkpoint(TRUNCATE);');
    debugPrint('[openote/store] $notebookId: put $restored blob(s) back into '
        'the notebook file, ${missing.length} could not be restored');
    return BlobRefill(restored: restored, missing: missing);
  }

  // ── v0.17 Step 8 item 1: rebuild the container from its own log ──────

  /// Where the half-built replacement lives while it is being built, and where
  /// the container it replaces is set aside during the swap.
  ///
  /// Both are **siblings of the container**, deliberately: the swap is two
  /// renames, and a rename is only atomic within one volume. They are also
  /// outside the `.onotebook`, so nothing a cloud client replicates ever sees
  /// a partially written database (v0.17 Step 4).
  static String _rebuildTempPath(String file) => '$file.rebuild';
  static String _rebuildAsidePath(String file) => '$file.previous';

  /// Put a notebook back together after a rebuild was killed mid-swap.
  ///
  /// **Driven by the files, never by a marker**, and that is the design rather
  /// than a detail. The spike that destroyed a 329-page notebook did it by
  /// obeying a marker — *"just run the migration again"* — on a disk state the
  /// marker did not actually describe. There are exactly three states to
  /// settle and each one is decided by looking:
  ///
  ///  * `.previous` there, container **gone** — killed between the two renames.
  ///    The notebook is the file set aside; put it back.
  ///  * `.previous` there, container there — the swap finished and only the
  ///    tidy-up was lost. The container is the new one; drop the old.
  ///  * `.rebuild` there — killed while building. It was never in place and
  ///    nothing has read it; drop it.
  ///
  /// Called from [_loadWorkspace] **before** the `existsSync` filter, which is
  /// the ordering that matters: that filter drops any entry whose file is
  /// missing, and `_saveWorkspace` then rewrites the registry from what
  /// survived. Without this line a kill in the one-rename-wide window would
  /// prune the notebook from the registry at the next start, permanently — the
  /// exact harm `workspaceFormat` exists to prevent, reached by another road.
  static void _settleInterruptedRebuild(String file) {
    try {
      final aside = File(_rebuildAsidePath(file));
      if (aside.existsSync()) {
        if (FileSystemEntity.typeSync(file, followLinks: true) ==
            FileSystemEntityType.notFound) {
          debugPrint('[openote/store] a rebuild was interrupted mid-swap; '
              'putting ${p.basename(file)} back');
          aside.renameSync(file);
        } else {
          aside.deleteSync();
        }
      }
      final tmp = File(_rebuildTempPath(file));
      if (tmp.existsSync()) tmp.deleteSync();
      for (final side in const ['-wal', '-shm']) {
        for (final base in [_rebuildTempPath(file), _rebuildAsidePath(file)]) {
          final f = File('$base$side');
          if (f.existsSync()) f.deleteSync();
        }
      }
    } catch (e) {
      // Never fatal. A workspace that cannot be tidied still has to load, and
      // both leftovers are inert: `.previous` is a whole valid notebook and
      // `.rebuild` was never in place. The leftovers scan reports them.
      debugPrint('[openote/store] could not settle a rebuild leftover for '
          '${p.basename(file)}: $e');
    }
  }

  /// Rebuild [notebookId]'s container from the append-only log, and put the
  /// result in place of the old one (v0.17 plan, Step 8 item 1).
  ///
  /// **This is the call `pendingForeignOps` structurally cannot make.** That one
  /// opens with `if (dev == device.id) continue` (`sync_recorder.dart`), because
  /// its job is folding in what *other* devices wrote. A single-device
  /// notebook's entire history lives in exactly the file it skips, so the join
  /// path has never been a rebuild path: a fresh device works because it has no
  /// log of its own, and a device that loses its cache but keeps its `deviceId`
  /// gets back only what other devices wrote. This reads every device's log,
  /// this one's included. Measured by the plan at 102–120 ms for 329 pages and
  /// 2,780 ops.
  ///
  /// **It is a wall of refusals with a small action at the end**, for the same
  /// reason [reclaimContainerBlobs] is: a rebuild that proceeds when the log
  /// cannot supply the whole notebook does not report an error, it produces a
  /// notebook that passes `PRAGMA integrity_check` and is missing things. The
  /// gates, in order:
  ///
  ///  1. the log opens and is not empty;
  ///  2. no op is beyond what this build can read (Step 3's envelope gate) —
  ///     writing a container from a half-read history is how an "edit" becomes
  ///     an undo of changes the user never asked to lose;
  ///  3. **every live node and every stored page the container holds is in the
  ///     rebuilt state.** This is the negative control: a notebook whose
  ///     container knows things its log does not — one created with logging off,
  ///     one whose log was truncated below a page — is refused rather than
  ///     silently reduced;
  ///  4. every blob the result names has a **byte-identical** file in `blobs/`.
  ///     Page JSON names a picture by hash, so a page whose bytes are gone is
  ///     byte-identical to one whose bytes are fine, and only re-hashing can
  ///     tell them apart. A spike skipped this and destroyed 193 image blocks
  ///     across 40 pages while printing `MIGRATION COMPLETE`;
  ///  5. free space ≥ 2.0 × (container + write-ahead log), measured in Step 7.
  ///
  /// Nothing is touched until every one of them passes, and the container is
  /// only removed once the replacement is built, verified and in place.
  ///
  /// **The replacement holds no `blobs` rows, and that is deliberate.** From
  /// Step 6 the bytes live in `.onotebook/blobs/` and the container reads
  /// through to them, so a rebuilt container is Step 7's shape whether or not
  /// Step 7's reclaim has been run — measured on the owner's real Drive
  /// notebook, 31,715,328 B → 1,495,040 B, against the 1,470,464 B the plan
  /// recorded for `DELETE FROM blobs; VACUUM` on the same shape. Gate 4 is what
  /// makes that safe rather than lossy, and [refillContainerBlobs] is the way
  /// back for anyone who needs the old shape.
  ///
  /// **The derived tables are not carried across either, and nothing is.**
  /// `block_authors` and `recent_deletions` (Step 8a) are folds of the very log
  /// this replays, so `AppState.rebuildContainerFromLog` forgets how far the
  /// fold had got and lets the next refresh re-derive them.
  Future<ContainerRebuild> rebuildContainerFromLog(String notebookId) async {
    ContainerRebuild refuse(String why, [String? details]) =>
        ContainerRebuild(refusal: why, details: details);

    final ref = notebooks.where((n) => n.id == notebookId).firstOrNull;
    if (ref == null) {
      return refuse('That notebook is not open, so there is nothing to '
          'rebuild.');
    }
    if (reclaimInProgress) {
      return refuse(
          'Openote is already tidying up a notebook. Let that finish first.',
          'marker: ${readReclaimMarker()}');
    }

    // ── Gate 1: there is a history to rebuild from. ────────────────────
    final store = OpLogStore.forNotebook(ref.file, logDir: ref.logDir);
    if (!store.opsDir.existsSync()) {
      return refuse(
          "Openote could not find this notebook's own folder, so there is no "
          'history to rebuild it from. Nothing has been changed.',
          'no ops directory at ${store.opsDir.path}');
    }
    final List<Op> ops;
    try {
      ops = store.readAll();
    } catch (e) {
      return refuse(
          "Openote could not read this notebook's history. Nothing has been "
          'changed.',
          '$e');
    }
    if (ops.isEmpty) {
      return refuse(
          "This notebook's folder has no history in it, so rebuilding would "
          'produce an empty notebook. Nothing has been changed.',
          'readAll() over ${store.opsDir.path} returned no ops');
    }

    final state = Materializer()..applyAll(ops);

    // ── Gate 2: nothing in the log is beyond this build. ───────────────
    if (state.unsupported.isNotEmpty) {
      return refuse(
          'Part of this notebook was written by a newer version of Openote, so '
          'this one cannot rebuild it without leaving that part out. Update '
          'Openote and try again. Nothing has been changed.',
          '${state.unsupported.length} op(s) with an envelope this build '
          'cannot read; first: ${state.unsupported.first.kind}');
    }

    // ── Gate 3: the replay reproduces the container, field for field. ──
    //
    // **The gate the whole call stands on, and the only one that can see the
    // notebook the log has never fully described.** Comparing ids would not do
    // it: `AppState._backfillTree` records a `node.upsert` for every container
    // node the log has never heard of, so a notebook saved before the log
    // existed has a log that *names* every page and holds not one of their
    // blocks. Ids would match and the rebuild would produce empty pages.
    //
    // So this compares content — the same comparison `SyncRecorder.verifyPage`
    // has always made, in bulk: canonical page JSON with blocks keyed by id on
    // both sides, plus every `nodes` column. Anything the container has that
    // the replay does not reproduce stops the rebuild before a byte is written.
    final db = _db(notebookId);
    final containerNodes = _count(db, 'nodes');
    final containerPages = _count(db, 'page_mirror');
    final differences = _rebuildDifferences(db, state);
    if (differences.isNotEmpty) {
      return refuse(
          'Openote will not do this. Rebuilding this notebook from its saved '
          'history would not give back what is in it now — '
          '${differences.length} page(s) or section(s) would come back '
          'different or empty. Nothing has been changed.',
          '${differences.length} difference(s), first few:\n'
          '${differences.take(5).join('\n')}\n'
          '${ops.length} op(s) replayed');
    }

    // ── Gate 5: the room to do it, before anything is written. ─────────
    final file = File(ref.file);
    final wal = File('${ref.file}-wal');
    final before = file.existsSync() ? file.lengthSync() : 0;
    final walBefore = wal.existsSync() ? wal.lengthSync() : 0;
    final need = (before + walBefore) * 2;
    final free = FreeSpace.bytesFor(ref.file);
    if (free == null) {
      return refuse(
          'Openote could not check how much room is left on this disk, and it '
          'will not rebuild a notebook without knowing. Nothing has been '
          'changed.',
          'FreeSpace.bytesFor returned null for ${p.dirname(ref.file)}; '
          'needed ${_mb(need)}');
    }
    if (free < need) {
      // Needed rounds UP and free rounds DOWN. With both rounded the same way,
      // a refusal one byte short of the bar printed "needs 60.5 MB free … and
      // this disk has 60.5 MB", which reads as a contradiction — observed
      // exactly that way on the owner's 31.7 MB notebook.
      return refuse(
          'There is not enough free space to do this safely. Rebuilding needs '
          '${_mbUp(need)} free for a moment while it works, and this disk has '
          '${_mb(free)}. Nothing has been changed — free up some room and try '
          'again.',
          'need ${need}B (2.0 × (${before}B container + ${walBefore}B '
          'write-ahead log)), free ${free}B');
    }

    // Past here we write — but only to a file the notebook does not depend on.
    // The marker goes down first so the leftovers scan is silent for the
    // duration: `findOrphanFiles` classes a `-wal` whose `.onote` is absent as
    // an orphan, and the swap below creates exactly that state for two renames.
    _writeReclaimMarker(notebookId, 'rebuild-from-log');
    final tmpPath = _rebuildTempPath(ref.file);
    final asidePath = _rebuildAsidePath(ref.file);
    Database? fresh;
    try {
      // Never onto an existing destination, anywhere in this method.
      // `File.renameSync` on Windows replaces silently — verified directly, and
      // it is how a re-run renamed a fabricated empty database over a real
      // 329-page notebook with no exception at all.
      _settleInterruptedRebuild(ref.file);

      fresh = openOnote(tmpPath, notebookId: notebookId, title: ref.title);
      final writer = NotebookWriter(fresh);
      final title = state.meta['title'] as String? ?? ref.title;
      fresh.execute('INSERT OR REPLACE INTO notebook_meta(key,value) '
          'VALUES(?,?)', ['title', jsonEncode(title)]);

      // **Parents before children, and every node, live or not.** Two foreign
      // keys make the order load-bearing — `nodes.parent_id` onto itself and
      // `page_mirror.page_id` onto `nodes` — and a soft-deleted node satisfies
      // both perfectly well, so unlike the sync pull this writes deleted nodes
      // in place rather than writing the live tree and soft-deleting after.
      // That is what keeps `deletedAt` at the value the log recorded instead of
      // resetting every trashed page's thirty-day clock to today.
      final ordered = <MatNode>[];
      final placed = <String>{};
      var droppedNodes = 0;
      var unknownKinds = 0;
      var progress = true;
      final pending = state.nodes.values.toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      while (progress) {
        progress = false;
        pending.removeWhere((n) {
          final parent = n.parentId;
          if (parent != null && !placed.contains(parent)) return false;
          placed.add(n.id);
          ordered.add(n);
          progress = true;
          return true;
        });
      }
      // Whatever is left is a node whose parent the log no longer holds — the
      // subtree of a `node.purge`. The container cascades a purge through
      // `nodes.parent_id ON DELETE CASCADE` and [Materializer] does not, so
      // these rows were already gone from the container before this ran. Gate 3
      // above is what makes dropping them safe: it has already refused if any
      // of them is still live in the container.
      droppedNodes = pending.length;

      final stmt = fresh.prepare(
          'INSERT INTO nodes(id,kind,parent_id,title,position,color,level,'
          'created_at,updated_at,deleted_at) VALUES(?,?,?,?,?,?,?,?,?,?)');
      try {
        writer.runInTransaction(() {
          for (final n in ordered) {
            // A kind this build cannot name is left out rather than coerced to
            // `page`: the container's own CHECK constraint would reject it, and
            // guessing "page" is what turned six section groups per notebook
            // into pages (v0.17 Step 3).
            final kind = nodeKindFromWire(n.kind);
            if (kind == null) {
              unknownKinds++;
              continue;
            }
            // **The SPEC spelling, not whatever the log happens to say.** The
            // container declares `CHECK (kind IN ('section_group','section',
            // 'page'))`, and every log written before v0.17 Step 3 spells a
            // section group `sectionGroup` — so writing it back verbatim fails
            // the INSERT outright and takes the whole transaction with it. The
            // plan recorded exactly this: "every rebuild a spike ran needed
            // exactly 6 fixups or the INSERT failed".
            stmt.execute([
              n.id, nodeKindWire(kind), n.parentId, n.title, n.position,
              n.color, n.level, n.createdAt, n.updatedAt, n.deletedAt,
            ]);
          }
        });
      } finally {
        stmt.dispose();
      }

      // Pages, in chunks so a big notebook does not hold one transaction open
      // across the whole rebuild.
      final pageIds = [
        for (final n in ordered)
          if (n.kind == 'page' && placed.contains(n.id)) n.id
      ];
      for (var i = 0; i < pageIds.length; i += _rebuildPageChunk) {
        final slice = pageIds.sublist(
            i, math.min(i + _rebuildPageChunk, pageIds.length));
        writer.runInTransaction(() {
          for (final pid in slice) {
            final mirror = state.pageMirror(pid);
            writer.writePage(
                pid,
                [
                  for (final b in (mirror['blocks'] as List? ?? const []))
                    Block.fromJson((b as Map).cast<String, dynamic>())
                ],
                PageProps.fromJson(
                    (mirror['page'] as Map?)?.cast<String, dynamic>()));
          }
        });
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }

      // **Nothing is carried across any more.** This used to copy
      // `page_versions` out of the old container and back into the new one, on
      // the grounds that the log has no op kind for page history and a repair
      // that loses history is not a repair. Plan decision 1 removed the other
      // end of that argument: the table is gone, Step 8a's `block_authors` and
      // `recent_deletions` replace it, and both are folds of the log that
      // `AppState.rebuildContainerFromLog` deliberately re-derives afterwards
      // rather than migrating. So a rebuilt container is the log, and only the
      // log — which is the property the whole call is for.

      // ── Gate 4: every picture the result names really is on disk. ────
      //
      // Read off the REBUILT container's own `blob_refs`, not off the old one:
      // that projection is what a reader follows, and it is what
      // `NotebookWriter.writePage` has just recomputed from the log's own page
      // content. Union'd with the log's `blob.put` set so a hash recorded but
      // never yet placed on a page is checked too — `importBlob` writes the op
      // before anything writes the page, so every paste and every crash between
      // the two leaves exactly that.
      final wanted = <String>{
        for (final r in fresh.select('SELECT DISTINCT hash FROM blob_refs'))
          (r['hash'] as String).replaceFirst('sha256:', ''),
        for (final h in state.blobs) h.replaceFirst('sha256:', ''),
      }.toList()
        ..sort();
      final absent = <String>[];
      final wrong = <String>[];
      for (var i = 0; i < wanted.length; i += _hashBatch) {
        final slice =
            wanted.sublist(i, math.min(i + _hashBatch, wanted.length));
        final actual =
            await _hashFiles([for (final h in slice) store.blobFile(h).path]);
        for (var j = 0; j < slice.length; j++) {
          if (!store.hasBlob(slice[j])) {
            absent.add(slice[j]);
          } else if (actual[j] != slice[j]) {
            wrong.add(slice[j]);
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      if (absent.isNotEmpty || wrong.isNotEmpty) {
        checkpointAndClose(fresh);
        fresh = null;
        _deleteContainerFiles(tmpPath);
        return refuse(
            'Openote will not do this yet. ${absent.length + wrong.length} of '
            "this notebook's ${wanted.length} pictures and drawings do not "
            "have a good copy in the notebook's own folder, and rebuilding "
            'would leave you with the folder alone. Open the notebook, leave '
            'it open for a minute so Openote can finish copying, then try '
            'again.',
            'no file: ${_fewHashes(absent)}\n'
            'wrong bytes: ${_fewHashes(wrong)}');
      }

      // Verified before it is anywhere near the registered path.
      final integrity =
          fresh.select('PRAGMA integrity_check;').first.columnAt(0) as String?;
      final builtNodes = _count(fresh, 'nodes');
      final builtPages = _count(fresh, 'page_mirror');
      checkpointAndClose(fresh);
      fresh = null;
      if (integrity != 'ok') {
        _deleteContainerFiles(tmpPath);
        return refuse(
            'Openote built a replacement for this notebook and then found it '
            'was not sound, so it has thrown it away. Nothing has been '
            'changed.',
            'integrity_check on $tmpPath said "$integrity"');
      }
      if (builtNodes < containerNodes || builtPages < containerPages) {
        // Belt and braces over gate 3: that gate compares ids, this compares
        // what actually landed. A write that silently dropped rows — a
        // constraint the DDL will grow later, a chunk that rolled back — must
        // not reach the swap.
        _deleteContainerFiles(tmpPath);
        return refuse(
            'Openote built a replacement for this notebook and it came out '
            'smaller than the one you have, so it has thrown it away. Nothing '
            'has been changed.',
            'rebuilt $builtNodes node(s) / $builtPages page(s) against '
            '$containerNodes / $containerPages in the container');
      }

      // ── The swap: two renames, neither onto anything. ────────────────
      //
      // The container's own handle is closed and checkpointed FIRST. In WAL
      // mode the `.onote` is not the notebook — the `-wal` beside it is, until
      // something folds it back in — and moving the main file while a `-wal`
      // holds pages throws those pages away and still passes
      // `integrity_check`. Measured on the owner's My Notebook: 2 whole pages
      // and newer revisions of 6 more in a 4,128,272-byte `-wal`.
      final open = _open.remove(notebookId);
      if (open != null) checkpointAndClose(open);
      _decodedPages.remove(notebookId);
      file.renameSync(asidePath);
      File(tmpPath).renameSync(ref.file);
      _deleteContainerFiles(asidePath);

      debugPrint('[openote/store] $notebookId: rebuilt from ${ops.length} op(s)'
          ' — $builtNodes node(s), $builtPages page(s)');
      return ContainerRebuild(
        done: true,
        ops: ops.length,
        nodes: builtNodes,
        pages: builtPages,
        blobsChecked: wanted.length,
        droppedNodes: droppedNodes,
        details: unknownKinds == 0
            ? null
            : '$unknownKinds node(s) left out — their kind was written by a '
                'newer version of Openote',
      );
    } catch (e) {
      try {
        if (fresh != null) checkpointAndClose(fresh);
      } catch (_) {/* the throw below is the one worth reporting */}
      // The files decide, not this catch: whatever stage it failed at,
      // `_settleInterruptedRebuild` restores the container or drops the
      // half-built one, exactly as it would after a hard kill at the same
      // point. One recovery path, exercised by every failure.
      _settleInterruptedRebuild(ref.file);
      return refuse(
          'Openote could not rebuild this notebook. Your notes have not been '
          'changed — everything is still where it was.',
          '$e');
    } finally {
      _clearReclaimMarker();
    }
  }

  // ── v0.17 Step 8: the rename, and the way back ───────────────────────

  /// The folder holding every notebook's working copy.
  ///
  /// **Local, and never inside a synced tree.** ADR-0006 §3 drew `cache.onote`
  /// inside `MyNotebook.onotebook/`, and §8 of that same ADR — six days later —
  /// made that directory the git repo root and the thing Drive, OneDrive,
  /// Dropbox and Syncthing replicate file by file. The drawing therefore puts a
  /// live WAL SQLite database back into the replicated set: the exact
  /// 31,954,368 bytes commit 435b2bd removed from the owner's own Drive, and the
  /// torn-database hazard ADR-0006 §2 calls a live risk. The ADR is what is
  /// wrong. The working copy goes here instead.
  ///
  /// Three properties, each one paid for by a specific failure:
  ///
  ///  * **Under the workspace**, which is where every container has always
  ///    lived. Nothing that was local becomes synced and nothing that was synced
  ///    becomes local; the only tree a student is ever told to put in Drive is
  ///    the `.onotebook`, and it does not come here.
  ///  * **Keyed by the notebook id, not its title.** The title is renameable and
  ///    two notebooks can share one; the id is the identity, which is exactly
  ///    what [NotebookRef.file]'s own comment says. A per-notebook directory
  ///    also pens in the `-wal`, the `-shm` and the `.rebuild`/`.previous` files
  ///    the rebuild swap makes, so none of them can ever collide with another
  ///    notebook's.
  ///  * **One level down**, so [findOrphanFiles]'s deliberately top-level-only
  ///    workspace scan cannot see a container mid-migration. That scan marks an
  ///    unclaimed workspace `.onote` `safeToDelete`, and a `-wal` whose `.onote`
  ///    is absent an orphan — offering a student their own half-migrated
  ///    notebook to delete is the one way that feature could destroy notes.
  ///
  /// The leading dot keeps it out of the way in the user's own Documents folder.
  /// It is never a path anybody has to type: `workspace.json` is the only thing
  /// that knows the way in, which is also why [workspaceFormat] guards it.
  Directory cacheDirFor(String notebookId) =>
      Directory(p.join(workspaceDir.path, '.cache', notebookId));

  /// Where [notebookId]'s working copy lives once it has been migrated.
  String cachePathFor(String notebookId) =>
      p.join(cacheDirFor(notebookId).path, workingCopyFileName);

  /// Whether this notebook's container has been migrated to a working copy.
  ///
  /// By path rather than by reading the file: this is asked on every registry
  /// write, and a `user_version` probe is a file open per notebook per save.
  bool isDemoted(NotebookRef ref) => p.equals(ref.file, cachePathFor(ref.id));

  /// Decide what a half-finished migration left behind, by looking at the files.
  ///
  /// **Driven by the disk, never by a marker**, for the reason
  /// [_settleInterruptedRebuild] is: the spike that destroyed a 329-page
  /// notebook did it by obeying a marker on a disk state the marker did not
  /// describe. There are three states and each is decided by looking:
  ///
  ///  * The registry already names the cache — the migration committed. Nothing
  ///    to settle.
  ///  * The registry names a container that is **there**, and a cache directory
  ///    exists anyway — an attempt that never committed. It cannot be the only
  ///    copy of anything, because both directions write `workspace.json` BEFORE
  ///    they delete the container they came from, so drop it.
  ///  * The registry names a container that is **gone**, and a working copy is
  ///    sitting in the cache — the one state where deleting would be the wrong
  ///    move. Adopt the cache instead. This is the difference between "the app
  ///    tidied up" and "the notebook is not in the list any more", and the
  ///    `existsSync` filter in [_loadWorkspace] makes the second one permanent.
  ///
  /// Returns the path the entry should use.
  String _settleDemotion(String notebookId, String file, String? logDir) {
    try {
      final cache = cachePathFor(notebookId);
      if (p.equals(file, cache)) return file;
      final dir = cacheDirFor(notebookId);
      if (!dir.existsSync()) return file;
      if (File(file).existsSync()) {
        debugPrint('[openote/store] dropping a cache directory left by an '
            'unfinished migration of $notebookId');
        dir.deleteSync(recursive: true);
        return file;
      }
      // The notes folder has to be named explicitly for a working copy to be
      // usable at all — [NotebookRef.logDir] — and the migration records it on
      // the same write that records the cache path. Without one there is nothing
      // to adopt: the ops would be looked for inside the cache directory itself.
      if (logDir != null && File(cache).existsSync()) {
        debugPrint('[openote/store] $notebookId: the notebook file is gone and '
            'a working copy is here; using the working copy');
        return cache;
      }
      return file;
    } catch (e) {
      // Never fatal. Both leftovers are inert and the registry still loads.
      debugPrint('[openote/store] could not settle a migration leftover for '
          '$notebookId: $e');
      return file;
    }
  }

  /// Move this notebook's container into its cache directory as `cache.onote`,
  /// stamp it as a working copy, and drop the old page snapshots
  /// (v0.17 plan, Step 8 — the rename).
  ///
  /// **Opt-in, one notebook at a time, and never on open.** Decision 4 of the
  /// plan ships macOS without a human pass, so a one-way v1 → v2 migration will
  /// run for the first time on a platform nobody has driven by hand. The
  /// response is not to soften the risk: it is that the student chooses the
  /// moment, the app runs indefinitely without it, and if a problem is ever
  /// reported the answer is *"don't press it yet"* rather than *"we already
  /// did"*.
  ///
  /// **A wall of refusals with a small action at the end**, the same shape as
  /// [reclaimContainerBlobs] and [rebuildContainerFromLog], because every gate
  /// here exists because something without it destroyed real data:
  ///
  ///  1. the registry is writable. If `workspace.json` was written by a newer
  ///     build this one loads it and never writes it back — so the move would
  ///     happen on disk and be forgotten, and the next start would look for the
  ///     container at the path it used to be;
  ///  2. there is a notes folder with a history in it, and it is not inside the
  ///     cache. That folder becomes the only permanent copy of the notebook's
  ///     structure, and [NotebookRef.logDir] has to name it explicitly from here
  ///     on because the sibling-of-the-container default stops meaning anything;
  ///  3. **the log can supply the whole notebook.** Calling a file a cache is a
  ///     promise that it can be rebuilt, and [_rebuildDifferences] is the only
  ///     thing that can tell a notebook whose log describes it from one whose
  ///     log merely names its pages. A notebook that fails this is refused with
  ///     nothing touched — it is not broken, it simply is not a cache;
  ///  4. free space ≥ 2.0 × (container + write-ahead log), the same bar Step 7
  ///     measured, checked before the marker goes down.
  ///
  /// **The order of the last three steps is the crash safety**, and it is the
  /// opposite of the obvious one: copy, then write the registry, then delete.
  /// Deleting first — or renaming — leaves a window in which `workspace.json`
  /// names a file that is not there, and [_loadWorkspace] drops such an entry
  /// and rewrites the registry without it. That is a notebook pruned from the
  /// list permanently for a kill inside a millisecond-wide window, which is the
  /// same disaster [workspaceFormat] exists to prevent, reached by another road.
  Future<ContainerDemotion> demoteContainerToCache(String notebookId) async {
    ContainerDemotion refuse(String why, [String? details]) =>
        ContainerDemotion(refusal: why, details: details);

    final ref = notebooks.where((n) => n.id == notebookId).firstOrNull;
    if (ref == null) {
      return refuse('That notebook is not open, so there is nothing to change.');
    }
    if (isDemoted(ref)) {
      return refuse('This notebook is already stored the new way. Nothing has '
          'been changed.', 'already at ${ref.file}');
    }
    if (reclaimInProgress) {
      return refuse(
          'Openote is already tidying up a notebook. Let that finish first.',
          'marker: ${readReclaimMarker()}');
    }
    // ── Gate 1: this build is allowed to write the list of notebooks. ──
    if (registryReadOnly != null) {
      return refuse(
          'Your list of notebooks was last used by a newer version of Openote, '
          'so this one is only reading it. Update Openote first — moving this '
          'notebook now would lose track of where it went.',
          registryReadOnly!.details);
    }
    final file = File(ref.file);
    if (!file.existsSync()) {
      return refuse(
          'Openote cannot find this notebook at the moment, so it has not '
          'changed anything.',
          'no file at ${ref.file}');
    }

    // ── Gate 2: there is a notes folder, and it is not inside the cache. ──
    final logs = ref.logDirPath;
    if (p.isWithin(cacheDirFor(notebookId).path, logs) ||
        p.equals(p.basename(logs), workingCopyFileName)) {
      return refuse(
          "Openote cannot tell where this notebook's own folder is, so it has "
          'not changed anything.',
          'refusing to record a log directory inside the cache: $logs');
    }
    final store = OpLogStore.forNotebook(ref.file, logDir: ref.logDir);
    if (!store.opsDir.existsSync()) {
      return refuse(
          "Openote could not find this notebook's own folder, so there would be "
          'nothing left to rebuild it from. Nothing has been changed.',
          'no ops directory at ${store.opsDir.path}');
    }
    final List<Op> ops;
    try {
      ops = store.readAll();
    } catch (e) {
      return refuse(
          "Openote could not read this notebook's history. Nothing has been "
          'changed.',
          '$e');
    }
    if (ops.isEmpty) {
      return refuse(
          "This notebook's folder has no history in it yet, so the notes file "
          'is still the only copy. Open the notebook, make a change, and try '
          'again. Nothing has been changed.',
          'readAll() over ${store.opsDir.path} returned no ops');
    }
    final state = Materializer()..applyAll(ops);
    if (state.unsupported.isNotEmpty) {
      return refuse(
          'Part of this notebook was written by a newer version of Openote, so '
          'this one cannot read all of it. Update Openote and try again. '
          'Nothing has been changed.',
          '${state.unsupported.length} op(s) with an envelope this build '
          'cannot read; first: ${state.unsupported.first.kind}');
    }

    // ── Gate 3: the history really does describe this notebook. ────────
    final db = _db(notebookId);
    final differences = _rebuildDifferences(db, state);
    if (differences.isNotEmpty) {
      return refuse(
          'Openote will not do this. This notebook has things in it that its '
          'saved history does not describe — ${differences.length} page(s) or '
          'section(s) — so the notes file is still the only copy of them and '
          'must not be treated as one Openote can throw away. Nothing has been '
          'changed.',
          '${differences.length} difference(s), first few:\n'
          '${differences.take(5).join('\n')}\n'
          '${ops.length} op(s) replayed');
    }

    // ── Gate 4: the room, before anything is written. ──────────────────
    final wal = File('${ref.file}-wal');
    final before = file.lengthSync();
    final walBefore = wal.existsSync() ? wal.lengthSync() : 0;
    final need = (before + walBefore) * 2;
    final free = FreeSpace.bytesFor(ref.file);
    if (free == null) {
      return refuse(
          'Openote could not check how much room is left on this disk, and it '
          'will not move a notebook without knowing. Nothing has been changed.',
          'FreeSpace.bytesFor returned null for ${p.dirname(ref.file)}; '
          'needed ${_mb(need)}');
    }
    if (free < need) {
      return refuse(
          'There is not enough free space to do this safely. It needs '
          '${_mbUp(need)} free for a moment while it works, and this disk has '
          '${_mb(free)}. Nothing has been changed — free up some room and try '
          'again.',
          'need ${need}B (2.0 × (${before}B container + ${walBefore}B '
          'write-ahead log)), free ${free}B');
    }

    final oldFile = ref.file;
    final oldLogDir = ref.logDir;
    final dest = cachePathFor(notebookId);
    _writeReclaimMarker(notebookId, 'demote-to-cache');
    var committed = false;
    try {
      // Anything already in the cache directory is from an attempt that never
      // committed — see [_settleDemotion] — and a copy onto an existing file is
      // the one thing this plan never does.
      final dir = cacheDirFor(notebookId);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);

      // **Checkpointed, and opened in order to be checkpointed if it was
      // closed.** In WAL mode the `.onote` is not the notebook — the `-wal`
      // beside it is, until something folds it back in. Measured on the owner's
      // own notebooks: My Notebook's 4,128,272-byte `-wal` held 2 whole pages,
      // newer revisions of 6 more, 1 of 5 blobs and 5 of 22 `page_versions`.
      // Copying the main file without this throws all of that away and the
      // result passes `PRAGMA integrity_check`.
      final open = _open.remove(notebookId);
      checkpointAndClose(open ??
          openExistingOnote(ref.file, notebookId: notebookId, title: ref.title));
      _decodedPages.remove(notebookId);

      await file.copy(dest);
      // By hash, not by length: a copy torn in the middle by a crash or a cloud
      // client has exactly the right length and passes a length check, and this
      // is the copy that decides whether the original may be deleted.
      if (!sameBytes(oldFile, dest)) {
        throw StateError('the copy of the notes file did not complete');
      }

      // Stamp it, and drop the old snapshots. Both happen on the COPY, so a
      // failure anywhere here leaves the original untouched and the registry
      // still pointing at it.
      final fresh =
          openExistingOnote(dest, notebookId: notebookId, title: ref.title);
      var dropped = 0;
      try {
        // **The one irreversible half of this migration** (plan decision 1).
        // `page_versions` held up to thirty full copies of every page; Step 8a
        // shipped what replaces it, and nothing in `lib/` has read this table
        // since. `undemote` cannot bring the rows back, which is why the dialog
        // says so before the button is pressed.
        try {
          dropped = _count(fresh, 'page_versions');
        } catch (_) {
          // A notebook made by a build that never created it. Nothing to drop.
        }
        fresh.execute('DROP TABLE IF EXISTS page_versions;');
        fresh.execute('VACUUM;');
        fresh.execute('PRAGMA user_version = $onoteWorkingCopyVersion;');
        final integrity =
            fresh.select('PRAGMA integrity_check;').first.columnAt(0) as String?;
        if (integrity != 'ok') {
          throw StateError('integrity_check on the copy said "$integrity"');
        }
      } finally {
        checkpointAndClose(fresh);
      }

      // ── Commit: the registry first, the deletion second. ─────────────
      //
      // Both facts land on one atomic `workspace.json` write — the new path AND
      // the notes folder, which stops being derivable from it — and the old
      // container is not touched until that write has returned.
      ref.logDir = logs;
      ref.file = dest;
      await _saveNow();
      committed = true;

      // Best-effort, and last. A lock or a permission on the original must not
      // fail a migration whose result is already recorded; what is left behind
      // is an ordinary leftover the "Find leftovers…" scan already reports.
      try {
        _deleteContainerFiles(oldFile);
      } catch (_) {/* see above */}

      debugPrint('[openote/store] $notebookId: $oldFile → $dest, '
          '$dropped page snapshot(s) dropped');
      return ContainerDemotion(
        done: true,
        from: oldFile,
        to: dest,
        snapshotsDropped: dropped,
        bytes: File(dest).existsSync() ? File(dest).lengthSync() : 0,
      );
    } catch (e) {
      if (!committed) {
        ref.file = oldFile;
        ref.logDir = oldLogDir;
        try {
          final dir = cacheDirFor(notebookId);
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        } catch (_) {/* [_settleDemotion] drops it at the next start */}
      }
      return refuse(
          'Openote could not change how this notebook is stored. Your notes '
          'have not been changed — everything is still where it was.',
          '$e');
    } finally {
      _clearReclaimMarker();
    }
  }

  /// Put a migrated notebook back the way it was (v0.17 Step 8's inverse).
  ///
  /// **Written, tested and executed in the same change as the rename**, because
  /// an inverse that has never been run is a paragraph rather than a rollback.
  /// Part 6 of the plan makes it a release blocker for the release that ships
  /// the rename.
  ///
  /// Four things go back, and they are exactly the four the plan names: the
  /// container returns to the workspace as an ordinary `.onote`, its
  /// `user_version` goes back to [onoteFormatMajor], [refillContainerBlobs]
  /// puts the picture bytes back into the `blobs` table so a build that reads
  /// pictures out of the container can render them, and `workspace.json`'s
  /// format falls back to 1 on the same write — see [_formatToWrite] — so an
  /// older Openote can use the registry again instead of holding it read-only.
  ///
  /// **The one thing it cannot undo is the page snapshots**, and it does not
  /// pretend to: `page_versions` was dropped and the log has never held a page
  /// history, so there is nothing to restore from. That is why the dialog says
  /// it before the button is pressed rather than here afterwards.
  ///
  /// Same commit order as [demoteContainerToCache], for the same reason: copy,
  /// registry, delete.
  Future<ContainerDemotion> undemoteContainerFromCache(String notebookId) async {
    ContainerDemotion refuse(String why, [String? details]) =>
        ContainerDemotion(refusal: why, details: details);

    final ref = notebooks.where((n) => n.id == notebookId).firstOrNull;
    if (ref == null) {
      return refuse('That notebook is not open, so there is nothing to change.');
    }
    if (!isDemoted(ref)) {
      return refuse('This notebook is already stored the old way. Nothing has '
          'been changed.', 'not a working copy: ${ref.file}');
    }
    if (reclaimInProgress) {
      return refuse(
          'Openote is already tidying up a notebook. Let that finish first.',
          'marker: ${readReclaimMarker()}');
    }
    if (registryReadOnly != null) {
      return refuse(
          'Your list of notebooks was last used by a newer version of Openote, '
          'so this one is only reading it. Nothing has been changed.',
          registryReadOnly!.details);
    }
    final file = File(ref.file);
    if (!file.existsSync()) {
      return refuse(
          'Openote cannot find this notebook at the moment, so it has not '
          'changed anything.',
          'no file at ${ref.file}');
    }
    final wal = File('${ref.file}-wal');
    final before = file.lengthSync();
    final walBefore = wal.existsSync() ? wal.lengthSync() : 0;
    final need = (before + walBefore) * 2;
    final free = FreeSpace.bytesFor(ref.file);
    if (free == null || free < need) {
      return refuse(
          'There is not enough free space to do this safely. It needs '
          '${_mbUp(need)} free for a moment while it works. Nothing has been '
          'changed.',
          'need ${need}B, free ${free ?? -1}B');
    }

    final oldFile = ref.file;
    final dest = _freeNotebookPath(ref.title);
    _writeReclaimMarker(notebookId, 'undemote-from-cache');
    var committed = false;
    try {
      final open = _open.remove(notebookId);
      checkpointAndClose(open ??
          openExistingOnote(ref.file, notebookId: notebookId, title: ref.title));
      _decodedPages.remove(notebookId);

      await file.copy(dest);
      if (!sameBytes(oldFile, dest)) {
        throw StateError('the copy of the notes file did not complete');
      }
      final fresh =
          openExistingOnote(dest, notebookId: notebookId, title: ref.title);
      try {
        fresh.execute('PRAGMA user_version = $onoteFormatMajor;');
      } finally {
        checkpointAndClose(fresh);
      }

      // [NotebookRef.logDir] stays exactly as it is rather than being cleared
      // back to null. The notes folder has not moved, `_freeNotebookPath` may
      // not hand back the name it originally had (the title can have changed,
      // or something else can be sitting on the name), and every build ever
      // released reads this field — so naming it is right and deriving it is a
      // guess.
      ref.file = dest;
      await _saveNow();
      committed = true;

      try {
        cacheDirFor(notebookId).deleteSync(recursive: true);
      } catch (_) {/* [_settleDemotion] drops it at the next start */}

      // Last, and only once the notebook is where an older build looks for it:
      // an older build reads pictures by following `blob_refs` into `blobs`, so
      // this is what makes them render rather than come up empty.
      final back = await refillContainerBlobs(notebookId);
      debugPrint('[openote/store] $notebookId: $oldFile → $dest, '
          '${back.restored} picture(s) put back');
      return ContainerDemotion(
        done: true,
        from: oldFile,
        to: dest,
        blobsRestored: back.restored,
        bytes: File(dest).existsSync() ? File(dest).lengthSync() : 0,
        details: back.missing.isEmpty
            ? null
            : '${back.missing.length} picture(s) had no good copy in the '
                "notebook's folder: ${_fewHashes(back.missing.toList())}",
      );
    } catch (e) {
      if (!committed) {
        ref.file = oldFile;
        try {
          if (File(dest).existsSync()) _deleteContainerFiles(dest);
        } catch (_) {/* the leftovers scan reports it */}
      }
      return refuse(
          'Openote could not put this notebook back the old way. Your notes '
          'have not been changed — everything is still where it was.',
          '$e');
    } finally {
      _clearReclaimMarker();
    }
  }

  /// Pages per transaction during a rebuild. The same order of magnitude as the
  /// sync pull's chunk, and for the same reason: big enough that transaction
  /// overhead is noise, small enough that one rollback is not the whole
  /// notebook.
  static const int _rebuildPageChunk = 64;

  /// Stop listing differences after this many. The list is for a person to
  /// read in the Advanced fold; on a notebook the log has never described it
  /// would otherwise be one line per page.
  static const int _rebuildDiffCap = 200;

  /// Everything the container holds that replaying its log does not reproduce.
  ///
  /// **The comparison of record.** Deliberately the same one
  /// `SyncRecorder.verifyPage` has made since shadow mode shipped — canonical
  /// page JSON with blocks keyed by id — because that is the property three
  /// investigation passes measured on the owner's real notebooks (329 of 329
  /// pages, 328 of 328, 14 of 14) and a second, subtly different comparison
  /// here would be a second chance to be wrong.
  ///
  /// **Blocks are compared as a set keyed by id, not as a list.** The container
  /// stores whatever order the app's list happened to be in, which carries no
  /// meaning — render order is the `z` field, and flow order is `y`
  /// (`AppState`'s flow restack sorts on it) — while a replay can only
  /// reconstruct them in id order. Comparing positions would report differences
  /// that are not differences. Every other field, including `createdAt`,
  /// `updatedAt` and `deletedAt`, is compared exactly.
  ///
  /// Page-level equality is **not** enough on its own and this is the single
  /// most important sentence about it: `page_mirror` names a picture by hash,
  /// so a page whose blob bytes have been destroyed is byte-identical to the
  /// same page with its bytes intact. A spike proved that the hard way — 329 of
  /// 329 pages "identical" over 278 hashes with no bytes anywhere and 193 broken
  /// image blocks. Gate 4 in [rebuildContainerFromLog] re-hashes the files; this
  /// is only the half that compares structure and content.
  List<String> _rebuildDifferences(Database db, Materializer state) {
    final out = <String>[];
    for (final r in db.select('SELECT id,kind,parent_id,title,position,color,'
        'level,created_at,updated_at,deleted_at FROM nodes')) {
      final id = r['id'] as String;
      final n = state.nodes[id];
      if (n == null) {
        out.add('$id: in the notebook, absent from its history');
        if (out.length >= _rebuildDiffCap) return out;
        continue;
      }
      // **Through the enum, not as raw strings.** Until v0.17 Step 3 the writer
      // spelled a section group the Dart way — `sectionGroup` — while the
      // container's own CHECK constraint says `section_group`, and Step 3
      // fixed the writer while promising the reader accepts both forever. So
      // every log written before that release carries the old spelling, and a
      // raw comparison reports a difference that is not one: measured on the
      // owner's real 329-page notebook, exactly 6 nodes of 360, which is the
      // count the plan's own §2.2 recorded.
      final kindNow = nodeKindFromWire(n.kind);
      final was = <String, Object?>{
        'kind': nodeKindFromWire(r['kind'] as String)?.name ?? r['kind'],
        'parentId': r['parent_id'],
        'title': r['title'],
        'position': r['position'],
        'color': r['color'],
        'level': r['level'],
        'createdAt': r['created_at'],
        'updatedAt': r['updated_at'],
        'deletedAt': r['deleted_at'],
      };
      final now = <String, Object?>{
        'kind': kindNow?.name ?? n.kind,
        'parentId': n.parentId,
        'title': n.title,
        'position': n.position,
        'color': n.color,
        'level': n.level,
        'createdAt': n.createdAt,
        'updatedAt': n.updatedAt,
        'deletedAt': n.deletedAt,
      };
      for (final k in was.keys) {
        if (canonicalJson(was[k]) != canonicalJson(now[k])) {
          out.add('$id.$k: notebook ${was[k]}, history ${now[k]}');
          if (out.length >= _rebuildDiffCap) return out;
        }
      }
    }
    for (final r in db.select('SELECT page_id,json FROM page_mirror')) {
      final pid = r['page_id'] as String;
      String fromContainer;
      try {
        final m = (jsonDecode(r['json'] as String) as Map).cast<String, dynamic>();
        final blocks = [
          for (final b in (m['blocks'] as List? ?? const [])) b as Map
        ]..sort((a, b) =>
            (a['id'] as String? ?? '').compareTo(b['id'] as String? ?? ''));
        fromContainer = canonicalJson({
          'schema': 'onote-page/1',
          'pageId': pid,
          'page': m['page'] ?? <String, dynamic>{},
          'blocks': blocks,
        });
      } catch (e) {
        // Unreadable stored JSON is a difference, not a pass. A page this
        // cannot decode is one nothing can prove the replay reproduces, and
        // waving it through is how a corrupt page becomes an empty one.
        out.add('$pid: the stored page could not be read ($e)');
        if (out.length >= _rebuildDiffCap) return out;
        continue;
      }
      if (canonicalJson(state.pageMirror(pid)) != fromContainer) {
        out.add('$pid: rebuild-from-log does not match the stored page');
        if (out.length >= _rebuildDiffCap) return out;
      }
    }
    return out;
  }

  /// The mime a blob's bytes announce.
  ///
  /// The `blobs` row carried one and the reclaim deleted it with the row, so on
  /// the way back it is read from the content. Only [blobIndex] — the Step 5
  /// backfill — ever consumes it, so an unrecognised type costs a generic
  /// label and nothing else; guessing wrong from a filename would cost more.
  static String _sniffMime(Uint8List b) {
    bool starts(List<int> magic, {int at = 0}) {
      if (b.length < at + magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (b[at + i] != magic[i]) return false;
      }
      return true;
    }

    if (starts([0x89, 0x50, 0x4e, 0x47])) return 'image/png';
    if (starts([0xff, 0xd8, 0xff])) return 'image/jpeg';
    if (starts([0x47, 0x49, 0x46, 0x38])) return 'image/gif';
    if (starts([0x52, 0x49, 0x46, 0x46]) &&
        starts([0x57, 0x45, 0x42, 0x50], at: 8)) {
      return 'image/webp';
    }
    if (starts([0x4f, 0x49, 0x53, 0x31])) return inkMimeType; // 'OIS1'
    return 'application/octet-stream';
  }

  static int _count(Database db, String table) =>
      db.select('SELECT count(*) c FROM $table').first['c'] as int;

  /// How many blob files one background hash costs, matching
  /// `SyncRecorder._proveBatch`: big enough that isolate spawn is noise against
  /// the hashing, small enough that a batch of huge ink blobs cannot make the
  /// app feel stuck.
  static const int _hashBatch = 32;

  /// Read and SHA-256 each path off this isolate. Measured on the owner's
  /// Honours-4: re-hashing all 488 blobs is 2.8 s of CPU, and its worst single
  /// file — 1.8 MB of binary ink — is a 164 ms block that no per-file yield can
  /// divide. Null for anything unreadable, which matches no hash.
  static Future<List<String?>> _hashFiles(List<String> paths) =>
      Isolate.run(() => [
            for (final path in paths)
              () {
                try {
                  return sha256Hex(File(path).readAsBytesSync());
                } catch (_) {
                  return null;
                }
              }()
          ]);

  /// A few hashes for the Advanced fold — never the whole list, which on a
  /// broken import is hundreds of lines.
  static String _fewHashes(List<String> h) =>
      h.isEmpty ? 'none' : '${h.length}: ${h.take(5).join(', ')}';

  static String _mb(int b) => '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';

  /// [_mb] rounded **up**, for a figure the user has to reach rather than one
  /// they already have. See the refusal in [rebuildContainerFromLog].
  static String _mbUp(int b) {
    final mb = b / (1024 * 1024);
    return '${((mb * 10).ceil() / 10).toStringAsFixed(1)} MB';
  }

  /// A free `<base>.onotebook` directory in the workspace, for a notebook
  /// arriving as logs rather than as a container.
  String freeLogDirPath(String title) {
    var base = title.replaceAll(RegExp(r'[^\w\- ]'), '').trim();
    if (base.isEmpty) base = 'Notebook';
    var dir = p.join(workspaceDir.path, '$base.onotebook');
    var i = 2;
    while (Directory(dir).existsSync()) {
      dir = p.join(workspaceDir.path, '$base-$i.onotebook');
      i++;
    }
    return dir;
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

  /// Copy a notebook, contents and all. The container is byte-copied — pages,
  /// text and the derived history index travel exactly — and so are the two
  /// directories that hold content BESIDE the log rather than inside the
  /// container: `media/` (recordings) and `blobs/` (picture bytes, which from
  /// v0.17 Step 6 live only there). `ops/` deliberately does not travel: the
  /// logs are the history of the notebook they were written for and must not
  /// be inherited by a new id. The copy gets a fresh workspace id; its
  /// internal `notebook_id` metadata is rewritten so the two don't collide
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
    // **Stamped back down to a notebook file.** Duplicating a MIGRATED notebook
    // byte-copies a container stamped [onoteWorkingCopyVersion] to an ordinary
    // `.onote` in the workspace — and `isOpenoteWorkingCopy` reads that stamp
    // straight out of the file header to decide whether a double-clicked file is
    // Openote's own cache. Left as it was, every duplicate of a migrated
    // notebook would be a v2 file that is not a cache, which breaks the one
    // invariant that test stands on and would make the copy refuse to open on a
    // build that predates v0.17.
    //
    // **Checkpointed straight away**, because `user_version` is a field in the
    // 100-byte file HEADER and in WAL mode a changed header sits in the `-wal`
    // until something folds it back in. `isOpenoteWorkingCopy` reads that header
    // directly, with nothing opened — so without this line a duplicate copied
    // onto a USB stick before the app next closed would still say v2 on disk,
    // and every build, old and new, would refuse the file.
    db.execute('PRAGMA user_version = $onoteFormatMajor;');
    db.execute('PRAGMA wal_checkpoint(TRUNCATE);');
    db.execute(
        "INSERT INTO notebook_meta(key,value) VALUES('notebook_id',?) "
        'ON CONFLICT(key) DO UPDATE SET value=excluded.value',
        [jsonEncode(newId0)]);
    db.execute(
        "INSERT INTO notebook_meta(key,value) VALUES('title',?) "
        'ON CONFLICT(key) DO UPDATE SET value=excluded.value',
        [jsonEncode(newTitle)]);
    _open[newId0] = db;
    // Videos are files beside the container, not rows inside it, so copying
    // the container alone would give you a duplicate whose recordings had
    // silently vanished. Only `media/` — the op logs belong to the notebook
    // they were written for and must not be inherited by a new id.
    final srcMedia = Directory(p.join(src.logDirPath, 'media'));
    if (srcMedia.existsSync()) {
      await _copyDirectory(
          srcMedia, Directory(p.join(ref.logDirPath, 'media')));
    }
    // Pictures are the same shape one step further out: from v0.17 Step 6 a
    // pasted image's bytes live ONLY in `blobs/` beside the log — the
    // container's `blobs` table is empty — so a duplicate made from the
    // container and `media/` alone rendered every picture blank, and for a
    // demoted notebook that is every picture it has. The duplicate's `logDir`
    // is null, so its `logDirPath` is the fresh `.onotebook` beside the new
    // container; [_copyDirectory] hash-verifies each file on the way in,
    // which matters more than usual because this is the copy's only copy from
    // birth. The source's `blobs/` is found through ITS `logDirPath`, which
    // is what makes the same line serve a shared or demoted source too.
    final srcBlobs = Directory(p.join(src.logDirPath, 'blobs'));
    if (srcBlobs.existsSync()) {
      await _copyDirectory(
          srcBlobs, Directory(p.join(ref.logDirPath, 'blobs')));
    }
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
  ///
  /// **And "another notebook" includes another COMPUTER.** `_logDirIsShared`
  /// only ever asked this workspace, which cannot see the other device at all,
  /// so purging a folder-joined notebook deleted the shared `.onotebook`
  /// outright — the other machine's `<device>.oplog` and every blob in it —
  /// while leaving the shared `.onote` behind, because on a joined notebook
  /// `ref.file` names this device's PRIVATE copy in the workspace and the
  /// shared container was never a registry entry at all. Measured, and it is
  /// the on-disk state the report described: `G:\My Drive\Openote` held
  /// `Eric - Computing Science Honours.onote` (35.9 MB) with its `-wal` and
  /// `-shm` and **no `.onotebook`** — a dead container the setup screen then
  /// offered as a notebook to join. Exactly the wrong half of the pair was
  /// removed, and the half that survived was the one nobody could use.
  ///
  /// See [_mayDeleteLogDir] for the rule that replaced it, and note the sync
  /// dialog's leftovers panel already reasoned this way — it refuses to delete
  /// anything outside the workspace because "a leftover in a SHARED folder may
  /// be another device's notebook". Purge simply did not agree with it.
  Future<void> purgeNotebook(String id) async {
    final i = trashedNotebooks.indexWhere((n) => n.id == id);
    if (i < 0) return;
    final ref = trashedNotebooks.removeAt(i);
    _open.remove(id)?.dispose();
    _decodedPages.remove(id);
    _deleteContainerFiles(ref.file);
    // The cache directory too, and unconditionally: it is named by THIS
    // notebook's id and nothing else can ever be in it, so a purge that left it
    // would strand a whole container the way purge used to strand `.onotebook`
    // directories. Harmless when the notebook was never migrated — there is
    // nothing there.
    try {
      final cache = cacheDirFor(id);
      if (cache.existsSync()) cache.deleteSync(recursive: true);
    } catch (_) {/* a lock or a permission must not fail the purge */}
    if (_mayDeleteLogDir(ref)) {
      try {
        final logs = Directory(ref.logDirPath);
        if (logs.existsSync()) logs.deleteSync(recursive: true);
      } catch (_) {/* a lock or a permission must not fail the purge */}
    }
    await _saveNow();
  }

  /// A container and the two files SQLite keeps beside it.
  ///
  /// Deleting the `.onote` alone strands its `-wal` and `-shm`, and they are
  /// not small: the real workspace held a 32 KB `-shm` and a 4.1 MB `-wal` for
  /// a notebook that no longer existed, and `findOrphanFiles` had to grow a
  /// case for them because nothing ever cleaned them up at the source. The
  /// `-wal` is the worse of the two — it holds committed pages that never made
  /// it into the main file, so a stranded one is real content in a file
  /// nothing will ever open again.
  static void _deleteContainerFiles(String container) {
    for (final path in [container, '$container-wal', '$container-shm']) {
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {/* best-effort; the workspace entry is already gone */}
    }
  }

  /// Whether this device owns [ref]'s log directory outright, and may delete
  /// it.
  ///
  /// Two shapes are private to this machine and safe to remove:
  ///
  ///   * **inside the workspace** — [freeLogDirPath] puts a git-cloned
  ///     notebook's logs there, and a local notebook's logs are simply its
  ///     container's sibling; nothing else can be writing to them; and
  ///   * **a directory holding nobody's log but ours.** A log file is named
  ///     after the device that writes it and exactly one device ever appends
  ///     to it, so "every `*.oplog` under `ops/` is this installation's" means
  ///     there is no other machine's history in there to lose.
  ///
  /// Anything else means other machines write their own files into that
  /// directory and it is not ours to remove. Purging then means "take it off
  /// this computer" — which is what the user asked for, and all we can
  /// honestly deliver.
  ///
  /// **Amended for v0.17 Step 4.** The second rule used to be "the sibling of
  /// this notebook's own container", on the reasoning that a device which
  /// *moved* its notebook into Drive sent the container and the logs there
  /// together. Step 4 stops the container going, so that test now answers
  /// "someone else's" for every notebook this device shared itself — which
  /// would strand this machine's own `.onotebook` in Drive for ever, the exact
  /// leftover [purgeNotebook] was written to stop. Asking whose logs are in
  /// there is a stronger rule than the pairing was in any case: it also
  /// refuses when a second computer has joined a folder this device created,
  /// which the old rule got wrong in the dangerous direction.
  bool _mayDeleteLogDir(NotebookRef ref) {
    if (_logDirIsShared(ref)) return false;
    final logs = ref.logDirPath;
    if (p.isWithin(workspaceDir.path, logs)) return true;
    return _logsAreAllOurs(logs);
  }

  /// Whether every device log in [logDir] was written by this installation.
  ///
  /// A listing, never an open: this runs on a directory in someone's Drive and
  /// answering the question must not create a file there.
  ///
  /// An empty `ops/` is ours (there is nothing to lose). A workspace with no
  /// device id has never recorded anything, so any log it finds belongs to
  /// somebody else — and an unreadable directory is not one to start deleting
  /// from.
  bool _logsAreAllOurs(String logDir) {
    try {
      final ops = Directory(p.join(logDir, 'ops'));
      if (!ops.existsSync()) return true;
      final mine = getSetting(DeviceIdentity.settingsKey) as String?;
      for (final f in ops.listSync(followLinks: false).whereType<File>()) {
        if (p.extension(f.path) != '.oplog') continue;
        if (p.basenameWithoutExtension(f.path) != mine) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Whether deleting [id] for good would leave a shared folder untouched.
  ///
  /// The confirmation dialog needs this BEFORE the click: "and all its pages
  /// will be removed for good" is a promise this cannot keep for a notebook
  /// joined from a folder, and saying so is the difference between a user who
  /// thinks their notes are gone everywhere and one who knows where they are.
  bool purgeKeepsSharedFolder(String id) {
    final ref = [...notebooks, ...trashedNotebooks]
        .where((n) => n.id == id)
        .firstOrNull;
    return ref != null && !_mayDeleteLogDir(ref);
  }

  /// Remove a live notebook and its files outright, bypassing the recycle bin.
  ///
  /// For a notebook that was never the user's — the half-built target of a
  /// cancelled or crashed import. The recycle-bin route is wrong for it twice
  /// over: it would offer to restore half a notebook, and `deleteNotebook`
  /// refuses the *last* notebook (there is always somewhere to be), so on a
  /// workspace with nothing else in it a cancelled import was silently kept.
  Future<void> discardNotebook(String id) async {
    final i = notebooks.indexWhere((n) => n.id == id);
    if (i < 0) return;
    trashedNotebooks.add(notebooks.removeAt(i));
    await purgeNotebook(id);
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
    final db = _db(notebookId);
    db.execute(
        'DELETE FROM nodes WHERE deleted_at IS NOT NULL AND deleted_at < ?',
        [_retentionCutoff()]);
    // **There is no `page_versions` sweep here any more** (plan decision 1).
    // This used to be the other half of the hole [NotebookWriter.purgeNode]
    // closed — the table declared no foreign key onto `nodes`, so an expired
    // page's snapshots outlived it for good, measured at 1,002,020 leaked bytes
    // for one expired page of average size. `block_authors` declares the
    // `ON DELETE CASCADE` the old table never did and `recent_deletions`' cap of
    // ten is its own prune, so the leak is designed out rather than swept up.
    //
    // …and the same for the copy of the page that lives in memory. This method
    // evicted nothing at all, which is the same hole [purgeNode] had for its
    // subtree, only wider: it names no ids, so a page whose retention ran out
    // stayed in `_decodedPages` in full. Measured: read a page, trash it,
    // backdate it past the window, run this — `readPageShared` still returned
    // its blocks while `readPage` returned nothing. Nobody has to press
    // anything for that; this runs by itself at startup.
    //
    // The orphan predicate again rather than a list of ids, for the reason
    // above: the DELETE takes whole subtrees through the cascade and never
    // names what it took. Safe as an eviction rule because `page_mirror.page_id`
    // is `REFERENCES nodes(id)` with `foreign_keys=ON` — a cached page with no
    // `nodes` row has no stored JSON either, so the only thing it can be
    // holding is a dead page or the empty one [readPage] returns for a missing
    // row, and both are re-read for free.
    final cached = _decodedPages[notebookId];
    if (cached == null || cached.isEmpty) return;
    final live = {
      for (final r in db.select('SELECT id FROM nodes')) r['id'] as String
    };
    cached.removeWhere((id, _) => !live.contains(id));
  }

  // ── Tree nodes ─────────────────────────────────────────────────────────

  List<TreeNode> loadNodes(String notebookId) =>
      _writer(notebookId).loadNodes();

  TreeNode upsertNode(String notebookId, TreeNode n) =>
      _writer(notebookId).upsertNode(n);

  /// Does this container hold a row for [nodeId] — deleted or not?
  ///
  /// Deliberately NOT `loadNodes().any(...)`: that returns only live nodes,
  /// and the question every caller here is actually asking is "will a foreign
  /// key onto `nodes(id)` be satisfied", which a soft-deleted row satisfies
  /// perfectly well. Used by the sync pull to decide whether a page it is
  /// about to mirror has somewhere to hang; see `_syncPullLocked`.
  bool hasNode(String notebookId, String nodeId) =>
      _db(notebookId).select('SELECT 1 FROM nodes WHERE id=?', [nodeId]).isNotEmpty;

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
  ///
  /// **[at] exists so the container and the log can agree.** They used to take
  /// two independent `nowMs()` readings for one deletion — this one, and
  /// `SyncRecorder.nodeDeleted`'s `at ?? nowMs()` — so whenever the pair
  /// straddled a millisecond boundary the notebook and its history recorded
  /// different deletion times. Nothing compared them until
  /// [rebuildContainerFromLog] did, and then the rebuild refused, at random, on
  /// any notebook with something in its recycle bin. It also meant the thirty-
  /// day retention promise was measured from a different instant on each side,
  /// and that a delete folded in from another device was stamped with THIS
  /// device's clock rather than the one the log recorded.
  void softDeleteNode(String notebookId, String nodeId, {int? at}) {
    final db = _db(notebookId);
    final ts = at ?? nowMs();
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

  /// Permanently delete a node and its subtree. The FK cascade clears
  /// `page_mirror`, `blob_refs` and `block_authors`; [NotebookWriter.purgeNode]
  /// is still the funnel rather than here because the import writer calls it
  /// directly, from its own isolate.
  void purgeNode(String notebookId, String nodeId) {
    // A purged page must not survive in the decoded cache: a page recreated
    // later under the same id (a restore, a sync replay) would read as its
    // dead predecessor.
    //
    // **Every id the purge took, not just the one we named.** `nodes.parent_id`
    // is `REFERENCES nodes(id) ON DELETE CASCADE`, so purging a SECTION deletes
    // its pages' rows without those page ids passing through here — and the
    // recycle bin purges sections, which is the common case rather than the
    // rare one. Evicting only [nodeId] left every page inside it cached:
    // measured, purging a section and then asking `readPageShared` for a page
    // that had been inside it returned that page's pre-purge blocks, while
    // `readPage` — the same page, straight from SQLite — correctly returned
    // nothing. Recreate the id from a device that never saw the purge
    // (`Materializer` handles `nodePurge` with a bare `nodes.remove` and keeps
    // no tombstone) and the new page reads as the dead one. This is the same
    // cascade blind spot 1be2d28 closed for `page_versions`, through the same
    // `_subtree` walk — which [NotebookWriter.purgeNode] now returns rather
    // than have a second one written here.
    final purged = _writer(notebookId).purgeNode(nodeId);
    final cached = _decodedPages[notebookId];
    if (cached == null) return;
    for (final id in purged) {
      cached.remove(id);
    }
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

  // ── Version history ────────────────────────────────────────────────────
  //
  // **`page_versions` is gone, and with it `maybeSnapshotVersion`,
  // `listVersions` and `versionJson`** (v0.17 plan, decision 1). The table
  // stored up to thirty complete copies of every page and was bounded by how
  // long a notebook had been edited, i.e. by nothing — `database.dart` records
  // 9,840 snapshots in a 322 MB container as the worst shape the owner's
  // 328-page notebook could reach. What replaces it is below, and the plain
  // statement of what a student loses is in the plan's Step 8a: they can see who
  // last changed each thing on a page and get back the last ten notable
  // deletions; they cannot wind a page back to how it looked at 09:40.
  //
  // Removing the READS as well as the writes is deliberate rather than tidy.
  // The schema no longer creates the table, so a read left behind would throw on
  // every notebook made from here on — which is exactly the "left pointing at a
  // table that is gone" the plan warns about. Rows already on disk are inert
  // until `demoteContainerToCache` drops them.

  // ── Simplified version history (v0.17 plan, Step 8a) ──────────────────
  //
  // Two thin delegates, and deliberately nothing more. All the behaviour is in
  // `history_store.dart` and `model/history.dart`; this class owns the one
  // thing they cannot reach, which is the container handle.

  /// The derived attribution index and ten-deep deletion list, read back out of
  /// [notebookId]'s container.
  NotebookHistory loadHistory(String notebookId) =>
      HistoryStore(_db(notebookId)).load();

  /// Persist whatever [history] has folded since its last flush. Returns rows
  /// touched — one per op the save was already recording, which is the "this
  /// is free" claim made countable.
  int flushHistory(String notebookId, NotebookHistory history) =>
      HistoryStore(_db(notebookId)).flush(history);

  /// Distinct pages that link to [pageId] (backlinks, TEXT-8).
  List<String> backlinkPageIds(String notebookId, String pageId) {
    final rows = _db(notebookId).select(
        'SELECT DISTINCT src_page_id FROM refs '
        'WHERE dst_page_id=? AND src_page_id<>?',
        [pageId, pageId]);
    return [for (final r in rows) r['src_page_id'] as String];
  }

  // ── Page content (mirror-write mode, spec §4) ──────────────────────────

  /// How many times a page has been read and decoded out of SQLite — cache
  /// misses, in effect, since [readPageShared] only lands here when it has
  /// nothing cached. For tests that assert caching by COUNT: the wall-clock
  /// versions measured how busy the CI runner was, not whether the cache
  /// worked, and failed on loaded macOS/Linux runners while the cache was
  /// doing its job perfectly.
  static int debugPageDecodes = 0;

  PageData readPage(String notebookId, String pageId) {
    debugPageDecodes++;
    final rows = _db(notebookId)
        .select('SELECT json FROM page_mirror WHERE page_id=?', [pageId]);
    if (rows.isEmpty) return PageData([], PageProps());
    final data = _decodePage(rows.first['json'] as String);
    // **Ink comes back out of its blob here.** Every consumer above this line —
    // the painter, the eraser, lasso, drag, resize, the three exporters —
    // keeps seeing the stroke list it has always seen. Only what is written to
    // disk changed, which is where the 63 MB was.
    //
    // A page with no ink pays nothing: `workingAll` returns the same list
    // object when it changed nothing.
    return PageData(
      InkStorage.workingAll(data.blocks, (h) => getBlob(notebookId, h)),
      data.props,
    );
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
  /// How many times a caller has asked for a page through the shared cache.
  ///
  /// Distinct from [debugPageDecodes], and the distinction is the whole point.
  /// That one counts cache MISSES at this layer, so it answers "did we hit
  /// SQLite?" — which a small fixture never does twice however broken the
  /// callers are. This one counts the ASK, which is what the per-keystroke
  /// caches upstream (deck counts, the tag rollup, the planner agenda) exist to
  /// avoid making at all: each of them walks every page in the notebook, and a
  /// cache that stopped holding would show up here as hundreds of reads and in
  /// `debugPageDecodes` as zero.
  ///
  /// Found by writing the assertion the other way round first: a test that
  /// required the decode counter to MOVE when a deck was invalidated failed,
  /// which is what exposed the zero it was pairing with as vacuous.
  static int debugSharedPageReads = 0;

  PageData readPageShared(String notebookId, String pageId) {
    debugSharedPageReads++;
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

  /// Pages that still hold their handwriting as inline JSON stroke arrays.
  ///
  /// A SQL prefilter, for the reason spelled out above [pageIdsWithTags]:
  /// decoding all 328 pages of a real notebook to discover that 215 have no ink
  /// is most of the work for none of the win. `"strokes":[{` is deliberately
  /// narrower than `"strokes"` — it excludes an empty array and excludes an
  /// already-converted page, so the conversion is re-runnable and a second run
  /// finds nothing.
  List<String> pageIdsWithInlineInk(String notebookId) => [
        for (final r in _db(notebookId).select(
            'SELECT page_id FROM page_mirror WHERE json LIKE ?',
            const [r'%"strokes":[{%']))
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

  /// Every scrap of page content this container holds, as raw JSON text.
  ///
  /// For the video sweep, which has to answer "does anything anywhere still
  /// name this file?" and where a missed reference deletes a lecture. Three
  /// deliberate choices, each of which is a way the obvious query would be
  /// wrong:
  ///
  ///  * **No `deleted_at` filter.** A page in the recycle bin keeps its
  ///    `page_mirror` row untouched — only `nodes.deleted_at` is stamped — and
  ///    it can be restored for thirty days. The usual
  ///    `WHERE deleted_at IS NULL` would hide precisely the pages whose videos
  ///    look unused, which is the deleted-page-comes-back-empty shape.
  ///  * **No `page_versions` any more, and that is a reduction in pinning
  ///    rather than a hole.** This used to yield up to thirty autosnapshots per
  ///    page as well, so a video removed from a page this morning was still
  ///    named by every snapshot taken before that — for ever, on a single-device
  ///    notebook, because a snapshot is only evicted when thirty newer ones of
  ///    the *same* page exist. Plan decision 1 dropped the table and put
  ///    `recent_deletions`' ten-deep list in its place as an explicit, bounded
  ///    garbage-collection root: [MediaGc] reads its `pins` column, so a video
  ///    in the last ten notable deletions is still safe and one that has fallen
  ///    off the end becomes reclaimable after `kVideoReclaimMinimumAge` — which
  ///    is what that constant was written to be.
  ///  * **Raw text, not decoded pages.** Decoding asks the schema's question;
  ///    the sweep needs the bytes' question. It is also what keeps this from
  ///    materialising a notebook's worth of `Block` objects to look for one
  ///    string.
  ///
  /// Lazy: the caller stops as soon as every candidate has been accounted for.
  Iterable<String> everyStoredPageText(String notebookId) sync* {
    final db = _db(notebookId);
    for (final r in db.select('SELECT json FROM page_mirror')) {
      yield r['json'] as String;
    }
  }

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

  /// Where this notebook's blob **bytes** live: `<log dir>/blobs/<sha256>`.
  ///
  /// Built per call rather than cached, for the same reason [_writer] is: the
  /// answer moves under us. `moveNotebookTo` and `adoptLogDirectory` both
  /// rewrite [NotebookRef.logDir], and a cached store would go on writing
  /// pictures into the folder the notebook used to be in.
  OpLogStore _blobStore(String notebookId) {
    final nb = notebooks.firstWhere((n) => n.id == notebookId);
    return OpLogStore.forNotebook(nb.file, logDir: nb.logDir);
  }

  /// Store bytes and return their content hash. **The container is not
  /// touched** (v0.17 Step 6).
  ///
  /// The hash is derived from the bytes, never taken on trust, because that is
  /// the whole of content-addressing: the same picture must produce the same
  /// filename on every device, which is what lets blobs skip merging.
  ///
  /// Deliberately not routed through the op-log recorder. The recorder writes
  /// the same file (idempotently) *and* records the `blob.put` op, but
  /// `AppState._recorderFor` can legitimately return null — a log that would
  /// not open, logging switched off in a test — and after Step 6 that would
  /// mean bytes landing nowhere at all. The op can be missed and recovered; the
  /// bytes cannot.
  String putBlob(String notebookId, Uint8List bytes, String mime) {
    final hash = sha256Hex(bytes);
    _blobStore(notebookId).writeBlob(hash, bytes);
    return hash;
  }

  /// Write a blob the way builds before v0.17 Step 6 did: into the container's
  /// `blobs` table, and nowhere else.
  ///
  /// **The only way left to construct the state every existing notebook is
  /// actually in**, which is the state Step 6's read path exists for — Step 5
  /// measured 378 of 488 blobs on the owner's own notebooks with bytes here and
  /// no file. [putBlob] cannot build it any more, so without this the backfill,
  /// the repair and the read-through fallback would all be tested only against
  /// notebooks that never had the problem.
  ///
  /// Test-only, and deliberately so: nothing that ships may put bytes back into
  /// the container. (Step 7's `refillContainerBlobs` inverse will need this
  /// same statement, and this is where it starts.)
  @visibleForTesting
  String putContainerBlobForTest(
      String notebookId, Uint8List bytes, String mime) {
    final hash = sha256Hex(bytes);
    _db(notebookId).execute(
        'INSERT OR IGNORE INTO blobs(hash,bytes,mime,size,created_at) '
        'VALUES(?,?,?,?,?)',
        [hash, bytes, mime, bytes.length, nowMs()]);
    return hash;
  }

  /// Bytes of a blob: `blobs/` first, the container's legacy `blobs` table
  /// second (v0.17 Step 6).
  ///
  /// **The fallback is the whole point of shipping Step 6 before Step 7.** Step
  /// 5 measured 378 of 488 blobs missing from `blobs/` on the owner's own
  /// notebooks; they are backfilled in the background on first open, so for the
  /// first few seconds of every upgraded notebook's life a read that finds no
  /// file is *normal* and the bytes are still in the container. Reading
  /// file-only would blank those pictures for the duration of the backfill;
  /// reading table-first would leave the file path untested in the field, which
  /// is exactly what this step exists to test.
  ///
  /// **Every fallback is recorded**, because Step 7 empties the table: a hash
  /// in [blobsServedFromContainer] is a picture that would come up blank the
  /// day that happens, and a migration must refuse while any remain. Silence
  /// here is the failure mode a spike already reproduced — `MIGRATION COMPLETE`
  /// over 193 destroyed image blocks.
  ///
  /// **Not verified on read — except for hashes on the held register.**
  /// Re-hashing costs 2.8 s across a real notebook's 488 blobs, which cannot
  /// be paid per repaint. `SyncRecorder.proveBlobs` (Step 5) is the verifier
  /// and it runs at every open; the sync pull checks each blob file that was
  /// present when its op folded, and puts every one it could NOT vouch for —
  /// not arrived yet, or holding the wrong bytes — on [holdBlobUntilVerified]'s
  /// register. A held hash is the one case this method re-hashes: once, here,
  /// before the file is first served, which is what covers the
  /// documented-normal log-before-picture ordering where the file lands
  /// AFTER its op has folded and no later pull would ever name it again.
  Uint8List? getBlob(String notebookId, String hash) {
    final bare = hash.replaceFirst('sha256:', '');
    final fromFile = _trustedBlobFile(notebookId, bare);
    if (fromFile != null) {
      // Both registers are "as of now", not "ever": the backfill and a cloud
      // client both land files while the app is running, and a Step 7 gate that
      // could never be cleared without a restart would refuse for ever.
      _blobsFromContainer[notebookId]?.remove(bare);
      _blobsNowhere[notebookId]?.remove(bare);
      return fromFile;
    }
    final bytes = containerBlob(notebookId, bare);
    final seen = (bytes == null ? _blobsNowhere : _blobsFromContainer)
        .putIfAbsent(notebookId, () => <String>{});
    if (seen.add(bare)) {
      debugPrint(bytes == null
          ? '[openote/store] blob $bare has no bytes in $notebookId — not in '
              "the notebook's folder and not in the notebook file"
          : '[openote/store] blob $bare came from the notebook file; the copy '
              "in the notebook's folder is not there yet");
    }
    return bytes;
  }

  /// [OpLogStore.readBlob], gated by the held register.
  ///
  /// A hash that is not held reads straight through — the common case, and it
  /// must stay free of hashing. A held hash is re-verified first and released
  /// the moment its file passes, so the register clears itself when the
  /// backfill, `proveBlobs`' repair or the cloud client's re-delivered copy
  /// puts the good bytes in place. While it fails, the file is invisible to
  /// the read path and the caller falls back to the container exactly as if
  /// no file existed.
  Uint8List? _trustedBlobFile(String notebookId, String bare) {
    final held = _blobsHeld[notebookId];
    if (held == null || !held.contains(bare)) {
      return _blobStore(notebookId).readBlob(bare);
    }
    if (!_blobStore(notebookId).blobBytesMatch(bare)) return null;
    held.remove(bare);
    if (held.isEmpty) _blobsHeld.remove(notebookId);
    return _blobStore(notebookId).readBlob(bare);
  }

  /// Keep [hash]'s file out of the read path until its bytes verify.
  ///
  /// **This exists so the sync pull never deletes in the shared folder.**
  /// `blobs/` is replicated: discarding a file whose bytes looked wrong
  /// replicated that deletion to every other device's good copy, and once
  /// Step 7 empties the container there is no copy left anywhere — permanent,
  /// all-device loss on the strength of one device's local evidence (which
  /// `blobBytesMatch` cannot even distinguish from a file it merely could not
  /// read). Holding the hash has only local consequences: [getBlob] treats
  /// the file as absent and falls back to the container, and the entry lifts
  /// itself the first time the file's bytes match the name — after
  /// `proveBlobs`' repair (which does hold verified container bytes), or
  /// after the cloud client finishes or re-delivers the copy.
  ///
  /// Also the register for a blob op whose FILE has not arrived at all: the
  /// file lands after the op has folded, nothing ever names that hash again,
  /// and without this it would be served all session without one check.
  void holdBlobUntilVerified(String notebookId, String hash) {
    _blobsHeld
        .putIfAbsent(notebookId, () => <String>{})
        .add(hash.replaceFirst('sha256:', ''));
  }

  /// Sweep the held register against what is on disk now.
  ///
  /// Called by every sync pull — including the empty ones the folder watcher
  /// fires when a blob file lands — so a late-arriving file is verified close
  /// to its arrival rather than only on its first read. Returns how many
  /// verified; free when nothing is held, which is always in a healthy
  /// notebook.
  int verifyHeldBlobs(String notebookId) {
    final held = _blobsHeld[notebookId];
    if (held == null || held.isEmpty) return 0;
    final store = _blobStore(notebookId);
    final cleared = [
      for (final bare in held)
        if (store.blobBytesMatch(bare)) bare
    ];
    held.removeAll(cleared);
    if (held.isEmpty) _blobsHeld.remove(notebookId);
    return cleared.length;
  }

  /// Hashes whose `blobs/` file may not be trusted yet — absent when its op
  /// folded, or found holding the wrong bytes. Per notebook, session-scoped:
  /// a restart re-runs `proveBlobs`, which is the durable verifier.
  final Map<String, Set<String>> _blobsHeld = {};

  /// Bytes from the container's legacy `blobs` table alone.
  ///
  /// Kept separate from [getBlob] on purpose, for the two callers that must
  /// *not* see `blobs/`: the backfill, whose job is to copy what exists only in
  /// the container, and `proveBlobs`' repair, which replaces a blob file whose
  /// bytes are wrong — handed the file's own bytes it would compare them
  /// against themselves, find no match, and report an unrepairable blob where
  /// the container was holding a perfect copy all along.
  Uint8List? containerBlob(String notebookId, String hash) {
    final rows = _db(notebookId).select(
        'SELECT bytes FROM blobs WHERE hash=?', [hash.replaceFirst('sha256:', '')]);
    return rows.isEmpty ? null : rows.first['bytes'] as Uint8List;
  }

  /// Hashes this session served from the container because `blobs/` had no
  /// file. **The Step 7 gate, from the read side.** Empty is the state a
  /// reclaim may run in; anything here is a picture the reclaim would erase.
  Set<String> blobsServedFromContainer(String notebookId) =>
      Set.unmodifiable(_blobsFromContainer[notebookId] ?? const <String>{});

  /// Hashes with no bytes in either place. Not necessarily an error — a shared
  /// notebook's log routinely arrives before its pictures do — but never
  /// silent.
  Set<String> blobsWithNoBytes(String notebookId) =>
      Set.unmodifiable(_blobsNowhere[notebookId] ?? const <String>{});

  final Map<String, Set<String>> _blobsFromContainer = {};
  final Map<String, Set<String>> _blobsNowhere = {};

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
      checkpointAndClose(db);
    }
    _open.clear();
  }

  bool _disposed = false;
}
