// One wrap-on-selection behaviour for every content field.
//
// "When highlighting a word and pressing ( or \" it doesn't wrap the word
// like it does elsewhere, it replaces it" — the behaviour lived only in the
// markdown editor; the formatter is now parameterised and installed on code
// cells, table cells, board cards, flashcard fields, the math field and the
// page title. These tests pin the formatter itself; which fields carry it
// is grep-able (`inputFormatters` + WrapSelectionFormatter).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/wrap_selection.dart';

TextEditingValue _typeOverSelection(
    WrapSelectionFormatter f, String text, int start, int end, String typed) {
  final oldValue = TextEditingValue(
    text: text,
    selection: TextSelection(baseOffset: start, extentOffset: end),
  );
  final newValue = TextEditingValue(
    text: text.replaceRange(start, end, typed),
    selection: TextSelection.collapsed(offset: start + typed.length),
  );
  return f.formatEditUpdate(oldValue, newValue);
}

void main() {
  const brackets = WrapSelectionFormatter(
      pairs: WrapSelectionFormatter.bracketPairs, autoCloseFences: false);

  test('typing ( over a selected word wraps it and keeps it selected', () {
    final r = _typeOverSelection(brackets, 'see foo here', 4, 7, '(');
    expect(r.text, 'see (foo) here');
    expect(r.selection.baseOffset, 5);
    expect(r.selection.extentOffset, 8,
        reason: 'the word stays selected, VS Code style');
  });

  test('quotes and backticks wrap with themselves', () {
    expect(_typeOverSelection(brackets, 'a word b', 2, 6, '"').text,
        'a "word" b');
    expect(_typeOverSelection(brackets, 'a word b', 2, 6, '`').text,
        'a `word` b');
  });

  test('a non-pair character still REPLACES the selection', () {
    final r = _typeOverSelection(brackets, 'a word b', 2, 6, 'x');
    expect(r.text, 'a x b', reason: 'wrapping is only for wrapping chars');
  });

  test('the bracket set does not treat * as a wrapper — code is not markdown',
      () {
    final r = _typeOverSelection(brackets, 'a * b_c', 4, 5, '*');
    expect(r.text, 'a * * _c'.replaceAll(' * * ', ' * *'),
        reason: 'selecting b and typing * in code means the character');
    // Plainly: the selection was replaced, not wrapped.
    expect(r.text.contains('*b*'), isFalse);
  });

  test('the markdown set DOES wrap on *', () {
    const md = WrapSelectionFormatter();
    final r = _typeOverSelection(md, 'a word b', 2, 6, '*');
    expect(r.text, 'a *word* b');
  });

  test('fences stay off where they are turned off', () {
    const oldValue = TextEditingValue(
      text: '```',
      selection: TextSelection.collapsed(offset: 3),
    );
    const typedEnter = TextEditingValue(
      text: '```\n',
      selection: TextSelection.collapsed(offset: 4),
    );
    expect(brackets.formatEditUpdate(oldValue, typedEnter).text, '```\n',
        reason: 'a code cell must not spawn markdown fences');
    expect(
        const WrapSelectionFormatter()
            .formatEditUpdate(oldValue, typedEnter)
            .text,
        '```\n\n```',
        reason: 'the markdown editor still does');
  });
}
