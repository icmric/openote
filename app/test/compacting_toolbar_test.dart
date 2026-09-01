// A toolbar that compacts before it scrolls (style/UI consistency pass).
//
// Reported: "it doesnt handle resizing well (menus should either compact as
// required or become sliding, again i belive the former is cleaner)." This
// replaces the horizontal-scroll rescue the command bar's trailing icon
// cluster used with a fold: whatever does not fit inline moves into one
// trailing "More" menu instead of sliding off screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/ui/compacting_toolbar.dart';

void main() {
  // Wider than [CompactingToolbar.moreButtonWidth] (40) on purpose: with
  // items the SAME width as the fold button, "all N fit" and "N-1 fit plus
  // the button" land on the exact same total, leaving no width at which the
  // fold path is reachable at all. 50 gives every test below a real,
  // unambiguous window to sit in.
  const itemWidth = 50.0;

  ToolbarControl control(String label, {VoidCallback? onPressed}) =>
      ToolbarControl(
        width: itemWidth,
        icon: Icons.circle,
        label: label,
        onPressed: onPressed,
        inline: IconButton(
          icon: const Icon(Icons.circle, size: 18),
          tooltip: label,
          visualDensity: VisualDensity.compact,
          onPressed: onPressed,
        ),
      );

  Future<void> pump(WidgetTester tester, double width, List<ToolbarControl> cs) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
              width: width, height: 40, child: CompactingToolbar(controls: cs)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('everything shows inline when there is room', (tester) async {
    await pump(tester, 400, [control('a'), control('b'), control('c')]);
    expect(find.byTooltip('a'), findsOneWidget);
    expect(find.byTooltip('b'), findsOneWidget);
    expect(find.byTooltip('c'), findsOneWidget);
    expect(find.byTooltip('More'), findsNothing,
        reason: 'a fold button that folds nothing is worse than none');
  });

  testWidgets('the ones that do not fit fold into More, not off screen',
      (tester) async {
    // Room for the More button (40) plus exactly two controls (50 each) —
    // the third must fold: 40+50+50=140 fits in 145, +50 more (190) does not.
    await pump(tester, 145, [control('a'), control('b'), control('c')]);
    expect(find.byTooltip('a'), findsOneWidget);
    expect(find.byTooltip('b'), findsOneWidget);
    expect(find.byTooltip('c'), findsNothing,
        reason: 'folded, not clipped — it must not still be inline');
    expect(find.byTooltip('More'), findsOneWidget);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(MenuItemButton, 'c'), findsOneWidget,
        reason: 'the SAME control, reachable from the fold');
  });

  testWidgets('folded controls keep working — same callback, same effect',
      (tester) async {
    var tapped = 0;
    await pump(tester, 145, [
      control('a'),
      control('b'),
      control('c', onPressed: () => tapped++),
    ]);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'c'));
    await tester.pumpAndSettle();
    expect(tapped, 1);
  });

  testWidgets('priority is declaration order: the FIRST ones stay inline',
      (tester) async {
    await pump(tester, 145, [control('first'), control('second'), control('third')]);
    expect(find.byTooltip('first'), findsOneWidget);
    expect(find.byTooltip('second'), findsOneWidget);
    expect(find.byTooltip('third'), findsNothing);
  });

  testWidgets('a folded control keeps its selected state visible', (tester) async {
    final selected = ToolbarControl(
      width: itemWidth,
      icon: Icons.circle,
      label: 'on',
      selected: true,
      inline: const IconButton(
          icon: Icon(Icons.circle, size: 18), isSelected: true, onPressed: null),
    );
    await pump(tester, 145, [control('a'), control('b'), selected]);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    final item = tester.widget<MenuItemButton>(
        find.widgetWithText(MenuItemButton, 'on'));
    expect(item.trailingIcon, isNotNull,
        reason: 'the fold must not silently drop what isSelected was saying');
  });

  testWidgets('a folded submenu control (Export…) nests its own items',
      (tester) async {
    var exported = 0;
    final export = ToolbarControl(
      width: itemWidth,
      icon: Icons.ios_share,
      label: 'Export',
      inline: const SizedBox(width: itemWidth),
      submenu: [
        ToolbarSubmenuItem(
            icon: Icons.description,
            label: 'Markdown (.md)',
            onPressed: () => exported++),
      ],
    );
    await pump(tester, 145, [control('a'), control('b'), export]);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SubmenuButton, 'Export'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'Markdown (.md)'));
    await tester.pumpAndSettle();
    expect(exported, 1);
  });

  testWidgets('growing the available width unfolds controls again',
      (tester) async {
    await pump(tester, 145, [control('a'), control('b'), control('c')]);
    expect(find.byTooltip('c'), findsNothing);

    await pump(tester, 400, [control('a'), control('b'), control('c')]);
    expect(find.byTooltip('c'), findsOneWidget,
        reason: 'the fold is a function of the width, not a one-way trip');
    expect(find.byTooltip('More'), findsNothing);
  });

  testWidgets('a window too narrow for even one control still shows More',
      (tester) async {
    await pump(tester, 30, [control('a'), control('b')]);
    expect(find.byTooltip('a'), findsNothing);
    expect(find.byTooltip('b'), findsNothing);
    expect(find.byTooltip('More'), findsOneWidget,
        reason: 'everything folds rather than overflowing or crashing');
  });

  group('fillAvailable + alignment: end — the command bar\'s own mode', () {
    Future<void> pumpFilled(
        WidgetTester tester, double width, List<ToolbarControl> cs) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: 40,
              child: CompactingToolbar(
                controls: cs,
                alignment: MainAxisAlignment.end,
                fillAvailable: true,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('visible controls hug the box\'s trailing edge', (tester) async {
      await pumpFilled(tester, 300, [control('a'), control('b')]);
      final aRight = tester.getTopRight(find.byTooltip('a')).dx;
      final bRight = tester.getTopRight(find.byTooltip('b')).dx;
      // 'b' is the LAST declared control, so it sits closest to the edge —
      // the same "flush right" place the old reverse:true scrollview kept
      // its rightmost, always-visible end.
      expect(bRight, closeTo(300, 5));
      expect(aRight, lessThan(bRight));
    });

    testWidgets('the More button lands at the trailing edge once folded',
        (tester) async {
      await pumpFilled(tester, 90, [control('a'), control('b'), control('c')]);
      expect(find.byTooltip('More'), findsOneWidget);
      final moreRight = tester.getTopRight(find.byTooltip('More')).dx;
      expect(moreRight, closeTo(90, 5));
    });
  });

  testWidgets(
      'a compact 18px IconButton really is 40px — the width this file, and '
      'command_bar.dart, hardcode for every plain icon control', (tester) async {
    // Guards every `width: 40` used here and in `command_bar.dart`'s own
    // `CompactingToolbar` wiring: if a Flutter/Material upgrade changes a
    // compact IconButton's own rendered size, this fails loudly rather than
    // the fold point silently drifting off by a few pixels forever after.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: IconButton(
          key: const Key('probe'),
          icon: const Icon(Icons.circle, size: 18),
          visualDensity: VisualDensity.compact,
          onPressed: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('probe'))).width, 40);
    expect(CompactingToolbar.moreButtonWidth, 40);
  });
}
