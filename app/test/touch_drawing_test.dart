// INK-1 / INK-4: when a finger draws, and when it must not.
//
// The regression pinned here is C-8: every touch used to be routed to pan
// unconditionally, so ink was simply unreachable on a touch-only tablet. Palm
// rejection is meant to be stylus-CONDITIONAL — a resting palm is only a hazard
// while a pen is in use.
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/ink_ops.dart';
import 'package:openote/state/app_state.dart';

bool draws(TouchDrawing mode, {int touches = 1, bool stylus = false}) =>
    touchShouldDraw(
        mode: mode, activeTouches: touches, stylusActive: stylus);

void main() {
  group('auto — the default', () {
    test('a finger draws when no stylus is around (C-8)', () {
      // The whole point: on a touch-only tablet this used to be false, which
      // made the pen tools dead controls.
      expect(draws(TouchDrawing.auto), isTrue);
    });

    test('a finger pans while a stylus is in use, so a palm cannot mark', () {
      expect(draws(TouchDrawing.auto, stylus: true), isFalse);
    });

    test('two fingers always pan, so the canvas stays navigable', () {
      expect(draws(TouchDrawing.auto, touches: 2), isFalse);
    });
  });

  group('explicit overrides', () {
    test('always draws even with a stylus present', () {
      expect(draws(TouchDrawing.always, stylus: true), isTrue);
    });

    test('always still yields to a second finger', () {
      // A pinch must never be interpreted as a stroke, whatever the setting —
      // otherwise zooming leaves a mark.
      expect(draws(TouchDrawing.always, touches: 2), isFalse);
    });

    test('never keeps the old strict behaviour', () {
      expect(draws(TouchDrawing.never), isFalse);
      expect(draws(TouchDrawing.never, stylus: false, touches: 1), isFalse);
    });
  });

  test('every mode has a label for the Draw tab', () {
    for (final m in TouchDrawing.values) {
      expect(m.label, isNotEmpty);
    }
  });
}
