/// Pure ink-domain logic, kept out of the canvas widget so it can be tested.
///
/// The canvas's most intricate algorithms have historically lived inside
/// `_PageCanvasState`, where they cannot be unit-tested at all (review §E-2).
/// This file is where they move as they are touched.
library;

import '../state/app_state.dart';

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
bool touchShouldDraw({
  required TouchDrawing mode,
  required int activeTouches,
  required bool stylusActive,
}) {
  if (mode == TouchDrawing.never) return false;
  if (activeTouches > 1) return false;
  if (mode == TouchDrawing.always) return true;
  return !stylusActive;
}
