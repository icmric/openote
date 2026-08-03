import 'package:flutter/material.dart';

import '../export/onenote_import.dart' show oneNoteLineHeight;
import '../model/models.dart';
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
  static TextStyle baseStyle(Block b, {required bool dark}) => TextStyle(
        fontSize: (b.content['fontSize'] as num?)?.toDouble() ?? 15,
        height: _lineHeightOf(b),
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
    final engine = OnoteEditors.active;
    // Image references are stripped before measuring: `![](sha256:<64 hex>)`
    // is 80-odd characters of source that the reader never sees, and measuring
    // it would pin any auto-width box to its maximum the instant a picture
    // landed in it.
    final source = engine
        .deserialize(b.content)
        .replaceAll(RegExp(r'^\s*!\[[^\]]*\]\([^)]*\)\s*$', multiLine: true), '');
    final w = engine.measureIntrinsicWidth(source, baseStyle(b, dark: dark));
    return (w + chrome + slack).clamp(minAutoW, maxAutoW).toDouble();
  }

  @override
  State<TextBlockView> createState() => _TextBlockViewState();
}

class _TextBlockViewState extends State<TextBlockView> {
  /// Live only while this block is the one being edited. Nineteen unfocused
  /// containers hold no session, no controller and no focus node.
  OnoteEditSession? _session;
  bool _undoPushed = false;
  bool _wasEditing = false;

  OnoteTextEditor get _engine => OnoteEditors.active;

  bool get editing => widget.app.editingBlockId == widget.block.id;

  /// F-3 fix: exit cleanup runs on the STATE transition (editing → not).
  void _handleExitTransition() {
    if (_wasEditing && !editing) {
      _undoPushed = false;
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

  OnoteEditSession _openSession() => _engine.openSession(
        block: widget.block,
        app: widget.app,
        onChanged: (v) {
          if (!_undoPushed) {
            widget.app.pushUndo();
            _undoPushed = true;
          }
          _engine.serialize(widget.block.content, v);
          widget.block.updatedAt = nowMs();
          // Width is measured in the parent build (lag-free); markDirty here
          // triggers that rebuild so the box grows in the same frame.
          widget.app.markDirty();
        },
      );

  @override
  void dispose() {
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
      hintText: 'Type here…  (# heading, - list, - [ ] task, **bold**)',
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
