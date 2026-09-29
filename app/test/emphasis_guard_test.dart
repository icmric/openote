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
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

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

/// [relocateEdgeWhitespace]'s new value, with the carry-on marker dropped —
/// that half is asserted through the formatter, further down.
TextEditingValue? relocated(TextEditingValue a, TextEditingValue b) =>
    relocateEdgeWhitespace(a, b)?.value;

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

      final fixed = relocated(before, raw);
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
        final fixed = relocated(before, typed(before, ' '));
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
        expect(relocated(before, raw), isNull, reason: 'for $src');
        expect(stillStyled(raw.text, 1), isTrue,
            reason: 'for $src — which is WHY nothing is moved');
      }
    });

    test('a run in the middle of a sentence keeps the rest of it', () {
      final before = at('see **this** ok', 10);
      final fixed = relocated(before, typed(before, ' '));
      expect(fixed?.text, 'see **this**  ok');
      expect(fixed?.selection.baseOffset, 13);
    });

    test('a nested run, which the top-level walk never sees', () {
      // `mdInlineRe.allMatches` is non-overlapping, so `**a *b* c**` is ONE
      // match and the italic's edge is invisible at that level.
      final before = at('**a *b* c**', 6);
      final fixed = relocated(before, typed(before, ' '));
      expect(fixed?.text, '**a *b*  c**',
          reason: 'the space lands outside the italic and inside the bold, '
              'which is where it was typed');
    });
  });

  group('a space at the opening edge goes outside it too', () {
    test('bold', () {
      final before = at('**bold**', 2);
      final fixed = relocated(before, typed(before, ' '));
      expect(fixed?.text, ' **bold**');
      expect(fixed?.selection.baseOffset, 1);
      expect(stillStyled(fixed!.text, 3), isTrue);
    });
  });

  group('and it keeps its hands off everything else', () {
    test('a space in the middle of a run is just a space', () {
      final before = at('**two words**', 5);
      expect(relocated(before, typed(before, ' ')), isNull);
    });

    test('a space outside a run is just a space', () {
      final before = at('**bold** here', 9);
      expect(relocated(before, typed(before, ' ')), isNull);
    });

    test('a code span has no flanking rule, so nothing is moved', () {
      // `` `a ` `` is legal and means something. Moving the space would
      // rewrite what the student typed.
      final before = at('`code`', 5);
      expect(relocated(before, typed(before, ' ')), isNull,
          reason: 'the rule asks whether the run actually breaks rather than '
              'assuming every marker carries a flanking guard');
    });

    test('a letter at the same edge is left where it was typed', () {
      final before = at('**bold**', 6);
      expect(relocated(before, typed(before, 'x')), isNull,
          reason: 'extending the run is the whole point of parking the caret '
              'there');
    });

    test('plain text with no markup at all', () {
      final before = at('just a sentence', 4);
      expect(relocated(before, typed(before, ' ')), isNull);
    });

    test('a deletion is not an insertion', () {
      expect(
          relocated(at('**bold **', 7), at('**bold**', 6)), isNull);
    });

    test('a replaced selection is not a bare insertion', () {
      const before = TextEditingValue(
        text: '**bold**',
        selection: TextSelection(baseOffset: 2, extentOffset: 6),
      );
      expect(relocated(before, at('** **', 3)), isNull);
    });

    test('a newline is left alone — Enter is the list engine\'s', () {
      final before = at('**bold**', 6);
      expect(relocated(before, typed(before, '\n')), isNull);
    });
  });

  group('a marker is never left without its partner', () {
    /// [before] with `[a,b)` selected, replaced by [ins].
    (TextEditingValue, TextEditingValue) over(String text, int a, int b,
        [String ins = '']) {
      final old = TextEditingValue(
        text: text,
        selection: TextSelection(baseOffset: a, extentOffset: b),
      );
      return (
        old,
        at(text.replaceRange(a, b, ins), a + ins.length),
      );
    }

    test('the reported one: back-select a bold word and delete it', () {
      // `note **big**` — the markers cannot be seen, so dragging back over
      // the word "big" really selects from the start of `big` to past the
      // closing `**`. Deleting that used to leave `note **`.
      final (old, raw) = over('note **big**', 7, 12);
      expect(raw.text, 'note **',
          reason: 'the report verbatim: "it will remove it but leave ** at '
              'the start, so it doesnt remove it all"');

      final fixed = healOrphanedMarkers(old, raw);
      expect(fixed?.text, 'note ');
      expect(fixed?.selection.baseOffset, 5);
    });

    test('selecting the word from the other side does the same', () {
      final (old, raw) = over('note **big**', 5, 10); // `**big`
      expect(raw.text, 'note **', reason: 'the mirror image, trailing this time');
      expect(healOrphanedMarkers(old, raw)?.text, 'note ');
    });

    test('and selecting only what can be seen', () {
      final (old, raw) = over('note **big**', 7, 10); // exactly the inner text
      expect(raw.text, 'note ****',
          reason: 'markers with nothing between them, which no grammar '
              'matches — so four asterisks appear');
      expect(healOrphanedMarkers(old, raw)?.text, 'note ');
    });

    test('but text that survives keeps its style', () {
      // Only the tail went, so "bi" is still bold and gets its marker back.
      final (old, raw) = over('note **big**', 9, 12);
      expect(raw.text, 'note **bi');
      final fixed = healOrphanedMarkers(old, raw);
      expect(fixed?.text, 'note **bi**');
      expect(fixed?.selection.baseOffset, 9);
      expect(stillStyled(fixed!.text, 7), isTrue);
    });

    test('and from the front', () {
      final (old, raw) = over('note **big**', 5, 9); // `**bi`
      final fixed = healOrphanedMarkers(old, raw);
      expect(fixed?.text, 'note **g**');
      expect(fixed?.selection.baseOffset, 7);
    });

    test('typing over the word joins the run rather than sitting outside it',
        () {
      final (old, raw) = over('note **big**', 9, 12, 'X');
      final fixed = healOrphanedMarkers(old, raw);
      expect(fixed?.text, 'note **biX**',
          reason: 'the marker goes back on the OUTSIDE of what was typed');
      expect(fixed?.selection.baseOffset, 10);
    });

    test('a selection that misses the markers is left alone', () {
      final (old, raw) = over('note **big**', 8, 9); // just "i"
      expect(healOrphanedMarkers(old, raw), isNull);
    });

    test('a selection nowhere near a run is left alone', () {
      final (old, raw) = over('note **big** and more', 13, 16);
      expect(healOrphanedMarkers(old, raw), isNull);
    });

    test('a selection across a line break is somebody deleting paragraphs', () {
      final (old, raw) = over('note **big**\nsecond', 7, 15);
      expect(healOrphanedMarkers(old, raw), isNull);
    });

    test('a collapsed caret is markerAwareDelete\'s job, not this one', () {
      expect(healOrphanedMarkers(at('note **big**', 12), at('note **big*', 11)),
          isNull);
    });
  });

  group('two runs with a space between them are one run', () {
    test('which is how bold survives the space bar', () {
      // What the field holds after the space was relocated and the next word
      // was wrapped by the re-armed queue.
      final folded = mergeRunAtCaret(at('note **big** **more**', 19));
      expect(folded?.text, 'note **big more**');
      expect(folded?.selection.baseOffset, 15,
          reason: 'still inside the closing markers, so typing goes on '
              'extending the run with no further help');
    });

    test('the same kind spelled differently is not the same run', () {
      // `**a**` and `__b__` are both bold; folding them would rewrite one
      // into the other's marks.
      expect(mergeRunAtCaret(at('**a** __b__', 9)), isNull);
    });

    test('anything but whitespace between them, and they are two runs', () {
      expect(mergeRunAtCaret(at('**a**, **b**', 10)), isNull);
    });

    test('and the caret has to be in the second one', () {
      expect(mergeRunAtCaret(at('**a** **b**', 3)), isNull);
      expect(mergeRunAtCaret(at('**a** **b**', 5)), isNull);
    });
  });

  group('the formatter is the three rules, in order', () {
    late AppState app;
    setUp(() => app = AppState(_NoopRepo()));

    test('a space at the edge moves, and arms the style to carry on', () {
      final f = EmphasisGuardFormatter(app, 'b1');
      final before = at('**bold**', 6);
      expect(f.formatEditUpdate(before, typed(before, ' ')).text, '**bold** ');
      expect(app.pendingMarks, {'**'},
          reason: 'the student was writing in bold and pressed space, so they '
              'are still writing in bold');
      expect(app.pendingMarkAt, 9);
      expect(app.pendingMarkBlockId, 'b1');
    });

    test('a space at the FRONT arms nothing — there is no run to continue',
        () {
      final f = EmphasisGuardFormatter(app, 'b1');
      final before = at('**bold**', 2);
      expect(f.formatEditUpdate(before, typed(before, ' ')).text, ' **bold**');
      expect(app.pendingMarks, isEmpty);
    });

    test('and everything else passes straight through', () {
      final f = EmphasisGuardFormatter(app, 'b1');
      final plain = at('hello', 5);
      final raw = typed(plain, ' ');
      expect(f.formatEditUpdate(plain, raw), raw);
      expect(app.pendingMarks, isEmpty);
    });
  });
}

/// Nothing here reaches storage.
class _NoopRepo implements Repository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
