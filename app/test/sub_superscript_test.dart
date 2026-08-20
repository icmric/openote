// Subscript and superscript for ordinary text: `H~2~O`, `x^2^`, authored with
// OneNote's own Ctrl+= and Ctrl+Shift+=. Plus Alt+= to start an equation.
//
// The whole risk of this feature is the ONE shared inline grammar
// (markdown/md_syntax.dart): a single `~` is a prefix of the `~~` this app has
// always used for strikethrough, which is character-for-character the `*`
// inside `**` collision that once rendered `***bold italic***` as bold plus a
// stray asterisk. So the grammar tests below are not decoration — they are the
// feature's only real defence, and they cover both the runs that must match
// and the prose that must be left alone.
//
// The other risk is shadowing: `=` is a printable character, and this codebase
// has been bitten before by canvas-level shortcuts eating keys out of the text
// editors. The shell group presses the real keys and checks that plain typing
// still gets through.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/live_markdown_controller.dart';
import 'package:openote/export/markdown_export.dart';
import 'package:openote/export/md_common.dart';
import 'package:openote/markdown/md_render.dart';
import 'package:openote/markdown/md_syntax.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/app_shell.dart';
import 'package:openote/ui/keyboard_map.dart';

import 'support/sqlite.dart';

/// Every match in [s], as `kind:inner` — the shape both renderers see.
List<String> scan(String s) => [
      for (final m in mdInlineRe.allMatches(s))
        '${classifyInline(m).kind.name}:${classifyInline(m).inner}'
    ];

void main() {
  // ── The grammar ────────────────────────────────────────────────────────
  group('the grammar matches sub and superscript', () {
    test('H~2~O is one subscript run', () {
      expect(scan('H~2~O'), ['subscript:2']);
    });

    test('x^2^ is one superscript run', () {
      expect(scan('x^2^'), ['superscript:2']);
    });

    test('letters work too, not just digits — a~m~ and x^n^', () {
      expect(scan('a~m~ and x^n^'), ['subscript:m', 'superscript:n']);
    });

    test('markers bracket the inner text exactly, so coverage holds', () {
      // The live editor re-emits marker + inner + marker as three substrings
      // of the source and then checks they concatenate back to the raw text.
      // If openLen/closeLen do not bracket `inner`, that check trips and the
      // whole block silently falls back to unstyled text.
      for (final m in mdInlineRe.allMatches('H~2~O and x^2^ and ~~gone~~')) {
        final c = classifyInline(m);
        final full = 'H~2~O and x^2^ and ~~gone~~'
            .substring(m.start, m.end);
        expect(full.substring(c.openLen, full.length - c.closeLen), c.inner,
            reason: 'markers do not bracket the inner text of "$full"');
      }
    });
  });

  group('the ~ / ~~ collision', () {
    test('~~struck~~ is still strikethrough, not two subscripts', () {
      expect(scan('~~struck~~'), ['strike:struck']);
    });

    test('both live in one sentence and keep their own kinds', () {
      expect(scan('H~2~O then ~~wrong~~ then CO~2~'),
          ['subscript:2', 'strike:wrong', 'subscript:2']);
    });

    test('strikethrough first even when a subscript opens the line', () {
      expect(scan('~a~ ~~b~~'), ['subscript:a', 'strike:b']);
    });

    test('and the other way round', () {
      expect(scan('~~b~~ ~a~'), ['strike:b', 'subscript:a']);
    });
  });

  group('a literal tilde or caret stays literal', () {
    // Each of these is prose a student actually writes. The no-whitespace
    // rule inside the markers is what saves every one of them: with a lazy
    // inner, "3^2 = 9 and 4^2 = 16" matched `^2 = 9 and 4^` and ate half the
    // sentence, because the closing caret is flanked by digits on both sides.
    const prose = <String, String>{
      'approximately': 'about ~5 to ~10 people',
      'arithmetic': '3^2 = 9 and 4^2 = 16',
      'home paths': '~/Documents and ~/Downloads',
      'spaced tilde': 'a ~ b',
      'lone caret': 'the caret ^ on its own',
      'lone tilde': 'roughly ~50',
    };
    prose.forEach((name, text) {
      test(name, () => expect(scan(text), isEmpty, reason: text));
    });

    test('but a real run beside literal prose still matches', () {
      expect(scan('about ~5 people drink H~2~O'), ['subscript:2']);
    });
  });

  // ── Both renderers ─────────────────────────────────────────────────────
  group('both renderers draw it, and draw it the same', () {
    const base = TextStyle(fontSize: 15, height: 1.5, color: Color(0xFF111111));

    test('the read renderer drops the markers and shifts the ink', () {
      final spans = inlineSpans('H~2~O', base, false);
      final text = spans
          .whereType<TextSpan>()
          .map((s) => s.text ?? '')
          .join();
      expect(text, 'H2O', reason: 'the tildes must not be readable');
      final sub = spans
          .whereType<TextSpan>()
          .firstWhere((s) => s.text == '2');
      expect(sub.style!.fontSize, lessThan(15));
      // Down for a subscript, up for a superscript — this is the only thing
      // that tells the two apart on screen.
      expect(sub.style!.shadows!.single.offset.dy, greaterThan(0));
      final sup = inlineSpans('x^2^', base, false)
          .whereType<TextSpan>()
          .firstWhere((s) => s.text == '2');
      expect(sup.style!.shadows!.single.offset.dy, lessThan(0));
    });

    test('the two renderers agree character for character', () {
      // The shared helper is the point: bold once drifted to w700 in the
      // editor against w600 when read, so text changed shape on click-in.
      expect(subSupStyle(base, sup: false, dark: false),
          subSupStyle(base, sup: false, dark: false));
      expect(subSupStyle(base, sup: true, dark: false) ==
          subSupStyle(base, sup: false, dark: false), isFalse);
    });

    testWidgets('the live editor keeps every code unit of the source',
        (t) async {
      await t.pumpWidget(
          const MaterialApp(home: Scaffold(body: SizedBox(width: 400))));
      for (final src in ['H~2~O', 'x^2^', '~~struck~~ and H~2~O']) {
        final c = LiveMarkdownController(text: src, dark: false)
          ..selection = const TextSelection.collapsed(offset: 0);
        final root = c.buildTextSpan(
            context: t.element(find.byType(SizedBox)),
            style: base,
            withComposing: false);
        // Children means the coverage check PASSED; one bare span means it
        // failed and fell back, which is how a broken build looks in the app
        // ("the styling just stopped working", with no crash to chase).
        expect(root.children, isNotNull, reason: src);
        expect(root.toPlainText(), src,
            reason: 'caret offsets move the moment this is not exact');
        c.dispose();
      }
    });

    testWidgets('and it styles the inner text while you type', (t) async {
      await t.pumpWidget(
          const MaterialApp(home: Scaffold(body: SizedBox(width: 400))));
      final c = LiveMarkdownController(text: 'H~2~O', dark: false)
        ..selection = const TextSelection.collapsed(offset: 0);
      final root = c.buildTextSpan(
          context: t.element(find.byType(SizedBox)),
          style: base,
          withComposing: false);
      final styled = <TextSpan>[];
      void walk(InlineSpan s) {
        if (s is TextSpan) {
          if (s.text == '2') styled.add(s);
          s.children?.forEach(walk);
        }
      }

      walk(root);
      expect(styled, hasLength(1));
      expect(styled.single.style!.shadows!.single.offset.dy, greaterThan(0));
      c.dispose();
    });
  });

  // ── The ink, counted ───────────────────────────────────────────────────
  //
  // The styles above prove what we ASKED for; these prove what is painted.
  // The shadow trick is unusual enough to be worth checking at the pixel
  // level, and doing so immediately found a real defect: at the rise
  // typography would suggest, the top of every superscript was cut off on
  // imported OneNote boxes — whose line height is 1.2207 and which are
  // exactly where imported superscripts arrive from.
  group('the ink actually moves, and nothing is cut off', () {
    final key = GlobalKey();

    /// Paint [src] at line height [lh] and report (ink pixels, first row with
    /// ink, last row with ink).
    Future<(int, int, int)> paint(
        WidgetTester t, String src, double lh) async {
      final style =
          TextStyle(fontSize: 20, height: lh, color: const Color(0xFF000000));
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFFFFFFFF),
          body: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: Container(
                color: const Color(0xFFFFFFFF),
                width: 200,
                height: 80,
                child: Text.rich(
                  TextSpan(children: inlineSpans(src, style, false)),
                  style: style,
                ),
              ),
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      late ui.Image img;
      await t.runAsync(() async => img = await boundary.toImage());
      final data = await t.runAsync(
          () async => img.toByteData(format: ui.ImageByteFormat.rawRgba));
      final b = data!.buffer.asUint8List();
      final w = img.width, h = img.height;
      var ink = 0, top = -1, bottom = -1;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          if (b[(y * w + x) * 4] < 128) {
            ink++;
            if (top < 0) top = y;
            bottom = y;
          }
        }
      }
      return (ink, top, bottom);
    }

    testWidgets('a superscript sits above the line and a subscript below',
        (t) async {
      final plain = await paint(t, 'H2', 1.5);
      final sup = await paint(t, 'H^2^', 1.5);
      final sub = await paint(t, 'H~2~', 1.5);
      // Flutter's TextStyle has no baseline shift, so the ink is moved by
      // painting the glyph as a zero-blur shadow. If that ever stopped
      // working the styles would still read correctly and the page would
      // show sub and super as the same plain small text.
      expect(sup.$2, lessThan(plain.$2), reason: 'superscript reaches higher');
      expect(sub.$3, greaterThan(plain.$3), reason: 'subscript reaches lower');
      // And they are genuinely smaller than the text around them.
      expect(sup.$1, lessThan(plain.$1));
      expect(sub.$1, lessThan(plain.$1));
    });

    testWidgets('nothing is clipped on an imported OneNote box', (t) async {
      // 1.2207 is `oneNoteLineHeight` — the line height every imported box
      // carries, and the tightest one any block in the app uses. A raised
      // glyph is drawn OUTSIDE its line box, so too big a rise is simply cut
      // off at the text box's edge.
      final roomy = await paint(t, 'H^2^', 1.5);
      final tight = await paint(t, 'H^2^', 1.2207031);
      expect(tight.$1, roomy.$1,
          reason: 'the superscript loses ink, i.e. its top is cut off');
      final tightSub = await paint(t, 'H~2~', 1.2207031);
      expect(tightSub.$1, (await paint(t, 'H~2~', 1.5)).$1,
          reason: 'and neither is the subscript');
    });
  });

  // ── The command ────────────────────────────────────────────────────────
  group('Ctrl+= / Ctrl+Shift+= through wrapSelection', () {
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());

    late Directory tmp;
    late Repository repo;
    late AppState app;
    late TextEditingController c;
    late Block block;

    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_subsup_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('T');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      await app.selectPage(
          app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
      block = Block(type: BlockType.text, x: 0, y: 0, content: {'text': ''});
      app.addBlock(block, recordUndo: false);
      c = TextEditingController();
      app.setActiveEditor(c, block, 'text');
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

    /// Put `text` in the editor with the caret at `|`, or a selection `«…»`.
    void edit(String spec) {
      final b = spec.indexOf('«');
      if (b >= 0) {
        final e = spec.indexOf('»');
        c.value = TextEditingValue(
          text: spec.replaceAll('«', '').replaceAll('»', ''),
          selection: TextSelection(baseOffset: b, extentOffset: e - 1),
        );
        return;
      }
      final i = spec.indexOf('|');
      c.value = TextEditingValue(
        text: spec.replaceFirst('|', ''),
        selection: TextSelection.collapsed(offset: i),
      );
    }

    test('with nothing selected it formats the word at the caret', () {
      if (!haveSqlite) return;
      edit('CO2 is not CO|2 yet');
      app.wrapSelection('~');
      expect(c.text, 'CO2 is not ~CO2~ yet');
    });

    test('with a selection it wraps and keeps the words selected', () {
      if (!haveSqlite) return;
      edit('H«2»O');
      app.wrapSelection('~');
      expect(c.text, 'H~2~O');
      expect(c.text.substring(c.selection.start, c.selection.end), '2');
    });

    test('pressing it again from inside the run takes it off', () {
      if (!haveSqlite) return;
      edit('H«2»O');
      app.wrapSelection('~');
      c.selection = const TextSelection.collapsed(offset: 2);
      app.wrapSelection('~');
      expect(c.text, 'H2O');
    });

    test('superscript is the same command with the other marker', () {
      if (!haveSqlite) return;
      edit('x«2»');
      app.wrapSelection('^');
      expect(c.text, 'x^2^');
      c.selection = const TextSelection.collapsed(offset: 2);
      app.wrapSelection('^');
      expect(c.text, 'x2');
    });

    test('the two REPLACE each other instead of nesting', () {
      if (!haveSqlite) return;
      // Nesting would write `~^2^~`, which the grammar reads as neither (the
      // inner run is never re-scanned), so the markers would sit in the note
      // for ever — the exact failure this command was rewritten to stop.
      edit('x«2»');
      app.wrapSelection('^');
      expect(c.text, 'x^2^');
      c.selection = const TextSelection.collapsed(offset: 2);
      app.wrapSelection('~');
      expect(c.text, 'x~2~', reason: 'swapped, not nested');
      expect(c.text.contains('^'), isFalse);
      // And back again.
      c.selection = const TextSelection.collapsed(offset: 2);
      app.wrapSelection('^');
      expect(c.text, 'x^2^');
    });

    test('a two-word selection is wrapped word by word, so it still renders',
        () {
      if (!haveSqlite) return;
      edit('say «hello world» there');
      app.wrapSelection('~');
      expect(c.text, 'say ~hello~ ~world~ there');
      // The point of doing it this way: `~hello world~` matches nothing.
      expect(scan(c.text), ['subscript:hello', 'subscript:world']);
    });

    test('the strikethrough command is untouched by the new marker', () {
      if (!haveSqlite) return;
      // `~` and `~~` are now separate entries in the same mark table, which
      // is exactly the shape that made Ctrl+I inside `**word**` produce
      // `*word*` before the command started asking the grammar.
      edit('a wo|rd b');
      app.wrapSelection('~~');
      expect(c.text, 'a ~~word~~ b');
      expect(scan(c.text), ['strike:word']);
      c.selection = const TextSelection.collapsed(offset: 6);
      app.wrapSelection('~~');
      expect(c.text, 'a word b', reason: 'and it still toggles off');
    });

    test('marksAtCaret lights the right one', () {
      if (!haveSqlite) return;
      edit('H~|2~O');
      expect(app.marksAtCaret(), contains(MdInline.subscript));
      edit('x^|2^');
      expect(app.marksAtCaret(), contains(MdInline.superscript));
    });
  });

  // ── Export ─────────────────────────────────────────────────────────────
  group('it round-trips through Markdown export', () {
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());

    late Directory tmp;
    late Repository repo;
    late AppState app;

    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_subsup_md_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('T');
      app = AppState(repo)..notebookId = nb.id;
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

    test('the .md carries the source verbatim, and it re-reads the same', () {
      if (!haveSqlite) return;
      const source = 'H~2~O, x^2^ and ~~struck~~';
      final md = pageMarkdownOf(app, 'Chem', [
        Block(type: BlockType.text, x: 0, y: 0, content: {'text': source})
      ]);
      expect(md, contains(source),
          reason: 'Pandoc syntax IS Markdown — nothing to convert');
      // Re-reading the exported line has to yield the same three runs, or the
      // export is lossy in the only way that matters.
      expect(scan(source),
          ['subscript:2', 'superscript:2', 'strike:struck']);
    });

    test('markdownInline leaves the markers alone', () {
      expect(markdownInline('H~2~O and x^2^'), 'H~2~O and x^2^');
    });

    test('plainLine strips them for summaries, and only when paired', () {
      // The planner and the tag rollup quote note lines outside the renderer,
      // and used to show the raw markers.
      expect(plainLine('- H~2~O and x^2^'), 'H2O and x2');
      expect(plainLine('~~gone~~ H~2~O'), 'gone H2O');
      // Prose survives — the same no-whitespace rule as the grammar.
      expect(plainLine('about ~5 to ~10 and 3^2 = 9'),
          'about ~5 to ~10 and 3^2 = 9');
    });
  });

  // ── The real shell ─────────────────────────────────────────────────────
  group('the shortcuts, from the real shell', () {
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());

    late Directory tmp;
    late Repository repo;
    late AppState app;
    late Block para;

    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_subsup_key_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Study');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
      para = Block(
          type: BlockType.text,
          x: 40,
          y: 120,
          w: 300,
          h: 60,
          content: {'text': 'water'});
      app.importPage(nb.id, page.id, [para], PageProps());
      app.reloadNodes();
      await app.selectPage(page.id);
      app.markOnboardingSeen();
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

    Future<void> pumpShell(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: onoteTheme(Brightness.light),
        home: AppShell(app: app),
      ));
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
    }

    /// Press [k], returning whether the shell swallowed the key event.
    Future<bool> key(WidgetTester tester, LogicalKeyboardKey k,
        {bool ctrl = false, bool shift = false, bool alt = false}) async {
      if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      final handled = await tester.sendKeyDownEvent(k);
      await tester.sendKeyUpEvent(k);
      if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      return handled;
    }

    /// Start editing the paragraph and select the whole word.
    Future<void> editWholeWord(WidgetTester tester) async {
      app.select(para.id, edit: true);
      await tester.pumpAndSettle();
      final ed = app.activeEditor!;
      ed.controller.selection = TextSelection(
          baseOffset: 0, extentOffset: ed.controller.text.length);
      await tester.pumpAndSettle();
    }

    /// Flush the autosave debounce an edit session arms.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
    }

    testWidgets('Ctrl+= subscripts, Ctrl+Shift+= superscripts', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(tester);
      await editWholeWord(tester);

      expect(await key(tester, LogicalKeyboardKey.equal, ctrl: true), isTrue);
      expect(app.activeEditor!.controller.text, '~water~');

      // Applying the other one replaces it rather than nesting.
      app.activeEditor!.controller.selection =
          const TextSelection.collapsed(offset: 3);
      await tester.pumpAndSettle();
      expect(
          await key(tester, LogicalKeyboardKey.equal, ctrl: true, shift: true),
          isTrue);
      expect(app.activeEditor!.controller.text, '^water^');
      await settle(tester);
    });

    testWidgets('REGRESSION: a bare = is still a character, not a command',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The bug this codebase has been bitten by twice: a canvas-level
      // binding shadowing the text editors, so a printable key stops being
      // printable. `=` is printable, and the shell now listens for it.
      await pumpShell(tester);
      app.select(para.id, edit: true);
      await tester.pumpAndSettle();
      final before = app.activeEditor!.controller.text;

      final swallowed =
          await key(tester, LogicalKeyboardKey.equal); // no modifiers
      expect(swallowed, isFalse,
          reason: 'a swallowed key never reaches the text input, and the '
              'character is simply never typed');
      expect(app.activeEditor!.controller.text, before,
          reason: 'and it certainly must not format anything');
      expect(app.blocks.where((b) => b.type == BlockType.math), isEmpty,
          reason: 'nor start an equation');

      // And typing really does still land, `=` included.
      await tester.enterText(
          find.byType(EditableText).last, 'a = b and H2O');
      await tester.pumpAndSettle();
      expect(app.activeEditor!.controller.text, 'a = b and H2O');
      await settle(tester);
    });

    testWidgets('Ctrl+= on the canvas still zooms — it is not stolen',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(tester);
      expect(app.editingBlockId, isNull);
      final before = app.canvas.scale;
      await key(tester, LogicalKeyboardKey.equal, ctrl: true);
      expect(app.canvas.scale, greaterThan(before),
          reason: 'the zoom chord lives after the typing early-return, and '
              'the subscript chord lives before it');
    });

    testWidgets('Alt+= starts an equation with the caret in it',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(tester);
      expect(app.blocks.where((b) => b.type == BlockType.math), isEmpty);

      expect(await key(tester, LogicalKeyboardKey.equal, alt: true), isTrue);
      final maths =
          app.blocks.where((b) => b.type == BlockType.math).toList();
      expect(maths, hasLength(1));
      expect(app.editingBlockId, maths.single.id,
          reason: 'ready to type, not merely created');
      await settle(tester);
    });

    testWidgets('Alt+= with words selected makes them maths WHERE THEY ARE',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // **Changed deliberately.** This used to cut the words out of the
      // paragraph and drop a separate equation block below it, so "the area is
      // 1/2bh" became "the area is " with something floating underneath. There
      // was also no other route to an inline equation at all — you had to know
      // to type the dollars. Now the selection is wrapped in place and the
      // live editor draws it as an equation immediately.
      await pumpShell(tester);
      await editWholeWord(tester);

      expect(await key(tester, LogicalKeyboardKey.equal, alt: true), isTrue);
      expect(app.blocks.where((b) => b.type == BlockType.math), isEmpty,
          reason: 'no block: the equation belongs in the sentence');
      final prose = app.blocks
          .where((b) => b.type == BlockType.text)
          .map((b) => b.content['text'] as String? ?? '')
          .join();
      expect(prose, contains(r'$water$'),
          reason: 'the words stay exactly where the student put them');
      await settle(tester);
    });

    testWidgets('Alt+SHIFT+= still lifts them out into a block of their own',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(tester);
      await editWholeWord(tester);

      expect(
          await key(tester, LogicalKeyboardKey.equal, alt: true, shift: true),
          isTrue);
      final maths =
          app.blocks.where((b) => b.type == BlockType.math).toList();
      expect(maths, hasLength(1));
      expect(maths.single.content['linearSource'], 'water');
      // `latex` must be seeded too: an equation whose latex is empty is swept
      // away when its editor closes, so the words would be lost on Escape.
      expect(maths.single.content['latex'], isNot(''));
      // And they are MOVED, not copied.
      final prose = app.blocks
          .where((b) => b.type == BlockType.text)
          .map((b) => b.content['text'] as String? ?? '')
          .join();
      expect(prose.contains('water'), isFalse,
          reason: 'a copy left behind is worse than no shortcut at all');
      await settle(tester);
    });

    testWidgets('Alt+= with the caret in a paragraph stays IN the paragraph',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The reported gap: "Doesnt seem to allow me to do equations inline with
      // a regular text block yet." Inline maths worked — there was simply no
      // way to ask for it that did not involve knowing to type two dollar
      // signs, because Alt+= with nothing selected dropped a separate block
      // below the paragraph.
      await pumpShell(tester);
      await editWholeWord(tester);
      // Collapse the selection: caret in the text, nothing highlighted.
      final ctrl = app.activeEditor!.controller;
      ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
      await tester.pumpAndSettle();

      expect(await key(tester, LogicalKeyboardKey.equal, alt: true), isTrue);
      await tester.pumpAndSettle();
      expect(app.blocks.where((b) => b.type == BlockType.math), isEmpty,
          reason: 'an equation asked for inside a paragraph belongs there');
      final prose = app.blocks
          .where((b) => b.type == BlockType.text)
          .map((b) => b.content['text'] as String? ?? '')
          .join();
      expect(prose, contains(r'$$'),
          reason: 'the empty equation is anchored in the sentence, ready to '
              'be typed into — and two bare dollars do not render as maths, '
              'so nothing shows until there is something to show');
      // Close it the way a student would. Left open, the session's dispose
      // would run the empty sweep DURING binding teardown and arm the save
      // debounce after the last flush - and the sweep itself deserves the
      // assertion: Escape must not leave `$$` in the note.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final after = app.blocks
          .where((b) => b.type == BlockType.text)
          .map((b) => b.content['text'] as String? ?? '')
          .join();
      expect(after.contains(r'$$'), isFalse,
          reason: 'an abandoned empty equation is swept, not saved');
      await settle(tester);
    });

    testWidgets('Ctrl+Z inside an equation goes to the app undo stack',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // Unclaimed, Ctrl+Z reached NOTHING in a block equation — the 700ms undo
    // coalescing written for exactly this was toolbar-only — and in an inline
    // one it reached the host TextField's own history, rewriting the
    // paragraph under the open session (probe-proven corruption).
    await pumpShell(tester);
    await key(tester, LogicalKeyboardKey.equal, alt: true); // block equation
    await tester.pumpAndSettle();
    expect(await key(tester, LogicalKeyboardKey.keyZ, ctrl: true), isTrue,
        reason: 'the shell claims Ctrl+Z while an equation holds the '
            'keyboard, so it can never fall through to a text history');
    expect(app.canRedo, isTrue,
        reason: 'and it really ran the app undo, not a swallow');
    await settle(tester);
  });

  testWidgets('Alt+= inside an equation does not spawn a second one',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(tester);
      await key(tester, LogicalKeyboardKey.equal, alt: true);
      expect(app.blocks.where((b) => b.type == BlockType.math), hasLength(1));
      final first = app.editingBlockId;
      await key(tester, LogicalKeyboardKey.equal, alt: true);
      // The COUNT alone proves nothing: an equation left empty is swept away
      // when its editor closes, so a second one would replace the first and
      // still read as one. The identity is what shows the chord did nothing.
      expect(app.editingBlockId, first,
          reason: 'a second empty equation underneath would be a surprise');
      expect(app.blocks.where((b) => b.type == BlockType.math), hasLength(1));
      await settle(tester);
    });
  });

  // ── The map ────────────────────────────────────────────────────────────
  group('both chords are in the keyboard map', () {
    test('Ctrl+/ can show them, or they do not exist as far as anyone knows',
        () {
      final all = [
        for (final s in keyboardMap)
          for (final b in s.bindings) b.keys
      ];
      expect(all, contains('Ctrl+= / Ctrl+Shift+='));
      expect(all, contains('Alt+='));
    });
  });
}
