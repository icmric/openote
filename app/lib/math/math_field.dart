/// The visual equation editor: the thing on screen (plan: v0.18 §5.3, §6).
///
/// It is a `Focus` node, not a `TextField`. A `TextField` would give us IME
/// and a system caret, but it would also insist on owning a linear string —
/// and the whole point of this editor is that there ISN'T one to own. Keys
/// arrive raw and go straight to [MathEditor]; the tree serialises back to TeX
/// every frame and `flutter_math` draws it.
///
/// The one cost, stated plainly: no IME. A physical keyboard is the input path
/// here, which covers every desktop platform Openote ships on. The on-screen
/// maths keyboard for touch and the web build is Phase 3 of the plan.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import 'math_editor.dart';
import 'math_inventory.dart';
import 'math_tree.dart';
import 'math_view.dart';

/// Which way the caret left the equation, so the caller can put it back into
/// the sentence on the correct side.
enum MathExit { left, right, done }

class MathField extends StatefulWidget {
  const MathField({
    super.key,
    required this.editor,
    required this.onChanged,
    required this.textStyle,
    this.onExit,
    this.autofocus = true,
    this.compact = false,
    this.focusNode,
  });

  final MathEditor editor;

  /// Called after every change, with the canonical LaTeX. The block writes it
  /// straight to the model — same live-commit rule the text and code editors
  /// use, so switching page or notebook mid-edit cannot drop the equation.
  final ValueChanged<String> onChanged;

  final TextStyle textStyle;
  final void Function(MathExit how)? onExit;
  final bool autofocus;

  /// Inline use: text style rather than display style, so the equation sits at
  /// the size of the sentence around it.
  final bool compact;

  final FocusNode? focusNode;

  @override
  State<MathField> createState() => MathFieldState();
}

class MathFieldState extends State<MathField> {
  FocusNode? _own;
  FocusNode get _focus => widget.focusNode ?? (_own ??= FocusNode());

  MathEditor get _e => widget.editor;

  @override
  void initState() {
    super.initState();
    // The empty-state chip (below) draws differently focused vs not, and a
    // focus flip is the one change that arrives without a keystroke.
    _focus.addListener(_focusFlipped);
  }

  void _focusFlipped() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_focusFlipped);
    _own?.dispose();
    super.dispose();
  }

  void _changed() {
    setState(() {});
    widget.onChanged(_e.latex);
  }

  /// A palette press, routed from the bar. Focus comes back here so the next
  /// keystroke lands in the equation rather than nowhere.
  void insertItem(MathItem item) {
    _e.insertItem(item);
    _focus.requestFocus();
    _changed();
  }

  /// Write the calculator's answer into the equation, at the end: `… = 0.5`.
  void insertResult(String value) {
    if (value.isEmpty) return;
    _e.placeAtEnd();
    // `'=\$value'` before — an ESCAPED dollar, so the button typed the seven
    // literal characters `=$value` into the equation instead of the answer.
    for (final ch in '=$value'.split('')) {
      _e.insertChar(ch);
    }
    _focus.requestFocus();
    _changed();
  }

  /// LaTeX goes on the clipboard, because that is what pastes into Word,
  /// Overleaf, a message to a classmate, or back into here.
  ///
  /// The HIGHLIGHT when there is one, the whole equation when there is not —
  /// so Ctrl+C behaves the way it does in every other editor rather than
  /// always taking everything, which is what the owner reported: "when i cut
  /// it cuts all the content, id love to be able to highlight and cut only
  /// part of the equation."
  void _copy() {
    final tex = (_e.hasSelection ? _e.selectionLatex : _e.latex).trim();
    if (tex.isEmpty) return;
    // WITH the dollars. Copying bare LaTeX is why a pasted equation stayed
    // plain text in a paragraph for ever: nothing downstream could tell it was
    // maths, so it never converted and never even flashed. `$…$` still pastes
    // into Word, Overleaf and a message as the LaTeX it is.
    Clipboard.setData(ClipboardData(text: MathClipboard.wrapInline(tex)));
  }

  /// Take whatever is on the clipboard as maths. LaTeX first; failing that the
  /// linear form, so `1/2` copied out of a text message still arrives as a
  /// fraction. Anything else lands as the characters themselves rather than
  /// being refused.
  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    _e.insertSource(text);
    _changed();
  }

  static bool _printable(String s) =>
      s.length == 1 && s.codeUnitAt(0) > 0x20 && s.codeUnitAt(0) != 0x7f;

  /// The character a key produced, if any. Keyed off `event.character` and not
  /// the physical key, because `^` is Shift+6 and `_` is Shift+minus — the
  /// same reason `app_shell` reads it this way for the Markdown chords.
  static String? _character(KeyEvent e) {
    final c = e.character;
    if (c != null && _printable(c)) return c;
    return null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    final ctrl = keys.isControlPressed || keys.isMetaPressed;
    final shift = keys.isShiftPressed;
    final k = e.logicalKey;

    // Ctrl+= / Ctrl+Shift+= — an index or a power, the same chord that writes
    // H₂O and x² in ordinary text. Consistency is the whole point.
    if (ctrl &&
        (k == LogicalKeyboardKey.equal || k == LogicalKeyboardKey.numpadEqual)) {
      _e.insertChar(shift ? '^' : '_');
      _changed();
      return KeyEventResult.handled;
    }
    // **The clipboard belongs to the equation while the equation has the
    // keyboard.** Letting these fall through to the canvas meant Ctrl+C copied
    // the whole BLOCK and — much worse — Ctrl+X *cut the block*, destroying the
    // equation the student was in the middle of writing. That is the only
    // keystroke in the editor that could still lose work.
    //
    // Both act on the HIGHLIGHT when there is one and on the whole equation
    // when there is not — the owner: "when i cut it cuts all the content, id
    // love to be able to highlight and cut only part of the equation."
    // Shift+arrows, Shift+Home/End and Ctrl+A make one.
    if (ctrl && k == LogicalKeyboardKey.keyC) {
      _copy();
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyX) {
      _copy();
      // Cut what was highlighted; only take everything when nothing was.
      if (!_e.deleteSelection()) _e.clear();
      _changed();
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyA) {
      if (_e.selectAll()) _changed();
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyV) {
      _paste();
      return KeyEventResult.handled;
    }
    // Everything else with Ctrl belongs to the app, not to the equation.
    if (ctrl) return KeyEventResult.ignored;

    switch (k) {
      case LogicalKeyboardKey.escape:
        widget.onExit?.call(MathExit.done);
        return KeyEventResult.handled;

      case LogicalKeyboardKey.tab:
        if (_e.tab(backwards: shift)) {
          _changed();
          return KeyEventResult.handled;
        }
        // Every box is full: Tab belongs to whatever is outside.
        return KeyEventResult.ignored;

      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        // Q4, decided by the owner: Enter inside an INLINE equation finishes
        // it and carries on with the sentence. Turning it into a display
        // equation is the explicit toggle, never a side effect of typing.
        if (!widget.compact && _e.addMatrixRow()) {
          _changed();
          return KeyEventResult.handled;
        }
        widget.onExit?.call(MathExit.done);
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowLeft:
        // Shift EXTENDS rather than moves, and stops at the row's edge — see
        // the note on `MathEditor.extendBy` for why a highlight never crosses
        // out of the row it started in.
        if (shift) {
          if (_e.extendBy(-1)) _changed();
          return KeyEventResult.handled;
        }
        if (_e.moveLeft()) {
          _changed();
        } else {
          widget.onExit?.call(MathExit.left);
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowRight:
        if (shift) {
          if (_e.extendBy(1)) _changed();
          return KeyEventResult.handled;
        }
        if (_e.moveRight()) {
          _changed();
        } else {
          widget.onExit?.call(MathExit.right);
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowUp:
        if (_e.moveUp()) _changed();
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowDown:
        if (_e.moveDown()) _changed();
        return KeyEventResult.handled;

      case LogicalKeyboardKey.home:
        if (shift) {
          while (_e.extendBy(-1)) {}
        } else {
          _e.placeAtStart();
        }
        _changed();
        return KeyEventResult.handled;

      case LogicalKeyboardKey.end:
        if (shift) {
          while (_e.extendBy(1)) {}
        } else {
          _e.placeAtEnd();
        }
        _changed();
        return KeyEventResult.handled;

      case LogicalKeyboardKey.backspace:
        if (_e.backspace()) {
          _changed();
        } else {
          // Nothing left to delete: back out the left-hand side, which is
          // where the student was heading.
          widget.onExit?.call(MathExit.left);
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.delete:
        if (_e.delete()) _changed();
        return KeyEventResult.handled;
    }

    final ch = _character(e);
    if (ch != null) {
      if (_e.insertChar(ch)) _changed();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.space) {
      if (_e.insertChar(' ')) _changed();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // **Claim the keyboard, post-frame.** `autofocus` alone was not enough: a
    // fresh equation opened with the canvas still holding focus, so nothing
    // typed into it at all until a palette press — which calls
    // `requestFocus` — happened to hand it over. Reported as "i cant actually
    // type anything right off the bat". The text editor claims focus the same
    // way and for the same reason: the host decides THAT a block is being
    // edited, but the field only exists after this build.
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_focus.hasFocus) _focus.requestFocus();
      });
    }

    final surfaces = Theme.of(context).extension<OnoteSurfaces>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? OnoteSurfaces.dark
            : OnoteSurfaces.light);
    final dark = Theme.of(context).brightness == Brightness.dark;

    final accent = Theme.of(context).colorScheme.primary;
    // `\colorbox` paints an opaque rectangle — it cannot blend — so the tint
    // is mixed against the surface HERE. Doing it any later would mean a
    // second rendering path for dark mode.
    final ctx = MathTexCtx(
      accent: _hex(accent),
      tint: _hex(Color.alphaBlend(
        accent.withValues(alpha: dark ? 0.34 : 0.18),
        surfaces.chrome,
      )),
      dim: _hex(surfaces.textSecondary),
    );

    return Focus(
      focusNode: _focus,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Clicking an equation you are ALREADY in puts the caret at the end.
        // True hit-testing inside the equation needs box geometry
        // flutter_math_fork does not expose (v0.18 phase 3); until it does,
        // predictable beats mysterious — the click used to do nothing at all,
        // so the caret stayed wherever it happened to be.
        onTap: () {
          if (_focus.hasFocus) {
            _e.placeAtEnd();
            _changed();
          } else {
            _focus.requestFocus();
          }
        },
        child: OnoteMath(
          // **An empty INLINE equation shows the tint chip, not nothing.**
          // The root row deliberately renders as a bare caret when empty
          // (a block has its own chrome saying "equation"), but mid-sentence
          // a lone hairline is invisible — the student would have no idea
          // where their equation is. The chip is the same affordance a
          // half-filled fraction already taught them (v0.20 C.1).
          widget.compact && _e.isEmpty
              ? (_focus.hasFocus
                  ? '${ctx.caretTex}${ctx.activeSlotTex}'
                  : ctx.activeSlotTex)
              : _e.renderTex(ctx),
          textStyle: widget.textStyle,
          compact: widget.compact,
        ),
      ),
    );
  }
}

String _hex(Color c) {
  final v = c.toARGB32() & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
