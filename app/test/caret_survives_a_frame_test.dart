// Click into a field and the caret is still there a frame later.
//
// The same defect has been fixed three times at three sites now — the
// paragraph, the equation field, and whatever this test turns up for the page
// title — each reported the same way:
//
//   "it will move the caret into it as if it was going to edit it, but then
//    it will just dispear from it and the other box never looses focus."
//
// Which is why this is one test over every kind of field rather than another
// regression test beside the last one. A claim registered from `build` runs
// after EVERY build, and the running app rebuilds constantly, so a field that
// takes the keyboard without asking [keyboardIsGoingSpare] steals it back on
// the next frame from whatever took it.
//
// Issue #19, and v1.0.2 bug 6.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/block_view.dart';
import 'package:openote/canvas/page_title_view.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/app_shell.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;
  late String paraId;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_caret_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Caret');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
    final para = Block(
        type: BlockType.text,
        x: 60,
        y: 300,
        w: 300,
        h: 60,
        content: {'text': 'a paragraph', 'autoWidth': false});
    paraId = para.id;
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

  Future<void> pumpShell(WidgetTester t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      theme: onoteTheme(Brightness.light),
      home: AppShell(app: app),
    ));
    await t.pump(const Duration(milliseconds: 900));
    await t.pumpAndSettle();
  }

  /// The title in the page band, not the same words in the sidebar.
  Finder titleBand(String text) => find.descendant(
      of: find.byType(PageTitleView), matching: find.text(text));

  /// Whether a live `EditableText` is holding the keyboard, and which.
  String? focusedFieldText() {
    final holder = FocusManager.instance.primaryFocus;
    if (holder == null) return null;
    for (final e in find.byType(EditableText).evaluate()) {
      final w = e.widget as EditableText;
      if (w.focusNode == holder) return w.controller.text;
    }
    return null;
  }

  testWidgets('THE PAGE TITLE KEEPS THE CARET IT WAS GIVEN', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pumpShell(t);

    await t.tap(titleBand('Untitled page'));
    await t.pumpAndSettle();
    expect(app.titleEditing, isTrue, reason: 'the band opened its field');

    // A frame is the whole test: the claim that steals the keyboard back is
    // registered from a build, so it fires on the one after.
    await t.pump();
    await t.pump();

    expect(focusedFieldText(), isNotNull,
        reason: 'something still holds the keyboard');
    await t.enterText(
        find.descendant(
            of: find.byType(PageTitleView), matching: find.byType(TextField)),
        'Lecture 4');
    await t.pumpAndSettle();
    expect(titleBand('Lecture 4'), findsOneWidget,
        reason: 'and what was typed went into the title');
    expect(focusedFieldText(), 'Lecture 4');
    app.cancelPendingSave();
  });

  testWidgets('CLICKING THE TITLE DOES NOT PUT A TEXT BOX ON THE PAGE',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pumpShell(t);
    final before = app.blocks.length;

    await t.tap(titleBand('Untitled page'));
    await t.pumpAndSettle();

    // Issue #19: *"Clicking on the title creates a text box on the page."*
    // The band sits inside the canvas and did not claim its pointers, so the
    // canvas also saw the click and did what a click on empty page does —
    // which is also where the caret went.
    expect(app.blocks, hasLength(before));
    expect(app.titleEditing, isTrue);
    app.cancelPendingSave();
  });

  testWidgets('a paragraph keeps the caret when the title had it', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pumpShell(t);

    await t.tap(titleBand('Untitled page'));
    await t.pumpAndSettle();
    await t.tap(find.byWidgetPredicate(
        (w) => w is BlockView && w.block.id == paraId));
    await t.pumpAndSettle();
    await t.pump();

    expect(app.titleEditing, isFalse, reason: 'the title let go');
    expect(app.editingBlockId, isNotNull, reason: 'the paragraph opened');
    expect(focusedFieldText(), 'a paragraph',
        reason: 'and it is what holds the keyboard');
    app.cancelPendingSave();
  });
}
