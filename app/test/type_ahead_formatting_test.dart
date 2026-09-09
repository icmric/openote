// Ctrl+B sets the style for what you type NEXT.
//
// The owner's words: "if i use a shortcut to apply text styles (i.e. bold,
// italics, etc) it will apply it to the previous word, rather than changing
// the style of the text i type after setting the style (like in a normal
// text/WYSIWYG editor), which is the behavior id like."
//
// Ctrl+B used to format the word the caret happened to be sitting in, so
// finishing a word and pressing Ctrl+B bolded the word you had just typed
// instead of the one you were about to. Now nothing is written until the
// next thing is typed, and that is what gets wrapped.
//
// These are the END-TO-END half: they drive the real field, so the
// input formatter that does the wrapping is genuinely in the path. The
// rules it applies (which marks, where the markers may sit) are unit-tested
// in inline_formatting_test.dart against AppState directly.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/block_view.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;
  late Block block;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_ahead_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('A');
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
      content: {'text': 'note ', 'autoWidth': false},
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

  /// Open the block for editing with the caret at [caret], and hand back the
  /// live controller.
  Future<TextEditingController> open(WidgetTester t, int caret) async {
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
    final c = app.activeEditor!.controller;
    c.selection = TextSelection.collapsed(offset: caret);
    await t.pump();
    return c;
  }

  /// Type [s] AT THE CARET, the way the platform delivers a keystroke —
  /// `enterText` would replace the whole field and always land at the end,
  /// which is exactly the position these tests are about.
  Future<void> type(WidgetTester t, TextEditingController c, String s) async {
    final at = c.selection.baseOffset;
    t.testTextInput.updateEditingValue(TextEditingValue(
      text: c.text.replaceRange(at, at, s),
      selection: TextSelection.collapsed(offset: at + s.length),
    ));
    await t.pump();
  }

  testWidgets('Ctrl+B then typing bolds what is typed, not what was there',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final c = await open(t, 5); // caret after "note "
    app.wrapSelection('**');
    await t.pump();
    expect(c.text, 'note ', reason: 'the chord alone writes nothing');

    await type(t, c, 'b');
    expect(c.text, 'note **b**');

    // And the run keeps growing, because the caret was left inside it — no
    // second trip through the queue needed.
    await type(t, c, 'i');
    await type(t, c, 'g');
    expect(c.text, 'note **big**');
    expect(app.pendingMarks, isEmpty);
    app.cancelPendingSave();
  });

  testWidgets('Backspace then takes the letter, not the marker', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final c = await open(t, 5);
    app.wrapSelection('**');
    await t.pump();
    for (final ch in ['b', 'i', 'g']) {
      await type(t, c, ch);
    }
    expect(c.text, 'note **big**');

    await t.sendKeyEvent(LogicalKeyboardKey.backspace);
    await t.pump();
    expect(c.text, 'note **bi**',
        reason: 'the closing markers cannot be seen, so eating one would '
            'un-bold the word AND print two asterisks');
    app.cancelPendingSave();
  });

  testWidgets('the word already typed is left alone', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // The caret sits against the end of a word, which is where the old
    // behaviour reached back and bolded it.
    final c = await open(t, 4); // "note|"
    app.wrapSelection('**');
    await t.pump();
    expect(c.text, 'note ');
    await type(t, c, 'X');
    expect(c.text, 'note**X** ');
    app.cancelPendingSave();
  });

  testWidgets('moving the caret away cancels the queue', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final c = await open(t, 5);
    app.wrapSelection('**');
    await t.pump();
    expect(app.pendingMarks, isNotEmpty);

    c.selection = const TextSelection.collapsed(offset: 2);
    await t.pump();
    expect(app.pendingMarks, isEmpty,
        reason: 'the queue belonged to a spot the caret has left');

    await type(t, c, 'x');
    expect(c.text, 'noxte ', reason: 'plain text, no markers');
    app.cancelPendingSave();
  });

  testWidgets('a word composed by an IME is bolded whole, once committed',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // How a Japanese or Chinese keyboard actually delivers a word: the
    // characters go INTO the buffer with a composing range around them and
    // are replaced as the student refines them, then committed. Wrapping a
    // preview would put markers around text about to be thrown away, and
    // treating the moved caret as "the caret left" would silently drop the
    // style for every student who does not type in English.
    final c = await open(t, 5);
    app.wrapSelection('**');
    await t.pump();

    void compose(String s, {bool composing = true}) {
      t.testTextInput.updateEditingValue(TextEditingValue(
        text: 'note $s',
        selection: TextSelection.collapsed(offset: 5 + s.length),
        composing:
            composing ? TextRange(start: 5, end: 5 + s.length) : TextRange.empty,
      ));
    }

    compose('こ');
    await t.pump();
    expect(c.text, 'note こ', reason: 'the preview is left alone');
    expect(app.pendingMarks, isNotEmpty, reason: 'and the queue survives it');

    compose('こん');
    await t.pump();
    compose('今日は');
    await t.pump();
    expect(c.text, 'note 今日は');

    // Committed.
    compose('今日は', composing: false);
    await t.pump();
    expect(c.text, 'note **今日は**',
        reason: 'the finished word is wrapped, all of it, once');
    app.cancelPendingSave();
  });

  testWidgets('a space first still bolds the word after it', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final c = await open(t, 5);
    app.wrapSelection('**');
    await t.pump();
    await type(t, c, ' ');
    expect(c.text, 'note  ', reason: '`** **` matches nothing');
    await type(t, c, 'z');
    expect(c.text, 'note  **z**');
    app.cancelPendingSave();
  });
}
