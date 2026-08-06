// The import writer isolate (v0.10, Option C) — the whole conversation, end to
// end, against real files.
//
// **What these reach.** The isolate spawns for real, opens a real SQLite
// container, writes a real op log, and answers the protocol. The one step
// stubbed is the Rust parse: a `.onepkg` is a CAB of binary OneNote sections,
// there is no fixture in this repository (real ones are someone's actual notes),
// and synthesising one would mean writing a second implementation of the format
// to test the first. The parse has its own end-to-end test against a real file;
// everything after it is new code, and it is what these cover.
//
// **The property that made the isolate possible** is worth stating, because it
// is what every one of these leans on: the import target is a *brand-new*
// notebook, so no other code holds its container, its log, or any state derived
// from them. That is why a second isolate can own it outright with no locking.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/export/import_writer.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/sync/op.dart';
import 'package:openote/sync/op_log.dart';

import 'support/sqlite.dart';

/// A parsed page in the shape the parse isolate produces.
///
/// `flow: 1` on every box is deliberate: it is what makes [restackFlows]
/// actually move something, which is what the measurement round trip exists to
/// do. A page of `flow: 0` boxes would pass these tests with the round trip
/// disconnected.
Map<String, dynamic> page(String title, {int boxes = 3, String? imageBase64}) =>
    {
      'title': title,
      'boxes': [
        for (var i = 0; i < boxes; i++)
          {
            'kind': 'text',
            // Long enough to wrap, which is the whole reason the parser's
            // one-line-per-source-line estimate is wrong and has to be redone
            // with real text measurement.
            'markdown': List.generate(
                6,
                (l) => 'Line $l of box $i on $title, long enough that it '
                    'wraps at this column width and so costs more vertical '
                    'space than the parser assumed.').join('\n'),
            'x': 60.0,
            'y': 120.0 + i * 40, // the naive pitch the restack corrects
            'w': 300.0,
            'flow': 1,
          }
      ],
      'images': imageBase64 == null
          ? const []
          : [
              {
                'data_base64': imageBase64,
                'x': 640.0,
                'y': 200.0,
                'disp_w': 320.0,
                'disp_h': 240.0,
              }
            ],
      'ink': const [],
    };

Map<String, dynamic> section(String name, List<Map<String, dynamic>> pages,
        {String? group}) =>
    {
      'name': name,
      if (group != null) 'group': group,
      'section': {'pages': pages},
    };

String packageJson(List<Map<String, dynamic>> sections,
        {List<String> failed = const []}) =>
    jsonEncode({'ok': true, 'sections': sections, 'failed': failed});

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  /// A workspace with one freshly created (and therefore isolate-ownable)
  /// notebook, handed over exactly as `ImportJob` hands it over.
  Future<(Repository, AppState, NotebookRef)> fixture(String name) async {
    final tmp = Directory.systemTemp.createTempSync(name);
    final repo = await Repository.openAt(tmp);
    late AppState created;
    addTearDown(() async {
      // Background log replays and blob backfills are fire-and-forget. Join
      // them before the fixture's directory goes, or one lands afterwards and
      // its file I/O is charged to whichever test runs next.
      await created.settleBackgroundWork();
      await repo.flushWorkspace();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final app = created = AppState(repo);
    final ref = await app.importCreateNotebook('Imported');
    app.beginExclusiveImport(ref.id);
    return (repo, app, ref);
  }

  ImportWriterConfig config(NotebookRef ref, String json,
          {bool materialiseBlobs = false, int batchPages = 4}) =>
      ImportWriterConfig(
        sourcePath: '/does/not/exist.onepkg', // preparsedJson wins
        notebookPath: ref.file,
        notebookId: ref.id,
        title: ref.title,
        deviceId: 'test-device',
        logDir: ref.logDir,
        materialiseBlobs: materialiseBlobs,
        batchPages: batchPages,
        sqliteLibrary: sqliteLibraryPathForTests,
        preparsedJson: json,
      );

  /// The frame yield a headless test can afford: one event-loop turn. The app
  /// passes `SchedulerBinding.instance.endOfFrame`, which would never complete
  /// here because nothing pumps.
  Future<void> tick() => Future<void>.delayed(Duration.zero);

  test('a whole package lands: groups, sections, pages, in order', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, ref) = await fixture('onote_writer_shape_');

    final result = await startImportWriter(
      config(
          ref,
          packageJson([
            section('Week 1', [page('Mon'), page('Tue')]),
            section('Week 2', [page('Wed')], group: 'Semester 1'),
          ])),
      frameYield: tick,
    ).result;

    expect(result, isNotNull);
    expect(result!.pages, 3);
    expect(result.firstPageId, isNotNull);

    app.endExclusiveImport(ref.id);
    final nodes = repo.loadNodes(ref.id);
    expect(nodes.where((n) => n.kind == NodeKind.section).length, 2);
    expect(nodes.where((n) => n.kind == NodeKind.sectionGroup).length, 1);
    expect(nodes.where((n) => n.kind == NodeKind.page).length, 3);
    // The starter section `createNotebook` seeds is gone once real content
    // landed — the isolate does that teardown too.
    expect(nodes.where((n) => n.title == 'Section 1'), isEmpty);
  });

  test('the flows are restacked, which only the main isolate can do', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, ref) = await fixture('onote_writer_restack_');

    await startImportWriter(
      config(
          ref,
          packageJson([
            section('S', [page('P', boxes: 3)])
          ])),
      frameYield: tick,
    ).result;

    app.endExclusiveImport(ref.id);
    final pageId =
        repo.loadNodes(ref.id).firstWhere((n) => n.kind == NodeKind.page).id;
    final data = repo.readPage(ref.id, pageId);
    final ys = [
      for (final b in data.blocks)
        if (b.type == BlockType.text) b.y
    ]..sort();
    expect(ys, hasLength(3));

    // The parser put them 40 apart, counting one line per source line. Six
    // wrapped lines each occupy far more than that, so a correct restack pushes
    // the second and third boxes well past where they started. If TextPainter
    // had silently not run — or the measurement round trip had been dropped —
    // these would still be 40 apart, which is exactly the imported-table-sits-
    // too-high bug restackFlows was written for.
    expect(ys[1] - ys[0], greaterThan(60),
        reason: 'the second box must be pushed down by real text measurement');
    expect(ys[2] - ys[1], greaterThan(60));
  });

  test('a box the parser gave no position keeps its default, not y=0',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, ref) = await fixture('onote_writer_noy_');

    // The parser omits `y` when it cannot recover a box's position, and
    // `importOneParsedPage` defaults those to the top of the content area.
    // The layout round trip must not quietly fill that hole in: reporting a
    // missing y as 0 sent the box to the very top of the page, under the title
    // band, which looks like a layout bug and is really a protocol one.
    final orphan = {
      'kind': 'text',
      'markdown': 'A box whose position the parser could not recover.',
      'x': 60.0,
      'flow': 0, // not in a flow, so the restack has nothing to say about it
    };
    await startImportWriter(
      config(
          ref,
          packageJson([
            section('S', [
              {
                'title': 'P',
                'boxes': [orphan],
                'images': const [],
                'ink': const [],
              }
            ])
          ])),
      frameYield: tick,
    ).result;

    app.endExclusiveImport(ref.id);
    final pageId =
        repo.loadNodes(ref.id).firstWhere((n) => n.kind == NodeKind.page).id;
    final block = repo.readPage(ref.id, pageId).blocks.single;
    expect(block.y, AppState.contentTop,
        reason: 'the importer default must survive the round trip');
  });

  test('images are stored and referenced', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, ref) = await fixture('onote_writer_images_');
    final bytes = Uint8List.fromList(List.generate(2048, (i) => i & 0xFF));

    final result = await startImportWriter(
      config(
          ref,
          packageJson([
            section('S', [page('P', imageBase64: base64Encode(bytes))])
          ])),
      frameYield: tick,
    ).result;

    expect(result!.images, 1,
        reason: 'the counters are per-isolate globals — '
            'they only reach the UI because the result carries them home');

    app.endExclusiveImport(ref.id);
    final pageId =
        repo.loadNodes(ref.id).firstWhere((n) => n.kind == NodeKind.page).id;
    final img = repo
        .readPage(ref.id, pageId)
        .blocks
        .firstWhere((b) => b.type == BlockType.image);
    final hash = (img.content['blob'] as String).replaceFirst('sha256:', '');
    expect(repo.getBlob(ref.id, hash), bytes);
  });

  test('the op log is written, and its seq comes home', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, ref) = await fixture('onote_writer_log_');

    final result = await startImportWriter(
      config(
          ref,
          packageJson([
            section('S', [page('P1'), page('P2')])
          ])),
      frameYield: tick,
    ).result;

    final store = OpLogStore.forNotebook(ref.file);
    final ops = store.readAll();
    expect(ops.where((o) => o.kind == OpKind.nodeUpsert), isNotEmpty);
    expect(ops.where((o) => o.kind == OpKind.blockSet), isNotEmpty);
    expect(ops.every((o) => o.device == 'test-device'), isTrue);

    // The seq the isolate reached has to be persisted on this side. It lives in
    // workspace settings, which the isolate cannot write — and a log running
    // ahead of the remembered seq is exactly what DeviceIdentity reads as
    // "another installation has been writing as us", which would fork the
    // device id on the next open of every imported notebook.
    expect(result!.lastSeq, greaterThan(0));
    expect(result.lastSeq, ops.where((o) => o.device == 'test-device').length);

    app.rememberImportedSeq(ref.id, result.lastSeq);
    app.endExclusiveImport(ref.id);
    expect(repo.getSetting('deviceSeq:${ref.id}'), result.lastSeq);
  });

  test('a local-only import writes no blob bytes into the log (wave 1a)',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, ref) = await fixture('onote_writer_hollow_');
    final bytes =
        Uint8List.fromList(List.generate(4096, (i) => (i * 7) & 0xFF));

    await startImportWriter(
      config(
        ref,
        packageJson([
          section('S', [page('P', imageBase64: base64Encode(bytes))])
        ]),
        materialiseBlobs: false,
      ),
      frameYield: tick,
    ).result;

    final store = OpLogStore.forNotebook(ref.file);
    expect(store.blobsDir.existsSync(), isFalse,
        reason: 'a notebook nothing else reads stores its images once');
    // ...but the op naming them is there, so turning sync on knows what to
    // fetch out of the container.
    expect(
        store.readAll().where((o) => o.kind == OpKind.blobPut), hasLength(1));

    app.endExclusiveImport(ref.id);
    final pageId =
        repo.loadNodes(ref.id).firstWhere((n) => n.kind == NodeKind.page).id;
    expect(repo.readPage(ref.id, pageId).blocks, isNotEmpty);
  });

  test('a shared import materialises them', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (_, app, ref) = await fixture('onote_writer_shared_');
    final bytes =
        Uint8List.fromList(List.generate(4096, (i) => (i * 3) & 0xFF));

    await startImportWriter(
      config(
        ref,
        packageJson([
          section('S', [page('P', imageBase64: base64Encode(bytes))])
        ]),
        materialiseBlobs: true,
      ),
      frameYield: tick,
    ).result;
    app.endExclusiveImport(ref.id);

    final store = OpLogStore.forNotebook(ref.file);
    expect(store.blobHashes(), hasLength(1));
  });

  test('cancel stops it, and stops it cleanly', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, ref) = await fixture('onote_writer_cancel_');

    final handle = startImportWriter(
      config(
        ref,
        packageJson([
          section('Big', [for (var i = 0; i < 60; i++) page('P$i')])
        ]),
        batchPages: 2,
      ),
      frameYield: tick,
      onProgress: (_, __, ___) {},
    );
    // Cancel the moment the first pages land, so this exercises the running
    // case rather than a cancel that happens to arrive before the spawn.
    handle.cancel();

    expect(await handle.result, isNull,
        reason: 'a cancelled run has no result');

    // The clean part: the isolate disposed its SQLite handle on the way out, so
    // the file can still be deleted. On Windows an open handle is precisely why
    // teardown would otherwise leave a half-imported notebook nothing claims.
    app.abandonExclusiveImport(ref.id);
    await app.discardImportedNotebook(ref.id);
    expect(File(ref.file).existsSync(), isFalse);
    expect(repo.notebooks.where((n) => n.id == ref.id), isEmpty);
  });

  // The test the v0.10 plan asked for, and the reason it asked: the existing
  // responsiveness test ("a 1 ms timer keeps firing during an import") passed
  // the whole time the user's clicks were starving. Firing is not the property
  // that matters. A click is a *conversation* — pointer-down, pointer-up,
  // gesture resolution, the handler, a state change, a rebuild, a paint, and an
  // async continuation that reads the database — and every leg of it has to fit
  // in a gap between whatever the import is doing. Under the old in-process
  // batched writer each gap was followed immediately by another 57 ms batch, so
  // the legs queued and the interaction completed when the import did.
  //
  // So this measures the gaps, not the ticks.
  test('every leg of an interaction lands inside a frame, all import long',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (_, app, ref) = await fixture('onote_writer_responsive_');

    // A page whose single text box is enormous. Real lecture pages have these,
    // no synthetic probe did, and it is why the import stall survived three
    // rounds of fixes: one TextPainter.layout of a 2000-line box is 216 ms of
    // atomic main-isolate work that pacing between boxes cannot split. The
    // paced path now measures it in 64-line chunks (probed: exactly additive)
    // — so these pages are in the responsiveness test's diet permanently.
    Map<String, dynamic> giantPage(String title) => {
          'title': title,
          'boxes': [
            {
              'kind': 'text',
              'markdown': List.generate(
                  1500,
                  (l) => 'Line $l of one enormous lecture box, with enough '
                      'words on it that it wraps at the recorded width at '
                      'least once and often twice over.').join('\n'),
              'x': 60.0,
              'y': 120.0,
              'w': 480.0,
              'flow': 1,
            },
            {
              'kind': 'text',
              'markdown': 'A second box the giant one must push down.',
              'x': 60.0,
              'y': 160.0,
              'w': 480.0,
              'flow': 1,
            },
          ],
          'images': const [],
          'ink': const [],
        };

    final handle = startImportWriter(
      config(
          ref,
          packageJson([
            section('Big', [
              for (var i = 0; i < 200; i++)
                if (i % 25 == 0) giantPage('G$i') else page('P$i')
            ])
          ]),
          batchPages: 4),
      frameYield: tick,
    );
    var importFinished = false;
    unawaited(handle.result.then((_) => importFinished = true));

    // One "leg" = a timer hop plus a microtask drain, which is what each step
    // of a real gesture → handler → setState chain costs to get scheduled.
    final legs = <int>[];
    final sw = Stopwatch()..start();
    while (!importFinished) {
      final at = sw.elapsedMicroseconds;
      await Future<void>.delayed(Duration.zero);
      await Future<void>.microtask(() {});
      legs.add(sw.elapsedMicroseconds - at);
    }
    await handle.result;
    app.endExclusiveImport(ref.id);

    expect(legs.length, greaterThan(100),
        reason: 'the loop has to have actually run during the import for the '
            'rest of this to mean anything');
    legs.sort();
    final p99 = legs[(legs.length * 0.99).floor()] / 1000;
    final worst = legs.last / 1000;
    expect(p99, lessThan(16),
        reason: 'p99 leg was ${p99.toStringAsFixed(1)} ms (worst '
            '${worst.toStringAsFixed(1)} ms). Anything approaching a batch '
            'time means the write phase is back on this thread.');
    // Generous against CI noise, but discriminating: with the chunked
    // measurement the worst observed leg is ~14 ms, while a giant box measured
    // atomically blocks for ~90 ms even on a fast machine — and this suite's
    // pages carry eight of them. Verified to fail against the atomic code.
    expect(worst, lessThan(60),
        reason: 'worst leg ${worst.toStringAsFixed(1)} ms — a giant box is '
            'being measured atomically again');
  });

  // The regression pin for the shape this replaced. The first version asked the
  // main isolate to lay out the WHOLE notebook before writing anything, which
  // meant two bad things at once: one enormous message copied in a single
  // uninterruptible go, and a progress card that showed a page total and then
  // sat on it. The report was "still locks up when it starts displaying all the
  // pages in the popup" — which is precisely the moment the total appeared and
  // the layout request went out.
  //
  // Layout is per batch now, so the first pages are written almost immediately.
  test(
      'pages start landing straight away, not after the whole notebook is '
      'laid out', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (_, app, ref) = await fixture('onote_writer_early_');

    final sw = Stopwatch()..start();
    int? firstProgressAt;
    int? doneAt;
    final handle = startImportWriter(
      config(
          ref,
          packageJson([
            section('Big', [for (var i = 0; i < 300; i++) page('P$i')])
          ]),
          batchPages: 4),
      frameYield: tick,
      onProgress: (_, __, ___) => firstProgressAt ??= sw.elapsedMicroseconds,
    );
    await handle.result;
    doneAt = sw.elapsedMicroseconds;
    app.endExclusiveImport(ref.id);

    expect(firstProgressAt, isNotNull);
    // A quarter of the run is a generous bar that the old shape could not clear
    // at any notebook size: it did every page's text layout before the first
    // write, so the first progress necessarily landed past the halfway mark.
    expect(firstProgressAt! / doneAt, lessThan(0.25),
        reason: 'the first batch reported after '
            '${(100 * firstProgressAt! / doneAt).round()}% of the import — '
            'layout is being done up front again');
  });

  test('a discarded import leaves nothing behind, not even a log directory',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (repo, app, ref) = await fixture('onote_writer_orphan_');
    final logDir = Directory(ref.logDirPath);

    await startImportWriter(
      config(
          ref,
          packageJson([
            section('S', [page('P')])
          ])),
      frameYield: tick,
    ).result;

    // The failure/cancel path. It must NOT start a background replay: the
    // replay rewrites `.onotebook/manifest.json` on its way through, so one
    // landing after the purge recreates the directory it just deleted — an
    // orphaned `.onotebook` no registry entry claims, which is what the
    // free-name search downstream then trips over.
    app.abandonExclusiveImport(ref.id);
    await app.discardImportedNotebook(ref.id);
    await app.settleBackgroundWork();

    expect(File(ref.file).existsSync(), isFalse);
    expect(logDir.existsSync(), isFalse,
        reason: 'a discarded import must not leave an orphaned .onotebook');
    expect(repo.notebooks.where((n) => n.id == ref.id), isEmpty);
  });

  test('a package with nothing readable fails with the reason', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (_, app, ref) = await fixture('onote_writer_empty_');

    await expectLater(
      startImportWriter(
        config(ref, jsonEncode({'ok': false, 'error': 'not a package'})),
        frameYield: tick,
      ).result,
      throwsA(isA<ImportWriterException>()
          .having((e) => e.message, 'message', 'not a package')),
    );
    app.endExclusiveImport(ref.id);
  });

  test('sections that failed to parse are named, not swallowed', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (_, app, ref) = await fixture('onote_writer_partial_');

    final result = await startImportWriter(
      config(
          ref,
          packageJson([
            section('Good', [page('P')])
          ], failed: [
            'Broken.one'
          ])),
      frameYield: tick,
    ).result;
    app.endExclusiveImport(ref.id);

    expect(result!.pages, 1);
    expect(result.skippedSections, ['Broken.one'],
        reason: 'someone who just handed over five years of notes must be told '
            'which parts did not make it');
  });
}
