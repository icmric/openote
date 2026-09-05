// The live editor's coverage invariant, held under the new list gutter.
//
// LiveMarkdownController rebuilds every line as spans and then CHECKS that
// they concatenate back to the raw text; if they do not it silently falls
// back to one unstyled span. Silently is the problem — a broken span build
// looks like "the styling just stopped working", with no crash to chase.
//
// List lines now emit a WidgetSpan standing for the prefix's first character
// with the rest hidden, so the arithmetic is worth proving line-shape by
// line-shape: a placeholder occupies exactly ONE code unit in layout, so if
// it ever stands for more than one source character every caret offset after
// it shifts.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/live_markdown_controller.dart';
import 'package:openote/l10n/l10n.dart';

/// Build the spans for [source] with the caret at [caret], and report
/// whether the controller kept them or fell back to one unstyled span.
///
/// The fallback is what the coverage check produces when the spans do not
/// reproduce the text, so "did it fall back" IS the invariant.
bool styled(WidgetTester t, String source, {int caret = 0}) {
  final c = LiveMarkdownController(text: source, dark: false)
    ..selection = TextSelection.collapsed(offset: caret);
  final root = c.buildTextSpan(
      context: t.element(find.byType(SizedBox)),
      style: const TextStyle(fontSize: 15, height: 1.5),
      withComposing: false);
  c.dispose();
  return root.children != null && root.children!.isNotEmpty;
}

void main() {
  Future<void> host(WidgetTester t) => t.pumpWidget(
      const MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: Scaffold(body: SizedBox(width: 400))));

  group('every line shape still builds styled spans', () {
    const shapes = <String, String>{
      'plain': 'just some words',
      'bullet': '- milk',
      'bullet star': '* milk',
      'bullet plus': '+ milk',
      'nested bullet': '  - milk',
      'deep bullet': '      - milk',
      'numbered': '1. first',
      'numbered paren': '2) second',
      'big number': '12. twelfth',
      'task': '- [ ] do it',
      'done task': '- [x] did it',
      'quote': '> quoted',
      'heading': '# Title',
      'bare marker': '-',
      'marker only': '- ',
      'divider': '---',
      'bold': 'a **bold** word',
      'bold italic': 'a ***both*** word',
      'code': 'a `code` word',
      'list with bold': '- a **bold** item',
      'list with link': '- see https://a.test/x',
      'empty': '',
      'blank lines': 'a\n\nb',
      'mixed doc': '# H\n\n- one\n  - two\n1. num\n- [ ] task\n\n> q\n\nend',
    };

    shapes.forEach((name, src) {
      testWidgets(name, (t) async {
        await host(t);
        if (src.isNotEmpty) {
          expect(styled(t, src), isTrue,
              reason: '"$src" fell back to unstyled — the coverage check '
                  'failed, so the span build does not reproduce the text');
        }
      });
    });
  });

  group('the caret can walk a list line without the text shifting', () {
    testWidgets('a placeholder stands for exactly one character', (t) async {
      await host(t);
      // Every caret position on a bulleted line must build cleanly: the
      // marker reveal/hide decisions run off the caret, so a bug here shows
      // up only at one particular offset.
      const src = '  - an item';
      for (var i = 0; i <= src.length; i++) {
        expect(styled(t, src, caret: i), isTrue,
            reason: 'caret at $i on "$src"');
      }
    });

    testWidgets('a multi-line document, caret on each line', (t) async {
      await host(t);
      const src = '- one\n  - two\n1. three\n- [ ] four';
      for (var i = 0; i <= src.length; i++) {
        expect(styled(t, src, caret: i), isTrue, reason: 'caret at $i');
      }
    });
  });
}
