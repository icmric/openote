// Layout fidelity against OneNote, expressed as two scale-free ratios that were
// MEASURED from OneNote's own PDF export of real pages (see the doc comments on
// the constants for the measurement tables).
//
// These pin the fix for the stakeholder-reported "text doesn't align with the
// other elements / text boxes, inking and images all get misaligned". Neither
// images nor ink were ever misplaced — imported *text* was rendered 11.7% too
// tall per line and a quarter as far indented, so it slid past the neighbours
// that sat at their own correct absolute positions.
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/export/onenote_import.dart' show oneNoteLineHeight;
import 'package:openote/markdown/md_render.dart'
    show kIndentPerLevel, indentPx;

/// Page space is 120 dpi; OneNote stores type in points.
const _pxPerPt = 120.0 / 72.0;

void main() {
  group('OneNote line pitch (vertical alignment)', () {
    // Ground truth: a grid fit over every line step in OneNote's PDF export,
    // in page units, divided by the em we render at —
    //   Lecture     22.38299u / 18.3333 = 1.220890 (66 steps)
    //   Lecture p2  22.37745u / 18.3333 = 1.220588 (55 steps)
    // Both match Calibri's own (1950+550)/2048 = 1.2207031.
    const measured = 1.2207031;

    test('matches OneNote within 0.5%', () {
      expect((oneNoteLineHeight - measured).abs() / measured, lessThan(0.005),
          reason: 'imported line pitch must track OneNote, not a guess');
    });

    test('a long box accumulates under 10px of drift', () {
      // The real first box of Lecture.one is 62 lines of 11pt text.
      const lines = 62, pt = 11.0;
      final ours = pt * _pxPerPt * oneNoteLineHeight;
      final onenote = pt * _pxPerPt * measured;
      final drift = (ours - onenote).abs() * lines;
      expect(drift, lessThan(10.0),
          reason: 'at lineHeight 1.35 this box drifted ~161px past its '
              'neighbouring images and ink');
    });
  });

  group('OneNote indent (horizontal alignment)', () {
    // Ground truth: indent step / font size. Lecture 20.60/8.400 = 2.452;
    // Lecture p2 26.20/10.728 = 2.442.
    const measured = 2.447;

    test('matches OneNote within 1%', () {
      expect((kIndentPerLevel - measured).abs() / measured, lessThan(0.01));
    });

    test('indent scales with font size and uses 2 spaces per level', () {
      // 11pt imported text → 18.33px; OneNote indents ~44.9px per level.
      const fontPx = 11.0 * _pxPerPt;
      expect(indentPx(2, fontPx), closeTo(44.9, 0.6),
          reason: 'one nesting level at imported body size');
      expect(indentPx(4, fontPx), closeTo(89.8, 1.2), reason: 'two levels');
      expect(indentPx(0, fontPx), 0);
      // Proportional, not fixed: bigger type indents further.
      expect(indentPx(2, fontPx * 2), closeTo(indentPx(2, fontPx) * 2, 0.01));
    });

    test('falls back to a sane default when the style has no size', () {
      expect(indentPx(2, null), closeTo(2.45 * 14.0, 0.01));
    });
  });
}
