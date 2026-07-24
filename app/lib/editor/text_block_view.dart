import 'package:flutter/material.dart';

import '../markdown/md_render.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'live_markdown_controller.dart';

/// Text block. While editing, a [LiveMarkdownController] styles Markdown in
/// real time (markers collapse as constructs complete, reveal when the caret
/// re-enters). When not editing, [MarkdownView] renders the full block
/// (headings, lists, checkboxes, inline math, wiki-links). Storage is an interim
/// Markdown string in content['text'], NOT the spec's structured `{nodes:[…]}`
/// model (Data Model Spec §5.1). It's forward-compatible via the unknown-field
/// round-trip, but the ADR-0004 structured editor will need a one-time
/// Markdown→nodes conversion — not a zero-touch drop-in.
class TextBlockView extends StatefulWidget {
  const TextBlockView({super.key, required this.block, required this.app});
  final Block block;
  final AppState app;

  static const double minAutoW = 200, maxAutoW = 640;

  static String? _fontFamilyOf(String? font) => switch (font) {
        null || '' || 'sans' => null,
        'serif' => 'Georgia', // legacy token
        'mono' => 'monospace', // legacy token
        _ => font, // any system family name (font picker)
      };

  /// The base text style for a block. Static so the canvas layer can measure
  /// auto-width with the *exact* style the field will render with.
  static TextStyle baseStyle(Block b, {required bool dark}) => TextStyle(
        fontSize: 15,
        height: 1.5,
        fontFamily: _fontFamilyOf(b.content['font'] as String?),
        color: dark ? OnoteColors.moon100 : OnoteColors.graphite700,
      );

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
    final text = b.content['text'] as String? ?? '';
    final tp = TextPainter(
      text: TextSpan(text: text.isEmpty ? ' ' : text, style: baseStyle(b, dark: dark)),
      textDirection: TextDirection.ltr,
      maxLines: null,
    )..layout(maxWidth: double.infinity); // width = intrinsic longest line
    return (tp.width + chrome + slack).clamp(minAutoW, maxAutoW).toDouble();
  }

  @override
  State<TextBlockView> createState() => _TextBlockViewState();
}

class _TextBlockViewState extends State<TextBlockView> {
  late final LiveMarkdownController _controller;
  final _focus = FocusNode();
  bool _undoPushed = false;
  bool _wasEditing = false;

  bool get editing => widget.app.editingBlockId == widget.block.id;

  @override
  void initState() {
    super.initState();
    _controller = LiveMarkdownController(
        text: widget.block.content['text'] as String? ?? '',
        dark: false);
  }

  /// F-3 fix: exit cleanup runs on the STATE transition (editing → not).
  void _handleExitTransition() {
    if (_wasEditing && !editing) {
      _undoPushed = false;
      widget.app.clearActiveEditor(widget.block.id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if ((widget.block.content['text'] as String? ?? '').trim().isEmpty) {
          widget.app.removeBlock(widget.block.id, recordUndo: false);
        }
      });
    }
    _wasEditing = editing;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _handleExitTransition();
    final dark = Theme.of(context).brightness == Brightness.dark;
    _controller.dark = dark;
    final style = TextBlockView.baseStyle(widget.block, dark: dark);

    if (editing) {
      widget.app.setActiveEditor(_controller, widget.block, 'text');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_focus.hasFocus) _focus.requestFocus();
      });
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: TextField(
          controller: _controller,
          focusNode: _focus,
          maxLines: null,
          style: style,
          cursorColor: Theme.of(context).colorScheme.primary,
          inputFormatters: [WrapSelectionFormatter()],
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            hintText: 'Type here…  (# heading, - list, - [ ] task, **bold**)',
            hintStyle: TextStyle(color: OnoteColors.graphite400, fontSize: 13),
          ),
          onChanged: (v) {
            if (!_undoPushed) {
              widget.app.pushUndo();
              _undoPushed = true;
            }
            widget.block.content['text'] = v;
            widget.block.updatedAt = nowMs();
            // Width is measured in the parent build (lag-free); markDirty here
            // triggers that rebuild so the box grows in the same frame.
            widget.app.markDirty();
          },
        ),
      );
    }

    final text = widget.block.content['text'] as String? ?? '';
    if (_controller.text != text) _controller.text = text;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: MarkdownView(
        text: text,
        baseStyle: style,
        onWikiLink: (label, id) => widget.app.openWikiLink(label, id),
        onToggleCheckbox: (newText) {
          widget.app.pushUndo();
          widget.block.content['text'] = newText;
          _controller.text = newText;
          widget.app.updateBlock(widget.block);
        },
      ),
    );
  }
}
