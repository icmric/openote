// v1.0.2 bug 13: "a wide Markdown table is cut off, not scrolled."
//
// It was in a horizontal scroll view all along, but a desktop mouse cannot drag
// one and nothing showed there was more, so the columns past the box's edge
// were out of reach for anyone using a mouse.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/markdown/md_render.dart';

void main() {
  Future<void> pump(WidgetTester tester, String md) async {
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            child: MarkdownView(
                text: md, baseStyle: const TextStyle(fontSize: 14)),
          ),
        ),
      ),
    ));
    await tester.pump(); // the metrics notification lands after first layout
  }

  ScrollPosition tablePosition(WidgetTester tester) => tester
      .state<ScrollableState>(find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(Scrollable)))
      .position;

  const wide = '| Alpha column | Bravo column | Charlie column | Delta column | Echo column |\n'
      '|---|---|---|---|---|\n'
      '| one | two | three | four | five |';

  testWidgets('a table wider than its box shows a scroll bar', (tester) async {
    await pump(tester, wide);
    expect(tablePosition(tester).maxScrollExtent, greaterThan(0));
    final bar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(bar.thumbVisibility, isTrue,
        reason: 'nothing else says there are more columns');
  });

  testWidgets('the bar can be dragged, and a wheel or trackpad reaches the end',
      (tester) async {
    await pump(tester, wide);
    expect(tester.widget<Scrollbar>(find.byType(Scrollbar)).interactive, isTrue,
        reason: 'draggable everywhere, not only where Material defaults it on');
    final pos = tablePosition(tester);
    final view = tester.getRect(find.byType(SingleChildScrollView));
    tester.binding.handlePointerEvent(PointerScrollEvent(
        position: view.center, scrollDelta: const Offset(2000, 0)));
    await tester.pump();
    expect(pos.pixels, pos.maxScrollExtent);
  });

  testWidgets('a table that fits looks exactly as it did', (tester) async {
    await pump(tester, '| a | b |\n|---|---|\n| 1 | 2 |');
    expect(tablePosition(tester).maxScrollExtent, 0);
    final bar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(bar.thumbVisibility, isFalse);
    final sv = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView));
    expect(sv.padding, EdgeInsets.zero, reason: 'no room kept for a bar');
  });
}
