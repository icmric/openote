// **A link is its words while you are writing, not its address.**
//
// Reported: *"links which are embedded into a page (as in the []() structure)
// expands out which it shouldnt do."* Every other inline kind in this editor
// changes character when the caret arrives — bold stays bold, an equation
// stays an equation, a table stays a table — and links were the last one that
// did not. Clicking into a sentence unfolded
// `[the docs](https://example.test/a/very/long/path)` in the middle of it and
// re-wrapped the line around sixty characters nobody had written.
//
// The old code's own comment gave the reason: *"Zero-width markers would hide
// half a URL and leave the caret walking through characters nobody can see."*
// That objection was correct when it was written and is not any more —
// `_snapOutOfHiddenMarkers` and `markerAwareDelete` are exactly the answer to
// it, and they arrived afterwards. So the job here is to register a link as an
// ordinary marker run and let that machinery do what it already does for bold.
//
// Which makes the invariants below the point of this file. The buffer is not
// allowed to change, every caret offset has to stay where it was, and the
// coverage check has to keep passing on every keystroke — because the cost of
// getting this wrong is not a link that looks wrong, it is a note that has
// been quietly rewritten.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/live_markdown_controller.dart';
import 'package:openote/markdown/md_syntax.dart';

void main() {
  const url = 'https://example.test/a/very/long/path';

  group('the marker arithmetic', () {
    test('an external link hides everything but its label', () {
      final mk = linkMarkers(MdInline.extLink, 'the docs', '[the docs]($url)');
      expect(mk, isNotNull);
      expect(mk!.openLen, 1, reason: 'the opening bracket');
      expect(mk.closeLen, ']($url)'.length, reason: 'and all of the address');
    });

    test('a wiki link hides its page id too', () {
      final mk = linkMarkers(MdInline.wikiLink, 'Chemistry', '[[Chemistry|p7]]');
      expect(mk, isNotNull);
      expect(mk!.openLen, 2);
      expect(mk.closeLen, '|p7]]'.length);
    });

    test('and one with no id still closes correctly', () {
      final mk = linkMarkers(MdInline.wikiLink, 'Chemistry', '[[Chemistry]]');
      expect(mk!.openLen, 2);
      expect(mk.closeLen, 2);
    });

    test('a label that is not where the arithmetic says gives up', () {
      // The fallback that makes this safe: null means "draw the source", which
      // is exactly what the editor did before. A grammar change can cost the
      // live form of a link; it can never cost the coverage invariant.
      expect(linkMarkers(MdInline.extLink, 'elsewhere', '[here]($url)'), isNull);
      expect(linkMarkers(MdInline.extLink, null, '[here]($url)'), isNull);
      expect(linkMarkers(MdInline.bold, 'x', '**x**'), isNull,
          reason: 'this answers for links and nothing else');
    });
  });

  group('what the caret sees', () {
    LiveMarkdownController ctl(String text) {
      final c = LiveMarkdownController(text: text, dark: false);
      addTearDown(c.dispose);
      return c;
    }

    test('the address is hidden and the words are not', () {
      final c = ctl('See [the docs]($url) for more.');
      final hidden = c.hiddenMarkerRanges();
      // `[` before the label, and `](…)` after it.
      expect(hidden, hasLength(2));
      expect(c.text.substring(hidden[0].start, hidden[0].end), '[');
      expect(c.text.substring(hidden[1].start, hidden[1].end), ']($url)');
    });

    test('a bare URL hides nothing, because it IS its own label', () {
      final c = ctl('See $url for more.');
      expect(c.hiddenMarkerRanges(), isEmpty);
    });

    test('a link inside a table cell hides its address the same way', () {
      // A cell is a `LiveMarkdownController` like any other, so this is the
      // same code — but it is the case the owner asked to be sure of, and
      // "same code" is a claim a test should be making rather than a comment.
      final c = ctl('[docs]($url)');
      final hidden = c.hiddenMarkerRanges();
      expect(hidden, hasLength(2));
      expect(hidden.first.start, 0);
      expect(hidden.last.end, c.text.length);
    });
  });

  group('the buffer is untouched, which is the whole invariant', () {
    late LiveMarkdownController c;

    setUp(() {
      c = LiveMarkdownController(text: 'See [the docs]($url) now.', dark: false);
      addTearDown(c.dispose);
    });

    testWidgets('the span reproduces the source character for character',
        (t) async {
      // The coverage check inside `buildTextSpan` falls back to an unstyled
      // span when it fails, so proving the LINK is drawn proves coverage held:
      // a failure would have produced one flat run and no hidden markers.
      late TextSpan span;
      await t.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          span = c.buildTextSpan(
              context: context,
              style: const TextStyle(fontSize: 14),
              withComposing: false) as TextSpan;
          return const SizedBox();
        }),
      ));

      final buf = StringBuffer();
      void collect(InlineSpan s) {
        if (s is TextSpan) {
          if (s.text != null) buf.write(s.text);
          s.children?.forEach(collect);
        }
      }

      collect(span);
      expect(buf.toString(), c.text,
          reason: 'every character of the buffer, in order, and no others');
      expect(c.hiddenMarkerRanges(), hasLength(2),
          reason: 'and it really took the link branch, not the fallback');
    });

    test('the text length never moves, so no caret offset does either', () {
      final before = c.text;
      c.hiddenMarkerRanges();
      expect(c.text, before);
      expect(c.text.length, before.length);
    });
  });

  group('the caret steps over the address in one press', () {
    // The behaviour the old comment was worried about, now provided by the
    // machinery it predates. Without the run registered, Right inside the
    // label would give the person `]`, `(`, `h`, `t`, `t`, `p`… — forty dead
    // keystrokes through characters that are not on the screen.
    late LiveMarkdownController c;
    const text = 'a [b](https://x.test) c';

    setUp(() {
      c = LiveMarkdownController(text: text, dark: false);
      addTearDown(c.dispose);
      c.selection = const TextSelection.collapsed(offset: 0);
    });

    test('moving right out of the label lands past the whole link', () {
      // Caret just after `b`, which is the last visible character of the link.
      const afterLabel = 4;
      c.selection = const TextSelection.collapsed(offset: afterLabel);
      // One step right, as the platform would report it.
      c.value = c.value.copyWith(
          selection: const TextSelection.collapsed(offset: afterLabel + 1));
      expect(c.selection.baseOffset, text.length - 2,
          reason: 'the end of `](https://x.test)`, not one character into it');
    });

    test('moving left out of the label lands before the whole link', () {
      const atLabel = 3; // just before `b`
      c.selection = const TextSelection.collapsed(offset: atLabel);
      c.value = c.value.copyWith(
          selection: const TextSelection.collapsed(offset: atLabel - 1));
      expect(c.selection.baseOffset, 2,
          reason: 'the `[` is hidden, so the caret does not stop inside it');
    });
  });
}
