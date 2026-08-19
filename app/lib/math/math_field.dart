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
  void dispose() {
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
        if (_e.moveLeft()) {
          _changed();
        } else {
          widget.onExit?.call(MathExit.left);
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowRight:
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
        _e.placeAtStart();
        _changed();
        return KeyEventResult.handled;

      case LogicalKeyboardKey.end:
        _e.placeAtEnd();
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
        onTap: () => _focus.requestFocus(),
        child: OnoteMath(
          _e.renderTex(ctx),
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
