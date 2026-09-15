// Getting a picture back out of a note.
//
// Issue #10: *"There is the possibility that you need an image you imported
// into the note. It would be REALLY useful to have a save image button."*
// An attachment and a video have each had their own "Save a copy…" since they
// were added; a picture — the thing people put in notes most — had none, so
// importing one was a one-way door.
//
// The write itself goes through `getSaveLocation`, a native dialog no widget
// test can drive, so what is pinned here is everything around it: WHO offers
// the item, and what the file is going to be called. The second matters more
// than it looks — the extension is what decides whether the saved file opens
// when it is double-clicked.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/context_menus.dart';

class _NoopRepo implements Repository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  Block image({String mime = 'image/png'}) => Block(
      type: BlockType.image,
      x: 0,
      y: 0,
      w: 40,
      content: {'blob': 'sha256:abc', 'mime': mime});

  group('what counts as a picture', () {
    test('an image block does', () {
      final p = pictureIn(image());
      expect(p, isNotNull);
      expect(p!.slide, isFalse);
      expect(p.hash, 'sha256:abc');
    });

    test('so does a PDF slide, which has to be rendered rather than read', () {
      // A slide is a REFERENCE — its pixels exist only while something is
      // looking at them — but it is a picture to whoever is looking at the
      // page, so it must offer the same item.
      final p = pictureIn(Block(
          type: BlockType.image,
          x: 0,
          y: 0,
          w: 40,
          content: {'pdf': 'sha256:doc', 'page': 3}));
      expect(p, isNotNull);
      expect(p!.slide, isTrue);
      expect(p.hash, 'sha256:doc');
    });

    test('a paragraph does not', () {
      expect(pictureIn(Block(type: BlockType.text, x: 0, y: 0, w: 40,
          content: {'text': 'hello'})), isNull);
    });

    test('nor does an image block whose reference is missing', () {
      expect(
          pictureIn(Block(
              type: BlockType.image, x: 0, y: 0, w: 40, content: {})),
          isNull);
    });
  });

  group('what the file is called', () {
    test('the extension follows the mime, so it opens when double-clicked', () {
      expect(extForMime('image/jpeg'), 'jpg');
      expect(extForMime('image/gif'), 'gif');
      expect(extForMime('image/webp'), 'webp');
      expect(extForMime('image/bmp'), 'bmp');
      expect(extForMime('image/svg+xml'), 'svg');
    });

    test('and an unknown or absent mime falls back to png, never to nothing',
        () {
      // A file with no extension opens in nothing at all on Windows, which is
      // a worse answer than a wrong-but-plausible one.
      expect(extForMime('image/png'), 'png');
      expect(extForMime(null), 'png');
      expect(extForMime('application/octet-stream'), 'png');
    });
  });

  group('the menu', () {
    late AppState app;

    Future<void> openMenuOn(WidgetTester t, Block b) async {
      app = AppState(_NoopRepo())
        ..notebookId = 'nb'
        ..pageId = 'pg'
        ..blocks = [b];
      addTearDown(app.cancelPendingSave);
      await t.pumpWidget(MaterialApp(
        localizationsDelegates: kOnoteLocalizations,
        supportedLocales: kOnoteLocales,
        theme: onoteTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showBlockMenu(context, app, b, Offset.zero),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    }

    testWidgets('offers Save image as… on a picture', (t) async {
      await openMenuOn(t, image());
      expect(find.text('Save image as…'), findsOneWidget);
    });

    testWidgets('and does not offer it on a paragraph', (t) async {
      await openMenuOn(
          t,
          Block(
              type: BlockType.text,
              x: 0,
              y: 0,
              w: 40,
              content: {'text': 'hello'}));
      expect(find.text('Save image as…'), findsNothing,
          reason: 'there is no picture here to save');
      expect(find.text('Delete'), findsOneWidget,
          reason: 'but the menu itself is still the menu');
    });
  });
}
