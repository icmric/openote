/// **The command row's two faces** — the band of chrome that belongs to what
/// you are touching.
///
/// The owner, on the old contextual Maths tab: *"moving the user to a new menu
/// up there when entering maths mode without them doing anything is jarring
/// and its best to not force any navigation."*
///
/// The whole answer, in one sentence:
///
/// > The tab row belongs to the student. The command row belongs to the tab
/// > they chose — and lends itself to an equation while they are writing one.
///
/// ## The band that used to be here
///
/// These lived on a third strip of their own, 36 px under the command row,
/// permanent so that the chrome was 32 + 44 + 36 px in every state and the
/// canvas box never moved. The owner, once the app had been used for a while:
/// *"We still have this extra bar of options under the existing menu bar (the
/// one with page rule options, fitting, zoom, etc). Lets move all of that into
/// its own tab called 'Page'."*
///
/// Right — and the reasoning that put the band there survives the move
/// unharmed, because the invariant was never "there are three strips", it was
/// **the chrome does not change height**. It is 32 + 44 in every state now.
/// The page controls are a tab like any other, and the equation palette
/// borrows the command row without moving anybody's tab, exactly as it used to
/// borrow the row below.
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
library;

import 'package:flutter/material.dart';

import '../math/active_math.dart';
import '../math/evaluate.dart';
import '../model/page_stats.dart';
import '../l10n/l10n.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'math_bar.dart';

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

/// The page's own controls: ruling, sheet or canvas, paper, snap and zoom.
///
/// These were the View tab, then the page half of the object row, and are now
/// the Page tab — which is where somebody looking for "how do I make this page
/// ruled" would have looked first each time. The trip back is not an
/// admission that the band was wrong: the band existed to keep the chrome one
/// height, and it still is one height.
class PageFace extends StatelessWidget {
  const PageFace({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = L.of(context);
    Widget bg(String v, IconData icon, String tip) => IconButton(
          icon: Icon(icon, size: OnoteIcon.md),
          tooltip: l.objectRowBackground(tip),
          isSelected: app.pageProps.background == v,
          visualDensity: VisualDensity.compact,
          color: app.pageProps.background == v ? scheme.primary : null,
          onPressed: () => app.setBackground(v),
        );
    final paged = app.pageProps.isPaged;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      bg('blank', Icons.crop_din, l.objectRowBackgroundBlank),
      bg('grid', Icons.grid_4x4, l.objectRowBackgroundGrid),
      bg('dotted', Icons.apps, l.objectRowBackgroundDotted),
      bg('ruled', Icons.notes, l.objectRowBackgroundRuled),
      const _Sep(),
      // Canvas or paper. Per page, not per notebook: one notebook holds the
      // lecture you scribble on and the essay you hand in, and making you
      // choose once for both is why people keep two apps.
      IconButton(
        icon: Icon(paged ? Icons.description : Icons.dashboard_customize,
            size: OnoteIcon.md),
        tooltip: paged
            ? l.objectRowPageMode(app.pageProps.paper.name,
                app.pageProps.landscape ? l.objectRowLandscapeSuffix : '')
            : l.objectRowCanvasMode,
        isSelected: paged,
        visualDensity: VisualDensity.compact,
        color: paged ? scheme.primary : null,
        onPressed: () => app.setPageLayout(paged ? 'canvas' : 'paged'),
      ),
      // At the END of its group, so its arrival displaces nothing.
      if (paged)
        PopupMenuButton<String>(
          tooltip: l.objectRowPaperSize,
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
              child: Text(l.objectRowLandscape),
            ),
          ],
        ),
      const _Sep(),
      IconButton(
        icon: Icon(app.snapToGrid ? Icons.grid_goldenratio : Icons.grid_off,
            size: OnoteIcon.md),
        tooltip: app.snapToGrid ? l.objectRowSnapOn : l.objectRowSnapOff,
        isSelected: app.snapToGrid,
        visualDensity: VisualDensity.compact,
        color: app.snapToGrid ? scheme.primary : null,
        onPressed: app.toggleSnap,
      ),
      const _Sep(),
      IconButton(
        icon: const Icon(Icons.remove, size: OnoteIcon.md),
        tooltip: l.objectRowZoomOut,
        visualDensity: VisualDensity.compact,
        onPressed: () => app.canvas.setZoom(app.canvas.scale / 1.2),
      ),
      // **A button, and it says so before you press it.** It was the only
      // control on this row with no tooltip, sitting between a minus and a
      // plus, reading as the number those two were changing — and pressing
      // it resets the OFFSET as well as the scale, so somebody at the bottom
      // of a long page was thrown back to the top with no warning.
      Tooltip(
        message: l.objectRowZoomReset,
        child: AnimatedBuilder(
          animation: app.canvas,
          builder: (context, _) => TextButton(
            onPressed: app.canvas.reset,
            child: Text(l.objectRowZoomPercent((app.canvas.scale * 100).round()),
                style: OnoteType.small),
          ),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.add, size: OnoteIcon.md),
        tooltip: l.objectRowZoomIn,
        visualDensity: VisualDensity.compact,
        onPressed: () => app.canvas.setZoom(app.canvas.scale * 1.2),
      ),
      IconButton(
        icon: const Icon(Icons.fit_screen_outlined, size: OnoteIcon.md),
        tooltip: l.objectRowZoomFit,
        visualDensity: VisualDensity.compact,
        onPressed: () => app.canvas.fitTo(app.contentBounds().inflate(24)),
      ),
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
/// **In the tab row, not on the Page tab.** The owner: *"move the word count
/// to the bar next to all the other options up top, i think that makes the
/// most sense for placement."* It is the one thing here that is not a
/// setting — you do not change it, you read it — and a number you check
/// twenty times an hour has no business behind a tab. Characters and reading
/// time stay one click behind it, because those are not.
class WordCount extends StatefulWidget {
  const WordCount({super.key, required this.app, this.width});

  final AppState app;

  /// **Fixed width, when it sits in the tab row.**
  ///
  /// `CompactingToolbar` decides what folds from each control's DECLARED
  /// width, so a control that renders wider than it declared overflows the
  /// row it is in — and this one's width follows the number in it, which
  /// grows as the page does. Constrained here so the declared width is the
  /// truth. Null anywhere else, where it takes the room it needs.
  final double? width;

  @override
  State<WordCount> createState() => _WordCountState();
}

class _WordCountState extends State<WordCount> {
  /// **Stateful only for this.** Counting the whole page from scratch is 68 ms
  /// on a page of eight hundred blocks — four dropped frames — and this row
  /// rebuilds on every keystroke. The cache re-counts only the block that
  /// changed; the rest are string comparisons. Measured after: 0.2 ms.
  final _cache = PageStatsCache();

  // **Listens for itself.** The row around it is built once and reused until
  // something it shows actually changes (`memo.dart`) — and the word count is
  // the one thing in that row which changes with every character. So it
  // subscribes on its own account rather than being carried along by a
  // rebuild of everything else.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.app,
        builder: (context, _) => _build(context),
      );

  Widget _build(BuildContext context) {
    final app = widget.app;
    final s = context.surfaces;
    final l = L.of(context);
    final stats = _cache.of(app.blocks);
    return Tooltip(
      message: l.objectRowWordCount,
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
            child: _row(l.objectRowWords, _n(stats.words)),
          ),
          PopupMenuItem<void>(
            enabled: false,
            height: 34,
            child: _row(l.objectRowCharacters, _n(stats.characters)),
          ),
          PopupMenuItem<void>(
            enabled: false,
            height: 34,
            child: _row(l.objectRowCharactersNoSpaces, _n(stats.charactersNoSpaces)),
          ),
          const PopupMenuDivider(),
          PopupMenuItem<void>(
            enabled: false,
            height: 34,
            // Rounded UP and never zero: "0 min" reads as a failure, and
            // anything written at all takes a moment to read.
            child: _row(
                l.objectRowReadingTime,
                stats.words == 0
                    ? '—'
                    : l.objectRowMinutes(stats.readingMinutes)),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: SizedBox(
            width: widget.width == null ? null : widget.width! - 16,
            child: Text(
              // Through a plural message, not an `== 1` in Dart: "1 words" is
              // the sort of thing that makes a student trust nothing else the
              // app tells them, and every language draws that line somewhere
              // different — several have a form for two, and for a few.
              l.objectRowWordTally(stats.words, _n(stats.words)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: OnoteType.small.copyWith(color: s.textSecondary),
            ),
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
