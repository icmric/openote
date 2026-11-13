// The automatic fixes in the real editor: typed into the live field, taken back
// with Backspace, and silent in any language but English.
//
// Typed through `testTextInput` one character at a time, because that is the
// path a keyboard takes (the field sees an update from the input method and runs
// its formatters), where `enterText` replaces the whole value and would never
// look like a keystroke.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/core/onote_text.dart';
import 'package:openote/editor/text_block_view.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  final have = OnoteText.available;

  Future<AppState> newApp(WidgetTester t, Locale system) async {
    late AppState app;
    late Repository repo;
    final tmp = Directory.systemTemp.createTempSync('onote_autofix_');
    addTearDown(() {
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await t.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Autofix');
      app = AppState(repo)..notebookId = nb.id;
      // Load the checker for real, off the test's fake clock, as the editor
      // does in the background.
      await OnoteText.warmUp(EnglishDialect.australian);
    });
    app.systemLocale = () => system;
    return app;
  }

  /// A block in edit mode, its field focused, caret at the end.
  Future<TextEditingController> edit(
      WidgetTester t, AppState app, String text) async {
    final b = Block(
        id: 'b1',
        type: BlockType.text,
        x: 0,
        y: 0,
        w: 300,
        content: {'text': text, 'autoWidth': false});
    app.editingBlockId = 'b1';
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: Scaffold(
          body: SizedBox(width: 300, child: TextBlockView(block: b, app: app))),
    ));
    await t.showKeyboard(find.byType(TextField));
    final c = app.activeEditor!.controller;
    t.testTextInput.updateEditingValue(TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length)));
    await t.pump();
    return c;
  }

  /// Tear the editor down and let the save's debounce timer run out, or the
  /// test ends with a timer pending.
  Future<void> settle(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  }

  /// One character typed at the end, as a keyboard delivers it.
  Future<void> type(WidgetTester t, TextEditingController c, String ch) async {
    final v = c.value;
    final o = v.selection.baseOffset;
    t.testTextInput.updateEditingValue(TextEditingValue(
        text: v.text.replaceRange(o, o, ch),
        selection: TextSelection.collapsed(offset: o + ch.length)));
    await t.pump();
  }

  testWidgets('typing a sure typo and a space fixes it, in English',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(t, const Locale('en', 'AU'));
    final c = await edit(t, app, 'say teh');
    await type(t, c, ' ');
    expect(c.text, 'say the ');
    expect(c.selection.baseOffset, 8);
    await settle(t);
  }, skip: !have);

  testWidgets('and a sentence gets its capital, and a lone i', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(t, const Locale('en', 'AU'));
    final c = await edit(t, app, 'hello');
    await type(t, c, ' ');
    expect(c.text, 'Hello ');
    for (final ch in "then i".split("")) {
      await type(t, c, ch);
    }
    await type(t, c, ' ');
    expect(c.text, 'Hello then I ');
    await settle(t);
  }, skip: !have);

  testWidgets('Backspace straight after a fix takes it back, once and for good',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(t, const Locale('en', 'AU'));
    final c = await edit(t, app, 'say teh');
    await type(t, c, ' ');
    expect(c.text, 'say the ');

    await t.sendKeyEvent(LogicalKeyboardKey.backspace);
    await t.pump();
    expect(c.text, 'say teh ', reason: 'the word is back as typed');
    expect(c.selection.baseOffset, 8, reason: 'and the space is kept');

    // Retype the space: the person said they meant it, so it is not fixed again.
    await t.sendKeyEvent(LogicalKeyboardKey.backspace);
    await t.pump();
    expect(c.text, 'say teh');
    await type(t, c, ' ');
    expect(c.text, 'say teh ');
    await settle(t);
  }, skip: !have);

  testWidgets('Backspace later is an ordinary Backspace', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(t, const Locale('en', 'AU'));
    final c = await edit(t, app, 'say teh');
    await type(t, c, ' ');
    await type(t, c, 'x');
    expect(c.text, 'say the x');
    await t.sendKeyEvent(LogicalKeyboardKey.backspace);
    await t.pump();
    expect(c.text, 'say the ', reason: 'it deleted the x and nothing else');
    await settle(t);
  }, skip: !have);

  testWidgets('nothing happens in a language that is not English', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    for (final loc in const [
      Locale('de', 'DE'),
      Locale('fr', 'FR'),
      Locale('es', 'ES'),
      Locale('it', 'IT'),
      Locale('pt', 'BR'),
      Locale('zh', 'CN'),
    ]) {
      final app = await newApp(t, loc);
      final c = await edit(t, app, 'say teh');
      await type(t, c, ' ');
      expect(c.text, 'say teh ', reason: 'no fix on a $loc computer');
      await settle(t);
    }
    await settle(t);
  }, skip: !have);

  testWidgets('and the person can say they write English on a German computer',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(t, const Locale('de', 'DE'));
    app.spellLanguage = 'en-AU';
    final c = await edit(t, app, 'say teh');
    await type(t, c, ' ');
    expect(c.text, 'say the ');
    await settle(t);
  }, skip: !have);

  testWidgets('each switch turns its own fix off', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    var app = await newApp(t, const Locale('en', 'AU'));
    app.autoCorrectEnabled = false;
    var c = await edit(t, app, 'say teh');
    await type(t, c, ' ');
    expect(c.text, 'say teh ', reason: 'typo fixing is off');

    await settle(t);
    app = await newApp(t, const Locale('en', 'AU'));
    app.autoCapitalizeEnabled = false;
    c = await edit(t, app, 'hello');
    await type(t, c, ' ');
    expect(c.text, 'hello ', reason: 'capitals are off');
    await settle(t);
  }, skip: !have);

  // ── Missing apostrophes, and Ctrl+Z (reported on the first real try) ──────
  //
  // These need no native library: the answer comes from a list, so they run
  // everywhere the editor does.

  testWidgets('a missing apostrophe is put in as the word is finished',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(t, const Locale('en', 'AU'));
    final c = await edit(t, app, 'I think we dont');
    await type(t, c, ' ');
    expect(c.text, "I think we don't ");
    for (final ch in 'and im sure'.split('')) {
      await type(t, c, ch);
    }
    expect(c.text, "I think we don't and I'm sure");
    await settle(t);
  });

  testWidgets('and its capital, at the start of a sentence', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(t, const Locale('en', 'AU'));
    final c = await edit(t, app, 'dont');
    await type(t, c, ' ');
    expect(c.text, "Don't ");
    await settle(t);
  });

  testWidgets('a word that could be wrong is left exactly as typed',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(t, const Locale('en', 'AU'));
    // `its`, `well` and `ill` are words; `alot`'s nearest dictionary word was
    // once "alto". None of them is changed behind the person's back.
    final c = await edit(t, app, 'its well ill');
    await type(t, c, ' ');
    expect(c.text, 'its well ill ');
    await settle(t);
  });

  testWidgets('Ctrl+Z straight after a fix takes back just the fix',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(t, const Locale('en', 'AU'));
    final c = await edit(t, app, 'we dont');
    await type(t, c, ' ');
    expect(c.text, "we don't ");

    // The app's own undo, which is what Ctrl+Z calls in a box.
    app.undo();
    await t.pump();
    expect(c.text, 'we dont ',
        reason: 'the word is back as typed, not the whole burst gone');
    expect(c.selection.baseOffset, 8, reason: 'with the caret where it was');

    // And it is not fixed again when the person carries on.
    await type(t, c, 'x');
    expect(c.text, 'we dont x');
    await settle(t);
  });

  testWidgets('Ctrl+Z after more typing is the ordinary undo', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(t, const Locale('en', 'AU'));
    final c = await edit(t, app, 'we dont');
    await type(t, c, ' ');
    await type(t, c, 'x');
    expect(c.text, "we don't x");
    expect(app.autoFixUndo, isNotNull);
    // The hook declines (the text has moved on) and is spent; the stack
    // carries on as it always did.
    app.undo();
    expect(app.autoFixUndo, isNull);
    expect(c.text, isNot('we dont x'),
        reason: 'the fix is not quietly reverted from under later typing');
    await settle(t);
  });

  testWidgets("its a becomes it's a, and Ctrl+Z takes back just that",
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(t, const Locale('en', 'AU'));
    final c = await edit(t, app, 'I think its a');
    await type(t, c, ' ');
    expect(c.text, "I think it's a ");
    app.undo();
    await t.pump();
    expect(c.text, 'I think its a ', reason: 'as typed, with the space kept');
    await settle(t);
  });
}
