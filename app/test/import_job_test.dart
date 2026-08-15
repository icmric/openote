// The background import: the batched writer, its cancel point, and the job
// that drives it.
//
// The Rust parser is not exercised here — these tests feed the writer the
// structure the parse isolate produces, which is exactly the seam the job was
// split at. The parser has its own e2e tests against real .one fixtures.
//
// Note on where `writePackageInBatches` runs since v0.10: it is the writer
// ISOLATE's loop now, not the app's. Its batching still matters — it is what
// bounds how long a cancel takes to land and how often progress is reported —
// but the app's responsiveness is no longer downstream of it. That property is
// pinned in `import_writer_test.dart`, which measures the gaps a real
// interaction has to fit into rather than whether a timer fires at all.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/export/import_job.dart';
import 'package:openote/export/import_sink.dart';
import 'package:openote/export/onenote_import.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/sync/op_log.dart';

import 'package:openote/export/import_writer.dart';

import 'support/sqlite.dart';

/// A parsed page in the shape the isolate hands over.
Map<String, dynamic> page(String title, {int boxes = 1, bool tagged = false}) =>
    {
      'title': title,
      'boxes': [
        for (var i = 0; i < boxes; i++)
          {
            'kind': 'text',
            'markdown': tagged && i == 0
                ? 'What is a proposition?\n  A statement that is true or false.'
                : 'Body text $i of $title',
            'x': 60.0,
            'y': 120.0 + i * 40,
            'w': 480.0,
            'flow': 0,
            if (tagged && i == 0)
              'tags': [
                {'line': 0, 'label': 'Question'}
              ],
          }
      ],
      'images': const [],
      'ink': const [],
    };

Map<String, dynamic> section(String name, List<Map<String, dynamic>> pages,
        {String? group}) =>
    {
      'name': name,
      if (group != null) 'group': group,
      'section': {'pages': pages},
    };

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Future<(Repository, Directory, AppState, String)> fixture(String name) async {
    final tmp = Directory.systemTemp.createTempSync(name);
    final repo = await Repository.openAt(tmp);
    addTearDown(() async {
      await repo.flushWorkspace();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final app = AppState(repo);
    final ref = await app.importCreateNotebook('Imported');
    return (repo, tmp, app, ref.id);
  }

  group('writePackageInBatches', () {
    test('imports sections, groups and pages with the right counts', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, _, app, nb) = await fixture('onote_job_counts_');

      final r = await writePackageInBatches(AppStateImportSink(app, nb), [
        section('Week 1', [page('Mon'), page('Tue', tagged: true)]),
        section('Week 2', [page('Wed')], group: 'Semester 1'),
      ]);

      expect(r.pages, 3);
      expect(r.firstPageId, isNotNull);
      final nodes = repo.loadNodes(nb);
      expect(nodes.where((n) => n.kind == NodeKind.section).length, 2);
      expect(nodes.where((n) => n.kind == NodeKind.sectionGroup).length, 1);
      expect(nodes.where((n) => n.kind == NodeKind.page).length, 3);
      // The seeded starter section is gone once real content landed.
      expect(nodes.where((n) => n.title == 'Section 1'), isEmpty);
      // The tag arrived and is findable without opening the page.
      expect(repo.pageIdsWithTags(nb), hasLength(1));
    });

    test('yields between batches, so cancel and progress can land', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (_, _, app, nb) = await fixture('onote_job_yield_');

      // A 40-page section. An earlier writer put the whole section in ONE
      // synchronous transaction, so nothing else in its isolate ran until
      // every page was written — no cancel check, no progress callback, and
      // (back when this ran on the UI thread) no frames either.
      var ticks = 0;
      final timer =
          Timer.periodic(const Duration(milliseconds: 1), (_) => ticks++);
      addTearDown(timer.cancel);

      await writePackageInBatches(
        AppStateImportSink(app, nb),
        [
          section('Big', [for (var i = 0; i < 40; i++) page('P$i', boxes: 3)])
        ],
        batchPages: 4,
      );

      expect(ticks, greaterThan(0),
          reason: 'nothing else ran during the entire write — a cancel could '
              'not be seen and no progress could be reported');
    });

    // ── The `.one` SECTION path (task #41) ──────────────────────────────
    //
    // The package path above runs in the writer isolate. Importing a single
    // `.one` into the notebook the user has open does not: it writes on the UI
    // isolate, and it used to do so in one synchronous transaction over the
    // whole section. Measured on the owner's notebook, the worst section (80
    // pages) blocked the event loop for 4.9 s with ZERO turns given to anything
    // else — the app frozen, and the busy dialog already popped because it only
    // ever wrapped the parse.
    test('a .one section yields between pages, so the app can paint and type',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, _, app, nb) = await fixture('onote_section_yield_');

      var ticks = 0;
      final timer =
          Timer.periodic(const Duration(milliseconds: 1), (_) => ticks++);
      addTearDown(timer.cancel);

      final (count, first) = await importParsedSection(app, nb, 'Big',
          [for (var i = 0; i < 60; i++) page('P$i', boxes: 3)]);

      // 60 pages at one per slice is 59 yields of at least a millisecond each,
      // so the counter cannot stay near zero. Unpaced, the whole section is a
      // single turn of the event loop and this counter cannot move AT ALL.
      expect(ticks, greaterThan(20),
          reason: 'the write must give the window turns to paint and type in, '
              'not run as one block');
      // …and it still imported everything.
      expect(count, 60);
      expect(first, isNotNull);
      expect(
          repo
              .loadNodes(nb)
              .where((n) => n.kind == NodeKind.page && n.title.startsWith('P'))
              .length,
          60);
    });

    test('the section import says which page it is on', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (_, _, app, nb) = await fixture('onote_section_progress_');

      // What the busy dialog renders. It could report nothing before this
      // change — not because it was never asked, but because a write that
      // never yields gives no frame in which a notifier's listeners can run.
      final seen = <(int, int)>[];
      await importParsedSection(
          app, nb, 'Big', [for (var i = 0; i < 12; i++) page('P$i')],
          onProgress: (done, total) => seen.add((done, total)));

      expect(seen.length, 12, reason: 'one report per page');
      expect(seen.first, (1, 12));
      expect(seen.last, (12, 12));
      // Monotonic, and never claims more than it has written.
      for (var i = 0; i < seen.length; i++) {
        expect(seen[i].$1, i + 1);
        expect(seen[i].$2, 12);
      }
    });

    test('cancel stops at a batch boundary, not at the end', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (_, _, app, nb) = await fixture('onote_job_cancel_');

      var written = 0;
      var cancelled = false;
      final r = await writePackageInBatches(
        AppStateImportSink(app, nb),
        [
          section('Big', [for (var i = 0; i < 40; i++) page('P$i')])
        ],
        batchPages: 4,
        shouldCancel: () => cancelled,
        onProgress: (_, done, __) {
          written = done;
          if (done >= 8) cancelled = true;
        },
      );

      expect(r.pages, lessThan(40));
      expect(r.pages, written);
    });

    test('progress narrates pages done against the true total', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (_, _, app, nb) = await fixture('onote_job_progress_');
      final seen = <(int, int)>[];
      await writePackageInBatches(
        AppStateImportSink(app, nb),
        [
          section('A', [for (var i = 0; i < 5; i++) page('A$i')]),
          section('B', [for (var i = 0; i < 3; i++) page('B$i')]),
        ],
        batchPages: 2,
        onProgress: (_, done, total) => seen.add((done, total)),
      );
      expect(seen.last, (8, 8));
      expect(seen.every((e) => e.$2 == 8), isTrue,
          reason: 'the denominator must be the whole package, not the section');
      expect(seen.map((e) => e.$1).toList(),
          List.of(seen.map((e) => e.$1))..sort(),
          reason: 'progress never goes backwards');
    });
  });

  group('image decoding at the isolate seam', () {
    test('decodePageImagesInPlace turns base64 into bytes', () {
      final png = Uint8List.fromList(List.generate(64, (i) => i));
      final p = <String, dynamic>{
        'images': [
          {'data_base64': base64Encode(png), 'in_flow': false},
          {'data_base64': '', 'in_flow': false},
        ],
      };
      decodePageImagesInPlace(p);
      final imgs = p['images'] as List;
      expect((imgs[0] as Map)['bytes'], png);
      expect((imgs[0] as Map).containsKey('data_base64'), isFalse);
      expect((imgs[1] as Map).containsKey('bytes'), isFalse);
    });

    test('the page writer accepts bytes and base64 alike', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, _, app, nb) = await fixture('onote_job_img_');
      final png = Uint8List.fromList(List.generate(256, (i) => i % 251));

      final withBytes = page('Bytes');
      withBytes['images'] = [
        {'bytes': png, 'in_flow': false, 'x': 10.0, 'y': 120.0}
      ];
      final withB64 = page('B64');
      withB64['images'] = [
        {
          'data_base64': base64Encode(png),
          'in_flow': false,
          'x': 10.0,
          'y': 120.0
        }
      ];

      final r = await writePackageInBatches(AppStateImportSink(app, nb), [
        section('S', [withBytes, withB64])
      ]);
      expect(r.pages, 2);
      // One blob, stored once — identical bytes share a hash by design.
      expect(repo.blobIndex(nb).length, 1);
    });
  });

  group('ImportJob — the state machine over the writer isolate', () {
    tearDown(() => ImportJob.current = null);

    ImportWriterOverrides overrides(String json) => ImportWriterOverrides(
          preparsedJson: json,
          sqliteLibrary: sqliteLibraryPathForTests,
          // The app passes `SchedulerBinding.instance.endOfFrame`; nothing
          // pumps here, so that would never complete.
          frameYield: () => Future<void>.delayed(Duration.zero),
        );

    String packageJson(List<Map<String, dynamic>> sections,
            {List<String> failed = const []}) =>
        jsonEncode({'ok': true, 'sections': sections, 'failed': failed});

    /// Wait for the job to reach a terminal state.
    ///
    /// The budget is deliberately far larger than the work: these tests spawn a
    /// real writer isolate, and `flutter test` runs several such files at once.
    /// On GitHub's macOS runners — three cores against four for Linux and
    /// Windows — that contention was enough to blow a ten-second ceiling, and
    /// the whole group failed there while passing everywhere else. A generous
    /// ceiling costs nothing on a fast machine, because it stops the moment the
    /// job finishes; it only decides how long a genuinely stuck job hangs
    /// before it is reported.
    Future<void> settle(ImportJob job) async {
      for (var i = 0; i < 12000 && !job.isFinished; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(job.isFinished, isTrue,
          reason: 'the job never reached a terminal state within 60s');
    }

    test('an import lands, and the card can say what arrived', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, _, app, _) = await fixture('onote_jobrun_ok_');

      final job =
          ImportJob.start(app, 'Discrete Maths.onepkg', 'ignored.onepkg',
              debugOverrides: overrides(packageJson([
                section('Week 1', [page('Mon'), page('Tue')]),
              ])));
      expect(job, isNotNull);
      await settle(job!);

      expect(job.state, ImportJobState.done);
      expect(job.importedPages, 2);
      expect(job.firstPageId, isNotNull);
      expect(job.message, contains('Imported'));
      // The notebook is named after the file, and it is really there.
      final imported =
          repo.notebooks.firstWhere((n) => n.title == 'Discrete Maths');
      expect(repo.loadNodes(imported.id).where((n) => n.kind == NodeKind.page),
          hasLength(2));
      // And the seq the isolate reached was persisted here — without it the
      // next open forks this device's id.
      expect(repo.getSetting('deviceSeq:${imported.id}'), isNotNull);
    });

    test('an imported picture has its bytes in the notebook folder, not only '
        'in the notebook file', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, _, app, _) = await fixture('onote_jobrun_blob_');
      final png = Uint8List.fromList(List.generate(300, (i) => (i * 7) & 0xff));
      final withImage = page('Diagram')
        ..['images'] = [
          {
            'data_base64': base64Encode(png),
            'in_flow': false,
            'x': 10.0,
            'y': 120.0
          }
        ];

      final job = ImportJob.start(app, 'Pictures.onepkg', 'ignored.onepkg',
          debugOverrides: overrides(packageJson([
            section('W1', [withImage])
          ])));
      await settle(job!);
      expect(job.state, ImportJobState.done);

      // **This is where the owner's 26.3 MB hole came from.** The writer
      // isolate used to be handed `materialiseBlobs: app.notebookIsShared(nb)`,
      // and an import into the local workspace is never shared at that moment —
      // so 378 of 488 pictures went into the container alone, and the log named
      // bytes that were nowhere on disk. An import is also the cheapest place
      // to get this right: the bytes are already in hand.
      final ref = repo.notebooks.firstWhere((n) => n.title == 'Pictures');
      final store = OpLogStore.forNotebook(ref.file, logDir: ref.logDir);
      final index = repo.blobIndex(ref.id);
      expect(index, hasLength(1));
      expect(store.readBlob(index.single.hash), png,
          reason: 'the same bytes, not merely a file of the right name');
    });

    test('a partial import says which sections did not make it', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (_, _, app, _) = await fixture('onote_jobrun_partial_');

      final job = ImportJob.start(app, 'Notes.onepkg', 'ignored.onepkg',
          debugOverrides: overrides(packageJson([
            section('Good', [page('P')])
          ], failed: [
            'Broken.one'
          ])));
      await settle(job!);

      expect(job.state, ImportJobState.done);
      expect(job.skippedSections, ['Broken.one']);
      expect(job.message, contains('1 section could not be read'));
    });

    test('an unreadable package fails, and the half-built notebook is gone',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, _, app, _) = await fixture('onote_jobrun_bad_');
      final before = repo.notebooks.length;

      final job = ImportJob.start(app, 'Broken.onepkg', 'ignored.onepkg',
          debugOverrides:
              overrides(jsonEncode({'ok': false, 'error': 'not a package'})));
      await settle(job!);

      expect(job.state, ImportJobState.failed);
      expect(job.message, contains('not a package'));
      // Everything or nothing. The notes still exist in OneNote, so a half
      // notebook in the list would be worse than none — and it must not be in
      // the recycle bin either, offering to restore half of something.
      expect(repo.notebooks, hasLength(before));
      expect(repo.trashedNotebooks, isEmpty);
    });

    test('a file with no path on disk is refused with a sentence', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (_, _, app, _) = await fixture('onote_jobrun_nopath_');

      final job = ImportJob.start(app, 'Ghost.onepkg', '');
      await settle(job!);

      expect(job.state, ImportJobState.failed);
      expect(job.message, contains('no location on disk'));
    });

    test('one at a time', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (_, _, app, _) = await fixture('onote_jobrun_one_');
      ImportJob.current = ImportJob.debugCreate(app, 'First.onepkg');

      expect(ImportJob.start(app, 'Second.onepkg', 'x.onepkg'), isNull,
          reason: 'two imports interleaving would confuse every progress '
              'surface and halve each other\'s throughput');
    });
  });

  group('the app frame yield', () {
    testWidgets('waits for a frame AND an idle gap, in that order',
        (tester) async {
      // The gap is the load-bearing half. On Windows the UI isolate lives on
      // the Win32 message loop, where posted messages outrank hardware input —
      // so a layout loop that resumes straight off the frame pipeline keeps
      // the queue non-empty forever and mouse/keyboard starve while frames
      // keep flowing. That was "any inputs I give aren't executed until after
      // the import is complete", four reports in. A regression to plain
      // `endOfFrame` completes without the second pump and fails here.
      var done = false;
      unawaited(ImportJob.appFrameYield().then((_) => done = true));

      await tester.pump(); // produce the frame endOfFrame is waiting for
      expect(done, isFalse,
          reason: 'resuming straight off the frame pipeline is the Windows '
              'input-starvation bug — there must be an idle gap');

      await tester.pump(const Duration(milliseconds: 2));
      expect(done, isTrue);
    });

    test('a yield with no event-loop turn starves timers — the mechanism',
        () async {
      // Not a test of app code: a demonstration pinning WHY the yield must
      // relinquish the event loop. A paced layout whose yields only await
      // microtasks never lets a timer fire, no matter how many chunks it
      // splits into — the starvation is total until the work ends. This is
      // the desktop failure in miniature, reproducible even on the Linux CI
      // VM that cannot reproduce the Win32 half.
      var ticks = 0;
      final timer =
          Timer.periodic(const Duration(milliseconds: 1), (_) => ticks++);

      final giant = <dynamic>[
        {
          'kind': 'text',
          'markdown': List.generate(
              2000,
              (l) => 'Line \$l long enough to wrap at this width, twice '
                  'over with room to spare.').join('\n'),
          'x': 60.0,
          'y': 100.0,
          'w': 300.0,
          'flow': 1,
        },
        {
          'kind': 'text',
          'markdown': 'the box below',
          'x': 60.0,
          'y': 140.0,
          'w': 300.0,
          'flow': 1,
        },
      ];

      await restackFlowsPaced(
        giant,
        shouldYield: () => true,
        onYield: () => Future<void>.microtask(() {}), // frame-pipeline-like
      );
      final starved = ticks;

      await restackFlowsPaced(
        giant,
        shouldYield: () => true,
        onYield: () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
      timer.cancel();

      expect(starved, 0,
          reason: 'microtask-only yields never give the event loop a turn — '
              'this passing non-zero would mean the mechanism analysis is '
              'wrong and the fix is built on sand');
      expect(ticks, greaterThan(0),
          reason: 'a real delay must let timers (and on Windows, input) run');
    });
  });
}
