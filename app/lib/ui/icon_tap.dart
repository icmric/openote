/// An icon button with **no tooltip**: for the controls everybody already knows
/// (undo, redo, zoom, close), where a bubble that appears after you stop on one
/// is clutter rather than help.
///
/// It is not unlabelled: the words are the label a screen reader reads, which is
/// all a tooltip was ever doing for someone who cannot see the icon. Anything
/// whose icon is not self-evident should keep its tooltip and use `IconButton`.
library;

import 'package:flutter/material.dart';

class IconTap extends StatelessWidget {
  const IconTap({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = 16,
    this.width = 30,
    this.height = 28,
    this.color,
    this.selected = false,
  });

  final IconData icon;

  /// Read out by a screen reader; never shown.
  final String label;
  final VoidCallback? onPressed;
  final double size;
  final double width;
  final double height;
  final Color? color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final base = color ?? IconTheme.of(context).color ?? scheme.onSurface;
    return Semantics(
      label: label,
      button: true,
      enabled: enabled,
      selected: selected,
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        height: height,
        child: InkResponse(
          mouseCursor: enabled
              ? WidgetStateMouseCursor.clickable
              : SystemMouseCursors.basic,
          radius: (width < height ? width : height) / 2 + 2,
          onTap: onPressed,
          child: Center(
            child: Icon(icon,
                size: size,
                color: enabled
                    ? (selected ? scheme.primary : base)
                    : base.withValues(alpha: .38)),
          ),
        ),
      ),
    );
  }
}
