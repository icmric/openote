import 'package:flutter/material.dart';

import '../markdown/md_render.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';

/// Text block with interim inline-Markdown (TEXT-2/4 at block granularity):
/// view mode RENDERS the Markdown; entering the block reveals the source.
/// Replaced wholesale by the ADR-0004 bake-off winner for true span-level
/// as-you-type rendering. Storage stays content['text'] (Markdown dialect,
/// Data Model Spec §5.2), so the swap won't touch saved notebooks.
class TextBlockView extends StatefulWidget {
  const TextBlockView({super.key, required this.block, required this.app});
  final Block block;
  final AppState app;

  @override
  State<TextBlockView> createState() => _TextBlockViewState();
}

class _TextBlockViewState extends State<TextBlockView> {
  late final TextEditingController _controller;
  final _focus = FocusNode();
  bool _undoPushed = false;
  bool _wasEditing = false;

  bool get editing => widget.app.editingBlockId == widget.block.id;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: widget.block.content['text'] as String? ?? '');
  }

  /// F-3 fix: exit cleanup runs on the STATE transition (editing → not),
  /// never on focus ordering (select(null) used to clear editingBlockId
  /// before focus loss, so focus-listener cleanup never ran).
  void _handleExitTransition() {
    if (_wasEditing && !editing) {
      _undoPushed = false;
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
    final style = TextStyle(
      fontSize: 15,
      height: 1.5,
      color: dark ? OnoteColors.moon100 : OnoteColors.graphite700,
    );

    if (editing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_focus.hasFocus) _focus.requestFocus();
      });
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: TextField(
          controller: _controller,
          focusNode: _focus,
          maxLines: null,
          style: style,
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
            widget.app.markDirty();
          },
        ),
      );
    }

    final text = widget.block.content['text'] as String? ?? '';
    // Keep controller in sync when model changed externally (undo/redo).
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
