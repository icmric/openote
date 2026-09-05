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
import '../onenote/graph_auth.dart';
import '../onenote/graph_client.dart';
import '../onenote/graph_import.dart';
import '../state/app_state.dart';
import 'import_sink.dart';
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

  /// Whether Stop has been pressed and the job has not finished stopping.
  ///
  /// Exposed so the card can stop offering a button that has already been
  /// pressed, and offer a way out instead.
  bool get isStopping => _cancelRequested && !isFinished;

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
  /// core is not linked — same contract as the modal path it replaces. The
  /// exception is a test supplying an already-parsed package, which needs no
  /// parser; see the check itself.
  static ImportJob? start(AppState app, String fileName, String sourcePath,
      {@visibleForTesting ImportWriterOverrides? debugOverrides}) {
    // "Already running" is checked FIRST: it is the cheaper question, and it
    // is the one whose answer must not depend on whether this build has the
    // native core linked. Refusing a second import is a scheduling fact; the
    // core being absent is an environment fact, and conflating their order
    // made the refusal untestable without a core.
    if (current != null && !current!.isFinished) return null;
    // The core is needed to PARSE, so ask for it only when there is something
    // to parse: not when the caller handed us no path (a caller fact — "you
    // gave me nothing" must not masquerade as "this build has no importer"),
    // and not when a test supplied an already-parsed package. Demanding it
    // regardless made four tests depend on a native library they never call,
    // and macOS is the one platform where `flutter build` does not build the
    // Rust core — so they died there and passed everywhere else. A stub that
    // still requires the thing it stubs is not a stub.
    final willParse =
        sourcePath.isNotEmpty && debugOverrides?.preparsedJson == null;
    if (willParse && OnoteCore.instance == null) throw OneNoteUnavailable();
    final job = ImportJob._(app, fileName);
    current = job;
    app.refresh(); // the shell mounts the card by watching AppState
    job._run(sourcePath, debugOverrides);
    return job;
  }

  /// Begin importing a notebook straight out of OneNote over the internet.
  ///
  /// Shares every field, the progress card, and cancel with the `.onepkg`
  /// path, because to a student they are the same thing happening. What
  /// differs is underneath: there is no file and no parse, so no writer
  /// isolate — the work is network latency, and the writing happens here in
  /// small batches so the notebook fills in **as it arrives** rather than
  /// appearing all at once at the end.
  static ImportJob? startFromCloud(
    AppState app,
    String notebookName,
    Future<GraphImportResult> Function(
            ImportSink sink,
            void Function(GraphImportProgress) onProgress,
            bool Function() shouldCancel)
        run,
  ) {
    if (current != null && !current!.isFinished) return null;
    final job = ImportJob._(app, notebookName);
    current = job;
    app.refresh();
    job._runCloud(run);
    return job;
  }

  Future<void> _runCloud(
      Future<GraphImportResult> Function(
              ImportSink sink,
              void Function(GraphImportProgress) onProgress,
              bool Function() shouldCancel)
          run) async {
    var nb = '';
    try {
      resetImportReport();
      state = ImportJobState.writing;
      message = 'Signing in to OneNote…';
      notifyListeners();

      final ref = await app.importCreateNotebook(
          importTitleFromName(fileName));
      notebookId = nb = ref.id;

      // Opened straight away, deliberately. The whole point of writing section
      // by section is that somebody can WATCH it arrive, and they cannot watch
      // a notebook they are not looking at.
      await app.selectNotebook(nb);

      final result = await run(
        AppStateImportSink(app, nb),
        (p) {
          pagesDone = p.pagesDone;
          // **Kept here, not only on the way out.** `importedPages` used to be
          // assigned after the import RETURNED, so an import that failed
          // partway looked like it had brought nothing — and the teardown
          // below then deleted the notebook, with every page the student had
          // just watched arrive. A failure must cost the rest, never the part
          // that already worked.
          if (p.pagesDone > importedPages) importedPages = p.pagesDone;
          // The total IS known now — every section's page list is fetched up
          // front — so the card can show a bar rather than a rising count.
          pagesTotal = p.pagesTotal;
          final waiting = p.waitingFor;
          if (p.preparing && waiting == null) {
            // Named plainly, because "enumerating sections" is not a sentence
            // anybody outside this file would write. What the student wants to
            // know is that something is happening and roughly how big this is
            // going to be.
            message = p.sectionsTotal == 0
                ? 'Looking through your notebook…'
                : p.pagesTotal == 0
                    ? 'Found ${p.sectionsTotal} section'
                        '${p.sectionsTotal == 1 ? '' : 's'} — seeing what is '
                        'in them…'
                    : '${p.pagesTotal} page'
                        '${p.pagesTotal == 1 ? '' : 's'} to bring over. '
                        'Starting now…';
          } else if (waiting != null) {
            // **Say that it is waiting.** OneNote throttles by request count,
            // and a large notebook WILL be asked to slow down: measured at six
            // and a half minutes of reading before the first refusal, with a
            // cooldown still in force minutes later. A card that sits silent
            // for two minutes cannot be told from one that has hung, and the
            // student's next move would be to kill the app halfway through
            // their own notebook.
            final secs = waiting.inSeconds;
            message = 'Microsoft has asked Openote to slow down — carrying on '
                'in ${secs < 1 ? 'a moment' : '${secs}s'}. '
                'Nothing already brought in is lost.';
          } else {
            message = 'Bringing in "${p.sectionName}" — ${p.pagesDone}'
                '${p.pagesTotal > 0 ? ' of ${p.pagesTotal}' : ''} '
                'page${p.pagesDone == 1 ? '' : 's'}…';
          }
          notifyListeners();
          app.reloadNodes();
          app.refresh();
        },
        () => _cancelRequested,
      );

      app.reloadNodes();
      // **Now, and only now.** A link on the first page routinely points at
      // the last, so the mapping is complete only once everything has landed.
      // Rewriting as we went would have fixed the backward links and missed
      // every forward one.
      final relinked = app.relinkImportedPages(nb, result.pageIdsByOneNoteId);
      if (relinked > 0) app.reloadNodes();
      app.refresh();
      importedPages = result.pages;
      firstPageId = result.firstPageId;

      if (result.cancelled) {
        // NOT torn down, unlike the file path. A cancelled cloud import has
        // already put real pages on screen and the student has been watching
        // them arrive; deleting them because they pressed stop would be the
        // opposite of what stop means.
        return _finish(ImportJobState.done,
            message: 'Stopped — kept the ${result.pages} '
                'page${result.pages == 1 ? '' : 's'} already brought in.');
      }
      if (result.pages == 0) {
        return _finish(ImportJobState.failed,
            message: 'That notebook had no pages in it.');
      }
      final lost = result.loss;
      final note = 'Imported ${result.pages} page'
          '${result.pages == 1 ? '' : 's'}';
      // Ink and attachments DO come across now, so the old blanket apology
      // would be a lie. Only real losses are named, and named specifically.
      final gone = <String>[
        if (lost.inkPages > 0)
          'handwriting on ${lost.inkPages} page'
              '${lost.inkPages == 1 ? '' : 's'}',
        if (lost.images > 0) '${lost.images} picture'
            '${lost.images == 1 ? '' : 's'}',
        if (lost.attachments > 0) '${lost.attachments} attachment'
            '${lost.attachments == 1 ? '' : 's'}',
      ];
      _finish(ImportJobState.done,
          message: gone.isEmpty
              ? '$note. Subpages arrive as ordinary pages — OneNote does not '
                  'send how they were nested.'
              : '$note, but could not bring ${gone.join(', ')}.');
    } on GraphAuthException catch (e) {
      error = e.message;
      if (nb.isNotEmpty) await _teardown();
      _finish(ImportJobState.failed, message: e.message);
    } on GraphException catch (e) {
      error = e.message;
      // Kept rather than torn down when pages already landed: see above.
      if (nb.isNotEmpty && importedPages == 0) {
        await _teardown();
      } else {
        app.reloadNodes();
        app.refresh();
      }
      // Not `failed` when something arrived. The student has a notebook with
      // real pages in it, and calling that a failure invites them to delete it
      // and start again — which is the one thing that would actually lose
      // work.
      if (importedPages > 0) {
        return _finish(ImportJobState.done,
            message: '${e.message} The $importedPages page'
                '${importedPages == 1 ? '' : 's'} already brought over '
                '${importedPages == 1 ? 'is' : 'are'} here.');
      }
      _finish(ImportJobState.failed, message: e.message);
    } catch (e) {
      error = '$e';
      // Same rule as the branch above, and for the same reason: an unexpected
      // fault is no more entitled to delete pages the student is looking at
      // than an expected one is.
      if (nb.isNotEmpty && importedPages == 0) {
        await _teardown();
      } else {
        app.reloadNodes();
        app.refresh();
      }
      if (importedPages > 0) {
        return _finish(ImportJobState.done,
            message: 'Something went wrong partway through, but the '
                '$importedPages page${importedPages == 1 ? '' : 's'} already '
                'brought over ${importedPages == 1 ? 'is' : 'are'} here. Try '
                'again for the rest.');
      }
      _finish(ImportJobState.failed,
          message: 'That notebook could not be brought over.');
    }
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
          deviceId: app.localDeviceId(),
          // **Unconditional** (v0.17 plan, Step 5). This one line is where the
          // owner's measured 378-of-488 hole came from: an import into the
          // local workspace wrote 26.3 MB of PNGs into the container and none
          // of them into `blobs/`, so the log named 488 blobs and could supply
          // 110. Doing it here is also strictly cheaper than the backfill that
          // would otherwise have to re-read all 26.3 MB back out at the next
          // open — the bytes are already in hand.
          materialiseBlobs: true,
          batchPages: _batchPages,
          syncLogEnabled: AppState.syncLogEnabled,
          sqliteLibrary: o?.sqliteLibrary,
          preparsedJson: o?.preparsedJson,
        ),
        frameYield: o?.frameYield ?? appFrameYield,
        onParsed: (pages) {
          state = ImportJobState.writing;
          pagesTotal = pages;
          message = 'Importing $pages pages…';
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

      if (result == null) {
        app.abandonExclusiveImport(nb);
        await _teardown();
        return _finish(ImportJobState.cancelled);
      }

      // BEFORE handing the notebook back. `endExclusiveImport` starts a
      // background replay of the log the writer just wrote, and the replay's
      // identity check compares the log's highest seq against this setting. A
      // log running ahead of it reads as "another installation has been writing
      // as us" and forks the device id — on every imported notebook. The
      // ordering held by luck before (nothing awaited in between); now it holds
      // because it is written down.
      app.rememberImportedSeq(nb, result.lastSeq);
      app.endExclusiveImport(nb);
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
      if (nb.isNotEmpty) app.abandonExclusiveImport(nb);
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
      if (nb.isNotEmpty) app.abandonExclusiveImport(nb);
      error = '$e';
      await _teardown();
      _finish(ImportJobState.failed, message: "The import failed: $e");
    }
  }

  /// Give the frame back during the layout pass, then go **idle** — see
  /// [startImportWriter] for the pass itself.
  ///
  /// The idle gap is the load-bearing half, and it was missing. `endOfFrame`
  /// alone resumes the layout straight off the frame pipeline, so the loop is
  /// chunk → frame → chunk with the queue never empty — and on Windows, where
  /// the UI isolate lives on the Win32 message loop, **posted messages are
  /// dispatched ahead of hardware input messages**. A queue that is never
  /// empty of posted work starves mouse and keyboard indefinitely while frames
  /// keep flowing. Which is the report, verbatim, for the fourth time: *"the
  /// popup still updates (although slowly), however any inputs I give aren't
  /// executed until after the import is complete."*
  ///
  /// A zero-delay timer would not fix it — a zero timer is itself posted work,
  /// due immediately, so the queue still never goes idle. It takes a real
  /// deadline: the message loop then *waits*, and Win32 delivers the queued
  /// input during the wait. Two milliseconds per chunk against a ~16 ms frame
  /// is noise for the import and the whole difference for the user.
  ///
  /// (This is also why every headless test passed while the app locked: the
  /// test VM has no Win32 queue, and the tests' injected yield was a timer —
  /// which drains their event queue anyway.)
  @visibleForTesting
  static Future<void> appFrameYield() async {
    await SchedulerBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }

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
