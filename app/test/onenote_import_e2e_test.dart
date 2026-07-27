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
      markTestSkipped('native core or sample .onepkg not available');
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
    final count = await buildNotebookFromPackage(app, nb.id, sections);
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
  }, timeout: const Timeout(Duration(minutes: 3)));
}
