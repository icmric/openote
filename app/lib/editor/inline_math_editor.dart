/// Inline maths in a sentence: the drawing, and the one surviving overlay.
///
/// **The card is gone** (v0.20 §A.4). An inline equation used to be edited in
/// a floating panel under the paragraph, which meant a second place on screen
/// showing the same maths, a 420 px card "nowhere near where you were
/// typing", and a focus fight between the card and the paragraph that
/// scattered keystrokes between the two — reported as "randomly overwriting
/// characters, going in weird orders". The equation is now edited IN PLACE:
/// `live_markdown_engine.enterInlineMath` mounts the shared [EquationEditor]
/// inside the very span that draws the equation, so there is nothing to
/// anchor, nothing to fight with, and one editor to maintain.
///
/// What this file still owns:
///  * [InlineMathAtom] — the equation as it appears in the sentence when it
///    is NOT being edited: drawn, and clickable.
///  * [EquationSourcePanel] — the LaTeX escape hatch for an equation the
///    visual tree cannot hold (an import using a construct we don't model).
///    It needs platform text input — IME, selection handles, a system caret —
///    which is exactly what a `MathField` deliberately does without, and a
///    real `TextField` inside a `WidgetSpan` would open a second
///    `TextInputConnection` inside the host's. So this one case keeps a
///    floating panel (v0.20 §A.5).
library;

import 'package:flutter/material.dart';

import '../math/linear_math.dart';
import '../math/math_tree.dart';
import '../math/math_view.dart';
import '../theme/onote_theme.dart';
import '../theme/tokens.dart';
import 'wrap_selection.dart';

/// The LaTeX source panel for ONE inline equation the tree cannot hold.
class EquationSourcePanel {
  EquationSourcePanel._(this._entry);

  final OverlayEntry _entry;
  static EquationSourcePanel? _open;

  static bool get isOpen => _open != null;

  static void dismiss() {
    _open?._entry.remove();
    _open = null;
  }

  static void show(
    BuildContext context, {
    required Rect anchor,
    required String latex,
    required ValueChanged<String> onChanged,
    VoidCallback? onDone,
  }) {
    dismiss();
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _SourcePanel(
        anchor: anchor,
        latex: latex,
        onChanged: onChanged,
        onDone: () {
          dismiss();
          onDone?.call();
        },
      ),
    );
    overlay.insert(entry);
    _open = EquationSourcePanel._(entry);
  }
}

class _SourcePanel extends StatefulWidget {
  const _SourcePanel({
    required this.anchor,
    required this.latex,
    required this.onChanged,
    required this.onDone,
  });

  final Rect anchor;
  final String latex;
  final ValueChanged<String> onChanged;
  final VoidCallback onDone;

  @override
  State<_SourcePanel> createState() => _SourcePanelState();
}

class _SourcePanelState extends State<_SourcePanel> {
  late final TextEditingController _source =
      TextEditingController(text: widget.latex);

  @override
  void dispose() {
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
    const panelWidth = 420.0;

    // Under the equation by default; above it when there is no room below.
    final below = widget.anchor.bottom + 6;
    final wantsAbove = below + 220 > screen.height;
    // `clamp` throws when its upper bound falls below its lower one, which is
    // what a window narrower than the panel does — measured at 436 px, where
    // tapping an inline equation threw ArgumentError instead of opening it.
    final maxLeft = screen.width - panelWidth - 8;
    final left = maxLeft <= 8.0 ? 8.0 : widget.anchor.left.clamp(8.0, maxLeft);

    final preview = linearToLatex(_source.text);
    return Stack(children: [
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
        width: panelWidth,
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
                TextField(
                  controller: _source,
                  autofocus: true,
                  maxLines: null,
                  style: const TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontFamilyFallback: onoteFontFallback,
                      fontSize: 13),
                  inputFormatters: const [
                    WrapSelectionFormatter(
                        pairs: WrapSelectionFormatter.bracketPairs,
                        autoCloseFences: false)
                  ],
                  decoration: const InputDecoration(
                      isDense: true, border: OutlineInputBorder()),
                  onChanged: (v) {
                    widget.onChanged(v);
                    setState(() {});
                  },
                ),
                if (preview.isNotEmpty) ...[
                  const Divider(height: 14),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: OnoteMath(preview,
                        textStyle: TextStyle(
                            fontSize: 18, color: surfaces.textPrimary)),
                  ),
                ],
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
    // **An equation with nothing in it yet.** Alt+= writes `$$` at the caret,
    // and without this the student saw two dollar signs appear in the middle
    // of their sentence — the owner: "It shows the $$ around it while its in
    // that mode ... id like to make it super clean and not have random things
    // popup as this would be jarring to a user who doesnt know LaTeX or
    // markdown."
    //
    // What they see instead is the SAME empty box the editor already draws
    // inside a half-filled fraction: one affordance, learned once, in the only
    // place a student has already met it. Not a wide "Type equation here" —
    // OneNote can afford that because its equation is on its own line, and
    // four words mid-sentence would shove the paragraph apart.
    final surfaces = Theme.of(context).extension<OnoteSurfaces>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? OnoteSurfaces.dark
            : OnoteSurfaces.light);
    final accent = Theme.of(context).colorScheme.primary;
    final math = latex.trim().isEmpty
        ? OnoteMath(
            MathTexCtx(
              accent: _hex(accent),
              tint: _hex(Color.alphaBlend(
                accent.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.34
                        : 0.18),
                surfaces.chrome,
              )),
            ).activeSlotTex,
            textStyle: style,
            compact: true,
          )
        : OnoteMath(latex, textStyle: style, compact: true);
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

String _hex(Color c) {
  final v = c.toARGB32() & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
