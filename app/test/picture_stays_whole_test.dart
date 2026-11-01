// A picture in a box is one thing: deleted whole, kept on its own line, and
// selected by clicking it.
//
// The owner: *"if my cursor is at the end of the image and i press backspace,
// it deletes part of the hash so that the image disapears but the hash
// appears. pressing backspace here should delete the whole thing, id also like
// ideally that when i click on the image then it selects it, so that i can
// copy, cut, or whatever i want easily."*
//
// A picture is `![](sha256:…)` with the line to itself, and it is drawn only
// while that is true — so the same "hash where the picture was" also came from
// typing just after one, deleting a selection so that its line joined the one
// above, and pasting a copied picture into a sentence. A card written into the
// prose (`?[front](back)`) is drawn the same way and broke the same way.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/block_view.dart';
import 'package:openote/editor/live_markdown_controller.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/tokens.dart';

import 'support/sqlite.dart';

const _hash =
    'abababababababababababababababababababababababababababababababab';
const _pic = '![](sha256:$_hash)';

/// Sized, as a real picture is - a 1x1 PNG drawn at its own size is smaller
/// than its resize grip, and a click on it lands on the grip.
const _sized = '![](sha256:$_hash =120x80)';
const _card = '?[osmosis](water crossing a membrane)';

void main() {
  final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwACh'
      'wGA60e6kgAAAABJRU5ErkJggg==');

  LiveMarkdownController make(String text, {int? caret}) {
    final c = LiveMarkdownController(text: text, dark: false)
      ..imageResolver = (_) => png;
    addTearDown(c.dispose);
    if (caret != null) c.selection = TextSelection.collapsed(offset: caret);
    return c;
  }

  /// What the editor does with a key: ask, and apply the answer if any.
  String press(LiveMarkdownController c, {required bool forward}) {
    final next = c.markerAwareDelete(c.value, forward: forward);
    if (next != null) c.value = next;
    return c.text;
  }

  /// Type [s] at the caret, the way the platform delivers it: the whole new
  /// value at once.
  void type(LiveMarkdownController c, String s) {
    final at = c.selection.baseOffset;
    c.value = TextEditingValue(
        text: c.text.replaceRange(at, at, s),
        selection: TextSelection.collapsed(offset: at + s.length));
  }

  group('deleted whole', () {
    test('Backspace at the end of a picture deletes all of it', () {
      final c = make('Intro\n$_pic\nMore', caret: 6 + _pic.length);
      expect(press(c, forward: false), 'Intro\n\nMore',
          reason: 'the picture goes; its line stays, empty');
      expect(c.selection.baseOffset, 6);
    });

    test('and Delete just before one', () {
      final c = make('Intro\n$_pic\nMore', caret: 6);
      expect(press(c, forward: true), 'Intro\n\nMore');
    });

    test('a card standing on its line is the same', () {
      final c = make('$_card\nMore', caret: _card.length);
      expect(press(c, forward: false), '\nMore');
    });

    test('NEGATIVE CONTROL: Backspace in ordinary text deletes one letter', () {
      final c = make('Intro\n$_pic', caret: 5);
      expect(c.markerAwareDelete(c.value, forward: false), isNull,
          reason: 'nothing to say, so the field does its own one-letter delete');
    });
  });

  group('kept on its own line', () {
    test('typing just after a picture goes on the next line', () {
      final c = make(_pic, caret: _pic.length);
      type(c, 'a');
      expect(c.text, '$_pic\na');
      expect(c.selection.baseOffset, _pic.length + 2,
          reason: 'the caret is after what was typed');
      type(c, 'b');
      expect(c.text, '$_pic\nab', reason: 'and the next letter joins it');
    });

    test('typing just before one goes on the line above', () {
      final c = make(_pic, caret: 0);
      type(c, 'a');
      expect(c.text, 'a\n$_pic');
      expect(c.selection.baseOffset, 1,
          reason: 'the caret stays at the end of the new line');
    });

    test('a line cannot join a picture by deleting what is between them', () {
      final c = make('Intro\n$_pic', caret: 6);
      c.value = TextEditingValue(
          text: 'Intro$_pic', selection: const TextSelection.collapsed(offset: 5));
      expect(c.text, 'Intro\n$_pic', reason: 'the picture keeps its line');
      expect(c.selection.baseOffset, 5);
    });

    test('but an empty line above it can go', () {
      final c = make('\n$_pic', caret: 1);
      c.value = const TextEditingValue(
          text: _pic, selection: TextSelection.collapsed(offset: 0));
      expect(c.text, _pic);
    });

    test('a copied picture pasted into a sentence gets a line of its own', () {
      final c = make('Hello world', caret: 6);
      type(c, _pic);
      expect(c.text, 'Hello \n$_pic\nworld');
      expect(c.selection.baseOffset, 'Hello \n'.length + _pic.length,
          reason: 'the caret is just after the picture');
    });

    test('Enter after a picture makes one empty line, not two', () {
      final c = make(_pic, caret: _pic.length);
      type(c, '\n');
      expect(c.text, '$_pic\n');
    });

    test('a card keeps its line too', () {
      final c = make(_card, caret: _card.length);
      type(c, 'x');
      expect(c.text, '$_card\nx');
    });

    test('a note written with a picture mid-sentence is left as it was', () {
      // An import, or an older build. Nothing here may rewrite a note just
      // because it was opened or typed in somewhere else.
      const old = 'See $_pic here';
      final c = make('$old\nnext', caret: old.length + 5);
      type(c, '!');
      expect(c.text, '$old\nnext!');
    });

    test('resizing a picture still rewrites its size', () {
      final c = make('Intro\n$_pic', caret: 0);
      c.resizeImageLine(6, 6 + _pic.length, _pic, 120, 80);
      expect(c.text, 'Intro\n![](sha256:$_hash =120x80)');
    });
  });

  group('selected by clicking it', () {
    Future<LiveMarkdownController> field(WidgetTester t, String text) async {
      final c = make(text);
      const style = TextStyle(fontSize: 14, height: 1.5);
      await t.pumpWidget(MaterialApp(
        localizationsDelegates: kOnoteLocalizations,
        supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              child: TextField(
                controller: c,
                maxLines: null,
                style: style,
                strutStyle:
                    StrutStyle.fromTextStyle(style, forceStrutHeight: false),
                decoration: OnoteInput.bare,
              ),
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
      return c;
    }

    testWidgets('a click on a picture selects all of it', (t) async {
      final c = await field(t, 'Intro\n$_sized\nMore');
      await t.tap(find.byType(Image));
      await t.pumpAndSettle();
      expect(c.selection.start, 6);
      expect(c.selection.end, 6 + _sized.length);
    });

    testWidgets('and it is drawn selected', (t) async {
      final c = await field(t, 'Intro\n$_sized\nMore');
      bool tinted() => t
          .widgetList<Container>(find.ancestor(
              of: find.byType(Image), matching: find.byType(Container)))
          .any((w) =>
              w.foregroundDecoration is BoxDecoration &&
              (w.foregroundDecoration! as BoxDecoration).color != null);
      expect(tinted(), isFalse, reason: 'precondition');
      await t.tap(find.byType(Image));
      await t.pumpAndSettle();
      expect(tinted(), isTrue,
          reason: 'a selection highlight is painted under a picture, where '
              'the picture covers it — so it has to say so itself');
      c.selection = const TextSelection.collapsed(offset: 0);
      await t.pumpAndSettle();
      expect(tinted(), isFalse);
    });

    testWidgets('then Delete takes it, as it would any selection', (t) async {
      final c = await field(t, 'Intro\n$_sized\nMore');
      await t.tap(find.byType(Image));
      await t.pumpAndSettle();
      c.value = c.value.replaced(c.selection, '');
      expect(c.text, 'Intro\n\nMore');
    });
  });

  group('the first click into a closed box', () {
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());

    testWidgets('selects a picture it lands on', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      late Directory tmp;
      late Repository repo;
      late AppState app;
      await t.runAsync(() async {
        AppState.syncLogEnabled = false;
        tmp = Directory.systemTemp.createTempSync('onote_pic_click_');
        repo = await Repository.openAt(tmp);
        final nb = await repo.createNotebook('C');
        app = AppState(repo)
          ..notebookId = nb.id
          ..spellCheckEnabled = false;
        app.reloadNodes();
      });
      addTearDown(() {
        AppState.syncLogEnabled = true;
        app.cancelPendingSave();
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      final hash = app.tryAddBlob(png, 'image/png')!;
      final ref = '![](sha256:$hash =120x80)';
      final b = Block(
          id: 'b1',
          type: BlockType.text,
          x: 0,
          y: 0,
          w: 420,
          content: {'text': 'Intro\n$ref\nMore'});
      app.blocks.add(b);
      t.view.physicalSize = const Size(1200, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        localizationsDelegates: kOnoteLocalizations,
        supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: app,
            builder: (_, __) => Stack(
                children: [BlockView(block: b, app: app, controller: app.canvas)]),
          ),
        ),
      ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(find.byType(Image), findsOneWidget, reason: 'drawn, read-only');

      await t.tapAt(t.getCenter(find.byType(Image)));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 20));
      }
      expect(app.editingBlockId, 'b1');
      final c = t.widget<TextField>(find.byType(TextField)).controller!;
      expect(c.selection.start, 6, reason: 'the picture, selected');
      expect(c.selection.end, 6 + ref.length);

      app.editingBlockId = null;
      await t.pumpWidget(const SizedBox());
      app.cancelPendingSave();
      await t.pump(const Duration(seconds: 2));
    });
  });
}
