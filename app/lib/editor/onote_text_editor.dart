import 'package:flutter/material.dart';

import '../model/models.dart';
import '../state/app_state.dart';
import 'live_markdown_engine.dart';

/// The rich-text **editor-engine seam** (ADR-0004).
///
/// ADR-0004 commits to this interface "from day one … so the loser remains a
/// swap candidate and the format never depends on engine internals" — that
/// holds whether the engine is the one we own, `super_editor`, or
/// `appflowy_editor`. Nothing above this seam may touch engine internals.
///
/// The contract is deliberately narrow, and it is exactly the four things the
/// canvas needs from a text engine:
///
///  1. [buildReadOnly] — the unfocused containers. ADR-0004 criterion 1 is a
///     20-container page with 19 read-only and one live; that split lives here
///     rather than inside the engine so the cheap path stays cheap.
///  2. [openSession] — the single live editor, as a per-block session that owns
///     the engine's mutable state and is disposed with the view.
///  3. [measureIntrinsicWidth] — auto-width measurement. The canvas needs this
///     *during layout*, so it must be answerable without mounting an editor.
///  4. [serialize] / [deserialize] — the storage contract, stated in one place
///     so the interim-Markdown → structured-`nodes` migration has somewhere to
///     land (see [textStorageKey]).
abstract class OnoteTextEditor {
  const OnoteTextEditor();

  /// Stable identifier, recorded in bake-off results and useful in bug reports.
  String get id;

  /// Read-only rendering of [surface]. Must be cheap: on a busy page this runs
  /// for every text container on screen, every frame they're dirty.
  Widget buildReadOnly(BuildContext context, TextSurface surface);

  /// Open an editing session for [block]. [onChanged] is called with the new
  /// document text on every edit; the host owns undo, dirty-marking and
  /// persistence, so an engine must never write to the block itself.
  OnoteEditSession openSession({
    required Block block,
    required AppState app,
    required ValueChanged<String> onChanged,
  });

  /// Width of the longest line of [text] at [style], excluding chrome. Used for
  /// auto-width boxes, measured in the parent's build pass so a box grows in the
  /// same frame its text changes.
  double measureIntrinsicWidth(String text, TextStyle style);

  /// The `content` key this engine stores its document under.
  ///
  /// Today every engine we care about round-trips the interim Markdown string in
  /// `content['text']`. A structured engine would declare `'nodes'` here and
  /// implement [serialize]/[deserialize] as the conversion, which is what keeps
  /// the Data Model §5.1 migration a one-file change.
  String get textStorageKey => 'text';

  /// Read the document out of a block's `content`. Returns `''` when absent so
  /// a block authored by a different engine degrades to empty rather than
  /// throwing.
  String deserialize(Map<String, dynamic> content) =>
      content[textStorageKey] as String? ?? '';

  /// Write [text] into a block's `content`, in place.
  void serialize(Map<String, dynamic> content, String text) {
    content[textStorageKey] = text;
  }
}

/// Everything an engine needs to render one text container. Passed per build
/// rather than held, because theme and per-block metrics can change underneath
/// a live session.
class TextSurface {
  const TextSurface({
    required this.block,
    required this.app,
    required this.baseStyle,
    required this.inset,
    required this.dark,
    this.hintText,
  });

  final Block block;
  final AppState app;

  /// Resolved base text style — includes the OneNote import metrics, so an
  /// engine must not derive its own font size or line height.
  final TextStyle baseStyle;

  /// Inner padding. Zero for imported boxes, where OneNote's stored offset *is*
  /// the first line's position.
  final EdgeInsets inset;

  final bool dark;
  final String? hintText;
}

/// One block's live editing state. Created by [OnoteTextEditor.openSession] and
/// disposed by the host.
abstract class OnoteEditSession {
  /// Build the editable surface. Called on every host rebuild.
  Widget build(BuildContext context, TextSurface surface);

  /// The current document text.
  String get text;

  /// Replace the document — used when the block changes underneath the session
  /// (undo, a checkbox toggle, a collaborative edit).
  set text(String value);

  /// The Flutter controller backing this session, when the engine is built on
  /// one. The command bar drives bold/italic/link insertion through it.
  ///
  /// An engine with its own selection model returns `null`; it is then
  /// responsible for registering its own command handlers, and
  /// [AppState.activeEditor] stays unset so the formatting buttons disable
  /// rather than silently no-op on the wrong target.
  TextEditingController? get commandController;

  /// Where the click that opened this session landed, in global coordinates.
  ///
  /// The canvas sets it before the session first builds; the engine consumes
  /// it once, to place the caret there. Null means "wherever you would
  /// normally put it".
  Offset? pendingCaretGlobal;

  /// The engine asking for the BOX to be this many logical pixels wider.
  ///
  /// An engine may not write to the block — that is the ADR-0004 seam, and the
  /// reason this is a callback rather than a reach into `AppState`. In-flow
  /// content can still need more room than it has: dragging a picture past the
  /// edge of its box should widen the box, not stop at it.
  ///
  /// A DEFICIT rather than a target width, deliberately. The engine knows how
  /// much more room it needs; only the host knows what `Block.w` currently is
  /// and how much of it the padding, insets and field chrome consume. Passing
  /// the difference means neither side has to model the other's arithmetic.
  ///
  /// The host may widen by less than asked (there is a ceiling). Engines must
  /// therefore treat their own available width as the truth on the next frame
  /// rather than assuming the request was granted.
  void Function(double extra)? requestExtraWidth;

  /// The text offset under a point in global (screen) coordinates, or null if
  /// the engine can't answer right now.
  ///
  /// Null is a supported answer, not a failure: the field may not have laid
  /// out yet, and a future engine may have no Flutter text layer at all.
  /// Callers must degrade (place the caret normally) rather than throw. This
  /// is what lets the canvas put the caret where you clicked, and drag-select
  /// from the very first gesture, without the canvas knowing anything about
  /// how the engine lays text out.
  int? offsetAtGlobal(Offset globalPosition) => null;

  /// Move the caret or extend the selection. No-op for an engine with no
  /// selection model of its own.
  void setSelection(int base, int extent) {}

  /// True while an inline equation INSIDE this session holds the keyboard.
  ///
  /// The one flag every gate reads (v0.20 §B.2.6): the session's own key
  /// handler stands down, and the shell's formatting chords and Escape ladder
  /// leave the keystroke to the equation. Three gates, one truth — the
  /// alternative was three copies of "is a MathField focused?" drifting apart.
  bool get inlineMathFocused => false;

  /// Start an equation AT THE CARET, inside this paragraph.
  ///
  /// Alt+= used to drop a separate equation block below the text, because the
  /// only route into an inline equation was knowing to type two dollar signs —
  /// which is why the owner reported that Openote "doesnt seem to allow me to
  /// do equations inline with a regular text block yet". Returns false when
  /// the engine has no inline maths of its own, and the caller then falls back
  /// to a block.
  bool startInlineMath() => false;

  void dispose();
}

/// The active engine.
///
/// A single mutable slot rather than injection through the widget tree: the
/// engine is a build-wide choice, not per-subtree, and threading it through
/// every canvas widget would put engine identity into a dozen constructors —
/// exactly the coupling the seam exists to prevent. Tests (and an ADR-0004
/// bake-off build) swap it via [use].
class OnoteEditors {
  OnoteEditors._();

  static const OnoteTextEditor _default = LiveMarkdownEngine();
  static OnoteTextEditor _active = _default;

  /// The engine in force.
  static OnoteTextEditor get active => _active;

  /// Install [engine] — a bake-off build, or a test double.
  static void use(OnoteTextEditor engine) => _active = engine;

  /// Restore the shipped engine. Test teardown.
  @visibleForTesting
  static void useDefault() => _active = _default;
}
