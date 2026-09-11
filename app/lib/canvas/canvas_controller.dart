import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
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
    // A hand on the wheel wins. Whatever the caret was asking for is stale
    // the moment the reader decides to look somewhere else.
    _stopFollowing();
    offset += delta;
    clampToPage();
    notifyListeners();
  }

  /// Zoom keeping the given screen point fixed (style guide §8.2).
  void zoomAt(Offset screenFocal, double factor) {
    _stopFollowing();
    final newScale = (scale * factor).clamp(minScale, maxScale);
    final pageFocal = screenToPage(screenFocal);
    scale = newScale;
    offset = screenFocal - pageFocal * scale;
    clampToPage();
    notifyListeners();
  }

  /// Restore an exact view (used by PDF export).
  void jumpTo(double s, Offset o) {
    _stopFollowing();
    scale = s;
    offset = o;
    notifyListeners();
  }

  void reset() {
    _stopFollowing();
    scale = 1.0;
    offset = Offset.zero; // page anchored top-left (OneNote-like)
    clampToPage();
    notifyListeners();
  }

  /// Last known viewport size (set by the canvas widget each layout).
  Size viewport = Size.zero;

  /// Where that viewport's top-left sits ON SCREEN, asked rather than stored:
  /// layout is the moment the size is known and the wrong moment to ask a
  /// render object where it ended up. The canvas installs this; anything that
  /// has a global rect (a caret, a selection) can then be compared against the
  /// part of the page a person can actually see.
  Offset? Function()? viewportOrigin;

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
    _stopFollowing();
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
    _stopFollowing();
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
    _stopFollowing();
    offset = Offset(viewport.width / 2, viewport.height / 2) - pagePoint * scale;
    clampToPage();
    notifyListeners();
  }

  // ── Keeping the caret in sight ──────────────────────────────────────────
  //
  // Reported: "when im typing and reach the bottom of the page, the text will
  // continue to expand downwards as expected, however the viewport does not
  // follow, meaning often times when typing larger things i have to manually
  // scroll down mid paragraph."
  //
  // Three things were asked for at once and they pull against each other:
  // gentle, keeps up with typing, and only when needed. A tween would satisfy
  // the first and lose the second — each keystroke would restart it, so a fast
  // typist gets a view that keeps easing towards a place the caret has already
  // left. What follows is a FOLLOWER rather than an animation: a target that
  // can be moved while it is being chased, closing a fixed fraction of the
  // remaining distance per unit time. Retargeting mid-flight costs nothing,
  // and the motion stays smooth because the distance is nearly always small.

  /// How quickly the view closes on the caret: the time to cover ~63% of the
  /// remaining distance. Small enough to keep up with a fast typist, long
  /// enough that a single line never reads as a jump.
  static const _followTau = 70.0; // ms

  /// Below this the chase is over — further frames would move the view by
  /// less than a pixel and cost a repaint each.
  static const _followEpsilon = 0.5;

  double? _followTargetDy;
  double? _lastTickMs;
  bool _following = false;

  /// True while the view is easing towards the caret. Tests assert on it; the
  /// canvas does not need to know.
  bool get isFollowingCaret => _following;

  void _stopFollowing() {
    _following = false;
    _followTargetDy = null;
    _lastTickMs = null;
  }

  /// Bring [globalRect] — a caret, say — back inside the viewport, moving the
  /// least that does it and moving gently.
  ///
  /// **Vertical only, and deliberately.** Typing grows a paragraph downwards,
  /// which is the direction that runs out of room; a view that also slid
  /// sideways as the caret crossed the page would be moving for reasons the
  /// writer did not ask about. Nothing happens at all while the caret sits in
  /// the comfortable band, which is almost always — this costs one rectangle
  /// comparison per keystroke.
  ///
  /// The band is measured in CARET HEIGHTS rather than pixels so it means the
  /// same thing in a heading, in body text, and at any zoom: room for a line
  /// and a half under the caret, half a line above it.
  void revealGlobalRect(Rect globalRect) {
    final origin = viewportOrigin?.call();
    if (origin == null || viewport == Size.zero) return;
    final lineish = math.max(globalRect.height, 8.0);
    final top = origin.dy + math.max(12.0, lineish * 0.5);
    final bottom =
        origin.dy + viewport.height - math.max(24.0, lineish * 1.5);
    if (bottom <= top) return; // a viewport too short to have a band

    // Where the view is heading, not where it is: mid-chase the caret has to
    // be judged against the destination, or every keystroke would ask for the
    // same scroll again and the two would race.
    final dy = _followTargetDy ?? offset.dy;
    final caretTop = globalRect.top + (dy - offset.dy);
    final caretBottom = globalRect.bottom + (dy - offset.dy);

    double want;
    if (caretBottom > bottom) {
      want = dy - (caretBottom - bottom);
    } else if (caretTop < top) {
      want = dy + (top - caretTop);
    } else {
      return; // already comfortable — the common case, and it does nothing
    }
    if ((want - offset.dy).abs() < _followEpsilon) return;
    _followTargetDy = want;
    if (_following) return;
    _following = true;
    _lastTickMs = null;
    SchedulerBinding.instance.scheduleFrameCallback(_followTick);
  }

  void _followTick(Duration stamp) {
    if (!_following) return;
    final target = _followTargetDy;
    if (target == null) {
      _stopFollowing();
      return;
    }
    final nowMs = stamp.inMicroseconds / 1000.0;
    // Clamped, because a dropped frame or a debugger pause must not teleport
    // the view: the follower would cover the whole distance in one step, which
    // is the jump this exists to avoid.
    final dt =
        _lastTickMs == null ? 16.0 : (nowMs - _lastTickMs!).clamp(1.0, 64.0);
    _lastTickMs = nowMs;

    final remaining = target - offset.dy;
    if (remaining.abs() < _followEpsilon) {
      offset = Offset(offset.dx, target);
      clampToPage();
      _stopFollowing();
      notifyListeners();
      return;
    }
    final before = offset.dy;
    offset = Offset(
        offset.dx, offset.dy + remaining * (1 - math.exp(-dt / _followTau)));
    clampToPage();
    // The clamp can refuse the move — at the bottom of the page there is
    // nowhere left to go. Stopping on "did not actually move" is what keeps
    // that from becoming a frame callback every frame for ever, which would
    // also stop any widget test from ever settling.
    if ((offset.dy - before).abs() < 0.01) {
      _stopFollowing();
      notifyListeners();
      return;
    }
    notifyListeners();
    SchedulerBinding.instance.scheduleFrameCallback(_followTick);
  }

  @override
  void dispose() {
    _stopFollowing();
    super.dispose();
  }

  void setZoom(double newScale) {
    zoomAt(Offset(viewport.width / 2, viewport.height / 2), newScale / scale);
  }

  /// Zoom-to-fit a page-space rectangle (style guide §8.2).
  void fitTo(Rect pageBounds) {
    _stopFollowing();
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
