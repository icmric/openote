// Clicking the page title edits the title, and makes nothing.
//
// Issue #19: *"When I create a new page, the curser focus on page title and I
// can change it -- perfect. But I can not edit the title after the change,
// Clicking on the title creates a text box on the page."* Fixed in 3c12bbf:
// the title band is drawn inside the canvas, in page space, and never claimed
// its pointers — claiming is how everything in there tells the canvas to keep
// its hands off a gesture — so the canvas ALSO saw the click and did what a
// click on empty page does. The band opened its field at the same moment and
// lost the keyboard to the box that had just appeared underneath it.
//
// Re-reported as #21 from Fedora/KDE Wayland against the v1.0.1 build, which
// predates that fix. Same bug, same cause; this is the guard that was never
// written. The fix shipped with `caret_survives_a_frame_test.dart`, which
// proves the title KEEPS the keyboard — and that was the right test for the
// diagnosis the plan got wrong, not for the bug. Nothing asserted the thing
// the fix actually does: that no block is created.
//
// It guards one more thing. `PageCanvas._selectDown` now records a touch
// BEFORE reading the claim, so that a pinch with a finger on a box is still a
// pinch; a single claimed pointer must still return early, and the title band
// is the cheapest place to notice if it ever stops.
import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/canvas/page_title_view.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

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
    tmp = Directory.systemTemp.createTempSync('onote_title_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('T');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    await app
        .selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
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

  Future<void> pump(WidgetTester t) async {
    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: Scaffold(
        body: SizedBox(width: 1100, height: 800, child: PageCanvas(state: app)),
      ),
    ));
    await t.pump();
    await t.pump();
  }

  /// The title's own words, which is what "clicking the page title" means.
  /// The band spans the page width but claims only the title ROW — a click
  /// out to the right of it is deliberately still a click on the page.
  Finder titleWords() => find.descendant(
      of: find.byType(PageTitleView), matching: find.text('Untitled page'));

  testWidgets('a click on the title creates no text box', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(t);
    expect(app.blocks, isEmpty, reason: 'precondition: an empty page');
    expect(find.byType(PageTitleView), findsOneWidget);

    await t.tapAt(t.getCenter(titleWords()));
    await t.pump();
    await t.pump(const Duration(milliseconds: 60));

    expect(app.blocks, isEmpty,
        reason: 'the canvas also saw the click and made a box to type in, '
            'which then took the keyboard off the title');
    expect(app.editingBlockId, isNull);
    app.cancelPendingSave();
  });

  testWidgets('and going BACK to it afterwards still makes none', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // The reporter's own words, and the half that actually broke: *"When I
    // create a new page, the curser focus on page title and I can change it
    // -- perfect. But I can not edit the title after the change, Clicking on
    // the title creates a text box on the page."*
    await pump(t);
    await t.tapAt(t.getCenter(titleWords()));
    await t.pump();
    await t.pump(const Duration(milliseconds: 60));

    // Leave the title the way anybody does: click the page. That makes a box
    // to type in, which is click-anywhere-to-type working as intended.
    await t.tapAt(app.canvas.pageToScreen(const Offset(300, 500)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 60));
    final after = app.blocks.length;

    // And now back to the title, which is the gesture that was broken.
    expect(titleWords(), findsOneWidget, reason: 'the title is a label again');
    await t.tapAt(t.getCenter(titleWords()));
    await t.pump();
    await t.pump(const Duration(milliseconds: 60));

    expect(app.blocks, hasLength(after),
        reason: 'going back to the title made another box');
    app.cancelPendingSave();
  });

  testWidgets('a FINGER tap on the title makes none either', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // `_selectDown` records a touch before it reads the claim, so that two
    // fingers are a pinch wherever they land. One claimed finger must still
    // be the title band's.
    await pump(t);
    await t.tapAt(t.getCenter(titleWords()), kind: PointerDeviceKind.touch);
    await t.pump();
    await t.pump(const Duration(milliseconds: 60));

    expect(app.blocks, isEmpty);
    app.cancelPendingSave();
  });

  testWidgets('NEGATIVE CONTROL: a click on the page below DOES make one',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // Click-anywhere-to-type is the behaviour this must not have taken away.
    await pump(t);
    await t.tapAt(app.canvas.pageToScreen(const Offset(300, 400)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 60));

    expect(app.blocks, hasLength(1), reason: 'a box to type in, as before');
    expect(app.blocks.single.type, BlockType.text);
    app.cancelPendingSave();
  });
}
