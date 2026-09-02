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

import 'dart:async';

import 'package:flutter/gestures.dart'
    show kPrimaryButton, kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import 'answer_menu.dart';
import 'math_editor.dart';
import 'math_hit.dart';
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
    this.initialTapGlobal,
  });

  final MathEditor editor;

  /// Called after every change, with the canonical LaTeX. The block writes it
  /// straight to the model — same live-commit rule the text and code editors
  /// use, so switching page or notebook mid-edit cannot drop the equation.
  final ValueChanged<String> onChanged;

  final TextStyle textStyle;
  final void Function(MathExit how)? onExit;
  final bool autofocus;

  /// Inline use: the equation sits inside a sentence rather than in a box of
  /// its own. It is drawn at the SAME size either way (the owner's call — see
  /// [OnoteMath.compact]); what this changes is the failure presentation and
  /// the selection reserve, which inline would shove the sentence's baseline
  /// around.
  final bool compact;

  final FocusNode? focusNode;

  /// Where the click that is opening this equation landed, in global
  /// coordinates — so the caret lands there too instead of at a fixed end,
  /// which is what every "open for edit" call site did before this (the
  /// owner: "clicking into an equation just puts me at the start every
  /// time"). Consulted exactly once, the moment this field first mounts for
  /// a given [editor] — a later rebuild with the same equation still open
  /// must never re-snap the caret back to the click that opened it.
  final Offset? initialTapGlobal;

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
    _committed = _e.latex;
    // The empty-state chip (below) draws differently focused vs not, and a
    // focus flip is the one change that arrives without a keystroke.
    _focus.addListener(_focusFlipped);
    final at = widget.initialTapGlobal;
    if (at != null) _armInitialTap(at);
  }

  void _focusFlipped() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(MathField old) {
    super.didUpdateWidget(old);
    // **A different equation means a different baseline.** The inline host
    // mounts this field under a persistent GlobalKey and swaps the tree
    // underneath it in one synchronous call, so no frame is built in
    // between and this State — with the LAST equation's `_committed` —
    // survives. The new equation's first edit was then compared against the
    // old one's LaTeX and, when the two matched (the same worked line twice
    // in a sentence), suppressed: the screen changed and the note did not.
    if (!identical(old.editor, widget.editor)) {
      _committed = _e.latex;
      // The SAME State surviving into a DIFFERENT equation is also how a
      // click that closes one inline equation and immediately opens another
      // arrives here: `initState` never reruns, so without this the second
      // equation's own click position would be silently dropped and it
      // would open at the caret's plain default instead.
      final at = widget.initialTapGlobal;
      if (at != null) _armInitialTap(at);
    }
  }

  @override
  void dispose() {
    _answerTimer?.cancel();
    _focus.removeListener(_focusFlipped);
    _own?.dispose();
    super.dispose();
  }

  /// The last LaTeX handed to the host, so pure caret movement commits
  /// NOTHING. Every onChanged is an edit to the hosts — an undo snapshot, a
  /// save debounce, a redo-stack clear — and arrow keys were firing all three
  /// with a byte-identical payload: pressing Undo, clicking back in and
  /// arrowing to the typo DESTROYED the redo it was meant to precede.
  String? _committed;

  void _changed() {
    setState(() {});
    final now = _e.latex;
    if (now == _committed) return;
    _committed = now;
    widget.onChanged(now);
    _scheduleAnswerRefresh();
  }

  /// **Answers follow the working, a beat behind.**
  ///
  /// The owner: *"Please make it update the value when i update the equation,
  /// but debounce it so its not doing lots of unnesesary updates."* Changing
  /// `2+3=5` to `2+4=5` makes the 5 wrong, and a wrong answer in a box that
  /// says the app worked it out is the worst kind of wrong.
  ///
  /// [_answerGap] is the wait. Long enough that a burst of typing re-works
  /// the sum once rather than once per keystroke — and long enough that the
  /// answer does not flicker away and back while a student is halfway
  /// through deleting a number.
  static const Duration _answerGap = Duration(milliseconds: 400);
  Timer? _answerTimer;

  void _scheduleAnswerRefresh() {
    if (!_e.hasAnswers) return; // nothing to re-work; no timer, no wakeup
    _answerTimer?.cancel();
    _answerTimer = Timer(_answerGap, () {
      if (!mounted) return;
      if (_e.refreshAnswers()) _changed();
    });
  }

  /// Work the answers out again now, without waiting for the debounce.
  ///
  /// What a degrees/radians switch calls on the equation that is open. Focus
  /// is untouched: nothing about this is a reason to stop writing.
  void reworkNow() {
    if (!_e.hasAnswers) return;
    if (_e.refreshAnswers()) _changed();
  }

  /// A palette press, routed from the bar. Focus comes back here so the next
  /// keystroke lands in the equation rather than nowhere.
  void insertItem(MathItem item) {
    _e.insertItem(item);
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
    if (_e.insertSource(text) == InsertOutcome.refused) {
      // Plain words, year-10 bar: no mention of parsing or LaTeX — and no
      // directions, because the way out is already on screen. The `⋯` menu on
      // the object row offers "Write the LaTeX by hand" the whole time an
      // equation is open. This used to send people to the Maths TAB, which
      // has not existed since the object row replaced it.
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
        content: Text("That maths couldn't be read, so nothing was changed. "
            "It's still on your clipboard."),
        duration: Duration(seconds: 4),
      ));
      return;
    }
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

  // ─────────────────────────────────────────────── the pointer (v0.20 E.3)
  //
  // Click places the caret at the nearest atom boundary. Drag highlights.
  // Shift+click extends. Double-click takes the atom under the pointer,
  // whole — for a fraction, the fraction. Before this the field's only
  // gesture was a tap that jumped the caret to the END and, worse, DESTROYED
  // any keyboard-made highlight on its way — so for a mouse user, selection
  // did not exist: "i cant highlight anything".
  //
  // Geometry comes from MathHitTable: the prefixes are laid out OFFSTAGE on
  // pointer-down and resolved one frame later. A click answered a frame late
  // is imperceptible; a caret that lands where you clicked, after years of
  // landing at the end, is not.

  List<String>? _probeTexes;
  List<GlobalKey>? _probeKeys;
  MathHitTable? _hits;

  /// True from the moment a click OPENS this equation until that click's
  /// position resolves one frame later. `_e.caretIndex` is not yet where the
  /// click landed for that one frame — only the editor's plain default — and
  /// [MathField.build] uses this to leave the caret out of the render
  /// entirely rather than flash it in a place nobody clicked.
  bool _awaitingInitialTap = false;

  /// The one place every resolve path clears the probe state, so none of
  /// them can clear `_probeTexes`/`_probeKeys` without also ending whatever
  /// [_awaitingInitialTap] wait they might be the answer to.
  void _clearProbes() {
    _probeTexes = null;
    _probeKeys = null;
    _awaitingInitialTap = false;
  }

  /// An answer the press landed on, waiting for the release to switch it.
  MAnswer? _armedAnswer;

  /// Whether the button is still down. The hit table resolves a frame after
  /// the press, and a quick tap is DOWN-UP inside that frame — so by the time
  /// the answer under the pointer is known, the release may already have
  /// happened and there is nothing left to wait for.
  bool _pointerIsDown = false;
  double _pendingDx = 0;
  bool _pendingShift = false;
  bool _pendingDouble = false;

  /// The press was the RIGHT button, so the gesture is asking the thing under
  /// it what it can do rather than moving the caret.
  bool _pendingSecondary = false;
  Offset _pendingGlobal = Offset.zero;
  DateTime _lastDown = DateTime.fromMillisecondsSinceEpoch(0);
  Offset _lastDownPos = Offset.zero;

  /// A click that OPENED this equation, not a live pointer — the widget that
  /// mounted this field already consumed the click, so there is no
  /// [PointerDownEvent] to read a local position from. This measures the
  /// same offstage probes a real click does and feeds [_resolveGesture]
  /// exactly the same synthesised inputs, once the field itself has a size
  /// to convert the click's global position against.
  void _armInitialTap(Offset global) {
    if (_e.root.isEmpty) return; // nothing to hit; focus is the whole job
    _awaitingInitialTap = true;
    _probeTexes = MathHitTable.prefixTexes(_e.root);
    _probeKeys = [for (final _ in _probeTexes!) GlobalKey()];
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _resolveInitialTap(global));
  }

  void _resolveInitialTap(Offset global) {
    if (!mounted || _probeTexes == null) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      setState(_clearProbes);
      return;
    }
    _pendingDx = box.globalToLocal(global).dx;
    _pendingShift = false;
    _pendingDouble = false;
    _pendingSecondary = false;
    _resolveGesture();
  }

  void _pointerDown(PointerDownEvent e) {
    _pointerIsDown = true;
    _pendingSecondary = e.buttons & kSecondaryButton != 0;
    _pendingGlobal = e.position;
    // The PREVIOUS gesture's table dies here, not on pointer-up: a quick
    // click's post-frame resolve lands after the up, so up-clearing left the
    // old geometry alive and the next drag's first frame consulted boundaries
    // measured for an equation that no longer exists.
    _hits = null;
    if (!_focus.hasFocus) _focus.requestFocus();
    final now = DateTime.now();
    final isDouble = now.difference(_lastDown).inMilliseconds < 400 &&
        (e.localPosition - _lastDownPos).distance < 8;
    _lastDown = now;
    _lastDownPos = e.localPosition;
    if (_e.root.isEmpty) return; // nothing to hit; focus was the whole job
    _pendingDx = e.localPosition.dx;
    _pendingShift = HardwareKeyboard.instance.isShiftPressed;
    _pendingDouble = isDouble;
    setState(() {
      _probeTexes = MathHitTable.prefixTexes(_e.root);
      _probeKeys = [for (final _ in _probeTexes!) GlobalKey()];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveGesture());
  }

  void _resolveGesture() {
    if (!mounted || _probeTexes == null) return;
    final bounds = <double>[];
    for (final k in _probeKeys!) {
      final b = k.currentContext?.findRenderObject() as RenderBox?;
      if (b == null || !b.hasSize) {
        setState(_clearProbes);
        return;
      }
      bounds.add(b.size.width);
    }
    final hits = MathHitTable(_e.root, bounds);
    _hits = hits;
    // **The right button asks, it does not move.** An answer has a handful of
    // choices about how it is written, and a menu is where a student expects
    // to find the choices something offers. Anywhere else in the equation the
    // right button does nothing at all — deliberately, because moving the
    // caret on a press that was going to open a menu is the worst of both.
    if (_pendingSecondary) {
      setState(_clearProbes);
      final a = _e.answerAt(hits.childStrictlyAt(_pendingDx));
      if (a != null) _openAnswerMenu(a, _pendingGlobal);
      return;
    }
    // **A click ON an answer switches how it is written**, decimal to
    // fraction and back — the box around it is what advertises that the
    // click is there to be made. It takes priority over placing the caret
    // because an answer has no inside to put a caret in: it is one object,
    // and the only thing a click on it could sensibly mean.
    //
    // `toggleAnswer` declines when there is nothing to switch to (a whole
    // number, or a decimal with no tidy fraction), and then this falls
    // through to placing the caret exactly as any other click would.
    // The toggle is ARMED here and fired on release (see [_endGesture]).
    // Doing it on the press meant a drag that began on an answer switched it
    // before selecting, and a double-click switched it twice — there and
    // back, so the second click appeared to do nothing at all.
    final onAnswer =
        _pendingShift || _pendingDouble ? null : _e.answerAt(hits.childStrictlyAt(_pendingDx));
    if (onAnswer != null && _e.canToggleAnswer(onAnswer)) {
      setState(_clearProbes);
      if (_pointerIsDown) {
        _armedAnswer = onAnswer;
      } else if (_e.toggleAnswer(onAnswer)) {
        // The tap was over before the geometry came back — fire now.
        _changed();
      }
      return;
    }
    if (_pendingDouble) {
      _e.selectChild(hits.childAt(_pendingDx));
    } else if (_pendingShift) {
      _e.selectTo(hits.boundaryAt(_pendingDx));
    } else {
      _e.placeAt(hits.boundaryAt(_pendingDx));
    }
    setState(_clearProbes);
    _changed();
  }

  /// The answer's own menu, and the keyboard handed straight back afterwards
  /// — a menu is a question, not a reason to stop writing.
  Future<void> _openAnswerMenu(MAnswer a, Offset at) async {
    final changed = await showAnswerMenu(
      context,
      at: at,
      editor: _e,
      answer: a,
    );
    if (!mounted) return;
    _focus.requestFocus();
    if (changed) _changed();
  }

  void _pointerMove(PointerMoveEvent e) {
    if (e.buttons & kPrimaryButton == 0) return;
    // Past the slop this is a DRAG, not a click, so whatever answer the
    // press landed on stops being a toggle and the gesture becomes a
    // selection like any other.
    if (_armedAnswer != null &&
        (e.localPosition - _lastDownPos).distance > 3) {
      _armedAnswer = null;
    }
    final h = _hits;
    if (h == null || _armedAnswer != null) return;
    final b = h.boundaryAt(e.localPosition.dx);
    if (b != _e.caretIndex || !_e.hasSelection) {
      _e.selectTo(b);
      _changed();
    }
  }

  /// The table is built for one gesture and dies with it — the equation can
  /// change the moment the button is up, and stale geometry that "mostly
  /// works" is worse than none.
  void _endGesture(PointerEvent _) {
    _hits = null;
    _pointerIsDown = false;
    if (_pendingSecondary) {
      _pendingSecondary = false;
      _armedAnswer = null;
      return;
    }
    final a = _armedAnswer;
    _armedAnswer = null;
    // A click that stayed put, on an answer: switch how it is written. It
    // declines when there is nothing to switch to, and then the press has
    // simply done nothing, which is the same as clicking a glyph that is
    // not an answer.
    if (a != null && _e.toggleAnswer(a)) _changed();
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
    // Ctrl+←/→ jumps a whole run — a number, a word, a run of operators, or
    // one entire structure — instead of one character at a time, which is
    // what the blanket "everything else with Ctrl belongs to the app" rule
    // below used to do to it: reported, it "does nothing" at all. Ctrl+Shift
    // highlights the same run, the same pairing Shift alone already has with
    // a plain arrow.
    if (ctrl && k == LogicalKeyboardKey.arrowLeft) {
      if (shift) {
        if (_e.extendByWord(-1)) _changed();
      } else if (_e.moveWord(-1)) {
        _changed();
      } else {
        // Nowhere left to jump to, even a whole row out — same "hand focus
        // back" every other left-moving key does at this edge.
        widget.onExit?.call(MathExit.left);
      }
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.arrowRight) {
      if (shift) {
        if (_e.extendByWord(1)) _changed();
      } else if (_e.moveWord(1)) {
        _changed();
      } else {
        widget.onExit?.call(MathExit.right);
      }
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
      // `&` inside a matrix means "next column", exactly as it does in the
      // LaTeX the matrix serialises to. Anywhere else it is a character.
      if (ch == '&' && _e.addMatrixColumn()) {
        _changed();
        return KeyEventResult.handled;
      }
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
      // Stronger than the slot tint on purpose. The slot tint measured
      // 1.34:1 against the block's white editing fill — a one-atom highlight
      // in it was invisible, reported as "i cant highlight anything". This is
      // the same weight every text editor gives its selection.
      selectionTint: _hex(Color.alphaBlend(
        accent.withValues(alpha: dark ? 0.55 : 0.38),
        surfaces.chrome,
      )),
      dim: _hex(surfaces.textSecondary),
      display: !widget.compact,
    );

    return Semantics(
      // The minimum a screen reader deserves: the field announces itself and
      // carries the equation's source. The LaTeX is jargon read aloud, but it
      // is honest and it is SOMETHING - the field was a bare Focus that
      // announced nothing at all. A spoken-maths walk of the tree is the
      // real fix, recorded in the roadmap.
      label: 'Equation',
      value: _e.isEmpty ? 'empty' : _e.latex,
      textField: true,
      child: Focus(
      focusNode: _focus,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _pointerDown,
          onPointerMove: _pointerMove,
          onPointerUp: _endGesture,
          onPointerCancel: _endGesture,
          // **A Column, NOT a Stack** — and the whole reason is one line of
          // Flutter: `RenderStack` reports no baseline, while `RenderFlex`
          // forwards its first child's. A `WidgetSpan` that asks for
          // `PlaceholderAlignment.baseline` and is handed no baseline falls
          // back to standing the whole box above the line, which is exactly
          // what the owner saw: "if i type some text then insert maths it
          // will do it all as superscript". Measured in a baseline `Row`: a
          // bare `OnoteMath` sat 4.5px down, ON the line; the same equation
          // inside this field sat at y=0, hard against the top.
          //
          // The probes still ride along as a second child, and cost the
          // layout nothing: an offstage child lays out (so it can be
          // measured) and reports zero size.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // **The highlight's height, reserved permanently** (v0.20
              // E.2.3). `\fcolorbox` costs exactly kSelectionBoxEm in height
              // and there is no way to remove it — `\fboxsep=0pt` is refused,
              // negative kerns are ignored, all measured. Without the reserve
              // the equation grows the moment a highlight appears and
              // everything around it — the line, the block, the wrap —
              // jumps. Vertical only: width shifts are interior to the row
              // and accepted.
              Padding(
                // Reserved only while NO highlight is drawn: the box adds
                // kSelectionBoxEm to the selected run, so if the padding
                // stayed, a full-row selection would grow the field by the
                // same amount the reserve was meant to absorb (measured:
                // +14.9px at 22px). With the swap, a flat row keeps its
                // height exactly. The one case that still moves: a short
                // selection beside a taller structure dips by up to
                // kSelectionBoxEm, because the box around the short run never
                // reaches the structure's height — accepted, and far rarer
                // than Ctrl+A.
                // …and only in a BLOCK. Inline, this reserve was measured
                // doing real damage: it inflates the placeholder, which
                // grows the line box, which pushes the sentence's baseline
                // DOWN 8.3px while the equation's own ink moves only 2.9px —
                // leaving the maths sitting 5.4px above the words at a 14px
                // font. That is precisely the owner's report, "if i type some
                // text then insert maths it will do it all as superscript",
                // and it appeared the moment you clicked in. A block has no
                // sentence to sit on, so it keeps the reserve and its
                // highlight still costs nothing.
                padding: EdgeInsets.symmetric(
                    vertical: widget.compact || _e.hasSelection
                        ? 0
                        : (widget.textStyle.fontSize ?? 14) *
                            (kSelectionBoxEm / 2)),
                child: OnoteMath(
                  // **An empty INLINE equation shows the tint chip, not
                  // nothing.** An empty equation nobody is in renders as
                  // nothing at all, and mid-sentence that leaves the student
                  // with no idea where their equation went. The chip is the
                  // same affordance a half-filled fraction already taught
                  // them (v0.20 C.1).
                  //
                  // Only the UNFOCUSED case is special now. Being in one is
                  // the tree's own job: an empty row with the caret in it
                  // draws the caret INSIDE the box (`caretSlotTex`), which
                  // this used to fake by writing a caret and a box next to
                  // each other — and it looked exactly like that.
                  widget.compact && _e.isEmpty && !_focus.hasFocus
                      ? ctx.activeSlotTex
                      : _e.renderTex(ctx, showCaret: !_awaitingInitialTap),
                  textStyle: widget.textStyle,
                  compact: widget.compact,
                ),
              ),
              // The hit-table probes: every prefix of the row, laid out and
              // never painted, alive for exactly one pointer gesture.
              //
              // `OverflowBox` hands them UNBOUNDED width, which the `Stack`
              // this replaced gave them for free. Without it a prefix wider
              // than the paragraph would be measured at the paragraph's
              // width, and every boundary past that point would be wrong —
              // clicks landing in the wrong place only in long equations,
              // the worst kind of bug to notice.
              if (_probeTexes != null)
                Offstage(
                  // Zero-sized on the outside, unbounded on the inside: the
                  // `SizedBox` gives the `OverflowBox` something finite to
                  // size ITSELF to (a Column hands its children unbounded
                  // height, which an OverflowBox asserts on), and the
                  // OverflowBox then hands the probes the unbounded width
                  // they need to be measured at their true size.
                  child: SizedBox(
                    width: 0,
                    height: 0,
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      maxWidth: double.infinity,
                      maxHeight: double.infinity,
                      child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < _probeTexes!.length; i++)
                          KeyedSubtree(
                            key: _probeKeys![i],
                            child: OnoteMath(
                              _probeTexes![i],
                              textStyle: widget.textStyle,
                              compact: widget.compact,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// What one `\fcolorbox` costs, in em, in BOTH width and height — measured at
/// 12/14/16/22/30px, text and display style alike: 2 x (fboxsep 3pt +
/// fboxrule 0.4pt). Pinned in a test so a flutter_math upgrade that changes
/// it fails loudly instead of quietly reintroducing the selection jump.
const double kSelectionBoxEm = 0.68;

String _hex(Color c) {
  final v = c.toARGB32() & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
