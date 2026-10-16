// Annotating an imported PDF, from issue #20.
//
// A slide is a locked block that covers the page, so every gesture over the
// page is a gesture over a block — and the canvas only ever handled the ones
// that landed on nothing. That made panning, box-selecting and moving all
// behave differently on a slide than on an empty page, which is where the
// report starts: *"it's almost impossible to work with imported PDFs or
// images"*.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  group('what a marquee takes in', () {
    test('a block it covers', () {
      expect(
          marqueeCatches(const Rect.fromLTWH(0, 0, 100, 100),
              const Rect.fromLTWH(10, 10, 20, 20)),
          isTrue);
    });

    test('not a block it only brushes', () {
      expect(
          marqueeCatches(const Rect.fromLTWH(0, 0, 100, 100),
              const Rect.fromLTWH(95, 95, 200, 200)),
          isFalse,
          reason: 'a corner overlap is not a selection');
    });

    test('half is enough — nobody drags a box precisely', () {
      expect(
          marqueeCatches(const Rect.fromLTWH(0, 0, 100, 100),
              const Rect.fromLTWH(50, 0, 100, 100)),
          isTrue);
    });

    test('a block with no area falls back to a touch', () {
      expect(
          marqueeCatches(const Rect.fromLTWH(0, 0, 100, 100),
              const Rect.fromLTWH(10, 10, 0, 0)),
          isTrue,
          reason: 'there is no proportion of nothing to take half of');
    });

    test('a marquee drawn inside a big picture does not select the picture', () {
      expect(
          marqueeCatches(const Rect.fromLTWH(400, 400, 60, 60),
              const Rect.fromLTWH(0, 0, 1000, 1400)),
          isFalse);
    });
  });

  group('on a page with a slide on it', () {
    late Repository repo;
    late Directory tmp;
    late AppState app;
    late Block slide;

    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_slide_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Slides');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      await app
          .selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
      // What `pdf_import.dart` writes: a locked picture covering the page.
      //
      // With a height, which the importer leaves to the picture's own
      // proportions — there is no picture to have any here, so the height is
      // what makes the block occupy the rectangle a real slide occupies.
      // `app.addBlock` places what it is given, so the position is set after.
      slide = app.addBlock(Block(
        type: BlockType.image,
        x: 0,
        y: 0,
        w: 800,
        h: 1000,
        content: {
          'locked': true,
          'naturalW': 800,
          'naturalH': 1000,
          'hash': 'sha256:slide',
        },
      ))
        ..x = 0
        ..y = 0;
      app.select(null);
    });

    tearDown(() {
      AppState.syncLogEnabled = true;
      if (!haveSqlite) return;
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<void> pump(WidgetTester t) async {
      await t.pumpWidget(MaterialApp(
        localizationsDelegates: kOnoteLocalizations,
        supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: SizedBox(width: 800, height: 600, child: PageCanvas(state: app)),
        ),
      ));
      await t.pump();
      await t.pump();
    }

    /// A note written on the slide, as an ink block over the top of it.
    Block noteAt(double x, double y) => app.addBlock(Block(
          type: BlockType.ink,
          x: x,
          y: y,
          w: 60,
          h: 20,
          content: {
            'strokes': [
              Stroke(
                tool: 'pen',
                colorHex: '#211F1B',
                size: 2,
                x: [x, x + 60],
                y: [y, y + 20],
              ).toJson()
            ]
          },
        ));

    testWidgets('A MIDDLE-DRAG OVER THE SLIDE PANS', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pump(t);
      final before = app.canvas.offset;

      final g = await t.startGesture(const Offset(400, 300),
          kind: PointerDeviceKind.mouse, buttons: kMiddleMouseButton);
      await g.moveBy(const Offset(-80, -40));
      await t.pump();
      await g.up();
      await t.pump();

      expect(app.canvas.offset, isNot(before));
      expect(app.selectedIds, isEmpty, reason: 'and it selected nothing');
      app.cancelPendingSave();
    });

    testWidgets('A DRAG OVER THE SLIDE BOX-SELECTS THE NOTES ON IT', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final note = noteAt(200, 200);
      await pump(t);

      final tl = app.canvas.pageToScreen(const Offset(180, 180));
      final br = app.canvas.pageToScreen(const Offset(300, 260));
      final g = await t.startGesture(tl, kind: PointerDeviceKind.mouse);
      await g.moveTo(br);
      await t.pump();
      await g.up();
      await t.pump();

      expect(app.selectedIds, contains(note.id));
      expect(app.selectedIds, isNot(contains(slide.id)),
          reason: 'the slide is what the note is drawn on, not one of the '
              'things being picked up');
      app.cancelPendingSave();
    });

    testWidgets('a click on the slide selects the slide and nothing else',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final before = app.blocks.length;
      await pump(t);

      await t.tapAt(const Offset(400, 300));
      await t.pump();

      expect(app.blocks, hasLength(before),
          reason: 'no text box was created over it');
      app.cancelPendingSave();
    });

    test('A LOCKED SLIDE DOES NOT STOP THE REST, AND DOES NOT COME ALONG', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final note = noteAt(100, 100);
      note
        ..x = 100
        ..y = 100;
      app.selectMany([slide.id, note.id]);

      app.moveSelectedBy(30, 40);

      expect([note.x, note.y], [130.0, 140.0], reason: 'the note moved');
      expect([slide.x, slide.y], [0.0, 0.0], reason: 'the slide stayed put');
      app.cancelPendingSave();
    });

    test('ink whose blob never arrived moves without taking the drag down', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The working list is missing entirely, which is what a block in the
      // reference form looks like before anything has decoded it. The cast
      // that used to be here threw out of the middle of the loop, so the
      // blocks already reached had moved, the rest had not, and nothing
      // repainted — "objects suddenly jump to different positions".
      final ink = app.addBlock(Block(
          type: BlockType.ink,
          x: 10,
          y: 10,
          w: 50,
          content: {
            'ink': {'v': 1, 'base': 'sha256:gone', 'n': 3, 'o': [0, 0]}
          }))
        ..x = 10
        ..y = 10;
      final after = app.addBlock(Block(
          type: BlockType.text, x: 200, y: 200, w: 100, content: {'text': 'b'}))
        ..x = 200
        ..y = 200;
      app.selectMany([ink.id, after.id]);

      app.moveSelectedBy(5, 5);

      expect([ink.x, ink.y], [15.0, 15.0]);
      expect([after.x, after.y], [205.0, 205.0],
          reason: 'the block after it in the list moved too');
      app.cancelPendingSave();
    });
  });
}
