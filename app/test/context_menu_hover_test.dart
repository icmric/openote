// A right-click menu that flashes while the pointer is over it.
//
// Reported: *"If i right click and move my mouse over the right click menu it
// will flash … the bigger issue seems to come when there is an image inlined
// with the text. If i rightclick anywhere inside there while editing, whether
// on text or on the image, it will flash rapidly while my mouse is on it,
// never ceasing, making it basically unuseable."*
//
// The menu is in the `Overlay`, so it is drawn OUTSIDE the block that opened
// it. Moving the pointer onto it therefore leaves the block's own
// `MouseRegion` — and `BlockView` answers that with `setState`, because
// hovering is what shows the block's chrome. That rebuilds the block, the
// field inside it and the menu the field owns.
//
// Both of these need the real shell: the hover regions, the chrome and the
// overlay all belong to `BlockView` and the canvas, and no test that mounts a
// bare `TextBlockView` has any of them.

import 'dart:io';

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart' show kSecondaryButton, PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/editor/text_block_view.dart';
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
  late Block block;

  /// Every element the menu has had during one hover. More than one means it
  /// was torn down and built again — which is the flash.
  late Set<int> seenMenuElements;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_menuhover_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('T');
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

  Future<void> pumpShell(WidgetTester t, String text) async {
    seenMenuElements = <int>{};
    final nb = app.notebookId!;
    final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
    block = Block(
        type: BlockType.text, x: 60, y: 140, w: 480, content: {'text': text});
    app.importPage(nb, page.id, [block], PageProps());
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
    block = app.blocks.single;
  }

  Future<void> openBlock(WidgetTester t) async {
    await t.tapAt(t.getTopLeft(find.byType(TextBlockView)) + const Offset(24, 14));
    await t.pumpAndSettle();
    app.cancelPendingSave();
  }

  /// Right-click inside the paragraph, then walk a real mouse onto the menu
  /// that opens — which is the whole gesture being reported, and the pointer
  /// LEAVING the block is the part that matters.
  ///
  /// The menu is found by its own type rather than by looking for a button:
  /// `AppShell` is full of buttons, and an earlier version of this walked the
  /// pointer onto the command bar and proved nothing at all.
  Future<void> openMenuAndHoverIt(WidgetTester t) async {
    final inside = t.getTopLeft(find.byType(TextBlockView)) + const Offset(24, 14);
    await t.tapAt(inside, buttons: kSecondaryButton);
    await t.pumpAndSettle();

    final menu = find.byType(DesktopTextSelectionToolbar);
    expect(menu, findsOneWidget,
        reason: 'the right-click has to actually open the menu, or the hover '
            'below lands on the page and the test proves nothing');

    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(() => mouse.removePointer());
    await mouse.addPointer(location: inside);
    await t.pump();
    // Onto the menu — outside the block, inside the overlay. Several small
    // steps, because what was reported is a flash while the pointer MOVES
    // over it, and one jump generates one enter/exit pair.
    final target = t.getCenter(menu);
    seenMenuElements.add(identityHashCode(menu.evaluate().first));
    for (var i = 1; i <= 8; i++) {
      await mouse.moveTo(Offset(
        inside.dx + (target.dx - inside.dx) * i / 8,
        inside.dy + (target.dy - inside.dy) * i / 8,
      ));
      await t.pump(const Duration(milliseconds: 16));
      final live = menu.evaluate();
      if (live.isNotEmpty) {
        seenMenuElements.add(identityHashCode(live.first));
      }
    }
  }


  /// `pumpAndSettle` throws if frames never stop being scheduled, which is
  /// what "flashing, never ceasing" is from the outside. It is the assertion
  /// rather than a count of rebuilds because the complaint is that the app
  /// never comes to rest, not that any one widget rebuilds.
  Future<void> hoverTheMenuAndSettle(WidgetTester t, String text) async {
    await pumpShell(t, text);
    await openBlock(t);
    await openMenuAndHoverIt(t);
    await t.pumpAndSettle();
    app.cancelPendingSave();
  }

  /// **Windows, explicitly.** A widget test is Android unless told otherwise,
  /// and a right-click toolbar is desktop behaviour — on Android the gesture
  /// never opens this menu, so the test would pass without reaching the thing
  /// it is about. Cleared in a `finally` and not an `addTearDown`, because
  /// tear-downs run AFTER the binding checks that no debug variable was left
  /// set, and that check fails the test.
  Future<void> onWindows(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('hovering the menu does not leave the app rebuilding for ever',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await onWindows(() =>
        hoverTheMenuAndSettle(t, 'A sentence to right-click inside of.'));
  });

  testWidgets('and still does not with a picture in the sentence', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // An in-flow picture: 64 hex characters the reader never sees. The bytes
    // are deliberately absent — what is being tested is the rebuild loop, and
    // a missing blob draws a placeholder of its own without changing who
    // rebuilds whom.
    await onWindows(() => hoverTheMenuAndSettle(
        t, 'Before ![](sha256:${'a' * 64}) after, with words either side.'));
  });

  /// **A standard row reads as its action.**
  ///
  /// Reported: *"the tooltips for paste and select just say 'More' which
  /// seems very wrong"*. They did. A `ContextMenuButtonItem` for one of
  /// Flutter's own actions carries a TYPE and a null `label` — turning that
  /// into words in the reader's language is the toolbar's job — so falling
  /// back to a placeholder when `label` was null labelled every standard row
  /// "More". `AdaptiveTextSelectionToolbar.getButtonLabel` is the public
  /// helper that does it properly, and hands Openote's own labelled items
  /// straight back.
  testWidgets('standard rows read as their action, not as More', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await onWindows(() async {
      await pumpShell(t, 'A sentence to right-click inside of.');
      await openBlock(t);
      await t.tapAt(
          t.getTopLeft(find.byType(TextBlockView)) + const Offset(24, 14),
          buttons: kSecondaryButton);
      await t.pumpAndSettle();

      final menu = find.byType(DesktopTextSelectionToolbar);
      expect(menu, findsOneWidget);
      final more = MaterialLocalizations.of(t.element(menu)).moreButtonTooltip;
      expect(find.descendant(of: menu, matching: find.text(more)), findsNothing,
          reason: 'every standard row was labelled "$more"');
      expect(
          find.descendant(of: menu, matching: find.text('Select all')),
          findsOneWidget,
          reason: 'and it should say what it does');
      app.cancelPendingSave();
    });
  });

  /// **The flash itself: the menu must not be rebuilt from scratch while the
  /// pointer is on it.**
  ///
  /// Measured before the fix, over an eight-step pointer move onto the menu:
  /// the menu's element changed once with a plain sentence and three times
  /// with a picture in it, while `TextBlockView`'s element and the
  /// paragraph's `EditableText` element both stayed the same. So the editor
  /// was never replaced — only the overlay entry holding the menu was, and a
  /// remount is a flash.
  ///
  /// Nothing loops: `pumpAndSettle` settles. The flashing is one flash per
  /// pointer event, which is why it looks continuous while the mouse moves
  /// and stops when it rests.
  testWidgets('the menu is not rebuilt from scratch while hovered', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await onWindows(() async {
      await hoverTheMenuAndSettle(t, 'A sentence to right-click inside of.');
      expect(seenMenuElements, hasLength(1),
          reason: 'the menu was torn down and rebuilt mid-hover');
    });
  });

  testWidgets('nor when a picture shares the sentence', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await onWindows(() async {
      await hoverTheMenuAndSettle(
          t, 'Before ![](sha256:${'a' * 64}) after, with words either side.');
      expect(seenMenuElements, hasLength(1),
          reason: 'worse with a picture: five elements, reported as '
              '"flash rapidly … never ceasing"');
    });
  });

  /// **Paste is offered even when the clipboard is empty.**
  ///
  /// Reported: *"the menu is also missing the option to paste which is fairly
  /// major"*. Flutter omits the row entirely unless the clipboard reports
  /// something pasteable, so an empty clipboard produced a menu with no Paste
  /// in it — which reads as "this app cannot paste" rather than "there is
  /// nothing to paste".
  ///
  /// The clipboard is mocked EMPTY here, which is the case that was broken;
  /// with text on it Flutter supplies the row itself.
  testWidgets('Paste is offered, disabled, with an empty clipboard', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await onWindows(() async {
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform, (MethodCall call) async {
        if (call.method == 'Clipboard.hasStrings') {
          return <String, dynamic>{'value': false};
        }
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await pumpShell(t, 'A sentence to right-click inside of.');
      await openBlock(t);
      await t.tapAt(
          t.getTopLeft(find.byType(TextBlockView)) + const Offset(24, 14),
          buttons: kSecondaryButton);
      await t.pumpAndSettle();

      final menu = find.byType(DesktopTextSelectionToolbar);
      final paste = find.descendant(of: menu, matching: find.text('Paste'));
      expect(paste, findsOneWidget, reason: 'the row was absent entirely');
      // Disabled, not merely present: a row you can press and that does
      // nothing is worse than one that says it cannot be pressed.
      final button = t.widget<TextButton>(find
          .ancestor(of: paste, matching: find.byType(TextButton))
          .first);
      expect(button.onPressed, isNull,
          reason: 'there is nothing on the clipboard to paste');
      app.cancelPendingSave();
    });
  });
}
