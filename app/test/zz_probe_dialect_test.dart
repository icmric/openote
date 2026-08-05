// THROWAWAY probe: do the two renderers agree on WHICH constructs exist?
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/markdown/md_render.dart';
import 'package:openote/theme/onote_theme.dart';

const style = TextStyle(fontSize: 15, height: 1.5, letterSpacing: 0.25);

void main() {
  testWidgets('what read mode makes of each line shape', (t) async {
    for (final src in [
      '# h1',
      '### h3',
      '#### h4',
      '##### h5',
      '- dash bullet',
      '* star bullet',
      '+ plus bullet',
      '---',
      '1) paren numbered',
    ]) {
      await t.pumpWidget(MaterialApp(
        theme: onoteTheme(Brightness.light),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
                width: 420,
                child: MarkdownView(text: src, baseStyle: style)),
          ),
        ),
      ));
      // What text actually reaches the screen tells us whether the markers
      // were consumed (a construct) or drawn (literal source).
      final shown = <String>[];
      for (final e in find.byType(RichText).evaluate()) {
        shown.add((e.widget as RichText).text.toPlainText());
      }
      // ignore: avoid_print
      print('${src.padRight(20)} -> $shown');
    }
  });
}
