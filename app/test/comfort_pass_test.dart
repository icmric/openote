// #41 and #42: buttons drawn too thin to aim at, and a cramped Sync dialog
// whose scroll bar sat on top of its controls.
//
// Measured on 8 November: a dialog's `TextButton` was PAINTED 20 px tall under
// the app's theme, inside a 40 px clickable box nobody can see. What is pinned
// here is the painted surface — the button's own `Material` — because that is
// what a person aims at.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/theme/onote_theme.dart';
import 'package:openote/theme/tokens.dart';
import 'package:openote/ui/onote_dialog.dart';
import 'package:openote/ui/sync_dialog.dart';

void main() {
  Future<double> paintedHeight(WidgetTester tester, Widget button) async {
    await tester.pumpWidget(MaterialApp(
      theme: onoteTheme(Brightness.light),
      home: Scaffold(body: Center(child: button)),
    ));
    final surface = find.descendant(
        of: find.byWidget(button), matching: find.byType(Material));
    return tester.getSize(surface.first).height;
  }

  for (final (name, button) in [
    ('TextButton', TextButton(onPressed: () {}, child: const Text('Done'))),
    (
      'TextButton.icon',
      TextButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.add),
          label: const Text('New'))
    ),
    ('FilledButton', FilledButton(onPressed: () {}, child: const Text('Use'))),
    (
      'OutlinedButton',
      OutlinedButton(onPressed: () {}, child: const Text('Close'))
    ),
  ]) {
    testWidgets('a themed $name is drawn at its stated height', (tester) async {
      expect(await paintedHeight(tester, button),
          greaterThanOrEqualTo(OnoteSize.buttonCompact),
          reason: 'compact density used to take 8 px off, drawing it 20 px');
    });
  }

  testWidgets('a scrolling dialog keeps a gutter for its scroll bar',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: onoteTheme(Brightness.light),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 200,
            child: DialogScrollBody(
              child: Container(key: const Key('content'), height: 600),
            ),
          ),
        ),
      ),
    ));
    final box = tester.getRect(find.byType(DialogScrollBody));
    final content = tester.getRect(find.byKey(const Key('content')));
    expect(box.right - content.right, kDialogScrollGutter,
        reason: 'the bar is drawn over the right edge; nothing may sit there');
    expect(kDialogScrollGutter, greaterThan(8 + 2),
        reason: "wider than the theme's bar and its margin");
  });

  test('the Sync dialog grows with the window and never collapses', () {
    expect(syncDialogBodyHeight(1025), greaterThan(600),
        reason: "the reporter's window: it was capped at 460");
    expect(syncDialogBodyHeight(768), lessThan(768 * 0.8));
    expect(syncDialogBodyHeight(300), 260);
  });
}
