import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart'; // ThemeMode + widgets
import 'package:path/path.dart' as p;

import '../canvas/align_guides.dart';
import '../canvas/canvas_controller.dart';
import '../core/engine.dart';
import '../core/ids.dart';
import '../core/onote_ffi.dart';
import '../editor/onote_text_editor.dart';
import '../export/md_common.dart' show plainLine;
import '../export/onenote_import.dart' show oneNoteLineHeight;
import '../model/models.dart';
import '../store/repository.dart';
import '../model/tags.dart';
import '../spell/spell_checker.dart';
import '../study/flashcards.dart';
import 'builtin_templates.dart';
import 'planner_state.dart';
import 'study_state.dart';
import '../sync/device_identity.dart';
import '../sync/folder_watch.dart';
import '../sync/op.dart';
import '../sync/op_log.dart';
import '../sync/cloud_folders.dart';
import '../sync/mirrors.dart';
import '../sync/sync_recorder.dart';

enum Tool { select, text, pen, highlighter, eraser, lasso }

/// How the eraser removes ink (INK-6).
enum EraserMode {
  /// Rub points out; surviving runs split into new strokes. The precise mode.
  area,

  /// Any touched stroke is removed whole — OneNote's default, and the fast way
  /// to delete a scribbled-out word.
  stroke;

  String get label => switch (this) {
        EraserMode.area => 'Area',
        EraserMode.stroke => 'Whole stroke',
      };
}

/// Whether a finger draws when an ink tool is selected (INK-1 / INK-4).
enum TouchDrawing {
  /// Draw with touch, unless a stylus is in use — then touch pans so a resting
  /// palm can't mark the page. The default: it gives pen users OneNote's palm
  /// rejection while leaving ink reachable on a touch-only tablet.
  auto,

  /// Always draw with touch, even with a stylus present.
  always,

  /// Never draw with touch; fingers only pan and pinch. OneNote's strict
  /// behaviour, and what Openote used to do unconditionally.
  never;

  String get label => switch (this) {
        TouchDrawing.auto => 'Auto (pen takes over)',
        TouchDrawing.always => 'Always',
        TouchDrawing.never => 'Never',
      };
}

/// The panels that can occupy the right-hand slot (style guide §7c).
///
/// An enum rather than five booleans, so "which panel is open" has exactly one
/// answer and cannot be five contradictory ones.
enum SidePanelKind {
  study('Study'),
  planner('Planner'),
  tags('Tags'),
  outline('Outline'),
  links('Links');

  const SidePanelKind(this.label);

  /// What the toggle's tooltip and the panel's header both say, so they cannot
  /// drift apart.
  final String label;
}

/// One tagged line, as the rollup and the planner both need it.
///
/// A typedef over a record rather than a class: it carries no behaviour, and
/// three call sites had already written the field list out by hand — which is
/// how [blockId] came to be missing from it for as long as nothing needed to
/// write back to the tag. Naming it means adding a field is one edit.
typedef TaggedLine = ({
  String pageId,
  String pageTitle,
  String blockId,
  NoteTag tag,
  String text,
});

/// App-wide state. Deliberately simple (ChangeNotifier) for the MVP; the
/// domain layer beneath it is what carries forward.
class AppState extends ChangeNotifier
    implements StudyDocument, PlannerDocument {
  AppState(this._repo) : engine = _selectEngine(_repo) {
    // Forwarded, not replaced. Every surface listens to `AppState`, so the
    // extraction must not change who wakes up when a card is graded — the
    // point of E3 is to give state an owner, not to renegotiate rebuilds in
    // the same pass. Narrowing a listener to `app.study` is now possible and
    // is a separate, checkable change.
    study.addListener(notifyListeners);
  }

  final Repository _repo;
  final DocumentEngine engine;

  /// Use the Rust core when its native library is linked, else the pure-Dart
  /// engine. Chosen once at construction — the app depends only on the seam.
  static DocumentEngine _selectEngine(Repository repo) {
    final core = OnoteCore.instance;
    return core != null ? RustEngine(repo, core) : MirrorEngine(repo);
  }

  // ── Storage facade ───────────────────────────────────────────────────
  //
  // `_repo` is private, and these are the only ways into it from outside this
  // class. That is not tidiness. ADR-0006 puts an append-only operation log
  // underneath persistence, and a log is only correct if it observes *every*
  // mutation — the failure mode of a second write path is not a crash but a
  // log that is quietly incomplete, which surfaces much later as a device that
  // won't converge. One funnel now is what makes "rebuild the container from
  // the log and compare" a usable check later.
  //
  // Widgets previously reached `app.repo` directly for blob reads inside
  // `build()`, and both importers wrote through it and then hand-patched
  // `app.nodes` — so any invariant on `nodes` was silently bypassed by import.

  /// Bytes of a blob in the current notebook, or null.
  Uint8List? blob(String hash) =>
      notebookId == null ? null : _repo.getBlob(notebookId!, hash);

  /// Store bytes in the current notebook, returning the content hash.
  String addBlob(Uint8List bytes, String mime) =>
      importBlob(notebookId!, bytes, mime);

  /// Every notebook in the workspace (registry order).
  List<NotebookRef> get notebooks => _repo.notebooks;

  /// The open notebook's registry entry.
  NotebookRef get currentNotebook =>
      _repo.notebooks.firstWhere((n) => n.id == notebookId);

  /// Read a page of the current notebook without making it the active page —
  /// used by exporters, which walk every page in turn.
  @override
  PageData readPage(String id) => _repo.readPage(notebookId!, id);

  @override
  PageData readPageShared(String id) => _repo.readPageShared(notebookId!, id);

  @override
  Set<String> pageIdsWithTags() => notebookId == null
      ? const {}
      : _repo.pageIdsWithTags(notebookId!).toSet();

  @override
  Set<String> allBlockIds() =>
      notebookId == null ? const {} : _repo.allBlockIds(notebookId!);

  /// Pages in this notebook whose *content* matches [query] (TEXT-7).
  /// The navigator searches titles itself; this is the other half.
  List<({String pageId, String snippet})> searchContent(String query) =>
      notebookId == null
          ? const []
          : _repo.searchPageContent(notebookId!, query);

  /// Re-read the tree from storage into [nodes], bumping [nodesRevision].
  /// Replaces the `app.nodes = repo.loadNodes(id)` line that used to be copied
  /// at every mutation site, importers included.
  void reloadNodes() {
    if (notebookId != null) nodes = _repo.loadNodes(notebookId!);
  }

  // ── Operation log (ADR-0006, shadow mode) ────────────────────────────
  //
  // Every mutation below also records an op into
  // `<Notebook>.onotebook/ops/<device>.oplog`, beside the `.onote`. The
  // container stays authoritative; the log is written alongside so that
  // "rebuild from the log and compare" is a check we can run today. When the
  // two agree consistently, the container can be demoted to a rebuildable
  // cache and the log becomes the synced artifact — at which point none of the
  // call sites below change.

  /// One recorder per notebook touched this session. Keyed because **imports
  /// write into a notebook that isn't the open one**, and a log that misses
  /// imported content is exactly the kind of quiet incompleteness this whole
  /// arrangement exists to catch.
  final Map<String, SyncRecorder> _recorders = {};

  /// Set false by tests that don't want log files written beside their fixture.
  static bool syncLogEnabled = true;

  /// Notebooks whose files another isolate currently owns.
  ///
  /// While the import writer isolate is running, it holds the notebook's
  /// container **and** appends to this device's op log inside its `.onotebook`.
  /// A recorder opened here would be a second writer on that same log file —
  /// which is the one thing ADR-0006's whole correctness argument forbids, and
  /// it is not hypothetical: the notebook manager draws a sync dot per row, and
  /// a sync dot asks for the device count, and the device count opens a
  /// recorder. Merely *listing* notebooks during an import would have done it.
  final Set<String> _importingNotebooks = {};

  /// Hand [nb]'s files to another isolate. Idempotent.
  void beginExclusiveImport(String nb) {
    _importingNotebooks.add(nb);
    _recorders.remove(nb);
    _repo.closeNotebook(nb);
  }

  /// Take them back after a **successful** import. The next read reopens the
  /// container; the log the writer wrote replays in the background so the first
  /// edit doesn't pay for it.
  void endExclusiveImport(String nb) {
    _importingNotebooks.remove(nb);
    _repo.closeNotebook(nb);
    _invalidateSyncStatus();
    // The import just wrote the biggest log this notebook will ever gain in
    // one sitting. Start its replay now, off-thread, so the recorder is ready
    // before the user's first edit — the alternative is a multi-second hitch
    // on the first keystroke into their freshly imported notes.
    unawaited(warmRecorder(nb));
  }

  /// Take them back after a **cancelled or failed** import, where the notebook
  /// is about to be discarded.
  ///
  /// Identical to [endExclusiveImport] except that it does not start a replay.
  /// Warming here raced the teardown: the replay's `announceDevice` rewrites
  /// `.onotebook/manifest.json`, and landing after the purge had deleted the
  /// directory recreated it — an orphaned `.onotebook` that no registry entry
  /// claims, which is exactly what the free-name search downstream trips over.
  void abandonExclusiveImport(String nb) {
    _importingNotebooks.remove(nb);
    _repo.closeNotebook(nb);
    _invalidateSyncStatus();
  }

  /// This installation's device id, minted on first use.
  ///
  /// The same value `DeviceIdentity.resolve` would settle on for a notebook with
  /// no log — which a brand-new import target always is, so the fork check has
  /// nothing to compare against and cannot fire. Public because the import
  /// writer isolate has no access to workspace settings and must be told, and
  /// because the folder watcher needs to know which log is its own without
  /// opening a recorder to ask.
  String localDeviceId() {
    final existing = _repo.getSetting(DeviceIdentity.settingsKey) as String?;
    if (existing != null && existing.isNotEmpty) return existing;
    final id = newId();
    _repo.setSetting(DeviceIdentity.settingsKey, id);
    return id;
  }

  /// Record how far the writer isolate got in [nb]'s log.
  ///
  /// Not optional. The seq lives in workspace settings, the isolate cannot write
  /// there, and a log that runs ahead of the remembered seq is precisely the
  /// signal `DeviceIdentity.resolve` reads as "another installation has been
  /// writing as us" — so skipping this would fork the device id on the next
  /// open of every imported notebook.
  void rememberImportedSeq(String nb, int seq) {
    if (seq <= 0) return;
    _repo.setSetting(DeviceIdentity.seqKey(nb), seq);
  }

  /// The recorder for [nb], opening one **synchronously** if none exists.
  ///
  /// The synchronous open replays the whole log on the calling thread — half a
  /// second for a big imported notebook, and that is what froze the app at
  /// launch and at the end of every import. So the rules are now:
  ///
  /// - **Mutations** call this. They cannot wait, and an op that isn't recorded
  ///   is a hole in the log, so the hitch is the price of correctness — paid
  ///   almost never, because [warmRecorder] runs the replay in a background
  ///   isolate the moment a notebook is opened, imported or selected, and a
  ///   cache hit here is free.
  /// - **Status reads never call this.** [syncDeviceCount] lists log files with
  ///   a bare [OpLogStore]; the watcher takes paths, not a recorder. A read
  ///   that opened a recorder was the launch freeze.
  SyncRecorder? _recorderFor(String nb) {
    if (!syncLogEnabled) return null;
    if (_importingNotebooks.contains(nb)) return null;
    final existing = _recorders[nb];
    if (existing != null) return existing;
    final ref = _repo.notebooks.where((n) => n.id == nb).firstOrNull;
    if (ref == null) return null;
    try {
      final r = SyncRecorder.open(
        notebookId: nb,
        notebookPath: ref.file,
        title: ref.title,
        logDir: ref.logDir,
        readSetting: _repo.getSetting,
        writeSetting: _repo.setSetting,
        // The 2× disk cost of shadow mode is only worth paying when something
        // other than this device will read the bytes. See [notebookIsShared].
        materialiseBlobs: notebookIsShared(nb),
      );
      _recorders[nb] = r;
      // Copy the container's blobs into `blobs/` — for a shared notebook that
      // is the whole point, and it is a no-op for a local-only one. In the
      // background either way: on a real imported notebook this is hundreds of
      // images, and doing it inline would stall the open.
      _startBlobBackfill(nb, r);
      return r;
    } catch (e) {
      // Shadow mode must never be able to break saving. The container is still
      // authoritative, so a log we cannot write is a degraded check, not lost
      // data — and failing the user's save to protect a shadow would be an
      // absurd trade.
      debugPrint('[openote/sync] log unavailable for $nb: $e');
      return null;
    }
  }

  /// In-flight background opens, so two callers don't replay the same log
  /// twice.
  final Map<String, Future<SyncRecorder?>> _recorderWarms = {};

  /// Open [nb]'s recorder with the replay in a background isolate, and install
  /// it when it lands. Safe to call eagerly and repeatedly.
  ///
  /// **The race, and why the loser is discarded.** A mutation can arrive while
  /// the background replay runs; `_recorderFor` then opens synchronously and
  /// *writes* (a seq, maybe ops). The warmed recorder's replayed state predates
  /// those writes, so installing it over the live one would re-issue sequence
  /// numbers the log already contains — two ops claiming one (device, seq) is
  /// the corruption the whole one-writer design exists to prevent. Hence: if a
  /// recorder exists by the time the warm lands, the warm is thrown away, and
  /// [SyncRecorder.openAsync] guarantees a discarded recorder has written
  /// nothing (its title seeding is deferred to the installer).
  Future<SyncRecorder?> warmRecorder(String nb) {
    if (_disposed || !syncLogEnabled || _importingNotebooks.contains(nb)) {
      return Future.value(null);
    }
    final existing = _recorders[nb];
    if (existing != null) return Future.value(existing);
    final inFlight = _recorderWarms[nb];
    if (inFlight != null) return inFlight;
    final ref = _repo.notebooks.where((n) => n.id == nb).firstOrNull;
    if (ref == null) return Future.value(null);
    final f = _warmAndInstall(nb, ref);
    _recorderWarms[nb] = f;
    return f;
  }

  Future<SyncRecorder?> _warmAndInstall(String nb, NotebookRef ref) async {
    try {
      final r = await SyncRecorder.openAsync(
        notebookId: nb,
        notebookPath: ref.file,
        title: ref.title,
        logDir: ref.logDir,
        readSetting: _repo.getSetting,
        writeSetting: _repo.setSetting,
        materialiseBlobs: notebookIsShared(nb),
      );
      final lostTheRace = _disposed ||
          _recorders.containsKey(nb) ||
          _importingNotebooks.contains(nb) ||
          !syncLogEnabled;
      final SyncRecorder? winner;
      if (lostTheRace) {
        winner = _recorders[nb]; // discard the unwritten warm
      } else {
        winner = r;
        _recorders[nb] = r;
        r.seedTitle(ref.title);
        _startBlobBackfill(nb, r);
      }
      // Either way: a notebook with no ops directory when `_startWatching` ran
      // left the watcher unstarted, and opening a recorder — this one or the
      // synchronous one that beat it — created that directory. Retry, or a
      // notebook shared in its first session would not auto-pull until the
      // next launch.
      if (winner != null && nb == notebookId && _watcher == null) {
        _startWatching();
      }
      return winner;
    } catch (e) {
      debugPrint('[openote/sync] background log open for $nb failed: $e');
      return null;
    } finally {
      _recorderWarms.remove(nb);
    }
  }

  /// Whether this notebook's bytes need to exist anywhere but the container.
  ///
  /// True when it lives in a folder something else keeps in step, or when it has
  /// a mirror. Mirrors count because a plain mirror (`keepVersions == 0`) copies
  /// the `.onotebook` directory and **not** the container — so a mirror of a
  /// notebook with an empty `blobs/` would be a backup of a notebook with no
  /// images in it, which is worse than no backup because it looks like one.
  ///
  /// This is deliberately the same rule the sync dot draws, minus the device
  /// count — `SyncState.local` on screen means exactly "stored once on disk",
  /// so the user has a way to see which notebooks are paying for sync. It is
  /// recomputed rather than read from [syncStatus] because `syncStatus` asks how
  /// many devices have written here, which opens a recorder, which asks this.
  bool notebookIsShared(String nb) {
    if (mirrorsFor(nb).isNotEmpty) return true;
    final path = notebookLogDir(nb);
    if (path == null) return false;
    return cloudFolderContaining(path, also: _syncRoots) != null;
  }

  /// Materialise this notebook's blob bytes into `blobs/` if it has become
  /// shared since its recorder was opened.
  ///
  /// Call after anything that can change [notebookIsShared] — moving a notebook
  /// into a sync folder, adding a mirror, remembering a sync root. Without it a
  /// notebook that starts syncing mid-session keeps deferring its bytes until
  /// the next launch, and the other device sees a notebook whose images are all
  /// missing.
  ///
  /// The reverse transition is deliberately not handled: nothing here deletes
  /// bytes. Moving a notebook back out of a sync folder stops *new* blobs being
  /// written on the next open and leaves the existing ones, which is wave 1b's
  /// job (blob GC) and not something to do as a side effect of a move.
  void materialiseBlobsIfShared(String nb) {
    if (!syncLogEnabled || !notebookIsShared(nb)) return;
    final existing = _recorders[nb];
    if (existing == null) {
      // No recorder yet — a background open reads the new shared state and
      // backfills on install. Background, because this is called from sync
      // *UI actions* (add a mirror, choose a folder) and a synchronous open
      // of a big notebook's log would freeze the click that asked for it.
      unawaited(warmRecorder(nb));
      return;
    }
    if (existing.materialiseBlobs) return;
    existing.materialiseBlobs = true;
    _startBlobBackfill(nb, existing);
  }

  void _startBlobBackfill(String nb, SyncRecorder r) {
    if (_disposed || !r.materialiseBlobs) return;
    final f = r
        .backfillBlobs(
      index: _repo.blobIndex(nb),
      read: (h) => _repo.getBlob(nb, h),
    )
        .catchError((Object e) {
      debugPrint('[openote/sync] blob backfill for $nb stopped: $e');
      return 0;
    });
    // Kept so a mirror run can wait for it. Without that, configuring a backup
    // on a notebook whose blobs have never been materialised would copy out a
    // `blobs/` that is still filling — a backup with most of the images missing,
    // taken at the exact moment the user is watching to see that it worked.
    _blobBackfills[nb] = f;
    unawaited(f.whenComplete(() {
      if (identical(_blobBackfills[nb], f)) _blobBackfills.remove(nb);
    }));
  }

  final Map<String, Future<int>> _blobBackfills = {};

  /// Wait for any in-flight blob materialisation for [nb]. Cheap when there is
  /// none, which is the common case.
  ///
  /// Waits through a recorder warm first: since materialisation rides the
  /// background open, the backfill a caller is asking about may not have
  /// STARTED yet — it starts when the warm installs. Without this, a mirror
  /// run right after "move to sync folder" saw nothing in flight and copied
  /// out a `blobs/` that was still empty.
  Future<void> awaitBlobBackfill(String nb) async {
    final w = _recorderWarms[nb];
    if (w != null) await w;
    final f = _blobBackfills[nb];
    if (f != null) await f;
  }

  /// Pull another device's changes into this notebook (ADR-0006 step 3).
  ///
  /// This is the moment sync exists: the transport is whatever put the other
  /// device's `.oplog` next to ours — a synced folder, a USB stick, rsync — and
  /// because each device only ever appends to its OWN log, there is nothing to
  /// resolve. Merging is reading: sort the union, apply, write the result.
  ///
  /// Returns the number of ops folded in.
  /// True while a pull is in flight.
  ///
  /// Guards re-entrancy: the watcher can fire again mid-pull (a cloud client
  /// writing a second log while we read the first), and two overlapping pulls
  /// would both read the same pending ops, both write them, and both advance
  /// the watermark — applying remote edits twice.
  bool _pulling = false;

  /// Set when a pull is requested while one is already running.
  ///
  /// Returning early on re-entrancy would **drop** that request: the watcher's
  /// debounce has already fired, so nothing else is going to ask again, and the
  /// other device's edits would sit unapplied until some later unrelated change
  /// happened to fire the watcher — possibly never, if they stopped typing.
  /// Auto-pull would then be "auto-pull, usually", which is worse than manual
  /// because nothing tells you it didn't happen.
  bool _pullAgain = false;

  Future<int> syncPull(String nb) async {
    if (_pulling) {
      // Don't queue a second concurrent pull — two overlapping pulls would both
      // read the same pending ops and both advance the watermark, applying
      // remote edits twice. Record that another round is owed instead.
      _pullAgain = true;
      return 0;
    }
    _pulling = true;
    try {
      var total = 0;
      // Loop rather than recurse: a device syncing a burst of logs can keep
      // setting the flag, and each round must see the ops that landed during
      // the previous one.
      do {
        _pullAgain = false;
        // Warmed, not opened inline: a pull fires from the folder watcher on
        // the UI thread's event loop, and the first pull for a big notebook
        // would otherwise pay the whole replay right there. This path is
        // already async, so it can simply wait for the background open.
        final r = await warmRecorder(nb);
        if (r == null) break;
        final pending = r.pendingForeignOps(_repo.getSetting);
        if (pending.isEmpty) continue;
        total += await _syncPullLocked(nb, r, pending);
      } while (_pullAgain);
      return total;
    } finally {
      _pulling = false;
    }
  }

  /// Copy the bytes of every blob these ops mention into this device's
  /// container, from the shared folder's content-addressed store.
  ///
  /// Returns how many were copied. Skips ones already held (blobs are immutable
  /// and content-addressed, so "same hash" really is "same bytes") and ones
  /// whose file has not arrived yet — a cloud client syncs the log and the
  /// blobs independently, so a reference can legitimately land first. That case
  /// is not an error and must not fail the pull; the page renders without the
  /// image until the file turns up, and `SyncRecorder.missingBlobs` is how the
  /// UI can say so.
  int _ingestForeignBlobs(String nb, SyncRecorder r, List<Op> pending) {
    var copied = 0;
    for (final op in pending) {
      if (op.kind != OpKind.blobPut) continue;
      // `Op.data` is Object? — a hand-edited or future log can put anything
      // here, and a malformed op must be skipped rather than crash the pull.
      final d = op.data;
      if (d is! Map) continue;
      final hash = d['hash'];
      if (hash is! String || hash.isEmpty) continue;
      if (_repo.getBlob(nb, hash) != null) continue;
      final bytes = r.store.readBlob(hash);
      if (bytes == null) continue; // not arrived yet — not an error
      // `putBlob` re-derives the hash from the bytes rather than trusting the
      // op, which is the point of content-addressing — but it also means a file
      // that does not match its claimed name would be stored under a DIFFERENT
      // hash, leaving the page still referencing nothing and the FK still
      // failing. Check rather than discover that later: a mismatch means a
      // truncated or corrupted download, so skip it and say so.
      final actual = _repo.putBlob(
          nb, bytes, d['mime'] as String? ?? 'application/octet-stream');
      if ('sha256:$actual' != hash && actual != hash) {
        debugPrint('[openote/sync] blob $hash does not match its bytes '
            '(got $actual) — skipping; the file is probably still copying');
        continue;
      }
      copied++;
    }
    return copied;
  }

  Future<int> _syncPullLocked(
      String nb, SyncRecorder r, List<Op> pending) async {
    // Flush first: a local edit still sitting in the debounce would otherwise
    // be overwritten by the materialised page we're about to write.
    await flushSave();

    final changed = r.applyForeign(pending);

    // **Bring the bytes across before the pages that reference them.**
    //
    // A blob op carries only hash/mime/size; the bytes travel as a
    // content-addressed file in the shared folder. Nothing was reading them
    // back, so an image made on another device arrived as a reference to
    // nothing — and not merely as a broken picture: `blob_refs.hash` is a
    // foreign key onto `blobs`, so `writePage` threw a constraint violation and
    // took the WHOLE pull down with it. One shared notebook with one image in
    // it stopped that device syncing at all.
    //
    // Inside the same transaction as the pages, and before them, so a crash
    // can never leave a page referencing bytes that are not there.
    final pulledBlobs = _ingestForeignBlobs(nb, r, pending);

    _repo.runInTransaction(nb, () {
      for (final pageId in changed.pages) {
        final mirror = r.materialisedPage(pageId);
        final blocks = [
          for (final b in (mirror['blocks'] as List? ?? const []))
            Block.fromJson((b as Map).cast<String, dynamic>())
        ];
        final props = PageProps.fromJson(
            (mirror['page'] as Map?)?.cast<String, dynamic>());
        _repo.writePage(nb, pageId, blocks, props);
      }
      if (changed.treeChanged) {
        // Deletions first: a node the log says is gone must leave the
        // container, or a remote delete would be silently ignored and
        // "delete wins" would become "delete loses". Soft-delete, so it
        // lands in the recycle bin exactly as a local delete would.
        for (final id in r.materialisedDeletedIds()) {
          _repo.softDeleteNode(nb, id);
        }
        for (final n in r.materialisedNodes()) {
          _repo.upsertNode(
              nb,
              TreeNode(
                id: n.id,
                kind: NodeKind.values.firstWhere((k) => k.name == n.kind,
                    orElse: () => NodeKind.page),
                parentId: n.parentId,
                title: n.title,
                position: n.position,
                color: n.color,
                level: n.level,
                createdAt: n.createdAt == 0 ? null : n.createdAt,
              ));
        }
      }
    });

    if (pulledBlobs > 0) {
      debugPrint(
          '[openote/sync] pulled $pulledBlobs blob(s) into the container');
    }

    // Watermark per device, only after the writes landed — a crash mid-pull
    // must re-apply rather than skip.
    final highest = <String, int>{};
    for (final op in pending) {
      if (op.seq > (highest[op.device] ?? 0)) highest[op.device] = op.seq;
    }
    highest
        .forEach((dev, seq) => r.markForeignSeen(dev, seq, _repo.setSetting));

    // Re-read whatever the user is looking at.
    reloadNodes();
    if (pageId != null && changed.pages.contains(pageId)) {
      final data = await engine.loadPage(nb, pageId!);
      blocks = data.blocks;
      pageProps = data.props;
      docRevision++;
    }
    lastSyncPull = pending.length;
    _invalidateSyncStatus();
    notifyListeners();
    return pending.length;
  }

  /// Ops folded in by the last [syncPull], for the status surface.
  int lastSyncPull = 0;

  // ── Cloud sync: a synced folder is the transport ─────────────────────

  /// Move a notebook into [targetDir] (a Drive/OneDrive/iCloud/Syncthing
  /// folder) so other devices see it. Returns the new path.
  ///
  /// No OAuth and no tokens by design: those providers' desktop clients
  /// already present the cloud as a local folder, and one-writer-per-file
  /// means they never have to merge anything — which is the thing they do
  /// badly. See `sync/cloud_folders.dart` for the full reasoning.
  Future<String> moveNotebookToFolder(String nb, String targetDir) async {
    await flushSave();
    // Drop the recorder: it holds the OLD path, and a stale log location would
    // silently write this device's ops somewhere nobody is looking.
    _recorders.remove(nb);
    // AWAITED, unlike everywhere else this is called: `moveNotebookTo` deletes
    // the old log directory, and on Windows that fails while the watcher still
    // holds a handle on it. The failure is swallowed there, which would leave
    // an orphaned `.onotebook` behind to collide with the next free-name
    // search — a silent, cumulative mess rather than an error.
    await _stopWatching();
    final path = await _repo.moveNotebookTo(nb, targetDir);
    // The user just told us this folder is where their notes sync. Remember
    // it, rather than re-guessing later from a list of well-known provider
    // paths that will not contain it.
    rememberSyncRoot(targetDir);
    _invalidateSyncStatus();
    // This notebook's images have been living only in the container. They are
    // about to be someone else's only copy, so write them out now rather than
    // whenever this notebook next happens to be opened.
    materialiseBlobsIfShared(nb);
    if (nb == notebookId) {
      await _loadNotebook();
      _startWatching();
    }
    notifyListeners();
    return path;
  }

  // ── Mirrors and backups ──────────────────────────────────────────────

  /// Extra one-way destinations per notebook id.
  final Map<String, List<MirrorTarget>> _mirrors = {};

  List<MirrorTarget> mirrorsFor(String nb) => _mirrors[nb] ?? const [];

  void addMirror(String nb, MirrorTarget t) {
    _mirrors.putIfAbsent(nb, () => []).add(t);
    _saveMirrors();
    _invalidateSyncStatus();
    // BEFORE the first run: a mirror copies `.onotebook/`, so mirroring a
    // notebook whose blobs were never materialised would produce a copy with no
    // images in it. The backfill is async, so the first run can still beat it —
    // mirrors are incremental and the next run picks up what landed late.
    materialiseBlobsIfShared(nb);
    // Run once immediately: a mirror you have to wait for is one you don't
    // trust yet.
    unawaited(runMirrors(nb));
    notifyListeners();
  }

  void removeMirror(String nb, String path) {
    _mirrors[nb]?.removeWhere((t) => t.path == path);
    _saveMirrors();
    _invalidateSyncStatus();
    notifyListeners();
  }

  void _saveMirrors() => _repo.setSetting('mirrors', {
        for (final e in _mirrors.entries)
          e.key: [for (final t in e.value) t.toJson()]
      });

  /// When each notebook's mirrors last ran, so saves don't trigger a copy
  /// storm. A mirror is a safety net, not a live replica.
  final Map<String, int> _lastMirrorRun = {};
  static const _mirrorMinGapMs = 60000;

  /// Copy [nb] out to its mirrors, at most once a minute.
  ///
  /// Callers usually fire and forget, so the run is also parked in
  /// [_mirrorRuns] where [awaitMirrorRun] can find it. Not bookkeeping for its
  /// own sake: a mirror run is file I/O against two directories, and one still
  /// in flight when a test's fixture is torn down throws a `PathNotFound` that
  /// gets charged to whichever test is running next. That exact shape produced
  /// an intermittent Windows CI failure once already.
  Future<void> runMirrors(String nb, {bool force = false}) {
    final f = _runMirrors(nb, force: force);
    _mirrorRuns[nb] = f;
    unawaited(f.whenComplete(() {
      if (identical(_mirrorRuns[nb], f)) _mirrorRuns.remove(nb);
    }));
    return f;
  }

  final Map<String, Future<void>> _mirrorRuns = {};

  /// Wait for any mirror run in flight for [nb]. Cheap when there is none.
  Future<void> awaitMirrorRun(String nb) async {
    final f = _mirrorRuns[nb];
    if (f != null) await f;
  }

  /// Wait for every background job this state has started — log replays, blob
  /// materialisations, mirror runs — to finish.
  ///
  /// These are all fire-and-forget by design: the UI must never wait on them.
  /// But "nobody waits" and "nobody can wait" are different, and the second is
  /// how late file I/O ends up landing after the directory it wants is gone —
  /// a log line at shutdown in the app, and in tests a failure charged to
  /// whichever test runs next.
  Future<void> settleBackgroundWork() async {
    // Each pass can start more work (a warm installs, which starts a
    // backfill), so drain until a pass finds nothing.
    for (var pass = 0; pass < 8; pass++) {
      final pending = <Future<void>>[
        ..._recorderWarms.values,
        ..._blobBackfills.values,
        ..._mirrorRuns.values,
      ];
      if (pending.isEmpty) return;
      await Future.wait(pending).catchError((_) => const <void>[]);
    }
  }

  Future<void> _runMirrors(String nb, {bool force = false}) async {
    final targets = mirrorsFor(nb);
    if (targets.isEmpty) return;
    final now = nowMs();
    if (!force && now - (_lastMirrorRun[nb] ?? 0) < _mirrorMinGapMs) return;
    _lastMirrorRun[nb] = now;
    // A mirror copies `.onotebook/`, so it must not start while that directory
    // is still being filled with the notebook's images.
    await awaitBlobBackfill(nb);
    final src = notebookLogDir(nb);
    if (src == null) return;
    for (final t in targets) {
      try {
        await mirrorNotebook(src, t,
            containerPath: notebookPath(nb),
            snapshot: (dest) => _repo.snapshotContainer(nb, dest));
      } catch (e) {
        // A mirror is a convenience; a failing one (USB stick unplugged,
        // network share down) must never interfere with editing.
        debugPrint('[openote/mirror] ${t.path} failed: $e');
      }
    }
    lastMirrorAt = nowMs();
    notifyListeners();
  }

  int lastMirrorAt = 0;

  /// The `.onotebook` directory for a notebook, which is what gets mirrored.
  String? notebookLogDir(String nb) =>
      _repo.notebooks.where((n) => n.id == nb).firstOrNull?.logDirPath;

  /// Pull automatically when another device's log changes. On by default —
  /// a sync you have to remember to click isn't sync.
  bool autoSync = true;

  void setAutoSync(bool v) {
    autoSync = v;
    _repo.setSetting('autoSync', v);
    v ? _startWatching() : _stopWatching();
    notifyListeners();
  }

  OpFolderWatcher? _watcher;

  void _startWatching() {
    _stopWatching();
    if (!autoSync || notebookId == null || !syncLogEnabled) return;
    // Paths and a device id — NOT a recorder. Opening a recorder here replayed
    // the whole log on the UI thread during startup's first frame, which was
    // most of "the app is locked up for the first few seconds after
    // launching". The watcher only needs to know where the logs live and which
    // one is ours; the recorder is opened (in the background) when a foreign
    // change actually arrives, which is the earliest moment its replayed state
    // is needed.
    final store = _bareLog(notebookId!);
    if (store == null || !store.opsDir.existsSync()) return;
    _watcher = OpFolderWatcher(
      opsDir: store.opsDir,
      ownDevice: localDeviceId(),
      onForeignChange: () {
        // Fire-and-forget: a failed pull must not take down the watcher, and
        // the next change (or the manual button) retries anyway.
        syncPull(notebookId!).catchError((Object e) {
          debugPrint('[openote/sync] auto-pull failed: $e');
          return 0;
        });
      },
    )..start();
  }

  /// Stop the folder watcher, and hand back the future that says when its
  /// handle is actually released.
  ///
  /// Most callers do not care and drop it — a watcher that stops a few
  /// milliseconds later is harmless when nothing is about to touch the
  /// directory. The one caller that MUST wait is `moveNotebookToFolder`, which
  /// goes on to delete the old log directory; see `FolderWatch.stop`.
  Future<void> _stopWatching() {
    final w = _watcher;
    _watcher = null;
    return w?.stop() ?? Future<void>.value();
  }

  /// Where this notebook lives, for the sync surface.
  String? notebookPath(String nb) =>
      _repo.notebooks.where((n) => n.id == nb).firstOrNull?.file;

  /// Devices that have written to this notebook, for the status surface.
  ///
  /// **Cached with a short TTL.** This is a synchronous directory listing, and
  /// the status bar that shows it rebuilds on every notify — i.e. every
  /// keystroke. Worse, once the notebook is in a cloud folder that listing hits
  /// a sync-client-backed (sometimes network) path, so uncached it cost
  /// milliseconds *per character typed*. The count changes only when another
  /// device appears, which is not a per-frame event.
  int syncDeviceCount(String nb) {
    final now = nowMs();
    final hit = _deviceCountCache[nb];
    if (hit != null && now - hit.at < 5000) return hit.count;
    // A bare store, NOT `_recorderFor`. The count is a directory listing
    // (0.24 ms); a recorder open replays the whole log (~0.5 s for a big
    // imported notebook) — and this is called from every sync dot's first
    // paint, which made launching the app and finishing an import freeze for
    // as long as the replay took. A status read must never pay a writer's
    // setup cost. (A side effect goes with it: painting a dot no longer
    // *creates* `.onotebook` directories for notebooks that had none.)
    final n = _bareLog(nb)?.deviceIds().length ?? 0;
    _deviceCountCache[nb] = (count: n, at: now);
    return n;
  }

  /// Read-only view of a notebook's log directory. No replay, no directory
  /// creation, no identity check — safe to call from paint.
  OpLogStore? _bareLog(String nb) {
    final ref = _repo.notebooks.where((n) => n.id == nb).firstOrNull;
    if (ref == null) return null;
    return OpLogStore.forNotebook(ref.file, logDir: ref.logDir);
  }

  final Map<String, ({int count, int at})> _deviceCountCache = {};

  /// Re-check sync status periodically, and notify only when it CHANGES.
  ///
  /// The second half of the grey-chip bug. Even with a folder remembered, the
  /// answer depends on the filesystem — a mirror target appears, a provider
  /// finishes mounting, a network share comes back — and none of those tell
  /// the app anything. The status was only ever recomputed as a side effect of
  /// something else calling `notifyListeners`, so a wrong answer could sit on
  /// screen for a whole session.
  ///
  /// Cheap because it notifies on *change*: the common case is one directory
  /// probe every 20 seconds that finds nothing new and repaints nothing. It
  /// also means this is not a substitute for [_invalidateSyncStatus] — user
  /// actions still update immediately; this is only for changes nobody told us
  /// about.
  Timer? _syncStatusPoll;

  void _startSyncStatusPolling() {
    _syncStatusPoll?.cancel();
    _syncStatusPoll =
        Timer.periodic(const Duration(seconds: 20), (_) => _pollSyncStatus());
  }

  /// Run one poll now — what the timer does, exposed so a test can drive it
  /// without waiting twenty seconds.
  @visibleForTesting
  void debugPollSyncStatus() => _pollSyncStatus();

  void _pollSyncStatus() {
    final nb = notebookId;
    if (nb == null) return;
    final before = syncStatus(nb);
    _invalidateSyncStatus();
    final after = syncStatus(nb);
    if (before.isSynced == after.isSynced &&
        before.devices == after.devices &&
        before.mirrors == after.mirrors &&
        before.folder?.path == after.folder?.path) {
      return;
    }
    notifyListeners();
  }

  /// Drop the cached count after something that can change it.
  void _invalidateSyncStatus() {
    _deviceCountCache.clear();
    _syncStatusCache.clear();
  }

  final Map<String, ({SyncStatus status, int at})> _syncStatusCache = {};

  // ── Remembered sync folders ──────────────────────────────────────────

  /// Folders the user has told us are sync locations, by choosing one in
  /// "Choose a folder…" or by joining a notebook from one.
  ///
  /// **Why this is stored rather than detected.** `detectCloudFolders` probes
  /// ~15 well-known paths, which is a fine way to *offer* somewhere to sync and
  /// a bad way to *report* whether syncing is on. It says no to any folder not
  /// on the list — a self-hosted Nextcloud somewhere else, a relocated
  /// OneDrive, a Google Drive on an unexpected drive letter — and it also says
  /// no to a folder on the list that has not mounted yet, which is why the
  /// chip could come up grey after a restart and stay grey for the session.
  /// What the user chose is a fact; where a provider happens to have mounted
  /// two seconds after launch is a guess.
  final List<CloudFolder> _syncRoots = [];

  List<CloudFolder> get syncRoots => List.unmodifiable(_syncRoots);

  /// Record [dir] as a sync location. Idempotent.
  void rememberSyncRoot(String dir) {
    if (dir.trim().isEmpty) return;
    if (_syncRoots.any((f) => p.equals(f.path, dir))) return;
    _syncRoots.add(describeChosenFolder(dir));
    _persistSyncRoots();
    _invalidateSyncStatus();
    // Calling a folder a sync location can make notebooks already inside it
    // shared. Only the ones with a recorder open are re-checked here — the rest
    // get the right answer when theirs is opened, which the notebook list does
    // for all of them the moment it draws their sync dots.
    for (final nb in _recorders.keys.toList()) {
      materialiseBlobsIfShared(nb);
    }
    notifyListeners();
  }

  void _persistSyncRoots() => _repo.setSetting('syncRoots', [
        for (final f in _syncRoots)
          {'path': f.path, 'name': f.name, 'kind': f.kind.name}
      ]);

  /// Restore the remembered roots. Public and standalone, like `study.load()`
  /// and `planner.load()` — `init()` needs a widgets binding, and a test of
  /// what survives a restart should not need a whole application to ask.
  void loadSyncRoots() {
    final raw = _repo.getSetting('syncRoots');
    if (raw is! List) return;
    for (final e in raw) {
      if (e is! Map) continue;
      final path = e['path'];
      if (path is! String || path.isEmpty) continue;
      if (_syncRoots.any((f) => p.equals(f.path, path))) continue;
      _syncRoots.add(CloudFolder(
        name: e['name'] as String? ?? p.basename(path),
        path: path,
        kind: CloudKind.values.asNameMap()[e['kind']] ?? CloudKind.other,
      ));
    }
  }

  /// What to show the user about this notebook's sync state.
  ///
  /// Answers "where does this notebook live", not "how many devices have
  /// touched it" — those differ for the entire period between setting sync up
  /// and a second device appearing, which is precisely when the user is
  /// looking for confirmation that it worked.
  SyncStatus syncStatus(String nb) {
    final now = nowMs();
    final hit = _syncStatusCache[nb];
    if (hit != null && now - hit.at < 5000) return hit.status;

    // The LOG directory, not the container: a device that joined a shared
    // notebook keeps its container in the local workspace, so asking where the
    // container is told that device it wasn't syncing — while it was.
    final path = notebookLogDir(nb);
    final folder =
        path == null ? null : cloudFolderContaining(path, also: _syncRoots);
    final devices = syncDeviceCount(nb);
    final status = SyncStatus(
      folder: folder,
      devices: devices,
      mirrors: mirrorsFor(nb).length,
    );
    _syncStatusCache[nb] = (status: status, at: now);
    return status;
  }

  /// Where this notebook's container and logs actually are, with sizes.
  Future<NotebookStorage> storageFor(String nb) async {
    final ref = _repo.notebooks.where((n) => n.id == nb).firstOrNull ??
        _repo.trashedNotebooks.where((n) => n.id == nb).firstOrNull;
    if (ref == null) {
      return const NotebookStorage(
          containerPath: '',
          containerBytes: 0,
          logPath: '',
          logBytes: 0,
          logExists: false,
          containerCloud: null,
          logCloud: null);
    }
    final logPath = ref.logDirPath;
    final logDir = Directory(logPath);
    return NotebookStorage(
      containerPath: ref.file,
      containerBytes: _fileBytes(ref.file),
      logPath: logPath,
      logBytes: await _dirBytes(logDir),
      logExists: logDir.existsSync(),
      containerCloud: cloudFolderContaining(ref.file, also: _syncRoots),
      logCloud: cloudFolderContaining(logPath, also: _syncRoots),
    );
  }

  /// Notebook files on disk that no registry entry — live or trashed — claims.
  ///
  /// Looks in this workspace and one level into each detected cloud folder
  /// (plus its `Openote` subfolder), which is where the app's own flows put
  /// things. Deliberately not a whole-disk scan.
  Future<List<OrphanFile>> findOrphanFiles() async {
    final claimed = <String>{};
    for (final n in [..._repo.notebooks, ..._repo.trashedNotebooks]) {
      claimed
        ..add(p.canonicalize(n.file))
        ..add(p.canonicalize(n.logDirPath));
    }

    final roots = <(String, bool)>[(_repo.workspaceDir.path, true)];
    for (final f in detectCloudFolders()) {
      roots
        ..add((f.path, false))
        ..add((p.join(f.path, 'Openote'), false));
    }

    final out = <OrphanFile>[];
    final seen = <String>{};
    for (final (root, isWorkspace) in roots) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;
      try {
        for (final e in dir.listSync(followLinks: false)) {
          final ext = p.extension(e.path).toLowerCase();
          final isLog = e is Directory && ext == '.onotebook';
          final isContainer = e is File && ext == '.onote';
          if (!isLog && !isContainer) continue;
          final canon = p.canonicalize(e.path);
          if (claimed.contains(canon) || !seen.add(canon)) continue;
          out.add(OrphanFile(
            path: e.path,
            bytes:
                isLog ? await _dirBytes(Directory(e.path)) : _fileBytes(e.path),
            isLog: isLog,
            safeToDelete: isWorkspace,
          ));
        }
      } catch (_) {
        // An unreadable folder (offline placeholders, permissions) must not
        // break the scan of the others.
      }
    }
    out.sort((a, b) => b.bytes.compareTo(a.bytes));
    return out;
  }

  /// Delete orphans, and ONLY ones marked safe. Returns the bytes reclaimed.
  Future<int> deleteOrphans(Iterable<OrphanFile> files) async {
    var freed = 0;
    for (final f in files) {
      if (!f.safeToDelete) continue; // never a shared folder; see [OrphanFile]
      try {
        if (f.isLog) {
          Directory(f.path).deleteSync(recursive: true);
        } else {
          File(f.path).deleteSync();
        }
        freed += f.bytes;
      } catch (_) {/* locked or gone; report what actually went */}
    }
    return freed;
  }

  int _fileBytes(String path) {
    try {
      final f = File(path);
      return f.existsSync() ? f.lengthSync() : 0;
    } catch (_) {
      return 0;
    }
  }

  Future<int> _dirBytes(Directory dir) async {
    if (!dir.existsSync()) return 0;
    var total = 0;
    try {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            total += e.lengthSync();
          } catch (_) {/* vanished mid-walk */}
        }
      }
    } catch (_) {/* unreadable; report what we counted */}
    return total;
  }

  /// Blobs the log references but whose bytes are not yet in `blobs/`.
  ///
  /// Empty means a rebuild from the log could reconstruct this notebook's
  /// content in full, not merely its structure — the distinction that decides
  /// whether the container is safe to demote to a cache.
  /// **Forces a synchronous log replay** if no recorder is open — this is a
  /// diagnostic, not a paint-path read. Nothing that runs during a build may
  /// call it; see [_recorderFor].
  Set<String> syncMissingBlobs(String nb) =>
      _recorderFor(nb)?.missingBlobs() ?? const {};

  /// Materialise this notebook's blob bytes into `blobs/`, and wait for it.
  ///
  /// This is "prepare this notebook for sync", stated outright: it turns
  /// [SyncRecorder.materialiseBlobs] on whether or not the notebook looks
  /// shared, because asking for it *is* the intent. The automatic paths
  /// ([materialiseBlobsIfShared] and the recorder's own open) go through the
  /// same machinery without the override.
  Future<int> syncBackfillBlobs(String nb) async {
    final r = _recorderFor(nb);
    if (r == null) return 0;
    r.materialiseBlobs = true;
    return r.backfillBlobs(
      index: _repo.blobIndex(nb),
      read: (h) => _repo.getBlob(nb, h),
    );
  }

  /// Upsert a node and record it. Every tree mutation funnels through here.
  TreeNode _putNode(String nb, TreeNode n) {
    final saved = _repo.upsertNode(nb, n);
    _recorderFor(nb)?.node(saved);
    return saved;
  }

  // ── Import write path ────────────────────────────────────────────────
  //
  // Importers write in bulk, into a notebook that may not be the open one, and
  // outside the interactive edit path. They still go through here rather than
  // touching the repository, for the reason above. The `import` prefix marks
  // them as the bulk path — an interactive edit must never use them, because
  // they deliberately skip autosave, undo and selection handling.

  /// Create a node during import. Returns the stored node.
  TreeNode importNode(String nb, TreeNode n) => _putNode(nb, n);

  /// Write a page's blocks during import.
  void importPage(String nb, String pageId, List<Block> blocks, PageProps p) {
    _repo.writePage(nb, pageId, blocks, p);
    _recorderFor(nb)?.page(pageId, blocks, p);
  }

  /// Store a blob during import (images pulled out of a `.one` file).
  String importBlob(String nb, Uint8List bytes, String mime) {
    final hash = _repo.putBlob(nb, bytes, mime);
    // The op records only the hash, mime and size; the bytes are written to
    // `blobs/<sha256>` — content-addressed and immutable, so they need no merge
    // logic and can be fetched lazily (ADR-0006 §3). Putting megabytes of image
    // into an append-only log would make it unbounded and unreadable.
    _recorderFor(nb)?.blob(hash, mime, bytes.length, bytes);
    return hash;
  }

  /// Hard-delete a node during import — used to clear a partially seeded
  /// notebook before re-seeding it, never on user data.
  void importPurgeNode(String nb, String id) {
    _repo.purgeNode(nb, id);
    _recorderFor(nb)?.nodePurged(id);
  }

  /// The tree of any notebook, open or not.
  List<TreeNode> importNodes(String nb) => _repo.loadNodes(nb);

  /// Run [body] as ONE transaction. Import writes hundreds of pages; without
  /// this each would pay its own commit.
  T importBatch<T>(String nb, T Function() body) =>
      _repo.runInTransaction(nb, body);

  /// Create the notebook an import targets. Unlike [createNotebook] this does
  /// not switch to it or flush the current page: the importer builds the whole
  /// notebook first and only then calls [selectNotebook], which flushes. The
  /// asymmetry is deliberate — switching mid-import would show the user a
  /// half-built notebook — and it is safe only because of that later switch.
  Future<NotebookRef> importCreateNotebook(String title) =>
      _repo.createNotebook(title);

  /// Shared so toolbar/shortcuts can drive zoom (style guide §8.2).
  final canvas = CanvasController();

  /// RepaintBoundary key for whole-page capture (PDF export).
  final canvasKey = GlobalKey();

  // Workspace / navigation
  @override
  String? notebookId;

  List<TreeNode> _nodes = [];

  /// The current notebook's tree, ordered by position.
  @override
  List<TreeNode> get nodes => _nodes;
  set nodes(List<TreeNode> v) {
    _nodes = v;
    nodesRevision++;
  }

  /// Bumped whenever the tree changes shape *or* a node's rendered fields
  /// change. The navigator memoises its widget subtree on this, so typing in a
  /// page no longer rebuilds every section and page tile (§7a.6).
  @override
  int nodesRevision = 0;

  /// Call after mutating a [TreeNode] in place (rename, indent) — those don't
  /// replace the list, so the setter above wouldn't notice.
  void bumpNodes() => nodesRevision++;

  @override
  String? pageId;
  final Set<String> collapsedGroups = {};

  // Navigator (§7b, two-column): the focused section fills the pages pane.
  @override
  String? activeSectionId;

  TreeNode? get activeSection => node(activeSectionId);

  // ── Navigator layout state ──────────────────────────────────────────
  //
  // Two independent widths rather than one split: sections and pages are
  // separate columns now (the OneNote shape), so each keeps its own size and
  // neither steals from the other when resized.

  double navSectionsW = 120; // sections column, px
  double navPagesW = 168; // pages column, px
  bool navCollapsed = false; // the whole navigator as a 44px rail

  /// The Home surface (favourites + recents) shown in the pages pane.
  /// Transient by design: selecting any page returns the pane to that page's
  /// section, so Home behaves like a springboard rather than a place you can
  /// get stuck in. Deliberately a BOOLEAN beside a real [activeSectionId], not
  /// a sentinel section id — every consumer of activeSectionId (study scoping,
  /// exam plans, deck counts) stays correct with zero special-casing.
  bool navHome = false;

  /// Bumped when navigator-only state changes that nothing else observes —
  /// favourites, collapse toggles, Home. The navigator memo in AppShell keys
  /// on it; leaving one of these out is how a stale (not broken, just frozen)
  /// navigator ships.
  int navRevision = 0;

  void setNavSectionsW(double v) {
    navSectionsW = v.clamp(96, 220);
    _repo.setSetting('navSectionsW', navSectionsW);
    notifyListeners();
  }

  void setNavPagesW(double v) {
    navPagesW = v.clamp(140, 320);
    _repo.setSetting('navPagesW', navPagesW);
    notifyListeners();
  }

  void toggleNavCollapsed() {
    navCollapsed = !navCollapsed;
    _repo.setSetting('navCollapsed', navCollapsed);
    notifyListeners();
  }

  void openHome() {
    navHome = true;
    navRevision++;
    notifyListeners();
  }

  /// Which page each section was last on, so browsing sections never loses
  /// your place. Keys are '<notebookId>:<sectionId>' because settings are
  /// workspace-scoped (same reasoning as favourites).
  final Map<String, String> _sectionLastPage = {};

  void _rememberSectionPage(String sectionId, String pageId) {
    _sectionLastPage['$notebookId:$sectionId'] = pageId;
    _repo.setSetting('sectionLastPage', _sectionLastPage);
  }

  /// A section's pages, in navigator order.
  ///
  /// One query rather than the same `where` written out at each call site — it
  /// was open-coded in three places, and "the pages of a section, in the order
  /// the navigator shows them" is exactly the thing a section-wide export or
  /// sort has to agree with the navigator about.
  List<TreeNode> pagesOf(String sectionId) => [
        for (final n in nodes)
          if (n.kind == NodeKind.page && n.parentId == sectionId) n
      ];

  /// Focus a section (the pages pane shows its pages). When the current page
  /// isn't inside the section, return to the page you were last on THERE —
  /// falling back to the first page only for a section never visited.
  ///
  /// The remembered page is what makes flicking between sections
  /// non-destructive: jumping to the *first* page every time meant merely
  /// looking at another section threw away your place in it, which OneNote
  /// gets right and users notice immediately.
  /// Awaitable, because `selectPage` only commits `pageId` after an awaited
  /// flush — fire-and-forget here let two quick section clicks interleave
  /// their page loads and land on the loser's page.
  Future<void> activateSection(String id) async {
    navHome = false;
    activeSectionId = id;
    final cur = node(pageId);
    if (cur == null || cur.parentId != id) {
      final remembered = node(_sectionLastPage['$notebookId:$id']);
      final target = (remembered != null && remembered.parentId == id)
          ? remembered
          : pagesOf(id).firstOrNull;
      if (target != null) {
        await selectPage(target.id); // sets activeSectionId + notifies
        return;
      }
    }
    notifyListeners();
  }

  // Page content
  @override
  List<Block> blocks = [];
  PageProps pageProps = PageProps();

  // Selection (CANVAS-7: single + multi)
  final Set<String> selectedIds = {};
  String? selectedBlockId; // primary (gets handles/chrome)
  String? editingBlockId;

  /// Bumped when block content changes from OUTSIDE its own editor widgets
  /// (undo/redo, page load) so views rebuild from model state.
  @override
  int docRevision = 0;

  /// Measured render sizes of auto-height blocks (runtime only; used for
  /// culling, marquee hit-testing, and content bounds).
  final Map<String, Size> renderSizes = {};

  /// Pointer ids claimed by block widgets this gesture, so the canvas-level
  /// handler ignores them (see BlockView / PageCanvas).
  final Set<int> claimedPointers = {};

  // Canvas settings
  Tool tool = Tool.select;
  bool snapToGrid = true; // on by default; the grid only shows while dragging
  int penColor = 0;
  double penSize = 2.5;

  // ── Tags (TEXT-5) ────────────────────────────────────────────────────

  /// Apply or remove [kind] on the line the caret is in, for the block being
  /// edited (or the selected one).
  ///
  /// Toggling is per (line, kind): applying the same tag to the same line
  /// removes it, which is what a toolbar button that shows its own state has
  /// to do.
  void toggleTagOnSelection(TagKind kind, {int? line}) {
    final b = blocks
        .where((x) => x.id == (editingBlockId ?? selectedBlockId))
        .firstOrNull;
    if (b == null || b.type != BlockType.text) return;
    final idx = line ?? _caretLine(b);
    pushUndo();
    final tags = [...NoteTag.listFrom(b.content)];
    final at = tags.indexWhere((t) => t.line == idx && t.kind == kind);
    if (at >= 0) {
      tags.removeAt(at);
    } else {
      tags.add(NoteTag(
          kind: kind, line: idx, checked: kind == TagKind.todo ? false : null));
    }
    NoteTag.writeInto(b.content, tags);
    updateBlock(b);
    docRevision++;
    notifyListeners();
  }

  /// Flip a to-do tag's completion.
  void setTagChecked(String blockId, int line, bool checked) {
    final b = blocks.where((x) => x.id == blockId).firstOrNull;
    if (b == null) return;
    pushUndo();
    final tags = [
      for (final t in NoteTag.listFrom(b.content))
        if (t.line == line && t.kind == TagKind.todo)
          t.copyWith(checked: checked)
        else
          t
    ];
    NoteTag.writeInto(b.content, tags);
    updateBlock(b);
    docRevision++;
    notifyListeners();
  }

  /// Change one tag, on any page of the open notebook.
  ///
  /// **Not open-page-only, and that is the point.** The planner lists tasks
  /// from the whole notebook, so ticking one or re-dating it must not depend on
  /// which page happens to be loaded. Routing it through `selectPage` instead
  /// was the first attempt and it is worse twice over: it yanks the reader to
  /// another page for a checkbox, and — because `selectPage` reloads the block
  /// list from storage — an edit made in the same turn is thrown away by the
  /// load that follows it.
  ///
  /// [change] is given the matching tag and returns its replacement, so the
  /// caller says *what* changes and this says *where*. Returns whether anything
  /// did.
  bool _updateTag(String pageId_, String blockId, int line, TagKind kind,
      NoteTag Function(NoteTag) change) {
    final nb = notebookId;
    if (nb == null) return false;

    List<NoteTag>? apply(Block b) {
      final tags = NoteTag.listFrom(b.content);
      if (!tags.any((t) => t.line == line && t.kind == kind)) return null;
      return [
        for (final t in tags)
          if (t.line == line && t.kind == kind) change(t) else t
      ];
    }

    if (pageId_ == pageId) {
      final b = blocks.where((x) => x.id == blockId).firstOrNull;
      if (b == null) return false;
      final next = apply(b);
      if (next == null) return false;
      pushUndo();
      NoteTag.writeInto(b.content, next);
      updateBlock(b);
      docRevision++;
      notifyListeners();
      return true;
    }

    // A closed page: read it, change it, write it back through the bulk path —
    // the same route `repairWholeNotebook` takes. No undo entry, because undo
    // is scoped to the open page and pushing one here would make Ctrl+Z restore
    // a page the user is not looking at.
    final data = readPage(pageId_);
    final b = data.blocks.where((x) => x.id == blockId).firstOrNull;
    if (b == null) return false;
    final next = apply(b);
    if (next == null) return false;
    NoteTag.writeInto(b.content, next);
    importBatch(nb, () => importPage(nb, pageId_, data.blocks, data.props));
    docRevision++;
    notifyListeners();
    return true;
  }

  /// Give a tag a due day, or (with null) take it away (v0.5 stage 2).
  @override
  bool setTagDue(String blockId, int line, TagKind kind, DateTime? day,
          {String? pageId}) =>
      _updateTag(pageId ?? this.pageId ?? '', blockId, line, kind,
          (t) => t.withDue(day));

  /// Tick a to-do off, wherever in the notebook it lives.
  bool setTagCheckedOn(
          String pageId_, String blockId, int line, bool checked) =>
      _updateTag(pageId_, blockId, line, TagKind.todo,
          (t) => t.copyWith(checked: checked));

  /// Tags on the caret's line, so the toolbar can show which are active.
  Set<TagKind> tagsAtCaret() {
    final b = blocks
        .where((x) => x.id == (editingBlockId ?? selectedBlockId))
        .firstOrNull;
    if (b == null || b.type != BlockType.text) return const {};
    final idx = _caretLine(b);
    return {
      for (final t in NoteTag.listFrom(b.content))
        if (t.line == idx) t.kind
    };
  }

  /// The text block a tag action applies to: the one being edited, else the
  /// one selected. Public because the tag menu needs to ask what is under the
  /// caret before it can offer to change it — the same block [tagsAtCaret]
  /// already answers about.
  Block? caretBlock() {
    final b = blocks
        .where((x) => x.id == (editingBlockId ?? selectedBlockId))
        .firstOrNull;
    return b != null && b.type == BlockType.text ? b : null;
  }

  /// Which line of [caretBlock] the caret is on. 0 when nothing is being
  /// edited, matching where a tag would land.
  int caretLineIndex() {
    final b = caretBlock();
    return b == null ? 0 : _caretLine(b);
  }

  /// Which line the caret sits on, so a tag lands where the user is looking.
  /// Falls back to line 0 when nothing is being edited (a tag applied to a
  /// merely-selected block is a tag on its first line).
  int _caretLine(Block b) {
    final ctl =
        activeEditor?.block.id == b.id ? activeEditor?.controller : null;
    final text = b.content['text'] as String? ?? '';
    if (ctl == null || !ctl.selection.isValid) return 0;
    final at = ctl.selection.baseOffset.clamp(0, text.length);
    return '\n'.allMatches(text.substring(0, at)).length;
  }

  /// Turn the caret's line into a flashcard, picking the tag that fits it.
  ///
  /// Tagging is the on-ramp — you mark a line while taking notes and it becomes
  /// a card — but "tag it Question or Definition and remember which one" is a
  /// rule the student has to learn before anything happens, and getting it
  /// wrong produces nothing at all with no explanation. So: one action, and it
  /// reads the line.
  ///
  /// Returns what a caller should tell the user, or null if there was no line
  /// to work with.
  String? makeCardAtCaret() {
    final b = blocks
        .where((x) => x.id == (editingBlockId ?? selectedBlockId))
        .firstOrNull;
    if (b == null || b.type != BlockType.text) return null;
    final lines = (b.content['text'] as String? ?? '').split('\n');
    final idx = _caretLine(b);
    if (idx >= lines.length) return null;
    final line = lines[idx].trim();
    if (line.isEmpty) return 'Put the caret on a line with something on it.';

    final kind = line.endsWith('?') ? TagKind.question : TagKind.definition;
    if (!tagsAtCaret().contains(kind)) toggleTagOnSelection(kind);

    // Say whether it actually produced a card. Silence is what made tagging
    // feel like it did nothing.
    final made = cardsFromBlock(b, pageId ?? '', '')
        .where((c) => c.line == idx)
        .isNotEmpty;
    if (made) return '${kind.label} card created.';
    return kind == TagKind.question
        ? 'Tagged as a Question — now indent the answer on the line below.'
        : 'Tagged as a Definition — write it as “term — meaning” to make a card.';
  }

  /// Blank out the selected words on a tagged line, making it a fill-in-the-
  /// blank. Returns false when there is no selection to blank.
  bool blankOutSelection() {
    final ed = activeEditor;
    if (ed == null) return false;
    final sel = ed.controller.selection;
    if (!sel.isValid || sel.isCollapsed) return false;
    final text = ed.controller.text;
    final a = sel.start, z = sel.end;
    final word = text.substring(a, z);
    if (word.trim().isEmpty) return false;
    pushUndo();
    ed.controller.value = ed.controller.value.copyWith(
      text: text.replaceRange(a, z, '==$word=='),
      selection: TextSelection.collapsed(offset: z + 4),
      composing: TextRange.empty,
    );
    // Blanking only means something on a line that is already a card.
    if (tagsAtCaret().isEmpty) toggleTagOnSelection(TagKind.question);
    markDirty();
    notifyListeners();
    return true;
  }

  /// Every tagged line in the notebook, for the find-tags rollup.
  ///
  /// Scans page mirrors rather than a maintained index: same reasoning as
  /// notebook-wide search — one source of truth beats an index that can drift.
  /// "Until it measurably hurts" arrived, though, with the first big imported
  /// notebook — so the scan is now narrowed twice *without* becoming an index:
  /// a SQL prefilter finds the pages that can possibly carry a tag (most
  /// cannot), and a decoded-page cache in the repository means a rebuild
  /// re-decodes only pages that changed. See `Repository.readPageShared`.
  ({String key, List<TaggedLine> tags})? _allTagsCache;

  @override
  List<TaggedLine> allTags() {
    if (notebookId == null) return const [];
    final key = '$notebookId#$docRevision#$nodesRevision#$pageId';
    final cached = _allTagsCache;
    if (cached != null && cached.key == key) return cached.tags;
    final tagged = _repo.pageIdsWithTags(notebookId!).toSet();
    final out = <TaggedLine>[];
    for (final n in nodes.where((n) => n.kind == NodeKind.page)) {
      // The open page's in-memory blocks are fresher than the container — and
      // it is also the one page the prefilter must not exclude, since its
      // unsaved edits may carry tags the stored JSON does not.
      if (n.id != pageId && !tagged.contains(n.id)) continue;
      final blocksOf = n.id == pageId
          ? blocks
          : _repo.readPageShared(notebookId!, n.id).blocks;
      for (final b in blocksOf) {
        if (b.type != BlockType.text) continue;
        final tags = NoteTag.listFrom(b.content);
        if (tags.isEmpty) continue;
        final lines = (b.content['text'] as String? ?? '').split('\n');
        for (final t in tags) {
          out.add((
            pageId: n.id,
            pageTitle: n.title,
            blockId: b.id,
            tag: t,
            // Plain, not raw: every consumer of this is a SUMMARY — the
            // tags rollup and the planner's agenda — and neither runs the
            // Markdown renderer, so a to-do written as a bullet showed up
            // as "- Finish tutorial 4", dash included.
            text: t.line < lines.length ? plainLine(lines[t.line]) : '',
          ));
        }
      }
    }
    _allTagsCache = (key: key, tags: out);
    return out;
  }

  bool get showTagsPanel => openPanel == SidePanelKind.tags;
  void toggleTagsPanel() => togglePanel(SidePanelKind.tags);

  // ── Study: flashcards, scheduling, stats (E3 — see study_state.dart) ──

  /// Cards, schedules, streaks and the exam countdown.
  ///
  /// Extracted in the E3 pass. `AppState` still forwards its notifications
  /// (see the constructor), so every existing listener keeps working exactly
  /// as it did — but the state itself now has an owner, and the next study
  /// feature has somewhere to go that is not this file.
  late final StudyState study = StudyState(this,
      readSetting: _repo.getSetting, writeSetting: _repo.setSetting);

  bool get showStudyPanel => openPanel == SidePanelKind.study;
  void toggleStudyPanel() => togglePanel(SidePanelKind.study);

  // ── The planner: dates, reminders, timetable (v0.5) ──────────────────

  /// Everything you have a date for, in one place.
  ///
  /// Owns the reminder store and the calendar subscription; **borrows**
  /// everything else. Exam dates stay in [study] and a task's deadline stays on
  /// its tag, because the agenda is a lens rather than a second store — see
  /// `planner_state.dart`.
  late final PlannerState planner = PlannerState(this, study,
      readSetting: _repo.getSetting, writeSetting: _repo.setSetting)
    ..addListener(notifyListeners);

  // ── The right-hand panel slot (style guide §7c) ──────────────────────

  /// Which panel occupies the single right-hand slot, or null for none.
  ///
  /// **One slot, one panel** — the five panels were independent booleans, so
  /// all five could be open at once: 1,360px of chrome on a Row, which leaves
  /// the canvas nothing on a 1366px laptop. No workflow was found that needs
  /// two at a time, and one-at-a-time is also the task-pane model a OneNote
  /// switcher already expects.
  ///
  /// The old `show*Panel` fields are now getters over this, so every existing
  /// call site keeps working and there is only one piece of state to be wrong.
  SidePanelKind? openPanel;

  /// Open [kind], replacing whatever was there. Idempotent.
  void showPanel(SidePanelKind kind) {
    if (openPanel == kind) return;
    openPanel = kind;
    notifyListeners();
  }

  void closePanel() {
    if (openPanel == null) return;
    openPanel = null;
    notifyListeners();
  }

  /// Open [kind], or close it if it is already the open one — what a toolbar
  /// toggle does.
  void togglePanel(SidePanelKind kind) =>
      openPanel == kind ? closePanel() : showPanel(kind);

  bool get showPlannerPanel => openPanel == SidePanelKind.planner;
  void togglePlannerPanel() => togglePanel(SidePanelKind.planner);

  /// Open the planner (idempotent) — what a "see all your dates" affordance
  /// elsewhere in the app should call.
  void openPlanner() => showPanel(SidePanelKind.planner);

  // ── Favourites & recents (ORG-10) ────────────────────────────────────
  //
  // Keys are '<notebookId>:<pageId>'. Settings are WORKSPACE-scoped, so a bare
  // page id would collide across notebooks and dangle after one is deleted.

  final Set<String> _favourites = {};
  final List<String> _recents = [];

  static const _recentsCap = 20;

  String _pageKey(String pageId, [String? nb]) => '${nb ?? notebookId}:$pageId';

  bool isFavourite(String pageId) => _favourites.contains(_pageKey(pageId));

  /// Favourite page ids in THIS notebook, in tree order.
  List<TreeNode> favouritePages() => [
        for (final n in nodes)
          if (n.kind == NodeKind.page && _favourites.contains(_pageKey(n.id))) n
      ];

  void toggleFavourite(String pageId) {
    final k = _pageKey(pageId);
    _favourites.contains(k) ? _favourites.remove(k) : _favourites.add(k);
    _repo.setSetting('favourites', _favourites.toList());
    navRevision++; // the Home pane renders favourites; nothing else changes
    notifyListeners();
  }

  /// Recently visited pages in this notebook, most recent first.
  List<TreeNode> recentPages({int max = 8}) {
    final out = <TreeNode>[];
    for (final k in _recents) {
      final parts = k.split(':');
      if (parts.length != 2 || parts[0] != notebookId) continue;
      final n = node(parts[1]);
      if (n != null) out.add(n);
      if (out.length >= max) break;
    }
    return out;
  }

  void _recordRecent(String pageId) {
    final k = _pageKey(pageId);
    _recents.remove(k);
    _recents.insert(0, k);
    if (_recents.length > _recentsCap) {
      _recents.removeRange(_recentsCap, _recents.length);
    }
    _repo.setSetting('recentPages', _recents);
  }

  /// Sort a section's pages by title or by last edit (ORG-8).
  ///
  /// Subpages move WITH their parent: a page carries the deeper-level pages
  /// that follow it, or sorting would silently reparent every subpage in the
  /// section to whatever landed above it.
  void sortSection(String sectionId, {required bool byTitle}) {
    final pages = pagesOf(sectionId);
    if (pages.length < 2) return;
    // Group each top-level page with its contiguous deeper-level run.
    final groups = <List<TreeNode>>[];
    for (final p in pages) {
      if (p.level == 0 || groups.isEmpty) {
        groups.add([p]);
      } else {
        groups.last.add(p);
      }
    }
    groups.sort((a, b) => byTitle
        ? a.first.title.toLowerCase().compareTo(b.first.title.toLowerCase())
        : b.first.updatedAt.compareTo(a.first.updatedAt));
    var seq = nowMs();
    for (final g in groups) {
      for (final n in g) {
        n.position = 'a${(seq++).toString().padLeft(15, '0')}';
        _putNode(notebookId!, n);
      }
    }
    reloadNodes();
    notifyListeners();
  }

  /// Spell check (TEXT-11). English-only for v0.2 — the bundled wordlist is
  /// en-US, and non-English dictionaries are a recorded follow-up rather than
  /// a half-built option here.
  bool spellCheckEnabled = true;

  void setSpellCheck(bool v) {
    spellCheckEnabled = v;
    _repo.setSetting('spellCheck', v);
    // Re-open the editing session so the change is visible immediately rather
    // than at the next block.
    docRevision++;
    notifyListeners();
  }

  /// Eraser behaviour (INK-6). Session-scoped like tool/penSize — a mode, not
  /// a preference.
  EraserMode eraserMode = EraserMode.area;

  void setEraserMode(EraserMode m) {
    eraserMode = m;
    notifyListeners();
  }

  /// Whether a finger draws (INK-1). Until 2026-07-27 every touch was routed to
  /// pan unconditionally, which meant ink was unreachable on a touch-only
  /// tablet — palm rejection implemented as "fingers never draw" rather than
  /// "fingers don't draw *while a pen is in use*".
  TouchDrawing touchDrawing = TouchDrawing.auto;

  void setTouchDrawing(TouchDrawing v) {
    touchDrawing = v;
    _repo.setSetting('touchDrawing', v.name);
    notifyListeners();
  }

  /// True when the selection is ink and can therefore be recoloured (INK-7).
  bool get hasInkSelection =>
      blocks.any((b) => selectedIds.contains(b.id) && b.type == BlockType.ink);

  /// Recolour every stroke in the selected ink blocks.
  ///
  /// Completes the lasso story: gathering, moving and deleting worked, but a
  /// lassoed diagram couldn't be changed — and recolouring after the fact is
  /// most of why you'd lasso a diagram at all. Resizing came free once blocks
  /// gained ink-scaling handles.
  void recolorSelectedInk(String hex) {
    if (!hasInkSelection) return;
    pushUndo();
    for (final b in blocks) {
      if (!selectedIds.contains(b.id) || b.type != BlockType.ink) continue;
      final strokes = b.content['strokes'];
      if (strokes is! List) continue;
      for (final raw in strokes) {
        if (raw is Map) raw['color'] = hex;
      }
      b.updatedAt = nowMs();
    }
    markDirty();
    docRevision++;
    notifyListeners();
  }

  /// Guides to draw while dragging (CANVAS-7), and the snap they imply.
  List<AlignGuide> alignGuides = const [];
  Offset _pendingSnap = Offset.zero;

  /// Recompute guides for the current selection against its neighbours.
  ///
  /// [scale] converts the fixed screen-pixel tolerance into page units, so the
  /// guide feels equally sticky at every zoom — a fixed page-unit threshold is
  /// unreachable zoomed out and glue-like zoomed in.
  void updateAlignGuides(double scale) {
    if (selectedIds.isEmpty || snapToGrid) {
      // Snap-to-grid already decides placement; two competing snaps fight.
      if (alignGuides.isNotEmpty) {
        alignGuides = const [];
        _pendingSnap = Offset.zero;
      }
      return;
    }
    final moving = _unionRect(selectedIds);
    if (moving == null) return;
    final others = [
      for (final b in blocks)
        if (!selectedIds.contains(b.id)) _rectOf(b)
    ];
    final r = findAlignment(moving, others, threshold: 7.0 / scale);
    alignGuides = r.guides;
    _pendingSnap = r.offset;
  }

  /// Apply the snap the guides promised, on drag end.
  ///
  /// Deliberately at the END rather than live: nudging mid-drag makes the
  /// block jitter against the pointer, which reads as the app fighting you.
  void applyAlignSnap() {
    if (_pendingSnap != Offset.zero) {
      moveSelectedBy(_pendingSnap.dx, _pendingSnap.dy);
      _pendingSnap = Offset.zero;
    }
    alignGuides = const [];
  }

  Rect _rectOf(Block b) =>
      Rect.fromLTWH(b.x, b.y, b.w, b.h ?? renderSizes[b.id]?.height ?? 60);

  Rect? _unionRect(Set<String> ids) {
    Rect? out;
    for (final b in blocks.where((b) => ids.contains(b.id))) {
      final r = _rectOf(b);
      out = out == null ? r : out.expandToInclude(r);
    }
    return out;
  }

  // True while a block is being dragged — the canvas shows a faint grid then.
  bool draggingBlock = false;
  void setDragging(bool v) {
    if (draggingBlock == v) return;
    draggingBlock = v;
    notifyListeners();
  }

  // Collapse state (OneNote-style hierarchy folding). Sections no longer
  // collapse — the stacked navigator shows one section's pages at a time, so
  // the old per-section collapse set had no readers once the tree layout went.
  final Set<String> collapsedPages = {};

  void togglePageCollapsed(String id) {
    collapsedPages.contains(id)
        ? collapsedPages.remove(id)
        : collapsedPages.add(id);
    navRevision++; // lengths can alias (one collapse + one expand); this can't
    notifyListeners();
  }

  // ── UI chrome state (Phase 2) ──────────────────────────────────────────

  ThemeMode themeMode = ThemeMode.system;
  void setThemeMode(ThemeMode m) {
    themeMode = m;
    _repo.setSetting('themeMode', m.name); // persist (§7a.5)
    notifyListeners();
  }

  /// The text/code editor currently mounted & editing, registered by its view
  /// so command-bar formatting can act on the live selection.
  ({
    TextEditingController controller,
    Block block,
    String contentKey
  })? activeEditor;

  /// The same editor as [activeEditor], through the engine seam.
  ///
  /// The canvas needs two things a bare controller can't give it: where a
  /// screen point lands in the text, and a way to extend the selection. Both
  /// live on the session, so the pointer handling in `block_view.dart` can
  /// place the caret where you clicked and drag-select from the first gesture
  /// without knowing how the engine lays text out.
  OnoteEditSession? activeSession;

  void setActiveEditor(TextEditingController c, Block b, String key,
      {OnoteEditSession? session}) {
    activeEditor = (controller: c, block: b, contentKey: key);
    if (session != null) activeSession = session;
    // No notify: called during build; enablement rides the select() notify.
  }

  void clearActiveEditor(String blockId) {
    if (activeEditor?.block.id == blockId) {
      activeEditor = null;
      activeSession = null;
    }
  }

  /// Where the click that is about to open an editor landed. Consumed once by
  /// the session on its first build.
  Offset? pendingCaretGlobal;

  void _commitActiveEditor() {
    final ae = activeEditor;
    if (ae == null) return;
    ae.block.content[ae.contentKey] = ae.controller.text;
    ae.block.updatedAt = nowMs();
    markDirty();
  }

  /// True when the block being edited is a text box (enables the Home-tab
  /// formatting buttons immediately, independent of child build order).
  bool get canFormatText {
    final id = editingBlockId;
    if (id == null) return false;
    return blocks.where((b) => b.id == id).firstOrNull?.type == BlockType.text;
  }

  /// Insert text at the caret of the active editor (e.g. a page link inline).
  void insertTextAtActiveCursor(String s) {
    final ae = activeEditor;
    if (ae == null) return;
    final c = ae.controller;
    final sel = c.selection;
    final at = sel.isValid ? sel.start : c.text.length;
    final end = sel.isValid ? sel.end : c.text.length;
    pushUndo();
    c.text = c.text.replaceRange(at, end, s);
    c.selection = TextSelection.collapsed(offset: at + s.length);
    _commitActiveEditor();
    notifyListeners();
  }

  // ── Text colour (inline {{#RRGGBB text}}) ──────────────────────────────

  String lastColor = 'C63838'; // last-used ink colour; default red
  final List<String> customColors = []; // recent/custom, persisted
  void rememberCustomColor(String hex) {
    customColors.remove(hex);
    customColors.insert(0, hex);
    if (customColors.length > 12) customColors.removeLast();
    _repo.setSetting('customColors', customColors);
    notifyListeners();
  }

  static final _colorOpenRe =
      RegExp(r'\{\{#([0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?) $');
  // Matches a whole wrapper as the entire selection: {{#hex inner}}.
  static final _colorWholeRe = RegExp(
      r'^\{\{#([0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?) (.*)\}\}$',
      dotAll: true);

  void applyTextColor(String hex) {
    final ae = activeEditor;
    if (ae == null) return;
    lastColor = hex;
    final c = ae.controller;
    final sel = c.selection;
    if (!sel.isValid || sel.isCollapsed) {
      notifyListeners();
      return;
    }
    final t = c.text;
    final s = math.min(sel.baseOffset, sel.extentOffset);
    final e = math.max(sel.baseOffset, sel.extentOffset);

    // Re-colour, don't nest (user report): if the selection is already the
    // inner content of an existing {{#hex …}} wrapper, or the selection spans
    // a whole wrapper, replace the existing colour in place.

    // Case A: selection is the INNER content of an existing wrapper —
    //   …{{#oldhex |selected|}}…  → swap oldhex for the new hex.
    final openBefore = _colorOpenRe.firstMatch(t.substring(0, s));
    if (openBefore != null &&
        e + 2 <= t.length &&
        t.substring(e, e + 2) == '}}') {
      pushUndo();
      final openLen = openBefore.group(0)!.length;
      const newOpenPrefix = '{{#';
      final newOpen = '$newOpenPrefix$hex ';
      c.text = t.replaceRange(s - openLen, s, newOpen);
      final shift = newOpen.length - openLen;
      c.selection =
          TextSelection(baseOffset: s + shift, extentOffset: e + shift);
      _commitActiveEditor();
      notifyListeners();
      return;
    }

    // Case B: the selection spans an ENTIRE wrapper — {{#oldhex inner}} —
    // e.g. selecting the coloured word including its markers. Rewrite it.
    final whole = _colorWholeRe.firstMatch(t.substring(s, e));
    if (whole != null) {
      pushUndo();
      final inner = whole.group(2)!;
      c.text = t.replaceRange(s, e, '{{#$hex $inner}}');
      final openLen = hex.length + 4; // '{{#' + hex + ' '
      c.selection = TextSelection(
          baseOffset: s + openLen, extentOffset: s + openLen + inner.length);
      _commitActiveEditor();
      notifyListeners();
      return;
    }

    // Case C: fresh selection — wrap it.
    pushUndo();
    final selText = t.substring(s, e);
    c.text = t.replaceRange(s, e, '{{#$hex $selText}}');
    final openLen = hex.length + 4; // '{{#' + hex + ' '
    c.selection = TextSelection(
        baseOffset: s + openLen, extentOffset: s + openLen + selText.length);
    _commitActiveEditor();
    notifyListeners();
  }

  /// The "flick" hotkey: colour the selection with the last colour, or strip
  /// the colour if it's already coloured (back to default).
  void toggleTextColor() {
    final ae = activeEditor;
    if (ae == null) return;
    final c = ae.controller;
    final sel = c.selection;
    if (!sel.isValid || sel.isCollapsed) return;
    final s = math.min(sel.baseOffset, sel.extentOffset);
    final e = math.max(sel.baseOffset, sel.extentOffset);
    final t = c.text;
    final m = _colorOpenRe.firstMatch(t.substring(0, s));
    if (m != null && e + 2 <= t.length && t.substring(e, e + 2) == '}}') {
      pushUndo();
      final openLen = m.group(0)!.length;
      c.text = t.replaceRange(e, e + 2, '').replaceRange(s - openLen, s, '');
      c.selection =
          TextSelection(baseOffset: s - openLen, extentOffset: e - openLen);
      _commitActiveEditor();
      notifyListeners();
    } else {
      applyTextColor(lastColor);
    }
  }

  // ── Text-box font family (box-level) ───────────────────────────────────

  void setActiveBlockFont(String font) {
    final id = editingBlockId;
    if (id == null) return;
    final b = blocks.where((x) => x.id == id).firstOrNull;
    if (b == null || b.type != BlockType.text) return;
    pushUndo();
    // Any system family name; '' or 'sans' = default. Legacy 'serif'/'mono'
    // map in the view.
    if (font.isEmpty || font == 'sans') {
      b.content.remove('font');
    } else {
      b.content['font'] = font;
    }
    updateBlock(b);
  }

  /// The font size of the text block being edited, in logical px, or null when
  /// it uses the default. Imported OneNote boxes carry an explicit size.
  double? get activeBlockFontSize {
    final id = editingBlockId;
    if (id == null) return null;
    final b = blocks.where((x) => x.id == id).firstOrNull;
    if (b == null || b.type != BlockType.text) return null;
    return (b.content['fontSize'] as num?)?.toDouble();
  }

  /// Set (or clear, with null) the font size of the text block being edited
  /// (TEXT-1). Sizes are offered in points and stored in the page's 120-dpi px.
  void setActiveBlockFontSize(double? pt) {
    final id = editingBlockId;
    if (id == null) return;
    final b = blocks.where((x) => x.id == id).firstOrNull;
    if (b == null || b.type != BlockType.text) return;
    pushUndo();
    if (pt == null) {
      b.content.remove('fontSize');
      b.content.remove('lineHeight');
    } else {
      b.content['fontSize'] = pt * 120.0 / 72.0;
      // Keep OneNote's pitch so a resized box still lines up with its
      // neighbours (see `oneNoteLineHeight`).
      b.content['lineHeight'] = oneNoteLineHeight;
    }
    updateBlock(b);
  }

  // ── New-page title flow ────────────────────────────────────────────────

  String? pendingTitleEdit; // page whose title should auto-focus on show

  /// Enter pressed in the title → drop into the first body text box.
  void startBodyFromTitle() {
    final pos = smartTextPosition(const Offset(pageLeftMargin, contentTop));
    final b = addBlock(Block(
        type: BlockType.text,
        x: pos.dx,
        y: pos.dy,
        w: 320,
        content: {'text': ''}));
    select(b.id, edit: true);
  }

  /// Toggle-wrap the live selection with markers (Ctrl+B/I, command bar).
  void wrapSelection(String mark, [String? closeMark]) {
    final ae = activeEditor;
    if (ae == null) return;
    final c = ae.controller;
    final sel = c.selection;
    if (!sel.isValid) return;
    final close = closeMark ?? mark;
    final s = math.min(sel.baseOffset, sel.extentOffset);
    final e = math.max(sel.baseOffset, sel.extentOffset);
    final t = c.text;
    pushUndo();
    final already = s >= mark.length &&
        e + close.length <= t.length &&
        t.substring(s - mark.length, s) == mark &&
        t.substring(e, e + close.length) == close;
    if (already) {
      c.text = t
          .replaceRange(e, e + close.length, '')
          .replaceRange(s - mark.length, s, '');
      c.selection = TextSelection(
          baseOffset: s - mark.length, extentOffset: e - mark.length);
    } else {
      c.text = t.replaceRange(s, e, '$mark${t.substring(s, e)}$close');
      c.selection = TextSelection(
          baseOffset: s + mark.length, extentOffset: e + mark.length);
    }
    _commitActiveEditor();
    notifyListeners();
  }

  /// Toggle a line prefix (headings, lists, checkboxes) on the selected lines.
  void toggleLinePrefix(String prefix, {bool exclusive = true}) {
    final ae = activeEditor;
    if (ae == null) return;
    final c = ae.controller;
    final sel = c.selection;
    if (!sel.isValid) return;
    pushUndo();
    final t = c.text;
    final s = math.min(sel.baseOffset, sel.extentOffset);
    final e = math.max(sel.baseOffset, sel.extentOffset);
    final lineStart = t.lastIndexOf('\n', math.max(0, s - 1)) + 1;
    var lineEnd = t.indexOf('\n', e);
    if (lineEnd < 0) lineEnd = t.length;
    final region = t.substring(lineStart, lineEnd);
    final stripRe = exclusive
        ? RegExp(r'^(#{1,3} |- \[[ xX]\] |[-*] |\d+\. |> )')
        : RegExp('^${RegExp.escape(prefix)}');
    final lines = region.split('\n');
    final allHave = lines.every((l) => l.startsWith(prefix));
    final out = [
      for (final l in lines)
        allHave
            ? l.substring(prefix.length)
            : '$prefix${l.replaceFirst(stripRe, '')}'
    ].join('\n');
    c.text = t.replaceRange(lineStart, lineEnd, out);
    c.selection = TextSelection.collapsed(
        offset: math.min(lineStart + out.length, c.text.length));
    _commitActiveEditor();
    notifyListeners();
  }

  // ── Block clipboard (internal, Ctrl+C/X/V when not typing) ────────────

  String? _blockClipboard;
  bool get canPasteBlocks => _blockClipboard != null;

  void copySelectedBlocks() {
    if (selectedIds.isEmpty) return;
    _blockClipboard = jsonEncode([
      for (final b in blocks.where((b) => selectedIds.contains(b.id)))
        b.toJson()
    ]);
    notifyListeners();
  }

  void cutSelectedBlocks() {
    copySelectedBlocks();
    removeSelected();
  }

  void pasteBlocks({Offset? at}) {
    final raw = _blockClipboard;
    if (raw == null) return;
    pushUndo();
    final list = (jsonDecode(raw) as List)
        .map((j) => Block.fromJson((j as Map).cast<String, dynamic>()))
        .toList();
    // Fresh identities (Data Model §2 rule 3), offset placement.
    final newIds = <String>[];
    for (final src in list) {
      final fresh = Block(
        id: newId(),
        type: src.type,
        x: (at?.dx ?? src.x + 28),
        y: (at?.dy ?? src.y + 28),
        w: src.w,
        h: src.h,
        placement: src.placement,
        content: jsonDecode(jsonEncode(src.content)) as Map<String, dynamic>,
      );
      if (fresh.type == BlockType.ink) {
        final dx = fresh.x - src.x, dy = fresh.y - src.y;
        for (final sj in (fresh.content['strokes'] as List)) {
          final m = (sj as Map);
          m['id'] = newId();
          m['x'] = [for (final v in (m['x'] as List)) (v as num) + dx];
          m['y'] = [for (final v in (m['y'] as List)) (v as num) + dy];
        }
      }
      clampBlockToPage(fresh);
      blocks.add(fresh);
      newIds.add(fresh.id);
    }
    selectMany(newIds);
    markDirty();
  }

  // ── Z-order (context menu) ─────────────────────────────────────────────

  void bringToFront(String id) {
    final b = blocks.where((b) => b.id == id).firstOrNull;
    if (b == null || blocks.isEmpty) return;
    pushUndo();
    b.z = blocks.map((e) => e.z).reduce(math.max) + 1;
    updateBlock(b);
  }

  void sendToBack(String id) {
    final b = blocks.where((b) => b.id == id).firstOrNull;
    if (b == null || blocks.isEmpty) return;
    pushUndo();
    b.z = blocks.map((e) => e.z).reduce(math.min) - 1;
    updateBlock(b);
  }

  // True while the in-page title field is focused (suppresses tool shortcuts).
  bool titleEditing = false;
  void setTitleEditing(bool v) {
    titleEditing = v;
    notifyListeners();
  }

  // Find (TEXT-7)
  bool findOpen = false;
  String findQuery = '';
  List<String> findMatches = [];
  int findIndex = 0;

  // Save & undo
  Timer? _saveDebounce;
  bool _dirty = false;
  bool get hasUnsavedChanges => _dirty;
  final List<String> _undo = [];
  final List<String> _redo = [];
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  // ── Document engine (Rust core, optional) ─────────────────────────────

  /// Human-readable label for the active engine, shown in the status bar
  /// ("Rust core vX" or "Dart engine").
  String get engineLabel => engine.label;

  /// Content hash of the most recently saved page (Rust core only); drives the
  /// status-bar chip. Null on the pure-Dart engine.
  String? get pageContentHash => engine.lastSavedHash;

  Future<void> init() async {
    // Session restore (§7a.5): theme, custom colours, per-page views, last loc.
    final tm = _repo.getSetting('themeMode') as String?;
    if (tm != null) themeMode = ThemeMode.values.asNameMap()[tm] ?? themeMode;
    final nsw = _repo.getSetting('navSectionsW');
    if (nsw is num) navSectionsW = nsw.toDouble().clamp(96, 220);
    final npw = _repo.getSetting('navPagesW');
    if (npw is num) navPagesW = npw.toDouble().clamp(140, 320);
    final nc = _repo.getSetting('navCollapsed');
    if (nc is bool) navCollapsed = nc;
    final slp = _repo.getSetting('sectionLastPage');
    if (slp is Map) {
      slp.forEach((k, v) {
        if (k is String && v is String) _sectionLastPage[k] = v;
      });
    }
    final as = _repo.getSetting('autoSync');
    if (as is bool) autoSync = as;
    final sc = _repo.getSetting('spellCheck');
    if (sc is bool) spellCheckEnabled = sc;
    onboardingSeen = _repo.getSetting('onboardingSeen') == true;
    // Personal dictionary: workspace-scoped and deliberately NOT synced — one
    // person's jargon shouldn't become everyone's on a shared notebook.
    final lw = _repo.getSetting('learnedWords');
    if (lw is List) loadLearnedWords(lw.cast<String>());
    onLearnedChanged = (words) => _repo.setSetting('learnedWords', words);
    final mi = _repo.getSetting('mirrors');
    if (mi is Map) {
      mi.forEach((k, v) {
        if (v is! List) return;
        _mirrors['$k'] = [
          for (final t in v)
            if (MirrorTarget.fromJson(t) case final m?) m
        ];
      });
    }
    loadSyncRoots();
    _startSyncStatusPolling();
    study.load();
    planner.load();
    // Armed only once state is restored: the scheduler's first act is to catch
    // up on what came due while Openote was closed, and it can only know that
    // after the reminders have been read.
    planner.startScheduler();
    final fav = _repo.getSetting('favourites');
    if (fav is List) _favourites.addAll(fav.cast<String>());
    final rec = _repo.getSetting('recentPages');
    if (rec is List) _recents.addAll(rec.cast<String>());
    final td = _repo.getSetting('touchDrawing') as String?;
    if (td != null) {
      touchDrawing = TouchDrawing.values.asNameMap()[td] ?? touchDrawing;
    }
    final cc = _repo.getSetting('customColors');
    if (cc is List) customColors.addAll(cc.cast<String>());
    final vm = _repo.getSetting('viewMemory');
    if (vm is Map) {
      vm.forEach((k, v) {
        if (v is List && v.length == 3) {
          _viewMemory[k as String] = [for (final x in v) (x as num).toDouble()];
        }
      });
    }
    final lastNb = _repo.getSetting('lastNotebook') as String?;
    // A workspace with no notebooks at all shouldn't happen — Repository.open
    // seeds one — but `first` on an empty list throws, which would turn an
    // odd registry into a startup that shows only an error screen. Making one
    // is always better than refusing to start.
    if (_repo.notebooks.isEmpty) await _repo.createNotebook('My notebook');
    notebookId = _repo.notebooks.any((n) => n.id == lastNb)
        ? lastNb!
        : _repo.notebooks.first.id;
    // Clear out anything that has outlived the recycle-bin retention window.
    await _repo.purgeExpiredNotebooks();
    _repo.purgeExpiredNodes(notebookId!);
    reloadNodes();
    // Replay the open notebook's log in a background isolate, starting now.
    // This used to happen synchronously inside `_startWatching` on the first
    // frame — for a freshly imported notebook that is a multi-megabyte log,
    // and it was most of "the app is locked up for the first few seconds
    // after launching".
    unawaited(warmRecorder(notebookId!));
    // Watch for other devices once the notebook is open.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startWatching());
    final lastPage = _repo.getSetting('lastPage') as String?;
    final target = nodes.any((n) => n.id == lastPage && n.kind == NodeKind.page)
        ? lastPage
        : nodes.where((n) => n.kind == NodeKind.page).firstOrNull?.id;
    await selectPage(target);
  }

  // ── Per-page view memory (§7a.5) ───────────────────────────────────────

  final Map<String, List<double>> _viewMemory = {};

  List<double>? viewFor(String id) => _viewMemory[id];

  void _rememberView() {
    final id = pageId;
    if (id == null) return;
    _viewMemory[id] = [canvas.scale, canvas.offset.dx, canvas.offset.dy];
    if (_viewMemory.length > 300) _viewMemory.remove(_viewMemory.keys.first);
  }

  void _persistSession() {
    _repo.setSetting('viewMemory', _viewMemory);
    _repo.setSetting('lastNotebook', notebookId);
    _repo.setSetting('lastPage', pageId);
  }

  Future<void> _loadNotebook() async {
    reloadNodes();
    // Reset the focused section for the new notebook (selectPage refines it).
    activeSectionId =
        nodes.where((n) => n.kind == NodeKind.section).firstOrNull?.id;
    final firstPage = nodes.where((n) => n.kind == NodeKind.page).firstOrNull;
    await selectPage(firstPage?.id);
  }

  Future<void> selectNotebook(String id) async {
    await flushSave();
    notebookId = id;
    // Replay this notebook's log in the background now, so the first edit
    // finds a ready recorder instead of paying the replay synchronously.
    unawaited(warmRecorder(id));
    await _loadNotebook();
    notifyListeners();
  }

  Future<void> createNotebook(String title) async {
    await flushSave();
    final ref = await _repo.createNotebook(title);
    await selectNotebook(ref.id);
  }

  /// Whether the welcome flow has run for this workspace.
  bool onboardingSeen = false;
  void markOnboardingSeen() {
    if (onboardingSeen) return;
    onboardingSeen = true;
    _repo.setSetting('onboardingSeen', true);
  }

  /// Open a `.onote` that already exists on disk — the second-device flow.
  Future<void> openExistingNotebook(String path) async {
    await flushSave();
    final ref = await _repo.openExistingNotebook(path);
    // Joining a notebook from a folder is the other moment the user tells us
    // where their sync lives — this device's logs go into that folder, so it
    // is a sync root by definition.
    rememberSyncRoot(p.dirname(path));
    await selectNotebook(ref.id);
  }

  Future<void> renameNotebook(String id, String title) async {
    await _repo.renameNotebook(id, title);
    _recorderFor(id)?.notebookMeta({'title': title});
    notifyListeners();
  }

  /// Duplicate a notebook (contents included) without switching to it.
  Future<NotebookRef> duplicateNotebook(String id) async {
    await flushSave(); // the copy is a byte copy — settle pending writes first
    final ref = await _repo.duplicateNotebook(id);
    notifyListeners();
    return ref;
  }

  ({int sections, int pages}) notebookCounts(String id) =>
      _repo.notebookCounts(id);

  /// Soft-delete a notebook to the recycle bin. Refuses the last one (there's
  /// always somewhere to be). Returns false if it couldn't (only notebook).
  Future<bool> deleteNotebook(String id) async {
    if (_repo.notebooks.length <= 1) return false;
    await flushSave();
    final wasCurrent = id == notebookId;
    await _repo.trashNotebook(id);
    if (wasCurrent) {
      notebookId = _repo.notebooks.first.id;
      await _loadNotebook();
    }
    notifyListeners();
    return true;
  }

  List<NotebookRef> get trashedNotebooks => _repo.trashedNotebooks;

  /// How long trashed items live before auto-deletion (recycle-bin retention).
  int get recycleRetentionDays => Repository.recycleRetentionDays;

  /// Sweep expired recycle-bin entries (notebooks + the current notebook's
  /// nodes). Runs at startup and whenever the recycle bin is opened.
  Future<void> purgeExpiredTrash() async {
    await _repo.purgeExpiredNotebooks();
    if (notebookId != null) _repo.purgeExpiredNodes(notebookId!);
    notifyListeners();
  }

  Future<void> restoreNotebook(String id) async {
    await _repo.restoreNotebook(id);
    notifyListeners();
  }

  Future<void> purgeNotebook(String id) async {
    await _repo.purgeNotebook(id);
    notifyListeners();
  }

  /// Throw away a notebook that was never the user's — the half-built target of
  /// a cancelled or crashed import. Not the recycle bin: see
  /// [Repository.discardNotebook].
  Future<void> discardImportedNotebook(String id) async {
    _importingNotebooks.remove(id);
    // Settle any background replay FIRST. It writes the manifest on its way
    // through, so deleting the directory out from under one leaves the
    // recreated husk behind.
    final warm = _recorderWarms[id];
    if (warm != null) {
      try {
        await warm;
      } catch (_) {/* a failed warm is not this operation's problem */}
    }
    _recorders.remove(id);
    await _repo.discardNotebook(id);
    _invalidateSyncStatus();
    notifyListeners();
  }

  Future<void> selectPage(String? id) async {
    _rememberView(); // keep your place when flicking between pages (§7a.5)
    await flushSave();
    pageId = id;
    select(null);
    _undo.clear();
    _redo.clear();
    renderSizes.clear();
    findMatches = [];
    findQuery = '';
    if (id == null) {
      blocks = [];
      pageProps = PageProps();
    } else {
      final data = await engine.loadPage(notebookId!, id);
      blocks = data.blocks;
      pageProps = data.props;
      _repairImportedFieldCodes();
      // Heal a page whose content sits under the title band (§7f). Marked
      // dirty only when something actually moved, so merely opening pages
      // does not rewrite the notebook.
      if (repairTitleBandOverlap() > 0) markDirty();
      // Keep the navigator's focused section in sync with the open page, and
      // remember it as the section's place so activateSection can come back
      // here. Selecting a page also leaves Home — the pane shows the
      // destination's siblings, which is what "I went somewhere" looks like.
      navHome = false;
      final parent = nodes.where((n) => n.id == id).firstOrNull?.parentId;
      if (parent != null) {
        activeSectionId = parent;
        _rememberSectionPage(parent, id);
      }
      _recordRecent(id);
    }
    docRevision++;
    _persistSession();
    notifyListeners();
  }

  /// Heal Word/OneNote field codes left in an already-imported page.
  ///
  /// The importer emitted a hyperlink as raw Word field scaffolding —
  /// `﷟HYPERLINK "https://…"` sitting next to the words it was attached to,
  /// unclickable. Fixing the importer does nothing for notes imported before
  /// the fix, and asking a student to re-import a term's notes to get their
  /// links back is not a fix. So a page repairs itself the first time it is
  /// opened.
  ///
  /// Cost on a clean page is one substring test per text block over text that
  /// is already in memory — no database read, no allocation, nothing written.
  /// The conversion itself is the Rust importer's own, over FFI, so there is
  /// exactly one parser rather than two that drift apart.
  /// Heal one page's blocks in place. Returns how many blocks changed.
  ///
  /// Shared by the on-open repair and the whole-notebook one so the two can
  /// never diverge — an imported page must end up identical whichever route
  /// reached it.
  int _healBlocks(List<Block> blocks, OnoteCore core) {
    String? repair(String text) {
      if (!textNeedsFieldRepair(text)) return null;
      final fixed = core.repairFieldCodes(text);
      return (fixed == text || fixed.isEmpty) ? null : fixed;
    }

    var changed = 0;
    for (final b in blocks) {
      if (b.type == BlockType.table) {
        final rows = b.content['cells'];
        if (rows is! List) continue;
        var touched = false;
        final out = <List<String>>[];
        for (final row in rows) {
          final cells = <String>[];
          for (final c in (row is List ? row : const [])) {
            final text = c?.toString() ?? '';
            final fixed = repair(text);
            if (fixed != null) touched = true;
            cells.add(fixed ?? text);
          }
          out.add(cells);
        }
        if (touched) {
          b.content['cells'] = out;
          b.updatedAt = nowMs();
          changed++;
        }
        continue;
      }
      final text = b.content['text'];
      if (text is! String) continue;
      final fixed = repair(text);
      if (fixed != null) {
        b.content['text'] = fixed;
        b.updatedAt = nowMs();
        changed++;
      }
    }
    return changed;
  }

  /// Heal EVERY page in the notebook, not just the ones you happen to open.
  ///
  /// The on-open repair is lazy by design — it costs nothing on a clean page
  /// — but on a notebook imported before the importer was fixed that means
  /// hundreds of pages keep their `﷟HYPERLINK "…"` junk and their needless
  /// `$…$` until the day you next visit them. This is the "just fix all of
  /// it" button, and it is worth having as an explicit action rather than a
  /// startup cost nobody asked for.
  ///
  /// Yields between chunks so a 300-page notebook doesn't freeze the window,
  /// and commits per chunk so an interruption keeps what it already fixed.
  Future<({int pages, int blocks})> repairWholeNotebook({
    void Function(int done, int total)? onProgress,
  }) async {
    final core = OnoteCore.instance;
    final nb = notebookId;
    if (core == null || nb == null) return (pages: 0, blocks: 0);
    await flushSave();

    final pages = nodes.where((n) => n.kind == NodeKind.page).toList();
    var healedPages = 0, healedBlocks = 0, done = 0;
    const chunk = 12;

    for (var start = 0; start < pages.length; start += chunk) {
      final end = (start + chunk).clamp(0, pages.length);
      importBatch(nb, () {
        for (var i = start; i < end; i++) {
          final n = pages[i];
          // The open page is already in memory and owns unsaved edits.
          final data =
              n.id == pageId ? PageData(blocks, pageProps) : readPage(n.id);
          final changed = _healBlocks(data.blocks, core);
          if (changed == 0) continue;
          healedPages++;
          healedBlocks += changed;
          importPage(nb, n.id, data.blocks, data.props);
        }
      });
      done = end;
      onProgress?.call(done, pages.length);
      await Future<void>.delayed(Duration.zero);
    }

    // The open page's blocks may have been rewritten in place above.
    docRevision++;
    notifyListeners();
    return (pages: healedPages, blocks: healedBlocks);
  }

  void _repairImportedFieldCodes() {
    final core = OnoteCore.instance;
    if (core == null) return; // Dart-only build: leave the text untouched.

    // Worked out on a COPY first, so the undo checkpoint below captures the
    // page as it was on disk rather than as it will be.
    final before = [for (final b in blocks) Block.fromJson(b.toJson())];
    if (_healBlocks(before, core) == 0) return;

    // Undoable. This is the one automatic path that rewrites text the user
    // already owns, and it runs the moment a page opens — without a checkpoint
    // there is no way back if the conversion reads a paragraph wrong. The
    // stack was cleared by `selectPage` just above, so this becomes its first
    // entry: one Ctrl+Z restores exactly what was on disk.
    pushUndo();
    _healBlocks(blocks, core);
    // Save through the normal funnel so the op log records it and the change
    // reaches other devices — a repair that only ever ran locally would have
    // to run again on every one of them.
    markDirty();
  }

  // ── Version history (SYNC-8) ───────────────────────────────────────────

  List<int> pageVersions() =>
      pageId == null ? [] : _repo.listVersions(notebookId!, pageId!);

  Future<void> restoreVersion(int at) async {
    if (pageId == null) return;
    final json = _repo.versionJson(notebookId!, pageId!, at);
    if (json == null) return;
    pushUndo();
    final j = jsonDecode(json) as Map<String, dynamic>;
    pageProps =
        PageProps.fromJson((j['page'] as Map?)?.cast<String, dynamic>());
    blocks = [
      for (final b in (j['blocks'] as List))
        Block.fromJson((b as Map).cast<String, dynamic>())
    ];
    docRevision++;
    markDirty();
    notifyListeners();
  }

  // ── Page templates (ORG-9) ─────────────────────────────────────────────

  /// Built-ins first, then the user's own. A user template that shares a
  /// built-in's name shadows it (their content wins in [applyTemplate]), so
  /// customising a built-in is just "save under the same name".
  List<String> templateNames() {
    final t = _repo.getSetting('templates');
    final user = t is Map ? t.keys.cast<String>().toList() : <String>[];
    return [
      ...builtinTemplates.keys,
      ...user.where((n) => !builtinTemplates.containsKey(n)),
    ];
  }

  void saveCurrentAsTemplate(String name) {
    final t =
        (_repo.getSetting('templates') as Map?)?.cast<String, dynamic>() ?? {};
    t[name] = jsonEncode({
      'page': pageProps.toJson(),
      'blocks': [for (final b in blocks) b.toJson()],
    });
    _repo.setSetting('templates', t);
    notifyListeners();
  }

  void applyTemplate(String name) {
    final t = _repo.getSetting('templates');
    // User template first so a same-named save shadows the built-in.
    final raw =
        (t is Map ? t[name] as String? : null) ?? builtinTemplates[name];
    if (raw == null) return;
    pushUndo();
    final j = jsonDecode(raw) as Map<String, dynamic>;
    pageProps =
        PageProps.fromJson((j['page'] as Map?)?.cast<String, dynamic>());
    for (final bj in (j['blocks'] as List)) {
      final src = Block.fromJson((bj as Map).cast<String, dynamic>());
      final fresh = Block(
        id: newId(),
        type: src.type,
        x: src.x,
        y: src.y,
        w: src.w,
        h: src.h,
        placement: src.placement,
        content: jsonDecode(jsonEncode(src.content)) as Map<String, dynamic>,
      );
      if (fresh.type == BlockType.ink) {
        for (final sj in (fresh.content['strokes'] as List)) {
          (sj as Map)['id'] = newId();
        }
      }
      blocks.add(fresh);
    }
    docRevision++;
    markDirty();
    notifyListeners();
  }

  // ── Page-surface geometry (CANVAS-1 v0.3) ──────────────────────────────

  static const double defaultPageHeight = 1400;
  static const double pageGrowMargin = 240;
  // In-page title band + left writing margin (OneNote-like page).
  static const double pageLeftMargin = 44;
  static const double titleBandHeight = 84; // title + date live here
  static const double contentTop = titleBandHeight + 8;

  /// Content-only extent (right & bottom edges), for page growth & fit.
  ({double right, double bottom}) contentExtent() {
    var right = pageLeftMargin, bottom = contentTop;
    for (final b in blocks) {
      final bh = b.h ?? renderSizes[b.id]?.height ?? estimatedHeight(b);
      if (b.x + b.w > right) right = b.x + b.w;
      if (b.y + bh > bottom) bottom = b.y + bh;
    }
    return (right: right, bottom: bottom);
  }

  /// A height for a block that has neither a stored one nor a measured one.
  ///
  /// `renderSizes` is only written by blocks that actually built, and the
  /// canvas culls everything outside the viewport — so a long note further
  /// down the page reports nothing at all. A flat 60px guess for it made
  /// [contentExtent] report a bottom edge ABOVE the real content, which is the
  /// wrong direction for every caller: the page stops growing early, fit-to-
  /// content clips, and anything that appends "below the last box" lands on
  /// top of the user's writing.
  ///
  /// Estimating from the text is coarse — it ignores wrapping, so it can still
  /// undershoot a long unwrapped paragraph — but it is far closer than a
  /// constant, and it errs low only where a constant erred catastrophically.
  double estimatedHeight(Block b) {
    if (b.type != BlockType.text) return 60;
    final text = b.content['text'] as String? ?? '';
    if (text.isEmpty) return 60;
    final size = (b.content['fontSize'] as num?)?.toDouble() ?? 15;
    final lh = (b.content['lineHeight'] as num?)?.toDouble() ?? 1.5;
    // Very rough wrap estimate: characters that fit across the box, at ~0.5em
    // per character for a proportional face.
    final perLine = ((b.w - 20) / (size * 0.5)).clamp(8, 400);
    var lines = 0;
    for (final l in text.split('\n')) {
      lines += l.isEmpty ? 1 : (l.length / perLine).ceil();
    }
    return (lines * size * lh + 16).clamp(36, 20000);
  }

  /// Content-based page size (used off-view, e.g. export). The on-screen page
  /// additionally grows to fill the viewport — computed in the canvas widget.
  Size pageSize() {
    final e = contentExtent();
    return Size(
      math.max(pageProps.pageWidth, e.right + pageGrowMargin),
      math.max(defaultPageHeight, e.bottom + pageGrowMargin),
    );
  }

  /// OneNote-style intelligent placement: create near the click, but align to
  /// the writing margin and to nearby content instead of landing pixel-exact.
  Offset smartTextPosition(Offset click) {
    const alignX = 56.0; // snap-to-left-edge threshold
    const alignY = 22.0; // snap-to-neighbour threshold
    final contentBlocks = blocks.where((b) => b.type != BlockType.ink).toList();

    // Empty page, clicked anywhere up top → the standard top-left spot.
    if (contentBlocks.isEmpty && click.dy < contentTop + 220) {
      return const Offset(pageLeftMargin, contentTop);
    }

    // X: snap to the writing margin or a nearby block's left edge.
    final xs = <double>[pageLeftMargin, ...contentBlocks.map((b) => b.x)];
    var x = click.dx;
    var bestX = double.infinity;
    for (final cx in xs) {
      if ((cx - click.dx).abs() < (bestX - click.dx).abs()) bestX = cx;
    }
    x = (bestX - click.dx).abs() < alignX
        ? bestX
        : math.max(click.dx, pageLeftMargin);

    // Y: snap just under a nearby block, or align with a block's top.
    var y = math.max(click.dy - 12, contentTop);
    final ys = <double>[];
    for (final b in contentBlocks) {
      final bh = b.h ?? renderSizes[b.id]?.height ?? 60;
      ys
        ..add(b.y)
        ..add(b.y + bh + 14);
    }
    var bestY = double.infinity;
    for (final cy in ys) {
      if ((cy - y).abs() < (bestY - y).abs()) bestY = cy;
    }
    if (bestY.isFinite && (bestY - y).abs() < alignY) y = bestY;

    return Offset(math.max(x, pageLeftMargin), math.max(y, contentTop));
  }

  Rect contentBounds() {
    if (blocks.isEmpty) return Rect.fromLTWH(0, 0, pageProps.pageWidth, 400);
    var r = Rect.zero;
    var first = true;
    for (final b in blocks) {
      final bh = b.h ?? renderSizes[b.id]?.height ?? 60;
      final br = Rect.fromLTWH(b.x, b.y, b.w, bh);
      r = first ? br : r.expandToInclude(br);
      first = false;
    }
    return r;
  }

  /// Content never above/left of the page origin (CANVAS-1 v0.3), and never
  /// underneath the title band (style guide §7f).
  ///
  /// The band is drawn as a `Positioned` overlay in the same coordinate space
  /// as the blocks, so a block placed above [contentTop] renders *through* the
  /// page title — the two strike each other out and neither is readable. The
  /// band already declared its height ([titleBandHeight]); nothing enforced it.
  /// The title is part of the page's layout, so the layout is where it is
  /// reserved.
  void clampBlockToPage(Block b) {
    if (b.x < 0) b.x = 0;
    if (b.y < contentTop) b.y = contentTop;
  }

  /// Push imported or legacy blocks out from under the title band.
  ///
  /// [clampBlockToPage] only runs on blocks the user moves. A page that
  /// arrived from the OneNote importer — or that was written before the band
  /// reserved its space — can already have content up there, and healing it on
  /// open is the same shape as `_repairImportedFieldCodes`.
  ///
  /// Returns how many blocks moved, so the caller can decide whether the page
  /// is dirty. The whole page shifts **together** when anything is above the
  /// band, rather than each stray block being clamped onto the same line: a
  /// note's blocks are positioned relative to each other, and collapsing two of
  /// them onto one y would destroy that.
  int repairTitleBandOverlap() {
    var top = double.infinity;
    for (final b in blocks) {
      if (b.y < top) top = b.y;
    }
    if (top == double.infinity || top >= contentTop) return 0;
    final shift = contentTop - top;
    for (final b in blocks) {
      b.y += shift;
    }
    return blocks.length;
  }

  // ── Tree ops ───────────────────────────────────────────────────────────

  static const _sectionColors = [
    'ink-500',
    'brass-400',
    'green',
    'blue',
    'violet',
    'red'
  ];

  Future<void> addSection({String? groupId}) async {
    final count = nodes.where((n) => n.kind == NodeKind.section).length;
    final n = _putNode(
        notebookId!,
        TreeNode(
            kind: NodeKind.section,
            parentId: groupId,
            title: 'Section ${count + 1}',
            color: _sectionColors[count % _sectionColors.length],
            position: _nextPosition()));
    reloadNodes();
    await addPage(sectionId: n.id);
  }

  void addSectionGroup() {
    final count = nodes.where((n) => n.kind == NodeKind.sectionGroup).length;
    _putNode(
        notebookId!,
        TreeNode(
            kind: NodeKind.sectionGroup,
            title: 'Group ${count + 1}',
            position: _nextPosition()));
    reloadNodes();
    notifyListeners();
  }

  Future<void> addPage({String? sectionId}) async {
    sectionId ??= sectionOf(pageId) ??
        nodes.where((n) => n.kind == NodeKind.section).firstOrNull?.id;
    if (sectionId == null) return;
    final n = _putNode(
        notebookId!,
        TreeNode(
            kind: NodeKind.page,
            parentId: sectionId,
            title: 'Untitled page',
            position: _nextPosition()));
    reloadNodes();
    await selectPage(n.id);
    pendingTitleEdit = n.id; // cursor lands in the title (OneNote behaviour)
    notifyListeners();
  }

  void renameNode(String id, String title) {
    final n = node(id);
    if (n == null) return; // deleted while a menu was open
    n.title = title;
    _putNode(notebookId!, n);
    bumpNodes();
    notifyListeners();
  }

  /// The colour tokens a section can be given, in picker order. `null` is the
  /// unset default, which renders in the app's own ink.
  static const List<String?> sectionColorTokens = [
    null,
    'brass-400',
    'green',
    'blue',
    'violet',
    'red',
  ];

  /// Recolour a section.
  ///
  /// The colour chip has always been rendered but only ever *written* by the
  /// OneNote importer, so on a notebook you started yourself every section was
  /// the same colour with no way to change it — a control that looks
  /// interactive and isn't.
  void setNodeColor(String id, String? token) {
    final n = node(id);
    if (n == null) return; // deleted while a menu was open
    n.color = token;
    _putNode(notebookId!, n);
    bumpNodes();
    notifyListeners();
  }

  /// Subpage indent (ORG-6): level 0..2.
  void indentPage(String id, int delta) {
    final n = node(id);
    if (n == null || n.kind != NodeKind.page) return;
    n.level = (n.level + delta).clamp(0, 2);
    _putNode(notebookId!, n);
    bumpNodes();
    notifyListeners();
  }

  /// Reorder among siblings (ORG-2, menu-driven for MVP).
  /// Drop [movingId] immediately before or after [targetId] among its siblings
  /// (ORG-2).
  ///
  /// Rebuilds every sibling's position rather than inventing a key between two
  /// neighbours: the position scheme is `'a' + padded-ms`, so there is no
  /// guaranteed gap between adjacent keys, and manufacturing one would collide
  /// eventually. Rewriting the run is O(siblings) and always correct.
  ///
  /// Subpages travel with their parent, for the same reason section sorting
  /// does it: the navigator renders hierarchy from contiguous runs, so moving
  /// a page without its children silently reparents them.
  void reorderNode(String movingId, String targetId, {required bool after}) {
    final moving = node(movingId), target = node(targetId);
    if (moving == null || target == null || movingId == targetId) return;
    if (moving.kind != target.kind) return;

    final siblings = nodes
        .where((s) => s.kind == moving.kind && s.parentId == target.parentId)
        .toList();
    if (siblings.isEmpty) return;

    // Group each top-level entry with the deeper-level run that follows it.
    final groups = <List<TreeNode>>[];
    for (final s in siblings) {
      if (s.level == 0 || groups.isEmpty) {
        groups.add([s]);
      } else {
        groups.last.add(s);
      }
    }
    final movingGroup =
        groups.where((g) => g.any((n) => n.id == movingId)).firstOrNull;
    if (movingGroup == null) return;
    // Dropping a page onto its own subpage would try to nest it inside itself.
    if (movingGroup.any((n) => n.id == targetId) &&
        movingGroup.first.id != targetId) {
      return;
    }
    groups.remove(movingGroup);
    final targetGroup =
        groups.where((g) => g.any((n) => n.id == targetId)).firstOrNull;
    final at = targetGroup == null
        ? groups.length
        : groups.indexOf(targetGroup) + (after ? 1 : 0);
    groups.insert(at.clamp(0, groups.length), movingGroup);

    pushUndo();
    // Re-parent in case the page came from another section.
    if (moving.parentId != target.parentId) {
      moving.parentId = target.parentId;
    }
    var seq = nowMs();
    for (final g in groups) {
      for (final n in g) {
        n.position = 'a${(seq++).toString().padLeft(15, '0')}';
        _putNode(notebookId!, n);
      }
    }
    reloadNodes();
    notifyListeners();
  }

  void moveNode(String id, int delta) {
    final n = node(id);
    if (n == null) return;
    final siblings = nodes
        .where((s) => s.kind == n.kind && s.parentId == n.parentId)
        .toList();
    final i = siblings.indexWhere((s) => s.id == id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= siblings.length) return;
    final other = siblings[j];
    final tmp = n.position;
    n.position = other.position;
    other.position = tmp;
    _putNode(notebookId!, n);
    _putNode(notebookId!, other);
    reloadNodes();
    notifyListeners();
  }

  void moveSectionToGroup(String sectionId, String? groupId) {
    final n = node(sectionId);
    if (n == null || n.kind != NodeKind.section) return;
    n.parentId = groupId;
    _putNode(notebookId!, n);
    reloadNodes();
    notifyListeners();
  }

  TreeNode? node(String? id) =>
      id == null ? null : nodes.where((n) => n.id == id).firstOrNull;

  // ── Recycle bin (ORG-7) ────────────────────────────────────────────────

  List<({String id, String kind, String title, int deletedAt})>
      deletedNodes() => _repo.loadDeletedNodes(notebookId!);

  Future<void> restoreDeleted(String id) async {
    _repo.restoreNode(notebookId!, id);
    // Restore is the ONLY thing that clears a delete (ADR-0006 §6a.3). An edit
    // must never resurrect a deleted node, or "delete wins" would silently
    // become "whichever device wrote last wins".
    _recorderFor(notebookId!)?.nodeRestored(id);
    reloadNodes();
    notifyListeners();
  }

  void purgeDeleted(String id) {
    _repo.purgeNode(notebookId!, id);
    _recorderFor(notebookId!)?.nodePurged(id);
    notifyListeners();
  }

  // ── Backlinks (TEXT-8) ─────────────────────────────────────────────────

  /// Page outline panel (TEXT-10).
  bool get showTocPanel => openPanel == SidePanelKind.outline;
  void toggleTocPanel() => togglePanel(SidePanelKind.outline);

  /// Headings on the current page, in reading order, for the outline panel.
  ///
  /// Cached on the same key as the links panel: without it, the panel rescans
  /// every block's Markdown on each notify — i.e. per keystroke — which is the
  /// exact cost the memoised navigator exists to avoid.
  ({
    String key,
    List<({String blockId, int level, String text})> items
  })? _tocCache;

  List<({String blockId, int level, String text})> pageOutline() {
    final key = '$pageId#$docRevision';
    final cached = _tocCache;
    if (cached != null && cached.key == key) return cached.items;
    final items = <({String blockId, int level, String text})>[];
    final ordered = [...blocks.where((b) => b.type == BlockType.text)]
      ..sort((a, b) => a.y.compareTo(b.y));
    for (final b in ordered) {
      final text = b.content['text'];
      if (text is! String) continue;
      for (final line in text.split('\n')) {
        final m = RegExp(r'^(#{1,3})\s+(.+)$').firstMatch(line.trimLeft());
        if (m == null) continue;
        items.add((
          blockId: b.id,
          level: m.group(1)!.length,
          text: m.group(2)!.trim(),
        ));
      }
    }
    _tocCache = (key: key, items: items);
    return items;
  }

  bool get showLinksPanel => openPanel == SidePanelKind.links;
  void toggleLinksPanel() => togglePanel(SidePanelKind.links);

  // The links panel is rebuilt on every notify while it's open, and both of
  // these are expensive: one is a synchronous SQLite query on the UI thread, the
  // other scans every text block. Cache them against (page, docRevision,
  // nodesRevision) so a keystroke doesn't re-run either.
  ({String key, List<TreeNode> back, List<TreeNode> out})? _linkCache;
  static final _outgoingLinkRe = RegExp(r'\[\[([^\]|]+)(?:\|([^\]]+))?\]\]');

  void _ensureLinks() {
    final key = '$pageId#$docRevision#$nodesRevision#${_dirty ? 1 : 0}';
    if (_linkCache?.key == key) return;
    final back = pageId == null
        ? <TreeNode>[]
        : _repo
            .backlinkPageIds(notebookId!, pageId!)
            .map(node)
            .whereType<TreeNode>()
            .toList();
    // Outgoing: `[[Title|id]]` resolves by id, a bare `[[Title]]` by title —
    // the panel used to ignore the bare form entirely.
    final out = <String, TreeNode>{};
    for (final b in blocks.where((b) => b.type == BlockType.text)) {
      for (final m
          in _outgoingLinkRe.allMatches(b.content['text'] as String? ?? '')) {
        final target =
            m.group(2) != null ? node(m.group(2)) : pageByTitle(m.group(1)!);
        if (target != null) out[target.id] = target;
      }
    }
    _linkCache = (key: key, back: back, out: out.values.toList());
  }

  List<TreeNode> backlinksForCurrent() {
    _ensureLinks();
    return _linkCache!.back;
  }

  /// Outgoing wiki-links found in the current page's text blocks.
  List<TreeNode> outgoingLinksForCurrent() {
    _ensureLinks();
    return _linkCache!.out;
  }

  List<TreeNode> get pages =>
      nodes.where((n) => n.kind == NodeKind.page).toList();

  TreeNode? pageByTitle(String title) {
    final t = title.trim().toLowerCase();
    return pages.where((p) => p.title.trim().toLowerCase() == t).firstOrNull;
  }

  /// Resolve a wiki-link target (EMBED-1): prefer the stable id, fall back to
  /// title match, and navigate.
  void openWikiLink(String label, String? id) {
    final target =
        (id != null && node(id) != null) ? id : pageByTitle(label)?.id;
    if (target != null) selectPage(target);
  }

  /// Insert a page-link (EMBED-1) as a new text block referencing the target
  /// by stable id: `[[Title|id]]`.
  void insertPageLink(String targetPageId) {
    final target = node(targetPageId);
    if (target == null) return;
    final pos = smartTextPosition(const Offset(pageLeftMargin, contentTop));
    final b = addBlock(Block(
      type: BlockType.text,
      x: pos.dx,
      y: pos.dy,
      w: 320,
      content: {'text': '[[${target.title}|${target.id}]]'},
    ));
    select(b.id);
  }

  /// Drag a page into another section (ORG-2): reparent, level 0, append.
  void movePageToSection(String pageId, String sectionId) {
    final n = node(pageId);
    final s = node(sectionId);
    if (n == null || n.kind != NodeKind.page || s?.kind != NodeKind.section) {
      return;
    }
    n
      ..parentId = sectionId
      ..level = 0
      ..position = _nextPosition();
    _putNode(notebookId!, n);
    reloadNodes();
    notifyListeners();
  }

  /// Drag a page onto another page → make it a subpage (ORG-6): same section,
  /// indented one level deeper, positioned right after the target.
  void makeSubpageOf(String pageId, String targetPageId) {
    if (pageId == targetPageId) return;
    final n = node(pageId);
    final target = node(targetPageId);
    if (n == null || target == null || target.kind != NodeKind.page) return;
    n
      ..parentId = target.parentId
      ..level = (target.level + 1).clamp(0, 2)
      // Sorts after the target (target.position is a prefix) and before its
      // next sibling; the full-millisecond suffix keeps repeated drops unique.
      ..position = '${target.position}m${nowMs().toString().padLeft(15, '0')}';
    _putNode(notebookId!, n);
    reloadNodes();
    notifyListeners();
  }

  void toggleGroupCollapsed(String id) {
    collapsedGroups.contains(id)
        ? collapsedGroups.remove(id)
        : collapsedGroups.add(id);
    navRevision++;
    notifyListeners();
  }

  Future<void> deleteNode(String id) async {
    _repo.softDeleteNode(notebookId!, id);
    _recorderFor(notebookId!)?.nodeDeleted(id);
    reloadNodes();
    if (pageId == id || !nodes.any((n) => n.id == pageId)) {
      await selectPage(
          nodes.where((n) => n.kind == NodeKind.page).firstOrNull?.id);
    }
    notifyListeners();
  }

  String? sectionOf(String? page) =>
      nodes.where((n) => n.id == page).firstOrNull?.parentId;

  // Append-ordered position key. Time-based (siblings sort by creation), padded
  // to a fixed width so lexicographic == numeric order. NOT the CRDT
  // fractional-index of Data Model Spec §1 — that lands with the Loro engine;
  // until then reorder is swap-based ([moveNode]) and insert-after-target uses a
  // suffix ([makeSubpageOf]), neither of which needs true between-key insertion.
  // (The old `% 1e8` truncation wrapped every ~28h, letting new nodes sort
  // before old ones — fixed by keeping the full millisecond value.)
  String _nextPosition() => 'a${nowMs().toString().padLeft(15, '0')}';

  // ── Undo / redo (page-scoped snapshots) ────────────────────────────────

  String _snapshot() => jsonEncode({
        'page': pageProps.toJson(),
        'blocks': [for (final b in blocks) b.toJson()],
      });

  void _restore(String snap) {
    final j = jsonDecode(snap) as Map<String, dynamic>;
    pageProps =
        PageProps.fromJson((j['page'] as Map?)?.cast<String, dynamic>());
    blocks = [
      for (final b in (j['blocks'] as List))
        Block.fromJson((b as Map).cast<String, dynamic>())
    ];
    selectedIds.clear();
    selectedBlockId = null;
    editingBlockId = null;
    docRevision++;
    markDirty();
    notifyListeners();
  }

  void pushUndo() {
    _undo.add(_snapshot());
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_snapshot());
    _restore(_undo.removeLast());
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_snapshot());
    _restore(_redo.removeLast());
  }

  // ── Selection & block ops ──────────────────────────────────────────────

  // Snap step comes from the page's own grid (Data Model Spec §3), so a page's
  // stored gridSize actually drives placement instead of being dead state.
  double get gridSize => pageProps.gridSize;
  double snap(double v) => snapToGrid ? (v / gridSize).round() * gridSize : v;

  Block addBlock(Block b, {bool recordUndo = true}) {
    if (recordUndo) pushUndo();
    b
      ..x = snap(b.x)
      ..y = snap(b.y)
      ..placement = snapToGrid ? 'snapped' : 'free'
      ..z = (blocks.isEmpty
          ? 0
          : blocks.map((e) => e.z).reduce((a, c) => a > c ? a : c) + 1);
    clampBlockToPage(b);
    blocks.add(b);
    markDirty();
    notifyListeners();
    return b;
  }

  void updateBlock(Block b) {
    b.updatedAt = nowMs();
    markDirty();
    notifyListeners();
  }

  void removeBlock(String id, {bool recordUndo = true}) {
    if (recordUndo) pushUndo();
    blocks.removeWhere((b) => b.id == id);
    selectedIds.remove(id);
    if (selectedBlockId == id) selectedBlockId = selectedIds.firstOrNull;
    if (editingBlockId == id) editingBlockId = null;
    markDirty();
    notifyListeners();
  }

  void removeSelected() {
    if (selectedIds.isEmpty) return;
    pushUndo();
    blocks.removeWhere((b) => selectedIds.contains(b.id));
    selectedIds.clear();
    selectedBlockId = null;
    editingBlockId = null;
    markDirty();
    notifyListeners();
  }

  /// Duplicate with FRESH ids (Data Model Spec §2 rule 3).
  void duplicateBlock(String id) {
    final src = blocks.where((b) => b.id == id).firstOrNull;
    if (src == null) return;
    pushUndo();
    final fresh = Block(
      id: newId(),
      type: src.type,
      x: src.x + 24,
      y: src.y + 24,
      w: src.w,
      h: src.h,
      placement: src.placement,
      content: jsonDecode(jsonEncode(src.content)) as Map<String, dynamic>,
    );
    if (fresh.type == BlockType.ink) {
      for (final sj in (fresh.content['strokes'] as List)) {
        (sj as Map)['id'] = newId();
      }
    }
    addBlock(fresh, recordUndo: false); // snaps + clamps fresh.x/y to final pos
    if (fresh.type == BlockType.ink) {
      // Translate strokes to the block's FINAL (snapped/clamped) position so the
      // duplicate's ink renders under its new rect, not on top of the original.
      final dx = fresh.x - src.x, dy = fresh.y - src.y;
      for (final sj in (fresh.content['strokes'] as List)) {
        final m = (sj as Map);
        m['x'] = [for (final v in (m['x'] as List)) (v as num) + dx];
        m['y'] = [for (final v in (m['y'] as List)) (v as num) + dy];
      }
      fresh.updatedAt = nowMs(); // refresh the canvas stroke cache key
    }
    select(fresh.id);
  }

  void select(String? id, {bool edit = false, bool additive = false}) {
    // The caret token is for the selection being made RIGHT NOW. Expiring it
    // here rather than trusting one widget type to consume it means a click
    // that never opens a text editor can't leave it lying around for the next
    // one — which showed up as a caret landing at a point on another block.
    if (!edit) pendingCaretGlobal = null;
    if (id == null) {
      selectedIds.clear();
      selectedBlockId = null;
      editingBlockId = null;
    } else if (additive) {
      if (!selectedIds.add(id)) selectedIds.remove(id);
      selectedBlockId = selectedIds.contains(id) ? id : selectedIds.firstOrNull;
      editingBlockId = null;
    } else {
      selectedIds
        ..clear()
        ..add(id);
      selectedBlockId = id;
      editingBlockId = edit ? id : null;
    }
    notifyListeners();
  }

  void selectMany(Iterable<String> ids) {
    selectedIds
      ..clear()
      ..addAll(ids);
    selectedBlockId = selectedIds.firstOrNull;
    editingBlockId = null;
    notifyListeners();
  }

  /// Move every selected block by a page-space delta (ink blocks translate
  /// their stroke coordinates — Ink Spec §3, coordinates are page-absolute).
  void moveSelectedBy(double dx, double dy) {
    for (final b in blocks.where((b) => selectedIds.contains(b.id))) {
      b.x += dx;
      b.y += dy;
      if (b.type == BlockType.ink) {
        for (final sj in (b.content['strokes'] as List)) {
          final m = (sj as Map);
          m['x'] = [for (final v in (m['x'] as List)) (v as num) + dx];
          m['y'] = [for (final v in (m['y'] as List)) (v as num) + dy];
        }
        // The canvas caches decoded strokes by `id#updatedAt`; bump it so the
        // painted ink follows the block instead of lagging until a reload.
        b.updatedAt = nowMs();
      }
    }
    markDirty();
    notifyListeners();
  }

  /// Snap + clamp all selected at drag end. Ongoing left-margin alignment:
  /// if a block lands near the invisible writing margin, tuck it to the
  /// margin so everything stays neat (matches the smart initial placement).
  void settleSelected() {
    for (final b in blocks.where((b) => selectedIds.contains(b.id))) {
      if (b.type != BlockType.ink) {
        if ((b.x - pageLeftMargin).abs() < 26) {
          b.x = pageLeftMargin;
        } else if (snapToGrid) {
          b.x = snap(b.x);
        }
        if (snapToGrid) b.y = snap(b.y);
        b.placement = snapToGrid ? 'snapped' : 'free';
      }
      clampBlockToPage(b);
    }
    markDirty();
    notifyListeners();
  }

  void setTool(Tool t) {
    tool = t;
    if (t != Tool.select) select(null);
    notifyListeners();
  }

  void toggleSnap() {
    snapToGrid = !snapToGrid;
    notifyListeners();
  }

  void setBackground(String bg) {
    pushUndo();
    pageProps.background = bg;
    markDirty();
    notifyListeners();
  }

  void refresh() => notifyListeners();

  // ── Find (TEXT-7, current page) ────────────────────────────────────────

  void toggleFind() {
    findOpen = !findOpen;
    if (!findOpen) {
      findQuery = '';
      findMatches = [];
    }
    notifyListeners();
  }

  void setFindQuery(String q) {
    findQuery = q;
    final needle = q.toLowerCase();
    findMatches = needle.isEmpty
        ? []
        : [
            for (final b in blocks)
              if (_blockText(b).toLowerCase().contains(needle)) b.id
          ];
    findIndex = 0;
    if (findMatches.isNotEmpty) _jumpToMatch();
    notifyListeners();
  }

  void findNext(int dir) {
    if (findMatches.isEmpty) return;
    findIndex = (findIndex + dir) % findMatches.length;
    if (findIndex < 0) findIndex += findMatches.length;
    _jumpToMatch();
    notifyListeners();
  }

  void _jumpToMatch() => jumpToBlock(findMatches[findIndex]);

  /// Replace text in the matched blocks (TEXT-7).
  ///
  /// Replaces in the *text-bearing* content field per block type, so replacing
  /// in a code block edits its source and not its language tag. Case-sensitive
  /// matching is deliberately not offered yet — find is case-insensitive, and a
  /// replace that matched differently from the find that found it would be a
  /// trap.
  ///
  /// Returns the number of occurrences replaced.
  int replaceAll(String find, String replacement, {bool onlyCurrent = false}) {
    if (find.isEmpty) return 0;
    final targets = onlyCurrent
        ? (findMatches.isEmpty
            ? const <String>[]
            : [findMatches[findIndex.clamp(0, findMatches.length - 1)]])
        : findMatches;
    if (targets.isEmpty) return 0;
    pushUndo();
    final needle = find.toLowerCase();
    var count = 0;
    for (final id in targets) {
      final b = blocks.where((x) => x.id == id).firstOrNull;
      if (b == null) continue;
      final key = switch (b.type) {
        BlockType.text => 'text',
        BlockType.code => 'source',
        _ => null,
      };
      if (key == null) continue;
      final src = b.content[key] as String? ?? '';
      final out = StringBuffer();
      var i = 0;
      while (i < src.length) {
        final at = src.toLowerCase().indexOf(needle, i);
        if (at < 0) {
          out.write(src.substring(i));
          break;
        }
        out
          ..write(src.substring(i, at))
          ..write(replacement);
        i = at + find.length;
        count++;
      }
      if (count > 0) b.content[key] = out.toString();
    }
    if (count > 0) {
      markDirty();
      docRevision++;
      // Re-run the search: the replaced text may no longer match, and leaving
      // stale matches would let a second Replace All hit blocks that no longer
      // contain the needle.
      setFindQuery(findQuery);
    }
    return count;
  }

  /// Select a block and centre the view on it. Shared by find and the page
  /// outline so both behave identically.
  void jumpToBlock(String id) {
    final b = blocks.where((b) => b.id == id).firstOrNull;
    if (b == null) return;
    selectedIds
      ..clear()
      ..add(id);
    selectedBlockId = id;
    editingBlockId = null;
    final h = b.h ?? renderSizes[id]?.height ?? 60;
    canvas.centerOn(Offset(b.x + b.w / 2, b.y + h / 2));
    notifyListeners();
  }

  String _blockText(Block b) => switch (b.type) {
        BlockType.text => b.content['text'] as String? ?? '',
        BlockType.code => b.content['source'] as String? ?? '',
        BlockType.math =>
          '${b.content['latex'] ?? ''} ${b.content['linearSource'] ?? ''}',
        _ => '',
      };

  // ── Persistence ────────────────────────────────────────────────────────

  void markDirty() {
    _dirty = true;
    // Cheap counter, not a rebuild: it lets the open page's flashcards be
    // rederived once per edit, so tagging a line produces a card immediately
    // instead of only after you navigate away.
    study.noteContentChanged();
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 700), flushSave);
    notifyListeners();
  }

  /// The last save failure, or null when the last save succeeded. Surfaced in
  /// the status bar — a silent failed save used to read as "Saved".
  Object? saveError;

  Future<void> flushSave() async {
    _saveDebounce?.cancel();
    if (!_dirty || pageId == null || notebookId == null) return;
    // Keep `_dirty` TRUE until the write actually lands: clearing it first meant
    // a throwing save (disk full, DB locked) left the page marked clean and the
    // status bar claiming "Saved" while the change was never persisted.
    final id = pageId!, nb = notebookId!;
    try {
      // The engine owns persistence: version snapshot (throttled, SYNC-8) + the
      // mirror write, plus content-hash change-detection on the Rust engine (a
      // save whose hash is unchanged is skipped). See RustEngine/MirrorEngine.
      await engine.savePage(nb, id, blocks, pageProps);
      _dirty = false;
      saveError = null;
      // Record AFTER the container write succeeds, so the log never claims a
      // change the notebook doesn't have. The reverse order would be worse than
      // useless: rebuild-from-log would then differ from the container on every
      // failed save, and the divergence would look like a recording bug rather
      // than the disk error it is.
      //
      // The recorder diffs against its replayed state, so an autosave that
      // changed one block appends one op, not the whole page.
      _recorderFor(nb)?.page(id, blocks, pageProps);
      // Throttled inside; a mirror is a safety net, not a live replica.
      unawaited(runMirrors(nb));
    } catch (e) {
      // Stay dirty so the next edit (or exit flush) retries, and tell the user.
      saveError = e;
      notifyListeners();
      return;
    }
    // Keep session state fresh so closing the app never loses your place.
    _rememberView();
    _persistSession();
    notifyListeners();
  }

  /// Persist everything before the process goes away (window close, logout).
  /// Awaited by the app's [AppLifecycleListener]; without it, up to one debounce
  /// interval of edits was silently lost on every close.
  Future<void> shutdown() async {
    _saveDebounce?.cancel();
    try {
      await flushSave();
    } catch (_) {
      // Never block exit on a save failure — flushSave already recorded it.
    }
    _rememberView();
    _persistSession();
    await _repo.flushWorkspace(); // settle the debounced registry write
  }

  /// Drop a pending debounced save without writing it.
  ///
  /// Only for tests: a widget test runs in a fake-async zone where the save's
  /// disk I/O would never complete, and leaving the timer armed fails the
  /// test's own "no pending timers" invariant.
  @visibleForTesting
  void cancelPendingSave() => _saveDebounce?.cancel();

  /// Set by [dispose]. Background work started before disposal checks this
  /// before touching anything, because a replay or a backfill can land after
  /// the repository it wants is closed — in the app that is a harmless log
  /// line at shutdown, in tests it is late I/O charged to whichever test runs
  /// next, which is the shape of an intermittent CI failure already fixed once.
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _stopWatching();
    _syncStatusPoll?.cancel();
    _saveDebounce?.cancel();
    // The planner owns a Timer. A `late final` touched here is constructed
    // just to be torn down, which costs nothing; a live timer left behind
    // keeps the isolate awake, which does.
    planner.dispose();
    canvas.dispose();
    _repo.dispose();
    super.dispose();
  }
}

/// Where one notebook's bytes actually are.
///
/// Exists because "is this syncing?" was being answered by inference and the
/// answer was wrong: a notebook can sit in the workspace with its logs beside
/// it while copies of it sit in a cloud folder, and the app happily reported
/// the copies' existence as sync. The only honest answer names the two paths
/// and says which of them a cloud client can see.
class NotebookStorage {
  const NotebookStorage({
    required this.containerPath,
    required this.containerBytes,
    required this.logPath,
    required this.logBytes,
    required this.logExists,
    required this.containerCloud,
    required this.logCloud,
  });

  final String containerPath;
  final int containerBytes;
  final String logPath;
  final int logBytes;
  final bool logExists;

  /// The detected cloud folder each half lives in, if any.
  final CloudFolder? containerCloud;
  final CloudFolder? logCloud;

  /// **The logs are what sync.** The container is a local cache by design
  /// (ADR-0006 §3), so a container in Drive without its logs there is not
  /// sync — it is a stray copy being re-uploaded on every save.
  bool get syncs => logCloud != null;

  int get totalBytes => containerBytes + logBytes;
}

/// A `.onote` or `.onotebook` on disk that no registry entry claims.
class OrphanFile {
  const OrphanFile({
    required this.path,
    required this.bytes,
    required this.isLog,
    required this.safeToDelete,
  });

  final String path;
  final int bytes;
  final bool isLog;

  /// True only inside this workspace, where nothing else can be using it.
  ///
  /// An orphan in a SHARED folder is never safe: it may be another device's
  /// notebook that this machine has simply never joined, and deleting it
  /// would destroy data this device never owned. Those are listed for the
  /// user to judge, never deleted for them.
  final bool safeToDelete;
}

/// What the UI needs to know about a notebook's sync state.
class SyncStatus {
  const SyncStatus({
    required this.folder,
    required this.devices,
    required this.mirrors,
  });

  /// The detected cloud folder the notebook lives in, or null when it is only
  /// on this machine.
  final CloudFolder? folder;

  /// How many devices have written a log here (this one included).
  final int devices;

  /// Configured one-way mirror/backup destinations.
  final int mirrors;

  bool get isSynced => folder != null;
  bool get hasOtherDevices => devices > 1;

  /// The chip label.
  ///
  /// The folder's own **name**, not its kind: for a detected provider the two
  /// are the same, but "OneDrive (work)" and a folder the user chose
  /// themselves both lose their identity if this reports the kind — the second
  /// would read "Folder", which tells the user nothing about where their notes
  /// went.
  String get label {
    if (!isSynced) return mirrors > 0 ? 'Backed up' : 'Sync…';
    if (hasOtherDevices) return '$devices devices';
    return folder!.name;
  }

  IconData get icon {
    if (!isSynced) {
      return mirrors > 0 ? Icons.backup_outlined : Icons.cloud_off_outlined;
    }
    if (hasOtherDevices) return Icons.devices;
    return Icons.cloud_done_outlined;
  }
}
