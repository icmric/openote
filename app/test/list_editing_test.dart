// The list engine: the keystrokes every note-taker has muscle memory for.
//
// Pure (text, selection) → (text, selection), so the behaviour is pinned here
// without a widget, a canvas or a notebook. Before this existed, Enter did not
// continue a bullet, Tab left the text box entirely, and `* item` was a list
// to the editor and plain text to the renderer.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/list_editing.dart';

/// `text` with `|` marking the caret (and `«`…`»` a selection), so the cases
/// below read like what the user actually does. Guillemets, not brackets:
/// brackets are checkbox syntax and half these cases are checkboxes.
TextEditingValue at(String spec) {
  final base = spec.indexOf('«');
  if (base >= 0) {
    final ext = spec.indexOf('»');
    final text = spec.replaceAll('«', '').replaceAll('»', '');
    return TextEditingValue(
        text: text,
        selection: TextSelection(baseOffset: base, extentOffset: ext - 1));
  }
  final i = spec.indexOf('|');
  return TextEditingValue(
    text: spec.replaceFirst('|', ''),
    selection: TextSelection.collapsed(offset: i),
  );
}

String show(TextEditingValue v) =>
    v.text.replaceRange(v.selection.start, v.selection.start, '|');

void main() {
  group('parsing — one definition of a list line', () {
    test('accepts every marker people actually type', () {
      for (final m in ['-', '*', '+']) {
        final p = parseListLine('$m item');
        expect(p, isNotNull, reason: '"$m item" must be a bullet');
        expect(p!.kind, ListKind.bullet);
        expect(p.body, 'item');
      }
    });

    test('numbered, both delimiters', () {
      expect(parseListLine('1. one')?.kind, ListKind.numbered);
      expect(parseListLine('2) two')?.kind, ListKind.numbered);
      expect(parseListLine('12. twelve')?.number, 12);
    });

    test('a checkbox is a checkbox, not a bullet whose body is "[ ]"', () {
      final p = parseListLine('- [ ] task');
      expect(p?.kind, ListKind.checkbox);
      expect(p?.body, 'task');
      expect(p?.checked, isFalse);
      expect(parseListLine('- [x] done')?.checked, isTrue);
    });

    test('a divider is not a list item', () {
      expect(parseListLine('---'), isNull);
      expect(parseListLine('***'), isNull);
      expect(parseListLine('- - -'), isNull);
    });

    test('plain prose is not a list item', () {
      expect(parseListLine('just words'), isNull);
      expect(parseListLine('3.14 is pi'), isNull, reason: 'needs a space');
      expect(parseListLine(''), isNull);
    });

    test('tabs nest the same as two spaces', () {
      expect(parseListLine('\t- x')?.indentWidth, kListIndentSpaces);
      expect(parseListLine('  - x')?.indentWidth, kListIndentSpaces);
      expect(parseListLine('    - x')?.level, 2);
    });

    test('prefix + body reassembles the source exactly', () {
      for (final line in ['- a', '  * b', '3) c', '\t- [x] d', '10. e']) {
        final p = parseListLine(line)!;
        expect('${p.prefix}${p.body}', line);
        expect(p.bodyStart, p.prefix.length);
      }
    });
  });

  group('Enter continues the list', () {
    test('a bullet begets the next bullet', () {
      final r = handleListEnter(at('- milk|'))!;
      expect(r.text, '- milk\n- ');
      expect(r.selection.start, r.text.length);
    });

    test('it continues with the marker you used, not a decreed one', () {
      expect(handleListEnter(at('* milk|'))!.text, '* milk\n* ');
      expect(handleListEnter(at('+ milk|'))!.text, '+ milk\n+ ');
    });

    test('numbered items count on', () {
      expect(handleListEnter(at('1. one|'))!.text, '1. one\n2. ');
      expect(handleListEnter(at('3) three|'))!.text, '3) three\n4) ');
    });

    test('a new task starts unticked, even from a ticked one', () {
      expect(handleListEnter(at('- [x] done|'))!.text, '- [x] done\n- [ ] ');
    });

    test('indentation is inherited', () {
      expect(handleListEnter(at('    - deep|'))!.text, '    - deep\n    - ');
    });

    test('Enter mid-item splits it and both halves keep a marker', () {
      final r = handleListEnter(at('- hel|lo'))!;
      expect(r.text, '- hel\n- lo');
    });

    test('an empty item at the left margin ends the list', () {
      final r = handleListEnter(at('- one\n- |'))!;
      expect(r.text, '- one\n');
      expect(r.selection.start, '- one\n'.length);
    });

    test('an empty NESTED item walks back out one level at a time', () {
      var v = at('- a\n    - |');
      v = handleListEnter(v)!;
      expect(v.text, '- a\n  - ');
      v = handleListEnter(v)!;
      expect(v.text, '- a\n- ');
      v = handleListEnter(v)!;
      expect(v.text, '- a\n', reason: 'and finally leaves the list');
    });

    test('plain prose is left alone — the field keeps its own newline', () {
      expect(handleListEnter(at('just words|')), isNull);
      expect(handleListEnter(at('|')), isNull);
    });

    test('Shift+Enter stays inside the item, at the item\'s own level', () {
      // NOT padded to the body offset: leading spaces are a NESTING encoding
      // (two spaces = one level), so padding `- [ ] ` to six characters
      // declared three levels and threw the continuation 87px right of the
      // words it belongs to. True alignment under the body needs a hanging
      // indent, which spaces cannot express.
      expect(handleListShiftEnter(at('- first|'))!.text, '- first\n');
      expect(handleListShiftEnter(at('  - deep|'))!.text, '  - deep\n  ');
      expect(handleListShiftEnter(at('- [ ] task|'))!.text, '- [ ] task\n');
    });
  });

  group('Tab nests, Shift+Tab un-nests', () {
    test('a second item may become a child of the first', () {
      final r = handleListTab(at('- a\n- b|'), outdent: false)!;
      expect(r.text, '- a\n  - b');
      expect(show(r), '- a\n  - b|');
    });

    test('the FIRST item of a list cannot be indented — it has no parent', () {
      expect(handleListTab(at('- only|'), outdent: false), isNull);
    });

    test('Shift+Tab pulls an item back out', () {
      final r = handleListTab(at('- a\n  - b|'), outdent: true)!;
      expect(r.text, '- a\n- b');
    });

    test('Shift+Tab at the left margin does nothing rather than misfire', () {
      expect(handleListTab(at('- a|'), outdent: true), isNull);
    });

    test('indenting a run of items moves all of them', () {
      final r = handleListTab(at('- a\n«- b\n- c»'), outdent: false)!;
      expect(r.text, '- a\n  - b\n  - c');
    });

    test('numbering is repaired after a nest — the child restarts at 1', () {
      final r = handleListTab(at('1. a\n2. b|'), outdent: false)!;
      expect(r.text, '1. a\n  1. b');
    });
  });

  group('Backspace at the start of an item', () {
    test('unwraps it, keeping the words and the line', () {
      final r = handleListBackspace(at('- |hello'))!;
      expect(r.text, 'hello');
      expect(r.selection.start, 0);
    });

    test('a nested item outdents first instead of losing its marker', () {
      final r = handleListBackspace(at('- a\n    - |b'))!;
      expect(r.text, '- a\n  - b');
    });

    test('mid-word it is an ordinary backspace', () {
      expect(handleListBackspace(at('- hel|lo')), isNull);
    });

    test('a checkbox unwraps whole, not one bracket at a time', () {
      expect(handleListBackspace(at('- [ ] |task'))!.text, 'task');
    });
  });

  group('ordered lists renumber themselves', () {
    test('the toolbar\'s "1. " on every line becomes 1, 2, 3', () {
      expect(renumberOrderedLists('1. a\n1. b\n1. c'), '1. a\n2. b\n3. c');
    });

    test('deleting an item closes the gap', () {
      expect(renumberOrderedLists('1. a\n3. c'), '1. a\n2. c');
    });

    test('each nesting level counts on its own', () {
      expect(
        renumberOrderedLists('1. a\n  1. x\n  5. y\n9. b'),
        '1. a\n  1. x\n  2. y\n2. b',
      );
    });

    test('a blank line starts a new list, which keeps its own start number',
        () {
      expect(renumberOrderedLists('1. a\n2. b\n\n7. new\n7. next'),
          '1. a\n2. b\n\n7. new\n8. next');
    });

    test('bullets and prose are untouched', () {
      const t = '- a\n- b\ntext\n- [ ] c';
      expect(renumberOrderedLists(t), t);
    });

    test('the delimiter the user chose survives', () {
      expect(renumberOrderedLists('1) a\n1) b'), '1) a\n2) b');
    });
  });

  group('the toolbar list buttons', () {
    test('turn prose into a list without eating the indentation', () {
      final r = toggleListOverSelection(at('  indented|'), ListKind.bullet);
      expect(r.text, '  - indented',
          reason: 'not "-   indented" — the old prefix-paste bug');
    });

    test('pressing the same button again removes the markers', () {
      final r = toggleListOverSelection(at('- a|'), ListKind.bullet);
      expect(r.text, 'a');
    });

    test('bullet → task swaps the marker instead of stacking one', () {
      final r = toggleListOverSelection(at('- a|'), ListKind.checkbox);
      expect(r.text, '- [ ] a');
    });

    test('a task is not destroyed by the bullet button', () {
      final r = toggleListOverSelection(at('- [x] a|'), ListKind.bullet);
      expect(r.text, '- a', reason: 'becomes a plain bullet, not "- - [x] a"');
    });

    test('a mixed selection becomes uniform on the first press', () {
      final r = toggleListOverSelection(at('«- a\nplain»'), ListKind.bullet);
      expect(r.text, '- a\n- plain');
    });

    test('numbered lists arrive already counting', () {
      final r = toggleListOverSelection(at('«a\nb\nc»'), ListKind.numbered);
      expect(r.text, '1. a\n2. b\n3. c');
    });

    test('blank lines in the selection stay blank', () {
      final r = toggleListOverSelection(at('«a\n\nb»'), ListKind.bullet);
      expect(r.text, '- a\n\n- b');
    });
  });

  group('checkboxes', () {
    test('tick and untick by offset', () {
      final v = at('- [ ] task|');
      final ticked = toggleCheckboxAt(v, 2)!;
      expect(ticked.text, '- [x] task');
      expect(toggleCheckboxAt(ticked, 2)!.text, '- [ ] task');
    });

    test('a non-checkbox line says so', () {
      expect(toggleCheckboxAt(at('- plain|'), 2), isNull);
    });
  });

  // Each of these is a defect an adversarial review found and confirmed
  // against the first cut of this engine.
  group('selections that are not left-to-right, and edges', () {
    test('a BACKWARDS selection keeps its direction and its characters', () {
      final v = TextEditingValue(
        text: 'a\nb',
        // Dragged right-to-left, or Shift+Up: base is the LATER offset.
        selection: const TextSelection(baseOffset: 3, extentOffset: 0),
      );
      final r = toggleListOverSelection(v, ListKind.bullet);
      expect(r.text, '- a\n- b');
      expect(r.selection.baseOffset, greaterThan(r.selection.extentOffset),
          reason: 'the drag direction must survive');
      expect(r.text.substring(r.selection.start, r.selection.end),
          '- a\n- b');
    });

    test('Tab with a backwards selection indents both lines', () {
      final v = TextEditingValue(
        text: '- a\n- b',
        selection: const TextSelection(baseOffset: 6, extentOffset: 2),
      );
      final r = handleListTab(v, outdent: false)!;
      expect(r.text, '  - a\n  - b');
    });

    test('a selection ending AT a line start does not drag that line in', () {
      // Exactly what Shift+Down and a triple-click produce.
      final v = TextEditingValue(
        text: '- a\n- b',
        selection: const TextSelection(baseOffset: 0, extentOffset: 4),
      );
      // Only line 1 is selected, and it is the first item — nothing to nest
      // under, so nothing should move.
      expect(handleListTab(v, outdent: false), isNull);
    });
  });

  group('a multi-line item does not break the numbering below it', () {
    test('an indented continuation line belongs to its item', () {
      expect(
        renumberOrderedLists('1. a\n1. b\n   note\n1. c\n1. d'),
        '1. a\n2. b\n   note\n3. c\n4. d',
        reason: 'the continuation line used to reset the run to 1',
      );
    });

    test('a Shift+Enter second line keeps the count going', () {
      expect(renumberOrderedLists('1. alpha\n   note\n1. beta'),
          '1. alpha\n   note\n2. beta');
    });

    test('but a blank line still ends the list', () {
      expect(renumberOrderedLists('1. a\n\n1. b'), '1. a\n\n1. b');
    });

    test('and unindented prose still ends it', () {
      expect(renumberOrderedLists('1. a\nprose\n1. b'), '1. a\nprose\n1. b');
    });
  });

  group('the caret never gets lost', () {
    test('renumbering carries the caret with its words', () {
      final v = TextEditingValue(
        text: '1. a\n1. bcd',
        selection: const TextSelection.collapsed(offset: 10), // after 'bc'
      );
      final r = renumberValue(v);
      expect(r.text, '1. a\n2. bcd');
      expect(r.text.substring(0, r.selection.start), '1. a\n2. bc');
    });

    test('a digit-width change still lands the caret on the same character',
        () {
      final v = TextEditingValue(
        text: '${List.generate(9, (i) => '${i + 1}. item').join('\n')}\n1. tenth',
        selection: const TextSelection.collapsed(offset: 0),
      );
      final r = renumberValue(v);
      expect(r.text.endsWith('10. tenth'), isTrue);
    });
  });
}
