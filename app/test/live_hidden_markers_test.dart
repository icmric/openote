// Formatting markers must stop reappearing under the caret.
//
// The owner's words: "once a word has had md chars put around it AND the
// cursor has moved off it, i dont want them to pop up again. While yes some
// users will be expecting it, the vast majority wont know what markdown even
// is, so if they click on a bold word and suddenly **** appears around it,
// this will be quite offputting."
//
// That is a change of character — from "live Markdown" towards "rich text that
// happens to save as Markdown" — and it moves work onto three other places,
// which is what most of this file tests:
//
//   * you can no longer delete a marker you cannot see, so Ctrl+B has to be
//     able to un-format from a bare caret inside the run;
//   * arrowing across an invisible marker used to be a keystroke that did
//     nothing visible, so the caret is stepped over it;
//   * Backspace and Delete at the edges of a run used to eat half a marker,
//     leaving `**bold*` — a word that silently un-bolds AND prints asterisks.
//
// The markers themselves are still LAID OUT, at 0.01px, which is the reason
// none of this needs new caret arithmetic: source offsets and paragraph
// positions have never diverged and still do not.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/block_view.dart';
import 'package:openote/editor/live_markdown_controller.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';

import 'support/sqlite.dart';

/// Every (text, fontSize) leaf the controller draws, in order.
List<({String text, double size})> _leaves(TextSpan root) {
  final out = <({String text, double size})>[];
  void walk(InlineSpan s) {
    if (s is TextSpan) {
      final t = s.text;
      if (t != null && t.isNotEmpty) {
        out.add((text: t, size: s.style?.fontSize ?? 14));
      }
      s.children?.forEach(walk);
    }
  }

  walk(root);
  return out;
}

/// A marker span is drawn at a hairline; anything a reader can see is not.
bool _isHidden(({String text, double size}) leaf) => leaf.size <= 1;

TextSpan _render(WidgetTester t, LiveMarkdownController c) => c.buildTextSpan(
    context: t.element(find.byType(EditableText)),
    style: const TextStyle(fontSize: 15, height: 1.5, letterSpacing: 0.25),
    withComposing: false);

Future<LiveMarkdownController> _pumpField(WidgetTester t, String text,
    {int? caret}) async {
  const style = TextStyle(fontSize: 15, height: 1.5, letterSpacing: 0.25);
  final c = LiveMarkdownController(text: text, dark: false);
  if (caret != null) c.selection = TextSelection.collapsed(offset: caret);
  await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
    theme: onoteTheme(Brightness.light),
    home: Scaffold(
      body: SizedBox(
        width: 600,
        child: TextField(controller: c, maxLines: null, style: style),
      ),
    ),
  ));
  await t.pumpAndSettle();
  return c;
}

void main() {
  group('the markers stay hidden, whatever the caret is doing', () {
    // One case per construct the editor styles, because the reveal was a
    // single shared line and a partial fix would be indistinguishable from
    // none until somebody used italics.
    const cases = {
      '**bold**': '**',
      '*ital*': '*',
      '~~gone~~': '~~',
      '`code`': '`',
      '==hot==': '==',
      '++under++': '++',
      '***both***': '***',
    };
    for (final e in cases.entries) {
      testWidgets('${e.key} with the caret inside it', (t) async {
        final c = await _pumpField(t, 'a ${e.key} b',
            caret: 2 + e.value.length + 1); // inside the styled word
        final marks =
            _leaves(_render(t, c)).where((l) => l.text.contains(e.value[0]));
        expect(marks, isNotEmpty, reason: 'precondition: markers are emitted');
        for (final m in marks) {
          expect(_isHidden(m), isTrue,
              reason: 'the caret revealed "${m.text}" at ${m.size}px');
        }
      });
    }

    testWidgets('a selection dragged across the run does not reveal them',
        (t) async {
      final c = await _pumpField(t, 'a **bold** b');
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 12);
      await t.pump();
      for (final l in _leaves(_render(t, c))) {
        if (l.text.contains('*')) expect(_isHidden(l), isTrue);
      }
    });

    testWidgets('a link still shows its source — it has no live form yet',
        (t) async {
      // Deliberately NOT hidden: zero-width markers would hide half a URL and
      // leave the caret walking through characters nobody can see.
      final c = await _pumpField(t, 'see [docs](https://x.test) now', caret: 6);
      final visible = _leaves(_render(t, c))
          .where((l) => !_isHidden(l))
          .map((l) => l.text)
          .join();
      expect(visible, contains('https://x.test'));
    });
  });

  group('typing the markers by hand still works', () {
    testWidgets('**bold** styles the word the moment it closes', (t) async {
      final c = await _pumpField(t, '');
      await t.tap(find.byType(TextField));
      await t.pumpAndSettle();
      // Character by character, the way somebody who knows Markdown types.
      for (final ch in '**bold**'.split('')) {
        await t.enterText(find.byType(TextField), c.text + ch);
        await t.pump();
      }
      expect(c.text, '**bold**', reason: 'the buffer keeps what was typed');

      final leaves = _leaves(_render(t, c));
      expect(leaves.where((l) => l.text == 'bold' && !_isHidden(l)), hasLength(1),
          reason: 'the word is styled, not literal');
      for (final l in leaves.where((l) => l.text.contains('*'))) {
        expect(_isHidden(l), isTrue, reason: 'the markers were consumed');
      }
    });

    testWidgets('a half-typed run stays literal so it can be finished',
        (t) async {
      final c = await _pumpField(t, '**bold', caret: 6);
      final visible = _leaves(_render(t, c))
          .where((l) => !_isHidden(l))
          .map((l) => l.text)
          .join();
      expect(visible, '**bold',
          reason: 'hiding an unclosed marker would hide the user\'s own typing');
    });
  });

  group('the caret steps over an invisible marker', () {
    // Two presses of Left that move the caret nowhere visible is exactly the
    // kind of thing the owner objected to. The markers are still there in the
    // buffer, so the caret is snapped past them in the direction of travel.
    testWidgets('Left from just after a run lands at the end of the word',
        (t) async {
      final c = await _pumpField(t, '**bold** x', caret: 8);
      await t.tap(find.byType(TextField));
      await t.pumpAndSettle();
      c.selection = const TextSelection.collapsed(offset: 8);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pump();
      expect(c.selection.baseOffset, 6,
          reason: 'offset 7 is between the two closing asterisks');
    });

    testWidgets('Right from the end of the word lands past the run', (t) async {
      final c = await _pumpField(t, '**bold** x');
      await t.tap(find.byType(TextField));
      await t.pumpAndSettle();
      c.selection = const TextSelection.collapsed(offset: 6);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
      expect(c.selection.baseOffset, 8);
    });

    testWidgets('Right off the front of a run lands on the first letter',
        (t) async {
      final c = await _pumpField(t, '**bold** x');
      await t.tap(find.byType(TextField));
      await t.pumpAndSettle();
      c.selection = const TextSelection.collapsed(offset: 0);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
      expect(c.selection.baseOffset, 2);
    });

    testWidgets('a keystroke that CHANGES the text is never snapped',
        (t) async {
      // The caret has to stay exactly where an edit put it, or a half-typed
      // `**bold*` would have its caret yanked away from the character the user
      // is about to type.
      final c = await _pumpField(t, '');
      await t.tap(find.byType(TextField));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '**bold**');
      await t.pump();
      expect(c.selection.baseOffset, 8);
    });
  });

  group('editing at the edge of a run leaves no half-marker', () {
    late LiveMarkdownController c;
    setUp(() => c = LiveMarkdownController(text: '', dark: false));
    tearDown(() => c.dispose());

    TextEditingValue at(String text, int offset) => TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: offset));

    test('Backspace just past a run deletes the last LETTER, not a marker', () {
      c.text = '**bold**';
      // The default deletes offset 7 and leaves `**bold*`: the word silently
      // un-bolds and two asterisks appear out of nowhere.
      final next = c.markerAwareDelete(at('**bold**', 8), forward: false);
      expect(next?.text, '**bol**');
      expect(next?.selection.baseOffset, 5,
          reason: 'still inside the run, so holding Backspace keeps eating it');
    });

    test('emptying a run takes its markers with it', () {
      c.text = 'a **b** c';
      final next = c.markerAwareDelete(at('a **b** c', 7), forward: false);
      expect(next?.text, 'a  c',
          reason: '`****` is four asterisks no renderer matches');
      expect(next?.selection.baseOffset, 2);
    });

    test('Backspace at the start of the word deletes what is before the run',
        () {
      c.text = 'hi **bold**';
      // Default: eats the second `*` of the opening marker. Word-processor
      // behaviour: joins the bold word to what precedes it.
      final next = c.markerAwareDelete(at('hi **bold**', 5), forward: false);
      expect(next?.text, 'hi**bold**');
      expect(next?.selection.baseOffset, 2);
    });

    test('Delete at the front of a run eats the first letter', () {
      c.text = '**bold** x';
      final next = c.markerAwareDelete(at('**bold** x', 0), forward: true);
      expect(next?.text, '**old** x');
      expect(next?.selection.baseOffset, 0);
    });

    test('Delete at the end of the word eats what FOLLOWS the run', () {
      c.text = '**bold** x';
      final next = c.markerAwareDelete(at('**bold** x', 6), forward: true);
      expect(next?.text, '**bold**x');
      expect(next?.selection.baseOffset, 6);
    });

    test('mid-word, the platform is already right and is left alone', () {
      c.text = '**bold**';
      expect(c.markerAwareDelete(at('**bold**', 4), forward: false), isNull);
      expect(c.markerAwareDelete(at('**bold**', 4), forward: true), isNull);
    });

    test('an emoji at the edge is not torn in half', () {
      const s = '**ok🙂**';
      c.text = s;
      final next = c.markerAwareDelete(at(s, s.length), forward: false);
      expect(next?.text, '**ok**',
          reason: 'a surrogate pair is one character to the person typing');
    });

  });

  group('and the engine really calls it', () {
    // Built in setUp, NOT in the test body: `testWidgets` runs inside a
    // fake-async zone where real file I/O never completes, so awaiting
    // Repository.openAt in there hangs forever.
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());

    late Repository repo;
    late Directory tmp;
    late AppState app;
    late Block block;

    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_marks_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('M');
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
        w: 300,
        content: {'text': '**bold**', 'autoWidth': false},
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

    testWidgets('Backspace past a bold word takes the letter, not the marker',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
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

      final ctrl = app.activeEditor!.controller;
      ctrl.selection = const TextSelection.collapsed(offset: 8);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.backspace);
      await t.pump();
      expect(ctrl.text, '**bol**');
      app.cancelPendingSave();
    });
  });

  group('formatting can still be removed without seeing the markers', () {
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());

    late Repository repo;
    late Directory tmp;
    late AppState app;
    late TextEditingController c;

    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_unfmt_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('U');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      await app
          .selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
      final block =
          Block(type: BlockType.text, x: 0, y: 0, content: {'text': ''});
      app.addBlock(block, recordUndo: false);
      c = LiveMarkdownController(text: '', dark: false);
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

    test('Ctrl+B from a bare caret inside a bold word un-bolds it', () {
      if (!haveSqlite) return;
      // This is the ONLY way out now, so it is load-bearing rather than a
      // convenience: there are no visible asterisks left to delete.
      c.value = const TextEditingValue(
          text: 'make this bold please',
          selection: TextSelection.collapsed(offset: 13));
      app.wrapSelection('**');
      expect(c.text, 'make this **bold** please');
      c.selection = const TextSelection.collapsed(offset: 14);
      app.wrapSelection('**');
      expect(c.text, 'make this bold please');
    });

    test('and the caret snapping does not get in its way', () {
      if (!haveSqlite) return;
      // The snap only ever moves a caret that is BETWEEN marker characters;
      // if it also fired on the offsets wrapSelection sets, the toggle would
      // act on the wrong run.
      c.value = const TextEditingValue(
          text: 'a **one** and **two** b',
          selection: TextSelection.collapsed(offset: 17));
      app.wrapSelection('**');
      expect(c.text, 'a **one** and two b');
    });
  });

  group('what the caret logic thinks is hidden is what is drawn', () {
    // The renderer and the caret logic scan the same grammar twice. If they
    // ever disagree, the caret would be snapped over something visible or
    // walk through something invisible — so the two scans are compared
    // directly, over every line shape that changes where the scan starts.
    const corpus = [
      'plain **bold** and *ital* text',
      '- a bullet with `code` in it',
      '- [x] a done task with ~~strike~~',
      '## heading with ==highlight==',
      '> quoted ++under++ line',
      '1. ordered H~2~O and x^2^',
      'a [link](https://x.test) and **bold**',
      '{{#ff0000 red}} and plain',
      '  - nested *one* two',
    ];
    for (final line in corpus) {
      testWidgets('«$line»', (t) async {
        final c = await _pumpField(t, line);
        final drawn = <int>{};
        var off = 0;
        void walk(InlineSpan s) {
          if (s is WidgetSpan) {
            // A placeholder stands for exactly ONE code unit of source — that
            // is the whole invariant this editor rests on — so it has to be
            // counted or every offset after a bullet is out by one.
            off += 1;
            return;
          }
          if (s is! TextSpan) return;
          final txt = s.text;
          if (txt != null) {
            if ((s.style?.fontSize ?? 14) <= 1) {
              for (var i = 0; i < txt.length; i++) {
                drawn.add(off + i);
              }
            }
            off += txt.length;
          }
          s.children?.forEach(walk);
        }

        // The gutter placeholder and the hidden prefix that trails it are not
        // inline markers, so they are excluded from both sides.
        final tree = _render(t, c);
        walk(tree);
        final claimed = <int>{
          for (final r in c.hiddenMarkerRanges())
            for (var i = r.start; i < r.end; i++) i
        };
        expect(claimed, isNotEmpty,
            reason: 'every line in the corpus carries markers; a scanner that '
                'found none would pass the next check vacuously');
        // One direction only, deliberately: the tree ALSO hides a list line's
        // literal prefix and the source behind a picture, which are not inline
        // markers and which the caret must be free to walk.
        expect(claimed.difference(drawn), isEmpty,
            reason: 'the caret would be snapped over something visible');
      });
    }
  });
}
