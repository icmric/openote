// Links: the import produces them, the renderer makes them clickable.
//
// Neither half had a test. The OneNote importer emitted no links at all (it
// passed Word field codes through as literal `﷟HYPERLINK "…"` junk), and
// nothing here asserted that the `[label](url)` the renderer does understand
// actually reaches a tappable widget rather than being swallowed by the block's
// tap-to-edit gesture.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/core/platform_open.dart';

import 'package:openote/l10n/l10n.dart';
import 'package:openote/markdown/md_render.dart';

void main() {
  const base = TextStyle(fontSize: 14);

  Future<void> pump(WidgetTester t, String text) => t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
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
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
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

  group('opening things from a notebook', () {
    // Note text is untrusted — an imported OneNote page or a shared notebook
    // can contain anything a stranger wrote — so what we hand the OS matters.
    test('only http, https and mailto are openable', () {
      expect(PlatformOpen.isOpenableUrl('https://example.com'), isTrue);
      expect(PlatformOpen.isOpenableUrl('http://example.com'), isTrue);
      expect(PlatformOpen.isOpenableUrl('mailto:a@b.com'), isTrue);
      // A link in a note must not be able to launch a local executable.
      expect(PlatformOpen.isOpenableUrl('file:///C:/Windows/System32/calc.exe'),
          isFalse);
      expect(PlatformOpen.isOpenableUrl('javascript:alert(1)'), isFalse);
      expect(PlatformOpen.isOpenableUrl('vbscript:msgbox'), isFalse);
      expect(PlatformOpen.isOpenableUrl('not a url'), isFalse);
    });

    // A URL is allowed to contain `&`, so the allow-list above cannot be what
    // protects a shell — which is why there is no longer a shell. These stay
    // openable ON PURPOSE; the safety comes from ShellExecuteW taking the
    // target as one parameter rather than as a command line.
    test('a URL with shell metacharacters is still a URL', () {
      expect(PlatformOpen.isOpenableUrl('https://x.com/?a=1&b=2'), isTrue);
      expect(PlatformOpen.isOpenableUrl('https://x.com/" & calc.exe & "'),
          isTrue);
    });

    test('programs are recognised, documents are not', () {
      for (final n in ['a.exe', 'a.BAT', 'setup.msi', 'x.ps1', 'y.lnk',
                       'invoice.pdf.exe', 'notes.sh', 'app.AppImage']) {
        expect(PlatformOpen.isExecutableName(n), isTrue, reason: n);
      }
      for (final n in ['notes.pdf', 'slides.pptx', 'photo.png', 'a.exe.pdf',
                       'noextension', '.hidden']) {
        expect(PlatformOpen.isExecutableName(n), isFalse, reason: n);
      }
    });
  });
}
