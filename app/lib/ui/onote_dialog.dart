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

/// A one-field prompt — "New notebook", "Save as template". Returns the
/// trimmed text, or null when it was cancelled or left empty.
///
/// **The controller belongs to the dialog's own [State], and that is the whole
/// reason this exists.** The obvious spelling is to make one beside the await
/// and dispose it after:
///
/// ```dart
/// final c = TextEditingController();
/// try {
///   return await showOnoteDialog<String>(... TextField(controller: c) ...);
/// } finally {
///   c.dispose();
/// }
/// ```
///
/// That is wrong, and it is what made creating a notebook crash the app. The
/// future returned by a dialog completes the moment the route is POPPED, and
/// the 150 ms exit transition above runs *after* that — so the `TextField` is
/// still mounted, still animating out, and still being rebuilt. Its next
/// rebuild re-subscribes to `Listenable.merge([focusNode, controller])`, and
/// `addListener` on a disposed controller throws "A TextEditingController was
/// used after being disposed". The framework abandons that update half-done,
/// and when the route finally leaves the overlay an `InheritedElement` is
/// deactivated with dependents still registered — `'_dependents.isEmpty': is
/// not true`, full screen, on top of the app. The user saw only that last
/// assertion, several frames downstream of the actual mistake.
///
/// Owning the controller in the dialog's State ties its lifetime to the
/// widget's instead of to the await, so it cannot be disposed while anything
/// can still build with it. Every text prompt goes through here so the trap
/// has one place to not be in.
Future<String?> promptForText(
  BuildContext context, {
  required String title,
  required String okLabel,
  String? hintText,
}) async {
  final v = await showOnoteDialog<String>(
    context: context,
    builder: (_) =>
        _TextPrompt(title: title, okLabel: okLabel, hintText: hintText),
  );
  final t = v?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

class _TextPrompt extends StatefulWidget {
  const _TextPrompt(
      {required this.title, required this.okLabel, this.hintText});

  final String title;
  final String okLabel;
  final String? hintText;

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  final TextEditingController _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _ctl,
          autofocus: true,
          decoration: InputDecoration(hintText: widget.hintText),
          onSubmitted: (s) => Navigator.pop(context, s),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, _ctl.text),
              child: Text(widget.okLabel)),
        ],
      );
}
