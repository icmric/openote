// Copied-in videos surviving a Markdown export.
//
// "Exporting a notebook to Markdown does not carry copied-in videos yet"
// (0.4.2 known gaps). It was worse than "not carried": `BlockType.file` fell
// through the exporter's `default:` arm, so a page of lectures exported as a
// page with no lectures and NO SIGN there had ever been any — the one failure
// mode an export must not have, because the person reading the `.md` has no
// way to know something is missing.
//
// The other half of these tests is the export folder as a person meets it: the
// file in `assets/` is called what the user called it, and the link in the
// `.md` actually resolves when clicked in a Markdown reader that is not this
// app.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openote/export/markdown_export.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/media_store.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;
  late NotebookRef ref;

  setUp(() async {
    if (!haveSqlite) return;
    tmp = Directory.systemTemp.createTempSync('onote_mdvideo_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Lectures');
    ref = repo.notebooks.firstWhere((n) => n.id == nb.id);
    app = AppState(repo)..notebookId = nb.id;
  });

  tearDown(() {
    if (!haveSqlite) return;
    app.cancelPendingSave();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// A stored video of [bytes] bytes, every byte [byteValue].
  Future<String> store(String filename, int byteValue, {int bytes = 4096}) async {
    final src = File(p.join(tmp.path, filename))
      ..writeAsBytesSync(Uint8List(bytes)..fillRange(0, bytes, byteValue));
    final name = await MediaStore.add(ref, src);
    src.deleteSync();
    return name;
  }

  Block videoBlock(String media, {String name = 'Lecture 3.mp4'}) =>
      Block(type: BlockType.file, x: 0, y: 0, content: {
        'kind': 'video',
        'media': media,
        'name': name,
        'mime': 'video/mp4',
        'size': 4096,
      });

  group('the projection', () {
    test('a copied-in video is no longer silently dropped', () async {
      // The regression. Before the fix this produced a heading and nothing
      // else — the assertion that matters is that the stored video is NAMED at
      // all in the output.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final media = <String, String>{};
      final md = pageMarkdownOf(
          app, 'Week 1', [videoBlock(await store('l.mp4', 1))],
          mediaOut: media);

      expect(md, contains('Lecture 3.mp4'),
          reason: 'the video is in the Markdown at all');
      expect(media, hasLength(1), reason: 'and its bytes are queued to copy');
    });

    test('the link uses the name the user gave the file, not the UUID',
        () async {
      // On disk a video is a UUIDv7 so two copies of the same lecture cannot
      // collide. An export folder is read by a person, and `0198f3c1-….mp4`
      // tells them nothing about which lecture it is.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final stored = await store('l.mp4', 1);
      final media = <String, String>{};
      final md = pageMarkdownOf(app, 'Week 1', [videoBlock(stored)],
          mediaOut: media);

      expect(media[stored], 'assets/Lecture 3.mp4');
      expect(md, isNot(contains(stored)), reason: 'no UUID in the writing');
      expect(md, contains('[Lecture 3.mp4](assets/Lecture%203.mp4)'));
    });

    test('a space in the filename does not break the link', () async {
      // `[x](assets/Lecture 3.mp4)` is not a link — the space ends the
      // destination — so the one thing the reader wants to click does nothing.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final md = pageMarkdownOf(
          app, 'Week 1', [videoBlock(await store('l.mp4', 1))],
          mediaOut: {});
      expect(md, contains('%20'));
      expect(md, isNot(contains('(assets/Lecture 3.mp4)')));
    });

    test('the stored extension wins over whatever the display name claims',
        () async {
      // The display name is arbitrary text from a picker; the stored extension
      // is the one `MediaStore.add` already vetted.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final stored = await store('l.mkv', 1);
      final media = <String, String>{};
      pageMarkdownOf(app, 'W',
          [videoBlock(stored, name: 'Lecture without an extension')],
          mediaOut: media);
      expect(media[stored], 'assets/Lecture without an extension.mkv');
    });

    test('two lectures a student called the same thing stay two files',
        () async {
      // Both blocks say "lecture.mp4". One output file would silently be the
      // second recording under the first one's link.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final a = await store('a.mp4', 0xAA);
      final b = await store('b.mp4', 0xBB);
      final media = <String, String>{};
      pageMarkdownOf(
          app,
          'W',
          [
            videoBlock(a, name: 'lecture.mp4'),
            videoBlock(b, name: 'lecture.mp4')..y = 10,
          ],
          mediaOut: media);
      expect(media.values.toSet(), hasLength(2));
      expect(media[a], 'assets/lecture.mp4');
      expect(media[b], 'assets/lecture (2).mp4');
    });

    test('a media name that tries to leave the folder is refused', () async {
      // The name comes out of page content, which may have been imported or
      // handed over by someone else. Without the guard, exporting is a copy of
      // any file the user can read into a folder they are about to share.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final media = <String, String>{};
      final md = pageMarkdownOf(
          app,
          'W',
          [
            videoBlock('../../../../etc/passwd', name: 'harmless.mp4'),
            videoBlock(r'..\..\Windows\System32\config\SAM', name: 'x.mp4'),
          ],
          mediaOut: media);
      expect(media, isEmpty);
      expect(md, isNot(contains('passwd')));
      expect(md, isNot(contains('SAM')));
    });

    test('a video that is only a link is still a link', () async {
      // A Panopto or YouTube page never had bytes here. It projects as the
      // plain link it always was, not as a missing file.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final media = <String, String>{};
      final md = pageMarkdownOf(
          app,
          'W',
          [
            Block(type: BlockType.file, x: 0, y: 0, content: {
              'kind': 'video',
              'url': 'https://example.edu/lecture',
              'name': 'Lecture 4',
            })
          ],
          mediaOut: media);
      expect(md, contains('[Lecture 4](https://example.edu/lecture)'));
      expect(media, isEmpty, reason: 'there are no bytes to copy');
    });

    test('the API projection does not need a filesystem', () async {
      // `pageMarkdownOf` is shared with the MCP `read_page` tool, which has no
      // output directory at all. It must still project rather than throw.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final md =
          pageMarkdownOf(app, 'W', [videoBlock(await store('l.mp4', 1))]);
      expect(md, contains('Lecture 3.mp4'));
    });
  });

  group('the folder someone opens afterwards', () {
    test('the video in assets/ is the video, byte for byte', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final stored = await store('l.mp4', 0x7E, bytes: 8192);
      final media = <String, String>{};
      final outPath = p.join(tmp.path, 'out', 'Week 1.md');
      Directory(p.dirname(outPath)).createSync(recursive: true);
      final md = pageMarkdownOf(app, 'Week 1', [videoBlock(stored)],
          mediaOut: media);
      await File(outPath).writeAsString(md);
      await writeExportedMedia(app, outPath, media);

      final written = File(p.join(p.dirname(outPath), 'assets', 'Lecture 3.mp4'));
      expect(written.existsSync(), isTrue,
          reason: 'the link in the .md resolves to a real file');
      final bytes = written.readAsBytesSync();
      expect(bytes.length, 8192);
      expect(bytes.every((b) => b == 0x7E), isTrue);
    });

    test('a video whose bytes never arrived still exports the writing',
        () async {
      // A notebook synced without its `media/` yet. A broken link beside the
      // notes is recoverable; losing the notes is not.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final outPath = p.join(tmp.path, 'out2', 'Week 2.md');
      Directory(p.dirname(outPath)).createSync(recursive: true);
      final media = <String, String>{};
      final md = pageMarkdownOf(
          app,
          'Week 2',
          [
            Block(type: BlockType.text, x: 0, y: 0, content: {'text': 'Notes'}),
            videoBlock('gone-from-this-copy.mp4'),
          ],
          mediaOut: media);
      await File(outPath).writeAsString(md);
      await writeExportedMedia(app, outPath, media);

      expect(File(outPath).readAsStringSync(), contains('Notes'));
      expect(
          File(p.join(p.dirname(outPath), 'assets', 'Lecture 3.mp4'))
              .existsSync(),
          isFalse);
    });
  });
}
