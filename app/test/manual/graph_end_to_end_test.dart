// A whole notebook, from the real service into a real notebook file.
//
// Everything else is tested against fixtures. This drives the actual thing:
// sign-in, listing, batching, throttling, conversion, and the same
// `AppStateImportSink` the app writes through — into a throwaway workspace, so
// it touches nothing the owner is using.
//
// It is the only check that the pieces fit together, and the only honest
// measurement of how long a real import takes.
//
// Run: $env:ONOTE_GRAPH_E2E="Mazle"; flutter test test/manual/graph_end_to_end_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/core/secret_store.dart';
import 'package:openote/export/import_sink.dart';
import 'package:openote/model/models.dart';
import 'package:openote/onenote/graph_auth.dart';
import 'package:openote/onenote/graph_client.dart';
import 'package:openote/onenote/graph_import.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import '../support/sqlite.dart';

const String _refreshKey = 'onenote.graph.refresh';

void main() {
  final want = Platform.environment['ONOTE_GRAPH_E2E'];
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  test('import a whole notebook', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final stored = SecretStore.debugPlatformRead(_refreshKey);
    expect(stored, isNotNull, reason: 'sign in through the app first');
    SecretStore.debugBackend = {_refreshKey: stored!};

    final tmp = Directory.systemTemp.createTempSync('onote_e2e_');
    final repo = await Repository.openAt(tmp);
    final app = AppState(repo);
    final ref = await repo.createNotebook('Imported');
    app.notebookId = ref.id;

    final auth = GraphAuth();
    final client = GraphClient(token: auth.accessToken);
    final sw = Stopwatch()..start();
    var lastReport = '';

    try {
      final notebooks = await client.notebooks();
      final chosen = notebooks.firstWhere(
          (n) => n.name.toLowerCase().contains(want!.toLowerCase()),
          orElse: () => notebooks.first);
      // ignore: avoid_print
      print('importing "${chosen.name}"');

      final result = await importNotebookFromGraph(
        client: client,
        notebookId: chosen.id,
        sink: AppStateImportSink(app, ref.id),
        onProgress: (p) {
          final line = p.waitingFor != null
              ? 'waiting ${p.waitingFor!.inSeconds}s'
              : '${p.pagesDone}/${p.pagesTotal} — ${p.sectionName}';
          if (line != lastReport) {
            lastReport = line;
            // ignore: avoid_print
            print('  $line  (${sw.elapsedMilliseconds} ms)');
          }
        },
      );
      sw.stop();

      app.reloadNodes();
      final pages =
          app.nodes.where((n) => n.kind == NodeKind.page).toList();
      final sections =
          app.nodes.where((n) => n.kind == NodeKind.section).length;
      final groups =
          app.nodes.where((n) => n.kind == NodeKind.sectionGroup).length;

      var textBoxes = 0, tables = 0, images = 0, inkBlocks = 0, files = 0;
      var strokes = 0, mathRuns = 0;
      for (final p in pages) {
        for (final b in repo.readPage(ref.id, p.id).blocks) {
          switch (b.type) {
            case BlockType.text:
              textBoxes++;
              final t = b.content['text'] as String? ?? '';
              mathRuns += RegExp(r'\$[^$]+\$').allMatches(t).length;
            case BlockType.table:
              tables++;
            case BlockType.image:
              images++;
            case BlockType.ink:
              inkBlocks++;
              strokes += ((b.content['strokes'] as List?) ?? const []).length;
            case BlockType.file:
              files++;
            default:
              break;
          }
        }
      }

      // ignore: avoid_print
      print('\n=== ${chosen.name} ===\n'
          'time            ${sw.elapsed.inSeconds}s\n'
          'pages           ${result.pages} (${pages.length} nodes)\n'
          'sections        $sections, groups $groups\n'
          'text boxes      $textBoxes\n'
          'tables          $tables\n'
          'images          $images\n'
          'attachments     $files\n'
          'ink blocks      $inkBlocks ($strokes strokes)\n'
          'inline maths    $mathRuns\n'
          'lost: ink pages ${result.loss.inkPages}, '
          'images ${result.loss.images}, '
          'attachments ${result.loss.attachments}\n'
          'per page        '
          '${result.pages == 0 ? 0 : sw.elapsedMilliseconds ~/ result.pages} ms');

      expect(result.pages, greaterThan(0));
    } finally {
      client.close();
      SecretStore.debugBackend = null;
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    }
  },
      timeout: const Timeout(Duration(minutes: 40)),
      skip: want == null ? 'set ONOTE_GRAPH_E2E to a notebook name' : null);
}
