import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../code/code_runner.dart';
import '../model/models.dart';
import 'code_languages.dart';
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
/// anything. The picker groups those two under "Runs on this device" and
/// badges them, so what will execute is visible before anything is typed.
///
/// The field types like an IDE — pairs close, Tab indents, Enter keeps the
/// indent and pushes `}` down a line — and the language names itself from
/// the source unless somebody chose one. All of that is
/// `editor/code_languages.dart`; this file only wires it up.
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

  CodeLanguage get _language =>
      languageFor(widget.block.content['language'] as String?);

  bool get _runnable => _language.runnable;

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
      // The resolved id, not the raw one: a block imported as ```javascript
      // or ```node shows a Run button, so it has to reach a runner too.
      language: _language.id,
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
    // Same reason as text_block_view: a page or notebook switch replaces this
    // element outright, so `_handleExitTransition` never runs and nothing else
    // tells AppState the controller it holds is about to be disposed.
    widget.app.releaseEditor(_controller);
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
    final lang = _language;
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
                  borderRadius: BorderRadius.circular(4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // The display name, not the id: a student reads "C++",
                      // never "cpp".
                      Text(lang.name,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: OnoteColors.graphite400)),
                      // Only while editing, because only then is it a button.
                      if (editing)
                        const Icon(Icons.arrow_drop_down,
                            size: 14, color: OnoteColors.graphite400),
                    ],
                  ),
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
                    // Two halves of one behaviour: with a selection, typing (
                    // WRAPS it (same formatter as every other field); with
                    // none, CodeTypingFormatter pairs, steps over a closer
                    // and indents after Enter. Order matters — the wrap
                    // formatter runs first and the pairing one then sees a
                    // selection it must keep its hands off.
                    inputFormatters: [
                      const WrapSelectionFormatter(
                          pairs: WrapSelectionFormatter.bracketPairs,
                          autoCloseFences: false),
                      CodeTypingFormatter(lang),
                    ],
                    decoration: OnoteInput.bare.copyWith(
                        hintText: lang.lineComment.isEmpty
                            ? 'code'
                            : '${lang.lineComment} code'),
                    onChanged: (v) {
                      if (!_undoPushed) {
                        widget.app.pushUndo();
                        _undoPushed = true;
                      }
                      final was =
                          widget.block.content['source'] as String? ?? '';
                      widget.block.content['source'] = v;
                      _autoDetect(was, v);
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
                            : highlightCode(source, lang.id, dark),
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
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Showing the first $kMaxOutputRows rows.',
                    style: TextStyle(
                        fontSize: 10, color: OnoteColors.graphite400)),
              ),
          ],
        ),
      ),
    ];
  }

  /// Write an edit the keyboard made, as one undo step and one save.
  ///
  /// The old Tab handler set `_controller.text` and then `.selection`, which
  /// is two notifications and a caret that lands at the end in between — and
  /// it never pushed undo, so tabbed-in indentation could not be undone.
  void _apply(TextEditingValue v) {
    if (!_undoPushed) {
      widget.app.pushUndo();
      _undoPushed = true;
    }
    _controller.value = v;
    widget.block.content['source'] = v.text;
    widget.block.updatedAt = nowMs();
    widget.app.markDirty();
  }

  /// Name the language from the source, unless somebody already named it.
  void _autoDetect(String was, String now) {
    final c = widget.block.content;
    final found = autoLanguageFor(
      current: c['language'] as String?,
      userPicked: c['languagePicked'] == true,
      autoSet: c['languageAuto'] == true,
      previousSource: was,
      source: now,
    );
    if (found == null) return;
    setState(() {
      c['language'] = found;
      // Remembered so a later paste may revise this guess, while a language
      // that came in with the content is left alone.
      c['languageAuto'] = true;
    });
  }

  /// Tab indents instead of moving focus (Tab isn't consumed by EditableText,
  /// so it bubbles here first), Shift+Tab outdents, and a selection spanning
  /// lines moves all of them. Ctrl+Enter runs — Jupyter's muscle memory.
  ///
  /// Pairing and Enter are NOT here: they arrive through the text input
  /// service, so they are input formatters (see code_languages.dart).
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyDownEvent &&
        e.logicalKey == LogicalKeyboardKey.enter &&
        HardwareKeyboard.instance.isControlPressed &&
        _runnable) {
      _run();
      return KeyEventResult.handled;
    }
    if ((e is KeyDownEvent || e is KeyRepeatEvent) &&
        e.logicalKey == LogicalKeyboardKey.tab) {
      final next = handleCodeTab(_controller.value, _language,
          outdent: HardwareKeyboard.instance.isShiftPressed);
      // Handled either way: Shift+Tab at column 0 does nothing, and doing
      // nothing must not mean "leave the code cell".
      if (next != null) _apply(next);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _pickLanguage() async {
    final current = _language.id;
    final choice = await showOnoteDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Language'),
        children: [
          for (final group in codeLanguageMenu) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 2),
              child: Text(group.title,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: OnoteColors.graphite400)),
            ),
            // Indented under their heading, so C, C++ and C# read as one
            // family rather than three unrelated rows.
            for (final l in group.languages)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, l.id),
                padding: const EdgeInsets.fromLTRB(36, 8, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(l.name,
                          style: TextStyle(
                              fontWeight: l.id == current
                                  ? FontWeight.w700
                                  : FontWeight.w400)),
                    ),
                    if (l.runnable) _runsHereBadge(context),
                    if (l.id == current)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.check, size: 16),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
    if (choice == null || choice == current) return;
    widget.app.pushUndo();
    widget.block.content['language'] = choice;
    // A pick is a decision: detection never second-guesses it again, and
    // picking again is the whole of "undoing" a detection.
    widget.block.content['languagePicked'] = true;
    widget.block.content.remove('languageAuto');
    widget.app.updateBlock(widget.block);
  }

  /// The mark on the languages that actually execute here. Plain words and
  /// the same play arrow as the Run button, so the promise the menu makes is
  /// the button the block will grow.
  Widget _runsHereBadge(BuildContext context) {
    final c = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 1, 7, 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.play_arrow, size: 11, color: c),
        Text('Run',
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: c)),
      ]),
    );
  }
}
