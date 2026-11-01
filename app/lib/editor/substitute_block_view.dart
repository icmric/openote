/// **Plug values into an equation, see the result.**
///
/// The graph block's sibling, for a single point rather than a curve. The inline
/// equivalent is the same `ActiveMathEditor.evaluateAtValue` closure the graph
/// button uses; this file is the standalone block.
///
/// ## What it stores
///
/// ```
/// content: {
///   'latex':     'v=u+a*t',     // its OWN copy of the equation
///   'from':      '<block id>',  // the equation it follows, when there is one
///   'fromLatex': 'u+a*t',       // an equation INSIDE a sentence has no id
///   'values':    {'u':'2','a':'3','t':'4'},  // what was typed, per name
///   'value':     '2',           // the pre-v1.0.2 spelling — see below
/// }
/// ```
///
/// **The latex is copied in rather than referenced.** A block that only pointed at
/// its equation would show nothing once that equation was deleted.
/// `from`/`fromLatex` is how it follows the original when the original changes.
///
/// ### `value` and `values`
///
/// `value` was a single string, because a substitute block could only ever have
/// one field — [substituteSourceFromLatex] says why that was and what changed.
///
/// **Both spellings are read, and `value` is still written while the formula has
/// exactly one variable.** That keeps a v1.0.1 build showing the number instead of
/// an empty field, and one notebook open on two machines running two releases is
/// the ordinary case here rather than a corner one. With several variables `value`
/// is left untouched: it never recorded *which* variable it held, so an older build
/// would print the number under the wrong label, and it cannot evaluate such a
/// formula anyway.
///
/// A value whose name has gone out of the equation is also kept. It costs a
/// short string, and it means editing `v = u + a*t` into `v = u + a` and back
/// again — or pressing Ctrl+Z — returns the numbers instead of silently
/// clearing them.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/focus_claim.dart';
import '../math/math_view.dart';
import '../math/substitute.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';

class SubstituteBlockView extends StatefulWidget {
  const SubstituteBlockView({super.key, required this.block, required this.app});

  final Block block;
  final AppState app;

  @override
  State<SubstituteBlockView> createState() => _SubstituteBlockViewState();
}

/// One variable's field: the controller behind it and the node that focuses
/// it, kept together so neither can outlive the other.
class _Slot {
  _Slot(String initial)
      : controller = TextEditingController(text: initial),
        focus = FocusNode(debugLabel: 'substitute value');

  final TextEditingController controller;
  final FocusNode focus;

  void dispose() {
    controller.dispose();
    focus.dispose();
  }
}

class _SubstituteBlockViewState extends State<SubstituteBlockView> {
  Block get b => widget.block;

  String get _latex => b.content['latex'] as String? ?? '';

  /// A field per variable, made on demand and outliving a rebuild.
  ///
  /// Keyed by variable name rather than held in a list, because the equation
  /// can change underneath this block while it is on screen — a graph and a
  /// substitute both follow their equation live, which is the owner's ask:
  /// *"it would be cool to see the graph change as i type."* Keying by name
  /// means `v = u + a*t` gaining a `k` leaves u, a and t exactly as they
  /// were, caret included.
  final Map<String, _Slot> _slots = {};

  /// The names the equation asked for on the last build, so [_write] can read
  /// the stored values the same way the build did — [storedValues] needs the
  /// order to know which name a pre-v1.0.2 `value` belonged to.
  List<String> _variables = const [];

  @override
  void dispose() {
    for (final s in _slots.values) {
      s.dispose();
    }
    super.dispose();
  }

  /// What the student has typed, by variable name — either spelling.
  Map<String, String> get _values => storedValues(b.content, _variables);

  void _write(String name, String text) {
    // Written as a whole map, so the first touch of any field also commits
    // the migrated reading of an old `value` rather than dropping it.
    b.content['values'] = _values..[name] = text;
    // **And the old spelling stays in step while there is only one name.**
    //
    // [storedValues] reads both, which is what stops a v1.0.2 build losing
    // what a v1.0.1 build wrote. This is the other direction: a v1.0.1 build
    // reads `value` and knows nothing of `values`, so without this it shows
    // an empty field for a number that is sitting right there in the file.
    // The same notebook on two machines running two releases is not a corner
    // case — it is how the owner tests.
    //
    // Only while there is ONE name, because that is the only case where the
    // old spelling can be true: it never recorded which variable it belonged
    // to, and a v1.0.1 build labels whatever it finds `x`. A formula with
    // several names cannot be evaluated by that build at all, so there is
    // nothing there to be in step with.
    if (_variables.length == 1) b.content['value'] = text;
    b.updatedAt = nowMs();
    widget.app.markDirty();
    setState(() {});
  }

  /// **Clicking a field closes the block that was open before it.**
  ///
  /// A tap on a `TextField` is won by the field's own gesture recognizer, so
  /// it never reaches `BlockView._tap` and nothing told the app that the
  /// student had left the sentence or the equation they were in. The reported
  /// symptom was the other box staying lit: *"the original one i was editing
  /// before still seems to stay selected which is kinda odd"* — and the
  /// reported WORKAROUND, clicking the containing box first, is precisely
  /// `_tap` being allowed to run. This does what that click did.
  ///
  /// It is also the deeper half of the focus fight. A block left open goes on
  /// rebuilding, and both the paragraph and the equation editor claim the
  /// keyboard from their own builds; ending the session removes the claimant
  /// rather than only guarding it (see [keyboardIsGoingSpare], which guards
  /// the frame between this focus change and the rebuild).
  ///
  /// `select` without `edit:` because `BlockType.substitute` has no editing
  /// session of its own to open — the fields ARE the interaction, and the
  /// block around them is merely selected, exactly as a click on its body
  /// leaves it.
  ///
  /// On the whole row of fields rather than on each one, so moving between
  /// them with Tab costs nothing: `Focus.onFocusChange` reports a DESCENDANT
  /// taking focus, and the handoff only has to happen when the group gains it
  /// from outside.
  void _groupFocusChanged(bool hasFocus) {
    if (!hasFocus) return;
    final app = widget.app;
    if (app.editingBlockId == null && app.selectedBlockId == b.id) return;
    app.select(b.id);
  }

  /// Bring [_slots] into line with the names the equation now needs, and
  /// return them in the order they are asked for.
  ///
  /// That order is the order the names are written in the formula, so
  /// `v = u + a*t` asks for u, then a, then t — not whatever order a `Map`
  /// felt like.
  List<(String, _Slot)> _slotsFor(List<String> names) {
    _variables = names;
    final values = _values;
    for (final name in names) {
      _slots.putIfAbsent(name, () => _Slot(values[name] ?? ''));
    }
    // A name the equation no longer mentions keeps its stored value (see the
    // library comment) but loses its field, which is what has to go away.
    for (final k in _slots.keys.where((k) => !names.contains(k)).toList()) {
      _slots.remove(k)!.dispose();
    }
    return [for (final name in names) (name, _slots[name]!)];
  }

  /// The width `AppState.insertSubstitute` gives a new block, and therefore
  /// the width at which [_scale] is 1.
  static const double kBaseWidth = 260;

  /// **How much bigger than default to draw everything, from the box's own
  /// width.**
  ///
  /// Reported: *"The equation solver is smaller text wise than the text on
  /// the rest of the page with no way of scaling it up, it should by default
  /// be larger and more readable, but also have a way of increasing its size
  /// (whether than be resizing the actual thing itself like we have with
  /// images or if it works off system scaling …)."*
  ///
  /// Measured, and the complaint was exact: page body text is
  /// `kEditorBodyFontSize` (15), an equation in a box of its own is
  /// `kMathBlockFontSize` (22), and this block drew its equation at **16**
  /// and every label, field and answer at `OnoteType.small` — **12**. So the
  /// answer, the thing the block exists to show, was a fifth smaller than
  /// the prose around it.
  ///
  /// The defaults are now the app's own: the equation at the size a maths
  /// block uses, the labels at body size, the answer between them and bold.
  ///
  /// The scale is the first of the two options asked for — resizing the thing
  /// itself, the way an image works — because it needs no new control and no
  /// stored field, and dragging the box is already how a block is made
  /// bigger. **The trade is real and worth stating:** width now does two
  /// jobs, so a box widened to fit a long equation also enlarges the text.
  /// It only ever grows (the floor is 1) and it stops at 2.2, so neither end
  /// can get silly, and dragging back undoes it.
  ///
  /// The other option — the platform text scale — is a bigger piece of work
  /// that nothing in the app reads yet (v1.0.2 §1), and this block should
  /// follow it when that lands rather than invent its own setting first.
  double get _scale => (b.w / kBaseWidth).clamp(1.0, 2.2);

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final latex = _latex;

    if (latex.isEmpty) {
      // Same rule as a graph or an equation with nothing in it (F-3): never
      // an invisible, unclickable husk.
      return Padding(
        padding: const EdgeInsets.all(OnoteSpace.x5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.calculate_outlined, size: 16, color: s.textSecondary),
            const SizedBox(width: OnoteSpace.x3),
            Expanded(
              child: Text('Nothing to evaluate — its equation is gone',
                  style: OnoteType.small.copyWith(color: s.textSecondary)),
            ),
          ],
        ),
      );
    }

    final source = substituteSourceFromLatex(latex);
    final slots = _slotsFor(source.variables);
    final answer = answerFor(source, _values);
    final scale = _scale;

    return Padding(
      padding: const EdgeInsets.all(OnoteSpace.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            // The size an equation in a box of its own is drawn at, because
            // that is what this is. It was 16 — one point above body text.
            child: OnoteMath(latex,
                textStyle: TextStyle(
                    fontSize: kMathBlockFontSize * scale,
                    color: s.textPrimary),
                compact: true),
          ),
          if (slots.isNotEmpty) ...[
            const SizedBox(height: OnoteSpace.x4),
            // **A Wrap, so three names do not need a wider block than one.**
            // The fields are small and self-labelled, so they tile: one name
            // reads as a single row exactly as it always did, and five names
            // fill the width and go onto a second line instead of pushing the
            // block off the page or clipping the last one.
            Focus(
              onFocusChange: _groupFocusChanged,
              child: Wrap(
                spacing: OnoteSpace.x5,
                runSpacing: OnoteSpace.x3,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final (name, slot) in slots)
                    _field(context, name, slot, slots.length, scale),
                ],
              ),
            ),
          ],
          const SizedBox(height: OnoteSpace.x4),
          _answer(context, source, answer, scale),
        ],
      ),
    );
  }

  /// One `name = [ ]` pair.
  Widget _field(BuildContext context, String name, _Slot slot, int of,
      double scale) {
    final s = context.surfaces;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // `Flexible`, so a long name at a large scale gives way rather than
        // overflowing the row it shares with the field. One or two
        // characters is the norm and never reaches this.
        Flexible(
          child: Text('$name =',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: OnoteType.ui.copyWith(
                  fontSize: kEditorBodyFontSize * scale,
                  color: s.textSecondary,
                  fontWeight: FontWeight.w600)),
        ),
        SizedBox(width: OnoteSpace.x3 * scale),
        SizedBox(
          // Narrower when there are several, so three fit the 260px block
          // `AppState.insertSubstitute` makes without wrapping, while one
          // keeps the room the single-field block was built with. Scaled
          // with the type, or a widened box would grow the words and leave
          // the fields behind.
          width: (of > 2 ? 56 : 84) * scale,
          height: OnoteSize.button * scale,
          child: TextField(
            controller: slot.controller,
            focusNode: slot.focus,
            onChanged: (text) => _write(name, text),
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
            // Enter moves to the next name rather than doing nothing, which
            // is the whole point of having more than one.
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => slot.focus.nextFocus(),
            inputFormatters: [
              // Numbers, and the handful of things `evaluateLinear` reads as
              // one: pi, e, +-*/^(), a decimal point.
              FilteringTextInputFormatter.allow(
                  RegExp(r'[0-9a-zA-Z.+\-*/^() ]')),
            ],
            style: OnoteType.ui.copyWith(
                fontSize: kEditorBodyFontSize * scale,
                fontFeatures: const [FontFeature.tabularFigures()]),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                  horizontal: OnoteSpace.x3 * scale,
                  vertical: OnoteSpace.x3 * scale),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(OnoteRadius.sm),
                  borderSide: BorderSide(color: s.border)),
            ),
          ),
        ),
      ],
    );
  }

  /// **The answer, in its own well, named.**
  ///
  /// It used to be a third column of the single input row, in the same size
  /// and weight as the label beside it: *"ensure the answer is clear, as at
  /// the moment its not super clear to me."* Three things fix that and none
  /// of them is a new colour — the answer gets the full width, a tinted well
  /// so it reads as output rather than as another thing to fill in, and its
  /// NAME, so `v = 14` says what the 14 is instead of leaving `= 14` to be
  /// matched against the equation above by eye.
  Widget _answer(BuildContext context, SubstituteSource source,
      SubstituteAnswer answer, double scale) {
    final s = context.surfaces;
    final scheme = Theme.of(context).colorScheme;
    final result = answer.result;
    final failed = result != null && !result.isOk;

    final String text;
    if (result == null) {
      // WHICH names are still needed, not a bare "enter a value" — with
      // three fields that sentence does not say what it is waiting on.
      text = 'enter ${_list(answer.missing)}';
    } else if (!result.isOk) {
      text = result.error!;
    } else {
      final name = answer.resultName ?? source.resultName;
      final value = result.value.isNaN ? 'no value there' : result.display;
      text = name == null ? '= $value' : '$name = $value';
    }

    final gotIt = result != null && result.isOk;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
          horizontal: OnoteSpace.x4 * scale, vertical: OnoteSpace.x3 * scale),
      decoration: BoxDecoration(
        color: failed
            ? scheme.error.withValues(alpha: 0.08)
            : result == null
                ? s.chrome2
                : scheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(OnoteRadius.md),
      ),
      child: Text(
        text,
        // Wraps rather than ellipsising: an error is a sentence, and a
        // sentence cut off at the box edge is no use to anybody.
        style: OnoteType.ui.copyWith(
          // **The answer is the biggest text in the block**, because it is
          // the one thing the block is for — between body size and the
          // equation's own. What is NOT an answer stays at body size: a
          // prompt and an error are sentences to read, not numbers to see.
          fontSize: (gotIt ? kAnswerFontSize : kEditorBodyFontSize) * scale,
          fontWeight: gotIt ? FontWeight.w600 : FontWeight.w400,
          color: failed
              ? scheme.error
              : result == null
                  ? s.textSecondary
                  : s.textPrimary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  /// The answer's own size: above body text, below the equation it came from.
  static const double kAnswerFontSize = 18;

  /// `u, a and t` — the list a sentence needs rather than a joined array.
  String _list(List<String> names) {
    if (names.length < 2) return names.join();
    return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  }
}
