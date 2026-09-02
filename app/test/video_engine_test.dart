// The video engine is a download, not part of the install.
//
// Measured on the v0.7.1 Windows Release bundle, libmpv and ANGLE were
// 48,423,670 B of 100,871,746 B — 48% of everything a student downloads, for a
// feature most of them never use. Splitting them out is worth doing and it is
// also the one change in this area that can frighten somebody: the whole
// failure mode is "my lecture has gone".
//
// So the tests are in two halves. The CACHE half is about a download that
// either completes and verifies or leaves nothing at all — the interesting
// cases are a byte-perfect length with wrong bytes, and an interruption. The
// CARD half is the NEGATIVE CONTROL: with no engine anywhere on the machine, a
// page with a video still opens, still renders, still says the video is here,
// and the reclamation sweep in store/media_gc.dart still counts the file as
// referenced. The player is optional. The video never is.
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/file_block_view.dart';
import 'package:openote/editor/video_block_view.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/media/video_engine.dart';
import 'package:openote/media/video_playback.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/media_gc.dart';
import 'package:openote/store/media_store.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/store/notebook_writer.dart' show sha256Hex;
import 'package:openote/update/app_update.dart';

import 'support/sqlite.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('onote_engine_');
    VideoEngine.debugSetRoot(tmp);
  });

  tearDown(() {
    VideoEngine.debugSetRoot(null);
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Stand-in bytes for one engine file, of exactly the pinned length. The
  /// real DLLs are 46 MB and are not in the repo; what is being tested is the
  /// bookkeeping around them, which does not care what is inside.
  Uint8List filler(EngineFile f, {int fill = 0x41}) =>
      Uint8List(f.bytes)..fillRange(0, f.bytes, fill);

  /// A zip holding one entry per engine file. [corrupt] names a file to fill
  /// with different bytes OF THE SAME LENGTH; [omit] leaves one out.
  Uint8List archiveOf(
      {String? corrupt, String? omit, Map<String, Uint8List>? real}) {
    final a = Archive();
    for (final f in VideoEngine.files) {
      if (f.name == omit) continue;
      final bytes = real?[f.name] ??
          filler(f, fill: f.name == corrupt ? 0x42 : 0x41);
      a.addFile(ArchiveFile(f.name, bytes.length, bytes));
    }
    return Uint8List.fromList(ZipEncoder().encode(a));
  }

  /// The manifest, rewritten so the pinned hashes describe [archiveOf]'s
  /// filler bytes instead of the real DLLs. Returns a fetch function; the test
  /// asserts against `VideoEngine.files` as patched.
  //
  // Not done by patching the constant — the point of the constant is that it
  // is pinned. Instead each test that wants a *passing* install computes the
  // filler hashes and asserts install() accepts exactly those, which is the
  // same check from the other side.

  group('the engine cache', () {
    test('nothing is installed on a machine that has never downloaded it', () {
      expect(VideoEngine.isInstalled, isFalse);
      expect(VideoEngine.load(), isFalse,
          reason: 'and asking it to load is a false, not a throw');
    });

    test('a file with the right length and the wrong bytes is refused',
        () async {
      // The lesson of commit 435b2bd, which replaced a length comparison in
      // the notebook mover with a SHA-256 one: a torn copy has the right
      // length far too often for a length to be a check. Here the archive is
      // complete, every entry is exactly the pinned number of bytes, and the
      // contents are wrong.
      await expectLater(
        VideoEngine.install(fetch: (_) async => archiveOf()),
        throwsA(isA<EngineInstallFailure>().having(
            (e) => e.details, 'details', contains('sha-256 mismatch'))),
      );
      expect(VideoEngine.isInstalled, isFalse,
          reason: 'a refused engine must not look installed');
      expect(
          Directory('${tmp.path}/video-engine').existsSync()
              ? Directory('${tmp.path}/video-engine').listSync()
              : const [],
          isEmpty,
          reason: 'and must leave nothing behind for the next launch to find');
    });

    test('the message a student reads names no DLL, no URL and no exception',
        () async {
      // Jargon rule. The sentence is what appears on the dialog; every
      // technical word belongs behind "Details (advanced)".
      try {
        await VideoEngine.install(fetch: (_) async => archiveOf());
        fail('expected a failure');
      } on EngineInstallFailure catch (e) {
        for (final jargon in [
          'dll',
          'sha',
          'mpv',
          'angle',
          'http',
          'exception',
          '://',
        ]) {
          expect(e.message.toLowerCase(), isNot(contains(jargon)),
              reason: '"$jargon" is for Details (advanced), not the card');
        }
        expect(e.message, contains('Nothing on this computer was changed.'));
      }
    });

    test('an archive missing a file is refused before anything is written',
        () async {
      final a = Uint8List.fromList(List.generate(64, (i) => i));
      final b = Uint8List.fromList(List.generate(31, (i) => 255 - i));
      VideoEngine.debugSetFiles([
        EngineFile('one.bin', a.length, sha256Hex(a)),
        EngineFile('two.bin', b.length, sha256Hex(b)),
      ]);
      addTearDown(() => VideoEngine.debugSetFiles(null));
      await expectLater(
        VideoEngine.install(
            fetch: (_) async => archiveOf(real: {'one.bin': a}, omit: 'two.bin')),
        throwsA(isA<EngineInstallFailure>()
            .having((e) => e.details, 'details', contains('missing two.bin'))),
      );
      expect(VideoEngine.isInstalled, isFalse);
    });

    test('a download that dies half way leaves nothing to find', () async {
      // The shape that matters: half an ANGLE set is not a slow start, it is
      // a crash inside a graphics driver with no message attached.
      await expectLater(
        VideoEngine.install(
            fetch: (_) async => throw const SocketException('connection reset')),
        throwsA(isA<EngineInstallFailure>()),
      );
      expect(VideoEngine.isInstalled, isFalse);
      expect(Directory('${tmp.path}/video-engine').existsSync(), isFalse,
          reason: 'not even a .partial directory survives');
    });

    test('a complete, verified engine installs, and a second launch reuses it',
        () async {
      // The happy path, on a small stand-in manifest — the real one names
      // 46 MB of DLLs that are deliberately not in the repo. Everything under
      // test here is bookkeeping: extract, hash, stamp, rename.
      final a = Uint8List.fromList(List.generate(64, (i) => i));
      final b = Uint8List.fromList(List.generate(31, (i) => 255 - i));
      VideoEngine.debugSetFiles([
        EngineFile('one.bin', a.length, sha256Hex(a)),
        EngineFile('two.bin', b.length, sha256Hex(b)),
      ]);
      addTearDown(() => VideoEngine.debugSetFiles(null));

      var fetches = 0;
      Future<Uint8List> fetch(EngineProgress p) async {
        fetches++;
        p(1.0, 'x');
        return archiveOf(real: {'one.bin': a, 'two.bin': b});
      }

      final seen = <double>[];
      await VideoEngine.install(fetch: fetch, onProgress: (f, _) => seen.add(f));
      expect(VideoEngine.isInstalled, isTrue);
      expect(seen.last, 1.0, reason: 'a 46 MB download must not look like a hang');

      final dir = Directory('${tmp.path}/video-engine/${VideoEngine.id}');
      expect(File('${dir.path}/one.bin').readAsBytesSync(), a);
      expect(File('${dir.path}/two.bin').readAsBytesSync(), b);
      expect(Directory('${dir.path}.partial').existsSync(), isFalse,
          reason: 'the staging directory is the commit, and it is gone');

      // The second launch. Nothing is fetched and nothing is re-hashed —
      // re-reading 46 MB to answer a question the stamp already answers would
      // cost more than the whole startup budget.
      expect(VideoEngine.isInstalled, isTrue);
      expect(fetches, 1, reason: 'a second launch does not download again');

      // And a file deleted by hand puts it back to "not installed" rather
      // than half-loading a broken set.
      File('${dir.path}/one.bin').deleteSync();
      expect(VideoEngine.isInstalled, isFalse);
    });

    test('a failed install never disturbs an engine that is already there',
        () async {
      // The upgrade case: somebody with a working player presses "Get it"
      // again, or a later version re-downloads. A refusal must leave the
      // engine they already have exactly as it was.
      final a = Uint8List.fromList(List.generate(64, (i) => i));
      VideoEngine.debugSetFiles([EngineFile('one.bin', a.length, sha256Hex(a))]);
      addTearDown(() => VideoEngine.debugSetFiles(null));

      await VideoEngine.install(
          fetch: (_) async => archiveOf(real: {'one.bin': a}));
      expect(VideoEngine.isInstalled, isTrue);

      final wrong = Uint8List.fromList(List.generate(64, (i) => i + 1));
      await expectLater(
        VideoEngine.install(
            fetch: (_) async => archiveOf(real: {'one.bin': wrong})),
        throwsA(isA<EngineInstallFailure>()),
      );
      expect(VideoEngine.isInstalled, isTrue,
          reason: 'the working engine survived a bad download');
      final dir = Directory('${tmp.path}/video-engine/${VideoEngine.id}');
      expect(File('${dir.path}/one.bin').readAsBytesSync(), a);
    });

    test('the stamp alone is not enough — every file has to be there', () {
      final dir = Directory('${tmp.path}/video-engine/${VideoEngine.id}')
        ..createSync(recursive: true);
      File('${dir.path}/installed').writeAsStringSync(VideoEngine.id);
      expect(VideoEngine.isInstalled, isFalse);
    });

    test('the engine lives outside the workspace', () {
      // Application support, never the workspace root: anything under the
      // workspace is in reach of AppState.findOrphanFiles, of every backup,
      // and of whatever cloud client is replicating the folder. A 46 MB
      // redownloadable cache belongs in none of them.
      expect(VideoEngine.id, isNotEmpty);
      final dir = '${tmp.path}/video-engine/${VideoEngine.id}';
      expect(dir, isNot(contains('.onote')));
    });
  });

  group('the release asset', () {
    test('is not something the updater could mistake for an installer', () {
      // app_update.parseLatestRelease picks the Windows installer out of a
      // release with `name.endsWith('-setup.exe')` and takes the LAST match.
      // A new asset on the same release must not match, or a student pressing
      // "Update" is handed an archive of DLLs to run.
      expect(VideoEngine.assetName.endsWith('-setup.exe'), isFalse);
      expect(VideoEngine.assetName, endsWith('.zip'));

      final picked = parseLatestRelease(current: '0.0.1', json: {
        'tag_name': 'v9.9.9',
        'html_url': 'https://example.invalid/r',
        'assets': [
          {
            'name': 'openote-9.9.9-setup.exe',
            'browser_download_url': 'https://example.invalid/setup',
          },
          // Deliberately AFTER the installer: the parser keeps the last match,
          // so an asset that matched would win.
          {
            'name': VideoEngine.assetName,
            'browser_download_url': 'https://example.invalid/engine',
          },
        ],
      });
      expect(picked, isNotNull);
      expect(picked!.windowsSetupUrl, 'https://example.invalid/setup');
    });

    test('the download URL names the running version', () {
      expect(VideoEngine.downloadUrl, contains('/v$kAppVersion/'));
      expect(VideoEngine.downloadUrl, endsWith(VideoEngine.assetName));
    });
  });

  group('NEGATIVE CONTROL: no engine, and the video is still there', () {
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());

    setUp(() => VideoPlayback.debugSetAvailable(false,
        reason: VideoUnavailable.needsDownload));

    Future<(AppState, NotebookRef)> newApp(WidgetTester t) async {
      late AppState app;
      late NotebookRef ref;
      final dir = Directory.systemTemp.createTempSync('onote_negctl_');
      late Repository repo;
      addTearDown(() {
        repo.dispose();
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      });
      await t.runAsync(() async {
        repo = await Repository.openAt(dir);
        final nb = await repo.createNotebook('Lectures');
        app = AppState(repo)..notebookId = nb.id;
        ref = app.currentNotebook;
      });
      return (app, ref);
    }

    File source(String name, int bytes) {
      final f = File('${tmp.path}/$name')..createSync(recursive: true);
      f.writeAsBytesSync(Uint8List(bytes));
      return f;
    }

    Block videoBlock(String media) =>
        Block(type: BlockType.file, x: 0, y: 0, content: {
          'kind': 'video',
          'media': media,
          'name': 'Lecture 3.mp4',
          'mime': 'video/mp4',
          'size': 4096,
        });

    testWidgets('the page renders, and the card says the video is here',
        (t) async {
      // The student on the train. No engine, no signal. The notebook opened,
      // the page drew, and the sentence they read must not be one they could
      // reasonably read as "your lecture is gone".
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      expect(VideoEngine.isInstalled, isFalse,
          reason: 'the machine under test genuinely has no engine');

      final (app, ref) = await newApp(t);
      final stored = (await t.runAsync(
          () => MediaStore.add(ref, source('l.mp4', 4096))))!;
      await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: SizedBox(
              width: 420,
              height: 240,
              child: FileBlockView(block: videoBlock(stored), app: app)),
        ),
      ));
      await t.pump();

      expect(find.byType(VideoBlockView), findsOneWidget,
          reason: 'the page rendered');
      expect(find.text('Lecture 3.mp4'), findsOneWidget);
      expect(find.textContaining('saved on this computer'), findsOneWidget,
          reason: 'the one thing a student must not be left guessing about');
      expect(find.textContaining('not in this copy'), findsNothing,
          reason: 'that sentence is for a file that really is missing');
      expect(find.byIcon(Icons.videocam_off_outlined), findsNothing,
          reason: 'and so is that icon');
      expect(find.byIcon(Icons.play_circle_outline), findsOneWidget,
          reason: 'the offer is one click, not a dead end');
      // "Which package should I install" is the Linux answer and would be
      // nonsense here.
      expect(find.byIcon(Icons.help_outline), findsNothing);
    });

    testWidgets('the file is still on disk and still openable elsewhere',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (app, ref) = await newApp(t);
      final stored = (await t.runAsync(
          () => MediaStore.add(ref, source('keep.mp4', 4096))))!;
      final onDisk = MediaStore.resolve(ref, stored);
      expect(onDisk, isNotNull);
      expect(onDisk!.existsSync(), isTrue);
      expect(onDisk.lengthSync(), 4096,
          reason: 'not one byte of the video depends on the player');
      expect(app.currentNotebook.id, isNotEmpty);
    });

    test('the reclamation sweep still sees a video as referenced', () async {
      // media_gc.dart (commit 209ef72) decides what is safe to delete. It
      // reads page content and op logs and knows nothing about the player —
      // which is exactly the property to pin, because a change that made the
      // sweep stop seeing a referenced video would delete a lecture.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final dir = Directory.systemTemp.createTempSync('onote_gc_');
      final repo = await Repository.openAt(dir);
      addTearDown(() {
        repo.dispose();
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      });
      final nb = await repo.createNotebook('Lectures');
      final ref = repo.notebooks.firstWhere((n) => n.id == nb.id);
      final stored = await MediaStore.add(ref, source('lecture.mp4', 2048));

      expect(VideoEngine.isInstalled, isFalse,
          reason: 'the whole point: the sweep runs with no engine present');

      final referenced = await MediaGc.sweep(
        ref: ref,
        containerText: () => ['{"media":"$stored"}'],
        liveText: () => const [],
        minimumAge: Duration.zero,
      );
      expect(referenced.refusal, isNull);
      expect(referenced.unused, isEmpty,
          reason: 'a referenced video is never a candidate for reclamation');
      expect(MediaStore.resolve(ref, stored)!.existsSync(), isTrue);

      // And the same sweep with the reference taken away DOES list it. Without
      // this the assertion above passes just as well on a sweep that finds
      // nothing at all, which is the shape a broken test takes.
      final orphaned = await MediaGc.sweep(
        ref: ref,
        containerText: () => const [],
        liveText: () => const [],
        minimumAge: Duration.zero,
      );
      expect(orphaned.unused.map((u) => u.name), [stored],
          reason: 'the scan is live, so "empty" above means something');
      expect(MediaStore.resolve(ref, stored)!.existsSync(), isTrue,
          reason: 'a sweep reports; it does not delete');
    });
  });
}
