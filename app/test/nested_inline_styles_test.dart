// Two styles on one piece of text — colour and bold, highlight and bold.
//
// The owner, on issue #17: *"Colour is a really important thing to me that we
// get right … surley its not that hard to be able to implement it given the
// parser already recurses with markdown (being able to apply multiple styles
// on a single bit of text), would it not be the same deal here?"*
//
// It did not recurse. `***both***` is a branch of the alternation written out
// by hand, which is why bold+italic looked like evidence of something
// general; everything else was one flat pass, so whichever marker won at the
// outer position took the style and the inner one stayed as characters on the
// page. The toggles have descended into nested runs all along
// (`AppState._runAround`), and the colour command writes `{{#hex **word**}}`
// whenever you colour a bold word — so this was two renderers disagreeing
// with the rest of the app, not a gap in the model.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/live_markdown_controller.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/markdown/md_render.dart';
import 'package:openote/theme/onote_theme.dart';

const _base = TextStyle(fontSize: 14, color: Color(0xFF211F1B));
const _red = Color(0xFFC63838);

/// Every leaf of text, with the style it is actually painted with — a child's
/// style merged onto its parent's, which is what [TextSpan] itself does.
List<({String text, TextStyle style})> _leaves(
    List<InlineSpan> spans, TextStyle base) {
  final out = <({String text, TextStyle style})>[];
  void walk(InlineSpan s, TextStyle inherited) {
    if (s is! TextSpan) return;
    final style = s.style == null ? inherited : inherited.merge(s.style!);
    final t = s.text;
    if (t != null && t.isNotEmpty) out.add((text: t, style: style));
    for (final k in s.children ?? const <InlineSpan>[]) {
      walk(k, style);
    }
  }

  for (final s in spans) {
    walk(s, base);
  }
  return out;
}

({String text, TextStyle style}) _read(String source) {
  final ls = _leaves(inlineSpans(source, _base, false), _base);
  expect(ls, hasLength(1), reason: 'one run of text: ${ls.map((l) => l.text)}');
  return ls.single;
}

void main() {
  group('the read renderer', () {
    test('COLOUR AROUND BOLD IS BOTH', () {
      final l = _read('{{#C63838 **word**}}');
      expect(l.text, 'word', reason: 'and no markers survive into the page');
      expect(l.style.color, _red);
      expect(l.style.fontWeight, FontWeight.w600);
    });

    test('AND BOLD AROUND COLOUR IS THE SAME TWO', () {
      // Which way round they were typed is not something anybody tracks, and
      // `applyTextColor` and `wrapSelection` can each produce either.
      final l = _read('**{{#C63838 word}}**');
      expect(l.text, 'word');
      expect(l.style.color, _red);
      expect(l.style.fontWeight, FontWeight.w600);
    });

    test('a highlighted bold word keeps its highlight', () {
      final l = _read('==**word**==');
      expect(l.style.fontWeight, FontWeight.w600);
      expect(l.style.backgroundColor, isNotNull);
    });

    test('colour and highlight together: ink and ground', () {
      final l = _read('{{#C63838 ==word==}}');
      expect(l.style.color, _red);
      expect(l.style.backgroundColor, isNotNull);
    });

    test('bold with an underscore italic inside it', () {
      final l = _read('**_word_**');
      expect(l.style.fontWeight, FontWeight.w600);
      expect(l.style.fontStyle, FontStyle.italic);
    });

    test('four deep, which is as many as anyone will ever ask for', () {
      final l = _read('{{#C63838 **_~~word~~_**}}');
      expect(l.style.color, _red);
      expect(l.style.fontWeight, FontWeight.w600);
      expect(l.style.fontStyle, FontStyle.italic);
      expect(l.style.decoration, TextDecoration.lineThrough);
    });

    test('a subscript inside bold stays bold, and stays small', () {
      final ls = _leaves(inlineSpans('**H~2~O**', _base, false), _base);
      expect(ls.map((l) => l.text).join(), 'H2O');
      for (final l in ls) {
        expect(l.style.fontWeight, FontWeight.w600);
      }
      final two = ls.firstWhere((l) => l.text == '2');
      expect(two.style.fontSize, lessThan(14));
    });

    test('and code is still literal', () {
      final l = _read('`**x**`');
      expect(l.text, '**x**', reason: 'a code span has no markup inside it');
      expect(l.style.fontWeight, isNot(FontWeight.w600));
    });

    test('***both*** still reads as both', () {
      final l = _read('***word***');
      expect(l.style.fontWeight, FontWeight.w600);
      expect(l.style.fontStyle, FontStyle.italic);
    });
  });

  group('the live editor', () {
    Future<LiveMarkdownController> pump(WidgetTester t, String text) async {
      final c = LiveMarkdownController(text: text, dark: false);
      await t.pumpWidget(MaterialApp(
        localizationsDelegates: kOnoteLocalizations,
        supportedLocales: kOnoteLocales,
        theme: onoteTheme(Brightness.light),
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: TextField(controller: c, maxLines: null, style: _base),
          ),
        ),
      ));
      await t.pumpAndSettle();
      return c;
    }

    /// What a reader can see. Markers are laid out at a hairline so no caret
    /// offset moves; anything that size is not on the page.
    List<({String text, TextStyle style})> visible(
            WidgetTester t, LiveMarkdownController c) =>
        _leaves([
          c.buildTextSpan(
              context: t.element(find.byType(EditableText)),
              style: _base,
              withComposing: false)
        ], _base).where((l) => (l.style.fontSize ?? 14) > 1).toList();

    testWidgets('SHOWS THE SAME TWO STYLES THE READER WILL SEE', (t) async {
      final c = await pump(t, 'a {{#C63838 **word**}} b');
      final seen = visible(t, c);

      expect(seen.map((l) => l.text).join(), 'a word b',
          reason: 'the markers are still hidden at both depths');
      final word = seen.firstWhere((l) => l.text == 'word');
      expect(word.style.color, _red);
      expect(word.style.fontWeight, FontWeight.w600);
    });

    testWidgets('the other way round, too', (t) async {
      final c = await pump(t, 'a **{{#C63838 word}}** b');
      final word = visible(t, c).firstWhere((l) => l.text == 'word');
      expect(word.style.color, _red);
      expect(word.style.fontWeight, FontWeight.w600);
    });

    testWidgets('and the caret is told about the markers it cannot see',
        (t) async {
      const src = '{{#C63838 **word**}}';
      final c = await pump(t, src);
      final hidden = <int>{
        for (final r in c.hiddenMarkerRanges())
          for (var i = r.start; i < r.end; i++) i
      };
      // `{{#C63838 ` is ten and its `}}` is two; the inner `**` is two each
      // side. Without the inner pair the caret walks through two dead
      // keystrokes at each end of the word and Backspace eats half a marker.
      expect(hidden, hasLength(16));
      final word = src.indexOf('word');
      expect(hidden.contains(word - 1), isTrue, reason: 'the inner `**`');
      expect(hidden.contains(word), isFalse, reason: 'but not the word');
    });
  });
}
