// An equation in a sentence: full size, and ON the line (owner, v0.21).
//
// Two reported regressions, both MEASURED here before they were fixed — and
// the first theory about the first one was wrong, which is why the numbers
// are written down:
//
//  * "if i type some text then insert maths it will do it all as superscript".
//    The first guess was that the editing field's `Stack` swallowed the
//    baseline. A probe put every wrapper in a baseline `Row` and disproved it
//    — Stack, Column, Focus, Listener, Semantics all forward a baseline
//    perfectly. The real cause was the SELECTION RESERVE: padding inside the
//    placeholder inflated it, which grew the line box, which dropped the
//    sentence's baseline 8.3px while the equation's own ink moved only 2.9px.
//    The maths ended up 5.4px above the words at a 14px font, and only while
//    you were editing it. The reserve is block-only now.
//  * "everything has now gone to being super small … i want it to still be
//    full size even when inlined with text". Inline maths was set in TeX
//    *text* style — script-size numerators, limits beside the sign — to match
//    OneNote's own PDF export, measured at a 0.727 ratio. The owner has
//    overruled that: full size everywhere (measured 16.7px → 28.1px for a
//    fraction at 14px), and the line grows to fit.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/inline_math_editor.dart';
import 'package:openote/editor/text_block_view.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/math/math_view.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  group('the equation sits ON the sentence, editing or not', () {
    // The pin for "if i type some text then insert maths it will do it all as
    // superscript". Measured cause: the selection reserve padded the editing
    // field, which inflated the placeholder, which grew the line box — the
    // sentence's baseline dropped 8.3px while the equation's ink moved only
    // 2.9px, leaving the maths 5.4px above the words at a 14px font. The
    // caret's own rect is the yardstick: it spans the line, so if the line
    // moves, it moves.
    testWidgets('clicking in moves NOTHING — not the line, not the equation',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final tmp = Directory.systemTemp.createTempSync('onote_base_');
      late Repository repo;
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      late AppState app;
      await tester.runAsync(() async {
        repo = await Repository.openAt(tmp);
        final nb = await repo.createNotebook('B');
        app = AppState(repo)..notebookId = nb.id;
      });
      final b = Block(
        id: 'b1',
        type: BlockType.text,
        x: 0,
        y: 0,
        w: 400,
        content: {'text': r'Ay text $x^2$ Ay more', 'autoWidth': false},
      );
      app.blocks.add(b);
      app.editingBlockId = 'b1';
      await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child:
                SizedBox(width: 400, child: TextBlockView(block: b, app: app)),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      Rect lineRect() {
        final ed = tester
            .state<EditableTextState>(find.byType(EditableText).first)
            .renderEditable;
        final caret = ed.getLocalRectForCaret(const TextPosition(offset: 0));
        return ed.localToGlobal(caret.topLeft) & caret.size;
      }

      final lineBefore = lineRect();
      final mathBefore = tester.getRect(find.byType(OnoteMath).first);

      await tester.tap(find.byType(InlineMathAtom));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final lineAfter = lineRect();
      final mathAfter = tester.getRect(find.byType(OnoteMath).first);

      expect(lineAfter.top, closeTo(lineBefore.top, 0.5),
          reason: 'the sentence itself must not move when a student clicks '
              'into an equation in it');
      expect(mathAfter.top, closeTo(mathBefore.top, 0.5),
          reason: 'and neither may the equation');
      // The relationship to the text is the thing a reader actually sees.
      expect(mathAfter.bottom - lineAfter.bottom,
          closeTo(mathBefore.bottom - lineBefore.bottom, 0.5),
          reason: 'the equation sits the same distance off the line either '
              'way — it was 5.4px higher while being edited, which is what '
              'made it look like a superscript');
      app.cancelPendingSave();
    });
  });

  group('full size, inline', () {
    testWidgets('an inline equation is set at DISPLAY size, like a block',
        (tester) async {
      // A fraction in text style sets its numerator at script size (~0.727 of
      // the body, measured against OneNote's own export). The owner wants the
      // full-size setting instead, tall line and all.
      await tester.pumpWidget(const MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OnoteMath(r'\frac{1}{2}',
                  textStyle: TextStyle(fontSize: 14),
                  compact: true,
                  key: Key('inline')),
              OnoteMath(r'\frac{1}{2}',
                  textStyle: TextStyle(fontSize: 14),
                  key: Key('block')),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final inline = tester.getSize(find.byKey(const Key('inline')));
      final block = tester.getSize(find.byKey(const Key('block')));
      expect(inline.height, block.height,
          reason: 'inline maths is no longer shrunk — the same fraction is '
              'the same size wherever it sits');
      expect(inline.width, block.width);
    });

    testWidgets('and the paragraph line GROWS to hold it', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final tmp = Directory.systemTemp.createTempSync('onote_size_');
      late Repository repo;
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      late AppState app;
      await tester.runAsync(() async {
        repo = await Repository.openAt(tmp);
        final nb = await repo.createNotebook('Size');
        app = AppState(repo)..notebookId = nb.id;
      });

      Future<double> heightOf(String text) async {
        final b = Block(
          id: 'b1',
          type: BlockType.text,
          x: 0,
          y: 0,
          w: 400,
          content: {'text': text, 'autoWidth': false},
        );
        await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                  width: 400, child: TextBlockView(block: b, app: app)),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        return tester.getSize(find.byType(TextBlockView)).height;
      }

      final plain = await heightOf('the area of it');
      final withMaths = await heightOf(r'the area of $\frac{1}{2}$');
      expect(withMaths, greaterThan(plain),
          reason: 'a full-size fraction is taller than a line of text, and '
              'THAT line has to make room for it — the owner asked for the '
              'height to be accounted for rather than the maths shrunk');
      app.cancelPendingSave();
    });

    testWidgets('the equation does not jump when you click into it',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final tmp = Directory.systemTemp.createTempSync('onote_jump_');
      late Repository repo;
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      late AppState app;
      await tester.runAsync(() async {
        repo = await Repository.openAt(tmp);
        final nb = await repo.createNotebook('Jump');
        app = AppState(repo)..notebookId = nb.id;
      });
      final b = Block(
        id: 'b1',
        type: BlockType.text,
        x: 0,
        y: 0,
        w: 400,
        content: {'text': r'we know $x^2$ here', 'autoWidth': false},
      );
      app.blocks.add(b);
      app.editingBlockId = 'b1';
      await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child:
                SizedBox(width: 400, child: TextBlockView(block: b, app: app)),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final atRest = tester.getRect(find.byType(OnoteMath).first);
      await tester.tap(find.byType(InlineMathAtom));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final editing = tester.getRect(find.byType(OnoteMath).first);

      // The drawing and the editor are the same equation at the same size in
      // the same place; a student clicking in must see nothing move.
      expect((editing.top - atRest.top).abs(), lessThan(4.0),
          reason: 'the equation jumped ${editing.top - atRest.top}px on '
              'click-in — the superscript defect showed up exactly here');
      app.cancelPendingSave();
    });
  });
}
