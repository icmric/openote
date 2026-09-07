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
        expect(find.byIcon(Icons.add_circle_outline), findsOneWidget,
            reason: '$tool');
      }
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
