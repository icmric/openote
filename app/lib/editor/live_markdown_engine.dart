import 'package:flutter/material.dart';

import '../markdown/md_render.dart';
import '../model/models.dart';
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
      );

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

class _LiveMarkdownSession implements OnoteEditSession {
  _LiveMarkdownSession({required this.controller, required this.onChanged});

  final LiveMarkdownController controller;
  final ValueChanged<String> onChanged;
  final FocusNode _focus = FocusNode();

  @override
  TextEditingController? get commandController => controller;

  @override
  String get text => controller.text;

  @override
  set text(String value) {
    if (controller.text != value) controller.text = value;
  }

  @override
  Widget build(BuildContext context, TextSurface s) {
    controller.dark = s.dark;
    // Focus is claimed post-frame: the host decides *that* a block is being
    // edited, but the field only exists after this build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_focus.context != null && !_focus.hasFocus) _focus.requestFocus();
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
          onChanged: onChanged,
        ),
      ),
    );
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
    controller.dispose();
    _focus.dispose();
  }
}
