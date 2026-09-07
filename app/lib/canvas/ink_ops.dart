/// Pure ink-domain logic, kept out of the canvas widget so it can be tested.
///
/// The canvas's most intricate algorithms have historically lived inside
/// `_PageCanvasState`, where they cannot be unit-tested at all (review §E-2).
/// This file is where they move as they are touched.
library;

import 'package:flutter/gestures.dart';

import '../model/models.dart';
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
bool penGestureErases({
  required PointerDeviceKind kind,
  required int buttons,
  bool heldWhileHovering = false,
}) {
  if (kind == PointerDeviceKind.invertedStylus) return true;
  if (kind != PointerDeviceKind.stylus) return false;
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

/// **How tall a picture is, before anything has measured it.**
///
/// A PDF slide is written by `pdf_import.dart` with a width and no height:
/// the height is whatever the page turns out to be, and the importer has no
/// business guessing it. Everything that needs a slide's rectangle therefore
/// falls back to the size the block reported after it was laid out — and that
/// is written silently, during layout, without a rebuild. So the frame that
/// decides where the pictures are is the frame BEFORE any of them has said.
///
/// Reported: *"Auto pen colour doesnt work on images/pdfs either, still
/// coming up as white on a white pdf background."* Quite so — the fallback of
/// last resort is sixty pixels, so every slide was reckoned to be a sixty-
/// pixel strip and ink below it was ink on the page.
///
/// The picture's own proportions answer it without waiting for anybody:
/// `naturalW`/`naturalH` are stored the moment a picture is added, and the
/// view lays the picture out at exactly that aspect. Null when they are
/// missing — an old block, or a picture that has never loaded — and the
/// caller falls back as before.
double? aspectHeight(Block b) {
  final nw = (b.content['naturalW'] as num?)?.toDouble();
  final nh = (b.content['naturalH'] as num?)?.toDouble();
  if (nw == null || nh == null || nw <= 0 || nh <= 0 || b.w <= 0) return null;
  return b.w * nh / nw;
}
