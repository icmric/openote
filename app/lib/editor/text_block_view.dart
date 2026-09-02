import 'package:flutter/material.dart';

import '../export/onenote_import.dart' show oneNoteLineHeight;
import '../model/models.dart';
import '../model/tags.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'onote_text_editor.dart';

/// Text block — the **host** for a text container, not an editor.
///
/// Everything text-engine-specific lives behind [OnoteEditors.active]
/// (ADR-0004): this class owns only the things that are the app's business and
/// would be identical under any engine — which block is being edited, the
/// undo checkpoint, focus/exit lifecycle, and the resolved type metrics.
///
/// The read-only/live split is the ADR-0004 multi-instance pattern: one session
/// exists at a time, created on entry and disposed on exit, so a 20-container
/// page pays for one editor and nineteen cheap renders.
///
/// Storage is an interim Markdown string in `content['text']`, NOT the spec's
/// structured `{nodes:[…]}` model (Data Model Spec §5.1). It's
/// forward-compatible via the unknown-field round-trip; the conversion, when it
/// happens, belongs in [OnoteTextEditor.serialize]/[OnoteTextEditor.deserialize]
/// rather than here.
class TextBlockView extends StatefulWidget {
  const TextBlockView({super.key, required this.block, required this.app});
  final Block block;
  final AppState app;

  static const double minAutoW = 200, maxAutoW = 640;

  static String? _fontFamilyOf(String? font) => switch (font) {
        null || '' || 'sans' => 'Inter', // the bundled default face
        'serif' => 'Georgia', // legacy token
        'mono' => 'JetBrains Mono', // legacy token
        _ => font, // any system family name (font picker)
      };

  /// The base text style for a block. Static so the canvas layer can measure
  /// auto-width with the *exact* style the field will render with.
  ///
  /// `fontSize` (px) and `lineHeight` (multiplier) are optional per-block
  /// overrides — the OneNote importer sets them so imported boxes render at
  /// OneNote's metrics and absolutely-positioned neighbours line up (a box
  /// rendered shorter than the source leaves a phantom gap above the sibling
  /// below it).
  /// Letter spacing, pinned rather than inherited — and it has to be.
  ///
  /// The three paths that render or measure a text box each merge onto a
  /// DIFFERENT Material default: the read view's `Text` inherits
  /// `DefaultTextStyle` (bodyMedium, 0.25), a `TextField` merges onto
  /// `bodyLarge` (0.5), and `measureIntrinsicWidth` uses a bare `TextPainter`
  /// with no inheritance at all (0). So the same sentence was drawn at three
  /// different widths: letters visibly spread on entering edit, and the box
  /// was measured narrower than the field it had to hold, which is why lines
  /// wrapped that had no business wrapping.
  ///
  /// 0.25 keeps read mode looking exactly as it does today and brings the
  /// other two to meet it.
  static const double letterSpacing = 0.25;

  static TextStyle baseStyle(Block b, {required bool dark}) => TextStyle(
        fontSize: (b.content['fontSize'] as num?)?.toDouble() ?? 15,
        height: _lineHeightOf(b),
        letterSpacing: letterSpacing,
        fontFamily: _fontFamilyOf(b.content['font'] as String?),
        // Imported boxes name their own family (Calibri, Consolas, …), which
        // bypasses the theme's fallback list — and a maths note is full of
        // characters an ordinary text font has no glyph for. Without this those
        // characters render as blank boxes.
        fontFamilyFallback: onoteFontFallback,
        color: dark ? OnoteColors.moon100 : OnoteColors.graphite700,
      );

  /// The line-height multiplier for a block, healing the legacy import value.
  ///
  /// Imported boxes store their pitch at import time, so notebooks brought
  /// across before the metric was measured carry the old `1.35` — 10.6% too
  /// tall, which is exactly the misalignment we fixed. Rather than make people
  /// re-import, treat that specific legacy value as "OneNote default pitch" and
  /// render it correctly. Any *other* stored value is honoured verbatim, so a
  /// deliberate choice is never overridden.
  static double _lineHeightOf(Block b) {
    final stored = (b.content['lineHeight'] as num?)?.toDouble();
    if (stored == null) return 1.5; // hand-authored default
    if ((stored - _legacyImportLineHeight).abs() < 0.001) {
      return oneNoteLineHeight;
    }
    return stored;
  }

  static const _legacyImportLineHeight = 1.35;

  /// Inner padding for this box.
  ///
  /// Hand-authored boxes get a comfortable inset. **Imported** boxes get none:
  /// OneNote's stored offset is exactly where its first line starts, so an inset
  /// shifts every line down and right of the source — measured as a constant
  /// −8 u vertical / +10 u horizontal error against OneNote's own PDF. New
  /// imports set `inset: 0`; older ones are recognised by carrying an explicit
  /// `fontSize`, which only the importer writes per box.
  static EdgeInsets insetFor(Block b) {
    final explicit = (b.content['inset'] as num?)?.toDouble();
    if (explicit != null) {
      return EdgeInsets.all(explicit);
    }
    final imported = b.content['fontSize'] != null;
    return imported
        ? EdgeInsets.zero
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 8);
  }

  /// The width a text box should render at. For auto-width boxes this is the
  /// intrinsic longest-line width (+ chrome + slack), clamped. Measured in the
  /// *parent* build pass (see BlockView) so the box widens in the SAME frame
  /// the text changes — no one-frame lag, so words never wrap before the box
  /// grows. Chrome = 2×10 content padding + borders + caret ≈ 26px; slack adds
  /// headroom for the glyph being typed. Manual resize (autoWidth == false)
  /// pins the stored width and skips measuring.
  static double autoWidth(Block b, {required bool dark}) {
    if (b.type != BlockType.text || b.content['autoWidth'] == false) return b.w;
    const chrome = 26.0, slack = 18.0;
    // Memoised, because this now runs in READ mode too (see BlockView) and a
    // pan or a zoom rebuilds every visible block. Laying out a TextPainter per
    // block per frame is exactly the kind of per-frame work §7a.6 budgets
    // against; the key is everything the measurement depends on, so a cache
    // hit is always the right answer.
    //
    // `\u0000` as an ESCAPE, never as a literal NUL byte. Written literally
    // it makes ripgrep call this file binary and skip it — nine hundred lines
    // of view code invisible to every code search in the repo, including the
    // ones that go looking for bugs in it. Dart reads the two forms
    // identically. See `source_hygiene_test.dart`, which is the only thing
    // that can see the difference.
    final key = '${b.id}\u0000${b.content['text']}\u0000'
        '${b.content['fontSize']}\u0000${b.content['lineHeight']}\u0000'
        '${b.content['font']}\u0000$dark';
    final hit = _autoWidthCache[key];
    if (hit != null) return hit;
    if (_autoWidthCache.length > 512) _autoWidthCache.clear();

    final engine = OnoteEditors.active;
    // Image references are stripped before measuring: `![](sha256:<64 hex>)`
    // is 80-odd characters of source that the reader never sees, and measuring
    // it would pin any auto-width box to its maximum the instant a picture
    // landed in it.
    final source = engine
        .deserialize(b.content)
        .replaceAll(RegExp(r'^\s*!\[[^\]]*\]\([^)]*\)\s*$', multiLine: true), '');
    final w = engine.measureIntrinsicWidth(source, baseStyle(b, dark: dark));
    return _autoWidthCache[key] =
        (w + chrome + slack).clamp(minAutoW, maxAutoW).toDouble();
  }

  /// Measurement cache for [autoWidth]; see the note there.
  static final Map<String, double> _autoWidthCache = {};

  @override
  State<TextBlockView> createState() => _TextBlockViewState();
}

class _TextBlockViewState extends State<TextBlockView> {
  /// Live only while this block is the one being edited. Nineteen unfocused
  /// containers hold no session, no controller and no focus node.
  OnoteEditSession? _session;
  bool _undoPushed = false;
  bool _wasEditing = false;

  /// When the last undo point was taken, so a BURST of typing is one step.
  ///
  /// It used to be exactly one point per editing session, latched until the
  /// box stopped being edited: click in, write two sentences, mistype one
  /// character in an equation, press Ctrl+Z, and the whole visit is gone —
  /// both sentences with it. That is the very defect `MathBlockView` was
  /// written to remove ("the punishment for a mistyped character was the
  /// whole thing you were writing"), and it was still live on this side, so
  /// an equation in a sentence and one in a box answered Ctrl+Z completely
  /// differently.
  ///
  /// Coalescing on TIME rather than keeping a second undo stack, for the same
  /// reason the block editor gives: the page already has one that syncs and
  /// persists, and two stacks means two chances to disagree about which one
  /// Ctrl+Z belongs to.
  int _lastUndoAt = 0;

  /// The same 700 ms the block equation editor uses. One number, one rule.
  static const int _undoGap = 700;

  void _pushUndoOnce() {
    final now = nowMs();
    if (!_undoPushed || now - _lastUndoAt > _undoGap) {
      widget.app.pushUndo();
      _undoPushed = true;
      _lastUndoAt = now;
    }
  }

  OnoteTextEditor get _engine => OnoteEditors.active;

  bool get editing => widget.app.editingBlockId == widget.block.id;

  /// F-3 fix: exit cleanup runs on the STATE transition (editing → not).
  ///
  /// [AppState.pendingEmptyBlockId] is set at the CLICK that opens a block
  /// (`BlockView._tap`/`PageCanvas._createTextAt`), not here: this widget's
  /// own `build` runs AFTER `BlockView`'s in the same frame, so setting it
  /// on an entry transition here would always be one frame too late for the
  /// chrome decision that already needed it. This only ever clears it, on
  /// the way out — belt and braces alongside the `onChanged` clear, for an
  /// exit that was never typed into at all (Escape, click away).
  void _handleExitTransition() {
    if (_wasEditing && !editing) {
      if (widget.app.pendingEmptyBlockId == widget.block.id) {
        widget.app.pendingEmptyBlockId = null;
      }
      _undoPushed = false;
      _lastUndoAt = 0;
      widget.app.clearActiveEditor(widget.block.id);
      _closeSession();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_engine.deserialize(widget.block.content).trim().isEmpty) {
          widget.app.removeBlock(widget.block.id, recordUndo: false);
        }
      });
    }
    _wasEditing = editing;
  }

  void _closeSession() {
    _session?.dispose();
    _session = null;
  }

  OnoteEditSession _openSession() {
    final session = _rawSession();
    // Dragging an in-flow picture past the edge of its box widens the BOX
    // rather than stopping the picture. The engine cannot do this itself —
    // it may not write to the block — so it asks, and the answer is here.
    session.requestExtraWidth = (extra) {
      final b = widget.block;
      if (extra <= 0) return;
      _pushUndoOnce();
      // Without this the next build measures the text and puts the width
      // straight back: `autoWidth` measurement deliberately ignores image
      // lines, so a box widened for a picture would snap shut every frame.
      // It is the same latch the manual resize handles set, and it is one-way
      // for the same reason — the box is now a size the user chose.
      b.content['autoWidth'] = false;
      // Same ceiling as a resize handle (block_view._resizeBy). A picture
      // cannot drag a box to a width the box could not be dragged to.
      b.w = (b.w + extra).clamp(80.0, 4000.0);
      widget.app.updateBlock(b);
      widget.app.markDirty();
    };
    return session;
  }

  OnoteEditSession _rawSession() => _engine.openSession(
        block: widget.block,
        app: widget.app,
        onChanged: (v) {
          // The first real edit ends the OneNote-style pending caret: chrome
          // and arrow-key page navigation are for BEFORE typing starts, not
          // for a box that has since been typed into and emptied again.
          if (widget.app.pendingEmptyBlockId == widget.block.id) {
            widget.app.pendingEmptyBlockId = null;
          }
          _pushUndoOnce();
          // Tags record a line index, so a keystroke that adds or removes a
          // line moves every marker below it onto the wrong sentence — and
          // takes the flashcards derived from them with it. Rebase before the
          // new text lands, while both versions are still available, and carry
          // each moved tag's review schedule across with it: a card is
          // identified by `blockId:line`, so a tag that moves alone leaves its
          // schedule orphaned under a name nothing points at any more.
          widget.app.study.remapCardStates(
            widget.block.id,
            NoteTag.rebase(widget.block.content,
                _engine.deserialize(widget.block.content), v),
          );
          _engine.serialize(widget.block.content, v);
          widget.block.updatedAt = nowMs();
          // Width is measured in the parent build (lag-free); markDirty here
          // triggers that rebuild so the box grows in the same frame.
          widget.app.markDirty();
        },
      );

  @override
  void dispose() {
    // Hand the registration back BEFORE the controller dies. This is the path
    // a page or notebook switch takes: `BlockView` is keyed
    // `'<id>#<docRevision>'`, `selectPage` bumps `docRevision`, so the element
    // is replaced outright and the editing → not-editing transition in
    // [build] — the only other caller of the clear — never runs. AppState was
    // left holding a disposed controller for the rest of the session.
    final ctrl = _session?.commandController;
    if (ctrl != null) widget.app.releaseEditor(ctrl);
    _closeSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _handleExitTransition();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = TextSurface(
      block: widget.block,
      app: widget.app,
      baseStyle: TextBlockView.baseStyle(widget.block, dark: dark),
      inset: TextBlockView.insetFor(widget.block),
      dark: dark,
      // **Name first, then the marks.** The caret is already blinking here,
      // so "Type here" is the redundancy the owner named; and the four
      // pairs used to read syntax-first ("# heading"), which is the exact
      // inversion of the form they asked for everywhere else — `symbol
      // (\symbol)`, not `symbol — type \symbol`.
      hintText: 'heading (#), list (-), task (- [ ]), bold (**)',
    );

    if (editing) {
      final session = _session ??= _openSession();
      // Keep the session in step with edits that bypassed it (undo, a checkbox
      // toggled while unfocused) — the block is the source of truth.
      session.text = _engine.deserialize(widget.block.content);
      // Register for command-bar formatting. An engine with its own selection
      // model reports no controller, and the buttons then stay disabled rather
      // than acting on a stale target.
      // Hand the caret target to the session before it builds; it consumes it
      // once, so the caret lands where the click did.
      session.pendingCaretGlobal ??= widget.app.pendingCaretGlobal;
      widget.app.pendingCaretGlobal = null;
      final ctrl = session.commandController;
      if (ctrl != null) {
        widget.app.setActiveEditor(ctrl, widget.block, _engine.textStorageKey,
            session: session);
      }
      return session.build(context, surface);
    }

    return _engine.buildReadOnly(context, surface);
  }
}
