// The container interaction model, and images in the flow of the text.
//
// Two long-standing complaints, both structural rather than cosmetic:
//
//   1. Dragging inside a text box MOVED the box. A GestureDetector wrapped the
//      whole block, so any click-drag over the body was claimed as a move
//      before the text layer saw it — but a click-drag inside a text box means
//      "select this text" to everyone who has ever used one. The fix is
//      OneNote's: a move bar, and a body that does not move.
//
//   2. A dropped or pasted image always became its own block, laid opaquely
//      over whatever it landed on with no text buffer and no editor — "I can't
//      type into this box with the image". In flow it is just Markdown, so
//      typing, selecting, cutting and pasting all work with no new code.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/block_view.dart';
import 'package:openote/canvas/media_drop.dart';
import 'package:openote/editor/text_block_view.dart';
import 'package:openote/model/models.dart';
import 'package:openote/model/tags.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  group('in-flow image splice', () {
    // A one-line PNG reference, in the §5.1 form the renderer understands.
    const ref = '![](sha256:abc123)';

    test('the reference always ends up alone on its line', () {
      // Mid-word, mid-paragraph — the worst case, because a reference sharing
      // a line with prose renders as literal source instead of a picture.
      final (out, _) = spliceImageOnOwnLine('hello world', 4, ref);
      final lines = out.split('\n');
      expect(lines, contains(ref));
      expect(lines.where((l) => l.contains('sha256')).single, ref);
    });

    test('what it produces is what the renderer matches', () {
      final (out, _) = spliceImageOnOwnLine('a\nb', 2, ref);
      final line = out.split('\n').firstWhere((l) => l.contains('sha256'));
      // The same line-anchored pattern read mode uses.
      expect(
        RegExp(r'^(\s*)!\[([^\]]*)\]\(([^)\s]+)(?:\s+=(\d+)x(\d+))?\)\s*$')
            .hasMatch(line),
        isTrue,
        reason: 'rendered as a picture, not printed as source',
      );
    });

    test('an empty block gets the reference and nothing else', () {
      final (out, at) = spliceImageOnOwnLine('', 0, ref);
      expect(out, ref);
      expect(at.line, 0);
      expect(at.linesAdded, 0);
    });

    test('it reports where it landed, so tags can be re-based', () {
      final (out, at) = spliceImageOnOwnLine('one\ntwo\nthree', 8, ref);
      expect(out.split('\n')[at.line], ref);
      expect(at.linesAdded, greaterThan(0));
    });

    test('the reference resolves through the renderer', () {
      // Prove the round trip, not just the string: `imageResolver` is what
      // read mode calls, and a reference it can't parse would silently render
      // as text.
      final (out, _) = spliceImageOnOwnLine('note', 4, ref);
      final matched = RegExp(r'\]\((sha256:[^)\s]+)\)').firstMatch(out);
      expect(matched?.group(1), 'sha256:abc123');
    });
  });

  group('dropping an image into a text box', () {
    Future<(Repository, Directory, AppState, Block)> fixture() async {
      final tmp = Directory.systemTemp.createTempSync('onote_inflow_');
      final repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Drop');
      final app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
      await app.selectPage(page.id);
      final b = app.addBlock(Block(
        type: BlockType.text,
        x: 100,
        y: 100,
        w: 300,
        h: 120,
        content: {'text': 'first line\nsecond line\nthird line'},
      ));
      return (repo, tmp, app, b);
    }

    final png = Uint8List.fromList(List.filled(64, 7));

    test('a drop ON the box goes into its text, not over it', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, b) = await fixture();
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final before = app.blocks.length;
      final hit = insertImageIntoTextAt(
          app, png, 'image/png', const Offset(150, 130),
          dark: false);
      expect(hit?.id, b.id);
      expect(app.blocks.length, before,
          reason: 'no new block laid over the note');
      expect(b.content['text'] as String, contains('](sha256:'));
      expect(b.content['autoWidth'], false,
          reason: 'an 80-character reference must not pin the box wide');
    });

    test('a drop that misses every box falls back to a picture block',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, _) = await fixture();
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      expect(
          insertImageIntoTextAt(app, png, 'image/png', const Offset(900, 900),
              dark: false),
          isNull);
    });

    test('tags below the image keep decorating their own lines', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, b) = await fixture();
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      // Tag the LAST line, then drop a picture near the top.
      NoteTag.writeInto(b.content, [NoteTag(kind: TagKind.important, line: 2)]);
      final tagged = (b.content['text'] as String).split('\n')[2];

      insertImageIntoTextAt(app, png, 'image/png', const Offset(150, 105),
          dark: false);

      final lines = (b.content['text'] as String).split('\n');
      final tag = NoteTag.listFrom(b.content).single;
      expect(lines[tag.line], tagged,
          reason: 'inserting lines must re-base every tag below the insert');
    });

    test('the same bytes twice reuse one blob', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, b) = await fixture();
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      insertImageIntoTextAt(app, png, 'image/png', const Offset(150, 120),
          dark: false);
      insertImageIntoTextAt(app, png, 'image/png', const Offset(150, 160),
          dark: false);
      final refs = RegExp(r'sha256:([0-9a-f]+)')
          .allMatches(b.content['text'] as String)
          .map((m) => m.group(1))
          .toSet();
      expect(refs.length, 1,
          reason: 'content-addressed storage: one copy, two references');
    });
  });

  group('the container move bar', () {
    // Built in setUp, NOT in the test body: `testWidgets` runs inside a
    // fake-async zone where real file I/O never completes, so awaiting
    // Repository.openAt in there hangs forever.
    late Repository repo;
    late Directory tmp;
    late AppState app;
    late Block block;

    setUp(() async {
      if (!haveSqlite) return;
      tmp = Directory.systemTemp.createTempSync('onote_movebar_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Bar');
      // Spell-check off: it loads a 172k-word dictionary asynchronously, and
      // a widget test has no reason to wait for that.
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      await app.selectPage(
          app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
      block = app.addBlock(Block(
        type: BlockType.text,
        x: 60,
        y: 60,
        w: 240,
        h: 100,
        content: {'text': 'select me please'},
      ));
      app.select(null);
    });

    tearDown(() {
      if (!haveSqlite) return;
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    // Wrapped in a ListenableBuilder because the real shell is: entering edit
    // mode has to actually swap the read-only Markdown for a live TextField,
    // or the caret and selection tests would be testing nothing.
    Future<void> pump(WidgetTester t) => t.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: app,
              builder: (_, __) => Stack(children: [
                BlockView(block: block, app: app, controller: app.canvas),
              ]),
            ),
          ),
        ));

    /// Three increments, because a drag recognizer swallows the one that wins
    /// it the gesture arena — asserting an exact total would be asserting
    /// Flutter's slop handling, not ours.
    Future<void> dragBy(WidgetTester t, Offset from, Offset step) async {
      final g = await t.startGesture(from);
      for (var i = 0; i < 3; i++) {
        await g.moveBy(step);
        await t.pump();
      }
      await g.up();
      await t.pump(const Duration(milliseconds: 50));
      // Moving a block schedules a debounced save. Its timer would still be
      // pending when the tree is torn down (a test failure), and letting it
      // fire would start real disk I/O inside the fake-async zone, which never
      // completes. Cancelling is the only correct answer here.
      app.cancelPendingSave();
    }

    /// The offset the live editor's caret currently sits at, or null if no
    /// editor is open.
    int? caret(AppState a) {
      final s = a.activeEditor?.controller.selection;
      return s != null && s.isValid ? s.baseOffset : null;
    }

    testWidgets('a box does not change width when you edit it', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // Auto-width was measured ONLY for the block being edited, so a box
      // carried whatever width it was created with until you first clicked
      // into it and then snapped to its real width — visible as the box
      // growing sideways the moment you started typing in it.
      block.content['text'] = 'The quick brown fox jumps over the lazy dog';
      block.h = null;
      await pump(t);
      await t.pump();
      final read = block.w;

      app.select(block.id, edit: true);
      await t.pump();
      await t.pump();
      final editing = block.w;

      app.select(null);
      await t.pump();
      await t.pump();
      app.cancelPendingSave();

      expect(editing, read, reason: 'entering edit resized the box');
      expect(block.w, read, reason: 'leaving edit resized the box');
    });

    testWidgets('a manually resized box is never re-measured', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // Dragging the handle sets autoWidth: false, and the OneNote importer
      // sets it too — OneNote gave those boxes a real width, and measuring
      // them would rewrite an imported page's layout.
      block.content['text'] = 'short';
      block.content['autoWidth'] = false;
      block.w = 300;
      block.h = null;
      await pump(t);
      await t.pump();
      app.select(block.id, edit: true);
      await t.pump();
      await t.pump();
      app.cancelPendingSave();
      expect(block.w, 300);
    });

    testWidgets('clicking into a paragraph puts the caret where you clicked',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The bug: the caret always landed at the END of the block, whatever you
      // clicked. The mechanism to place it existed but never fired, because it
      // searched DOWNWARDS from the focus node's context for the
      // EditableTextState — and `EditableText` builds its `Focus` inside
      // itself, so the state is an ANCESTOR. With no offset to place,
      // EditableText fell through to its documented "place cursor at the end
      // if the selection is invalid when we receive focus".
      block.content['text'] = 'first line here\nsecond line here\nthird line';
      block.h = null; // a text box is auto-height; a fixed one clips
      await pump(t);

      // Near the start of the first line.
      await t.tapAt(Offset(block.x + 12, block.y + 12));
      await t.pump(); // the session is created during this build
      await t.pump(); // its post-frame callback places the caret
      app.cancelPendingSave();

      final at = caret(app);
      final len = (block.content['text'] as String).length;
      expect(at, isNotNull, reason: 'a tap must open an editor');
      expect(at, lessThan(len),
          reason: 'the caret jumped to the end of the block again');
      expect(at, lessThan(20),
          reason: 'clicked near the start of the first line, landed at $at');
    });

    testWidgets('the caret follows the click to a later line', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      block.content['text'] = 'first line here\nsecond line here\nthird line';
      block.h = null; // a text box is auto-height; a fixed one clips
      await pump(t);
      // Two clicks at clearly different heights must give clearly different
      // offsets — a caret that is merely "not at the end" could still be
      // pinned at zero.
      await t.tapAt(Offset(block.x + 12, block.y + 8));
      await t.pump();
      await t.pump();
      final high = caret(app);

      app.select(null);
      await t.pump();
      await t.tapAt(Offset(block.x + 12, block.y + 40));
      await t.pump();
      await t.pump();
      final low = caret(app);
      app.cancelPendingSave();

      expect(high, isNotNull);
      expect(low, isNotNull);
      expect(low!, greaterThan(high!),
          reason: 'clicking lower down must land later in the text');
    });

    testWidgets('dragging across an unselected box selects its text',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // A non-editing block renders read-only Markdown — there is no field to
      // drag-select in until the session exists. The first drag has to open
      // one mid-gesture and extend the selection from the press point.
      block.content['text'] = 'aaaa bbbb cccc dddd eeee ffff';
      block.h = null;
      await pump(t);

      final g = await t.startGesture(Offset(block.x + 10, block.y + 12));
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(18, 0));
        await t.pump();
      }
      await g.up();
      await t.pump();
      app.cancelPendingSave();

      final sel = app.activeEditor?.controller.selection;
      expect(sel, isNotNull, reason: 'the drag must have opened an editor');
      expect(sel!.isCollapsed, isFalse,
          reason: 'dragging across the text must select it, not just focus it');
      expect(sel.textInside(app.activeEditor!.controller.text), isNotEmpty);
    });

    testWidgets('dragging the body does NOT move the block', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pump(t);
      final x = block.x, y = block.y;
      // Straight through the middle of the text — the exact gesture that used
      // to drag the whole container away.
      await dragBy(t, const Offset(140, 130), const Offset(24, 8));
      expect(block.x, x, reason: 'a drag over the text is a text selection');
      expect(block.y, y);
    });

    testWidgets('dragging the bar moves the block', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The bar only exists once the block is live (hovered or selected).
      app.select(block.id);
      await pump(t);
      final x = block.x, y = block.y;
      // The reserved strip is the 16px above the content's top edge.
      await dragBy(t, Offset(block.x + 40, block.y - 8), const Offset(20, 15));
      expect(block.x - x, greaterThan(15));
      expect(block.y - y, greaterThan(10));
    });

    testWidgets('a locked block has no bar and cannot be dragged', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // An imported PDF slide: an annotation surface, so it must not move when
      // the pen misses.
      block.content['locked'] = true;
      app.select(block.id);
      await pump(t);
      final x = block.x, y = block.y;
      await dragBy(t, Offset(block.x + 40, block.y - 8), const Offset(20, 15));
      await dragBy(t, Offset(block.x + 40, block.y + 40), const Offset(20, 15));
      expect(block.x, x);
      expect(block.y, y);
    });
  });

  group('auto-width', () {
    testWidgets('an image reference does not pin the box to its maximum',
        (t) async {
      // `![](sha256:<64 hex>)` is ~80 characters of source the reader never
      // sees. Measured, it would slam any auto-width box to maxAutoW the
      // instant a picture landed in it.
      final plain = Block(
          type: BlockType.text, x: 0, y: 0, w: 200, content: {'text': 'hi'});
      final withImage =
          Block(type: BlockType.text, x: 0, y: 0, w: 200, content: {
        'text': 'hi\n![](sha256:${'a' * 64})',
      });
      expect(
        TextBlockView.autoWidth(withImage, dark: false),
        TextBlockView.autoWidth(plain, dark: false),
        reason: 'the hidden reference must not decide the width',
      );
    });
  });
}
