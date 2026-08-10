import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../code/code_runner.dart';
import '../model/models.dart';
import 'wrap_selection.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'code_highlight.dart';
import '../theme/tokens.dart';
import '../ui/onote_dialog.dart';

/// Code block (CODE-1): monospace, language label, copy button, preserved
/// formatting, and dependency-free syntax highlighting (see `code_highlight`;
/// swappable for `re_highlight` later without touching this view).
/// content: { language, source, output?, ranAt? }.
///
/// `sql` and `js` cells RUN (v0.14 local code, phases 1–2): the Run button
/// (or Ctrl+Enter while editing) executes the source in a sandboxed isolate
/// — see code/code_runner.dart for the rules — and the output persists under
/// the source, so the page reads like a finished notebook without re-running
/// anything.
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
  bool _running = false;

  /// Where the last pointer went down on the read-only view — the tap that
  /// opens the editor carries it as the caret target.
  Offset? _readPressGlobal;

  bool get editing => widget.app.editingBlockId == widget.block.id;

  /// The text offset under a global point, via the editing TextField's own
  /// RenderEditable (found by walking our subtree — TextField doesn't
  /// expose it). Null while there's no laid-out field yet.
  int? _offsetAtGlobal(Offset global) {
    EditableTextState? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is EditableTextState) {
        found = e.state as EditableTextState;
        return;
      }
      e.visitChildren(visit);
    }

    final root = context as Element;
    root.visitChildren(visit);
    final r = found?.renderEditable;
    if (r == null || !r.hasSize) return null;
    return r.getPositionForPoint(global).offset;
  }

  bool get _runnable =>
      isRunnableLanguage(widget.block.content['language'] as String?);

  /// One click, one run: gather the page's table blocks, hand everything to
  /// the sandboxed runner, persist what came back. The output is part of the
  /// note (it syncs, it undoes) — that is the Jupyter property.
  Future<void> _run() async {
    if (_running) return;
    setState(() => _running = true);
    final b = widget.block;
    final app = widget.app;
    // Page tables in reading order, named by their first header cell — the
    // runner sanitises and also mounts them as t1…tn.
    final tableBlocks = [...app.blocks.where((x) => x.type == BlockType.table)]
      ..sort((a, c) => a.y != c.y ? a.y.compareTo(c.y) : a.x.compareTo(c.x));
    final tables = <CodeTable>[
      for (final t in tableBlocks)
        if (t.content['cells'] is List)
          (
            name: (() {
              final cells = t.content['cells'] as List;
              final first = cells.isNotEmpty ? cells.first : null;
              return first is List && first.isNotEmpty ? '${first.first}' : '';
            })(),
            cells: [
              for (final r in (t.content['cells'] as List))
                [for (final c in (r as List)) '$c']
            ]
          ),
    ];
    final out = await runCode(
      language: b.content['language'] as String? ?? 'text',
      source: b.content['source'] as String? ?? '',
      tables: tables,
    );
    if (!mounted) return;
    app.pushUndo();
    b.content['output'] = out.toJson();
    b.content['ranAt'] = nowMs();
    app.updateBlock(b);
    setState(() => _running = false);
  }

  void _clearOutput() {
    widget.app.pushUndo();
    widget.block.content.remove('output');
    widget.block.content.remove('ranAt');
    widget.app.updateBlock(widget.block);
  }

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
      widget.app.clearActiveEditor(widget.block.id);
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
      fontFamily: 'JetBrains Mono', fontFamilyFallback: onoteFontFallback,
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
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: OnoteColors.graphite400)),
                ),
                const Spacer(),
                if (_runnable)
                  _running
                      ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: SizedBox(
                              width: 13,
                              height: 13,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : IconButton(
                          icon: const Icon(Icons.play_arrow, size: 16),
                          visualDensity: VisualDensity.compact,
                          color: Theme.of(context).colorScheme.primary,
                          tooltip: 'Run  (Ctrl+Enter)',
                          onPressed: _run,
                        ),
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
                ? Builder(builder: (context) {
                    widget.app
                        .setActiveEditor(_controller, widget.block, 'source');
                    // Consume the click-point token the canvas set, once the
                    // field exists — the caret lands where the click did
                    // instead of wherever focus drops it ("it doesnt respect
                    // click position").
                    final want = widget.app.pendingCaretGlobal;
                    if (want != null) {
                      widget.app.pendingCaretGlobal = null;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        final at = _offsetAtGlobal(want);
                        if (at != null) {
                          _controller.selection =
                              TextSelection.collapsed(offset: at);
                        }
                      });
                    }
                    return Focus(
                      onKeyEvent: _onKey,
                      child: TextField(
                    controller: _controller,
                    focusNode: _focus..requestFocus(),
                    maxLines: null,
                    style: mono,
                    // Same wrap-on-selection as the text editor — typing (
                    // over a selected word wraps it, never replaces it.
                    // Brackets and quotes only: * is a character in code.
                    inputFormatters: const [
                      WrapSelectionFormatter(
                          pairs: WrapSelectionFormatter.bracketPairs,
                          autoCloseFences: false)
                    ],
                    decoration:
                        OnoteInput.bare.copyWith(hintText: '// code'),
                    onChanged: (v) {
                      if (!_undoPushed) {
                        widget.app.pushUndo();
                        _undoPushed = true;
                      }
                      widget.block.content['source'] = v;
                      widget.block.updatedAt = nowMs();
                      widget.app.markDirty();
                    },
                  ),
                    );
                  })
                // Selectable WITHOUT entering the editor — drag highlights,
                // Ctrl+C copies, exactly like a text block's body. A plain
                // tap still opens the editor (with the caret at the tap),
                // via onTap below; the press point is caught by the
                // Listener because SelectableText's own tap details don't
                // surface a global position.
                : Listener(
                    onPointerDown: (e) => _readPressGlobal = e.position,
                    child: SelectableText.rich(
                      TextSpan(
                        style: mono,
                        children: source.isEmpty
                            ? [const TextSpan(text: ' ')]
                            : highlightCode(source, language, dark),
                      ),
                      onTap: () {
                        widget.app.pendingCaretGlobal = _readPressGlobal;
                        widget.app.select(widget.block.id, edit: true);
                      },
                    ),
                  ),
          ),
          ..._outputPane(context, mono, dark),
        ],
      ),
    );
  }

  /// The run's result, under the source: text and errors in the same mono,
  /// rows as a real table. Persisted content, not widget state — device B
  /// reads device A's output without running anything.
  List<Widget> _outputPane(BuildContext context, TextStyle mono, bool dark) {
    final out = CodeOutput.fromJson(widget.block.content['output']);
    if (out == null) return const [];
    final headerStyle = mono.copyWith(
        fontSize: 12, fontWeight: FontWeight.w600);
    final cellStyle = mono.copyWith(fontSize: 12);
    return [
      Divider(
          height: 1,
          color: dark ? OnoteColors.night300 : OnoteColors.paper300),
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 2, 4, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Text(out.kind == 'error' ? 'error' : 'output',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: out.kind == 'error'
                          ? OnoteColors.danger
                          : OnoteColors.graphite400)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 12),
                visualDensity: VisualDensity.compact,
                tooltip: 'Clear the output',
                onPressed: _clearOutput,
              ),
            ]),
            if (out.cells != null)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Table(
                  defaultColumnWidth: const IntrinsicColumnWidth(),
                  border: TableBorder.all(
                      color:
                          dark ? OnoteColors.night300 : OnoteColors.paper300,
                      width: .5),
                  children: [
                    for (var r = 0; r < out.cells!.length; r++)
                      TableRow(children: [
                        for (final c in out.cells![r])
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            child: Text(c,
                                style: r == 0 ? headerStyle : cellStyle),
                          ),
                      ]),
                  ],
                ),
              )
            else
              SelectableText(out.text ?? '',
                  style: out.kind == 'error'
                      ? cellStyle.copyWith(color: OnoteColors.danger)
                      : cellStyle),
            if (out.truncated)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Showing the first $kMaxOutputRows rows.',
                    style: const TextStyle(
                        fontSize: 10, color: OnoteColors.graphite400)),
              ),
          ],
        ),
      ),
    ];
  }

  /// Tab inserts two spaces at the caret instead of moving focus (Tab isn't
  /// consumed by EditableText, so it bubbles here first). Ctrl+Enter runs —
  /// Jupyter's muscle memory.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyDownEvent &&
        e.logicalKey == LogicalKeyboardKey.enter &&
        HardwareKeyboard.instance.isControlPressed &&
        _runnable) {
      _run();
      return KeyEventResult.handled;
    }
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.tab) {
      final sel = _controller.selection;
      if (!sel.isValid) return KeyEventResult.ignored;
      final at = sel.start;
      _controller.text = _controller.text.replaceRange(sel.start, sel.end, '  ');
      _controller.selection = TextSelection.collapsed(offset: at + 2);
      widget.block.content['source'] = _controller.text;
      widget.block.updatedAt = nowMs();
      widget.app.markDirty();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _pickLanguage() async {
    const langs = ['text', 'dart', 'python', 'js', 'ts', 'rust', 'c', 'cpp',
      'java', 'kotlin', 'sql', 'bash', 'json', 'yaml', 'html', 'css'];
    final choice = await showOnoteDialog<String>(
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
