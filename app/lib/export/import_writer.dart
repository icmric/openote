/// The import writer isolate — the fix for "interactions aren't completed until
/// the import is finished" (v0.10 latency plan, Option C).
///
/// ## What was still wrong after v0.9
///
/// v0.9 moved the *parse* off the UI thread and batched the write phase, yielding
/// `Future.delayed(Duration.zero)` between batches. That buys **one event-loop
/// turn**, which is enough for a vsync callback and not enough for an
/// interaction. A click is not one event; it is a conversation — pointer-down,
/// pointer-up, gesture resolution, the handler, a state change, a rebuild, a
/// paint, and for anything real an async continuation that reads the database.
/// Every leg had to fit in a sliver between 57 ms batches, and each sliver was
/// followed immediately by the next one. So paint survived (the progress card
/// animated, which is why it *looked* fine) and input starved. Verbatim the
/// report: *"Visually it updates with the popup, however interactions with the
/// page aren't completed until the import is finished."*
///
/// ## The shape now
///
/// One isolate owns the whole import: it reads the `.onepkg`, runs the Rust
/// parse, opens its **own** SQLite connection on the brand-new `.onote`, and
/// writes pages, blobs and the op log directly. The UI thread does nothing but
/// receive progress messages.
///
/// The property that makes this safe is that the target is a **brand-new
/// notebook**: no other code holds its container, its log files, or any
/// in-memory state derived from them. `Repository.closeNotebook` hands over the
/// one handle that did exist. There is no shared mutable anything, so there is
/// nothing to lock.
///
/// ## The one thing that cannot leave the main isolate
///
/// [restackFlows] corrects the parser's naive line-pitch layout using real text
/// measurement, and `TextPainter` throws *"UI actions are only available on root
/// isolate"* anywhere else. Measured, it costs **1.2 ms per page** — small, but
/// unavoidably main-side.
///
/// So the writer asks — **per batch, and for nine fields per box**. Both halves
/// of that were learned the hard way. The first shape asked once, up front, for
/// the whole notebook, and it reproduced the original report almost exactly:
/// the progress card showed the page total (the `parsed` message) and the app
/// then froze, because receiving an isolate message is a deep copy the receiver
/// does in **one uninterruptible go** — no amount of frame pacing inside the
/// restack loop helps, since the block is over before the loop starts. It also
/// meant nothing was written until every page had been laid out, so a big
/// notebook sat on a total that did not move.
///
/// Now each batch of four pages asks for its own layout immediately before
/// writing, sending only [flowMeasurementInput] — the fields the restack
/// actually reads, not the tag lists and style runs the parser also attached.
/// Measured on a synthetic 3000-page notebook, the worst interaction stall
/// during the layout pass went from **48 ms to 4 ms**, and progress now moves
/// from the first batch.
///
/// The images still never cross, which remains why the parse lives here rather
/// than in a `compute` on the main side.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

import '../core/onote_ffi.dart';
import '../ink/ink_codec.dart';
import '../ink/ink_storage.dart';
import '../model/models.dart';
import '../store/database.dart';
import '../store/notebook_writer.dart';
import '../sync/sync_recorder.dart';
import 'import_sink.dart';
import 'onenote_import.dart';

// ── Protocol ──────────────────────────────────────────────────────────────
//
// Plain maps with a `t` tag rather than sealed classes: everything here crosses
// an isolate boundary, where the payload has to be a sendable type anyway, and
// a class hierarchy would buy type safety at exactly the seam where the
// compiler cannot check it for us.

/// Everything the writer needs to do its job without a Repository, an AppState,
/// or a Flutter binding.
class ImportWriterConfig {
  const ImportWriterConfig({
    required this.sourcePath,
    required this.notebookPath,
    required this.notebookId,
    required this.title,
    required this.deviceId,
    this.logDir,
    this.materialiseBlobs = false,
    this.batchPages = 4,
    this.syncLogEnabled = true,
    this.sqliteLibrary,
    this.preparsedJson,
  });

  /// The `.onepkg` on disk. A **path**, not bytes: a five-year notebook is
  /// hundreds of MB and reading it is the isolate's job too.
  final String sourcePath;

  final String notebookPath;
  final String notebookId;
  final String title;

  /// Resolved on the main isolate, because device identity lives in workspace
  /// settings and those are Repository's. A brand-new notebook has no log, so
  /// there is nothing for `DeviceIdentity.resolve` to fork away from.
  final String deviceId;

  final String? logDir;

  /// Whether to write blob bytes into `blobs/` as well as the container
  /// (storage wave 1a). False for the overwhelmingly common case — a notebook
  /// imported into the local workspace.
  final bool materialiseBlobs;

  final int batchPages;

  /// Mirrors `AppState.syncLogEnabled`, so a test that doesn't want log files
  /// beside its fixture gets the same behaviour here.
  final bool syncLogEnabled;

  /// Explicit path to the SQLite native library.
  ///
  /// `open.overrideForAll` is a static, and statics are per-isolate — so a test
  /// harness that pointed `package:sqlite3` at the build output's library did so
  /// only for the isolate it ran on. In the app this is null and the default
  /// resolution (which works in any isolate) applies.
  final String? sqliteLibrary;

  /// An already-parsed package, used INSTEAD of reading and parsing
  /// [sourcePath]. Test-only.
  ///
  /// This is the only way to exercise this isolate. A `.onepkg` is a CAB of
  /// binary OneNote sections; there is no fixture in the repository (real ones
  /// are someone's actual notes), and synthesising one would mean writing a
  /// second implementation of the format in order to test the first. The Rust
  /// parse has its own end-to-end test against a real file. Everything *after*
  /// it — the protocol, the measurement round trip, the container and op-log
  /// writes, cancel, the seq handoff — is what this reaches, and that is all
  /// the code that is new.
  ///
  /// A JSON string rather than the decoded structure so it is trivially
  /// sendable and cannot smuggle a non-transferable object across the boundary.
  final String? preparsedJson;

  Map<String, Object?> toMap() => {
        'sourcePath': sourcePath,
        'notebookPath': notebookPath,
        'notebookId': notebookId,
        'title': title,
        'deviceId': deviceId,
        'logDir': logDir,
        'materialiseBlobs': materialiseBlobs,
        'batchPages': batchPages,
        'syncLogEnabled': syncLogEnabled,
        'sqliteLibrary': sqliteLibrary,
        'preparsedJson': preparsedJson,
      };

  static ImportWriterConfig fromMap(Map<Object?, Object?> m) =>
      ImportWriterConfig(
        sourcePath: m['sourcePath'] as String,
        notebookPath: m['notebookPath'] as String,
        notebookId: m['notebookId'] as String,
        title: m['title'] as String,
        deviceId: m['deviceId'] as String,
        logDir: m['logDir'] as String?,
        materialiseBlobs: m['materialiseBlobs'] as bool? ?? false,
        batchPages: (m['batchPages'] as num?)?.toInt() ?? 4,
        syncLogEnabled: m['syncLogEnabled'] as bool? ?? true,
        sqliteLibrary: m['sqliteLibrary'] as String?,
        preparsedJson: m['preparsedJson'] as String?,
      );
}

/// What the writer reports when it finishes.
class ImportWriterResult {
  const ImportWriterResult({
    required this.pages,
    required this.firstPageId,
    required this.images,
    required this.strokes,
    required this.tags,
    required this.droppedStrokes,
    required this.skippedSections,
    required this.lastSeq,
  });

  final int pages;
  final String? firstPageId;

  /// The arrival counters. They are process globals in `onenote_import.dart`,
  /// accumulated as content is written — and globals are **per isolate**, so the
  /// main side would read zeros. They have to be carried back explicitly.
  final int images;
  final int strokes;
  final int tags;
  final int droppedStrokes;

  final List<String> skippedSections;

  /// The op-log sequence this device reached. The main isolate persists it into
  /// workspace settings; without that, the next open would see a log ahead of
  /// the remembered seq and correctly conclude another installation had been
  /// writing as us — and fork the device id (ADR-0006 §6a.2).
  final int lastSeq;

  static ImportWriterResult fromMap(Map<Object?, Object?> m) =>
      ImportWriterResult(
        pages: (m['pages'] as num).toInt(),
        firstPageId: m['firstPageId'] as String?,
        images: (m['images'] as num?)?.toInt() ?? 0,
        strokes: (m['strokes'] as num?)?.toInt() ?? 0,
        tags: (m['tags'] as num?)?.toInt() ?? 0,
        droppedStrokes: (m['dropped'] as num?)?.toInt() ?? 0,
        skippedSections:
            ((m['skipped'] as List?) ?? const []).cast<String>().toList(),
        lastSeq: (m['seq'] as num?)?.toInt() ?? 0,
      );
}

// ── The isolate ───────────────────────────────────────────────────────────

/// Entry point. [message] is `(SendPort toMain, Map config)`.
void importWriterMain((SendPort, Map<Object?, Object?>) message) {
  final (toMain, rawConfig) = message;
  final config = ImportWriterConfig.fromMap(rawConfig);
  final fromMain = ReceivePort();

  // Hand the main isolate a way to answer measurement requests and to cancel.
  // First message out, before any work, so a cancel arriving immediately has
  // somewhere to land.
  toMain.send({'t': 'ready', 'port': fromMain.sendPort});

  var cancelled = false;
  Completer<List<Object?>>? pendingMeasure;

  fromMain.listen((msg) {
    if (msg is! Map) return;
    switch (msg['t']) {
      case 'cancel':
        cancelled = true;
        // Release a measurement wait so the writer can reach its next cancel
        // check instead of blocking on an answer that is no longer coming.
        pendingMeasure?.complete(const []);
        pendingMeasure = null;
      case 'measured':
        pendingMeasure?.complete((msg['ys'] as List?) ?? const []);
        pendingMeasure = null;
    }
  });

  Future<List<Object?>> measure(List<Object?> boxesPerPage) {
    final c = Completer<List<Object?>>();
    pendingMeasure = c;
    toMain.send({'t': 'measure', 'boxes': boxesPerPage});
    return c.future;
  }

  Future<void> run() async {
    Database? db;
    // The terminal message is BUILT here and SENT in the `finally`, after the
    // container is closed. Sending it inline looked fine and wasn't: the main
    // isolate reopens the notebook the instant it hears "done", and it won an
    // sqlite3 `database is locked` race against this isolate's own dispose.
    // Handing a file over is not finished until the handle is gone.
    Map<String, Object?>? terminal;
    try {
      if (config.sqliteLibrary != null) {
        open.overrideForAll(() => DynamicLibrary.open(config.sqliteLibrary!));
      }

      final Map<String, dynamic> parsed;
      if (config.preparsedJson != null) {
        parsed = jsonDecode(config.preparsedJson!) as Map<String, dynamic>;
        for (final s in (parsed['sections'] as List? ?? const [])) {
          for (final pg
              in ((((s as Map)['section'] as Map?)?['pages'] as List?) ??
                  const [])) {
            decodePageImagesInPlace((pg as Map).cast<String, dynamic>());
          }
        }
      } else {
        if (OnoteCore.instance == null) throw StateError('core unavailable');
        final bytes = await File(config.sourcePath).readAsBytes();
        if (cancelled) return;
        parsed = parseOnepkgStructured(bytes);
      }
      if (cancelled) return;
      final skipped =
          ((parsed['failed'] as List?) ?? const []).cast<String>().toList();
      if (parsed['ok'] != true) {
        terminal = {
          't': 'error',
          'message': parsed['error'] as String?,
          'skipped': skipped,
        };
        return;
      }
      final sections = (parsed['sections'] as List?) ?? const [];
      final pages = <Map<String, dynamic>>[
        for (final s in sections)
          for (final pg
              in ((((s as Map)['section'] as Map?)?['pages'] as List?) ??
                  const []))
            (pg as Map).cast<String, dynamic>()
      ];
      if (pages.isEmpty) {
        terminal = {'t': 'error', 'message': null, 'skipped': skipped};
        return;
      }
      toMain.send({'t': 'parsed', 'pages': pages.length});

      db = openOnote(config.notebookPath,
          notebookId: config.notebookId, title: config.title);
      final sink = IsolateImportSink.open(db, config);

      final counts = await writePackageInBatches(
        sink,
        sections,
        batchPages: config.batchPages,
        // The restack cannot run here (TextPainter is root-isolate-only), so
        // each batch asks the main isolate to lay its pages out first, and
        // `restack: false` stops the translation trying again.
        restack: false,
        prepareBatch: (batch) async {
          final ys = await measure([
            for (final pg in batch)
              [
                for (final b in (((pg as Map)['boxes'] as List?) ?? const []))
                  flowMeasurementInput((b as Map).cast<String, dynamic>())
              ]
          ]);
          for (var i = 0; i < batch.length && i < ys.length; i++) {
            final boxes = ((batch[i] as Map)['boxes'] as List?) ?? const [];
            final pageYs = (ys[i] as List?) ?? const [];
            for (var b = 0; b < boxes.length && b < pageYs.length; b++) {
              final box = boxes[b];
              final y = pageYs[b];
              // A null means the restack left this box's position alone AND it
              // never had one. Writing anything here would invent a position.
              if (box is Map && y != null) box['y'] = y;
            }
          }
        },
        shouldCancel: () => cancelled,
        onProgress: (name, done, total) => toMain.send(
            {'t': 'progress', 'section': name, 'done': done, 'total': total}),
      );

      if (cancelled) return;

      terminal = {
        't': 'done',
        'pages': counts.pages,
        'firstPageId': counts.firstPageId,
        'images': lastImportedImages,
        'strokes': lastImportedStrokes,
        'tags': lastImportedTags,
        'dropped': lastDroppedStrokes,
        'skipped': skipped,
        'seq': sink.lastSeq,
      };
    } catch (e, st) {
      terminal = {'t': 'error', 'message': '$e', 'stack': '$st'};
    } finally {
      // ALWAYS, including after a cancel. sqlite3's Database is a native
      // resource; an isolate that exits without disposing leaks the handle for
      // the life of the process — and on Windows an open handle is why the
      // teardown's file delete would then fail, leaving a half-imported
      // notebook on disk that nothing claims.
      db?.dispose();
      fromMain.close();
      // No terminal message means we returned early on a cancel.
      toMain.send(terminal ?? const {'t': 'cancelled'});
    }
  }

  unawaited(run());
}

/// The [ImportSink] that writes straight into one container and one op log.
///
/// The counterpart of `AppStateImportSink`: same six methods, same ordering
/// (container first, then the op — a log entry for a write that failed would
/// make rebuild-from-log differ on every disk error, ADR-0006 §7).
class IsolateImportSink implements ImportSink {
  IsolateImportSink(this.writer, this.recorder);

  /// Open a sink over an already-open container, attaching an op-log recorder
  /// unless logging is off.
  factory IsolateImportSink.open(Database db, ImportWriterConfig config) {
    final writer = NotebookWriter(db);
    if (!config.syncLogEnabled) return IsolateImportSink(writer, null);
    // Settings are Repository's, and Repository is not here. A map is enough:
    // the only setting `SyncRecorder.open` reads is the device id (passed in)
    // and the only one it writes is this device's seq, which travels home in
    // the result. A brand-new notebook has no log, so the fork check has
    // nothing to compare against and cannot trigger.
    final settings = <String, Object?>{'deviceId': config.deviceId};
    final recorder = SyncRecorder.open(
      notebookId: config.notebookId,
      notebookPath: config.notebookPath,
      title: config.title,
      logDir: config.logDir,
      readSetting: (k) => settings[k],
      writeSetting: (k, v) => settings[k] = v,
      materialiseBlobs: config.materialiseBlobs,
    );
    return IsolateImportSink(writer, recorder).._settings = settings;
  }

  final NotebookWriter writer;
  final SyncRecorder? recorder;

  Map<String, Object?> _settings = const {};

  /// The seq this device reached, for the main isolate to persist.
  int get lastSeq {
    final nb = recorder?.notebookId;
    if (nb == null) return 0;
    return (_settings['deviceSeq:$nb'] as num?)?.toInt() ?? 0;
  }

  @override
  List<TreeNode> nodes() => writer.loadNodes();

  @override
  TreeNode node(TreeNode n) {
    final saved = writer.upsertNode(n);
    recorder?.node(saved);
    return saved;
  }

  @override
  void page(String pageId, List<Block> blocks, PageProps props) {
    // Imported handwriting becomes bytes HERE rather than in the importer.
    //
    // The importer builds ink as JSON stroke maps because that is what the
    // Rust parser hands back and what the model takes; converting it there
    // would mean the same change in every importer. This is the one place
    // every import route already funnels through, and it has `blob` beside it.
    //
    // On the real notebook this is the difference between an import writing
    // 63 MB of stroke text and writing 3.2 MB — twice, since the log gets a
    // copy too.
    final toWrite = InkStorage.persistAll(blocks, (bytes) => blob(bytes, inkMimeType));
    writer.writePage(pageId, toWrite, props);
    recorder?.page(pageId, toWrite, props);
  }

  @override
  String blob(Uint8List bytes, String mime) {
    final hash = writer.putBlob(bytes, mime);
    recorder?.blob(hash, mime, bytes.length, bytes);
    return hash;
  }

  @override
  T batch<T>(T Function() body) => writer.runInTransaction(body);

  @override
  void purgeNode(String id) {
    writer.purgeNode(id);
    recorder?.nodePurged(id);
  }
}

// ── The main-isolate driver ───────────────────────────────────────────────

/// A running import. The future completes when the writer finishes, fails or
/// honours a cancel.
class ImportWriterHandle {
  ImportWriterHandle._(this.result, this._cancel);

  final Future<ImportWriterResult?> result;
  final void Function() _cancel;

  /// Ask the writer to stop. It finishes the batch it is in — a few pages —
  /// and shuts down cleanly, which matters more than stopping instantly:
  /// killing the isolate outright would leave its SQLite handle open, and on
  /// Windows an open handle is exactly why the teardown's file delete would
  /// then fail and leave a half-imported notebook nothing claims.
  ///
  /// [result] completes with null once it has stopped.
  void cancel() => _cancel();

  /// How many measurement round-trips the writer has asked the main isolate to
  /// serve since this was last reset.
  ///
  /// A **counter, not a clock**, and it exists for one assertion: that pages
  /// start landing before the whole notebook has been laid out. The shape this
  /// import replaced measured every page up front and only then wrote, so the
  /// first write necessarily came after the last measurement; the streaming
  /// shape interleaves them, so the first write lands after one batch's worth.
  ///
  /// That claim used to be tested as a wall-clock ratio — first progress inside
  /// the first quarter of the run — which passed alone and failed in a full
  /// suite, because `flutter test` runs files in parallel and the ratio was
  /// really measuring how much CPU the machine had left. On a two-core CI
  /// runner it failed every time, on all four platforms. Counting the thing the
  /// change actually altered depends on nothing but the code.
  static int debugMeasureRequests = 0;
}

/// Spawn the writer and drive the conversation.
///
/// [frameYield] is how the measurement pass gives the frame back — the app
/// passes `SchedulerBinding.instance.endOfFrame`, which (unlike a zero-delay
/// timer) does not continue until a frame has actually been produced. It is a
/// parameter rather than a default because a `flutter_test` fake clock never
/// produces frames unless the test pumps, so a hard-coded `endOfFrame` would
/// turn every headless import test into a hang.
ImportWriterHandle startImportWriter(
  ImportWriterConfig config, {
  required Future<void> Function() frameYield,
  void Function(int pages)? onParsed,
  void Function(String section, int done, int total)? onProgress,
  // Just inside a 16.7 ms frame. A layout chunk that fits in a frame costs
  // nothing visible, so there is no reason to interrupt one; a chunk that
  // overruns gets a real frame handed back mid-way. Tightening this to 8 ms
  // dropped p99 interaction latency from 14 ms to 4 ms — both imperceptible —
  // and made a 2000-page import 60% slower, because every extra yield waits a
  // whole frame the writer is blocked on.
  Duration measureBudget = const Duration(milliseconds: 12),
}) {
  final done = Completer<ImportWriterResult?>();
  final fromWriter = ReceivePort();
  SendPort? toWriter;
  var cancelRequested = false;

  void finish(ImportWriterResult? r, [Object? error, StackTrace? st]) {
    if (done.isCompleted) return;
    fromWriter.close();
    if (error != null) {
      done.completeError(error, st);
    } else {
      done.complete(r);
    }
  }

  /// Lay out every page's flows, a frame's worth at a time.
  Future<void> answerMeasure(List<Object?> boxesPerPage) async {
    ImportWriterHandle.debugMeasureRequests++;
    // `num?`, and the nulls are load-bearing. The parser omits `y` on a box
    // whose position it could not recover, and `importOneParsedPage` defaults
    // those to `AppState.contentTop`. Reporting a missing y as 0 would defeat
    // that default and drop the box on the page's title band — a silent
    // misplacement of exactly the kind the restack exists to prevent.
    final ys = <List<num?>>[];
    final sw = Stopwatch()..start();
    // Give a frame back whenever the running chunk overruns the budget —
    // checked between BOXES, because a page is only as cheap as its worst box
    // and a single lecture page can carry one enormous text box. Never yield
    // gratuitously: [frameYield] waits for a real frame in the app, so every
    // avoidable yield puts a ~16 ms floor under a batch — a wall-clock tax of
    // seconds over a large notebook.
    Future<void> giveFrameBack() async {
      await frameYield();
      sw.reset();
    }

    for (var i = 0; i < boxesPerPage.length; i++) {
      final boxes = (boxesPerPage[i] as List?) ?? const [];
      // Mutates `y` in place, so read it back afterwards.
      await restackFlowsPaced(
        boxes,
        shouldYield: () =>
            sw.elapsedMicroseconds >= measureBudget.inMicroseconds,
        onYield: giveFrameBack,
      );
      ys.add([for (final b in boxes) (b as Map)['y'] as num?]);
    }
    toWriter?.send({'t': 'measured', 'ys': ys});
  }

  fromWriter.listen((msg) {
    // `onExit` sends null and `onError` sends [error, stack]. Both mean the
    // writer died — a native fault, an OOM, an uncaught error. `finish` is
    // idempotent, so a normal exit arriving after 'done' is harmless, and a
    // crash before it becomes a failed import rather than a progress card that
    // never moves again.
    if (msg == null) {
      finish(null, ImportWriterException('the import stopped unexpectedly'));
      return;
    }
    if (msg is List) {
      finish(null, ImportWriterException('${msg.isEmpty ? '' : msg.first}'));
      return;
    }
    if (msg is! Map) return;
    switch (msg['t']) {
      case 'ready':
        toWriter = msg['port'] as SendPort;
        // A cancel that arrived before the writer was listening still has to
        // land, or the user's Stop does nothing until the import ends.
        if (cancelRequested) toWriter!.send({'t': 'cancel'});
      case 'parsed':
        onParsed?.call((msg['pages'] as num?)?.toInt() ?? 0);
      case 'measure':
        unawaited(answerMeasure((msg['boxes'] as List?) ?? const []));
      case 'progress':
        onProgress?.call(
            msg['section'] as String? ?? '',
            (msg['done'] as num?)?.toInt() ?? 0,
            (msg['total'] as num?)?.toInt() ?? 0);
      case 'done':
        finish(ImportWriterResult.fromMap(msg));
      case 'cancelled':
        finish(null);
      case 'error':
        finish(
            null,
            ImportWriterException(msg['message'] as String?,
                ((msg['skipped'] as List?) ?? const []).cast<String>()));
    }
  });

  unawaited(() async {
    try {
      await Isolate.spawn<(SendPort, Map<Object?, Object?>)>(
        importWriterMain,
        (fromWriter.sendPort, config.toMap()),
        onError: fromWriter.sendPort,
        onExit: fromWriter.sendPort,
        errorsAreFatal: true,
        debugName: 'openote-import-writer',
      );
    } catch (e, st) {
      finish(null, e, st);
    }
  }());

  return ImportWriterHandle._(done.future, () {
    cancelRequested = true;
    toWriter?.send({'t': 'cancel'});
  });
}

/// The writer could not produce a notebook. [skippedSections] is carried
/// because "we read none of it" and "we read most of it" are different things
/// to tell someone who just handed over five years of notes.
class ImportWriterException implements Exception {
  ImportWriterException(this.message, [this.skippedSections = const []]);
  final String? message;
  final List<String> skippedSections;

  @override
  String toString() => message ?? 'the import produced nothing readable';
}

/// Test-only substitutions for a whole run, threaded from `ImportJob.start`.
///
/// One nullable parameter instead of three, so the production signature carries
/// a single clearly-named seam rather than a scattering of debug arguments.
/// Why any seam at all: see [ImportWriterConfig.preparsedJson]. Not annotated
/// `@visibleForTesting` because `ImportJob.start` names it in its signature and
/// the annotation would fire on the declaration itself — the parameter carries
/// the marker instead.
class ImportWriterOverrides {
  const ImportWriterOverrides({
    this.preparsedJson,
    this.sqliteLibrary,
    this.frameYield,
  });

  final String? preparsedJson;
  final String? sqliteLibrary;

  /// A yield that completes without a frame being produced — a `flutter_test`
  /// fake clock never produces one unless the test pumps, so the app's
  /// `endOfFrame` would hang a headless test forever.
  final Future<void> Function()? frameYield;
}
