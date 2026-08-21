/// The ONE equation editor, used everywhere an equation is edited
/// (plan: v0.20 §A).
///
/// **Why it exists.** The block editor and the inline card were two copies of
/// the same eight things — the `MathEditor` lifecycle, the LaTeX fallback, the
/// palette registration, the calculator, the focus claim — and they had
/// already drifted: the card had no calculator and no preview, so a fix landed
/// in one place and not the other. The owner, verbatim: *"i want it to be the
/// exact same experience as if i was typing it in its own box, ideally all
/// using the same code so that when i make updates and changes in the future
/// to one it also gets reflected in the other."* This file is that code.
///
/// What stays with the HOST, deliberately: the model commit (`onChanged`),
/// undo coalescing, the empty-equation sweep on exit, and how extra width is
/// granted (`onWidthWanted`) — a block widens itself, a paragraph widens its
/// text box. The widget never touches a `Block` or a text buffer; that is the
/// same seam ADR-0004 draws for text engines.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../editor/inline_math_editor.dart';
import '../editor/wrap_selection.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../theme/tokens.dart';
import 'active_math.dart';
import 'evaluate.dart';
import 'linear_math.dart';
import 'math_editor.dart';
import 'math_field.dart';
import 'math_inventory.dart';
import 'math_parse.dart';
import 'math_view.dart';

/// Where the equation lives, which decides display vs text style, what Enter
/// means (matrix row vs finish), and how the LaTeX escape hatch is shown.
enum EquationPlacement { block, inline }

class EquationEditor extends StatefulWidget {
  const EquationEditor({
    super.key,
    required this.app,
    required this.placement,
    required this.textStyle,
    required this.onChanged,
    required this.onExit,
    this.editor,
    this.latex = '',
    this.onWidthWanted,
    this.linearSource,
    this.onLinearChanged,
    this.autofocus = true,
    this.focusNode,
    this.onDrawGraph,
    this.onReworkSiblings,
  });

  /// Only for `setActiveMath` / `noteMathUse` — the toolbar's Maths tab has to
  /// find this editor, wherever it is mounted.
  final AppState app;

  final EquationPlacement placement;
  final TextStyle textStyle;

  /// Canonical LaTeX, on every change. The host commits it — to
  /// `block.content['latex']` or through `replaceMathAt` — and must do so
  /// live, because a page switch tears this widget down before any
  /// "finished editing" moment exists.
  final ValueChanged<String> onChanged;

  /// The caret is leaving. The HOST decides where it goes: back to the canvas,
  /// or into the sentence on the side the equation was left by.
  final void Function(MathExit how) onExit;

  /// A host-owned tree, for a mount point whose `State` cannot be trusted to
  /// survive (the inline span is rebuilt on every keystroke of the paragraph).
  /// Null means "open [latex] yourself", which is what the block does — its
  /// `State` lives exactly as long as the edit.
  final MathEditor? editor;

  /// What to open when [editor] is null.
  final String latex;

  /// The equation needs this many logical pixels of width, measured from the
  /// laid-out field. Grow-only by contract: the widget re-reports on every
  /// change, and hosts that cannot grow simply pass null and keep the scroll.
  final ValueChanged<double>? onWidthWanted;

  /// The LaTeX view's raw text as last stored, so `\sum_(n=1)^oo` written in
  /// the linear grammar survives a close and reopen exactly as typed.
  final String? linearSource;

  /// Raw text of the LaTeX view on every change, for hosts that store it.
  final ValueChanged<String>? onLinearChanged;

  final bool autofocus;
  final FocusNode? focusNode;

  /// Draw this equation as a graph beside it.
  ///
  /// Supplied by the HOST, because only the host knows what a graph would
  /// follow: a block equation is followed by its id, an equation in a
  /// sentence by what it says. The editor itself stays placement-blind, which
  /// is the rule this whole file exists to keep — and it is what makes the
  /// menu entry appear identically in both.
  final VoidCallback? onDrawGraph;

  /// Work out every OTHER equation in the same paragraph again.
  ///
  /// Null for an equation in a box of its own — it has no siblings, and the
  /// page-wide pass reaches every other block already.
  final void Function(AngleMode writtenIn)? onReworkSiblings;

  @override
  State<EquationEditor> createState() => EquationEditorState();
}

class EquationEditorState extends State<EquationEditor> {
  final _fieldKey = GlobalKey<MathFieldState>();
  final _latexFocus = FocusNode();
  late final TextEditingController _source;

  /// Owned only when the host did not pass one in.
  MathEditor? _owned;
  MathEditor? get _editor => widget.editor ?? _owned;

  bool _latexMode = false;

  @override
  void initState() {
    super.initState();
    if (widget.editor == null) {
      // An equation the tree can't hold opens as source, exactly as it always
      // has — never silently reshaped on the first keystroke (v0.18 §6.6).
      _owned = MathEditor.open(widget.latex);
      _latexMode = _owned == null;
    }
    _source = TextEditingController(
        text: widget.linearSource ?? _currentLatex());
  }

  @override
  void dispose() {
    // Post-frame, NOT inline: dispose runs while the tree is locked, and
    // `clearActiveMath` notifies — the toolbar must hear that its Maths tab
    // lost its equation, but telling it mid-unmount throws "setState called
    // when widget tree was locked". The owner guard makes lateness safe: if a
    // successor has registered by the time this fires, it is a no-op.
    final app = widget.app;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => app.clearActiveMath(this));
    _source.dispose();
    _latexFocus.dispose();
    super.dispose();
  }

  String _currentLatex() =>
      widget.editor?.latex ?? (_owned?.latex ?? widget.latex);

  // ── the public face, driven by the toolbar and the hosts ────────────────

  /// A palette press, routed here from the object row.
  void insertItem(MathItem item) => _fieldKey.currentState?.insertItem(item);

  /// Work this equation's answers out again — what a degrees/radians switch
  /// asks of the equation that is open.
  void rework(AngleMode writtenIn) {
    _fieldKey.currentState?.reworkNow();
    // And whatever ELSE is in the same sentence. For an equation in a box of
    // its own this is null and the page-wide pass has already done the
    // neighbours; for one in a paragraph the page-wide pass skipped the whole
    // paragraph, because rewriting a live one from outside reads as a foreign
    // edit and closes the equation. Only the session that owns the buffer can
    // do it safely, so it is asked to.
    widget.onReworkSiblings?.call(writtenIn);
  }

  bool get isEmpty => _latexMode
      ? _source.text.trim().isEmpty
      : (_editor?.isEmpty ?? true);

  String get latex => _latexMode
      ? (_source.text.trim().isEmpty ? '' : linearToLatex(_source.text.trim()))
      : (_editor?.latex ?? '');

  void _toggleLatexMode() {
    // Inline placement cannot swap a TextField into its span — a real text
    // field there would open a second TextInputConnection inside the host's
    // (v0.20 A.5). The LaTeX escape hatch is a small anchored panel instead.
    if (widget.placement == EquationPlacement.inline) {
      _openInlineSourcePanel();
      return;
    }
    if (_latexMode) {
      // **Say why, rather than doing nothing.** Writing something the buttons
      // cannot draw is the whole POINT of this view — the symbol search's own
      // empty state sends people here for exactly that — and "Back to the
      // buttons" then quietly did nothing at all, twice, with the only way
      // out greyed. The app knows precisely which bit it cannot draw.
      final check = parseLatex(latex);
      if (!check.supported || check.root == null) {
        final bit = (check.unknown ?? '').trim();
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(bit.isEmpty
              ? 'The buttons cannot draw this one, so it stays as typed text.'
              : "The buttons cannot draw '$bit' yet, so this stays as typed "
                  'text.'),
          duration: const Duration(seconds: 4),
        ));
        return;
      }
    }
    setState(() {
      if (_latexMode) {
        final reopened = MathEditor.open(latex);
        if (reopened == null) return; // checked above; belt and braces
        if (widget.editor != null) {
          widget.editor!.adopt(reopened);
        } else {
          _owned = reopened;
        }
        _editor!.placeAtEnd();
        _latexMode = false;
      } else {
        _source.text = widget.linearSource?.trim().isNotEmpty == true
            ? widget.linearSource!
            : _currentLatex();
        _latexMode = true;
      }
    });
  }

  void _openInlineSourcePanel() {
    final box = context.findRenderObject() as RenderBox?;
    final anchor = box == null || !box.hasSize
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : box.localToGlobal(Offset.zero) & box.size;
    EquationSourcePanel.show(
      context,
      anchor: anchor,
      latex: widget.linearSource ?? _currentLatex(),
      onChanged: (v) {
        _commitSource(v);
        // Keep the visual tree in step, so the equation in the sentence is
        // redrawn as the source is typed — same live rule as everywhere else.
        final ed = _editor;
        final reopened = MathEditor.open(
            v.trim().isEmpty ? '' : linearToLatex(v.trim()));
        if (ed != null && reopened != null) {
          setState(() => ed.adopt(reopened));
        }
      },
    );
  }

  /// **The typed source is written AFTER the equation, not before.**
  ///
  /// The host clears its stored source on any ordinary edit — see
  /// `MathBlockView._commitLatex` — because a source that goes stale is worse
  /// than none: reopening this view showed the equation as it had been when
  /// the source was last typed, and pressing "Back to the buttons" then
  /// rebuilt the equation from THAT, silently throwing away everything
  /// written visually since. Committing in this order lets the clear happen
  /// and then be overwritten by the source that caused it.
  void _commitSource(String v) {
    widget.onChanged(v.trim().isEmpty ? '' : linearToLatex(v.trim()));
    widget.onLinearChanged?.call(v);
  }

  /// The measured width the equation actually needs, reported post-frame.
  /// Reading the render box any earlier would measure last frame's equation.
  void _reportWidth() {
    final want = widget.onWidthWanted;
    if (want == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      want(box.size.width);
    });
  }

  @override
  Widget build(BuildContext context) {
    // The palette is the toolbar's Maths tab, wherever this editor is
    // mounted. Registered from `build` WITHOUT a notify — the rebuild that
    // reveals the tab rides whatever notify opened this editor (v0.18 §5.2).
    widget.app.setActiveMath(ActiveMathEditor(
      owner: this,
      insert: (item) {
        widget.app.noteMathUse(item.id);
        insertItem(item);
      },
      latexMode: _latexMode,
      latexAvailable: _latexMode || _editor != null,
      toggleLatex: _toggleLatexMode,
      drawGraph: widget.onDrawGraph,
      rework: rework,
    ));

    if (_latexMode) return _latexEditor(context);

    _reportWidth();
    final field = Focus(
      // Tab with every box full is the field saying "this key is not mine";
      // it means "leave to the right" (Shift+Tab: the left), and catching it
      // HERE keeps Flutter's focus traversal from carrying the caret into
      // some unrelated widget (v0.20 §B.2.7).
      onKeyEvent: (node, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.tab) {
          widget.onExit(HardwareKeyboard.instance.isShiftPressed
              ? MathExit.left
              : MathExit.right);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MathField(
        key: _fieldKey,
        editor: _editor!,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        compact: widget.placement == EquationPlacement.inline,
        textStyle: widget.textStyle,
        onChanged: widget.onChanged,
        onExit: widget.onExit,
      ),
    );

    // **The box grows, and scrolls when it cannot** (v0.18 §14 fix) — now at
    // BOTH sites. Inline, the paragraph hands the span a finite width; capping
    // at it makes the measured 112px RenderLine overflow structurally
    // impossible, and `onWidthWanted` asks the paragraph's own box to widen
    // so the cap is rarely felt.
    if (widget.placement == EquationPlacement.inline) {
      return LayoutBuilder(builder: (ctx, cons) {
        if (!cons.maxWidth.isFinite) return field;
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: cons.maxWidth),
          // **The scroll view swallows the baseline** — and an equation in a
          // sentence is positioned BY its baseline. A viewport reports none,
          // so the placeholder fell back to "baseline = my full height",
          // which seats the whole equation above the line. Measured: a lone
          // `x` jumped 4.8px and a paragraph holding a summation grew 7px
          // the instant you clicked into it, and the taller the maths the
          // worse it got. [KeepBaseline] hands the field's own baseline back
          // out through the viewport.
          child: KeepBaseline(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: field,
            ),
          ),
        );
      });
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: field,
    );
  }

  Widget _latexEditor(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _latexMode && !_latexFocus.hasFocus) {
        _latexFocus.requestFocus();
      }
    });
    final preview = linearToLatex(_source.text);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _source,
          focusNode: _latexFocus,
          maxLines: null,
          style: const TextStyle(
              fontFamily: 'JetBrains Mono',
              fontFamilyFallback: onoteFontFallback,
              fontSize: 14),
          inputFormatters: const [
            WrapSelectionFormatter(
                pairs: WrapSelectionFormatter.bracketPairs,
                autoCloseFences: false)
          ],
          decoration: OnoteInput.bare.copyWith(
            hintText: r'LaTeX or linear maths… e.g. \sum_(n=1)^oo 1/n^2',
          ),
          onChanged: (v) {
            _commitSource(v);
            setState(() {});
          },
        ),
        if (preview.isNotEmpty) ...[
          const Divider(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: OnoteMath(preview, textStyle: widget.textStyle),
          ),
        ],
      ],
    );
  }
}


/// Reports the baseline of the box inside, through a wrapper that hides one.
///
/// A `SingleChildScrollView` is a viewport, and a viewport has no baseline to
/// give — it does not know, or care, that the single thing it is scrolling is
/// a line of maths that has to sit on a sentence. Flutter's fallback for a
/// placeholder with no baseline is to treat the whole box as sitting on the
/// line, which lifts the equation clear of the words by its own height.
///
/// So this walks down to the first descendant that DOES have a baseline and
/// converts it into this box's coordinates. Deliberately a search rather than
/// a fixed path: the chain between here and the equation is
/// viewport → sliver adapter → Focus → MathField → Stack, and any of those may
/// change without this needing to.
class KeepBaseline extends SingleChildRenderObjectWidget {
  const KeepBaseline({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderKeepBaseline();
}

class RenderKeepBaseline extends RenderProxyBox {
  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final own = super.computeDistanceToActualBaseline(baseline);
    if (own != null) return own;
    final found = _firstBaseline(child, baseline);
    if (found == null) return null;
    final (box, offset) = found;
    // Into OUR coordinates: the descendant may sit anywhere inside.
    return box.localToGlobal(Offset(0, offset), ancestor: this).dy;
  }

  /// The first descendant that answers with a baseline, depth first.
  static (RenderBox, double)? _firstBaseline(
      RenderObject? node, TextBaseline baseline) {
    if (node == null) return null;
    // `hasSize` and NOT `debugNeedsLayout`. That getter assigns its result
    // inside an `assert`, so with asserts stripped it throws a
    // LateInitializationError — in RELEASE and PROFILE only, which is every
    // build a student ever runs and no build a test ever runs. The throw
    // happened inside the paragraph's layout, where `RenderObject.layout`
    // logs rather than rethrows, so every open inline equation broke its
    // paragraph's layout, silently, once per frame. `hasSize` is the check
    // that was actually wanted; a box that is sized but dirty trips
    // Flutter's own assert in debug, which is the honest place for it.
    if (node is RenderBox && node.hasSize) {
      final b = node.getDistanceToActualBaseline(baseline);
      if (b != null) return (node, b);
    }
    (RenderBox, double)? hit;
    node.visitChildren((c) {
      hit ??= _firstBaseline(c, baseline);
    });
    return hit;
  }
}
