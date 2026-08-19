// A dot point that runs over more than one line must keep its indent WHILE IT
// IS BEING EDITED, not only when it is read.
//
// The owner's words: "if i have a dotpoint that goes over multiple lines when
// its in view mode it renders properly where both lines start at the same
// indent as expected, however when editing the second (and further) lines push
// all the way left to the edge of the box, this shouldnt happen."
//
// The read renderer gets this free — a list line there is a Row of
// [gutter, Expanded(Text)] — while the editor is one paragraph in one
// TextField, and Flutter has no per-paragraph hanging indent. These tests hold
// the mechanism that closes the gap (live_markdown_controller.dart) to three
// promises: the indent is real, the caret still lands exactly where the source
// says it does, and a line that cannot hang cleanly is left alone rather than
// half-done.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/block_view.dart';
import 'package:openote/editor/live_markdown_controller.dart';
import 'package:openote/markdown/md_render.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/theme/tokens.dart';

import 'support/sqlite.dart';

const _style = TextStyle(fontSize: 15, height: 1.5, letterSpacing: 0.25);

/// The field the engine builds, minus focus and spell-check (neither affects
/// geometry). The LayoutBuilder is the load-bearing part and mirrors
/// `_LiveMarkdownSession.build`: the controller cannot predict where the field
/// will wrap without knowing the width it will be laid out at.
Widget _editField(LiveMarkdownController c, double width) => Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: LayoutBuilder(builder: (ctx, cons) {
          c.layoutWidth = cons.maxWidth - kEditorCaretMargin;
          return TextField(
            controller: c,
            maxLines: null,
            style: _style,
            strutStyle: StrutStyle.fromTextStyle(_style, forceStrutHeight: false),
            decoration: OnoteInput.bare,
          );
        }),
      ),
    );

RenderEditable _editable(WidgetTester t) =>
    t.state<EditableTextState>(find.byType(EditableText)).renderEditable;

/// Where each visual line begins: its source offset and the x the caret sits
/// at just after that offset's placeholder or glyph — i.e. where the line's
/// text actually starts.
List<({int offset, double textX})> _lineStarts(RenderEditable re, String text) {
  final out = <({int offset, double textX})>[];
  double? lastY;
  for (var i = 0; i <= text.length; i++) {
    final r = re.getLocalRectForCaret(TextPosition(offset: i));
    if (lastY == null || (r.top - lastY).abs() > 1) {
      out.add((
        offset: i,
        textX: re.getLocalRectForCaret(TextPosition(offset: i + 1)).left,
      ));
      lastY = r.top;
    }
  }
  return out;
}

void main() {
  group('a wrapped dot point keeps its indent while editing', () {
    testWidgets('every continuation line starts on the body indent', (t) async {
      const text = '- alpha bravo charlie delta echo foxtrot golf hotel';
      final c = LiveMarkdownController(text: text, dark: false);
      await t.pumpWidget(MaterialApp(
          theme: onoteTheme(Brightness.light),
          home: Scaffold(body: _editField(c, 200))));
      await t.pumpAndSettle();

      final lines = _lineStarts(_editable(t), text);
      expect(lines.length, greaterThan(2),
          reason: 'precondition: the bullet has to wrap at all');
      // The first line's text begins after the hanging bullet glyph; every
      // wrapped line has to begin in the same place. Before this, they began
      // at 0 — "the second (and further) lines push all the way left".
      for (final l in lines) {
        expect(l.textX, moreOrLessEquals(kBulletGutter, epsilon: 0.5),
            reason: 'line starting at offset ${l.offset} is flush left');
      }
    });

    testWidgets('a nested bullet hangs on ITS indent, not the outer one',
        (t) async {
      const text = '    - nested alpha bravo charlie delta echo foxtrot golf';
      final c = LiveMarkdownController(text: text, dark: false);
      await t.pumpWidget(MaterialApp(
          theme: onoteTheme(Brightness.light),
          home: Scaffold(body: _editField(c, 260))));
      await t.pumpAndSettle();

      // Four leading spaces is two Markdown levels; the read renderer puts the
      // body on indentPx(4), so the editor has to as well or the two disagree
      // by a level every time the caret enters the block.
      final want = indentPx(4, _style.fontSize);
      final lines = _lineStarts(_editable(t), text);
      expect(lines.length, greaterThan(1), reason: 'precondition: it wraps');
      for (final l in lines) {
        expect(l.textX, moreOrLessEquals(want, epsilon: 0.5));
      }
    });

    testWidgets('a plain paragraph is left exactly alone', (t) async {
      const text = 'plain alpha bravo charlie delta echo foxtrot golf hotel';
      final c = LiveMarkdownController(text: text, dark: false);
      await t.pumpWidget(MaterialApp(
          theme: onoteTheme(Brightness.light),
          home: Scaffold(body: _editField(c, 200))));
      await t.pumpAndSettle();

      final lines = _lineStarts(_editable(t), text);
      expect(lines.length, greaterThan(1), reason: 'precondition: it wraps');
      // Prose has no gutter to hang in, so indenting its wrapped lines would
      // be inventing a layout the read renderer does not have.
      for (final l in lines.skip(1)) {
        expect(l.textX, lessThan(kBulletGutter));
      }
    });

    testWidgets('a word longer than the line is left flush, not half-indented',
        (t) async {
      // There is no space to stand the gutter box on when a line wraps
      // mid-word, and half an indented bullet reads as a bug. The item keeps
      // exactly the behaviour it had before this feature existed.
      const text =
          '- supercalifragilisticexpialidociousandthensomemore tail words here';
      final c = LiveMarkdownController(text: text, dark: false);
      await t.pumpWidget(MaterialApp(
          theme: onoteTheme(Brightness.light),
          home: Scaffold(body: _editField(c, 200))));
      await t.pumpAndSettle();

      final lines = _lineStarts(_editable(t), text);
      expect(lines.length, greaterThan(2), reason: 'precondition: it wraps');
      for (final l in lines.skip(1)) {
        expect(l.textX, lessThan(kBulletGutter),
            reason: 'all or nothing: no line of this item may hang');
      }
    });
  });

  group('the indent moves no caret offset', () {
    testWidgets('every source offset still has its own caret position',
        (t) async {
      const text = '- alpha bravo charlie delta echo foxtrot golf hotel';
      final c = LiveMarkdownController(text: text, dark: false);
      await t.pumpWidget(MaterialApp(
          theme: onoteTheme(Brightness.light),
          home: Scaffold(body: _editField(c, 200))));
      await t.pumpAndSettle();
      final re = _editable(t);

      // The whole mechanism rests on a WidgetSpan being exactly ONE code unit,
      // so the paragraph has as many positions as the buffer has characters.
      // Walking every offset in order must never go backwards on a line and
      // must never skip one.
      Offset? prev;
      for (var i = 0; i <= text.length; i++) {
        final r = re.getLocalRectForCaret(TextPosition(offset: i));
        expect(r.left.isFinite && r.top.isFinite, isTrue, reason: 'offset $i');
        if (prev != null && (r.top - prev.dy).abs() < 1) {
          expect(r.left, greaterThanOrEqualTo(prev.dx - 0.01),
              reason: 'caret went backwards between $i and ${i - 1}');
        }
        prev = Offset(r.left, r.top);
      }
      expect(c.text, text, reason: 'rendering must never touch the buffer');
    });

    testWidgets('clicking on a wrapped line lands on the character clicked',
        (t) async {
      const text = '- alpha bravo charlie delta echo foxtrot golf hotel';
      final c = LiveMarkdownController(text: text, dark: false);
      await t.pumpWidget(MaterialApp(
          theme: onoteTheme(Brightness.light),
          home: Scaffold(body: _editField(c, 200))));
      await t.pumpAndSettle();
      final re = _editable(t);

      // Pick a character on a wrapped line, ask where it is drawn, then ask
      // what is at that point. An indent that shifted ink without shifting
      // layout — the tempting shortcut — fails exactly here.
      final at = text.indexOf('foxtrot') + 3;
      final box = re
          .getBoxesForSelection(
              TextSelection(baseOffset: at, extentOffset: at + 1))
          .single;
      // A quarter into the glyph, not the middle: getPositionForPoint snaps to
      // the nearest character BOUNDARY, so dead centre is a coin toss.
      final local = Offset(box.left + box.toRect().width / 4, box.top + 2);
      final global = re.localToGlobal(local);
      expect(re.getPositionForPoint(global).offset, at);
    });
  });

  group('the width the wrap prediction is made against', () {
    testWidgets('is the field constraint less the caret gap', (t) async {
      // kEditorCaretMargin is RenderEditable's own `_kCaretGap + cursorWidth`,
      // read off a private constant. If a Flutter upgrade changes it, every
      // predicted wrap point moves and the indent lands mid-sentence — so the
      // number is pinned here against what the field actually does.
      const text = '- alpha bravo charlie delta echo foxtrot golf hotel';
      final c = LiveMarkdownController(text: text, dark: false);
      await t.pumpWidget(MaterialApp(
          theme: onoteTheme(Brightness.light),
          home: Scaffold(
              body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 200,
              child: TextField(
                controller: c,
                maxLines: null,
                style: _style,
                strutStyle:
                    StrutStyle.fromTextStyle(_style, forceStrutHeight: false),
                decoration: OnoteInput.bare,
              ),
            ),
          ))));
      await t.pumpAndSettle();
      final re = _editable(t);
      expect(re.constraints.maxWidth, 200);

      final actual = [for (final l in _lineStarts(re, text)) l.offset];
      List<int> predictAt(double w) {
        final tp = TextPainter(
            text: c.buildTextSpan(
                context: t.element(find.byType(EditableText)),
                style: _style,
                withComposing: false),
            textDirection: TextDirection.ltr,
            maxLines: null)
          ..setPlaceholderDimensions(const [
            PlaceholderDimensions(
                size: Size(kBulletGutter, 15),
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                baselineOffset: 12)
          ])
          ..layout(maxWidth: w);
        final out = [
          for (final m in tp.computeLineMetrics())
            tp
                .getLineBoundary(
                    tp.getPositionForOffset(Offset(0, m.baseline - 1)))
                .start
        ];
        tp.dispose();
        return out;
      }

      expect(predictAt(200 - kEditorCaretMargin), actual);
      expect(predictAt(200), isNot(actual),
          reason: 'the caret gap is not optional — this is the control');
    });
  });

  group('through the real editor', () {
    // The geometry tests above build the field themselves. This one proves the
    // ENGINE hands the controller its width at all: without the LayoutBuilder
    // in live_markdown_engine.dart, `layoutWidth` stays null and nothing
    // above ever runs in the app.
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());

    late Repository repo;
    late Directory tmp;
    late AppState app;
    late Block block;

    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_hang_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Hang');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      await app
          .selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
      block = app.addBlock(Block(
        type: BlockType.text,
        x: 0,
        y: 0,
        w: 240,
        h: 160,
        content: {
          'text': '- alpha bravo charlie delta echo foxtrot golf hotel',
          'autoWidth': false,
        },
      ));
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

    testWidgets('the engine gives the controller its layout width', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await t.pumpWidget(MaterialApp(
        theme: onoteTheme(Brightness.light),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: app,
            builder: (_, __) => Stack(children: [
              BlockView(block: block, app: app, controller: app.canvas),
            ]),
          ),
        ),
      ));
      await t.pump();
      app.select(block.id, edit: true);
      await t.pump();
      await t.pump();

      final text = block.content['text'] as String;
      final lines = _lineStarts(_editable(t), text);
      expect(lines.length, greaterThan(1), reason: 'precondition: it wraps');
      for (final l in lines.skip(1)) {
        expect(l.textX, greaterThan(kBulletGutter - 0.5),
            reason: 'the engine never told the controller how wide it is');
      }
      app.cancelPendingSave();
    });
  });
}
