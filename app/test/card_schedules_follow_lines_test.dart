// A flashcard's review history stays with the card when the lines move.
//
// v1.0.2 bug 16. A card's schedule is filed under `blockId:line`, and only
// TAGGED lines were carried across when lines moved — the remap was fed the
// tags' moves, and a card written in the prose (`?[…](…)`) has no tag.
// Measured before the fix: one line typed above two cards moved osmosis from
// B:0 to B:1, which was diffusion's id, with a remap of `{}` — so osmosis took
// diffusion's schedule, diffusion started over, and osmosis's own history was
// left for the next prune to delete.
//
// Three more ways to the same swap turned up on the way, and are pinned here:
// a card never reviewed moving onto a deleted card's id inherited its history;
// Ctrl+Z put the text back while leaving the schedules where the edit had put
// them; and a picture dropped into a box moved its tags but not its cards —
// and rebuilt each tag without its deadline.
//
// The v1.0.3 card rebuild gives every card a permanent id and ends this for
// good. Until then, these are the schedules that rebuild will convert.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/api/mcp_tools.dart' show callMcpTool;
import 'package:openote/canvas/media_drop.dart' show insertImageIntoTextAt;
import 'package:openote/editor/text_block_view.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/model/tags.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/study/flashcards.dart';
import 'package:openote/theme/onote_theme.dart';

import 'support/sqlite.dart';

const _osmosis = '?[osmosis](water crossing a membrane)';
const _diffusion = '?[diffusion](particles spreading out)';
const _twoCards = '$_osmosis\n$_diffusion';

/// A real 1x1 PNG, so a drop stores real bytes.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;
  late String boxId;

  /// The box as it is NOW — undo replaces block objects wholesale.
  Block box() => app.blocks.firstWhere((b) => b.type == BlockType.text);

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_card_lines_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Study');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
    app.importPage(
        nb.id,
        page.id,
        [
          Block(
              type: BlockType.text,
              x: 40,
              y: 120,
              w: 520,
              content: {'text': _twoCards}),
        ],
        PageProps());
    app.reloadNodes();
    await app.selectPage(page.id);
    boxId = box().id;
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

  String id(int line) => '$boxId:$line';

  /// Whose schedule is filed under [line], told apart by what was done to
  /// each: osmosis is reviewed three times, diffusion failed once, and a card
  /// never reviewed has nothing filed at all.
  String history(int line) {
    final s = app.study.cardState(id(line));
    if (s.dueAt == 0) return 'never reviewed';
    if (s.repetitions == 3 && s.lapses == 0) return 'osmosis';
    if (s.lapses == 1) return 'diffusion';
    return 'someone else';
  }

  void review({bool diffusionToo = true}) {
    for (var i = 0; i < 3; i++) {
      app.study.gradeCard(id(0), Grade.good);
    }
    if (diffusionToo) app.study.gradeCard(id(1), Grade.again);
    expect(history(0), 'osmosis', reason: 'precondition');
    expect(history(1), diffusionToo ? 'diffusion' : 'never reviewed',
        reason: 'precondition');
  }

  List<String> cardLines() => [
        for (final c in cardsFromBlock(box(), 'pg', 'Page'))
          '${c.line}:${c.front}'
      ];

  group('where every line went', () {
    test('a line typed above moves every line below it', () {
      expect(NoteTag.lineMoves(_twoCards, 'Week 3\n$_twoCards'), {0: 1, 1: 2});
    });

    test('a line deleted pulls the ones below it up, and is not listed', () {
      expect(NoteTag.lineMoves(_twoCards, _diffusion), {1: 0});
    });

    test('an edit inside a line moves nothing', () {
      expect(NoteTag.lineMoves(_twoCards, '$_osmosis!\n$_diffusion'), isEmpty);
    });

    test('lines the edit rewrote are not listed — only what came through', () {
      expect(NoteTag.lineMoves('A\nB\nC\nD', 'A\nW\nX\nY\nZ\nD'), {3: 5});
    });

    test('the cause: asked of the TAGS, an untagged box reports no moves', () {
      // What the remap was fed. A `?[…](…)` card is not a tag, so a box full
      // of them reported that nothing moved, every time.
      final content = <String, dynamic>{'text': _twoCards};
      expect(NoteTag.rebase(content, _twoCards, 'Week 3\n$_twoCards'), isEmpty);
    });
  });

  group('the schedules', () {
    void edit(String after) {
      final b = box();
      final before = b.content['text'] as String;
      app.study.remapCardStates(b.id, NoteTag.lineMoves(before, after));
      b.content['text'] = after;
    }

    test('one line typed above two cards: each keeps its own history', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      review();
      edit('Week 3\n$_twoCards');
      expect(cardLines(), ['1:osmosis', '2:diffusion']);
      expect([history(1), history(2)], ['osmosis', 'diffusion']);
      expect(history(0), 'never reviewed',
          reason: 'the new line is not a card and has no history');
    });

    test("a card never reviewed does not inherit a deleted card's history",
        () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // Osmosis reviewed, diffusion never; osmosis's line is deleted, and
      // diffusion slides up onto its id. Overwriting a destination only when
      // the arriving card HAD a schedule left osmosis's history right where
      // diffusion now is.
      review(diffusionToo: false);
      edit(_diffusion);
      expect(cardLines(), ['0:diffusion']);
      expect(history(0), 'never reviewed',
          reason: 'diffusion was never reviewed, and must not look as if it '
              'had been');
    });
  });

  test("an AI helper's edit moves them as a typed one does", () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // Spec 14 section 4.6: an AI helper's write is an edit like any other.
    review();
    await callMcpTool(app, 'update_block', {
      'pageId': app.pageId,
      'blockId': boxId,
      'content': {'text': 'Week 3\n$_twoCards'},
    });
    expect([history(1), history(2)], ['osmosis', 'diffusion']);
    expect(history(0), 'never reviewed');
  });

  group('through the real editor', () {
    Future<void> pump(WidgetTester t) async {
      app.editingBlockId = boxId;
      await t.pumpWidget(MaterialApp(
        localizationsDelegates: kOnoteLocalizations,
        supportedLocales: kOnoteLocales,
        theme: onoteTheme(Brightness.light),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 520,
              child: ListenableBuilder(
                listenable: app,
                builder: (_, __) => TextBlockView(block: box(), app: app),
              ),
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
      await t.tap(find.byType(TextField).first);
      await t.pumpAndSettle();
      app.cancelPendingSave();
    }

    /// Type as the keyboard does: the platform hands the field a new value,
    /// and the field's own onChanged runs — the path every keystroke takes.
    Future<void> type(WidgetTester t, String text, int caret) async {
      t.testTextInput.updateEditingValue(TextEditingValue(
          text: text, selection: TextSelection.collapsed(offset: caret)));
      await t.pumpAndSettle();
      app.cancelPendingSave();
    }

    testWidgets('Enter at the top of the box carries both histories down',
        (t) async {
      if (!haveSqlite) return;
      review();
      await pump(t);
      await type(t, '\n$_twoCards', 0);
      expect(box().content['text'], '\n$_twoCards');
      expect([history(1), history(2)], ['osmosis', 'diffusion']);
      app.cancelPendingSave();
    });

    testWidgets('Ctrl+Z carries them back, and Ctrl+Y down again', (t) async {
      if (!haveSqlite) return;
      review();
      await pump(t);
      await type(t, '\n$_twoCards', 0);
      expect([history(1), history(2)], ['osmosis', 'diffusion'],
          reason: 'precondition');

      app.undo();
      await t.pumpAndSettle();
      app.cancelPendingSave();
      expect(box().content['text'], _twoCards);
      expect([history(0), history(1)], ['osmosis', 'diffusion'],
          reason: 'undo put the text back; the histories must follow it');

      app.redo();
      await t.pumpAndSettle();
      app.cancelPendingSave();
      expect(box().content['text'], '\n$_twoCards');
      expect([history(1), history(2)], ['osmosis', 'diffusion']);
    });
  });

  test("a picture dropped into a box moves the schedules below it, and keeps "
      "a task's deadline", () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // The drop had its own copy of the tag rebase. It moved the tags and not
    // the cards' schedules, and it rebuilt each tag without its `due` — so a
    // picture dropped above a dated task cleared the date.
    final b = box();
    b.content['text'] = '$_osmosis\nFinish the essay';
    NoteTag.writeInto(
        b.content, [NoteTag(kind: TagKind.todo, line: 1, due: '2026-11-03')]);
    review(diffusionToo: false);

    // At the very top of the box, so the picture lands above both lines.
    final made = insertImageIntoTextAt(
        app, _png, 'image/png', Offset(b.x + 4, b.y + 2),
        dark: false);
    expect(made?.id, b.id, reason: 'precondition: it went into the box');
    final lines = (b.content['text'] as String).split('\n');
    expect(lines.first, startsWith('![](sha256:'));
    expect(lines.indexOf(_osmosis), 1);

    expect(history(1), 'osmosis',
        reason: 'osmosis keeps its history on the line it moved to');
    expect(history(0), 'never reviewed', reason: 'the picture is not a card');
    final task = NoteTag.listFrom(b.content).single;
    expect(task.line, 2);
    expect(task.due, '2026-11-03', reason: 'the deadline survives the drop');
  });
}
