// Media-link cards (MEDIA-7): a lecture recording embedded in the page as a
// link, so it can be reached from the notes instead of hunted for in a
// browser.
//
// The interesting part is what it is NOT: not a new BlockType, and not a copy
// of the video. It rides `BlockType.file`, which every shipped build already
// renders, so a card written today degrades in an older build to an inert but
// correctly-labelled attachment rather than "Unsupported block".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:io';

import 'package:openote/core/platform_open.dart';
import 'package:openote/editor/file_block_view.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/model/models.dart';

import 'support/sqlite.dart';

void main() {
  Block link(String url, {String? name, String kind = 'video'}) => Block(
        type: BlockType.file,
        x: 0,
        y: 0,
        content: {'url': url, if (name != null) 'name': name, 'kind': kind},
      );

  group('a media link is an ordinary file block', () {
    test('it carries no blob, so nothing is copied into the notebook', () {
      // A lecture recording is hundreds of megabytes, and blobs live in the
      // container AND in .onotebook/blobs/ once a notebook is shared. A URL is
      // a few dozen bytes and resolves on every device.
      final b = link('https://example.edu/lecture-7', name: 'Lecture 7');
      expect(b.content.containsKey('blob'), isFalse);
      expect(b.type, BlockType.file);
    });

    test('it round-trips, so an old build hands it back intact', () {
      // The degradation contract. An older build reads type "file", renders
      // FileBlockView, finds content['blob'] null and disables both buttons —
      // an inert card with the right label. `url` and `kind` ride along in
      // content untouched, so a current build restores the feature.
      final src = link('https://example.edu/lecture-7', name: 'Lecture 7');
      final back = Block.fromJson(src.toJson());
      expect(back.type, BlockType.file);
      expect(back.content['url'], 'https://example.edu/lecture-7');
      expect(back.content['name'], 'Lecture 7');
      expect(back.content['kind'], 'video');
    });
  });

  group('only links we will actually open are accepted', () {
    test('http and https are openable', () {
      expect(PlatformOpen.isOpenableUrl('https://youtu.be/abc'), isTrue);
      expect(PlatformOpen.isOpenableUrl('http://example.edu/x'), isTrue);
    });

    test('file: is refused, so a note cannot launch a local program', () {
      // The allow-list is the whole reason a link in note content is safe: a
      // notebook can arrive from an import or a shared folder, so its links
      // are not necessarily ones this user chose.
      expect(PlatformOpen.isOpenableUrl('file:///C:/Windows/system32/cmd.exe'),
          isFalse);
      expect(PlatformOpen.isOpenableUrl('javascript:alert(1)'), isFalse);
      expect(PlatformOpen.isOpenableUrl('not a url at all'), isFalse);
    });
  });

  group('the card renders through the real dispatch', () {
    // A repo-backed AppState, built in setUp because `testWidgets` runs in a
    // fake-async zone where Repository.openAt's real file I/O never completes.
    late Repository repo;
    late Directory tmp;
    late AppState app;
    var haveSqlite = false;

    setUpAll(() => haveSqlite = initSqliteForTests());

    setUp(() async {
      if (!haveSqlite) return;
      tmp = Directory.systemTemp.createTempSync('onote_medialink_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Links');
      app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
    });

    tearDown(() {
      if (!haveSqlite) return;
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<void> show(WidgetTester t, Block b) => t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
          home: Scaffold(body: FileBlockView(block: b, app: app)),
        ));

    testWidgets('a url block becomes a link card, not an attachment row',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await show(t, link('https://example.edu/lecture-7', name: 'Lecture 7'));
      await t.pump();

      expect(find.text('Lecture 7'), findsOneWidget);
      expect(find.text('example.edu'), findsOneWidget,
          reason: 'the host tells you where the link goes before you click');
      expect(find.byIcon(Icons.play_circle_outline), findsOneWidget,
          reason: "kind 'video' picks the play glyph");
      // The attachment affordances belong to the blob path and must not show.
      expect(find.byIcon(Icons.download_outlined), findsNothing);
    });

    testWidgets('a link we cannot open says so instead of pretending',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // A card that looks clickable and silently does nothing is worse than
      // one that plainly is not.
      await show(t, link('file:///C:/Windows/system32/cmd.exe', name: 'Nope'));
      await t.pump();

      expect(find.text('Not a link this can open'), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new), findsNothing);
    });
  });
}
