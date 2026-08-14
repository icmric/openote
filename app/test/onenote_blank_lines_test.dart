// Blank lines the writer typed must survive the import, and only those.
//
// Reported: "across every page ive checked the blank lines ive added havent
// once been respected and are always ignored in the import. This causes all
// sorts of issues (as much of my formatting relies on them, which also means
// drawings are offset, images arent quite right)". They were: an empty
// paragraph produced no line at all, so every gap closed up and everything
// below a gap rode up the page.
//
// The fix keys on WHICH object is empty — a OneNote paragraph is a RichText
// (0x0D) container plus a RichText_Run (0x0E), the container is textless by
// construction, and only an empty RUN is a line the writer left blank. The
// unit tests for that live in `rust/onote_core/src/onenote.rs`; this is the
// check against a real file, because an earlier attempt keyed on "is the text
// empty" and double-spaced the whole notebook (24 content lines came back
// separated by 31 blanks) without any unit test noticing.
//
// GROUND TRUTH is OneNote's own PDF export of this page, which shows 24
// paragraphs of content and a single blank line before each of the four
// headings after the first. Numbers below are read off that export.
//
// Skips (does not fail) when the native core or the sample aren't on the
// machine, like the other import e2e tests — the sample is a user's own export
// and is not in the repo, so a missing one must not break the build. But a
// skipped test is RECORDED AS A SUCCESS, which would make this file go green in
// CI having asserted nothing at all: the same false confidence that let the
// first attempt at this fix ship double-spaced. So the skip prints a loud
// NOT VERIFIED line naming what was missing. Run locally with:
//   flutter test test/onenote_blank_lines_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openote/core/onote_ffi.dart';

/// Every markdown line of a parsed page, in order, across all of its text boxes.
List<String> _lines(Map<String, dynamic> page) => [
      for (final raw in (page['boxes'] as List? ?? const []))
        ...(((raw as Map)['markdown'] as String? ?? '').isEmpty
            ? const <String>[]
            : ((raw)['markdown'] as String).split('\n'))
    ];

void main() {
  test('an empty paragraph imports as a blank line, and a full one does not',
      () {
    final core = OnoteCore.instance;
    final solo = File(p.join(
        Platform.environment['USERPROFILE'] ?? '',
        'Downloads',
        'Logic Tautologies, Contradictions and Quantifiers.one'));
    if (core == null || !solo.existsSync()) {
      final why = core == null
          ? 'the native core is not built'
          : 'the sample export is not at ${solo.path}';
      // ignore: avoid_print
      print('!!! NOT VERIFIED: onenote_blank_lines_test asserted NOTHING — '
          '$why. Blank-line import fidelity is unchecked in this run. To check '
          'it, export the OneNote page "Logic: Tautologies, Contradictions and '
          'Quantifiers" to ${solo.path} and re-run.');
      markTestSkipped('$why — see the NOT VERIFIED line above');
      return;
    }

    final parsed =
        jsonDecode(core.importOne(solo.readAsBytesSync())) as Map<String, dynamic>;
    expect(parsed['ok'], isTrue, reason: 'the sample export must parse');
    final pages = (parsed['pages'] as List).cast<Map<String, dynamic>>();
    expect(pages, hasLength(1), reason: 'a single-page export holds one page');

    final lines = _lines(pages.single);
    final blanks = lines.where((l) => l.trim().isEmpty).length;
    final content = lines.length - blanks;

    // 24 and 4 are counted off OneNote's PDF export of this page. Both numbers
    // matter and they fail in opposite directions: 0 blanks is the original
    // complaint, while a blank count near the content count is the
    // double-spacing that got the first attempt reverted.
    expect(content, 24, reason: 'the page has 24 paragraphs of content');
    expect(blanks, 4, reason: 'and exactly four blank lines between them');

    // Position, not just count — a gap in the wrong place still misplaces the
    // drawings and images that sit below it.
    for (final heading in const [
      '***Contradiction***',
      '***Variables***',
      '***Quantifiers***',
      '***Negation of Quantified Statements***',
    ]) {
      final at = lines.indexOf(heading);
      expect(at, greaterThan(0), reason: '$heading should survive the import');
      expect(lines[at - 1].trim(), isEmpty,
          reason: 'OneNote shows a blank line above $heading');
    }

    // The leading blank OneNote stores at the top of the box is NOT one of
    // them: the box is positioned by its own y coordinate, so keeping it would
    // push the text down a line relative to where OneNote drew it.
    expect(lines.first.trim(), isNotEmpty,
        reason: 'a box must not open with a blank line');

    // And no gap is ever doubled on this page.
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) {
        expect(lines[i - 1].trim(), isNotEmpty,
            reason: 'two blank lines in a row at $i means empties are doubling');
      }
    }
  });
}
