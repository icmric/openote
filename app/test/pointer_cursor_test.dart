// A button that looks pressable should feel pressable.
//
// Reported: "when hovering over many buttons in the app, the pointer style
// doesnt change to the click style, it always stays as the regular pointer".
//
// This is not a list of missed widgets, it is one line of Flutter. Every
// Material button defaults to `WidgetStateMouseCursor.adaptiveClickable`:
//
//     return kIsWeb ? SystemMouseCursors.click : SystemMouseCursors.basic;
//
// So on desktop the framework hands back the plain arrow on purpose. These
// tests assert the app's own answer instead, and they are written against the
// theme rather than against any one screen — the reporter said "many buttons",
// and a per-screen test would go stale the moment a new screen was added.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/theme/onote_theme.dart';

void main() {
  MouseCursor cursorOf(WidgetStateProperty<MouseCursor?>? p) =>
      p?.resolve(const <WidgetState>{}) ?? SystemMouseCursors.basic;

  for (final brightness in [Brightness.light, Brightness.dark]) {
    group('${brightness.name} theme', () {
      final t = onoteTheme(brightness);

      test('every kind of button asks for the hand', () {
        final styles = <String, ButtonStyle?>{
          'filled': t.filledButtonTheme.style,
          'elevated': t.elevatedButtonTheme.style,
          'text': t.textButtonTheme.style,
          'outlined': t.outlinedButtonTheme.style,
          'icon': t.iconButtonTheme.style,
        };
        styles.forEach((name, style) {
          expect(cursorOf(style?.mouseCursor), SystemMouseCursors.click,
              reason: '$name buttons still hand back the desktop default');
        });
      });

      test('so do the controls people press just as often', () {
        expect(cursorOf(t.checkboxTheme.mouseCursor), SystemMouseCursors.click);
        expect(cursorOf(t.radioTheme.mouseCursor), SystemMouseCursors.click);
        expect(cursorOf(t.switchTheme.mouseCursor), SystemMouseCursors.click);
        expect(
            cursorOf(t.listTileTheme.mouseCursor), SystemMouseCursors.click);
      });

      test('a disabled control does NOT invite a click', () {
        // The whole point of a state-dependent cursor. A hand over a button
        // that will not respond is a worse lie than an arrow over one that
        // will.
        final disabled = t.filledButtonTheme.style?.mouseCursor
            ?.resolve(const <WidgetState>{WidgetState.disabled});
        expect(disabled, SystemMouseCursors.basic);
      });
    });
  }

  testWidgets('a real button in a real tree resolves to the hand',
      (tester) async {
    // The theme test above proves what the theme SAYS. This proves a widget
    // actually picks it up, which is the part that would silently regress if
    // a future Flutter changed how button styles merge.
    await tester.pumpWidget(MaterialApp(
      theme: onoteTheme(Brightness.light),
      home: Scaffold(
        body: Center(
          child: FilledButton(onPressed: () {}, child: const Text('Press')),
        ),
      ),
    ));

    final region = tester.widget<MouseRegion>(
      find
          .descendant(
              of: find.byType(FilledButton), matching: find.byType(MouseRegion))
          .first,
    );
    expect(region.cursor, SystemMouseCursors.click);
  });
}
