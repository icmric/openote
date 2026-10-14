// An in-flow flashcard is as wide as its box.
//
// v1.0.2 #7: *"A flashcard cannot be resized on its own — only the whole
// box."* Insert ▸ Flashcard makes a text box holding one `?[front](back)`
// line, and the card in it was a fixed 420 x 132 in the editor whatever the
// box was — so resizing the box did nothing to the card — and up to 460 wide
// in the reading view, so the card moved when you clicked into it.
//
// Height stays fixed on purpose: a card turns over, and a height taken from
// whichever face is showing would move the paragraph mid-flip.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/flashcard_view.dart';
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

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_cardsize_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('F');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
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

  /// The whole shell, with one card in a box shaped like Insert ▸ Flashcard
  /// makes it: 460 wide, not auto-width.
  Future<Block> pumpCard(WidgetTester t, {double w = 460}) async {
    final nb = app.notebookId!;
    final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
    final card = Block(
        type: BlockType.text,
        x: 60,
        y: 160,
        w: w,
        content: {
          'text': '?[What is osmosis?](Water moving across a membrane)\n',
          'autoWidth': false,
        });
    app.importPage(nb, page.id, [card], PageProps());
    app.reloadNodes();
    await app.selectPage(page.id);
    app.markOnboardingSeen();
    t.view.physicalSize = const Size(1600, 900);
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
    app.cancelPendingSave();
    return app.blocks.single;
  }

  Size cardSize(WidgetTester t) => t.getSize(find.byType(FlipCard));

  /// Resize the box the way its handle does: a new width, through the normal
  /// update path.
  Future<void> resizeBox(WidgetTester t, Block b, double w) async {
    b.w = w;
    app.updateBlock(b);
    await t.pumpAndSettle();
    app.cancelPendingSave();
  }

  Future<void> openBox(WidgetTester t, Block b) async {
    app.select(b.id, edit: true);
    await t.pumpAndSettle();
    app.cancelPendingSave();
  }

  Future<void> closeBox(WidgetTester t) async {
    app.select(null);
    await t.pumpAndSettle();
    app.cancelPendingSave();
  }

  testWidgets('THE REPORTED ONE: resizing the box resizes the card', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final b = await pumpCard(t);
    final before = cardSize(t);

    await resizeBox(t, b, 660);
    final wider = cardSize(t);
    expect(wider.width - before.width, closeTo(200, 1),
        reason: 'every pixel the box gained, the card gained');

    await resizeBox(t, b, 360);
    expect(cardSize(t).width - before.width, closeTo(-100, 1),
        reason: 'and it shrinks with the box too');
    expect(cardSize(t).height, kInlineCardHeight,
        reason: 'height is the card\'s own; see the note at the top');
  });

  testWidgets('and the same while the box is being edited', (t) async {
    // The editor caches the card by its text. Without the width in that key
    // it would hand back the card at its old width after a resize.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final b = await pumpCard(t);
    await openBox(t, b);
    final before = cardSize(t);
    await resizeBox(t, b, 660);
    expect(cardSize(t).width - before.width, closeTo(200, 1));
    await closeBox(t);
  });

  testWidgets("clicking into the box does not change the card's width",
      (t) async {
    // The two views used to disagree — 420 in the editor, up to 460 when
    // reading — so the card changed width every time the box was opened.
    // Both now ask `inlineCardWidth` with the width each lays its paragraph
    // out at, and agree to the pixel.
    //
    // **Not asserted: the vertical.** The card sits 4px lower in the editor
    // than when read, and did before this change too — it is how the
    // editor's line places a placeholder, not anything to do with width.
    // Recorded rather than hidden behind a tolerance. A card exactly as wide
    // as its line made it 7.3px, which is what `_kTailRoom` is for.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final b = await pumpCard(t);
    for (final w in [460.0, 300.0, 820.0]) {
      if (b.w != w) await resizeBox(t, b, w);
      final reading = t.getRect(find.byType(FlipCard));
      await openBox(t, b);
      final editing = t.getRect(find.byType(FlipCard));
      expect(editing.left, reading.left, reason: 'a $w-wide box');
      expect(editing.right, reading.right, reason: 'a $w-wide box');
      expect(editing.height, reading.height, reason: 'a $w-wide box');
      expect(editing.top - reading.top, lessThanOrEqualTo(4),
          reason: 'no worse than it has always been');
      await closeBox(t);
    }
  });

  testWidgets('a narrow box squeezes the card without overflowing it',
      (t) async {
    // The framework fails a test on a RenderFlex overflow, so getting here
    // without one is the assertion. The face's label and footer give way
    // rather than spilling a yellow-and-black bar across the card.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final b = await pumpCard(t);
    await resizeBox(t, b, 150);
    expect(cardSize(t).width, lessThan(150));
    await openBox(t, b);
    expect(cardSize(t).width, lessThan(150));
    await closeBox(t);
  });

  testWidgets('turning the card over does not change its size', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pumpCard(t);
    final front = cardSize(t);
    await t.tap(find.text('Reveal'));
    await t.pumpAndSettle();
    app.cancelPendingSave();
    expect(find.text('ANSWER'), findsOneWidget, reason: 'precondition: flipped');
    expect(cardSize(t), front);
  });
}
