/// Editing an equation that lives inside a sentence (plan: v0.18 §7).
///
/// **Why this exists at all.** The live editor now draws an inline `$…$` as
/// the equation rather than as source, which is the whole point — but it also
/// means the caret can no longer walk into the middle of it. Without a way in,
/// making inline maths look right would have made it read-only, which is a
/// worse bug than the one being fixed. This is the way in: one click.
///
/// **How it differs from the plan, stated rather than buried.** §7 chose an
/// overlay drawn at exactly the equation's rect, matching font size and
/// baseline so the swap is invisible. What is built here anchors a small
/// editing card *under* the equation instead, with the equation in the
/// sentence updating live as you type. The reason is honest: pixel-matching a
/// `WidgetSpan`'s baseline inside a `TextField` across three platforms and two
/// themes is a lot of fragile measurement to buy a transition effect, and
/// every frame of it would be a place for the equation to jump. The card
/// carries the same [MathField] and the same maths bar the block editor uses,
/// so the *editing* is identical; only the choreography is simpler.
library;

import 'package:flutter/material.dart';

import '../math/active_math.dart';
import '../math/math_editor.dart';
import '../math/math_field.dart';
import '../math/math_view.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';

/// Opens the editing card for one inline equation.
///
/// [anchor] is the equation's rect in global coordinates. [onChanged] receives
/// the new LaTeX on every keystroke — the sentence rewrites live, so what the
/// student sees in the card and what is in their note never differ. An empty
/// string means "the equation is gone", which the caller removes.
class InlineMathPopover {
  InlineMathPopover._(this._entry);

  final OverlayEntry _entry;
  static InlineMathPopover? _open;

  static bool get isOpen => _open != null;

  static void dismiss() {
    _open?._entry.remove();
    _open = null;
  }

  static void show(
    BuildContext context, {
    required AppState app,
    required Rect anchor,
    required String latex,
    required ValueChanged<String> onChanged,
    VoidCallback? onDone,
  }) {
    dismiss();
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    // An equation the tree can't hold opens as source, exactly as the block
    // does — never silently reshaped on the first keystroke (§6.6).
    final editor = MathEditor.open(latex);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _InlineMathCard(
        app: app,
        anchor: anchor,
        editor: editor,
        latex: latex,
        onChanged: onChanged,
        onDone: () {
          dismiss();
          onDone?.call();
        },
      ),
    );
    overlay.insert(entry);
    _open = InlineMathPopover._(entry);
  }
}

class _InlineMathCard extends StatefulWidget {
  const _InlineMathCard({
    required this.app,
    required this.anchor,
    required this.editor,
    required this.latex,
    required this.onChanged,
    required this.onDone,
  });

  final AppState app;
  final Rect anchor;
  final MathEditor? editor;
  final String latex;
  final ValueChanged<String> onChanged;
  final VoidCallback onDone;

  @override
  State<_InlineMathCard> createState() => _InlineMathCardState();
}

class _InlineMathCardState extends State<_InlineMathCard> {
  final _fieldKey = GlobalKey<MathFieldState>();
  late final TextEditingController _source =
      TextEditingController(text: widget.latex);
  late bool _latexMode = widget.editor == null;

  @override
  void initState() {
    super.initState();
    widget.editor?.placeAtEnd();
  }

  @override
  void dispose() {
    widget.app.clearActiveMath(this);
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surfaces = Theme.of(context).extension<OnoteSurfaces>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? OnoteSurfaces.dark
            : OnoteSurfaces.light);
    final screen = MediaQuery.of(context).size;
    const cardWidth = 420.0;

    // Under the equation by default; above it when there is no room below, so
    // the card never hangs off the bottom of the window.
    final below = widget.anchor.bottom + 6;
    final wantsAbove = below + 220 > screen.height;
    final left = widget.anchor.left.clamp(8.0, screen.width - cardWidth - 8);

    // The palette is the toolbar's Maths tab, the same one the block editor
    // drives — so this card holds ONLY the equation. Registered from `build`
    // without a notify, matching the block editor.
    widget.app.setActiveMath(ActiveMathEditor(
      owner: this,
      insert: (item) => _fieldKey.currentState?.insertItem(item),
      latexMode: _latexMode,
      latexAvailable: widget.editor != null,
      toggleLatex: () => setState(() {
        _latexMode = !_latexMode;
        if (_latexMode) _source.text = widget.editor?.latex ?? '';
      }),
    ));

    return Stack(children: [
      // Tapping anywhere else finishes — the same "click away commits" rule
      // every other editor in the app follows.
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: widget.onDone,
        ),
      ),
      Positioned(
        left: left.toDouble(),
        top: wantsAbove ? null : below,
        bottom: wantsAbove ? screen.height - widget.anchor.top + 6 : null,
        width: cardWidth,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(10),
          color: surfaces.raised,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_latexMode)
                  TextField(
                    controller: _source,
                    autofocus: true,
                    maxLines: null,
                    style: const TextStyle(
                        fontFamily: 'JetBrains Mono', fontSize: 13),
                    decoration: const InputDecoration(
                        isDense: true, border: OutlineInputBorder()),
                    onChanged: widget.onChanged,
                  )
                else
                  MathField(
                    key: _fieldKey,
                    editor: widget.editor!,
                    compact: false,
                    textStyle: TextStyle(
                        fontSize: 20, color: surfaces.textPrimary),
                    onChanged: widget.onChanged,
                    onExit: (_) => widget.onDone(),
                  ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: widget.onDone,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: const Text('Done', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ]);
  }
}

/// The equation as it appears INSIDE the sentence: drawn, and clickable.
///
/// A `WidgetSpan`'s child is a real widget, which is what makes one click into
/// an equation possible at all — the `TextField` around it will never route a
/// keystroke here, but it does route a tap.
class InlineMathAtom extends StatelessWidget {
  const InlineMathAtom({
    super.key,
    required this.latex,
    required this.style,
    this.onTap,
  });

  final String latex;
  final TextStyle style;

  /// Called with the equation's rect in global coordinates.
  final void Function(Rect anchor)? onTap;

  @override
  Widget build(BuildContext context) {
    final math = OnoteMath(latex, textStyle: style, compact: true);
    if (onTap == null) return math;
    return Builder(builder: (ctx) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Q2, decided by the owner: ONE click gets you in. Escape is always
          // one key away, so the cost of an accidental entry is a single
          // keystroke — far less than the cost of an equation that looks
          // editable and isn't.
          onTap: () {
            final box = ctx.findRenderObject() as RenderBox?;
            if (box == null || !box.hasSize) return;
            final origin = box.localToGlobal(Offset.zero);
            onTap!(origin & box.size);
          },
          child: math,
        ),
      );
    });
  }
}
