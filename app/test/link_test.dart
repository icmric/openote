// Links: the import produces them, the renderer makes them clickable.
//
// Neither half had a test. The OneNote importer emitted no links at all (it
// passed Word field codes through as literal `﷟HYPERLINK "…"` junk), and
// nothing here asserted that the `[label](url)` the renderer does understand
// actually reaches a tappable widget rather than being swallowed by the block's
// tap-to-edit gesture.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/markdown/md_render.dart';

void main() {
  const base = TextStyle(fontSize: 14);

  Future<void> pump(WidgetTester t, String text) => t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: MarkdownView(text: text, baseStyle: base),
          ),
        ),
      ));

  /// The link is a WidgetSpan, so it shows up as its own Text.rich.
  Finder linkLabel(String label) => find.byWidgetPredicate((w) {
        if (w is! RichText) return false;
        return w.text.toPlainText().startsWith('$label ↗');
      });

  testWidgets('an explicit [label](url) renders as a link', (t) async {
    await pump(t, 'See [the notes](https://example.com/a) tonight.');
    expect(linkLabel('the notes'), findsOneWidget);
  });

  testWidgets('a bare URL is autolinked', (t) async {
    // Typing a URL into a note makes it a link in every other app. Requiring
    // `[label](url)` to get that is a Markdown detail nobody asked to learn.
    await pump(t, 'Watch https://www.youtube.com/watch?v=abc for Friday');
    expect(linkLabel('youtube.com/watch?v=abc'), findsOneWidget);
  });

  testWidgets('trailing sentence punctuation is not part of the address',
      (t) async {
    await pump(t, 'Read https://example.com/a.');
    expect(linkLabel('example.com/a'), findsOneWidget);
    // The full stop stays in the prose.
    expect(
      find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().endsWith('.')),
      findsWidgets,
    );
  });

  testWidgets('an explicit link is not double-matched by the autolinker',
      (t) async {
    // The bare-URL branch is last in the alternation for exactly this reason:
    // at the same position, `[label](url)` must win, or the label and the
    // address would both render.
    await pump(t, '[docs](https://example.com/x)');
    expect(linkLabel('docs'), findsOneWidget);
    expect(linkLabel('example.com/x'), findsNothing);
  });

  testWidgets('a long URL is shortened for reading but opens in full',
      (t) async {
    const long = 'https://example.com/very/long/path/that/keeps/going/'
        'and/going/until/it/would/overflow/the/box/final.pdf';
    await pump(t, 'x $long');
    final tip = t.widget<Tooltip>(find.byType(Tooltip));
    expect(tip.message, long, reason: 'the tooltip carries the real address');
    final label = t
        .widgetList<RichText>(find.byType(RichText))
        .map((w) => w.text.toPlainText())
        .firstWhere((s) => s.contains('…'));
    expect(label.length, lessThan(60));
  });

  testWidgets('a link inherits the surrounding text size', (t) async {
    // A WidgetSpan child does not inherit the enclosing span's style, so a
    // link used to render at the default size inside a 24pt heading.
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: MarkdownView(
          text: '[x](https://example.com)',
          baseStyle: TextStyle(fontSize: 24),
        ),
      ),
    ));
    final rt = t.widget<RichText>(linkLabel('x'));
    TextStyle? found;
    rt.text.visitChildren((s) {
      if (s is TextSpan && s.text == 'x') found = s.style;
      return found == null;
    });
    expect(found?.fontSize, 24);
  });
}
