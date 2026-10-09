/// **Is the keyboard going spare, or is somebody typing into something?**
///
/// Asked by an editor that claims the keyboard in a post-frame callback
/// registered from its own `build`. Two of those exist — the paragraph in
/// `live_markdown_engine.dart` and the [MathField] in `math/math_field.dart`
/// — and both were written as a one-off: *the host decides THAT a block is
/// being edited, but the field only exists after this build, so pick the
/// keyboard up once the field is there.*
///
/// Running after EVERY build makes that a standing claim instead, and the
/// running app rebuilds constantly. So clicking into a field that belongs to
/// some other block put the caret there and the next rebuild took it straight
/// back, reported twice over:
///
/// > *"it will move the caret into it as if it was going to edit it, but then
/// > it will just dispear from it and the other box never looses focus."*
///
/// — once for the paragraph, and again for an equation: *"if im in a maths
/// equation (any maths equation, even one not linked to that evaluator) it
/// still has the same issue."*
///
/// ## Why "am I the editing block?" is not the test
///
/// The obvious guard is to claim only while `app.editingBlockId` is this
/// block. It does not work, because the fields being stolen from belong to
/// blocks the canvas does not consider editable — `BlockType.substitute`,
/// `flashcard` and `board` are not in `BlockView._editableType`, so tapping
/// one of their fields never changes `editingBlockId` at all. The paragraph
/// or equation remains the editing block for the whole gesture and would go
/// on claiming with the student's caret sat in the field next door.
///
/// What the claimant actually wants to know is not who owns the block but
/// whether the keyboard is in use, and the focus manager can answer that
/// directly.
library;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// The field that asked for the keyboard this frame, and the frame it asked in.
///
/// See [claimKeyboard]. Two values rather than one because a marker left over
/// from an earlier frame must not go on answering for this one.
FocusNode? _asked;
Duration? _askedDuring;

/// The frame being built, or null between frames.
///
/// `currentFrameTimeStamp` asserts when read outside a frame, hence the phase
/// check; every non-idle phase has a timestamp.
Duration? _thisFrame() {
  final b = SchedulerBinding.instance;
  return b.schedulerPhase == SchedulerPhase.idle
      ? null
      : b.currentFrameTimeStamp;
}

/// **Take the keyboard for [node], and leave word that you did.**
///
/// Use this instead of a bare `requestFocus` for a field that has just been
/// opened by something the user did and asks from a post-frame callback,
/// because it has to wait for the field to exist. Such a request is NOT
/// visible to [keyboardIsGoingSpare] yet: `FocusManager` applies a request in
/// a microtask, so `primaryFocus` still names the previous holder for the
/// rest of the frame — and a standing claim running later in that same frame
/// reads "going spare" and takes the keyboard off a field that was promised
/// it. Last request before the microtask wins, and the standing claim is the
/// one that rebuilds constantly, so it is always last.
///
/// Measured on the page title, which is how this was found (v1.0.2 item 6,
/// second half). Clicking a title with the MOUSE while a paragraph was open:
///
/// ```text
/// DOWN  -> scope(...)      the click unfocused the paragraph — Flutter's own
///                          desktop "tap outside a field ends the edit", which
///                          is why a touch tap never showed this
/// UP    -> titleEditing=true   the title opened and asked, post-frame
/// frame -> paragraph       and the paragraph's standing claim took it back,
///                          because a scope held focus and so the keyboard
///                          looked spare
/// ```
///
/// The title field was left open and unfocused, so it took a second click to
/// start typing — reported as *"seems to take 2 clicks to actually start
/// editing the title"*.
void claimKeyboard(FocusNode node) {
  _asked = node;
  _askedDuring = _thisFrame();
  node.requestFocus();
}

/// Whether [claimant] may take the keyboard without interrupting anybody.
///
/// True when nothing holds focus, when it is parked on a [FocusScopeNode] —
/// which is what the framework does once a field is disposed or unfocused,
/// and the state a newly-opened block is claimed from — or when it is held by
/// a node ABOVE [claimant] in its own path.
///
/// That last case is the whole purpose of the callers rather than an
/// exception to it: the click which opened the block leaves the keyboard on
/// the canvas's traversal node or on the block's own `Focus`, both ancestors
/// of the field about to exist. A first version of this guard allowed only
/// the scope case and stopped a newly-opened box taking the caret at all,
/// which the regression test beside it caught.
///
/// Anything else is a plain [FocusNode] belonging to a widget that asked for
/// it — a field in some other block, being typed into — and taking it off
/// them is the bug this exists to stop.
bool keyboardIsGoingSpare(FocusNode claimant) {
  // Somebody else asked for it in this same frame (see [claimKeyboard]).
  // Their request is in flight and `primaryFocus` cannot say so yet.
  if (_asked != null && _asked != claimant) {
    if (_askedDuring != null && _askedDuring == _thisFrame()) return false;
    _asked = null; // a frame has passed: the answer below is the true one
    _askedDuring = null;
  }
  final holder = FocusManager.instance.primaryFocus;
  if (holder == null || holder is FocusScopeNode) return true;
  return claimant.ancestors.contains(holder);
}
