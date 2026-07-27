// Regression coverage for "fit page on open" (the navigator/image-visibility
// fix): a wide imported page zooms out to reveal its full width — including
// images placed to the right of the text — while a narrow page stays at 100%.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/canvas/canvas_controller.dart';

void main() {
  test('fitWidth zooms out wide pages, leaves narrow pages at 100%', () {
    final c = CanvasController()
      ..viewport = const Size(940, 700)
      ..pageSize = const Size(1500, 1400);

    // Wide page (content extends to x=1400): scale down so the full width fits.
    c.fitWidth(1400);
    expect(c.scale, closeTo(940 / (1400 + 24), 0.001));
    expect(c.scale, lessThan(1.0));
    expect(c.offset, Offset.zero, reason: 'anchored top-left');
    // The right edge of content is now within the viewport.
    expect(1400 * c.scale, lessThanOrEqualTo(940));

    // Narrow page: never enlarge past natural size.
    c.fitWidth(600);
    expect(c.scale, 1.0);
    expect(c.offset, Offset.zero);

    // Degenerate viewport falls back to the default view.
    final c2 = CanvasController()..viewport = Size.zero;
    c2.fitWidth(1400);
    expect(c2.scale, 1.0);
  });
}
