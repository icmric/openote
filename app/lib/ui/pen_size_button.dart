/// **The pen's size, behind one control.**
///
/// The Draw row used to spend a button per preset plus a sixth for the exact
/// slider. The owner: *"Pen size doesnt change regularly so that can be hiden
/// behind a single menu. The whole drawing menu has sprawled out a lot."*
///
/// So: one button that draws the dot it would put down — the row still says
/// what the pen is set to, which is the only reason the presets were visible
/// at all — and a menu holding every preset and the slider behind it.
library;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';

/// Sentinel for the menu's last row, which opens the slider instead of
/// setting a size. Negative, because no pen is.
const double _kExact = -1;

class PenSizeButton extends StatelessWidget {
  const PenSizeButton({
    super.key,
    required this.app,
    required this.sizes,
    required this.label,
    required this.onExact,
  });

  final AppState app;

  /// The presets, in order. Passed in rather than imported so the one list in
  /// `command_bar.dart` stays the only one.
  final List<double> sizes;

  /// How a size reads — "2" rather than "2.0", shared with the slider.
  final String Function(double) label;

  /// Opens the exact-size slider. Also passed in, for the same reason.
  final Future<void> Function(BuildContext) onExact;

  /// A dot of diameter [v], clamped so the thinnest is still visible.
  Widget _dot(BuildContext context, double v, {required bool on}) {
    final scheme = Theme.of(context).colorScheme;
    final d = (v * 2.2).clamp(4.0, 18.0);
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? scheme.primary.withValues(alpha: .14) : null,
      ),
      child: Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? scheme.primary : context.surfaces.textSecondary,
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final l = L.of(context);
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final at = box.localToGlobal(box.size.bottomLeft(Offset.zero));
    final picked = await showMenu<double>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        for (final v in sizes)
          PopupMenuItem<double>(
            value: v,
            height: 36,
            child: Row(children: [
              _dot(context, v, on: app.penSize == v),
              const SizedBox(width: 8),
              Text(label(v), style: const TextStyle(fontSize: 13)),
            ]),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<double>(
          value: _kExact,
          height: 36,
          child: Row(children: [
            const SizedBox(width: 4),
            Icon(Icons.tune, size: 16, color: context.surfaces.textSecondary),
            const SizedBox(width: 12),
            Text(l.barPenSizeExact, style: const TextStyle(fontSize: 13)),
          ]),
        ),
      ],
    );
    if (picked == null) return;
    if (picked == _kExact) {
      if (context.mounted) await onExact(context);
      return;
    }
    app.penSize = picked;
    app.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Tooltip(
      message: l.barPenSize(label(app.penSize)),
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: OnoteRadius.smAll,
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            // The dot it would put down, so the row still advertises the size
            // without spending a button per preset to do it.
            _dot(context, app.penSize, on: true),
            Icon(Icons.arrow_drop_down,
                size: 16, color: context.surfaces.textSecondary),
          ]),
        ),
      ),
    );
  }
}
