// The Unicode font-fallback chain must actually reach the text.
//
// This exists because "the characters still don't render" is indistinguishable
// from "the fallback was never applied", and the second is easy to cause by
// accident: `TextBlockView.baseStyle` builds a raw `TextStyle` with the box's own
// family, which bypasses the theme's fallback entirely. That was the original
// bug, and a misspelled family name fails the same silent way.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/text_block_view.dart';
import 'package:openote/model/models.dart';
import 'package:openote/theme/onote_theme.dart';

void main() {
  Block textBlock(Map<String, dynamic> content) =>
      Block(type: BlockType.text, x: 0, y: 0, w: 300, content: content);

  test('a plain block carries the fallback chain', () {
    final s = TextBlockView.baseStyle(textBlock({'text': 'x'}), dark: false);
    expect(s.fontFamilyFallback, onoteFontFallback);
  });

  test('an imported block carries it too, despite naming its own family', () {
    // The regression that mattered: imported boxes set `font`, and a style with
    // an explicit family does not consult the theme's fallback list.
    final s = TextBlockView.baseStyle(
        textBlock({'text': 'x', 'font': 'Calibri', 'fontSize': 18.33}),
        dark: false);
    expect(s.fontFamily, 'Calibri');
    expect(s.fontFamilyFallback, onoteFontFallback,
        reason: 'without this, ∧ ∀ ∃ ⊆ render as blank boxes in every '
            'imported maths note');
  });

  test('the theme sets it as the app-wide default', () {
    for (final b in Brightness.values) {
      expect(onoteTheme(b).textTheme.bodyMedium?.fontFamilyFallback,
          onoteFontFallback,
          reason: '$b');
    }
  });

  test('the bundled primary face is Inter, with the chain still behind it', () {
    // Style guide §4.1: the app must look the same on every OS, which only
    // holds if the primary family is bundled — and the fallback chain must
    // stay behind it, or math/symbol glyphs regress to blank boxes.
    for (final b in Brightness.values) {
      final body = onoteTheme(b).textTheme.bodyMedium;
      expect(body?.fontFamily, 'Inter', reason: '$b');
      expect(body?.fontFamilyFallback, onoteFontFallback, reason: '$b');
    }
  });

  group('chain composition', () {
    test('wide-coverage symbol fonts come before the PUA-only ones', () {
      // Symbol and Wingdings also claim U+00AC, where Symbol's glyph is a left
      // arrow. They must be reachable (for U+F0xx) but only last.
      final segoe = onoteFontFallback.indexOf('Segoe UI Symbol');
      final dejavu = onoteFontFallback.indexOf('DejaVu Sans');
      final symbol = onoteFontFallback.indexOf('Symbol');
      final wingdings = onoteFontFallback.indexOf('Wingdings');
      expect(segoe, greaterThanOrEqualTo(0));
      expect(symbol, greaterThan(segoe));
      expect(symbol, greaterThan(dejavu));
      expect(wingdings, greaterThan(dejavu));
    });

    test('no duplicates and no empty entries', () {
      expect(onoteFontFallback.toSet().length, onoteFontFallback.length);
      expect(onoteFontFallback.any((f) => f.trim().isEmpty), isFalse);
    });
  });
}
