import 'package:flutter/services.dart';

/// Wraps the current selection with a matching pair when a wrapping character
/// is typed over a non-empty selection — VS Code style. `foo` + `(` → `(foo)`
/// with `foo` re-selected, instead of replacing the text.
///
/// One formatter for EVERY content editor, parameterised rather than copied:
/// "when highlighting a word and pressing ( or \" it doesn't wrap the word
/// like it does elsewhere, it replaces it" — the behaviour existed only in
/// the markdown editor, and each other field had quietly kept the platform
/// default. The pair set differs by surface on purpose: markdown gets its
/// own emphasis characters, while a code cell wrapping `x` in `*` would be
/// inventing syntax; the fence auto-close is markdown-only for the same
/// reason.
class WrapSelectionFormatter extends TextInputFormatter {
  const WrapSelectionFormatter(
      {this.pairs = markdownPairs, this.autoCloseFences = true});

  /// The markdown editor's full set: brackets, quotes, and the emphasis
  /// characters that mean "wrap" there.
  static const markdownPairs = {
    '(': ')',
    '[': ']',
    '{': '}',
    '"': '"',
    "'": "'",
    '`': '`',
    '*': '*',
    '_': '_',
    '~': '~',
    '=': '=',
    '<': '>',
  };

  /// Brackets and quotes only — code cells, table cells, board cards, math,
  /// titles: everywhere `*` is a character, not a command.
  static const bracketPairs = {
    '(': ')',
    '[': ']',
    '{': '}',
    '"': '"',
    "'": "'",
    '`': '`',
  };

  final Map<String, String> pairs;
  final bool autoCloseFences;

  /// A line that is exactly an opening fence, so Enter should close it.
  static final _openFenceRe = RegExp(r'^\s*```[A-Za-z0-9+#-]*$');

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (autoCloseFences) {
      final fenced = _autoCloseFence(oldValue, newValue);
      if (fenced != null) return fenced;
    }

    final sel = oldValue.selection;
    if (!sel.isValid || sel.isCollapsed) return newValue;
    final selText = oldValue.text.substring(sel.start, sel.end);
    final tailLen = oldValue.text.length - sel.end;
    // The new text must be old-with-selection-replaced-by-one-char.
    if (newValue.text.length != oldValue.text.length - selText.length + 1) {
      return newValue;
    }
    final insertedEnd = newValue.text.length - tailLen;
    if (insertedEnd <= sel.start || insertedEnd > newValue.text.length) {
      return newValue;
    }
    final inserted = newValue.text.substring(sel.start, insertedEnd);
    final close = pairs[inserted];
    if (inserted.length != 1 || close == null) return newValue;

    final wrapped =
        oldValue.text.replaceRange(sel.start, sel.end, '$inserted$selText$close');
    return TextEditingValue(
      text: wrapped,
      selection: TextSelection(
          baseOffset: sel.start + 1, extentOffset: sel.start + 1 + selText.length),
    );
  }

  /// Pressing Enter on a bare ``` line opens a fence: insert the closing line
  /// and leave the caret between them (TEXT-2).
  ///
  /// Without this, typing a code fence means typing the closing ``` yourself
  /// and remembering to sit above it — the one Markdown construct where the
  /// editor asking "did you mean a code block?" is unambiguously right.
  TextEditingValue? _autoCloseFence(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final sel = oldValue.selection;
    if (!sel.isValid || !sel.isCollapsed) return null;
    // Exactly one newline inserted at the caret.
    if (newValue.text.length != oldValue.text.length + 1) return null;
    final at = sel.baseOffset;
    if (at < 0 || at > oldValue.text.length) return null;
    if (newValue.text.length <= at || newValue.text[at] != '\n') return null;

    final lineStart = oldValue.text.lastIndexOf('\n', at - 1) + 1;
    final line = oldValue.text.substring(lineStart, at);
    if (!_openFenceRe.hasMatch(line)) return null;
    // Already inside a fence (odd number of fence lines above)? Then this line
    // is a CLOSING fence and must not spawn another.
    final before = oldValue.text.substring(0, lineStart);
    final fencesAbove =
        '\n$before'.split('\n').where((l) => l.trimLeft().startsWith('```')).length;
    if (fencesAbove.isOdd) return null;

    final indent = RegExp(r'^\s*').firstMatch(line)!.group(0)!;
    final insert = '\n$indent```';
    final text = oldValue.text.replaceRange(at, at, '\n$insert');
    return TextEditingValue(
      text: text,
      // Caret on the blank line between the fences.
      selection: TextSelection.collapsed(offset: at + 1),
    );
  }
}
