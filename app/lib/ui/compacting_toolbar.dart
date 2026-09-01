import 'package:flutter/material.dart';

/// **A row of controls that compacts before it scrolls.**
///
/// Reported: *"it doesnt handle resizing well (menus should either compact
/// as required or become sliding, again i believe the former is
/// cleaner)."* The command bar's trailing icon cluster used to answer a
/// narrow window by scrolling — a `SingleChildScrollView` that kept every
/// control reachable but hid however many did not fit off one edge, with
/// nothing on screen to say more was there. This keeps the controls that
/// fit inline, in the order they were given (first = kept longest), and
/// folds whatever does not fit into one trailing "More" menu instead —
/// itself hidden when everything already fits, so it never sits there
/// doing nothing.
///
/// Widths are supplied by the caller rather than measured live: every
/// control here is a small, fixed-configuration Material widget (a compact
/// `IconButton`, a compact `ActionChip`) whose rendered size does not
/// depend on window content the way a paragraph of text would, so a
/// constant measured once — see `command_bar_test.dart`'s width-guard
/// test, which fails loudly the moment a Flutter/Material upgrade changes
/// that — is exact rather than a guess, and avoids the one-frame layout
/// jump a live "build it, measure it, rebuild" pass would cost on every
/// resize.
class CompactingToolbar extends StatelessWidget {
  const CompactingToolbar({
    super.key,
    required this.controls,
    this.alignment = MainAxisAlignment.start,
    this.fillAvailable = false,
  });

  final List<ToolbarControl> controls;

  /// Where the visible controls sit when they need less room than [fillAvailable]
  /// gives them — `start` to hug the leading edge, `end` the trailing one.
  /// Meaningless (and ignored, since there is no extra room to place
  /// within) unless [fillAvailable] is also true.
  final MainAxisAlignment alignment;

  /// Occupy the FULL width offered rather than only what the visible
  /// controls need — what a caller under a flex parent (`Expanded`) wants,
  /// so `alignment: end` hugs the parent's own trailing edge the way this
  /// bar's scrolling predecessor always sat flush against the window edge.
  /// A caller that instead wants this to take only as much room as its
  /// content needs, so a sibling can claim the rest, leaves it false.
  final bool fillAvailable;

  /// The width of the "More" button itself, in the same units as each
  /// [ToolbarControl.width] — reserved whenever folding is even possible,
  /// so the decision of whether everything fits never has to be redone
  /// once the fold has already made room for its own trigger.
  static const double moreButtonWidth = 40;

  @override
  Widget build(BuildContext context) {
    if (controls.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      final maxWidth = constraints.maxWidth;
      final totalWidth = controls.fold<double>(0, (sum, c) => sum + c.width);

      Widget fill(Widget row, double used) {
        // A window narrower than the content needs is not a real case this
        // app's chrome will ever hit, but this must not throw a hard
        // overflow assertion even so — it renders at its natural size
        // rather than being forced into a width with nothing left to give.
        if (maxWidth.isFinite && used > maxWidth) {
          return OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: 0,
              maxWidth: double.infinity,
              child: row);
        }
        if (fillAvailable && maxWidth.isFinite) {
          return SizedBox(width: maxWidth, child: row);
        }
        return row;
      }

      if (!maxWidth.isFinite || totalWidth <= maxWidth) {
        final row = Row(
            mainAxisAlignment: alignment,
            mainAxisSize: MainAxisSize.min,
            children: [for (final c in controls) c.inline]);
        return fill(row, totalWidth);
      }

      var used = moreButtonWidth;
      var shown = 0;
      for (final c in controls) {
        final next = used + c.width;
        if (next > maxWidth) break;
        used = next;
        shown++;
      }
      final visible = controls.take(shown);
      final overflow = controls.skip(shown);
      final row = Row(
          mainAxisAlignment: alignment,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in visible) c.inline,
            _MoreMenu(overflow: overflow.toList()),
          ]);
      return fill(row, used);
    });
  }
}

/// One control in a [CompactingToolbar] — the same control shown inline or
/// folded, never a different one with different behaviour.
class ToolbarControl {
  const ToolbarControl({
    required this.width,
    required this.inline,
    required this.icon,
    required this.label,
    this.selected = false,
    this.onPressed,
    this.submenu,
  });

  /// The space this needs when shown inline, measured — see the class doc
  /// on [CompactingToolbar].
  final double width;

  /// What renders while there is room.
  final Widget inline;

  /// What the same control becomes once folded: an icon and a label in the
  /// "More" menu, standing in for whatever [inline] actually is.
  final IconData icon;
  final String label;

  /// Shown as a check beside the folded label, mirroring an inline
  /// button's own `isSelected` highlight — folding a control must not also
  /// lose the one thing an `isSelected` button was there to say.
  final bool selected;

  final VoidCallback? onPressed;

  /// Present only for a control that is itself a menu (Export…): its own
  /// items nest under this one's label when folded, rather than the
  /// control losing its submenu the moment it stops fitting inline.
  final List<ToolbarSubmenuItem>? submenu;
}

class ToolbarSubmenuItem {
  const ToolbarSubmenuItem(
      {required this.icon, required this.label, required this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.overflow});
  final List<ToolbarControl> overflow;

  @override
  Widget build(BuildContext context) {
    if (overflow.isEmpty) return const SizedBox.shrink();
    return MenuAnchor(
      builder: (context, controller, _) => IconButton(
        icon: const Icon(Icons.more_horiz, size: 18),
        tooltip: 'More',
        visualDensity: VisualDensity.compact,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        for (final c in overflow)
          if (c.submenu case final items?)
            SubmenuButton(
              leadingIcon: Icon(c.icon, size: 18),
              menuChildren: [
                for (final s in items)
                  MenuItemButton(
                    leadingIcon: Icon(s.icon, size: 18),
                    onPressed: s.onPressed,
                    child: Text(s.label),
                  ),
              ],
              child: Text(c.label),
            )
          else
            MenuItemButton(
              leadingIcon: Icon(c.icon, size: 18),
              trailingIcon: c.selected ? const Icon(Icons.check, size: 16) : null,
              onPressed: c.onPressed,
              child: Text(c.label),
            ),
      ],
    );
  }
}
