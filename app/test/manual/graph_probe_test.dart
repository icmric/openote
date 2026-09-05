// **Not a test. A window onto what Microsoft Graph actually sends.**
//
// Skipped unless `ONOTE_GRAPH_PROBE` names a directory to write into, so the
// suite ignores it entirely:
//
//   $env:ONOTE_GRAPH_PROBE="C:\some\dir"; flutter test test/manual/graph_probe_test.dart
//
// It exists because three fixes in a row were built on an assumption about the
// real markup and three in a row were wrong — the page hierarchy, the table
// column widths, and equations. The converter's own tests pass against samples
// written by the same person who wrote the converter, which proves it does
// what was expected and says nothing about whether what was expected is what
// OneNote sends.
//
// It reuses the app's sign-in and rotates the stored refresh token exactly as
// the app would, so running it cannot invalidate the credential the app is
// using.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/core/secret_store.dart';
import 'package:openote/onenote/graph_auth.dart';
import 'package:openote/onenote/graph_client.dart';

const String _refreshKey = 'onenote.graph.refresh';

void main() {
  final dest = Platform.environment['ONOTE_GRAPH_PROBE'];

  test('look at the wire', () async {
    final outDir = Directory(dest!)..createSync(recursive: true);

    // Under `flutter test` the credential store swaps itself for an in-memory
    // map, so the real one has to be read through its own escape hatch and
    // seeded into the map the rest of the code will use.
    final stored = SecretStore.debugPlatformRead(_refreshKey);
    expect(stored, isNotNull,
        reason: 'sign in through the app first — nothing is stored');
    SecretStore.debugBackend = {_refreshKey: stored!};

    final auth = GraphAuth();
    final client = GraphClient(token: auth.accessToken);
    final log = StringBuffer();

    try {
      final notebooks = await client.notebooks();
      log.writeln('notebooks: ${notebooks.length}');

      GraphNotebook? chosen;
      var mostSections = -1;
      for (final n in notebooks) {
        final s = await client.sections(n.id);
        log.writeln('  ${n.name}: ${s.length} sections');
        if (s.length > mostSections) {
          mostSections = s.length;
          chosen = n;
        }
      }
      final nb = chosen!;
      log.writeln('probing "${nb.name}"');

      final sections = await client.sections(nb.id);
      File('${outDir.path}/sections.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert([
        for (final s in sections)
          {'id': s.id, 'name': s.name, 'groupPath': s.groupPath}
      ]));

      // The hierarchy question, answered from the wire rather than from the
      // documentation: does `level` come back, and what else is on the object?
      final raw = await client.debugRawJson(
          'https://graph.microsoft.com/v1.0/me/onenote/sections/'
          '${sections.first.id}/pages?\$top=5');
      File('${outDir.path}/pages-raw.json').writeAsStringSync(raw);
      final rows =
          ((jsonDecode(raw) as Map<String, dynamic>)['value'] as List?) ??
              const [];
      if (rows.isNotEmpty) {
        log.writeln('page object keys: ${(rows.first as Map).keys.toList()}');
      }

      var saved = 0;
      for (final section in sections) {
        final pages = await client.pages(section.id);
        final levels = pages.map((p) => p.level).toSet().toList()..sort();
        log.writeln('${section.groupPath}/${section.name}: '
            '${pages.length} pages, levels $levels');
        for (final p in pages.take(3)) {
          final html = await client.pageHtml(p.id);
          File('${outDir.path}/${saved.toString().padLeft(3, '0')}.html')
              .writeAsStringSync(html);
          saved++;
        }
        if (saved >= 45) break;
      }
      log.writeln('saved $saved pages');
    } finally {
      client.close();
      SecretStore.debugBackend = null;
    }

    File('${outDir.path}/log.txt').writeAsStringSync(log.toString());
    // ignore: avoid_print
    print(log);
  },
      timeout: const Timeout(Duration(minutes: 10)),
      skip: dest == null ? 'set ONOTE_GRAPH_PROBE to run' : null);
}
