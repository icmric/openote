import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../markdown/md_render.dart';
import '../markdown/md_syntax.dart';
import '../model/models.dart';
import '../model/tags.dart';
import '../spell/spell_checker.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../math/equation_editor.dart';
import '../math/evaluate.dart';
import '../math/math_editor.dart';
import '../math/math_field.dart';
import 'inline_math_editor.dart';
import 'list_editing.dart';
import 'math_paste_formatter.dart';
import 'live_markdown_controller.dart';
import 'onote_text_editor.dart';
import 'unicode_input.dart';

/// The engine we own: a [TextField] driven by [LiveMarkdownController] for the
/// live container, [MarkdownView] for the read-only ones.
///
/// This is the ADR-0004 incumbent. It already satisfies the spike's demo scope
/// (see `docs/adr/ADR-0004-editor-engine.md` for the decision and the evidence),
/// and it is a few hundred lines we control end-to-end rather than a dev-channel
/// dependency. It sits behind [OnoteTextEditor] all the same, so replacing it
/// stays a one-line swap.
class LiveMarkdownEngine extends OnoteTextEditor {
  const LiveMarkdownEngine();

  @override
  String get id => 'live-markdown';

  @override
  Widget buildReadOnly(BuildContext context, TextSurface s) {
    final app = s.app;
    final block = s.block;
    return Padding(
      padding: s.inset,
      child: MarkdownView(
        text: deserialize(block.content),
        baseStyle: s.baseStyle,
        onWikiLink: (label, id) => app.openWikiLink(label, id),
        // In-flow images (Data Model §5.1): resolve sha256: refs from the
        // notebook's content-addressed blob store.
        imageResolver: (src) {
          final nb = app.notebookId;
          if (nb == null || !src.startsWith('sha256:')) return null;
          return app.blob(src);
        },
        // **A graph and its equation light up together**, in a sentence just
        // as in a box of its own. On the READ path because clicking a graph
        // clears the selection, so the paragraph an equation lives in is
        // never the one being edited at the moment its graph is picked out —
        // which made "it works both ways" true only for maths blocks.
        mathLinkTint: (latex) => app.inlineGraphTint(block.id, latex),
        // Tag markers (TEXT-5) hang in the line's gutter.
        tagsByLine: NoteTag.byLine(block.content),
        onToggleTag: (line, checked) =>
            app.setTagChecked(block.id, line, checked),
        onToggleCheckbox: (newText) {
          app.pushUndo();
          serialize(block.content, newText);
          app.updateBlock(block);
        },
      ),
    );
  }

  @override
  OnoteEditSession openSession({
    required Block block,
    required AppState app,
    required ValueChanged<String> onChanged,
  }) =>
      _LiveMarkdownSession(
        app: app,
        controller: LiveMarkdownController(
            text: deserialize(block.content), dark: false)
          // The same resolver the read view gets, so an in-flow image is a
          // picture in both — see the note in live_markdown_controller.dart on
          // how it stays there without desyncing a single caret offset.
          ..imageResolver = (src) {
            if (app.notebookId == null || !src.startsWith('sha256:')) return null;
            return app.blob(src);
          },
        onChanged: onChanged,
      )
        ..spellCheckEnabled = app.spellCheckEnabled
        // Check once on open so existing text is marked without an edit.
        ..scheduleInitialSpellCheck();

  @override
  double measureIntrinsicWidth(String text, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text.isEmpty ? ' ' : text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: null,
    )..layout(maxWidth: double.infinity); // width = intrinsic longest line
    final w = tp.width;
    tp.dispose();
    return w;
  }
}

class _LiveMarkdownSession extends OnoteEditSession {
  _LiveMarkdownSession({
    required this.app,
    required this.controller,
    required this.onChanged,
  }) {
    // Resizing a picture rewrites the buffer from inside the controller, and a
    // programmatic edit never fires TextField.onChanged — without this the new
    // size would draw perfectly and then be gone on the next open.
    controller.onSelfEdit = () => onChanged(controller.text);
    // Forwarded, not handled: only the host may touch the block (ADR-0004).
    controller.requestExtraWidth = (extra) => requestExtraWidth?.call(extra);
    controller.onMathTap = (start, end, latex, _) =>
        enterInlineMath(start, end, latex, atStart: false);
    controller.mathEditorBuilder = _buildInlineEditor;
    controller.graphLinkTint = (latex) {
      final host = app.editingBlockId;
      if (host == null) return null;
      return app.inlineGraphTint(host, latex,
          editing: _graphAnchor != null && _graphAnchor == latex.trim());
    };
    // A click that lands OUTSIDE the equation is the one signal the student
    // has left it - the host caret is parked inside the run while editing,
    // so any selection outside [start, end] means "close" (v0.20 B.2.5).
    controller.addListener(_maybeCloseOnCaretExit);
  }

  /// Alt+= in a paragraph: an empty equation AT THE CARET, opened for editing.
  ///
  /// The `$$` pair is written first so the equation has somewhere to live -
  /// caret arithmetic requires a placeholder to stand on at least one real
  /// code unit (v0.20 C.2) - and the editor then mounts IN that span. No
  /// card, no dollars on screen: the student sees the same empty tint chip a
  /// half-filled fraction already taught them, at the exact place they were
  /// typing.
  @override
  bool startInlineMath() {
    final sel = controller.selection;
    if (!sel.isValid) return false;
    final start = sel.start;
    var pair = '\$\$';
    // The empty-pair grammar declines when glued to a following word (that
    // guard is what keeps it off a display equation's opening), so mid-word
    // the pair takes a space with it - the word boundary the sentence would
    // need anyway.
    final t = controller.text;
    _mathPadded = false;
    if (sel.end < t.length && !_isSpace(t.codeUnitAt(sel.end))) {
      pair = '\$\$ ';
      _mathPadded = true;
    }
    _applyEdit(TextEditingValue(
      text: t.replaceRange(sel.start, sel.end, pair),
      selection: TextSelection.collapsed(offset: start + 1),
      composing: TextRange.empty,
    ));
    enterInlineMath(start, start + 2, '', atStart: true);
    return true;
  }

  static bool _isSpace(int cu) => cu == 0x20 || cu == 0x09 || cu == 0x0A;

  // -- In-place inline equation editing (v0.20 B) ---------------------------
  //
  // The equation is edited WHERE IT SITS: the span that draws it carries the
  // live [EquationEditor] while it is being written. Everything that must
  // survive a keystroke lives HERE in the session - the span is rebuilt on
  // every buffer change, so a State down there owns nothing.

  int? _mathStart;
  int _mathEnd = 0;
  MathEditor? _mathEditor;

  /// True while the session itself is writing the buffer, so the foreign-
  /// rewrite watcher does not fire on our own edits.
  bool _mathSelfEditing = false;

  /// The buffer as of our last own write — anything else that changes it is a
  /// FOREIGN rewrite (undo restoring an older buffer, the toolbar's Bold
  /// wrapping the word at the parked caret) and the session's cached anchors
  /// are dead the moment it happens. Both routes were probe-proven to corrupt
  /// the note: the next equation keystroke wrote the tree at the stale range,
  /// duplicating the equation or eating the words after it.
  String? _mathSelfText;

  /// How many dollars wrap THIS equation — 1 for $x$, 2 for the display
  /// form. Writing an edit back with the wrong count would silently demote a
  /// display equation to an inline one on the first keystroke.
  int _mathDollars = 1;

  /// Whether startInlineMath injected a trailing space (the mid-word case),
  /// so the empty sweep can take it back out — Alt+= then Escape used to
  /// leave the word permanently split.
  bool _mathPadded = false;
  final FocusNode _mathFocus = FocusNode();
  final GlobalKey<EquationEditorState> _mathKey =
      GlobalKey<EquationEditorState>();

  @override
  bool get inlineMathFocused => _mathFocus.hasFocus;

  Widget _buildInlineEditor(String latex, TextStyle base) {
    final ed = _mathEditor;
    // The builder can race a close by one frame; drawing nothing for it is
    // right because the very next span rebuild goes back to the atom.
    if (ed == null) return const SizedBox.shrink();
    return EquationEditor(
      key: _mathKey,
      app: app,
      placement: EquationPlacement.inline,
      textStyle: base,
      editor: ed,
      focusNode: _mathFocus,
      onChanged: _inlineMathChanged,
      onExit: closeInlineMath,
      // **What you typed by hand comes back.** Writing `sum_(n=1)^oo 1/n^2`
      // in the source panel, closing it and opening it again used to give
      // you the machine's `\sum_{n=1}^{\infty}\frac{1}{n^2}` instead of
      // your own characters. A block equation has kept them since v0.18; an
      // equation in a sentence has nowhere in the buffer to put them, so the
      // session holds them for as long as the equation is open — which is
      // the same lifetime the block's copy effectively has, because any
      // visual edit clears that one too.
      linearSource: _inlineSource,
      onLinearChanged: (v) => _inlineSource = v,
      // **The same menu entry a block equation has.** The link is anchored to
      // what the equation SAYS rather than to where it sits, because where it
      // sits is a character offset that every keystroke in the paragraph
      // moves. `_graphAnchor` is what the graph will follow from here.
      onDrawGraph: _drawGraph,
      onReworkSiblings: _reworkSiblingMath,
      // A summation's stacked limits are far wider than the same maths reads
      // inline; without this the equation hits the paragraph's edge and
      // starts scrolling inside its span. The deficit seam is the one
      // in-flow images already widen the box through (ADR-0004: the engine
      // may not touch the block).
      onWidthWanted: (w) {
        final avail = controller.layoutWidth;
        if (avail == null) return;
        final extra = w + 16 - avail;
        if (extra > 0) requestExtraWidth?.call(extra);
      },
    );
  }

  /// One click on an equation in a sentence - or the caret crossing into it,
  /// or Alt+= - and it is being edited, in place.
  void enterInlineMath(int start, int end, String latex,
      {required bool atStart}) {
    // One session at a time. Equation B's atom stays tappable while A is
    // open, and entering B without closing A left A's empty pair unswept —
    // or, for an unsupported B, TWO editors writing the same buffer. Closing
    // A may sweep characters out from under B's offsets, so they are
    // re-based on what the sweep removed.
    if (_mathStart != null) {
      final before = controller.text.length;
      final aStart = _mathStart!;
      closeInlineMath(MathExit.done, reposition: false);
      final removed = before - controller.text.length;
      if (removed > 0 && aStart < start) {
        start -= removed;
        end -= removed;
      }
      final run = controller.mathRunNear(start);
      if (run == null || run.start != start) return; // B moved; ask again
      end = run.end;
      latex = run.inner;
    }
    final ed = MathEditor.open(latex);
    if (ed == null) {
      // The tree cannot hold this equation (an import using a construct we
      // don't model). The LaTeX escape hatch edits it as source instead -
      // never silently reshaped (v0.18 6.6).
      _openSourcePanel(start, end, latex);
      return;
    }
    if (atStart) {
      ed.placeAtStart();
    } else {
      ed.placeAtEnd();
    }
    _mathStart = start;
    _mathEnd = end;
    _mathEditor = ed;
    // The empty pair $$ is INLINE (it is the chip); only a filled $$x$$
    // is a display equation.
    _mathDollars =
        end - start >= 4 && controller.text.codeUnitAt(start + 1) == 0x24
            ? 2
            : 1;
    controller.editingMathAt = start;
    _inlineSource = null;
    _graphAnchor = ed.latex.trim();
    _mathSelfText = controller.text;
    // Park the host caret INSIDE the run - offset start+1 is "this equation"
    // (v0.20 B.4) - and repaint the span tree so the editor mounts.
    controller.selection = TextSelection.collapsed(offset: start + 1);
    controller.refreshSpans();
  }

  /// The paragraph this session is editing.
  ///
  /// Asked of the model rather than held: the session is deliberately given
  /// no `Block` (ADR-0004 — only the host may touch one), and NAMING the
  /// block for a link is not touching it. An equation is only ever open while
  /// its own paragraph is the one being edited, so this is that paragraph.
  String? get _hostBlockId => app.editingBlockId;

  /// The raw text last typed in this equation's LaTeX panel, or null.
  ///
  /// Cleared by any edit made with the buttons, because a source that no
  /// longer describes the equation is worse than none: reopening the panel
  /// would offer to rebuild the equation from it.
  String? _inlineSource;

  /// What any graph made from this equation is currently following.
  ///
  /// Set when the equation is opened and moved forward on every keystroke, so
  /// the graph is always chasing the text it last saw rather than the text it
  /// was born with.
  String? _graphAnchor;

  /// A graph of the equation being written, beside the paragraph.
  void _drawGraph() {
    final ed = _mathEditor;
    if (ed == null) return;
    final latex = ed.latex.trim();
    if (latex.isEmpty) return;
    app.pushUndo();
    final host = _hostBlockId;
    if (host == null) return;
    app.insertGraph(latex: latex, from: host, fromLatex: latex);
    _graphAnchor = latex;
  }

  /// **Work out every OTHER equation in this paragraph again.**
  ///
  /// The page-wide pass a DEG/RAD press starts skips the block being edited,
  /// because rewriting a live one from outside reads as a foreign edit and
  /// closes the equation. For a maths BLOCK that is exactly right: the one
  /// open equation refreshes itself. For a sentence, "the block being edited"
  /// is the whole paragraph, so every other answered equation in it was left
  /// showing the old mode's number — in a grey panel that says the app worked
  /// it out, under a button that now says the opposite.
  ///
  /// Only the session that owns the buffer can rewrite it safely, so it does:
  /// backwards, skipping the open run, and carrying the open equation's own
  /// offsets along by however much the text in front of it changed length.
  void _reworkSiblingMath(AngleMode writtenIn) {
    final start = _mathStart;
    final text = controller.text;
    var out = text;
    var shift = 0;
    for (final run in mathRunsIn(text).toList().reversed) {
      if (run.start == start) continue; // it does its own
      if (!run.latex.contains('boxed')) continue;
      // Read in the mode the digits were WRITTEN in, so the figures the
      // student chose for each one are recognised; refreshed in the mode
      // that is on now.
      final saved = mathAngleMode;
      mathAngleMode = writtenIn;
      final MathEditor? e;
      try {
        e = MathEditor.open(run.latex);
      } finally {
        mathAngleMode = saved;
      }
      if (e == null || !e.refreshAnswers()) continue;
      out = replaceMathRun(out, run, e.latex);
      if (start != null && run.start < start) {
        shift += e.latex.length - run.latex.length;
      }
    }
    if (out == text) return;
    final sel = controller.selection;
    _mathSelfEditing = true;
    try {
      controller.value = controller.value.copyWith(
        text: out,
        selection: sel.isValid
            ? TextSelection.collapsed(offset: sel.baseOffset + shift)
            : sel,
        composing: TextRange.empty,
      );
    } finally {
      _mathSelfEditing = false;
    }
    if (start != null) {
      _mathStart = start + shift;
      _mathEnd += shift;
      controller.editingMathAt = _mathStart;
    }
    _mathSelfText = controller.text;
    controller.refreshSpans();
    onChanged(controller.text);
  }

  /// Every keystroke inside the equation, written straight through to the
  /// sentence. The re-derived end is what keeps a growing equation from
  /// overwriting the word after it.
  void _inlineMathChanged(String next) {
    final start = _mathStart;
    if (start == null) return;
    // Re-derive the end from the buffer, never trust the cache: replaceMathAt
    // silently refuses a stale range, and _mathEnd advancing anyway is how
    // the screen and the saved note diverged. A run that has MOVED means a
    // foreign rewrite beat the watcher to this keystroke — close, don't
    // write over whatever is there now.
    final run = controller.mathRunNear(start);
    if (run == null || run.start != start) {
      closeInlineMath(MathExit.done, reposition: false);
      return;
    }
    _mathEnd = run.end;
    final tidy = next.trim();
    // An emptied equation stays as its `$$` pair WHILE editing - removing
    // the dollars would unmount the very editor the student is typing into.
    // The pair is swept on close.
    final wrap = r'$' * _mathDollars;
    final written = tidy.isEmpty ? '\$\$' : '${wrap}${tidy}${wrap}';
    _mathSelfEditing = true;
    try {
      controller.replaceMathAt(start, _mathEnd, tidy,
          keepEmptyPair: true, caretAt: start + 1, dollars: _mathDollars);
    } finally {
      _mathSelfEditing = false;
    }
    _mathEnd = start + written.length;
    _mathSelfText = controller.text;
    // An edit made with the buttons; the typed source no longer describes
    // this equation. The source path re-sets it straight afterwards (see
    // `EquationEditor._commitSource`, which commits in that order for exactly
    // this reason).
    _inlineSource = null;
    // **Any graph of this equation redraws now**, not on a timer: the owner
    // asked to see the graph change as they type, and a compiled curve costs
    // microseconds a sample. The anchor moves with it, so the next keystroke
    // finds the same graph again.
    final was = _graphAnchor;
    final host = _hostBlockId;
    if (was != null && host != null && was != tidy) {
      // **Not if another equation in this sentence reads the same thing.**
      //
      // This is how typing in one equation used to steal a different one's
      // graph. Write `y=x`, draw it, start a second equation and type `=x`
      // into it: for one keystroke both read `y=x`, and the next keystroke
      // moved the FIRST equation's graph on to the second, link and all,
      // with nothing for Ctrl+Z to bring back.
      //
      // The buffer has already been written, so this equation reads [tidy]
      // and anything still reading [was] is somebody else. The anchor stays
      // put as well, so this equation's own graph picks the thread back up
      // as soon as the two stop reading alike.
      final mine = mathRunsIn(controller.text)
          .where((r) => r.latex.trim() == was)
          .length;
      if (mine == 0) {
        app.pushInlineEquationToGraphs(host, was, tidy);
        _graphAnchor = tidy;
      }
    }
    onChanged(controller.text);
    _scheduleSpellCheck();
  }

  /// The ONE exit path (v0.20 B.2.5): keyboard exits, clicks elsewhere and
  /// teardown all come through here, so the empty sweep and the caret's
  /// landing place cannot disagree between routes.
  void closeInlineMath(MathExit how, {bool reposition = true}) {
    final start = _mathStart;
    if (start == null) return;
    final end = _mathEnd;
    final latex = (_mathEditor?.latex ?? '').trim();
    _mathStart = null;
    _mathEditor = null;
    // **The link's tint goes out with the equation.** The owner's rule is
    // that it shows only while one end of the link is chosen; leaving the
    // anchor set left an equation lit up in a paragraph nobody was in.
    _graphAnchor = null;
    controller.editingMathAt = null;
    final pad = _mathPadded;
    _mathPadded = false;
    if (latex.isEmpty) {
      // Alt+= then Escape must not leave `$$` in the note for ever. The
      // sweep is VERIFIED first: after a foreign rewrite the cached range may
      // hold someone else's characters, and deleting those would be a second
      // corruption on the way out.
      final t = controller.text;
      if (end <= t.length && t.substring(start, end) == '\$\$') {
        // The mid-word pad goes with it, or Alt+= then Escape in the middle
        // of a word leaves it permanently split.
        final stop = pad && end < t.length && t.codeUnitAt(end) == 0x20
            ? end + 1
            : end;
        _mathSelfEditing = true;
        try {
          controller.replaceMathAt(start, stop, '');
        } finally {
          _mathSelfEditing = false;
        }
        _mathSelfText = controller.text;
        onChanged(controller.text);
      }
    } else if (reposition) {
      final off = how == MathExit.left ? start : end;
      controller.selection = TextSelection.collapsed(
          offset: off > controller.text.length ? controller.text.length : off);
    }
    controller.refreshSpans();
    if (reposition) _focus.requestFocus();
  }

  void _maybeCloseOnCaretExit() {
    final start = _mathStart;
    if (start == null || _mathSelfEditing) return;
    // A buffer change the session did not make — undo restoring an older
    // buffer, the toolbar's Bold wrapping the word at the parked caret — kills
    // the cached anchors AND the tree's claim to match the note. The only
    // safe move is out: close without repositioning and let the buffer's own
    // grammar redraw whatever is really there. Both routes were probe-proven
    // to corrupt the note when the session stayed open.
    if (_mathSelfText != null && controller.text != _mathSelfText) {
      closeInlineMath(MathExit.done, reposition: false);
      return;
    }
    final sel = controller.selection;
    if (!sel.isValid) return;
    if (sel.baseOffset < start || sel.baseOffset > _mathEnd) {
      // The student clicked somewhere else in the paragraph; the host's own
      // tap already placed the caret, so don't yank it back.
      closeInlineMath(MathExit.done, reposition: false);
    }
  }

  /// The caret crossing an equation's edge steps INSIDE it rather than over
  /// it (v0.20 B.4) - Backspace and Delete at an edge do the same instead of
  /// eating a `$` nobody can see (B.5).
  bool _enterMathAtEdge({required bool fromRight}) {
    final sel = controller.selection;
    if (!sel.isValid || !sel.isCollapsed) return false;
    final at = sel.baseOffset;
    final run = controller.mathRunNear(at);
    if (run == null) return false;
    if (fromRight && at == run.end) {
      enterInlineMath(run.start, run.end, run.inner, atStart: false);
      return true;
    }
    if (!fromRight && at == run.start) {
      enterInlineMath(run.start, run.end, run.inner, atStart: true);
      return true;
    }
    return false;
  }

  /// **A click past an equation that ENDS its line steps into it.**
  ///
  /// The owner: *"clicking on the end of a text box doesnt at the moment
  /// automatically put me into the maths editor."* Clicking in the blank space
  /// to the right of a trailing equation, or below the last line, put the
  /// caret at `run.end` and stopped there — while ArrowLeft from that exact
  /// offset had always stepped inside. Same caret, same run, two answers.
  ///
  /// **The "it ends the line" test is the load-bearing part.** In
  /// `$y=3x$ and more` the seam after the equation is an ordinary caret
  /// position that has to stay one, or the words after an equation become
  /// untypable. Only when there is nothing after it but the end of the line
  /// is the click unambiguous — there is nowhere else it could have meant.
  ///
  /// Escape is still one key away, and lands the caret back at `run.end` with
  /// the editor closed, so a student who wants to keep writing can.
  bool _enterMathOnTapAtLineEnd() {
    if (_mathStart != null) return false; // one is already open
    final sel = controller.selection;
    if (!sel.isValid || !sel.isCollapsed) return false;
    final at = sel.baseOffset;
    final run = controller.mathRunNear(at);
    if (run == null || at != run.end) return false;
    final t = controller.text;
    if (run.end != t.length && t.codeUnitAt(run.end) != 0x0A) return false;
    enterInlineMath(run.start, run.end, run.inner, atStart: false);
    return true;
  }

  /// An equation the visual tree cannot hold, edited as source in a small
  /// anchored panel - the only surviving overlay (v0.20 A.5).
  void _openSourcePanel(int start, int end, String latex) {
    final ctx = _lastContext;
    if (ctx == null || !ctx.mounted) return;
    final box = _focus.context?.findRenderObject() as RenderBox?;
    final anchor = box == null || !box.hasSize
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : box.localToGlobal(Offset.zero) & box.size;
    var current = end;
    EquationSourcePanel.show(
      ctx,
      anchor: anchor,
      latex: latex,
      onChanged: (next) {
        final tidy = next.trim();
        final written = tidy.isEmpty ? '' : '\$${tidy}\$';
        // Re-derived when possible: an edit the panel did not make (undo
        // under the open panel) leaves `current` stale, and a write against
        // a stale end lands on the words AFTER the equation.
        final run = controller.mathRunNear(start);
        final stop = run != null && run.start == start ? run.end : current;
        controller.replaceMathAt(start, stop, tidy);
        current = start + written.length;
        onChanged(controller.text);
      },
      onDone: () => _focus.requestFocus(),
    );
  }

  /// The most recent context this session built in — the only handle it has on
  /// an `Overlay`, since a session is not a widget.
  BuildContext? _lastContext;

  /// Needed only so the in-place equation editor can register with the
  /// toolbar's Maths tab — the session itself never reads the model.
  final AppState app;
  final LiveMarkdownController controller;
  final ValueChanged<String> onChanged;
  final FocusNode _focus = FocusNode();

  /// Debounce so a check runs between keystrokes, not on each one. Checking a
  /// block is sub-millisecond once the dictionary is resident, but re-styling
  /// the whole span tree mid-word makes typing feel busy.
  Timer? _spellDebounce;

  void _scheduleSpellCheck({Duration delay = const Duration(milliseconds: 300)}) {
    if (!spellCheckEnabled) {
      controller.misspellings = const [];
      return;
    }
    _spellDebounce?.cancel();
    _spellDebounce = Timer(delay, () async {
      final checker = SpellChecker.loaded ?? await SpellChecker.instance();
      // The session may have been disposed while the dictionary loaded.
      if (_disposed) return;
      controller.misspellings = checker.check(controller.text);
    });
  }

  /// Check the text a session opens with, without waiting for a keystroke.
  void scheduleInitialSpellCheck() =>
      _scheduleSpellCheck(delay: const Duration(milliseconds: 50));

  // ── List keystrokes (list_editing.dart) ─────────────────────────────────
  //
  // Enter continues the list, Enter on an empty item leaves it, Tab nests and
  // Shift+Tab un-nests, Backspace at the start of an item unwraps it. Before
  // this the field had no key handling at all beyond Alt+X, so the single
  // most common thing anyone does while taking notes — bullet, Enter, Tab —
  // did nothing, and Tab actually left the text box.
  //
  // Intercepted here rather than in an input formatter because Tab never
  // reaches the field as text, and because the embedder composes a character
  // only for a key the framework reports UNHANDLED — which is what lets
  // `handled` suppress the newline the field would otherwise insert.

  /// Commit a programmatic edit the way a keystroke would: the field's own
  /// `onChanged` never fires for one, so the block would otherwise render the
  /// change and never save it.
  void _applyEdit(TextEditingValue next) {
    controller.value = next;
    onChanged(next.text);
    _scheduleSpellCheck(delay: const Duration(milliseconds: 10));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // Gate ONE of three (v0.20 B.2.6): while an inline equation holds the
    // keyboard, every keystroke that bubbles up here was already offered to
    // the equation and declined - it belongs to nobody else in this session.
    // Above the Alt+X check on purpose: Alt+X would otherwise rewrite the
    // code point at the HOST caret while the student is inside an equation.
    if (inlineMathFocused) return KeyEventResult.ignored;
    if (isAltXChord(event) && _applyAltX()) return KeyEventResult.handled;
    // A REPEAT counts. Holding Enter on `- item` fires one down event and
    // then repeats, and skipping those let the field insert plain newlines
    // between the handled ones — stranding a bare `- ` marker mid-run.
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final hw = HardwareKeyboard.instance;
    // A chord is somebody else's (Ctrl+B, Ctrl+Enter, the canvas nudges).
    if (hw.isControlPressed || hw.isMetaPressed || hw.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final k = event.logicalKey;
    // The caret crossing an equation steps INSIDE it, one step, from either
    // side (v0.20 B.4). Only a plain arrow: Shift+arrow selects OVER the
    // equation as a unit, which is its own correct behaviour (E.4).
    if (!hw.isShiftPressed && k == LogicalKeyboardKey.arrowLeft) {
      if (_enterMathAtEdge(fromRight: true)) return KeyEventResult.handled;
      return KeyEventResult.ignored;
    }
    if (!hw.isShiftPressed && k == LogicalKeyboardKey.arrowRight) {
      if (_enterMathAtEdge(fromRight: false)) return KeyEventResult.handled;
      return KeyEventResult.ignored;
    }
    final TextEditingValue? next;
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      next = hw.isShiftPressed
          ? handleListShiftEnter(controller.value)
          : handleListEnter(controller.value);
    } else if (k == LogicalKeyboardKey.tab) {
      next = handleListTab(controller.value, outdent: hw.isShiftPressed);
      // Tab is ALWAYS consumed inside a text box, even when the engine
      // declines to change anything — Shift+Tab at the left margin, or Tab
      // on a list's first item, which has no parent to nest under. Falling
      // through returns `ignored`, and Flutter's focus traversal then moves
      // the caret out of the box entirely: the exact behaviour this handler
      // exists to remove, reappearing on the one keystroke that declines.
      if (next == null) return KeyEventResult.handled;
    } else if (k == LogicalKeyboardKey.backspace) {
      // Backspace at an equation's right edge steps INSIDE it (v0.20 B.5) -
      // the default would eat the closing dollar nobody can see and revert
      // the whole equation to source, the exact defect class markerAwareDelete
      // exists to prevent for `**bold**`.
      if (!hw.isShiftPressed && _enterMathAtEdge(fromRight: true)) {
        return KeyEventResult.handled;
      }
      // The list unwrap first — it owns the start of a list item's body, which
      // is a different position from any marker edge.
      next = hw.isShiftPressed
          ? null
          : handleListBackspace(controller.value) ??
              controller.markerAwareDelete(controller.value, forward: false);
    } else if (k == LogicalKeyboardKey.delete) {
      // Delete at an equation's left edge is Backspace's mirror: step in.
      if (!hw.isShiftPressed && _enterMathAtEdge(fromRight: false)) {
        return KeyEventResult.handled;
      }
      // Delete has no list behaviour, only the marker edges. See
      // LiveMarkdownController.markerAwareDelete for why the default is wrong
      // now that the markers cannot be seen.
      next = hw.isShiftPressed
          ? null
          : controller.markerAwareDelete(controller.value, forward: true);
    } else {
      return KeyEventResult.ignored;
    }
    if (next == null) return KeyEventResult.ignored;
    _applyEdit(next);
    return KeyEventResult.handled;
  }

  bool _disposed = false;

  /// Set by the host from app state; a plain field so the session doesn't need
  /// a reference to AppState.
  bool spellCheckEnabled = true;

  @override
  TextEditingController? get commandController => controller;

  @override
  Offset? pendingCaretGlobal;

  @override
  String get text => controller.text;

  @override
  set text(String value) {
    if (controller.text != value) controller.text = value;
  }

  /// Reach the live [EditableTextState] that owns our focus node.
  ///
  /// **Upwards, and that is the whole trick.** `EditableText.build` wraps its
  /// content in `Focus(focusNode: widget.focusNode, …)` — the Focus is built
  /// *inside* EditableText — so the node's context sits BELOW the state, and
  /// walking down from it can never find it. Searching downwards silently
  /// returned null every time, which is why the caret kept landing at the end
  /// of the block: with no offset to place, `EditableText` fell through to
  /// `_adjustedSelectionWhenFocused`, whose documented behaviour is "place
  /// cursor at the end if the selection is invalid when we receive focus".
  ///
  /// This is the one place the engine leans on Flutter's internal widget
  /// composition, which is why every caller treats a null answer as "don't
  /// know" rather than an error.
  EditableTextState? _editableState() {
    final ctx = _focus.context;
    // `mounted` is load-bearing: an ancestor walk from a deactivated element
    // asserts, and this runs from a post-frame callback that can fire after
    // the block has been rebuilt out from under us.
    if (ctx == null || !ctx.mounted) return null;
    EditableTextState? found;
    ctx.visitAncestorElements((e) {
      if (e is StatefulElement && e.state is EditableTextState) {
        found = e.state as EditableTextState;
        return false;
      }
      return true;
    });
    return found;
  }

  /// **Known imprecision, by construction.** The point comes from a click on
  /// the READ-ONLY view, where Markdown markers are gone, and is resolved
  /// against the EDIT view, where they are present (dimmed, or collapsed to a
  /// hairline). On a plain line the two layouts are identical and the caret
  /// lands exactly where you clicked; on a line with markers it can be off by
  /// their width. Every live-Markdown editor has this, and the alternative —
  /// teaching `MarkdownView` to report source offsets — is a much larger piece
  /// of machinery than the error justifies. Worth knowing before someone files
  /// it as the "caret at the end" bug again; that one was a different thing
  /// entirely (see [_editableState]).
  @override
  int? offsetAtGlobal(Offset globalPosition) {
    final st = _editableState();
    if (st == null) return null;
    try {
      final r = st.renderEditable;
      if (!r.hasSize) return null;
      return r.getPositionForPoint(globalPosition).offset;
    } catch (_) {
      // No layout yet, or the field went away between frames.
      return null;
    }
  }

  @override
  void setSelection(int base, int extent) {
    final n = controller.text.length;
    controller.selection = TextSelection(
      baseOffset: base.clamp(0, n),
      extentOffset: extent.clamp(0, n),
    );
  }

  @override
  Widget build(BuildContext context, TextSurface s) {
    controller.dark = s.dark;
    // The only handle a session — which is not a widget — has on an Overlay,
    // for the inline equation editor to anchor itself in.
    _lastContext = context;
    // Focus is claimed post-frame: the host decides *that* a block is being
    // edited, but the field only exists after this build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_focus.context == null) return;
      // Place the caret where the click landed BEFORE taking focus.
      // EditableText's focus handler only overwrites an INVALID selection, so
      // setting a valid one first survives — and without this the caret always
      // jumped to the END of the block, so clicking into the middle of a
      // paragraph put you somewhere else.
      final want = pendingCaretGlobal;
      if (want != null) {
        pendingCaretGlobal = null;
        final at = offsetAtGlobal(want);
        if (at != null) {
          controller.selection = TextSelection.collapsed(offset: at);
          // The first click into a block that was not being edited comes
          // through here rather than through the field's own onTap.
          _enterMathOnTapAtLineEnd();
        }
      }
      if (!_focus.hasFocus) _focus.requestFocus();
    });
    return Padding(
      padding: s.inset,
      child: Focus(
        // Chords are intercepted above the field so they run before the
        // character would be typed — the embedder only composes text for a
        // key the framework reported unhandled. Returning `ignored` when no
        // rule applies keeps every other key available to whoever wants it.
        onKeyEvent: _onKey,
        child: LayoutBuilder(builder: (context, cons) {
          // The hanging indent for wrapped list lines has to know the width
          // the field's paragraph will be laid out at, and it has to know it
          // in the SAME frame or a resize would draw the indent against last
          // frame's wrap points — a gap in the middle of a line, which is far
          // worse than no indent. LayoutBuilder builds its child during
          // layout, so this assignment lands before `buildTextSpan` runs.
          // A plain field, never a notifying setter: this runs inside layout.
          controller.layoutWidth = cons.maxWidth.isFinite
              ? cons.maxWidth - kEditorCaretMargin
              : null;
          return _field(context, s);
        }),
      ),
    );
  }

  Widget _field(BuildContext context, TextSurface s) => ListenableBuilder(
      // The host keeps focus while an inline equation is edited (the field is
      // its focus DESCENDANT), so without this the paragraph blinks a second
      // caret right next to the equation's own.
      listenable: _mathFocus,
      builder: (context, _) => TextField(
      controller: controller,
      focusNode: _focus,
      // Fires ONCE, after the caret has been placed, and never for a tap
      // that landed on the equation itself (that one is the atom's own
      // gesture, which wins the arena). See [_enterMathOnTapAtLineEnd].
      onTap: _enterMathOnTapAtLineEnd,
      showCursor: !_mathFocus.hasFocus,
      maxLines: null,
      style: s.baseStyle,
      // NON-FORCED strut, explicitly. TextField's default when none is
      // given is `StrutStyle.fromTextStyle(style, forceStrutHeight: true)`,
      // and a forced strut makes every line box EXACTLY the base height —
      // per-span metrics are discarded, so the controller's 22px heading
      // style was being measured and then thrown away. That is most of why
      // "the text slightly compresses during editing": headings physically
      // could not be taller than a body line. Non-forced keeps the strut as
      // a minimum (empty and marker-only lines hold their height) while a
      // taller span grows its line, same as the read renderer.
      strutStyle:
          StrutStyle.fromTextStyle(s.baseStyle, forceStrutHeight: false),
      cursorColor: Theme.of(context).colorScheme.primary,
      inputFormatters: const [
        WrapSelectionFormatter(),
        // Maths pasted into a paragraph arrives as maths. See the file
        // header for why this is a formatter and not a key handler.
        MathPasteFormatter(),
      ],
      decoration: InputDecoration(
        isDense: true,
        // Zero, not the dense default: InputDecorator otherwise adds 8px
        // of vertical padding that the read renderer does not have, so
        // every block grew 8px on entering edit and shrank back on exit.
        // The block's own inset already provides the breathing room.
        contentPadding: EdgeInsets.zero,
        border: InputBorder.none,
        // The rest of the borderless set, because the themed
        // InputDecorationTheme's enabledBorder would otherwise win over
        // this one and put an outline round every text block.
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        hintText: s.hintText,
        hintStyle:
            const TextStyle(color: OnoteColors.graphite400, fontSize: 13),
      ),
      // Spell suggestions on right-click. Flutter's own spell-check menu
      // is unreachable here (see spell/spell_checker.dart for why), so the
      // corrections are spliced into the standard adaptive menu instead of
      // replacing it — cut/copy/paste must keep working.
      contextMenuBuilder: (context, editable) {
        // **One menu, not two.** `MathField` answers the right button on a
        // raw `Listener`, which never enters the gesture arena — so the same
        // press also opened the paragraph's cut/copy/paste toolbar over the
        // top of the answer's own menu, offering actions that act on the
        // SENTENCE. A block equation has no such second menu; this is the
        // same rule, stated the same way as the caret is two lines up.
        if (_mathFocus.hasFocus) return const SizedBox.shrink();
        final items = [...editable.contextMenuButtonItems];
        final extra = _spellMenuItems(editable);
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: editable.contextMenuAnchors,
          buttonItems: [...extra, ...items],
        );
      },
      onChanged: (v) {
        onChanged(v);
        _scheduleSpellCheck();
      }));

  /// Correction items for the word under the caret, plus "Add to dictionary".
  /// Empty when the click didn't land on a misspelling — the menu then looks
  /// exactly as it always did.
  List<ContextMenuButtonItem> _spellMenuItems(EditableTextState editable) {
    final checker = SpellChecker.loaded;
    if (checker == null || !spellCheckEnabled) return const [];
    final sel = controller.selection;
    if (!sel.isValid) return const [];
    final text = controller.text;
    final range = checker.misspelledAt(text, sel.baseOffset.clamp(0, text.length));
    if (range == null) return const [];
    final word = text.substring(range.start, range.end);

    void replaceWith(String replacement) {
      final next = text.replaceRange(range.start, range.end, replacement);
      controller.value = controller.value.copyWith(
        text: next,
        selection:
            TextSelection.collapsed(offset: range.start + replacement.length),
        composing: TextRange.empty,
      );
      onChanged(next); // a programmatic edit doesn't fire the field's onChanged
      _scheduleSpellCheck(delay: const Duration(milliseconds: 10));
      editable.hideToolbar();
    }

    return [
      for (final s in checker.suggest(word))
        ContextMenuButtonItem(label: s, onPressed: () => replaceWith(s)),
      ContextMenuButtonItem(
        label: 'Add to dictionary',
        onPressed: () {
          learnWord(word);
          _scheduleSpellCheck(delay: const Duration(milliseconds: 10));
          editable.hideToolbar();
        },
      ),
    ];
  }

  /// Convert the code point at the caret (or the selection) in place. Returns
  /// false when nothing applied, so the keystroke can fall through.
  bool _applyAltX() {
    final edit = applyAltX(controller.text, controller.selection);
    if (edit == null) return false;
    controller.value = controller.value.copyWith(
      text: edit.text,
      selection: edit.selection,
      composing: TextRange.empty,
    );
    // The field's own onChanged doesn't fire for a programmatic edit, so the
    // host has to be told or the change would never be persisted.
    onChanged(edit.text);
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    // The one exit path runs even on teardown, so Alt+= followed by clicking
    // a different block cannot leave an empty `$$` in the note.
    closeInlineMath(MathExit.done, reposition: false);
    EquationSourcePanel.dismiss();
    _lastContext = null;
    _spellDebounce?.cancel();
    controller.removeListener(_maybeCloseOnCaretExit);
    controller.dispose();
    _focus.dispose();
    _mathFocus.dispose();
  }
}
