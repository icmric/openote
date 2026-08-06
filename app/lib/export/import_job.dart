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

import '../core/onote_ffi.dart';
import '../model/models.dart';
import '../state/app_state.dart';
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

  /// Begin importing [bytes] (a `.onepkg`) as a new notebook. Returns the job,
  /// or null if one is already running.
  ///
  /// Throws [OneNoteUnavailable] before doing anything visible when the Rust
  /// core is not linked — same contract as the modal path it replaces.
  static ImportJob? start(AppState app, String fileName, Uint8List bytes) {
    if (OnoteCore.instance == null) throw OneNoteUnavailable();
    if (current != null && !current!.isFinished) return null;
    final job = ImportJob._(app, fileName);
    current = job;
    app.refresh(); // the shell mounts the card by watching AppState
    job._run(bytes);
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

  Future<void> _run(Uint8List bytes) async {
    try {
      // The arrival counters are process globals accumulated during the page
      // writes; without this, a second import would report the first one's
      // images and strokes on top of its own.
      resetImportReport();
      final result = await compute(parseOnepkgStructured, bytes);
      if (_cancelRequested) return _finish(ImportJobState.cancelled);
      if (result['ok'] != true) {
        error = result['error'] as String?;
        return _finish(ImportJobState.failed,
            message: error == null
                ? "Couldn't read any sections from that file."
                : "Couldn't import: $error");
      }
      skippedSections =
          ((result['failed'] as List?) ?? const []).cast<String>().toList();
      final sections = (result['sections'] as List?) ?? const [];
      if (sections.isEmpty) {
        return _finish(ImportJobState.failed,
            message: "Couldn't read any sections from that file.");
      }

      state = ImportJobState.writing;
      pagesTotal = 0;
      for (final s in sections) {
        pagesTotal +=
            ((((s as Map)['section'] as Map?)?['pages'] as List?) ?? const [])
                .length;
      }

      final nbTitle = importTitleFromName(fileName);
      final ref = await app.importCreateNotebook(nbTitle);
      notebookId = ref.id;

      final counts = await writePackageInBatches(
        app,
        ref.id,
        sections,
        batchPages: _batchPages,
        shouldCancel: () => _cancelRequested,
        onProgress: (sectionName, done, total) {
          pagesDone = done;
          message = 'Importing "$sectionName"…';
          notifyListeners();
        },
      );

      if (_cancelRequested) {
        await _teardown();
        return _finish(ImportJobState.cancelled);
      }

      importedPages = counts.pages;
      firstPageId = counts.firstPageId;
      droppedStrokes = lastDroppedStrokes;
      _finish(ImportJobState.done,
          message: skippedSections.isEmpty
              ? 'Imported ${importArrivalNote(counts.pages, lastImportedImages, lastImportedStrokes, lastImportedTags)}.'
              : 'Imported ${importArrivalNote(counts.pages, lastImportedImages, lastImportedStrokes, lastImportedTags)} '
                  '— ${skippedSections.length} '
                  'section${skippedSections.length == 1 ? '' : 's'} could not '
                  'be read.');
    } catch (e) {
      // A crashed isolate, an OOM, a native fault. Never silent: the user
      // handed us five years of notes and must not have to guess what
      // happened to them.
      error = '$e';
      await _teardown();
      _finish(ImportJobState.failed, message: "The import failed: $e");
    }
  }

  /// Remove the partly-built notebook after a cancel or a crash. Everything
  /// or nothing: the notes still exist in OneNote, so nothing is lost by
  /// discarding a half.
  Future<void> _teardown() async {
    final nb = notebookId;
    notebookId = null;
    if (nb == null) return;
    try {
      await app.deleteNotebook(nb);
      await app.purgeNotebook(nb);
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

/// Write a parsed package into notebook [nbId] a few pages at a time,
/// yielding to the event loop between batches.
///
/// This is [buildNotebookFromPackage]'s responsive sibling and shares its
/// per-page translation via [importOneParsedPage]; the differences are the
/// batch boundaries and the cancel check. Kept as a top-level function so it
/// is drivable headlessly in tests, exactly as its predecessor is.
Future<({int pages, String? firstPageId})> writePackageInBatches(
  AppState app,
  String nbId,
  List<dynamic> sections, {
  int batchPages = 4,
  bool Function()? shouldCancel,
  void Function(String sectionName, int pagesDone, int pagesTotal)? onProgress,
}) async {
  final seeded = app.importNodes(nbId);
  final posBase = nowMs();
  var pos = 0;
  String next() => 'a${(posBase + pos++).toString().padLeft(15, '0')}';

  var total = 0;
  for (final s in sections) {
    total += ((((s as Map)['section'] as Map?)?['pages'] as List?) ?? const [])
        .length;
  }

  var written = 0;
  String? firstPageId;
  final groupIds = <String, String>{};
  for (final sRaw in sections) {
    if (shouldCancel?.call() ?? false) break;
    final s = (sRaw as Map).cast<String, dynamic>();
    final pages = ((s['section'] as Map?)?['pages'] as List?) ?? const [];
    if (pages.isEmpty) continue;
    final name = importTitleFromName(s['name'] as String? ?? 'Section');

    String? groupId;
    final group = (s['group'] as String?)?.trim();
    if (group != null && group.isNotEmpty) {
      groupId = groupIds.putIfAbsent(
          group,
          () => app
              .importNode(
                  nbId,
                  TreeNode(
                      kind: NodeKind.sectionGroup,
                      title: group.replaceAll('/', ' › '),
                      position: next()))
              .id);
    }
    final section = app.importNode(
        nbId,
        TreeNode(
          kind: NodeKind.section,
          parentId: groupId,
          title: name,
          position: next(),
        ));

    for (var start = 0; start < pages.length; start += batchPages) {
      if (shouldCancel?.call() ?? false) break;
      final end =
          (start + batchPages) > pages.length ? pages.length : start + batchPages;
      final first = app.importBatch(nbId, () {
        String? firstInBatch;
        for (var i = start; i < end; i++) {
          final id = importOneParsedPage(app, nbId, section.id,
              (pages[i] as Map).cast<String, dynamic>(), next);
          firstInBatch ??= id;
        }
        return firstInBatch;
      });
      firstPageId ??= first;
      written += end - start;
      onProgress?.call(name, written, total);
      // The whole point: let input, paint and everything else queued behind
      // this import actually run. `Duration.zero` yields to the event loop,
      // which is where frames live.
      await Future<void>.delayed(Duration.zero);
    }
  }

  if (written > 0 && !(shouldCancel?.call() ?? false)) {
    for (final n in seeded.where((n) => n.kind == NodeKind.section)) {
      app.importPurgeNode(nbId, n.id);
    }
  }
  return (pages: written, firstPageId: firstPageId);
}
