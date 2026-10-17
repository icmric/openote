/// Pure ink-domain logic, kept out of the canvas widget so it can be tested.
///
/// The canvas's most intricate algorithms have historically lived inside
/// `_PageCanvasState`, where they cannot be unit-tested at all (review §E-2).
/// This file is where they move as they are touched.
library;

import 'package:flutter/gestures.dart';

import '../state/app_state.dart';

/// **Which pen buttons mean "erase".**
///
/// Three bits rather than one, because drivers disagree. `kPrimaryStylusButton`
/// shares its value with `kSecondaryButton` — that is how Windows Ink reports a
/// barrel press — and some pens report the same press as
/// `kSecondaryStylusButton`. Accepting all three costs nothing, because what
/// keeps a right-click mouse drag from erasing is the device KIND, never the
/// bit.
const int kPenEraseButtons =
    kPrimaryStylusButton | kSecondaryStylusButton | kSecondaryButton;

/// Does this pen event mean erase, whatever tool is selected?
///
/// Reported by a Galaxy Book / S Pen user: *"Holding the side button should
/// temporarily activate the eraser, then return to writing when released. This
/// doesn't work for me."*
///
/// Two things were wrong. Only one bit was checked, and the button was read
/// **once, at the instant of contact** — so pressing it while the pen floated
/// above the page did nothing, which is exactly how somebody uses it: press
/// first, then touch down. [heldWhileHovering] carries what the hover events
/// saw.
///
/// The pen's tail is unconditional: that end of a pen IS an eraser.
///
/// [penInRange] widens the KIND that is believed, and is the second half of
/// the same report coming back: *"pressing the button on my pen i have
/// defined to be the eraser does not change it … I have 2 buttons on my
/// pen, pressing one of them does cause a circle to come around the pointer
/// on screen but this may be a windows thing."*
///
/// That circle is Windows' own right-click indicator, which is the giveaway:
/// on Windows a barrel press is often not delivered as a stylus button at
/// all. It is **promoted to a mouse right-button**, so the app is handed a
/// `mouse` event at the pen's position while the pen itself is reporting
/// separately as a stylus. Requiring `kind == stylus` threw exactly that
/// away.
///
/// The guard against a real mouse is not the kind but the pen: [penInRange]
/// is only true while a stylus has reported itself in the last couple of
/// seconds, which somebody working with a mouse alone never satisfies.
bool penGestureErases({
  required PointerDeviceKind kind,
  required int buttons,
  bool heldWhileHovering = false,
  bool penInRange = false,
}) {
  if (kind == PointerDeviceKind.invertedStylus) return true;
  final fromAPen = kind == PointerDeviceKind.stylus ||
      // Some drivers report a pen with no kind at all rather than lying about
      // it; a pen in range is what makes that believable.
      (penInRange &&
          (kind == PointerDeviceKind.mouse ||
              kind == PointerDeviceKind.unknown));
  if (!fromAPen) return false;
  return (buttons & kPenEraseButtons) != 0 || heldWhileHovering;
}

/// Whether a touch pointer should draw rather than pan (INK-1 / INK-4).
///
/// Until 2026-07-27 the canvas routed **every** touch to pan unconditionally.
/// That is palm rejection implemented as "a finger never draws", which also
/// means ink is unreachable on a touch-only tablet — INK-1 explicitly requires
/// finger input. The distinction that rule missed: a resting palm is only a
/// hazard *while a pen is in use*. With no pen present, a finger is the only
/// input the user has.
///
/// - [activeTouches] is the number of touch pointers already down, **including
///   this one**. Two or more always means pan/zoom, whatever the mode — a
///   drawing tool must not make the canvas unnavigable.
/// - [stylusActive] means a stylus was seen recently (not necessarily now):
///   a palm rests between strokes as well as during them, so the window has to
///   outlive the gap.
/// - [penEverSeen] means one has been used on this machine **at all**, which
///   is the question that actually matters and the one a grace window only
///   approximated. Reported: *"it sometimes will still use finger input when
///   im drawing with the pen as drawing, it should never use regular touch to
///   draw when a pen has been used, and unless explicitly set it should always
///   under any circumstance treat touch inputs as navigational."* Two seconds
///   after the last stylus event is not "when a pen has been used": a hand
///   rests on the page for longer than that between words.
///
///   It does not take ink away from anybody. A touch-only tablet has never
///   seen a pen, so a finger still draws there, which is the whole of INK-1.
///   Somebody who writes with a pen on a machine that also has a touchscreen
///   gets what they asked for: a finger that navigates. `always` overrides it,
///   which is what explicitly set means.
bool touchShouldDraw({
  required TouchDrawing mode,
  required int activeTouches,
  required bool stylusActive,
  bool penEverSeen = false,
}) {
  if (mode == TouchDrawing.never) return false;
  if (activeTouches > 1) return false;
  if (mode == TouchDrawing.always) return true;
  return !penEverSeen && !stylusActive;
}
