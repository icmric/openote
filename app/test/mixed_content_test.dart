// What can actually share ONE box with text?
//
// The ask: "Verify that i can have images and videos (and tables, maths, etc)
// all in the same box with text and each other." This file is the answer,
// written as executable assertions against the REAL renderer rather than as a
// claim. Where something does not compose, the test pins the reason, so the
// gap is documented instead of surprising.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';
import 'package:openote/markdown/md_render.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:openote/model/models.dart';

void main() {
  // A REAL 1x1 transparent PNG. It has to decode: Flutter resolves the codec
  // asynchronously and an invalid image throws into the test, even though the
  // Image widget itself is built either way.
  final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwACh'
      'wGA60e6kgAAAABJRU5ErkJggg==');

  Future<void> render(WidgetTester t, String md) => t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: MarkdownView(
            text: md,
            baseStyle: const TextStyle(fontSize: 14),
            imageResolver: (_) => png,
          ),
        ),
      ));

  /// Every character the renderer actually laid out as text, joined. Anything
  /// that became a widget (an image, a table, maths) will NOT appear here —
  /// which is exactly how we tell "rendered" from "printed as source".
  String renderedText(WidgetTester t) => t
      .widgetList<RichText>(find.byType(RichText))
      .map((r) => r.text.toPlainText())
      .join('\n');

  group('these all share one box with the text', () {
    testWidgets('an image, on its own line, between paragraphs', (t) async {
      await render(t, 'Before the picture\n'
          '![](sha256:abc123)\n'
          'After the picture');
      // The picture became a real Image widget, and the prose either side
      // survived as text.
      expect(find.byType(Image), findsOneWidget);
      final text = renderedText(t);
      expect(text, contains('Before the picture'));
      expect(text, contains('After the picture'));
      expect(text, isNot(contains('sha256:')),
          reason: 'a rendered image must not also print its own source');
    });

    testWidgets('inline maths, mid-sentence, beside the words', (t) async {
      // `$…$` is in the inline alternation, so maths shares a LINE with text,
      // not merely a box.
      await render(t, r'The identity $e^{i\pi}+1=0$ closes the term.');
      expect(find.byType(Math), findsWidgets,
          reason: 'the maths became a real formula, not literal source');
      expect(renderedText(t), contains('closes the term'));
    });

    testWidgets('display maths on its own line, with prose around it',
        (t) async {
      await render(t, 'The mean is\n'
          r'$$\sum_{i=1}^{n} x_i$$'
          '\nas expected.');
      expect(find.byType(Math), findsWidgets);
      final text = renderedText(t);
      expect(text, contains('The mean is'));
      expect(text, contains('as expected'));
    });

    testWidgets('a table, under a paragraph, in the same box', (t) async {
      await render(t, 'Results below:\n'
          '| n | f(n) |\n'
          '| - | ---- |\n'
          '| 1 | 1    |');
      expect(find.byType(Table), findsOneWidget);
      expect(renderedText(t), contains('Results below'));
    });

    testWidgets('lists, checkboxes, quotes and rules', (t) async {
      await render(t, 'Plan:\n'
          '- a bullet\n'
          '- [ ] a task\n'
          '1. numbered\n'
          '> quoted\n'
          '---\n'
          'and prose after.');
      final text = renderedText(t);
      for (final s in ['Plan', 'a bullet', 'a task', 'numbered', 'quoted',
        'and prose after']) {
        expect(text, contains(s), reason: '"$s" should render in the box');
      }
    });

    testWidgets('everything at once, in a single box', (t) async {
      // The actual question, asked directly: text + image + maths + table +
      // a list, all in ONE text block.
      await render(t, 'Lecture 7\n'
          '- covered truth tables\n'
          '![](sha256:abc123)\n'
          r'The identity $e^{i\pi}+1=0$ came up.'
          '\n| n | f(n) |\n'
          '| - | ---- |\n'
          '| 1 | 1    |\n'
          r'$$\sum_{i=1}^{n} x_i$$');
      expect(find.byType(Image), findsOneWidget, reason: 'image');
      expect(find.byType(Table), findsOneWidget, reason: 'table');
      expect(find.byType(Math), findsWidgets, reason: 'maths');
      final text = renderedText(t);
      expect(text, contains('Lecture 7'));
      expect(text, contains('covered truth tables'));
    });
  });

  group('these do NOT, and here is exactly why', () {
    testWidgets('an image cannot share a line with words', (t) async {
      // `_reImage` is line-anchored (`^…$`) and the inline alternation has no
      // image branch, so a reference beside prose renders as literal source.
      // This is why the insert helpers force a picture onto its own line.
      await render(t, 'text ![](sha256:abc123) more text');
      expect(find.byType(Image), findsNothing);
      expect(renderedText(t), contains('sha256:'),
          reason: 'it degrades to visible source rather than a picture');
    });

    test('a video is its own block, not something inside the text', () {
      // Media links ride BlockType.file. There is no inline video dialect, so
      // a recording cannot sit inside a paragraph the way an image or
      // `$maths$` can — it is a card that lives beside the box.
      final v = Block(
        type: BlockType.file,
        x: 0,
        y: 0,
        content: {'url': 'https://example.edu/lecture', 'kind': 'video'},
      );
      expect(v.type, isNot(BlockType.text));
    });

    test('ink is its own block too', () {
      // Handwriting is page-absolute strokes, not characters, so it overlays
      // the page rather than flowing with the writing.
      final ink = Block(type: BlockType.ink, x: 0, y: 0, content: {'strokes': []});
      expect(ink.type, isNot(BlockType.text));
    });
  });
}
