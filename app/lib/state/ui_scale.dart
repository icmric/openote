/// How big the whole window is drawn: the presets, and how far a window can
/// honestly go.
///
/// **The window can always be made small again.** A preset that does not fit the
/// window would push Settings, the one place that can undo it, off the edge.
/// So the size shown is never larger than the window can hold: the layout is
/// always at least [kMinLogicalWidth] by [kMinLogicalHeight] units, which is
/// enough for the Settings dialog and the toolbar button that opens it.
library;

import 'dart:math' as math;
import 'dart:ui' show Size;

/// The sizes offered, as multiples of normal. 1.0 is the default, and it is
/// what the app starts at: there is no guess at a "recommended" size, because
/// the screen's physical size is not something the app is told.
const List<double> kUiScales = [0.75, 0.9, 1.0, 1.25, 1.5, 1.75, 2.0];

/// The smallest area, in layout units, the interface is ever squeezed into.
/// The Settings dialog is 620 wide and 380 high; this leaves room for its
/// margins and for the toolbar that holds the button that opens it.
const double kMinLogicalWidth = 720;
const double kMinLogicalHeight = 520;

/// The scale to draw at, given the one chosen and the window's size.
///
/// Smaller-than-normal sizes always apply (they only give the layout more
/// room). Larger ones apply up to the point where the layout would fall below
/// [kMinLogicalWidth] x [kMinLogicalHeight], and never drop below normal.
double effectiveUiScale(double chosen, Size window) {
  if (chosen <= 1.0) return chosen;
  if (window.width <= 0 || window.height <= 0) return 1.0;
  final fit = math.min(
      window.width / kMinLogicalWidth, window.height / kMinLogicalHeight);
  return math.max(1.0, math.min(chosen, fit));
}

/// "125%" for 1.25.
String uiScalePercent(double scale) => '${(scale * 100).round()}%';
