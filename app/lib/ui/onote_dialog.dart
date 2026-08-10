import 'package:flutter/material.dart';

/// Every Openote dialog opens through here (PLANNING "Consistency/UX":
/// "simple unobtrusive animations consistently … a little bounce when a
/// popup appears"). ONE transition — a quick fade with a slight scale
/// overshoot — rather than per-dialog choices that drift. 150 ms: present
/// enough to feel alive, short enough to never be waited on.
/// [growFrom], when given, is the GLOBAL point the dialog should appear to
/// grow out of — pass a tapped card's centre and the dialog reads as that
/// card opening ("the PDF viewer looking like it opens from the
/// thumbnail"). Omitted, the scale is centred.
Future<T?> showOnoteDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Offset? growFrom,
}) {
  Alignment origin = Alignment.center;
  if (growFrom != null) {
    final size = MediaQuery.of(context).size;
    origin = Alignment(
      (growFrom.dx / size.width) * 2 - 1,
      (growFrom.dy / size.height) * 2 - 1,
    );
  }
  final fromPoint = growFrom != null;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (ctx, _, __) => builder(ctx),
    transitionBuilder: (ctx, anim, _, child) {
      // easeOutBack overshoots ~1% past full size — the "little bounce".
      // The reverse curve is a plain ease-in: a bounce on the way OUT
      // would read as the dialog resisting dismissal.
      final eased = CurvedAnimation(
          parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
      return FadeTransition(
        opacity: CurvedAnimation(
            parent: anim, curve: Curves.easeOut, reverseCurve: Curves.easeIn),
        child: ScaleTransition(
          // From a point the growth is the whole story, so it starts small;
          // the centred default is a subtle settle.
          scale: Tween<double>(begin: fromPoint ? 0.75 : 0.94, end: 1)
              .animate(eased),
          alignment: origin,
          child: child,
        ),
      );
    },
  );
}
