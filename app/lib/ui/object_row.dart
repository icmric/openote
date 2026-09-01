/// **The object row** — the band of chrome that belongs to what you are
/// touching (plan: v0.23, "the object row").
///
/// The owner, on the old contextual Maths tab: *"moving the user to a new menu
/// up there when entering maths mode without them doing anything is jarring
/// and its best to not force any navigation."*
///
/// The whole answer, in one sentence:
///
/// > The tab row and the command row belong to the student. This row belongs
/// > to the page — and the page lends it to an equation while the student is
/// > writing one.
///
/// ## The invariant
///
/// **The chrome is 32 + 44 + 36 = 112 px, in every state of the app.** Nothing
/// in it grows, shrinks, moves or re-points; only this row's *contents*
/// change, and they cross-fade in place. The canvas's box therefore never
/// changes size or position, so there is no compensating pan to write and no
/// promise to keep by hand.
///
/// That is why the row is permanent rather than appearing with the equation.
/// A row that slid in would push the page down 36 px, and putting the page
/// back means panning it up 36 px — which `CanvasController.panBy` discards
/// whenever the content is shorter than the viewport (`clampToPage`'s `axis()`
/// returns 0 there). On a short page, or a zoomed-out one — exactly where a
/// student is when they press Alt+= for their first equation — the page would
/// jump. A conditional band cannot honour "don't move the user". A permanent
/// one honours it by construction.
///
/// ## Hard rules for anything added here
///
///  * **No `Spacer`, `Expanded` or `Flexible` children.** A flex child under
///    the unbounded constraint a horizontal scroll view offers is a hard
///    layout assertion — it is what once killed the entire Draw row. Push
///    things apart with a `SizedBox`.
///  * **Nothing may reach through `FocusManager`.** Every control here acts on
///    something the student is in the middle of writing; taking the caret
///    away to run a command is the bug this release opened with.
///  * **Opacity only when the face changes.** A slide says "a new thing
///    arrived from elsewhere"; a fade says "this row is now about that".
library;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import '../math/active_math.dart';
import '../math/evaluate.dart';
import '../model/page_stats.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'math_bar.dart';
import 'object_face.dart';

/// The row's height, everywhere. `OnoteSize.button` plus two above and below.
const double kObjectRowHeight = 36;

class ObjectRow extends StatelessWidget {
  const ObjectRow({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final face = objectFaceOf(app);
    return Container(
      height: kObjectRowHeight,
      decoration: BoxDecoration(
        // `chrome2` — the "insets within chrome" role — so the row reads as a
        // different layer and is never mistaken for a second command row.
        color: s.chrome2,
        border: Border(top: BorderSide(color: s.border)),
      ),
      child: ScrollConfiguration(
        behavior: const _RowScroll(),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: AnimatedSwitcher(
            duration: kMathMenuFade,
            // Keyed on the FACE, not on the widget, so moving between two
            // equations does not re-animate a row that is about to be
            // identical.
            switchInCurve: Curves.easeOut,
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: KeyedSubtree(
              key: ValueKey(face),
              child: _face(context, face),
            ),
          ),
        ),
      ),
    );
  }

  Widget _face(BuildContext context, ObjectFace face) {
    switch (face) {
      case ObjectFace.equation:
        final m = app.activeMath;
        // One frame at most: the face is derived from `editingBlockId`, which
        // is true before the equation editor has built and registered itself.
        // Empty, NEVER the page face — falling back would flash the page
        // controls for a frame every time an equation opened.
        if (m == null) return const SizedBox(height: kObjectRowHeight);
        return EquationFace(
          math: m,
          onDrawGraph: m.drawGraph,
          onEvaluateAtValue: m.evaluateAtValue,
          angleMode: app.angleMode,
          onToggleAngleMode: () {
            // The open equation and its neighbours are worked out by
            // `setAngleMode` itself — every route to it behaves the same,
            // and only it knows which mode the page was written in.
            app.setAngleMode(app.angleMode == AngleMode.degrees
                ? AngleMode.radians
                : AngleMode.degrees);
          },
          recentIds: app.recentMathIds,
        );
      case ObjectFace.page:
        return PageFace(app: app);
    }
  }
}

/// The palette, while an equation is being written.
///
/// **The parity rule, made mechanical.** This takes an [ActiveMathEditor] and
/// primitives — no `AppState`, no `Block`, no `BlockType`, no block id, no
/// placement. A standalone equation and one inside a sentence therefore
/// produce the same row in the same pixels, because nothing here is given
/// anything it could tell them apart with. The owner: *"A regular user is not
/// going to think a standalone maths box is any different to one in a text
/// box, so they must have exact feature and behaviour parrody."*
///
/// Keeping that a compile error rather than a review catch is the point;
/// `EquationPlacement` exists two files away, and discipline is what wore out
/// last time.
class EquationFace extends StatelessWidget {
  const EquationFace({
    super.key,
    required this.math,
    required this.angleMode,
    required this.onToggleAngleMode,
    this.onDrawGraph,
    this.onEvaluateAtValue,
    this.recentIds = const [],
  });

  final ActiveMathEditor math;

  /// Draw this equation, or null when it cannot be drawn from here.
  final VoidCallback? onDrawGraph;

  /// Plug a value into this equation, or null when it cannot be from here.
  final VoidCallback? onEvaluateAtValue;
  final AngleMode angleMode;
  final VoidCallback onToggleAngleMode;
  final List<String> recentIds;

  @override
  Widget build(BuildContext context) => MathBar(
        onInsert: math.insert,
        onDrawGraph: onDrawGraph,
        onEvaluateAtValue: onEvaluateAtValue,
        latexMode: math.latexMode,
        latexAvailable: math.latexAvailable,
        onToggleLatex: math.toggleLatex,
        angleMode: angleMode,
        onToggleAngleMode: onToggleAngleMode,
        recentIds: recentIds,
      );
}

/// The page's own controls, when nothing else is being written.
///
/// These are the page half of what used to be the View tab. They belong here
/// because "when nothing is selected, the thing you are touching is the page"
/// — and once they live here, the View tab holds nothing but four preferences
/// that Settings already carries, so the tab goes.
class PageFace extends StatelessWidget {
  const PageFace({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget bg(String v, IconData icon, String tip) => IconButton(
          icon: Icon(icon, size: OnoteIcon.md),
          tooltip: 'Background: $tip',
          isSelected: app.pageProps.background == v,
          visualDensity: VisualDensity.compact,
          color: app.pageProps.background == v ? scheme.primary : null,
          onPressed: () => app.setBackground(v),
        );
    final paged = app.pageProps.isPaged;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(width: 2),
      bg('blank', Icons.crop_din, 'blank'),
      bg('grid', Icons.grid_4x4, 'grid'),
      bg('dotted', Icons.apps, 'dotted'),
      bg('ruled', Icons.notes, 'ruled'),
      const _Sep(),
      // Canvas or paper. Per page, not per notebook: one notebook holds the
      // lecture you scribble on and the essay you hand in, and making you
      // choose once for both is why people keep two apps.
      IconButton(
        icon: Icon(paged ? Icons.description : Icons.dashboard_customize,
            size: OnoteIcon.md),
        tooltip: paged
            ? 'Page mode: ${app.pageProps.paper.name}'
                '${app.pageProps.landscape ? ' landscape' : ''} '
                '— click for canvas'
            : 'Canvas mode: boundless — click for pages',
        isSelected: paged,
        visualDensity: VisualDensity.compact,
        color: paged ? scheme.primary : null,
        onPressed: () => app.setPageLayout(paged ? 'canvas' : 'paged'),
      ),
      // At the END of its group, so its arrival displaces nothing.
      if (paged)
        PopupMenuButton<String>(
          tooltip: 'Paper size',
          icon: const Icon(Icons.aspect_ratio, size: OnoteIcon.md),
          onSelected: (v) => v == '_rotate'
              ? app.setPageLayout('paged',
                  landscape: !app.pageProps.landscape)
              : app.setPageLayout('paged', paper: v),
          itemBuilder: (_) => [
            for (final p in PaperSize.all)
              CheckedPopupMenuItem(
                value: p.name,
                checked: app.pageProps.paperSize == p.name,
                child: Text(p.name),
              ),
            const PopupMenuDivider(),
            CheckedPopupMenuItem(
              value: '_rotate',
              checked: app.pageProps.landscape,
              child: const Text('Landscape'),
            ),
          ],
        ),
      const _Sep(),
      IconButton(
        icon: Icon(app.snapToGrid ? Icons.grid_goldenratio : Icons.grid_off,
            size: OnoteIcon.md),
        tooltip: app.snapToGrid
            ? 'Snap to grid: ON (grid shows while dragging)'
            : 'Snap to grid: OFF — free placement',
        isSelected: app.snapToGrid,
        visualDensity: VisualDensity.compact,
        color: app.snapToGrid ? scheme.primary : null,
        onPressed: app.toggleSnap,
      ),
      const _Sep(),
      IconButton(
        icon: const Icon(Icons.remove, size: OnoteIcon.md),
        tooltip: 'Zoom out  (Ctrl+-)',
        visualDensity: VisualDensity.compact,
        onPressed: () => app.canvas.setZoom(app.canvas.scale / 1.2),
      ),
      // **A button, and it says so before you press it.** It was the only
      // control on this row with no tooltip, sitting between a minus and a
      // plus, reading as the number those two were changing — and pressing
      // it resets the OFFSET as well as the scale, so somebody at the bottom
      // of a long page was thrown back to the top with no warning.
      Tooltip(
        message: 'Back to 100% and the top of the page  (Ctrl+0)',
        child: AnimatedBuilder(
          animation: app.canvas,
          builder: (context, _) => TextButton(
            onPressed: app.canvas.reset,
            child: Text('${(app.canvas.scale * 100).round()}%',
                style: OnoteType.small),
          ),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.add, size: OnoteIcon.md),
        tooltip: 'Zoom in  (Ctrl+=)',
        visualDensity: VisualDensity.compact,
        onPressed: () => app.canvas.setZoom(app.canvas.scale * 1.2),
      ),
      IconButton(
        icon: const Icon(Icons.fit_screen_outlined, size: OnoteIcon.md),
        tooltip: 'Zoom to fit content',
        visualDensity: VisualDensity.compact,
        onPressed: () => app.canvas.fitTo(app.contentBounds().inflate(24)),
      ),
      const _Sep(),
      _WordCount(app: app),
      const SizedBox(width: 4),
    ]);
  }
}

/// **How much have I written?**
///
/// PLANNING: *"Word counter, char count, estimated reading time."* Every
/// essay has a word limit on it, and until now the only way to find out was
/// to export the page and paste it somewhere else.
///
/// The count is on the row, because that is where things about the PAGE live
/// and a word limit is a thing about the page. The other two are one click
/// behind it: a bare number is what a student checks twenty times an hour,
/// and characters and reading time are not.
class _WordCount extends StatefulWidget {
  const _WordCount({required this.app});

  final AppState app;

  @override
  State<_WordCount> createState() => _WordCountState();
}

class _WordCountState extends State<_WordCount> {
  /// **Stateful only for this.** Counting the whole page from scratch is 68 ms
  /// on a page of eight hundred blocks — four dropped frames — and this row
  /// rebuilds on every keystroke. The cache re-counts only the block that
  /// changed; the rest are string comparisons. Measured after: 0.2 ms.
  final _cache = PageStatsCache();

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final s = context.surfaces;
    final stats = _cache.of(app.blocks);
    return Tooltip(
      message: 'Words on this page — click for characters and reading time',
      child: PopupMenuButton<void>(
        position: PopupMenuPosition.under,
        tooltip: '',
        // Wide enough for the longest label and the longest number a page
        // will realistically carry, so the four rows line up as a column of
        // figures rather than four ragged pairs.
        constraints: const BoxConstraints(minWidth: 224, maxWidth: 260),
        itemBuilder: (_) => [
          PopupMenuItem<void>(
            enabled: false,
            height: 34,
            child: _row('Words', _n(stats.words)),
          ),
          PopupMenuItem<void>(
            enabled: false,
            height: 34,
            child: _row('Characters', _n(stats.characters)),
          ),
          PopupMenuItem<void>(
            enabled: false,
            height: 34,
            child: _row('Without spaces', _n(stats.charactersNoSpaces)),
          ),
          const PopupMenuDivider(),
          PopupMenuItem<void>(
            enabled: false,
            height: 34,
            // Rounded UP and never zero: "0 min" reads as a failure, and
            // anything written at all takes a moment to read.
            child: _row(
                'Reading time',
                stats.words == 0
                    ? '—'
                    : '${stats.readingMinutes} min'),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(
            // Singular when it is one, because "1 words" is the sort of thing
            // that makes a student trust nothing else the app tells them.
            '${_n(stats.words)} ${stats.words == 1 ? 'word' : 'words'}',
            style: OnoteType.small.copyWith(color: s.textSecondary),
          ),
        ),
      ),
    );
  }

  static Widget _row(String label, String value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(label,
                style: OnoteType.small, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 16),
          Text(value,
              style: OnoteType.small.copyWith(fontWeight: FontWeight.w600)),
        ],
      );

  /// Thousands separated, because 12480 and 1248 are one glance apart and a
  /// word limit is exactly the number you are squinting at.
  static String _n(int v) {
    final digits = v.toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }
}

class _Sep extends StatelessWidget {
  const _Sep();
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 20,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: context.surfaces.border,
      );
}

/// A row wider than the window must SCROLL, not clip: clipped pixels do not
/// hit-test, so on a narrow window the rightmost controls simply stop
/// responding with no visible reason. Mouse and trackpad are added to the drag
/// devices for the same reason the toolbar's own scroller adds them.
class _RowScroll extends MaterialScrollBehavior {
  const _RowScroll();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}
