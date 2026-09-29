// Choosing an ink colour, including one nobody chose for you.
//
// From issue #7, and the owner's follow-up: *"the issue raised the lack of
// options (i.e. wanting to be able to change/create custom colours, and
// something like an eyedropper too as an option to select a colour, thinking
// that and a more traditional colour selector)."*
//
// The blocker was the model rather than the toolbar. The pen's colour was an
// INDEX into a fixed list — `penColor = 2` — and an index means nothing
// without the list it counts into, so there was nowhere to put a seventh
// colour and no way to say "the one I mixed". Storing the colour itself is
// what lets the six swatches, the full picker and the eyedropper all write
// the same field.
//
// `auto` stays a real value in that field, not a missing one: it is the
// default ink, and it resolves when the stroke is DRAWN — see
// `auto_ink_color_test.dart`.

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/ink_ops.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/color_picker.dart';
import 'package:openote/ui/command_bar.dart';

import 'support/app.dart';
import 'support/sqlite.dart';

class _NoopRepo implements Repository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('the colour the tool in hand will draw with', () {
    test('the pen and the highlighter keep their own', () {
      // Not interchangeable in either direction: a highlighter colour used as
      // ink is unreadable, and ink used as a highlighter is a blackout. They
      // shared one index before, which is why picking a highlighter colour
      // used to change the pen too.
      final app = AppState(_NoopRepo());

      app.tool = Tool.pen;
      app.setInkColor('#2F6FB3');
      app.tool = Tool.highlighter;
      expect(app.inkColor, isNot('#2F6FB3'));

      app.setInkColor('#F3B0C6');
      app.tool = Tool.pen;
      expect(app.inkColor, '#2F6FB3', reason: 'the pen kept its own');
    });

    test('the default pen is `auto`, which is a colour and not a blank', () {
      final app = AppState(_NoopRepo());
      expect(app.inkColor, 'auto');
    });

    test('one spelling of a colour, so a swatch can compare equal to it', () {
      // The swatch ring is drawn by comparing the stored string with the one
      // the swatch would set. Two spellings of the same colour is a swatch
      // that never looks selected.
      expect(inkHexOf(const Color(0xFF2f6fb3)), '#2F6FB3');
      expect(inkHexOf(const Color(0x882F6FB3)), '#2F6FB3',
          reason: 'ink carries its opacity separately, in the stroke');
    });
  });

  group('the toolbar', () {
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());

    Future<AppState> fixture(WidgetTester tester, String name) async {
      late AppState app;
      late Repository repo;
      final tmp = Directory.systemTemp.createTempSync(name);
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      await tester.runAsync(() async {
        repo = await Repository.openAt(tmp);
        final nb = await repo.createNotebook('Ink');
        app = AppState(repo)..notebookId = nb.id;
        app.reloadNodes();
      });
      return app;
    }

    Future<void> drawTab(WidgetTester tester, AppState app) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // Through a `ListenableBuilder`, because that is what the shell is: the
      // bar itself does not listen, so mounting it bare means nothing ever
      // repaints and every assertion below would be about a frozen frame.
      await tester.pumpWidget(testApp(Scaffold(
        body: ListenableBuilder(
          listenable: app,
          builder: (_, __) => CommandBar(app: app),
        ),
      )));
      await tester.pump();
      await tester.tap(find.text('Draw'));
      await tester.pump();
    }

    testWidgets('a colour that was mixed is offered next time', (tester) async {
      // The recents are the same list the text-colour picker keeps. A colour
      // is a colour: somebody who mixed one for a heading should find it
      // under the pen without mixing it twice.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = await fixture(tester, 'onote_ink_recent_');
      app.tool = Tool.pen;
      app.rememberCustomColor('7A3E9D');
      await drawTab(tester, app);

      final swatch = find.byTooltip('#7A3E9D');
      expect(swatch, findsOneWidget, reason: 'it should be on the row');
      await tester.tap(swatch);
      await tester.pump();
      expect(app.inkColor, '#7A3E9D');

      // Remembering a colour writes a setting, which arms the debounced
      // workspace save; leave it running and the test fails on the timer
      // instead of on what it came to check.
      app.cancelPendingSave();
    });

    testWidgets('the eyedropper arms rather than acting', (tester) async {
      // It cannot pick a colour until somebody points at one, so the button
      // is a mode with an end: the next click on the page takes the colour
      // and the mode is over.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = await fixture(tester, 'onote_ink_dropper_');
      app.tool = Tool.pen;
      await drawTab(tester, app);

      expect(app.pickingInkColor, isFalse);
      await tester.tap(find.byIcon(Icons.colorize_outlined));
      await tester.pump();
      expect(app.pickingInkColor, isTrue);
      expect(find.textContaining('Click anything on the page'), findsOneWidget,
          reason: 'a mode with no visible state is a mode nobody can leave');
    });

    testWidgets('the colours are there whatever tool is in hand',
        (tester) async {
      // Reported: *"i want it to always be there, not just when im drawing.
      // This also means that the eyedropper is unusable … when i attempt to
      // select it and move my cursor it then moves away from inking and
      // therefore that disappears."*
      //
      // Reaching for the mouse is how a toolbar button is pressed, and it is
      // also what puts the pen back down — so a control gated on the pen was
      // gone before the pointer arrived at it.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = await fixture(tester, 'onote_ink_always_');
      await drawTab(tester, app);

      for (final tool in Tool.values) {
        app.setTool(tool);
        await tester.pump();
        expect(find.byIcon(Icons.colorize_outlined), findsOneWidget,
            reason: '$tool');
        // A palette, not a plus: `add_circle_outline` beside a row of
        // colours reads as "add a colour to this row" when what it opens is
        // the whole picker.
        expect(find.byIcon(Icons.palette_outlined), findsOneWidget,
            reason: '$tool');
      }
    });

    testWidgets('pen thickness is a few dots, not a slider to aim at',
        (tester) async {
      // The owner: *"The slider to adjust the pen size is not intuitive,
      // please have just a few options for size, then maybe an option to
      // adjust it to something more exact or specific."*
      //
      // 1-to-10 across 110px is nine pixels per unit, so choosing a thickness
      // was a drag you had to aim and reading the one you had meant looking
      // at a handle position rather than at a thickness.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = await fixture(tester, 'onote_ink_size_');
      app.tool = Tool.pen;
      await drawTab(tester, app);

      expect(find.byType(Slider), findsNothing,
          reason: 'not on the toolbar any more');
      for (final v in kPenSizes) {
        expect(find.byTooltip('Pen size ${v == v.roundToDouble() ? v.toInt() : v}'),
            findsOneWidget,
            reason: 'a dot for $v');
      }

      await tester.tap(find.byTooltip('Pen size 5'));
      await tester.pump();
      expect(app.penSize, 5);

      // And anything the four do not cover is still reachable.
      await tester.tap(find.byTooltip('Exact size…'));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsOneWidget,
          reason: 'the slider is behind a button, not gone');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    });

    testWidgets('the exact-size popup is popup-sized, and shows the dot',
        (tester) async {
      // The owner: *"The 'exact size' popup has the right length but its
      // height expands as far as it can. Some numbers also have a huge amount
      // of decimal places… Also it would be nice to have a circle on there
      // which shows the size of the dot that it will draw. This dot should
      // also be coloured the same as the currently selected colour."*
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = await fixture(tester, 'onote_ink_exact_');
      app.tool = Tool.pen;
      app.setInkColor('#7A3E9D');
      await drawTab(tester, app);

      await tester.tap(find.byTooltip('Exact size…'));
      await tester.pumpAndSettle();

      // The dialog's SURFACE, not `AlertDialog`'s own render box — that one
      // is the full-screen `Align` every dialog is centred by, and measuring
      // it says 900 for a perfectly ordinary popup.
      final surface = tester.getSize(find
          .descendant(
              of: find.byType(AlertDialog), matching: find.byType(Material))
          .first);
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(surface.height, lessThan(screen.height * 0.5),
          reason: '`showOnoteDialog` goes through `showGeneralDialog`, whose '
              'page fills the screen. Measured before the fix: 852 of 900, '
              'because `Row(mainAxisSize: min)` sizes its CROSS axis to its '
              'tallest child, and a `SizedBox` that sets only a width passes '
              'the height constraint straight through to the Slider');

      // The dot, at the size AND colour the pen will draw with.
      final dot = tester.widget<Container>(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byWidgetPredicate((w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).shape == BoxShape.circle)));
      expect((dot.decoration as BoxDecoration).color,
          onoteColorFromHex('#7A3E9D'));

      // **The drag tells the rest of the app once, at the end.**
      //
      // The owner: *"Dragging the slider is super laggy."* Every step used to
      // call `app.refresh()`, which notifies `AppState` and rebuilds the whole
      // shell — navigator, command bar and a canvas full of blocks — to move a
      // dot inside a dialog.
      var notified = 0;
      void count() => notified++;
      app.addListener(count);

      final before = app.penSize;
      final bar = tester.getRect(find.byType(Slider));
      final g = await tester.startGesture(bar.centerLeft + const Offset(8, 0));
      for (var i = 0; i < 12; i++) {
        await g.moveBy(const Offset(18, 0));
        await tester.pump();
      }
      final steps = app.penSize;
      await g.up();
      await tester.pumpAndSettle();
      app.removeListener(count);

      expect(steps, greaterThan(before),
          reason: 'the drag really did walk through a lot of sizes');
      expect(notified, 1,
          reason: 'once, when the finger came off — not once per step. '
              '`penSize` is a plain field that nothing reads until the next '
              'stroke is drawn');

      // Half-pixel steps, kept half-pixel: 19.5/39 added repeatedly in binary
      // floating point is what produced 3.4000000000000004.
      expect(app.penSize, snapPenSize(app.penSize),
          reason: 'the stored size IS a half — it does not merely print as one');
      expect(app.penSize * 2, (app.penSize * 2).roundToDouble());

      // And it goes further than it did: *"would be nice to be able to make
      // it a little bigger"*.
      final wide = await tester.startGesture(bar.centerLeft);
      await wide.moveTo(bar.centerRight + const Offset(40, 0));
      await tester.pump();
      await wide.up();
      await tester.pumpAndSettle();
      expect(app.penSize, kPenSizeMax);
      expect(kPenSizeMax, greaterThan(20.0));

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('the row shows two mixed colours, not four', (tester) async {
      // *"There are by default a lot of options for colours, more than most
      // people would want."* Six presets plus four recents plus two buttons
      // is twelve round things — and the recents were also what made the row
      // change width as you used it.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = await fixture(tester, 'onote_ink_two_');
      app.tool = Tool.pen;
      for (final hex in ['111111', '222222', '333333', '444444']) {
        app.rememberCustomColor(hex);
      }
      await drawTab(tester, app);

      // `rememberCustomColor` puts the newest first.
      expect(find.byTooltip('#444444'), findsOneWidget);
      expect(find.byTooltip('#333333'), findsOneWidget);
      expect(find.byTooltip('#222222'), findsNothing,
          reason: 'the rest are one click away in the picker, which keeps '
              'every one of them');
      // `rememberCustomColor` writes the list to settings, which arms a
      // 400ms workspace save; a pending timer fails the test at teardown.
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('picking a colour picks up the pen', (tester) async {
      // The click that being always-visible would otherwise have added:
      // choosing an ink colour is choosing to draw.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = await fixture(tester, 'onote_ink_picksup_');
      app.setTool(Tool.select);
      await drawTab(tester, app);

      await tester.tap(find.byTooltip('#2F6FB3'));
      await tester.pump();
      expect(app.tool, Tool.pen);
      expect(app.inkColor, '#2F6FB3');
      expect(app.toolWasAutomatic, isFalse,
          reason: 'chosen, so the mouse does not put it straight back down');
    });

    testWidgets('the eraser lights up while the pen button is held',
        (tester) async {
      // The reported fault was "the button does nothing", which covers both
      // the app never hearing the button and the app hearing it and doing
      // nothing. This is the half that tells them apart.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = await fixture(tester, 'onote_ink_eraser_');
      app.tool = Tool.pen;
      await drawTab(tester, app);

      IconButton eraser() => tester.widget<IconButton>(find.ancestor(
          of: find.byIcon(Icons.cleaning_services_outlined),
          matching: find.byType(IconButton)));

      expect(eraser().isSelected, isFalse);
      app.setPenErasing(true);
      await tester.pump();
      expect(eraser().isSelected, isTrue,
          reason: 'hold the button and the tool it is about to become is lit');
    });
  });

  group('what a pen button erases through', () {
    bool erases(PointerDeviceKind kind, int buttons, {bool near = false}) =>
        penGestureErases(kind: kind, buttons: buttons, penInRange: near);

    test('a barrel press promoted to a mouse right-button, pen in range', () {
      // Windows does not always hand a barrel press over as a stylus button.
      // It promotes it to a mouse right-button at the pen's own position —
      // which is what the ring around the pointer is — and requiring
      // `kind == stylus` threw exactly that away.
      expect(erases(PointerDeviceKind.mouse, kSecondaryButton, near: true),
          isTrue);
    });

    test('but not a real right-click, with no pen anywhere near', () {
      expect(erases(PointerDeviceKind.mouse, kSecondaryButton), isFalse);
    });

    test('and never a finger, pen in range or not', () {
      // A palm rests on the glass while a pen is in range constantly. This is
      // the one that must not widen.
      expect(erases(PointerDeviceKind.touch, kSecondaryButton, near: true),
          isFalse);
    });

    test('a mouse merely moving about near a pen does not erase', () {
      expect(erases(PointerDeviceKind.mouse, 0, near: true), isFalse);
    });
  });
}
