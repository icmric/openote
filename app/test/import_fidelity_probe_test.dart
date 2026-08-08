// ignore_for_file: avoid_print — this file exists to PRINT what an import
// produced; that is its entire job.
// A probe, not a guard: run the REAL parser and the REAL Dart import over one
// specific `.one` and print what came out.
//
// Reported: "some [pages] just arent importing properly ... a page where we are
// just straight up missing half the content". The Rust parser's own `--import`
// dump shows this page's content is fully recovered — 13 text boxes, 11 ink
// strokes — so if something is missing by the time it reaches a notebook, it is
// lost on THIS side, and there was no way to see that.
//
// Skips when the sample is not on the machine, like the other import e2e test.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/open.dart';

import 'package:openote/core/onote_ffi.dart';
import 'package:openote/export/import_sink.dart';
import 'package:openote/export/onenote_import.dart';
import 'package:openote/ink/ink_storage.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('what actually lands for the Hasse diagram page', () async {
    final one = File(p.join(
        Platform.environment['USERPROFILE'] ?? '',
        'Downloads',
        'Equivalence Relations, Partial Orders and Hasse Diagrams.one'));
    final core = OnoteCore.instance;
    if (core == null || !one.existsSync()) {
      markTestSkipped('native core or the sample .one is not on this machine');
      return;
    }

    // 1) The parser, for real.
    final raw = core.importOne(one.readAsBytesSync());
    final parsed = jsonDecode(raw) as Map<String, dynamic>;
    expect(parsed['ok'], isTrue, reason: 'the parse itself must succeed');
    final pages = (parsed['pages'] as List).cast<Map<String, dynamic>>();
    print('PARSER: ${pages.length} page(s)');
    for (final pg in pages) {
      print('  "${pg['title']}"  boxes=${(pg['boxes'] as List).length} '
          'images=${(pg['images'] as List).length} '
          'ink=${(pg['ink'] as List).length}');
    }

    // 2) The Dart import, for real, into a temp notebook.
    final tmp = Directory.systemTemp.createTempSync('onote_probe_');
    addTearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final repo = await Repository.openAt(tmp);
    addTearDown(repo.dispose);
    final nb = await repo.createNotebook('Probe');
    final app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    addTearDown(app.cancelPendingSave);

    final sink = AppStateImportSink(app, nb.id);
    final section = sink.node(TreeNode(kind: NodeKind.section, title: 'Probe'));
    importPagesForTest(sink, section.id, pages);

    app.reloadNodes();
    final pageNodes =
        app.nodes.where((n) => n.kind == NodeKind.page).toList();
    print('IMPORTED: ${pageNodes.length} page node(s)');

    for (final n in pageNodes) {
      final data = repo.readPage(nb.id, n.id);
      print('  "${n.title}" -> ${data.blocks.length} blocks');
      final byType = <String, int>{};
      for (final b in data.blocks) {
        byType[b.type.name] = (byType[b.type.name] ?? 0) + 1;
      }
      print('    kinds: $byType');
      for (final b in data.blocks) {
        final where = '(${b.x.round()},${b.y.round()}) w=${b.w.round()}';
        if (b.type == BlockType.ink) {
          print('    ink   $where strokes=${InkStorage.strokeCount(b.content)}');
        } else {
          final t = (b.content['text'] as String? ?? '')
              .replaceAll('\n', ' | ');
          print('    ${b.type.name.padRight(5)} $where '
              '${t.length > 70 ? '${t.substring(0, 70)}…' : t}');
        }
      }
    }
  });
}
