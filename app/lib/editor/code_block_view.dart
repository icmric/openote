import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'code_highlight.dart';

/// Code block (CODE-1 interim): monospace, language label, copy button,
/// preserved formatting. Syntax highlighting arrives with the re_highlight
/// integration pass — tracked, not forgotten. content: { language, source }.
class CodeBlockView extends StatefulWidget {
  const CodeBlockView({super.key, required this.block, required this.app});
  final Block block;
  final AppState app;

  @override
  State<CodeBlockView> createState() => _CodeBlockViewState();
}

class _CodeBlockViewState extends State<CodeBlockView> {
  late final TextEditingController _controller;
  final _focus = FocusNode();
  bool _undoPushed = false;

  bool get editing => widget.app.editingBlockId == widget.block.id;

  bool _wasEditing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
        text: widget.block.content['source'] as String? ?? '');
  }

  /// F-3 fix: cleanup on state transition, not focus ordering.
  void _handleExitTransition() {
    if (_wasEditing && !editing) {
      _undoPushed = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if ((widget.block.content['source'] as String? ?? '').trim().isEmpty) {
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
    final mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 13,
      height: 1.45,
      color: dark ? OnoteColors.moon100 : OnoteColors.graphite700,
    );
    final language = widget.block.content['language'] as String? ?? 'text';
    final source = widget.block.content['source'] as String? ?? '';
    if (!editing && _controller.text != source) _controller.text = source;

    return Container(
      decoration: BoxDecoration(
        color: dark ? OnoteColors.night100 : OnoteColors.paper100,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 4, 0),
            child: Row(
              children: [
                InkWell(
                  onTap: editing ? _pickLanguage : null,
                  child: Text(language,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: OnoteColors.graphite400)),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy, size: 14),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Copy code',
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: source)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: editing
                ? TextField(
                    controller: _controller,
                    focusNode: _focus..requestFocus(),
                    maxLines: null,
                    style: mono,
                    decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '// code'),
                    onChanged: (v) {
                      if (!_undoPushed) {
                        widget.app.pushUndo();
                        _undoPushed = true;
                      }
                      widget.block.content['source'] = v;
                      widget.block.updatedAt = nowMs();
                      widget.app.markDirty();
                    },
                  )
                : Text.rich(
                    TextSpan(
                      style: mono,
                      children: source.isEmpty
                          ? [const TextSpan(text: ' ')]
                          : highlightCode(source, language, dark),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickLanguage() async {
    const langs = ['text', 'dart', 'python', 'js', 'ts', 'rust', 'c', 'cpp',
      'java', 'kotlin', 'sql', 'bash', 'json', 'yaml', 'html', 'css'];
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Language'),
        children: [
          for (final l in langs)
            SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, l), child: Text(l)),
        ],
      ),
    );
    if (choice != null) {
      widget.block.content['language'] = choice;
      widget.app.updateBlock(widget.block);
    }
  }
}
