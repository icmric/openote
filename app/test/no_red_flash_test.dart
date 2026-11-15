// A word is only wrong once it is finished.
//
// "When I typed didnt it initially underlined it with red then fixed the
// punctuation and removed the line." The line was drawn for the moment between
// the last letter and the space that finishes the word. Fixed by leaving the
// word the caret is still at the end of alone while the person is typing, and
// marking it when the caret leaves, if it is still wrong.
//
// Needs the real checker (it is what decides a word is wrong), so it is skipped
// where the native library is absent.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/core/onote_text.dart';
import 'package:openote/editor/live_markdown_controller.dart';
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

  // A made-up word: wrong, and not in anything that autocorrects.
  const wrong = 'zzqxtion';

  late AppState app;
  late Repository repo;

  /// The debounce fires and the native check comes back (a real isolate, so the
  /// fake clock steps aside for it).
  Future<void> settle(WidgetTester t) async {
    await t.pump(const Duration(milliseconds: 400));
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    await t.pump();
  }

  Future<LiveMarkdownController> open(WidgetTester t, String text) async {
    final tmp = Directory.systemTemp.createTempSync('onote_flash_');
    addTearDown(() {
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await t.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Flash');
      app = AppState(repo)..notebookId = nb.id;
      await OnoteText.warmUp(EnglishDialect.australian);
    });
    app.systemLocale = () => const Locale('en', 'AU');
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
    final c = app.activeEditor!.controller as LiveMarkdownController;
    t.testTextInput.updateEditingValue(TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length)));
    await t.pump();
    await settle(t);
    return c;
  }

  Future<void> type(WidgetTester t, LiveMarkdownController c, String chars) async {
    for (final ch in chars.split('')) {
      final v = c.value;
      final o = v.selection.baseOffset;
      t.testTextInput.updateEditingValue(TextEditingValue(
          text: v.text.replaceRange(o, o, ch),
          selection: TextSelection.collapsed(offset: o + ch.length)));
      await t.pump();
    }
  }

  Future<void> done(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  }

  testWidgets('the word being typed is not underlined until it is finished',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final c = await open(t, 'I think ');
    await type(t, c, wrong);
    await settle(t); // a pause with the caret still at the end of it
    expect(c.misspellings, isEmpty,
        reason: 'no red line while the word is still being typed');

    await type(t, c, ' ');
    await settle(t);
    expect(c.misspellings, hasLength(1),
        reason: 'finished, and still wrong: now it is marked');
    await done(t);
  }, skip: !have);

  testWidgets('and is marked when the caret moves away, with no typing',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final c = await open(t, 'I think ');
    await type(t, c, wrong);
    await settle(t);
    expect(c.misspellings, isEmpty);

    c.selection = const TextSelection.collapsed(offset: 0);
    await t.pump();
    expect(c.misspellings, hasLength(1),
        reason: 'the caret left it: it shows at once, not after more typing');
    await done(t);
  }, skip: !have);

  testWidgets('a wrong word that was already there is underlined at once',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // Opening a note and clicking at the end of a misspelled word is not typing.
    final c = await open(t, 'I think $wrong');
    expect(c.misspellings, hasLength(1));
    await done(t);
  }, skip: !have);
}
