// Review writing takes the page to a word by sliding, not cutting.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/canvas_controller.dart';

void main() {
  CanvasController make() => CanvasController()
    ..viewport = const Size(800, 600)
    ..pageSize = const Size(1200, 4000);

  testWidgets('it arrives where a jump would, by way of the places between',
      (t) async {
    final jump = make()..centerOn(const Offset(600, 1500));
    final c = make();
    c.glideTo(const Offset(600, 1500));
    expect(c.offset, Offset.zero, reason: 'nothing has moved yet');
    await t.pump();
    await t.pump(const Duration(milliseconds: 150));
    expect(c.offset.dy, lessThan(0));
    expect(c.offset.dy, greaterThan(jump.offset.dy),
        reason: 'part of the way, not there yet');
    await t.pump(const Duration(milliseconds: 400));
    expect(c.offset, jump.offset);
  });

  testWidgets('a hand on the wheel ends it where it is', (t) async {
    final c = make();
    c.glideTo(const Offset(600, 1500));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    final mid = c.offset;
    c.panBy(const Offset(0, 5));
    await t.pump(const Duration(milliseconds: 500));
    expect(c.offset.dy, closeTo(mid.dy + 5, 0.01));
  });
}
