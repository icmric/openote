import 'package:flutter/widgets.dart';

/// First-party pan/zoom (Tech Eval §7.3: own transform, no InteractiveViewer).
/// Maps between screen space and page space. The model is unbounded, but
/// panning is clamped to the page origin (`clampToPage`) so the page can't be
/// lost off-screen (CANVAS-1 v0.3).
class CanvasController extends ChangeNotifier {
  double scale = 1.0;
  Offset offset = Offset.zero; // page-space origin's screen position

  static const minScale = 0.15;
  static const maxScale = 8.0;

  Matrix4 get matrix => Matrix4.identity()
    ..translate(offset.dx, offset.dy)
    ..scale(scale);

  Offset screenToPage(Offset screen) => (screen - offset) / scale;
  Offset pageToScreen(Offset page) => page * scale + offset;

  void panBy(Offset delta) {
    offset += delta;
    clampToPage();
    notifyListeners();
  }

  /// Zoom keeping the given screen point fixed (style guide §8.2).
  void zoomAt(Offset screenFocal, double factor) {
    final newScale = (scale * factor).clamp(minScale, maxScale);
    final pageFocal = screenToPage(screenFocal);
    scale = newScale;
    offset = screenFocal - pageFocal * scale;
    clampToPage();
    notifyListeners();
  }

  /// Restore an exact view (used by PDF export).
  void jumpTo(double s, Offset o) {
    scale = s;
    offset = o;
    notifyListeners();
  }

  void reset() {
    scale = 1.0;
    offset = Offset.zero; // page anchored top-left (OneNote-like)
    clampToPage();
    notifyListeners();
  }

  /// Last known viewport size (set by the canvas widget each layout).
  Size viewport = Size.zero;

  /// Current page-surface size in page coords (set by the canvas each build);
  /// used to clamp panning so the page can't be lost (CANVAS-1 v0.3).
  Size? pageSize;

  /// Pin the page's origin to the top-left: in normal zoom (page ≥ viewport)
  /// you can't reveal backdrop above/left of the page; when zoomed out
  /// (page < viewport) the page sits top-left and the backdrop shows to the
  /// right/below — so its bounds are visible, "page that can be a canvas".
  void clampToPage() {
    final ps = pageSize;
    if (ps == null || viewport == Size.zero) return;
    double axis(double o, double vp, double contentPx) {
      if (contentPx <= vp) return 0; // smaller than viewport → pin top-left
      return o.clamp(vp - contentPx, 0.0); // fills → stay within the page
    }

    offset = Offset(
      axis(offset.dx, viewport.width, ps.width * scale),
      axis(offset.dy, viewport.height, ps.height * scale),
    );
  }

  /// Initial view: page anchored top-left, filling the window (the page is at
  /// least viewport-wide, so no backdrop shows in normal use). Zooming out
  /// later reveals the page bounds — "a page that can become a canvas."
  void centerPage() {
    scale = 1.0;
    offset = Offset.zero;
    clampToPage();
    notifyListeners();
  }

  /// Fit [contentWidth] page-px to the viewport width, anchored top-left. Only
  /// zooms OUT (never past 100%), so a narrow page keeps its natural size while
  /// a wide imported page reveals its full width — including images placed to
  /// the right of the text at their original OneNote offsets, which otherwise
  /// sit off-screen at 100%. Vertical position stays at the top (scroll down
  /// for the rest), so text stays readable rather than shrinking to fit height.
  void fitWidth(double contentWidth) {
    if (viewport == Size.zero || contentWidth <= 0) {
      centerPage();
      return;
    }
    const pad = 24.0;
    final needed = contentWidth + pad;
    scale = needed <= viewport.width
        ? 1.0
        : (viewport.width / needed).clamp(minScale, 1.0);
    offset = Offset.zero;
    clampToPage();
    notifyListeners();
  }

  /// Center a page-space point in the viewport (find, navigation).
  void centerOn(Offset pagePoint) {
    offset = Offset(viewport.width / 2, viewport.height / 2) - pagePoint * scale;
    clampToPage();
    notifyListeners();
  }

  void setZoom(double newScale) {
    zoomAt(Offset(viewport.width / 2, viewport.height / 2), newScale / scale);
  }

  /// Zoom-to-fit a page-space rectangle (style guide §8.2).
  void fitTo(Rect pageBounds) {
    if (viewport == Size.zero || pageBounds.isEmpty) {
      reset();
      return;
    }
    const pad = 48.0;
    final sx = (viewport.width - pad * 2) / pageBounds.width;
    final sy = (viewport.height - pad * 2) / pageBounds.height;
    scale = (sx < sy ? sx : sy).clamp(minScale, maxScale);
    offset = Offset(
      (viewport.width - pageBounds.width * scale) / 2 - pageBounds.left * scale,
      (viewport.height - pageBounds.height * scale) / 2 - pageBounds.top * scale,
    );
    notifyListeners();
  }
}
