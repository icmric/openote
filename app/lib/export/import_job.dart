/// A OneNote import that the app stays alive underneath (v0.9 §1).
///
/// **What was wrong, in order of harm.** Importing a real notebook locked the
/// whole application for the duration — a minute or more on good hardware —
/// and, from the onboarding path, did so with **no feedback at all**: the
/// welcome dialog popped itself and then passed its own, now-defunct context
/// as the progress dialog's parent, so the `mounted` check inside quietly
/// dropped the dialog on the floor. A first-run user picked their `.onepkg`
/// and watched a frozen app do apparently nothing for a minute. That is the
/// single worst moment the product had.
///
/// **Why it locked.** The parse itself was already off the UI thread — but
/// nothing else was. `jsonDecode` of the parser's result (a string that can
/// run to hundreds of MB), a `base64Decode` per image, and every database
/// write ran on the UI isolate, with exactly one yield per *section*. A
/// hundred-page section is one uninterrupted stall.
///
/// **The shape now.** Ownership of each phase goes to where it can run
/// without being felt:
///
///   1. *Parse* — one `compute` call that does the Rust parse, the JSON
///      decode AND the image base64, returning the finished structure.
///      `compute` hands the result over via `Isolate.exit`, which is O(1) —
///      no copy lands on the UI thread.
///   2. *Write* — on the UI isolate, because SQLite handles and `AppState`
///      live there, but in **batches of a few pages inside one transaction,
///      yielding to the event loop between batches** so input and paint run
///      between every batch. The remaining per-batch work is milliseconds.
///
/// A modal dialog would be the wrong surface for something the user no longer
/// has to wait for, so the job is a [ChangeNotifier] that a floating card
/// observes: progress while it runs, a result and an **Open notebook** button
/// when it lands, cancel at any point. Onboarding starts the job and carries
/// on — which is the requested flow: *"get them to import at the start, then
/// do the onboarding while that's working away in the background."*
///
/// **One at a time.** [ImportJob.start] refuses to run two concurrently — two
/// imports interleaving batches on one UI thread would halve each other's
/// responsiveness and confuse every progress surface. Nobody imports two
/// five-year notebooks at once on purpose.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:path/path.dart' as p;

import '../core/onote_ffi.dart';
import '../state/app_state.dart';
import 'import_writer.dart';
import 'onenote_import.dart';

enum ImportJobState { parsing, writing, done, failed, cancelled }

class ImportJob extends ChangeNotifier {
  ImportJob._(this.app, this.fileName);

  final AppState app;

  /// The `.onepkg`'s basename, for the progress card's title.
  final String fileName;

  ImportJobState state = ImportJobState.parsing;

  /// One human sentence about where the job is. The card renders it verbatim.
  String message = 'Reading the notebook…';

  /// Pages written so far / total to write. 0/0 during the parse phase.
  int pagesDone = 0;
  int pagesTotal = 0;

  /// Set once the target notebook exists, so Open can find it — and so cancel
  /// knows what to tear down.
  String? notebookId;

  /// The first page of the imported notebook, for Open to land on.
  String? firstPageId;

  /// Counts for the completion card, mirroring the old snackbar's honesty
  /// about partial imports.
  int importedPages = 0;
  List<String> skippedSections = const [];
  int droppedStrokes = 0;
  String? error;

  bool _cancelRequested = false;

  /// The running job, if any. Global because the *surfaces* are global: the
  /// progress card floats over whatever the user is doing, which may be three
  /// navigations away from wherever the import was started.
  static ImportJob? current;

  /// Begin importing the `.onepkg` at [sourcePath] as a new notebook. Returns
  /// the job, or null if one is already running.
  ///
  /// A **path**, not bytes. The writer isolate reads the file itself, so a
  /// five-year notebook's hundreds of megabytes never pass through the UI
  /// isolate's heap — and the read, which is itself seconds of I/O, is not done
  /// on the thread the user is typing on.
  ///
  /// Throws [OneNoteUnavailable] before doing anything visible when the Rust
  /// core is not linked — same contract as the modal path it replaces.
  static ImportJob? start(AppState app, String fileName, String sourcePath,
      {@visibleForTesting ImportWriterOverrides? debugOverrides}) {
    // "Already running" is checked FIRST: it is the cheaper question, and it
    // is the one whose answer must not depend on whether this build has the
    // native core linked. Refusing a second import is a scheduling fact; the
    // core being absent is an environment fact, and conflating their order
    // made the refusal untestable without a core.
    if (current != null && !current!.isFinished) return null;
    if (OnoteCore.instance == null) throw OneNoteUnavailable();
    final job = ImportJob._(app, fileName);
    current = job;
    app.refresh(); // the shell mounts the card by watching AppState
    job._run(sourcePath, debugOverrides);
    return job;
  }

  bool get isFinished =>
      state == ImportJobState.done ||
      state == ImportJobState.failed ||
      state == ImportJobState.cancelled;

  /// Ask the job to stop. Honoured at the next batch boundary — a batch is a
  /// few pages, so this lands within tens of milliseconds. Everything already
  /// written is torn down: a half-imported notebook that lingered would read
  /// as "the import worked but ate half my notes".
  void cancel() {
    if (isFinished) return;
    _cancelRequested = true;
    message = 'Stopping…';
    // The writer finishes the batch it is in — a few pages — then shuts down
    // cleanly. Killing the isolate outright would leave its SQLite handle open,
    // and on Windows an open handle is exactly why the teardown's delete would
    // then fail, stranding a half-imported notebook nothing claims.
    _writer?.cancel();
    notifyListeners();
  }

  /// Drop the finished card. Also forgets the job so a new import can start.
  void dismiss() {
    if (ImportJob.current == this) ImportJob.current = null;
    app.refresh();
  }

  /// Open the imported notebook. The one navigation this job ever performs,
  /// and only because the user pressed the button asking for it — a
  /// background import that yanked the app to its result the moment it
  /// finished would interrupt whatever the user moved on to doing.
  Future<void> open() async {
    final nb = notebookId;
    if (nb == null || state != ImportJobState.done) return;
    await app.selectNotebook(nb);
    if (firstPageId != null) await app.selectPage(firstPageId!);
    dismiss();
  }

  /// A job that never runs, for screenshot/widget tests of the card. The real
  /// entry point needs the native core and a file; the card needs neither.
  @visibleForTesting
  static ImportJob debugCreate(AppState app, String fileName) =>
      ImportJob._(app, fileName);

  /// Test-only: fire the notifier after mutating fields directly.
  @visibleForTesting
  void debugNotify() => notifyListeners();

  /// Pages per transaction. Small enough that the stall between yields stays
  /// well under a frame budget even for image-heavy pages; big enough that
  /// transaction overhead stays amortised across a large notebook.
  static const _batchPages = 4;

  /// The running writer, so [cancel] has something to ask.
  ImportWriterHandle? _writer;

  Future<void> _run(String sourcePath, ImportWriterOverrides? o) async {
    var nb = '';
    try {
      if (sourcePath.isEmpty) {
        return _finish(ImportJobState.failed,
            message: "Couldn't read that file — it has no location on disk.");
      }
      // The arrival counters are process globals accumulated during the page
      // writes; without this, a second import would report the first one's
      // images and strokes on top of its own. The writer isolate has its own
      // copy of them (globals are per isolate) and carries its totals home in
      // the result — this reset is for the counters the UI reads.
      resetImportReport();

      // The notebook is created HERE, before the isolate starts, because
      // creating it is a workspace-registry change and the registry is
      // Repository's alone. From this point until the writer finishes, its
      // files belong to the isolate.
      // `basenameWithoutExtension`, like the single-section path above it —
      // without it, importing "Discrete Maths.onepkg" produced a notebook
      // called, verbatim, "Discrete Maths.onepkg".
      final ref = await app.importCreateNotebook(
          importTitleFromName(p.basenameWithoutExtension(fileName)));
      notebookId = nb = ref.id;
      app.beginExclusiveImport(nb);

      final handle = startImportWriter(
        ImportWriterConfig(
          sourcePath: sourcePath,
          notebookPath: ref.file,
          notebookId: ref.id,
          title: ref.title,
          logDir: ref.logDir,
          deviceId: app.deviceIdForImport(),
          materialiseBlobs: app.notebookIsShared(nb),
          batchPages: _batchPages,
          syncLogEnabled: AppState.syncLogEnabled,
          sqliteLibrary: o?.sqliteLibrary,
          preparsedJson: o?.preparsedJson,
        ),
        frameYield: o?.frameYield ?? _endOfFrame,
        onParsed: (pages) {
          state = ImportJobState.writing;
          pagesTotal = pages;
          message = 'Laying out $pages pages…';
          notifyListeners();
        },
        onProgress: (sectionName, done, total) {
          pagesDone = done;
          message = 'Importing "$sectionName"…';
          notifyListeners();
        },
      );
      _writer = handle;
      if (_cancelRequested) handle.cancel();

      final result = await handle.result;
      app.endExclusiveImport(nb);

      if (result == null) {
        await _teardown();
        return _finish(ImportJobState.cancelled);
      }

      app.rememberImportedSeq(nb, result.lastSeq);
      app.reloadNodes();
      app.refresh();

      importedPages = result.pages;
      firstPageId = result.firstPageId;
      droppedStrokes = result.droppedStrokes;
      skippedSections = result.skippedSections;
      final note = importArrivalNote(
          result.pages, result.images, result.strokes, result.tags);
      _finish(ImportJobState.done,
          message: skippedSections.isEmpty
              ? 'Imported $note.'
              : 'Imported $note — ${skippedSections.length} '
                  'section${skippedSections.length == 1 ? '' : 's'} could not '
                  'be read.');
    } on ImportWriterException catch (e) {
      if (nb.isNotEmpty) app.endExclusiveImport(nb);
      skippedSections = e.skippedSections;
      error = e.message;
      await _teardown();
      _finish(ImportJobState.failed,
          message: e.message == null
              ? "Couldn't read any sections from that file."
              : "Couldn't import: ${e.message}");
    } catch (e) {
      // A crashed isolate, an OOM, a native fault. Never silent: the user
      // handed us five years of notes and must not have to guess what
      // happened to them.
      if (nb.isNotEmpty) app.endExclusiveImport(nb);
      error = '$e';
      await _teardown();
      _finish(ImportJobState.failed, message: "The import failed: $e");
    }
  }

  /// Give the frame back during the layout pass — see [startImportWriter].
  static Future<void> _endOfFrame() => SchedulerBinding.instance.endOfFrame;

  /// Remove the partly-built notebook after a cancel or a crash. Everything
  /// or nothing: the notes still exist in OneNote, so nothing is lost by
  /// discarding a half.
  ///
  /// Deliberately NOT the recycle bin. This used to soft-delete and then purge,
  /// which failed silently whenever the import target was the only notebook in
  /// the workspace — `deleteNotebook` refuses the last one — so cancelling an
  /// import could leave the half-built notebook sitting in the list.
  Future<void> _teardown() async {
    final nb = notebookId;
    notebookId = null;
    if (nb == null) return;
    try {
      await app.discardImportedNotebook(nb);
    } catch (_) {/* a leftover notebook beats a crash during cleanup */}
  }

  void _finish(ImportJobState s, {String? message}) {
    state = s;
    if (message != null) this.message = message;
    if (s == ImportJobState.cancelled) this.message = 'Import cancelled.';
    notifyListeners();
    // The card is watching this job, not AppState — but whether a card should
    // exist at all is AppState-level (the shell checks ImportJob.current).
    app.refresh();
  }
}
