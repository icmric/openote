// The pen's side button, which is meant to erase while it is held.
//
// Reported by a Galaxy Book / S Pen user: "Holding the side button should
// temporarily activate the eraser, then return to writing when released. This
// doesn't work for me."
//
// Two things were wrong, and both are the kind that only show up on hardware:
//
//   1. **One bit was checked.** Drivers disagree about which one a barrel
//      press sets, and this reporter's evidently does not use the one the
//      original was written against.
//   2. **It was read once, at the instant of contact.** Pressing the button
//      while the pen floated above the page did nothing — and pressing first,
//      then touching down, is exactly how a person uses it.
//
// Nobody working on this owns the hardware, so the decision lives in a pure
// function and the bit arithmetic is asserted here rather than discovered by
// somebody else's pen.

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/ink_ops.dart';

void main() {
  bool erases(PointerDeviceKind kind, int buttons, {bool held = false}) =>
      penGestureErases(
          kind: kind, buttons: buttons, heldWhileHovering: held);

  group('the button, however the driver spells it', () {
    test('every bit a barrel press is known to arrive as', () {
      // kPrimaryStylusButton and kSecondaryButton are the SAME value — that
      // is how Windows Ink reports a barrel press — and some pens use
      // kSecondaryStylusButton instead. All three have to work.
      for (final bit in [
        kPrimaryStylusButton,
        kSecondaryStylusButton,
        kSecondaryButton,
      ]) {
        expect(erases(PointerDeviceKind.stylus, bit), isTrue,
            reason: 'a barrel press reported as $bit must erase');
      }
    });

    test('the pen tail always erases, buttons or not', () {
      // That end of a pen IS an eraser; there is nothing to hold.
      expect(erases(PointerDeviceKind.invertedStylus, 0), isTrue);
      expect(erases(PointerDeviceKind.invertedStylus, kPrimaryButton), isTrue);
    });

    test('a plain pen tip writes', () {
      expect(erases(PointerDeviceKind.stylus, 0), isFalse);
      expect(erases(PointerDeviceKind.stylus, kPrimaryButton), isFalse);
    });
  });

  group('held before the pen lands', () {
    test('a button pressed while hovering still erases on contact', () {
      // The half that was missing. The touch-down event may carry no buttons
      // at all — what the hover events saw is what decides.
      expect(erases(PointerDeviceKind.stylus, 0, held: true), isTrue);
    });

    test('and letting go goes back to writing', () {
      expect(erases(PointerDeviceKind.stylus, 0), isFalse);
    });
  });

  group('what must NOT erase', () {
    test('a right-click mouse drag', () {
      // kSecondaryButton is in the erase set, so the device KIND is the only
      // thing standing between a right-drag and rubbing out somebody's work.
      expect(erases(PointerDeviceKind.mouse, kSecondaryButton), isFalse);
      expect(erases(PointerDeviceKind.mouse, kSecondaryButton, held: true),
          isFalse);
    });

    test('a finger, whatever it claims to be holding', () {
      expect(erases(PointerDeviceKind.touch, kSecondaryButton), isFalse);
      expect(erases(PointerDeviceKind.touch, 0, held: true), isFalse);
    });

    test('an unknown device', () {
      expect(erases(PointerDeviceKind.unknown, kSecondaryButton), isFalse);
    });
  });
}
