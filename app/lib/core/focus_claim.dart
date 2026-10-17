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

import 'dart:async';

import 'package:flutter/widgets.dart';

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
  final asked = _asked;
  if (asked != null &&
      asked != claimant &&
      !claimant.ancestors.contains(asked)) {
    return false;
  }
  final holder = FocusManager.instance.primaryFocus;
  if (holder == null || holder is FocusScopeNode) return true;
  return claimant.ancestors.contains(holder);
}

/// A node that has asked for the keyboard but does not hold it yet.
///
/// Cleared in a microtask, so it only ever describes the synchronous run of
/// callbacks it was set in — which is exactly as long as the gap lasts.
FocusNode? _asked;

/// Take the keyboard on purpose, where [keyboardIsGoingSpare] can see it.
///
/// [FocusNode.requestFocus] does not take effect where it is called: the
/// manager marks the node and applies the change in a microtask. Post-frame
/// callbacks all run before that microtask, so a standing claim that asks
/// `primaryFocus` who holds the keyboard is told "nobody" — and asks for it
/// too. Two requests in one frame are settled by their order, and the
/// standing claim is registered from a `build`, so it is always second.
///
/// That is issue #19's second report: *"if the caret is in a regular text box
/// and I click on the title, the title will grow a little bit (as if it were
/// entering edit mode) yet the caret stays where it was before, then clicking
/// again will move it in."* The title's field opened, asked, and the
/// paragraph it had opened over took the keyboard straight back.
void claimKeyboard(FocusNode node) {
  if (_asked == null) scheduleMicrotask(() => _asked = null);
  _asked = node;
  node.requestFocus();
}
