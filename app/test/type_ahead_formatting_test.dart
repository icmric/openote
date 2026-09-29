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
import 'package:openote/markdown/md_syntax.dart';
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

  testWidgets('and a space at the end of it does not print the asterisks',
      (t) async {
    // The owner: *"if i bold (or otherwise style) some text then press space
    // at the end, it breaks the interpreter and shows the `**`, that is not
    // what i want at all. It should never under any circumstances show the md
    // styling chars after the style has been applied."*
    //
    // The caret is parked INSIDE the closing markers on purpose — the test
    // above is what that buys. But it means the space bar aims straight at
    // the one place a marker may not sit: CommonMark's flanking rule forbids
    // `**big **`, so the run stopped being a run and four asterisks appeared
    // in the middle of a sentence.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final c = await open(t, 5);
    app.wrapSelection('**');
    await t.pump();
    for (final ch in ['b', 'i', 'g']) {
      await type(t, c, ch);
    }
    expect(c.text, 'note **big**');

    await type(t, c, ' ');

    expect(c.text, 'note **big** ',
        reason: 'the space goes to the other side of the marker, which is '
            'where a word processor puts it and the only place Markdown can '
            'hold it — `**big **` is not expressible as bold at all');
    expect(c.selection.baseOffset, 13,
        reason: 'and the caret follows the space it just typed');

    // The thing the owner actually sees: still one bold run, no loose marks.
    final runs = [
      for (final m in mdInlineRe.allMatches(c.text))
        if (classifyInline(m).kind == MdInline.bold) m
    ];
    expect(runs, hasLength(1));
    expect(classifyInline(runs.single).inner, 'big');

    app.cancelPendingSave();
  });

  testWidgets('and the bold carries on through it, word after word', (t) async {
    // The owner, on the first cut of the fix: *"if i bold and press space now
    // it just doesnt keep the bolding, so if i tried to type multiple words in
    // bold it wouldnt."*
    //
    // Quite right. Moving the space out of the run stops the run, so the space
    // has to re-arm the same queue Ctrl+B uses. The next word is then wrapped
    // as its own run and the two are folded back into one, which is why the
    // buffer below holds a single pair of markers rather than a pair per word.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final c = await open(t, 5);
    app.wrapSelection('**');
    await t.pump();
    for (final ch in ['b', 'i', 'g']) {
      await type(t, c, ch);
    }

    await type(t, c, ' ');
    expect(app.pendingMarks, {'**'},
        reason: 'the space says "still bold", because that is what the '
            'student was doing when they pressed it');

    for (final ch in ['r', 'e', 'd']) {
      await type(t, c, ch);
    }
    expect(c.text, 'note **big red**',
        reason: 'one run, not `**big** **red**` — they render the same, and '
            'the tidier one is what somebody would have typed');

    // A third word needs no further help: the caret is back inside the run.
    await type(t, c, ' ');
    for (final ch in ['o', 'x']) {
      await type(t, c, ch);
    }
    expect(c.text, 'note **big red ox**');

    final runs = [
      for (final m in mdInlineRe.allMatches(c.text))
        if (classifyInline(m).kind == MdInline.bold) m
    ];
    expect(runs, hasLength(1));
    expect(classifyInline(runs.single).inner, 'big red ox');
    app.cancelPendingSave();
  });

  testWidgets('back-selecting a bold word deletes all of it, markers included',
      (t) async {
    // The owner: *"if i back select a bold word it will remove it but leave
    // ** at the start, so it doesnt remove it all, you need to ensure that it
    // never disconnects them."*
    //
    // `markerAwareDelete` already answers this for a Backspace at a marker
    // edge, but it takes a COLLAPSED caret only and returns null for a
    // selection — which then falls through to the field's own delete, and the
    // field cannot see markers.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final c = await open(t, 5);
    app.wrapSelection('**');
    await t.pump();
    for (final ch in ['b', 'i', 'g']) {
      await type(t, c, ch);
    }
    expect(c.text, 'note **big**');

    // Back over the word, the way a drag right-to-left or Shift+Left reports
    // it: from the end of what can be seen to the start of it.
    c.selection = const TextSelection(baseOffset: 12, extentOffset: 7);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.backspace);
    await t.pump();

    expect(c.text, 'note ',
        reason: 'all of it, markers included — not `note **`');
    expect(c.selection.baseOffset, 5);
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

  testWidgets('the chord again at the end STOPS bolding, it does not unbold',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // Reported: "pressing the hotkey again after typing out the text will
    // unbold it, which is wrong." Typing a bold word leaves the caret against
    // the closing marker, and pressing the chord there is how everybody turns
    // bold off for what comes NEXT.
    final c = await open(t, 5);
    app.wrapSelection('**');
    await t.pump();
    for (final ch in ['b', 'i', 'g']) {
      await type(t, c, ch);
    }
    expect(c.text, 'note **big**');

    app.wrapSelection('**');
    await t.pump();
    expect(c.text, 'note **big**', reason: 'the word keeps its bold');
    expect(app.marksAtCaret(), isNot(contains(MdInline.bold)),
        reason: 'and the toolbar says bold is off now');

    // What comes next is plain, and lands after the word rather than in it.
    await type(t, c, '!');
    expect(c.text, 'note **big**!');
    app.cancelPendingSave();
  });

  testWidgets('but inside the word it still takes the bold off', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // The markers cannot be seen, so this is the only way to un-format
    // without selecting first. It must survive the fix above.
    final c = await open(t, 5);
    app.wrapSelection('**');
    await t.pump();
    for (final ch in ['b', 'i', 'g']) {
      await type(t, c, ch);
    }
    c.selection = const TextSelection.collapsed(offset: 8); // inside "big"
    await t.pump();
    app.wrapSelection('**');
    await t.pump();
    expect(c.text, 'note big');
    app.cancelPendingSave();
  });

  testWidgets('the toolbar lights up the moment the chord is pressed',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // Nothing is written until you type, so the button going on is the only
    // thing that can say the next word will be bold.
    await open(t, 5);
    expect(app.marksAtCaret(), isEmpty);
    app.wrapSelection('**');
    await t.pump();
    expect(app.marksAtCaret(), contains(MdInline.bold));
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
