/// Maths pasted into a paragraph arrives as maths.
///
/// **Why a formatter and not a key handler.** The shell's Ctrl+V branch cannot
/// decide this: reading the clipboard is a `Future`, so by the time the answer
/// arrives the field has already inserted the raw text — and inserting the
/// wrapped form as well pasted the equation TWICE. Intercepting where the text
/// actually lands is synchronous, and it covers drag-and-drop and middle-click
/// paste for free.
///
/// The same seam `WrapSelectionFormatter` already uses.
library;

import 'package:flutter/services.dart';

import '../math/math_view.dart';

class MathPasteFormatter extends TextInputFormatter {
  const MathPasteFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Only a PASTE-shaped edit: one contiguous run, longer than a keystroke,
    // replacing the old selection. Typing must never go near this.
    final inserted = _insertedRun(oldValue, newValue);
    if (inserted == null || inserted.text.length < 2) return newValue;
    if (!MathClipboard.looksLikeMaths(inserted.text)) return newValue;

    final wrapped =
        MathClipboard.wrapInline(MathClipboard.unwrap(inserted.text));
    if (wrapped.isEmpty || wrapped == inserted.text) return newValue;

    final text = newValue.text
        .replaceRange(inserted.start, inserted.start + inserted.text.length,
            wrapped);
    return TextEditingValue(
      text: text,
      selection:
          TextSelection.collapsed(offset: inserted.start + wrapped.length),
      composing: TextRange.empty,
    );
  }

  /// The single run of text this edit added, or null when the edit was
  /// something else (a deletion, a replacement in two places, a no-op).
  ({int start, String text})? _insertedRun(
      TextEditingValue oldV, TextEditingValue newV) {
    final removed = oldV.selection.isValid && !oldV.selection.isCollapsed
        ? oldV.selection.end - oldV.selection.start
        : 0;
    final grew = newV.text.length - (oldV.text.length - removed);
    if (grew <= 0) return null;
    final start = newV.selection.isValid ? newV.selection.end - grew : -1;
    if (start < 0 || start + grew > newV.text.length) return null;
    return (start: start, text: newV.text.substring(start, start + grew));
  }
}
