// Ground truth for "which revision of a page is the current one", checked
// against the only authority there is: OneNote's own export of that page.
//
// A `.one` section inside a `.onepkg` carries, for each page, the object space
// as it stands PLUS every stored page version (MS-ONESTORE revision manifests
// with a `gctxid`). The parser used to choose between competing declarations of
// an object by raw file offset, and ONESTORE reuses free chunks — so a version
// snapshot sitting further down the file silently replaced live content. On
// "Logic: Tautologies, Contradictions and Quantifiers" that swapped a
// 21-paragraph outline for an 18-paragraph one and deleted the page's last five
// lines ("Negation of Quantified Statements" and its bullets); on "Equivalence
// Relations…" it cut the page from 2475 characters to 866.
//
// The check: OneNote's single-page `.one` export of a page contains only the
// live revision, so it IS the answer. The same page pulled out of the whole
// notebook's `.onepkg` must read back identically, box for box.
//
// Skips (does not fail) when the native core or the samples aren't on the
// machine, like the other import e2e tests. Run locally with:
//   flutter test test/onenote_revision_currency_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openote/core/onote_ffi.dart';

/// A page OneNote exported on its own, and a phrase that identifies the same
/// page inside the package. The page is found by CONTENT, not by title, so that
/// the title is left free to be checked rather than assumed.
///
/// It used to be checked and found wanting: two of these pages carried each
/// other's titles in the package, and this file recorded that as the file's own
/// doing. It was ours. A page series lists its pages in display order and their
/// metadata in creation order, and the importer paired the two arrays by index,
/// so any section with a reordered page handed titles to the wrong pages — 16
/// of the notebook's 329. The titles are matched by page identity now, and the
/// assertion below is the guard: OneNote's own export says what the page is
/// called.
const _cases = <({String file, String marker})>[
  (
    file: 'Logic Tautologies, Contradictions and Quantifiers.one',
    marker: 'Negation of Quantified Statements',
  ),
  (
    file: 'Equivalence Relations, Partial Orders and Hasse Diagrams.one',
    marker: 'A relation that is reflective, symmetric, AND transitive',
  ),
  (
    file: 'Natural Language and Intro to Truth Tables.one',
    marker: 'Natural language is',
  ),
];

/// Every box's text, in order — the part of a parsed page this is about.
/// Tables contribute their cells, so a lost table fails too.
String _content(Map<String, dynamic> page) {
  final out = StringBuffer();
  for (final raw in (page['boxes'] as List? ?? const [])) {
    final b = (raw as Map).cast<String, dynamic>();
    out.writeln(b['markdown'] as String? ?? '');
    for (final row in (b['cells'] as List? ?? const [])) {
      out.writeln((row as List).join(''));
    }
    out.writeln((b['latex'] as String? ?? ''));
  }
  return out.toString();
}

void main() {
  test('a page in the .onepkg reads the same as OneNote exported it', () {
    final core = OnoteCore.instance;
    final downloads =
        p.join(Platform.environment['USERPROFILE'] ?? '', 'Downloads');
    final pkg =
        File(p.join(downloads, 'Eric - Computing Science (Honours).onepkg'));
    final present = [
      for (final c in _cases)
        if (File(p.join(downloads, c.file)).existsSync()) c
    ];
    if (core == null || !pkg.existsSync() || present.isEmpty) {
      final why = core == null
          ? 'the native core is not built'
          : !pkg.existsSync()
              ? 'the notebook package is not at ${pkg.path}'
              : 'none of the single-page exports are in $downloads';
      // A skipped test is RECORDED AS A SUCCESS, so staying quiet here would
      // let this file go green in CI having asserted nothing at all — the same
      // false confidence that let a version snapshot ship as live content.
      // ignore: avoid_print
      print('!!! NOT VERIFIED: onenote_revision_currency_test asserted '
          'NOTHING — $why. Which revision of a page the importer treats as '
          'current is unchecked in this run. To check it, put '
          '"${p.basename(pkg.path)}" and at least one of '
          '${_cases.map((c) => '"${c.file}"').join(', ')} in $downloads and '
          're-run.');
      markTestSkipped('$why — see the NOT VERIFIED line above');
      return;
    }

    // Every page in the package, flattened — the section a page lives in does
    // not matter here, only that its content survived the parse.
    final parsed = jsonDecode(core.importOnepkg(pkg.readAsBytesSync()))
        as Map<String, dynamic>;
    expect(parsed['ok'], isTrue, reason: 'the package parse must succeed');
    final packagePages = [
      for (final s in (parsed['sections'] as List? ?? const []))
        for (final pg
            in (((s as Map)['section'] as Map?)?['pages'] as List? ?? const []))
          (pg as Map).cast<String, dynamic>()
    ];
    expect(packagePages, isNotEmpty);

    for (final c in present) {
      final one = File(p.join(downloads, c.file));
      final solo = jsonDecode(core.importOne(one.readAsBytesSync()))
          as Map<String, dynamic>;
      expect(solo['ok'], isTrue, reason: '${c.file} must parse');
      final soloPages = (solo['pages'] as List).cast<Map<String, dynamic>>();
      expect(soloPages, hasLength(1),
          reason: 'a single-page export holds one page');
      final expected = _content(soloPages.single);
      expect(expected, contains(c.marker),
          reason: 'the marker must identify the exported page itself');

      final matches =
          packagePages.where((pg) => _content(pg).contains(c.marker)).toList();
      expect(matches, hasLength(1),
          reason: '${c.marker} should identify exactly one page in the package');
      expect(_content(matches.single), expected,
          reason: 'the package copy of "${c.file}" lost or changed content — '
              'a page-version snapshot has been read as live content again');
      // The page OneNote exported under this name must come out of the package
      // under the same name. Before page metadata was matched by page identity,
      // the page holding "Negation of Quantified Statements" came back titled
      // "Truth Tables, Compound Statements and Implication" — the title of the
      // page before it.
      expect(matches.single['title'], soloPages.single['title'],
          reason: 'the package copy of "${c.file}" is wearing another page\'s '
              'title — page metadata has been paired by position again');
    }
  });
}
