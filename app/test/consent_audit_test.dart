// The app does not move you, or your work, without being asked (v0.23 audit).
//
// The owner's third principle, verbatim: *"dont change things or move the user
// without their concent and command."* Each group here is one place the app
// was doing exactly that.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/model/tags.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_consent_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('T');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
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

  group('tagging a line does not rebuild the page', () {
    test('so the caret is not thrown to the end of the paragraph', () {
      if (!haveSqlite) return;
      final b = app.addBlock(Block(
          type: BlockType.text,
          x: 20,
          y: 200,
          w: 300,
          content: {'text': 'buy milk\nand bread'}));
      app.select(b.id, edit: true);
      final revision = app.docRevision;

      app.toggleTagOnSelection(TagKind.todo);

      expect(NoteTag.listFrom(b.content), isNotEmpty,
          reason: 'the tag was written');
      expect(app.docRevision, revision,
          reason: 'every block widget is keyed by docRevision, so bumping it '
              'throws the text box away and rebuilds it with a fresh '
              'controller — which puts the caret at the very end');
      app.cancelPendingSave();
    });
  });

  group('opening a page does not rearrange it', () {
    test('a pen mark near the top does not drag the whole page down', () {
      if (!haveSqlite) return;
      final text = app.addBlock(Block(
          type: BlockType.text,
          x: 20,
          y: 200,
          w: 300,
          content: {'text': 'notes'}));
      // Ink at the very top of the page, which nothing stops a student doing.
      app.addBlock(Block(
        type: BlockType.ink,
        x: 0,
        y: 4,
        w: 400,
        content: {
          'strokes': [
            {'x': <double>[10, 20], 'y': <double>[8, 12]}
          ]
        },
      ));
      final wasY = text.y;

      expect(app.repairTitleBandOverlap(), 0,
          reason: 'a stroke near the top of a page is drawing, not damage — '
              'and its box is DERIVED from the strokes, so it must never be '
              'what moves everything else');
      expect(text.y, wasY);
      app.cancelPendingSave();
    });

    test('but a block genuinely under the title band is still pushed out', () {
      if (!haveSqlite) return;
      final b = app.addBlock(Block(
          type: BlockType.text, x: 20, y: 300, w: 300, content: {'text': 'a'}));
      // addBlock clamps, so put it under the band by hand the way an import
      // would have.
      b.y = 4;
      expect(app.repairTitleBandOverlap(), greaterThan(0));
      expect(b.y, greaterThanOrEqualTo(AppState.contentTop));
      app.cancelPendingSave();
    });

    test('and when ink IS moved, the strokes move with it', () {
      if (!haveSqlite) return;
      final ink = app.addBlock(Block(
        type: BlockType.ink,
        x: 0,
        y: 300,
        w: 400,
        content: {
          'strokes': [
            {'x': <double>[10, 20], 'y': <double>[300, 320]}
          ]
        },
      ));
      final text = app.addBlock(Block(
          type: BlockType.text, x: 20, y: 300, w: 300, content: {'text': 'a'}));
      text.y = 4;
      app.repairTitleBandOverlap();
      final ys = ((ink.content['strokes'] as List).first as Map)['y'] as List;
      expect(ys.first, greaterThan(300),
          reason: 'a stroke is page-absolute; moving only its box walks the '
              'selection away from the drawing');
      app.cancelPendingSave();
    });
  });
}
