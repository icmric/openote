import 'package:flutter_test/flutter_test.dart';
import 'package:openote/export/md_common.dart';
import 'package:openote/math/linear_math.dart';

// Regression tests for export projection + math grammar. (Replaces the default
// Flutter counter template, which referenced a non-existent `MyApp` and broke
// the test build.)
void main() {
  group('safeFilename', () {
    test('preserves international titles', () {
      expect(safeFilename('日本語'), '日本語');
      expect(safeFilename('Über notes'), 'Über notes');
    });
    test('strips filesystem-hostile characters', () {
      expect(safeFilename('a/b:c*?'), 'a b c');
      expect(safeFilename('  trailing.  '), 'trailing');
    });
    test('falls back for empty / reserved names', () {
      expect(safeFilename('***'), 'untitled');
      expect(safeFilename('CON'), 'untitled');
      expect(safeFilename('', fallback: 'page'), 'page');
    });
  });

  group('markdownInline projection', () {
    test('wiki-links become onote:// links, not leaked brackets', () {
      expect(markdownInline('see [[Topic|abc123]] now'),
          'see [Topic](onote://page/abc123) now');
      expect(markdownInline('[[Just a title]]'), '[Just a title]');
    });
    test('colour spans degrade to their inner text', () {
      expect(markdownInline('a {{#FF0000 red}} b'), 'a red b');
      expect(markdownInline('{{#00FF0080 alpha}}'), 'alpha');
    });
  });

  group('tableToMarkdown', () {
    test('pads ragged rows and escapes pipes', () {
      final md = tableToMarkdown([
        ['a', 'b'],
        ['c'], // short row
        ['d|e', 'f'],
      ]);
      expect(md, contains('| a | b |'));
      expect(md, contains('| c |  |')); // padded to 2 cols
      expect(md, contains(r'd\|e'));
    });
  });

  group('linearToLatex fraction binding (Math Input Spec §7 seed)', () {
    test('the conformance seed builds the expected LaTeX', () {
      final out = linearToLatex(r'\sum_(n=1)^oo 1/n^2 = pi^2/6');
      expect(out, contains(r'\frac{1}{n^2}'));
      // The previously-broken case: the unicode/control-word space no longer
      // detaches the numerator, so pi^2/6 binds as a fraction.
      expect(out, contains(r'\frac{\pi^2}{6}'));
    });
  });
}
