// Clicking into a field leaves the caret there, for every kind of field.
//
// v1.0.2 item 6: *"A page title cannot be edited once you are on the page —
// the caret lands and jumps back out."* That is the third report of one shape.
// The first two were the paragraph and the maths field, each claiming the
// keyboard from a post-frame callback registered in its own `build` — which
// runs after EVERY build, so it is a standing claim rather than the one-off it
// was written as, and the running app rebuilds constantly. `keyboardIsGoingSpare`
// in `core/focus_claim.dart` is the guard both now ask.
//
// The planning doc's own conclusion: *"Three occurrences says this wants one
// test that opens each kind of field and asserts the caret survives a frame."*
// This is that test, and it mounts the whole `AppShell` on purpose. The claims
// that do the stealing belong to OTHER widgets, so a test that mounts one field
// on its own has nobody to be robbed by — which is exactly how three of these
// shipped.
//
// **The caret ARRIVING is not the property. The caret STAYING is.** Every case
// here pumps several frames after the click, because a standing claim fires on
// the next build, not on this one.

import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/page_title_view.dart';
import 'package:openote/editor/text_block_view.dart';
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
    tmp = Directory.systemTemp.createTempSync('onote_fieldfocus_');
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

  /// The shell, with [blocks] on the open page.
  ///
  /// A paragraph is on the page in every case even when the test is about the
  /// title, because the paragraph's claim is one of the suspects: a page with
  /// nothing on it has nobody to steal the caret.
  Future<void> pumpShell(WidgetTester t, List<Block> blocks) async {
    final nb = app.notebookId!;
    final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
    app.importPage(nb, page.id, blocks, PageProps());
    app.reloadNodes();
    await app.selectPage(page.id);
    app.markOnboardingSeen();
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

  Block paragraph({double y = 240}) => Block(
      type: BlockType.text,
      x: 60,
      y: y,
      w: 480,
      content: {'text': 'A paragraph that would like the keyboard.'});

  /// Let every standing claim have its go. A claim runs from a post-frame
  /// callback registered in a build, so one pump proves nothing.
  Future<void> settleFrames(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 16));
    }
    app.cancelPendingSave();
  }

  /// **Close an open title edit before the test ends.**
  ///
  /// `PageTitleView.dispose` commits the in-flight title, and committing
  /// writes to the notebook — so a test that finishes mid-edit has the widget
  /// tree reach for a repository the tear-down has already closed, and the
  /// failure lands on whichever test runs next rather than on this one.
  /// Tapping the page away from the band is how a person leaves it too.
  Future<void> closeTitle(WidgetTester t) async {
    await t.tapAt(const Offset(1200, 820));
    await t.pumpAndSettle();
    app.cancelPendingSave();
  }

  /// **A click of a given [kind], down and up.**
  ///
  /// `tester.tap` sends a TOUCH pointer, and the pointer kind turns out to
  /// decide this bug: Flutter unfocuses a text field when a click lands
  /// outside it on desktop, and only for a mouse. Touch keeps the focus, so
  /// a touch tap never leaves the keyboard looking spare and never meets the
  /// claim that steals it. Three versions of this file passed while the
  /// owner's mouse failed.
  Future<void> clickAt(WidgetTester t, Offset p, PointerDeviceKind kind) async {
    final g = await t.startGesture(p, kind: kind);
    await g.up();
    await t.pumpAndSettle();
    app.cancelPendingSave();
  }

  /// **Does the title's own field hold the caret?**
  ///
  /// Sharper than "did the holder change", which is what the first version of
  /// this file asked — and it passed while the bug was live, because the
  /// holder stayed put: it was the NEW PARAGRAPH the same tap had created,
  /// stable from the first frame. A stability check cannot tell a field that
  /// kept the caret from a thief that never let go.
  bool titleHasCaret(WidgetTester t) {
    final f = find.descendant(
        of: find.byType(PageTitleView), matching: find.byType(TextField));
    if (f.evaluate().isEmpty) return false;
    final node = t.widget<TextField>(f).focusNode;
    return node != null && node.hasPrimaryFocus;
  }

  /// The field the caret is in, by the widget that owns the focused node.
  String focusHolder() {
    final f = FocusManager.instance.primaryFocus;
    if (f == null) return 'nobody';
    if (f is FocusScopeNode) return 'scope(${f.debugLabel ?? ''})';
    return f.debugLabel ?? 'unlabelled FocusNode';
  }

  testWidgets('THE REPORTED ONE: the page title keeps the caret', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pumpShell(t, [paragraph()]);

    // The title is a tappable Text until it is being edited — there is no
    // field to find by type until the tap has happened.
    //
    // Scoped to the band: the sidebar lists the same page by the same name, so
    // a bare `find.text` matches twice and tries to tap the navigator.
    final title = find.descendant(
        of: find.byType(PageTitleView), matching: find.text('Untitled page'));
    expect(title, findsOneWidget, reason: 'precondition: the title band is up');
    await t.tap(title);
    await t.pumpAndSettle();
    app.cancelPendingSave();

    expect(app.titleEditing, isTrue, reason: 'the edit session opened');
    final field = find.widgetWithText(TextField, '');
    expect(field, findsWidgets, reason: 'the title became a field');

    expect(titleHasCaret(t), isTrue,
        reason: 'the caret reaches the title. Holder is ${focusHolder()}');
    expect(app.blocks.length, 1,
        reason: 'THE BUG: the same tap also ran the canvas click-on-empty-page '
            'rule and made a second text box');

    await settleFrames(t);

    expect(titleHasCaret(t), isTrue,
        reason: 'and KEEPS it. Holder is now ${focusHolder()}');
    expect(app.titleEditing, isTrue,
        reason: 'and the title session must still be open');
    await closeTitle(t);
  });

  testWidgets('typing after the click reaches the TITLE, not the page',
      (t) async {
    // The symptom as it is met: you click the title, type, and the words go
    // somewhere else. Typed at whatever holds the keyboard — naming the field
    // would assume the answer.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pumpShell(t, [paragraph()]);
    await t.tap(find.descendant(
        of: find.byType(PageTitleView), matching: find.text('Untitled page')));
    await t.pumpAndSettle();
    app.cancelPendingSave();
    await settleFrames(t);

    t.testTextInput.enterText('Photosynthesis');
    await t.pumpAndSettle();
    app.cancelPendingSave();

    expect(find.widgetWithText(TextField, 'Photosynthesis'), findsOneWidget,
        reason: 'the letters must land in the title field');
    expect(
        app.blocks.any(
            (b) => '${b.content['text']}'.contains('Photosynthesis')),
        isFalse,
        reason: 'and not one of those letters in any block on the page');
    await closeTitle(t);
  });

  for (final kind in const [PointerDeviceKind.touch, PointerDeviceKind.mouse])
    testWidgets('THE REPORTED JOURNEY ($kind): edit a paragraph, THEN click '
        'the title', (t) async {
      // *"once you are on the page"* is the part that matters. With nothing
      // being edited the title keeps the caret perfectly well — the test
      // above proves that — so opening a paragraph first is the difference
      // between a test that passes and the bug the owner meets.
      //
      // **And the MOUSE case is the one that was shipped broken.** A mouse
      // down outside a field unfocuses it (Flutter's desktop default), which
      // parks focus on a scope; the title then asked for the keyboard from a
      // post-frame callback, and the paragraph's standing claim ran later in
      // that same frame, read the scope as "going spare", and took it back —
      // leaving the title open, empty and unfocused. *"seems to take 2 clicks
      // to actually start editing the title."* `claimKeyboard` is the fix.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pumpShell(t, [paragraph()]);

      await clickAt(
          t,
          t.getTopLeft(find.byType(TextBlockView).first) +
              const Offset(24, 14),
          kind);
      expect(app.editingBlockId, isNotNull,
          reason: 'precondition: a paragraph is open and claiming');

      await clickAt(
          t,
          t.getCenter(find.descendant(
              of: find.byType(PageTitleView),
              matching: find.text('Untitled page'))),
          kind);
      expect(titleHasCaret(t), isTrue,
          reason: 'ONE click must be enough. Holder is ${focusHolder()}');

      await settleFrames(t);

      expect(titleHasCaret(t), isTrue,
          reason: 'and it keeps it with a paragraph open. Holder is now '
              '${focusHolder()}');

      // And the keyboard really is the title's: type and see where it lands.
      t.testTextInput.enterText('Osmosis');
      await t.pumpAndSettle();
      app.cancelPendingSave();
      expect(find.widgetWithText(TextField, 'Osmosis'), findsOneWidget,
          reason: 'the letters belong to the title');

      await closeTitle(t);
    });

  testWidgets('a paragraph keeps the caret when clicked into', (t) async {
    // The first of the two already fixed, pinned here so the family lives in
    // one file rather than being re-derived at each site.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pumpShell(t, [paragraph(), paragraph(y: 420)]);

    await t.tapAt(
        t.getTopLeft(find.byType(TextBlockView).first) + const Offset(24, 14));
    await t.pumpAndSettle();
    app.cancelPendingSave();
    final arrived = FocusManager.instance.primaryFocus;

    await settleFrames(t);
    expect(FocusManager.instance.primaryFocus, same(arrived),
        reason: 'holder is now ${focusHolder()}');
  });
}
