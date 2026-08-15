// Videos you keep in the notebook, and play in the page.
//
// The ask: "i do really want the ability to put in my own custom videos, even
// if it will chew through storage. I also want to be able to watch the videos
// in the app, that is most of the point of having it in there, otherwise its
// just a hyperlink to a website."
//
// Two halves, tested separately, because they fail differently. The STORE is
// the half that touches the disk and reads names out of page content, so its
// tests are about a copy that either completes or leaves nothing, and about
// refusing a reference that tries to name a file outside the notebook. The
// BLOCK is the half that decides whether to spin up a decoder, so its tests
// are about never doing so until asked.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart' show Video;

import 'package:openote/editor/file_block_view.dart';
import 'package:openote/editor/video_block_view.dart';
import 'package:openote/media/video_playback.dart' show VideoPlayback, VideoUnavailable;
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/media_store.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  late Directory tmp;
  late NotebookRef ref;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('onote_media_');
    ref = NotebookRef(
        id: 'n1', file: '${tmp.path}/Lectures.onote', title: 'Lectures');
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// A file of [bytes] bytes, big enough to arrive in more than one chunk so
  /// the streaming path is actually exercised.
  File source(String name, int bytes) {
    final f = File('${tmp.path}/$name')..createSync(recursive: true);
    f.writeAsBytesSync(Uint8List(bytes));
    return f;
  }

  group('the store', () {
    test('a copy lands beside the notebook, not inside it', () async {
      // The whole reason this store exists: a lecture in the `blobs` table
      // would be one enormous SQLite row that has to be decoded whole before a
      // frame plays. Here it is a file, and a file is a path a player can open.
      final name = await MediaStore.add(ref, source('lecture.mp4', 4096));
      final stored = MediaStore.resolve(ref, name)!;
      expect(stored.existsSync(), isTrue);
      expect(stored.lengthSync(), 4096);
      expect(stored.path, contains('Lectures.onotebook'));
      expect(stored.path, endsWith('.mp4'),
          reason: 'the extension is what makes "open externally" land right');
    });

    test('progress is reported on the way', () async {
      final seen = <double>[];
      await MediaStore.add(ref, source('big.mp4', 1 << 20),
          onProgress: seen.add);
      expect(seen, isNotEmpty, reason: 'a gigabyte must not look like a hang');
      expect(seen.last, closeTo(1.0, 0.001));
      expect(seen, everyElement(predicate<double>((v) => v >= 0 && v <= 1)));
    });

    test('two copies of the same file do not collide', () async {
      final a = await MediaStore.add(ref, source('a.mp4', 512));
      final b = await MediaStore.add(ref, source('a.mp4', 512));
      expect(a, isNot(b));
      expect(MediaStore.resolve(ref, a), isNotNull);
      expect(MediaStore.resolve(ref, b), isNotNull);
    });

    test('a cancelled copy leaves nothing behind', () async {
      // Not even a partial file: a half-written video that still looks like a
      // video is worse than no video, because it plays for ten seconds and
      // stops.
      await expectLater(
        MediaStore.add(ref, source('huge.mp4', 1 << 20),
            isCancelled: () => true),
        throwsA(isA<MediaCopyCancelled>()),
      );
      final dir = MediaStore.dirFor(ref);
      expect(dir.existsSync() ? dir.listSync() : const [], isEmpty);
    });

    group('a reference is a filename and nothing else', () {
      // The name comes out of page content, and page content comes out of a
      // file that may have been imported, synced, or handed over by someone
      // else. Without this, "media": "../../../../etc/passwd" is a read of any
      // file the user can read, and "Save a copy…" is the way to get it out.
      for (final bad in [
        '../secrets.txt',
        '..\\secrets.txt',
        '/etc/passwd',
        r'C:\Windows\System32\config\SAM',
        'sub/dir.mp4',
        '.hidden',
        '',
      ]) {
        test('refuses ${bad.isEmpty ? '(empty)' : bad}', () {
          expect(MediaStore.isValidName(bad), isFalse);
          expect(MediaStore.resolve(ref, bad), isNull);
        });
      }

      test('accepts what it writes', () async {
        final name = await MediaStore.add(ref, source('ok.mkv', 16));
        expect(MediaStore.isValidName(name), isTrue);
      });
    });

    test('a name that is valid but absent resolves to nothing', () {
      // A notebook copied without its `.onotebook`, or a sync still bringing
      // the bytes across. Not an error — a card that says so.
      expect(MediaStore.resolve(ref, 'nothing-here.mp4'), isNull);
    });

    test('totalBytes is what the storage line reports', () async {
      await MediaStore.add(ref, source('a.mp4', 1000));
      await MediaStore.add(ref, source('b.mp4', 2000));
      expect(MediaStore.totalBytes(ref), 3000);
    });

    test('an odd extension is dropped rather than carried', () async {
      // The extension ends up in a filename we later hand to the OS.
      final name = await MediaStore.add(ref, source('clip.this is not an ext', 8));
      expect(MediaStore.isValidName(name), isTrue);
    });
  });

  group('the block', () {
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());
    // Every test in here runs as a machine WITHOUT libmpv unless it says
    // otherwise: that is the state a widget test is really in, and it is also
    // the state of a Linux box that never installed mpv-libs.
    //
    // The reason is now stated rather than inferred. Since the video engine
    // was split out of the Windows download (media/video_engine.dart) there
    // are two ways to have no player — a distribution package that was never
    // installed, and a one-off download that has not happened — and they get
    // different cards. These tests are the first one.
    setUp(() => VideoPlayback.debugSetAvailable(false,
        reason: VideoUnavailable.missingSystemLibrary));

    Future<AppState> newApp(WidgetTester t) async {
      late AppState app;
      final dir = Directory.systemTemp.createTempSync('onote_vblock_');
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
      });
      return app;
    }

    /// Real file I/O inside `testWidgets` needs `runAsync`: the test binding
    /// runs a fake clock, so an un-wrapped `await` on a disk read simply never
    /// completes and the test hangs rather than fails.
    Future<String> store(WidgetTester t, AppState app, File src) async =>
        (await t.runAsync(() => MediaStore.add(app.currentNotebook, src)))!;

    Future<void> show(WidgetTester t, AppState app, Block b) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
              width: 420, height: 240, child: FileBlockView(block: b, app: app)),
        ),
      ));
      await t.pump();
    }

    Block videoBlock(String media, {String name = 'Lecture 3.mp4', int size = 0}) =>
        Block(type: BlockType.file, x: 0, y: 0, content: {
          'kind': 'video',
          'media': media,
          'name': name,
          'mime': 'video/mp4',
          'size': size,
        });

    testWidgets('a media block renders the player card, not the file card',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = await newApp(t);
      await show(t, app, videoBlock('missing.mp4'));
      expect(find.byType(VideoBlockView), findsOneWidget);
      expect(find.text('Lecture 3.mp4'), findsOneWidget);
    });

    testWidgets('nothing plays until Play is pressed', (t) async {
      // The resource claim: a page with six recordings must not open six mpv
      // instances by being looked at. Asserted as "no Video widget exists",
      // which is the same thing said in a way a test can check without libmpv.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      VideoPlayback.debugSetAvailable(true);
      final app = await newApp(t);
      final stored = await store(t, app, source('l.mp4', 64));
      await show(t, app, videoBlock(stored));
      expect(find.byIcon(Icons.play_circle_fill), findsOneWidget,
          reason: 'the offer is there');
      expect(find.byType(Video), findsNothing, reason: 'the decoder is not');
    });

    testWidgets('a file that is not here says so instead of offering Play',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      VideoPlayback.debugSetAvailable(true);
      final app = await newApp(t);
      await show(t, app, videoBlock('gone.mp4'));
      expect(find.byIcon(Icons.play_circle_fill), findsNothing);
      expect(find.textContaining('not in this copy'), findsOneWidget);
    });

    testWidgets('without libmpv it explains rather than offering a dead button',
        (t) async {
      // A Linux box that never installed mpv-libs. The honest answer is which
      // package to install, and the file is still openable in a real player.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = await newApp(t);
      final stored = await store(t, app, source('l.mp4', 64));
      await show(t, app, videoBlock(stored, size: 64));
      expect(find.byIcon(Icons.play_circle_fill), findsNothing);
      expect(find.byIcon(Icons.help_outline), findsOneWidget);
      expect(find.textContaining('your usual player'), findsOneWidget);

      await t.tap(find.byIcon(Icons.help_outline));
      await t.pumpAndSettle();
      expect(find.textContaining('mpv-libs'), findsOneWidget,
          reason: 'Fedora, which is the machine this was reported from');
      expect(find.textContaining('libmpv2'), findsOneWidget,
          reason: 'and Debian/Ubuntu, which is the other half of the .deb');
    });

    testWidgets('a link card is still a link card', (t) async {
      // The two shapes share BlockType.file, so this pins that adding one did
      // not swallow the other.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = await newApp(t);
      await show(
          t,
          app,
          Block(type: BlockType.file, x: 0, y: 0, content: {
            'url': 'https://example.edu/lecture',
            'name': 'Lecture 4',
            'kind': 'video',
          }));
      expect(find.byType(VideoBlockView), findsNothing);
      expect(find.text('Lecture 4'), findsOneWidget);
    });
  });

  group('the storage the user was told to expect', () {
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());

    test('video is counted separately from the sync log it sits in', () async {
      // "even if it will chew through storage" — it does, and the dialog has
      // to say so in those words rather than folding four gigabytes of
      // lectures into a line labelled "sync log".
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final dir = Directory.systemTemp.createTempSync('onote_storage_');
      final repo = await Repository.openAt(dir);
      addTearDown(() {
        repo.dispose();
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      });
      final nb = await repo.createNotebook('Lectures');
      final app = AppState(repo)..notebookId = nb.id;
      addTearDown(app.cancelPendingSave);

      expect((await app.storageFor(nb.id)).mediaBytes, 0);
      await MediaStore.add(app.currentNotebook, source('l.mp4', 5000));
      final after = await app.storageFor(nb.id);
      expect(after.mediaBytes, 5000);
      expect(after.logBytes, greaterThanOrEqualTo(after.mediaBytes),
          reason: 'the video lives inside the log directory it is broken out of');
    });
  });

  group('a video travels with its notebook', () {
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());

    test('duplicating a notebook copies its recordings too', () async {
      // The container is a SQLite file and the video is not in it, so copying
      // the container alone gives a duplicate whose lectures have quietly
      // gone. Moving a notebook already carried the whole `.onotebook`;
      // duplicating had no reason to think about it until now.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final dir = Directory.systemTemp.createTempSync('onote_dup_');
      final repo = await Repository.openAt(dir);
      addTearDown(() {
        repo.dispose();
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      });
      final nb = await repo.createNotebook('Lectures');
      final ref = repo.notebooks.firstWhere((n) => n.id == nb.id);
      final stored = await MediaStore.add(ref, source('l.mp4', 1234));

      final copy = await repo.duplicateNotebook(nb.id);
      final carried = MediaStore.resolve(copy, stored);
      expect(carried, isNotNull, reason: 'the copy kept the recording');
      expect(carried!.lengthSync(), 1234);
      expect(carried.path, isNot(MediaStore.resolve(ref, stored)!.path),
          reason: 'and it is its own file, not a link back to the original');
    });
  });

  group('the sizes people will actually see', () {
    test('a lecture reads as gigabytes, not as a ten-digit number', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(2048), '2.0 KB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
      expect(formatBytes(3 * 1024 * 1024 * 1024), '3.00 GB');
    });
  });
}
