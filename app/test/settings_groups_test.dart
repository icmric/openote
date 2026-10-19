// Settings is a rail of groups, one open at a time.
//
// The owner: *"The settings menu is looking pretty messy though at the moment.
// Like its alright but its a bit hard to find things and navigate. I wonder if
// we go for a more standard 'tab' style … rather than one long page we instead
// have a series of groups along the left."*
//
// What that has to mean, and what is asserted here: every group is named where
// you can see all of them at once, only one group's rows are on screen, and
// the dialog does not change size as you move down the rail — a dialog that
// grew and shrank would move the rail out from under the pointer.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/settings_dialog.dart';

import 'support/app.dart';
import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Future<AppState> newApp(WidgetTester t) async {
    late AppState app;
    late Repository repo;
    final tmp = Directory.systemTemp.createTempSync('onote_settings_');
    addTearDown(() {
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await t.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Settings');
      app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      await app.selectPage(
          app.nodes.where((n) => n.kind == NodeKind.page).first.id);
    });
    return app;
  }

  Future<void> open(WidgetTester t, AppState app,
      {Size window = const Size(1100, 780)}) async {
    t.view.physicalSize = window;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(testApp(Builder(
      builder: (context) => TextButton(
        onPressed: () => showSettingsDialog(context, app),
        child: const Text('go'),
      ),
    )));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
  }

  const groups = [
    'Appearance',
    'Writing and drawing',
    'Connections',
    'Help',
    'About',
  ];

  // **The descriptions, as a bound rather than as a judgement.** The owner:
  // *"the items within it now feel quite messy due to the length and
  // redundancy in some situations of the descriptions, many of them are long
  // and add nearly nothing."* Whether a sentence earns its place is a reading
  // and cannot be asserted — but the two mechanical ways this page got messy
  // can be, and both of them had happened: a tooltip pressed into service as
  // a row label, three lines long, and hints growing into paragraphs.
  group('the words', () {
    Map<String, String> messages(String loc) {
      final j = jsonDecode(
              File('lib/l10n/app_$loc.arb').readAsStringSync()) as Map;
      return {
        for (final e in j.entries)
          if (!e.key.toString().startsWith('@'))
            e.key.toString(): e.value as String
      };
    }

    test('NO SETTING IS A PARAGRAPH, IN ANY LANGUAGE', () {
      for (final loc in ['en', 'de', 'es', 'fr', 'it', 'pt', 'zh']) {
        messages(loc).forEach((key, value) {
          if (!key.startsWith('settings')) return;
          expect(value, isNot(contains('\n')),
              reason: '$loc · $key is several lines: a settings row is a '
                  'label, a line under it and a control, and a label that '
                  'wraps three times is the mess this is here to stop');
        });
      }
    });

    test('and no hint runs past a line', () {
      messages('en').forEach((key, value) {
        if (!key.startsWith('settings') || !key.endsWith('Hint')) return;
        expect(value.length, lessThanOrEqualTo(60),
            reason: '$key is ${value.length} characters. A hint says the one '
                'thing the label and the control do not; past a line it is '
                'prose, and prose here is what made the page hard to read');
      });
    });
  });

  testWidgets('EVERY GROUP IS NAMED, AND ONE OF THEM IS OPEN', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await open(t, await newApp(t));

    for (final g in groups) {
      expect(find.text(g), findsOneWidget, reason: '$g is in the rail');
    }
    // The first group's own rows, and nobody else's: the whole point of a rail
    // is that you are not reading four other groups to find one.
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Spell check'), findsNothing);
    expect(find.text('Sync'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('AND PICKING ONE SWAPS THE PAGE', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await open(t, await newApp(t));

    await t.tap(find.text('Writing and drawing'));
    await t.pumpAndSettle();

    expect(find.text('Spell check'), findsOneWidget);
    expect(find.text('Theme'), findsNothing,
        reason: 'the page it replaced really went away');
    expect(t.takeException(), isNull);
  });

  testWidgets('the dialog is the same size whichever group is open',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await open(t, await newApp(t));
    final was = t.getSize(find.byType(AlertDialog));

    for (final g in groups.skip(1)) {
      await t.tap(find.text(g));
      await t.pumpAndSettle();
      expect(t.getSize(find.byType(AlertDialog)), was, reason: 'opening $g');
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('A GROUP WITH TWO KINDS OF SETTING IN IT SAYS SO', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await open(t, await newApp(t));
    await t.tap(find.text('Writing and drawing'));
    await t.pumpAndSettle();

    expect(find.text('Pen and touch'), findsOneWidget,
        reason: 'the two hardware rows are not about writing');
    expect(find.text('Spell check'), findsOneWidget);
    expect(find.text('Draw with your finger'), findsOneWidget);
    // **One rule, both halves.** A line goes between two settings, and never
    // against a subheading — which is already a boundary, so a line there
    // would be a line under a line. On this page that leaves exactly one: the
    // two rows under the subheading.
    expect(find.byType(Divider), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('and it fits a small window, every group of it', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // Smaller than the dialog asks for, which is the case a fixed width gets
    // wrong: 620 points of rail and rows in 600 points of window.
    await open(t, await newApp(t), window: const Size(600, 560));

    for (final g in groups) {
      await t.tap(find.text(g));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: '$g overflowed');
    }
  });
}
