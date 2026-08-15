// End-to-end verification of the OneNote `.onepkg` import: drives the REAL
// native parser (onote_core.dll) and the REAL import/persistence code into a
// temp SQLite notebook, then checks the resulting section/page tree — order,
// subpage levels, no orphans/flattening — against known ground truth.
//
// Skips (does not fail) when the native DLL or the sample notebook aren't
// present, so CI without them stays green. Run locally with:
//   flutter test test/onenote_import_e2e_test.dart
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/open.dart';

import 'package:openote/core/onote_ffi.dart';
import 'package:openote/export/import_sink.dart';
import 'package:openote/export/onenote_import.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

/// A section's imported page as (title, subpage level), in tab order.
typedef PageRow = ({String title, int level});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // sqlite3 needs its native lib; the app bundles it under the build output.
  setUpAll(() {
    for (final rel in [
      'build/windows/x64/runner/Debug/sqlite3.dll',
      'build/windows/x64/runner/Release/sqlite3.dll',
    ]) {
      final f = File(rel);
      if (f.existsSync()) {
        open.overrideForAll(() => DynamicLibrary.open(f.absolute.path));
        break;
      }
    }
  });

  test('.onepkg imports with correct order, subpage nesting, and no orphans',
      () async {
    final onepkg = File(
        p.join(Platform.environment['USERPROFILE'] ?? '', 'Downloads',
            'Eric - Computing Science (Honours).onepkg'));
    final core = OnoteCore.instance;
    if (core == null || !onepkg.existsSync()) {
      final why = core == null
          ? 'the native core is not built'
          : 'the sample notebook is not at ${onepkg.path}';
      // A skipped test is RECORDED AS A SUCCESS, so a silent skip would let
      // this file go green having asserted nothing at all. Say so loudly.
      // ignore: avoid_print
      print('!!! NOT VERIFIED: onenote_import_e2e_test asserted NOTHING — '
          '$why. Page order, subpage nesting AND the erased-ink ground truth '
          'below are all unchecked in this run. To check them, build the core '
          '(cargo build --release in rust/onote_core) and put the exported '
          'notebook at ${onepkg.path}, then re-run.');
      markTestSkipped('$why — see the NOT VERIFIED line above');
      return;
    }

    // 1) REAL native parse.
    final result =
        jsonDecode(core.importOnepkg(onepkg.readAsBytesSync())) as Map<String, dynamic>;
    expect(result['ok'], true, reason: 'parser should succeed');
    final sections = (result['sections'] as List?) ?? const [];
    expect(sections, isNotEmpty);

    // 2) REAL import into a throwaway workspace.
    final tmp = Directory.systemTemp.createTempSync('onote_e2e_');
    final repo = await Repository.openAt(tmp);
    addTearDown(() {
      repo.dispose(); // close SQLite handles before removing the dir
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {/* best-effort temp cleanup */}
    });
    final nb = await repo.createNotebook('E2E Import');
    final app = AppState(repo);
    final count = await buildNotebookFromPackage(AppStateImportSink(app, nb.id), sections);
    expect(count, greaterThan(100), reason: 'a full notebook of pages');

    // 3) Reconstruct the persisted tree exactly as the sidebar reads it
    //    (nodes ordered by position), grouped by section.
    final nodes = repo.loadNodes(nb.id); // ORDER BY position
    List<PageRow> pagesOf(String sectionTitle) {
      final sec = nodes.firstWhere(
          (n) => n.kind == NodeKind.section && n.title == sectionTitle);
      return [
        for (final n in nodes)
          if (n.kind == NodeKind.page && n.parentId == sec.id)
            (title: n.title, level: n.level),
      ];
    }

    // ── Ground truth: Programming 1 matches the live OneNote exactly ──
    final prog1 = pagesOf('Programming 1');
    expect(prog1.map((e) => e.title).toList(), [
      'Misc',
      'Week 1 Lecture',
      'Week 2 Lecture',
      'Week 4 Lecture',
      'Code comprehension notes',
      'Week 8 lecture',
    ]);
    expect(prog1.every((e) => e.level == 0), true,
        reason: 'Programming 1 has no subpages');

    // ── Discrete Mathematics: correct nesting throughout ──
    final disc = pagesOf('Discrete Mathematics');
    expect(disc.length, greaterThan(50),
        reason: 'all pages present (regression: an older build dropped ~11)');
    // The first week's page and its three subpages, in order.
    final i = disc.indexWhere((e) => e.title == 'Week 1: Logic and Statements');
    expect(i, greaterThanOrEqualTo(0));
    expect(disc[i].level, 0);
    expect(disc[i + 1],
        (title: 'Natural Language and Intro to Truth Tables', level: 1));
    expect(disc[i + 3].level, 1, reason: 'subpages stay nested');

    // ── Revision fix: a heavily-edited page still yields its text (the
    //    per-revision global-id-table bug lost content on such pages). The
    //    "Misc" page of Intro to Information Systems has real text under many
    //    revisions; assert it isn't an empty husk. ──
    final iis = nodes.firstWhere(
        (n) => n.kind == NodeKind.section && n.title.startsWith('Intro to Info'));
    final misc = nodes.firstWhere(
        (n) => n.kind == NodeKind.page && n.parentId == iis.id && n.title == 'Misc');
    final miscData = repo.readPage(nb.id, misc.id);
    final miscText = miscData.blocks
        .where((b) => b.type == BlockType.text)
        .map((b) => b.content['text'] as String? ?? '')
        .join('\n');
    expect(miscText, contains('assessment'),
        reason: 'revised page kept its text (regression: lost on stub-latest revision)');

    // Intro to Info Systems nests 3 levels deep (Module → Lecture → sub-note).
    final iisPages = pagesOf(iis.title);
    expect(iisPages.any((p) => p.level == 2), true,
        reason: '3-level nesting preserved');

    // ── No orphaned subpages in ANY section (the "flattened after the first
    //    group" bug): every level-n page is preceded, within its section, by a
    //    level-(n-1) page. Also assert real nesting exists somewhere. ──
    var sawNesting = false;
    for (final sec in nodes.where((n) => n.kind == NodeKind.section)) {
      final pages = pagesOf(sec.title);
      final seenAtLevel = <int, bool>{0: true};
      for (final pg in pages) {
        if (pg.level > 0) {
          sawNesting = true;
          expect(seenAtLevel[pg.level - 1] ?? false, true,
              reason:
                  'orphan L${pg.level} "${pg.title}" in "${sec.title}" — no parent level above it');
        }
        seenAtLevel[pg.level] = true;
        // Descending past a level resets deeper levels' "seen" state.
        seenAtLevel.removeWhere((k, _) => k > pg.level + 1);
      }
    }
    expect(sawNesting, true, reason: 'the notebook does use subpages');

    // ── Erased ink stays erased ────────────────────────────────────────────
    // Reported: "on some pages (like symbols in DM) there is some inking there
    // i guess was there originally in some old version but it isnt there if i
    // open up onenote."
    //
    // Ink used to be collected by a FLAT SCAN of the section's object space,
    // which asked only "is this the newest declaration of this container?" and
    // never "does the live page still reference it at all". Erasing ink in
    // OneNote removes the reference from the page tree and leaves the object in
    // the file forever, so every stroke ever erased came back on import. Ink is
    // now imported only when the live page still reaches it.
    //
    // GROUND TRUTH is the notebook's owner, checking these three pages in
    // OneNote: "Yep no ink on that page [Symbols]. That will be because i used
    // it for lots of quick notes where it was just erased. There is some text
    // and stuff on the cheatsheet page (and nothing on questions) but no ink on
    // either of them in onenote, so its all historic and has been erased."
    List<Block> blocksOf(String sectionTitle, String pageTitle) {
      final sec = nodes.firstWhere(
          (n) => n.kind == NodeKind.section && n.title == sectionTitle);
      final page = nodes.firstWhere((n) =>
          n.kind == NodeKind.page &&
          n.parentId == sec.id &&
          n.title == pageTitle);
      return repo.readPage(nb.id, page.id).blocks;
    }

    // "Foundation Mathamatics" is spelled that way in the notebook — it is the
    // real section name, not a typo in this test.
    //
    // A `null` marker means the owner says the page is EMPTY. "Questions" used
    // to be listed here with the marker 'tangent line', because the ink fix
    // read "nothing on questions" as "no INK on questions" and assumed the note
    // it was importing was live. It was not: that note, and the screenshot
    // beside it, are unreachable from the page's live root and no live-revision
    // object in the file references either of them. They were resurrections of
    // the same kind as the 121 erased ink containers on the same page — found
    // by a different scan, which is the only reason they outlived the ink fix.
    // The owner's sentence was right the first time.
    for (final (section, page, marker) in const [
      ('Discrete Mathematics', 'Symbols', 'Set of all integers'),
      ('Foundation Mathamatics', 'Cheat Sheet notes', 'Integration'),
      ('Foundation Mathamatics', 'Questions', null),
    ]) {
      final blocks = blocksOf(section, page);
      final strokes = blocks
          .where((b) => b.type == BlockType.ink)
          .fold<int>(
              0,
              (n, b) =>
                  n + (((b.content['strokes'] as List?) ?? const []).length));
      expect(strokes, 0,
          reason: 'the owner confirms "$page" shows no ink in OneNote — all of '
              'it was erased, and a flat scan of the object space resurrected '
              'it (39 strokes on "Symbols" alone)');

      // The other direction: dropping erased ink must not drop the page. The
      // pages the owner says still show text keep it, so a filter that swung
      // too far and took live objects with it fails here.
      final text = blocks
          .where((b) => b.type == BlockType.text)
          .map((b) => b.content['text'] as String? ?? '')
          .join('\n');
      if (marker == null) {
        expect(text.trim(), isEmpty,
            reason: 'the owner says "$page" is empty in OneNote — everything '
                'the file still holds for it is unreachable from its live root');
      } else {
        expect(text, contains(marker),
            reason: '"$page" keeps its text boxes — only the ink was erased');
      }
    }
    // "Symbols" is the page that was reported, and its live content is a set of
    // text boxes plus a maths block: 6 live children where a stored page
    // VERSION lists 43.
    expect(blocksOf('Discrete Mathematics', 'Symbols').length,
        greaterThanOrEqualTo(6),
        reason: 'Symbols keeps all of its live boxes');

    // Images too, not just text — and on THIS page the screenshot goes with the
    // note it was pasted beside. Its image object is declared only inside a
    // version revision and nothing live points at it, exactly like the note and
    // the ink. This assertion used to demand the picture survive, on the theory
    // that "not ink" meant "not erased"; deleting a picture in OneNote unlinks
    // it in precisely the same way, and one page cannot be half-alive.
    final questions = ((sections.firstWhere(
                    (s) => (s as Map)['name'] == 'Foundation Mathamatics')
                as Map)['section'] as Map)['pages'] as List;
    final qPage = (questions.firstWhere((p) => (p as Map)['title'] == 'Questions')
            as Map)
        .cast<String, dynamic>();
    expect((qPage['images'] as List?) ?? const [], isEmpty,
        reason: 'the picture on "Questions" was deleted along with the note');

    // The page that showed the ink fix was not finished. Two pages in "Maths 1"
    // are called "Working out" and the owner cleared one of them: its live
    // outline lists no children, while a stored VERSION of that same outline
    // still lists 180 ink containers. Reachability was being measured from
    // whichever outline declaration a scan of the object space turned up — the
    // version's, because the live one is empty and an empty declaration was
    // skipped — so the filter walked straight into the 180 erased strokes and
    // called them live. Measured from the page's own live root it reaches the
    // empty outline and stops. The other "Working out" is untouched, which is
    // why this is a pair: one page must lose all its ink and one must keep all
    // of it, and a rule that cannot tell them apart fails whichever way it errs.
    {
      final maths = ((sections.firstWhere((s) => (s as Map)['name'] == 'Maths 1')
              as Map)['section'] as Map)['pages'] as List;
      final workings = [
        for (final p in maths)
          if ((p as Map)['title'] == 'Working out')
            ((p['ink'] as List?) ?? const []).length
      ];
      expect(workings, hasLength(2),
          reason: 'the section really does have two pages of this name');
      expect(workings.where((n) => n == 0), hasLength(1),
          reason: 'the cleared "Working out" imports no ink at all');
      expect(workings.where((n) => n > 0), hasLength(1),
          reason: 'and the other one keeps every stroke it still has');
    }

    // A deleted box is not always an empty page — usually it is a DUPLICATE.
    // The Euler page carried an outline group, declared only inside a version
    // revision, holding five bullets that the page's live outline also holds;
    // it imported as five extra boxes stacked below the real ones. Each of
    // those lines must appear exactly once now, and — the other half of the
    // claim — must still appear.
    {
      final text = blocksOf('Discrete Mathematics',
              'Euler Paths and Circuits, and the Königsberg Bridge Problem')
          .where((b) => b.type == BlockType.text)
          .map((b) => b.content['text'] as String? ?? '')
          .join('\n');
      for (final line in const [
        'is a path which uses every edge exactly once',
        'is an Euler path which is also a circuit',
        'If every node has an (non-zero) even degree, it contains an Euler circuit',
      ]) {
        expect(line.allMatches(text).length, 1,
            reason: 'the Euler page should hold "$line" exactly once — a '
                'deleted outline group repeated five of its bullets below it');
      }
    }

    // And the notebook at large keeps its ink. This is the assertion that
    // catches the tempting-but-wrong rule "drop ink declared only inside a
    // version revision": 180 containers here hold ink the user can still see
    // whose only stored declaration is exactly that, because OneNote never
    // rewrites an object that has not changed.
    var totalStrokes = 0;
    for (final n in nodes.where((n) => n.kind == NodeKind.page)) {
      for (final b in repo.readPage(nb.id, n.id).blocks) {
        if (b.type == BlockType.ink) {
          totalStrokes +=
              ((b.content['strokes'] as List?) ?? const []).length;
        }
      }
    }
    expect(totalStrokes, greaterThan(60000),
        reason: 'the notebook is mostly handwritten — 64 080 strokes survive '
            'the filter, and only 0.83 % of the raw scan was erased ink');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
