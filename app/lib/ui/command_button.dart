/// The labelled command button — style guide §7a.5.
///
/// **Why this exists.** The command bar had two kinds of control that looked
/// like two different applications. Home, Draw and View are `IconButton`s,
/// which take their foreground from `onSurface` — neutral, the same ink as the
/// rest of the chrome. Insert was built from `TextButton.icon`, and Material 3
/// colours a `TextButton` with `colorScheme.primary`. So every command on the
/// Insert tab rendered in the accent colour while every command on every other
/// tab rendered in ink, and switching tabs changed the palette of the toolbar.
///
/// That is not a colour choice, it is an unmade one: the accent is reserved for
/// *state* (§3.5 — selection, focus, the active tool), and spending it on "this
/// is a button" leaves nothing to say "this one is on". Insert's commands are
/// not more important than Home's; they merely needed labels, because
/// `Icons.functions` does not read as "equation" the way `B` reads as bold.
///
/// So the rule this widget encodes: **a label does not change a command's
/// colour.** Icon-only and icon-plus-label commands are the same control at
/// two widths.
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A command-bar button with an icon and a text label.
///
/// Use wherever an `IconButton` would be used but the icon alone is not
/// self-explanatory. Disabled when [onPressed] is null, and disabled looks the
/// same here as it does on an `IconButton` — one greyed vocabulary across the
/// bar, per §7a.2.
class CommandButton extends StatelessWidget {
  const CommandButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final enabled = onPressed != null;
    final button = TextButton.icon(
      icon: Icon(icon, size: OnoteIcon.sm),
      label: Text(label),
      onPressed: onPressed,
      style: TextButton.styleFrom(
        // The whole point: ink, not accent.
        foregroundColor: s.textPrimary,
        disabledForegroundColor: s.textDisabled,
        textStyle: OnoteType.small,
        visualDensity: VisualDensity.compact,
        minimumSize: const Size(0, OnoteSize.button),
        padding: const EdgeInsets.symmetric(horizontal: OnoteSpace.x4),
      ),
    );
    final tip = tooltip;
    if (tip == null || !enabled) return button;
    return Tooltip(message: tip, child: button);
  }
}

/// A command-bar button whose "icon" is a short word — `H2`, `H3`.
///
/// Same colours and same metrics as [CommandButton]; it exists because two
/// characters of bold text is a better glyph for a heading level than any icon
/// in the set, not because it is a different kind of control.
class CommandTextButton extends StatelessWidget {
  const CommandTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final button = TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: s.textPrimary,
        disabledForegroundColor: s.textDisabled,
        textStyle: OnoteType.uiStrong,
        visualDensity: VisualDensity.compact,
        minimumSize: const Size(30, OnoteSize.button),
        padding: const EdgeInsets.symmetric(horizontal: OnoteSpace.x3),
      ),
      child: Text(label),
    );
    final tip = tooltip;
    if (tip == null || onPressed == null) return button;
    return Tooltip(message: tip, child: button);
  }
}
