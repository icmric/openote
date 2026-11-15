/// **Review writing**: the panel, the sheet it becomes on a narrow window, and
/// the entry in the status bar.
///
/// One list, three kinds of mistake. Each kind has its own **Fix all**; every
/// item has a tick (accept) and a cross (ignore); the item the page is on is
/// opened to show why and what else it could be. When the page would keep at
/// least [kReviewMinCanvas] beside it, it is a side panel, resizable by its left
/// edge; when it would not, the same content rises from the status bar as a
/// sheet instead, so the page keeps its full width. See
/// `spell/writing_review.dart` for what is checked and how a fix is written.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/onote_text.dart';
import '../l10n/l10n.dart';
import '../spell/writing_review.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../theme/tokens.dart';
import 'side_panel.dart';
import 'toast.dart';

/// The colour of each kind, the same ones the underlines use.
Color reviewColor(ReviewCategory c) => switch (c) {
      ReviewCategory.spelling => const Color(0xFFE5484D),
      ReviewCategory.grammar => const Color(0xFF4C8DF6),
      ReviewCategory.punctuation => const Color(0xFFD9971F),
    };

String _categoryName(L l, ReviewCategory c) => switch (c) {
      ReviewCategory.spelling => l.reviewSpelling,
      ReviewCategory.grammar => l.reviewGrammar,
      ReviewCategory.punctuation => l.reviewPunctuation,
    };

String _dialectName(L l, EnglishDialect? d) => switch (d) {
      EnglishDialect.australian => l.settingsEnglishAU,
      EnglishDialect.british => l.settingsEnglishGB,
      EnglishDialect.american => l.settingsEnglishUS,
      EnglishDialect.canadian => l.settingsEnglishCA,
      EnglishDialect.indian => l.settingsEnglishIN,
      null => '',
    };

// ── The status bar entry ─────────────────────────────────────────────────────

/// The count, at the right of the status bar. Nothing at all while the person
/// is not writing English, and nothing until the page has been looked at once.
class ReviewChip extends StatelessWidget {
  const ReviewChip({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final review = app.review;
    return ListenableBuilder(
      listenable: review,
      builder: (context, _) {
        if (!review.checked) return const SizedBox.shrink();
        final l = L.of(context);
        final n = review.count;
        final scheme = Theme.of(context).colorScheme;
        final open = app.openPanel == SidePanelKind.review;
        final clear = n == 0;
        final fg = open
            ? scheme.onPrimary
            : clear
                ? OnoteColors.success
                : scheme.primary;
        // No tooltip: the chip says what it is. The label is for a screen reader.
        return Semantics(
          label: l.reviewTooltip,
          button: true,
          excludeSemantics: true,
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            borderRadius: BorderRadius.circular(10),
            onTap: app.toggleReview,
            child: Container(
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: open
                    ? scheme.primary
                    : clear
                        ? null
                        : scheme.primary.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.spellcheck, size: 14, color: fg),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(clear ? l.reviewChipClear : l.reviewChip(n),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: clear ? FontWeight.w400 : FontWeight.w600,
                        color: fg)),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

// ── The side panel ───────────────────────────────────────────────────────────

class ReviewPanel extends StatelessWidget {
  const ReviewPanel({super.key, required this.app, required this.maxWidth});
  final AppState app;

  /// The widest it may be dragged to, which leaves the page its minimum.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final s = context.surfaces;
    final width = app.reviewPanelW.clamp(
        kReviewPanelMin, maxWidth < kReviewPanelMin ? kReviewPanelMin : maxWidth);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      // The panel's left edge is its handle, the way the navigator's columns
      // are resized, and it draws the hairline the shell draws for the others.
      MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          key: const ValueKey('review-resize'),
          behavior: HitTestBehavior.opaque,
          // Dragging left widens it: the panel is on the right.
          onHorizontalDragUpdate: (d) {
            app.reviewPanelW = (app.reviewPanelW - d.delta.dx).clamp(
                kReviewPanelMin,
                maxWidth < kReviewPanelMin ? kReviewPanelMin : maxWidth);
            app.refresh();
          },
          onHorizontalDragEnd: (_) => app.setReviewPanelW(app.reviewPanelW),
          child: Container(
            width: 5,
            alignment: Alignment.center,
            color: s.chrome,
            child: Container(width: 1, color: s.border),
          ),
        ),
      ),
      SidePanel(
        title: l.reviewTitle,
        icon: Icons.spellcheck,
        width: width,
        onClose: app.closePanel,
        child: ReviewBody(app: app, narrow: false),
      ),
    ]);
  }
}

// ── The sheet ────────────────────────────────────────────────────────────────

/// The same content over the lower part of a narrow window, with a grab bar,
/// the three kinds as tabs, and touch-sized controls. Sits in the shell's
/// column between the page and the status bar, so the page above it shrinks to
/// what is left instead of being covered.
class ReviewSheet extends StatelessWidget {
  const ReviewSheet({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final s = context.surfaces;
    final h = MediaQuery.sizeOf(context).height;
    return Container(
      height: (h * 0.5).clamp(260.0, 560.0),
      decoration: BoxDecoration(
        color: s.chrome,
        border: Border(top: BorderSide(color: s.border)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x33000000), blurRadius: 18, offset: Offset(0, -4))
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Column(children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
                color: s.border, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(children: [
            Icon(Icons.spellcheck,
                size: 16, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(l.reviewTitle,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: l.navClose,
              onPressed: app.closePanel,
            ),
          ]),
        ),
        Expanded(child: ReviewBody(app: app, narrow: true)),
      ]),
    );
  }
}

// ── The content, shared ──────────────────────────────────────────────────────

class ReviewBody extends StatefulWidget {
  const ReviewBody({super.key, required this.app, required this.narrow});
  final AppState app;
  final bool narrow;

  @override
  State<ReviewBody> createState() => _ReviewBodyState();
}

class _ReviewBodyState extends State<ReviewBody> {
  AppState get app => widget.app;
  WritingReview get review => app.review;
  ReviewCategory _tab = ReviewCategory.spelling;
  final FocusNode _focus = FocusNode(debugLabel: 'review-writing');

  @override
  void initState() {
    super.initState();
    // Opened on purpose, so the keys (arrows, Enter, Delete, Esc) are the
    // panel's from the first moment, whatever had them before.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.escape) {
      app.closePanel();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      review.step(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      review.step(-1);
      return KeyEventResult.handled;
    }
    final cur = review.current;
    if (cur == null) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      if (cur.canFix) review.accept(cur);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      review.ignore(cur);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _fixAll(ReviewCategory c) {
    final l = L.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final n = review.fixAll(c);
    if (n == 0) return;
    messenger.hideCurrentSnackBar();
    messenger.showToast(SnackBar(
      content: Text(switch (c) {
        ReviewCategory.spelling => l.reviewFixedSpelling(n),
        ReviewCategory.grammar => l.reviewFixedGrammar(n),
        ReviewCategory.punctuation => l.reviewFixedPunctuation(n),
      }),
      // One undo takes the whole batch back.
      action: SnackBarAction(label: l.navUndo, onPressed: app.undo),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final s = context.surfaces;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _key,
      child: ListenableBuilder(
        listenable: review,
        builder: (context, _) {
          final items = review.items;
          final byCat = {
            for (final c in ReviewCategory.values) c: review.itemsOf(c)
          };
          // A tab that has emptied gives way to one that has not.
          if (byCat[_tab]!.isEmpty) {
            final next =
                ReviewCategory.values.where((c) => byCat[c]!.isNotEmpty);
            if (next.isNotEmpty) _tab = next.first;
          }
          // The card that is open belongs to what is on show.
          review.focusCategory = widget.narrow ? _tab : null;
          final sub = Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 12, 8),
            child: Text(
                l.reviewSubtitle(
                    items.length, _dialectName(l, app.writingDialect)),
                style: TextStyle(fontSize: 11, color: s.textSecondary)),
          );
          if (items.isEmpty) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              sub,
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(children: [
                  const Icon(Icons.check_circle_outline,
                      size: 16, color: OnoteColors.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(l.reviewAllClear,
                        style: TextStyle(
                            fontSize: 12, color: s.textSecondary)),
                  ),
                ]),
              ),
            ]);
          }
          final cats = widget.narrow
              ? [_tab]
              : [
                  for (final c in ReviewCategory.values)
                    if (byCat[c]!.isNotEmpty) c
                ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sub,
              if (widget.narrow) _tabs(context, byCat),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    for (final c in cats) ...[
                      _categoryHeader(context, c, byCat[c]!.length),
                      for (final it in byCat[c]!)
                        it.key == review.current?.key
                            ? _ItemCard(
                                key: ValueKey('card-${it.key}'),
                                item: it,
                                review: review,
                                narrow: widget.narrow)
                            : _ItemRow(
                                key: ValueKey('row-${it.key}'),
                                item: it,
                                review: review,
                                narrow: widget.narrow),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _tabs(BuildContext context, Map<ReviewCategory, List<ReviewItem>> by) {
    final l = L.of(context);
    final s = context.surfaces;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(children: [
        for (final c in ReviewCategory.values) ...[
          if (c != ReviewCategory.values.first) const SizedBox(width: 6),
          Expanded(
            child: InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
              borderRadius: BorderRadius.circular(8),
              onTap: by[c]!.isEmpty
                  ? null
                  : () => setState(() {
                        _tab = c;
                        review.focusCategory = c;
                      }),
              child: Container(
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: _tab == c ? scheme.primary : s.border),
                  color: _tab == c ? scheme.primary.withValues(alpha: .12) : null,
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: reviewColor(c), shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text('${_categoryName(l, c)} ${by[c]!.length}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: by[c]!.isEmpty
                                ? s.textDisabled
                                : _tab == c
                                    ? s.textPrimary
                                    : s.textSecondary)),
                  ),
                ]),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _categoryHeader(BuildContext context, ReviewCategory c, int n) {
    final l = L.of(context);
    final s = context.surfaces;
    final fixable = review.itemsOf(c).any((i) => i.canFix);
    return Container(
      height: widget.narrow ? 38 : 34,
      padding: const EdgeInsets.only(left: 16, right: 8),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: s.border))),
      child: Row(children: [
        if (!widget.narrow) ...[
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: reviewColor(c), shape: BoxShape.circle)),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text('${_categoryName(l, c).toUpperCase()} · $n',
              style: TextStyle(
                  fontSize: 11,
                  letterSpacing: .6,
                  fontWeight: FontWeight.w700,
                  color: s.textSecondary)),
        ),
        TextButton.icon(
          style: TextButton.styleFrom(
              minimumSize: Size(0, widget.narrow ? 32 : 26),
              padding: const EdgeInsets.symmetric(horizontal: 10)),
          icon: const Icon(Icons.done_all, size: 14),
          label: Text(l.reviewFixAll,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          onPressed: fixable ? () => _fixAll(c) : null,
        ),
      ]),
    );
  }
}

/// A closed item: the words, what they would become, and a tick and a cross.
class _ItemRow extends StatelessWidget {
  const _ItemRow(
      {super.key,
      required this.item,
      required this.review,
      required this.narrow});
  final ReviewItem item;
  final WritingReview review;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final s = context.surfaces;
    final f = item.finding;
    final fix = item.firstChoice;
    final box = narrow ? 40.0 : 26.0;
    return InkWell(
      mouseCursor: WidgetStateMouseCursor.clickable,
      onTap: () => review.open(item),
      child: Container(
        constraints: BoxConstraints(minHeight: narrow ? 44 : 32),
        padding: const EdgeInsets.only(left: 16, right: 6),
        child: Row(children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: f.word,
                    style: TextStyle(
                        color: s.textSecondary,
                        decoration: TextDecoration.lineThrough,
                        decorationColor: reviewColor(item.category))),
                if (fix != null) ...[
                  TextSpan(
                      text: '  →  ',
                      style: TextStyle(color: s.textSecondary)),
                  TextSpan(
                      text: fix.isEmpty ? l.reviewRemove : fix,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: narrow ? 13 : 12),
            ),
          ),
          if (item.canFix)
            _IconAction(
                key: const ValueKey('review-accept'),
                icon: Icons.check,
                tooltip: l.reviewAccept,
                color: OnoteColors.success,
                size: box,
                onTap: () => review.accept(item)),
          _IconAction(
              key: const ValueKey('review-ignore'),
              icon: Icons.close,
              tooltip: l.reviewIgnore,
              color: s.textSecondary,
              size: box,
              onTap: () => review.ignore(item)),
        ]),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction(
      {super.key,
      required this.icon,
      required this.tooltip,
      required this.color,
      required this.size,
      required this.onTap});
  final IconData icon;

  /// Read out by a screen reader. Not shown as a tooltip: a tick and a cross
  /// beside a suggestion need no bubble.
  final String tooltip;
  final Color color;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        label: tooltip,
        button: true,
        excludeSemantics: true,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, size: size > 30 ? 18 : 16, color: color)),
        ),
      );
}

/// The open item: why it was flagged, the words around it, every choice, and
/// what to do about it.
class _ItemCard extends StatelessWidget {
  const _ItemCard(
      {super.key,
      required this.item,
      required this.review,
      required this.narrow});
  final ReviewItem item;
  final WritingReview review;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final s = context.surfaces;
    final scheme = Theme.of(context).colorScheme;
    final f = item.finding;
    final ctx = item.around;
    final why = item.category == ReviewCategory.spelling
        ? l.reviewNotInDictionary
        : f.message;
    final chipH = narrow ? 34.0 : 26.0;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        color: s.canvas,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.primary),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (why.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(why,
                style: TextStyle(fontSize: 11, height: 1.35, color: s.textSecondary)),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '…${ctx.before}'),
              TextSpan(
                  text: f.word,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.lineThrough,
                      decorationColor: reviewColor(item.category))),
              TextSpan(text: '${ctx.after}…'),
            ]),
            style: TextStyle(fontSize: narrow ? 13 : 12, height: 1.45),
          ),
        ),
        if (item.canFix)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (i, c) in item.choices.take(5).indexed)
                SizedBox(
                  height: chipH,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: Size(0, chipH),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: const StadiumBorder(),
                      side: BorderSide(
                          color: i == 0 ? scheme.primary : s.border),
                      foregroundColor:
                          i == 0 ? scheme.primary : s.textPrimary,
                    ),
                    onPressed: () => review.accept(item, choice: c),
                    child: Text(c.isEmpty ? l.reviewRemove : c,
                        style: TextStyle(
                            fontSize: narrow ? 13 : 12,
                            fontWeight:
                                i == 0 ? FontWeight.w600 : FontWeight.w400)),
                  ),
                ),
            ]),
          ),
        Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (item.canFix)
            FilledButton(
              style: FilledButton.styleFrom(
                  minimumSize: Size(0, narrow ? 36 : 28),
                  padding: const EdgeInsets.symmetric(horizontal: 14)),
              onPressed: () => review.accept(item),
              child: Text(l.reviewAccept,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          TextButton(
            style: TextButton.styleFrom(
                minimumSize: Size(0, narrow ? 36 : 28),
                foregroundColor: s.textSecondary),
            onPressed: () => review.ignore(item),
            child: Text(l.reviewIgnore, style: const TextStyle(fontSize: 12)),
          ),
          if (item.category == ReviewCategory.spelling)
            TextButton(
              style: TextButton.styleFrom(
                  minimumSize: Size(0, narrow ? 36 : 28),
                  foregroundColor: s.textSecondary),
              onPressed: () => review.addToDictionary(item),
              child: Text(l.reviewAddToDictionary,
                  style: const TextStyle(fontSize: 12)),
            ),
        ]),
      ]),
    );
  }
}
