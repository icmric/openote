// A space at the edge of a styled run must never expose its markers.
//
// The owner: *"if i bold (or otherwise style) some text then press space at
// the end, it breaks the interpreter and shows the `**` … It should never
// under any circumstances show the md styling chars after the style has been
// applied."*
//
// These are unit tests on the rule itself rather than widget tests on a field,
// because the rule is a pure function of two `TextEditingValue`s and that is
// the honest size of it.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/emphasis_guard.dart';
import 'package:openote/markdown/md_syntax.dart';

/// The value a field holds with [text] and the caret at [at].
TextEditingValue at(String text, int offset) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );

/// [what] typed at the caret of [before], as the field would report it before
/// any formatter has had a look.
TextEditingValue typed(TextEditingValue before, String what) {
  final o = before.selection.baseOffset;
  return at(before.text.replaceRange(o, o, what), o + what.length);
}

/// Does [text] still read as styled markup — i.e. is there a run covering
/// [probe] whose markers a renderer would hide?
bool stillStyled(String text, int probe) {
  for (final m in mdInlineRe.allMatches(text)) {
    final c = classifyInline(m);
    if (c.openLen == 0) continue;
    if (probe >= m.start && probe < m.end) return true;
  }
  return false;
}

void main() {
  group('a space at the closing edge goes outside the run', () {
    test('the reported one: bold, then space', () {
      // Where `applyPendingMarks` leaves the caret on purpose — INSIDE the
      // closing markers, so the next keystroke extends the run.
      final before = at('**bold**', 6);
      final raw = typed(before, ' ');

      expect(raw.text, '**bold **',
          reason: 'what the field would hold without this rule, and it is no '
              'longer a bold run at all — the flanking guard forbids a marker '
              'against a space, so a renderer prints the asterisks');
      expect(stillStyled(raw.text, 2), isFalse,
          reason: 'which is exactly the report: the markup became visible');

      final fixed = relocateEdgeWhitespace(before, raw);
      expect(fixed, isNotNull);
      expect(fixed!.text, '**bold** ');
      expect(fixed.selection.baseOffset, 9,
          reason: 'the caret follows the space it just typed, outside the run');
      expect(stillStyled(fixed.text, 2), isTrue,
          reason: 'and the word is still bold');
    });

    test('every form that carries a flanking guard', () {
      // These are the asterisk and underscore emphasis forms, and they are
      // the only ones that can break this way.
      for (final (src, caret, want) in const [
        ('*hi*', 3, '*hi* '),
        ('***hi***', 5, '***hi*** '),
        ('__hi__', 4, '__hi__ '),
        ('_hi_', 3, '_hi_ '),
      ]) {
        final before = at(src, caret);
        final fixed = relocateEdgeWhitespace(before, typed(before, ' '));
        expect(fixed?.text, want, reason: 'for $src');
        expect(stillStyled(fixed!.text, 1), isTrue, reason: 'for $src');
      }
    });

    test('and the forms that do not are left exactly alone', () {
      // `~~`, `==` and `++` have no flanking guard in the grammar, so
      // `~~hi ~~` is still a strikethrough run and the markers stay hidden.
      // Moving the space would be rewriting what somebody typed for no gain.
      // Asserted so that the day one of these GAINS a guard, this test is the
      // thing that notices.
      for (final (src, caret) in const [
        ('~~hi~~', 4),
        ('==hi==', 4),
        ('++hi++', 4),
      ]) {
        final before = at(src, caret);
        final raw = typed(before, ' ');
        expect(relocateEdgeWhitespace(before, raw), isNull, reason: 'for $src');
        expect(stillStyled(raw.text, 1), isTrue,
            reason: 'for $src — which is WHY nothing is moved');
      }
    });

    test('a run in the middle of a sentence keeps the rest of it', () {
      final before = at('see **this** ok', 10);
      final fixed = relocateEdgeWhitespace(before, typed(before, ' '));
      expect(fixed?.text, 'see **this**  ok');
      expect(fixed?.selection.baseOffset, 13);
    });

    test('a nested run, which the top-level walk never sees', () {
      // `mdInlineRe.allMatches` is non-overlapping, so `**a *b* c**` is ONE
      // match and the italic's edge is invisible at that level.
      final before = at('**a *b* c**', 6);
      final fixed = relocateEdgeWhitespace(before, typed(before, ' '));
      expect(fixed?.text, '**a *b*  c**',
          reason: 'the space lands outside the italic and inside the bold, '
              'which is where it was typed');
    });
  });

  group('a space at the opening edge goes outside it too', () {
    test('bold', () {
      final before = at('**bold**', 2);
      final fixed = relocateEdgeWhitespace(before, typed(before, ' '));
      expect(fixed?.text, ' **bold**');
      expect(fixed?.selection.baseOffset, 1);
      expect(stillStyled(fixed!.text, 3), isTrue);
    });
  });

  group('and it keeps its hands off everything else', () {
    test('a space in the middle of a run is just a space', () {
      final before = at('**two words**', 5);
      expect(relocateEdgeWhitespace(before, typed(before, ' ')), isNull);
    });

    test('a space outside a run is just a space', () {
      final before = at('**bold** here', 9);
      expect(relocateEdgeWhitespace(before, typed(before, ' ')), isNull);
    });

    test('a code span has no flanking rule, so nothing is moved', () {
      // `` `a ` `` is legal and means something. Moving the space would
      // rewrite what the student typed.
      final before = at('`code`', 5);
      expect(relocateEdgeWhitespace(before, typed(before, ' ')), isNull,
          reason: 'the rule asks whether the run actually breaks rather than '
              'assuming every marker carries a flanking guard');
    });

    test('a letter at the same edge is left where it was typed', () {
      final before = at('**bold**', 6);
      expect(relocateEdgeWhitespace(before, typed(before, 'x')), isNull,
          reason: 'extending the run is the whole point of parking the caret '
              'there');
    });

    test('plain text with no markup at all', () {
      final before = at('just a sentence', 4);
      expect(relocateEdgeWhitespace(before, typed(before, ' ')), isNull);
    });

    test('a deletion is not an insertion', () {
      expect(
          relocateEdgeWhitespace(at('**bold **', 7), at('**bold**', 6)), isNull);
    });

    test('a replaced selection is not a bare insertion', () {
      const before = TextEditingValue(
        text: '**bold**',
        selection: TextSelection(baseOffset: 2, extentOffset: 6),
      );
      expect(relocateEdgeWhitespace(before, at('** **', 3)), isNull);
    });

    test('a newline is left alone — Enter is the list engine\'s', () {
      final before = at('**bold**', 6);
      expect(relocateEdgeWhitespace(before, typed(before, '\n')), isNull);
    });
  });

  test('the formatter is the rule, and passes everything else through', () {
    const f = EmphasisGuardFormatter();
    final before = at('**bold**', 6);
    expect(f.formatEditUpdate(before, typed(before, ' ')).text, '**bold** ');

    final plain = at('hello', 5);
    final raw = typed(plain, ' ');
    expect(f.formatEditUpdate(plain, raw), raw);
  });
}
