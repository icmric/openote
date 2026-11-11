// The section colours: the eight new sections cycle through, and what must not
// change for sections that already exist.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/theme/onote_theme.dart';
import 'package:openote/theme/section_palette.dart';

void main() {
  test('there are eight colours, each with its own token and name', () {
    expect(sectionPalette, hasLength(8));
    expect({for (final h in sectionPalette) h.token}, hasLength(8));
    expect({for (final h in sectionPalette) h.name}, hasLength(8));
  });

  test('a colour paints differently on dark and on light', () {
    for (final h in sectionPalette) {
      expect(sectionColorFor(h.token, true), h.dark);
      expect(sectionColorFor(h.token, false), h.light);
      expect(h.dark, isNot(h.light));
    }
  });

  test('colours saved by earlier versions paint exactly as they did', () {
    // Silently recolouring someone's notebook is worse than the sameness the
    // palette replaces, so these must never move.
    expect(sectionColorFor('brass-400', true), OnoteColors.brass400);
    expect(sectionColorFor('brass-400', false), OnoteColors.brass400);
    expect(sectionColorFor('green', true), OnoteColors.success);
    expect(sectionColorFor('blue', false), const Color(0xFF2F6FB3));
    expect(sectionColorFor('violet', true), const Color(0xFF6A4BC0));
    expect(sectionColorFor('red', false), OnoteColors.danger);
    for (final t in ['brass-400', 'green', 'blue', 'violet', 'red']) {
      expect(isLegacySectionColor(t), isTrue);
    }
    expect(isLegacySectionColor('coral'), isFalse);
  });

  test('a section nobody coloured looks like ink, as it always did', () {
    expect(sectionColorFor(null, true), OnoteColors.ink400);
    expect(sectionColorFor(null, false), OnoteColors.ink500);
    // …and the palette's own ink is that same colour, so choosing it changes
    // nothing on screen.
    expect(sectionColorFor('ink', true), OnoteColors.ink400);
    expect(sectionColorFor('ink', false), OnoteColors.ink500);
    expect(pickerTokenFor(null), 'ink');
  });

  test('an unknown token falls back to ink rather than failing', () {
    // A notebook saved by a newer version may carry a token this one lacks.
    expect(sectionColorFor('from-the-future', true), OnoteColors.ink400);
  });

  test('a group takes its first section\'s colour, softened towards slate', () {
    final coral = sectionColorFor('coral', true);
    final g = groupColorFor('coral', true, hasSections: true);
    expect(g, isNot(coral));
    expect(g, isNot(const Color(0xFF8FA3BF)));
    // Empty: plain slate.
    expect(groupColorFor(null, true, hasSections: false),
        const Color(0xFF8FA3BF));
    expect(groupColorFor(null, false, hasSections: false),
        const Color(0xFF5A6F8C));
  });
}
