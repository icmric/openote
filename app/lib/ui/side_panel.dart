/// The one right-hand panel scaffold (style guide §7c).
///
/// **Why this exists.** Five panels — study, planner, find-tags, links, page
/// outline — each hand-rolled the same anatomy at four different widths
/// (240, 240, 260, 300, 320), each picked its own background by branching on
/// `Brightness.dark`, each drew its own border on top of the shell's divider,
/// and each wrote its own header row with slightly different type. The 2026-08
/// UI review named that as one of the two things making the app feel unfinished:
/// not any single panel being wrong, but no two of them agreeing.
///
/// So the anatomy is decided once here and the panels supply content. A new
/// panel that uses this is consistent by construction; a new panel that does
/// not is a review flag.
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A right-hand panel: title, optional actions, body, optional footer.
class SidePanel extends StatelessWidget {
  const SidePanel({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    required this.onClose,
    this.actions = const [],
    this.banner,
    this.footer,
  });

  /// Shown in `overline` — the app's only all-caps style, reserved for panel
  /// titles and list-group labels so it keeps meaning something.
  final String title;

  /// The 16px leading icon. Panels are switched between, so each needs a mark
  /// that is recognisable before the word is read.
  final IconData icon;

  /// Trailing icon actions, before the close button. Compact icon buttons with
  /// tooltips (§7a.2).
  final List<Widget> actions;

  /// A full-width strip between the header and the body — a catch-up notice, a
  /// warning. Kept out of [child] so it cannot be scrolled away from.
  final Widget? banner;

  /// The panel's content. Given the remaining height; scroll inside it.
  final Widget child;

  /// A row pinned to the bottom, above a hairline.
  final Widget? footer;

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    return Container(
      width: OnoteSize.panelWidth,
      // `chrome`, never `canvas`: in dark mode a panel on the canvas colour
      // merged into the page, so the two regions became one black rectangle.
      color: s.chrome,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHeader(
              title: title, icon: icon, actions: actions, onClose: onClose),
          if (banner != null) banner!,
          Expanded(child: child),
          if (footer != null) ...[
            Divider(height: 1, color: s.border),
            footer!,
          ],
        ],
      ),
    );
  }
}

/// The panel header, separately available for surfaces that need the anatomy
/// without the frame.
class PanelHeader extends StatelessWidget {
  const PanelHeader({
    super.key,
    required this.title,
    required this.icon,
    required this.onClose,
    this.actions = const [],
  });

  final String title;
  final IconData icon;
  final List<Widget> actions;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          OnoteSpace.x5, OnoteSpace.x5, OnoteSpace.x2, OnoteSpace.x2),
      child: Row(children: [
        Icon(icon, size: OnoteIcon.sm, color: s.textSecondary),
        const SizedBox(width: OnoteSpace.x3),
        Expanded(
          child: Text(title.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: OnoteType.overline.copyWith(color: s.textSecondary)),
        ),
        ...actions,
        IconButton(
          icon: const Icon(Icons.close, size: OnoteIcon.sm),
          visualDensity: VisualDensity.compact,
          tooltip: 'Close $title',
          onPressed: onClose,
        ),
      ]),
    );
  }
}

/// A list-group label inside a panel — `overline`, the same style as a panel
/// title, because they are the same kind of thing: a heading over rows.
class PanelLabel extends StatelessWidget {
  const PanelLabel(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
            OnoteSpace.x5, OnoteSpace.x5, OnoteSpace.x5, OnoteSpace.x1),
        child: Text(text.toUpperCase(),
            style: OnoteType.overline
                .copyWith(color: color ?? context.surfaces.textSecondary)),
      );
}

/// The empty state every panel owes the user (style guide §7c, §7).
///
/// One strong line saying what is not here, one short paragraph saying what
/// would put something here, then real actions. **Never skeleton bars** —
/// placeholder grey rectangles read as content that failed to load, which is
/// the opposite of the reassurance an empty state is for.
class PanelEmpty extends StatelessWidget {
  const PanelEmpty({
    super.key,
    required this.headline,
    required this.body,
    this.actions = const [],
  });

  final String headline;
  final String body;

  /// Built with [PanelAction]. Empty is allowed only when there is genuinely
  /// nothing the user could do from here.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          OnoteSpace.x5, OnoteSpace.x4, OnoteSpace.x5, OnoteSpace.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(headline,
              style: OnoteType.uiStrong.copyWith(color: s.textPrimary)),
          const SizedBox(height: OnoteSpace.x4),
          Text(body,
              style: OnoteType.small
                  .copyWith(color: s.textSecondary, height: 1.45)),
          if (actions.isNotEmpty) const SizedBox(height: OnoteSpace.x5),
          ...actions,
        ],
      ),
    );
  }
}

/// One action inside a [PanelEmpty] — an icon and a label in `primary`.
class PanelAction extends StatelessWidget {
  const PanelAction(
      {super.key,
      required this.icon,
      required this.label,
      required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: OnoteRadius.mdAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: OnoteSpace.x3),
        child: Row(children: [
          Icon(icon, size: OnoteIcon.sm, color: primary),
          const SizedBox(width: OnoteSpace.x3),
          // Expanded, not bare: an unconstrained Text in a Row overflows a
          // fixed-width panel, which is how a 23px overflow shipped in the
          // planner's empty state.
          Expanded(
            child:
                Text(label, style: OnoteType.ui.copyWith(color: primary)),
          ),
        ]),
      ),
    );
  }
}
