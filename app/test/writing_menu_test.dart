// The right-click menu on an underline, in the real editor: the fixes it offers,
// what it must NOT offer, and that a stale underline can never damage the note.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/core/onote_text.dart';
import 'package:openote/editor/text_block_view.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/spell/spell_checker.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());
  final have = OnoteText.available;

  Future<AppState> newApp(WidgetTester t, {Locale? system}) async {
    late AppState app;
    late Repository repo;
    final tmp = Directory.systemTemp.createTempSync('onote_menu_');
    addTearDown(() {
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await t.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Menu');
      app = AppState(repo)..notebookId = nb.id;
      await OnoteText.warmUp(EnglishDialect.australian);
    });
    app.systemLocale = () => system ?? const Locale('en', 'AU');
    return app;
  }

  /// Let the debounce fire and the native check come back (it runs on a real
  /// isolate, so the test's fake clock has to step aside for it).
  Future<void> settleCheck(WidgetTester t) async {
    await t.pump(const Duration(milliseconds: 400));
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    await t.pump();
  }

  /// Open [text] for editing and let the first check come back.
  Future<TextEditingController> open(
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
    await settleCheck(t);
    return app.activeEditor!.controller;
  }

  Future<void> done(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  }

  /// Put the caret inside [word] and open the menu.
  Future<void> menuOn(WidgetTester t, TextEditingController c, String word) async {
    final at = c.text.indexOf(word) + 1;
    c.selection = TextSelection.collapsed(offset: at);
    await t.pump();
    t.state<EditableTextState>(find.byType(EditableText)).showToolbar();
    await t.pump();
  }

  testWidgets('a misspelling offers its fixes, best first, and Add to dictionary',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(t);
    final c = await open(t, app, 'I recieve it');
    await menuOn(t, c, 'recieve');
    expect(find.text('receive'), findsOneWidget);
    expect(find.text('Add to dictionary'), findsOneWidget);

    await t.tap(find.text('receive'));
    await t.pump();
    expect(c.text, 'I receive it');
    await done(t);
  }, skip: !have);

  testWidgets('every misspelling gets suggestions, however many there are',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(t);
    final text = [for (var i = 0; i < 20; i++) 'recieve$i'.replaceAll(RegExp(r'\d'), '')]
        .join(' ');
    final c = await open(t, app, '$text lecure');
    // The last one, far past the twelve the first version looked up.
    await menuOn(t, c, 'lecure');
    expect(find.text('lecture'), findsOneWidget);
    await done(t);
  }, skip: !have);

  testWidgets('a grammar underline says why, and offers the fix', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(t);
    final c = await open(t, app, 'I could of done it');
    await menuOn(t, c, 'could of');
    expect(find.text('could have'), findsOneWidget);
    await t.tap(find.text('could have'));
    await t.pump();
    expect(c.text, 'I could have done it');
    await done(t);
  }, skip: !have);

  testWidgets('a word the checker accepts gets no misspelling menu', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(t);
    // Not in the old American word list; fine for the real checker.
    final c = await open(t, app, 'On Monday I emailed the website.');
    await menuOn(t, c, 'Monday');
    expect(find.text('Add to dictionary'), findsNothing);
    await done(t);
  }, skip: !have);

  testWidgets('a stale underline cannot be spliced into changed text', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(t);
    final c = await open(t, app, 'I recieve it');
    // The note changes under the underline before the next check lands.
    c.value = const TextEditingValue(
        text: 'Yes I recieve it', selection: TextSelection.collapsed(offset: 7));
    await t.pump();
    // The marks still point at the old offsets, which now cover other letters.
    await menuOn(t, c, 'recieve');
    expect(find.text('receive'), findsNothing,
        reason: 'the old offsets no longer cover the word');
    expect(c.text, 'Yes I recieve it', reason: 'and nothing was edited');
    await done(t);
  }, skip: !have);

  testWidgets('a word added to the dictionary stops being flagged', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(t);
    addTearDown(() => learnedWords.remove('recieve'));
    final c = await open(t, app, 'I recieve it');
    await menuOn(t, c, 'recieve');
    await t.tap(find.text('Add to dictionary'));
    await settleCheck(t);
    expect(learnedWords, contains('recieve'));
    expect(c.text, 'I recieve it');
    // …and the underline is gone, so the menu has no spelling items now.
    await menuOn(t, c, 'recieve');
    expect(find.text('Add to dictionary'), findsNothing);
    await done(t);
  }, skip: !have);

  testWidgets('nothing is underlined, and the menu is plain, in German',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(t, system: const Locale('de', 'DE'));
    final c = await open(t, app, 'Ich habe einen Hundd und recieve');
    expect(app.activeEditor!.controller.text, isNotEmpty);
    await menuOn(t, c, 'Hundd');
    expect(find.text('Add to dictionary'), findsNothing);
    await done(t);
  }, skip: !have);
}
