import 'dart:async';

import 'package:flutter/material.dart';

import '../markdown/md_render.dart';
import '../model/models.dart';
import '../model/tags.dart';
import '../spell/spell_checker.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
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
        controller: LiveMarkdownController(
            text: deserialize(block.content), dark: false),
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
  _LiveMarkdownSession({required this.controller, required this.onChanged});

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
        }
      }
      if (!_focus.hasFocus) _focus.requestFocus();
    });
    return Padding(
      padding: s.inset,
      child: Focus(
        // Alt+X is intercepted above the field so it runs before the character
        // would be typed. Returning `ignored` when no rule applies keeps the
        // chord available to anything else rather than swallowing it.
        onKeyEvent: (_, event) =>
            isAltXChord(event) && _applyAltX() ? KeyEventResult.handled : KeyEventResult.ignored,
        child: TextField(
          controller: controller,
          focusNode: _focus,
          maxLines: null,
          style: s.baseStyle,
          cursorColor: Theme.of(context).colorScheme.primary,
          inputFormatters: [WrapSelectionFormatter()],
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            hintText: s.hintText,
            hintStyle:
                const TextStyle(color: OnoteColors.graphite400, fontSize: 13),
          ),
          // Spell suggestions on right-click. Flutter's own spell-check menu
          // is unreachable here (see spell/spell_checker.dart for why), so the
          // corrections are spliced into the standard adaptive menu instead of
          // replacing it — cut/copy/paste must keep working.
          contextMenuBuilder: (context, editable) {
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
          },
        ),
      ),
    );
  }

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
    _spellDebounce?.cancel();
    controller.dispose();
    _focus.dispose();
  }
}
