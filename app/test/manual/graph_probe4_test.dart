// Does `$batch` still work now that each page carries its ink?
//
// Asking for `includeinkML=true` turns a 6 KB response into a multipart one,
// and on a heavily drawn page into 292 KB. Twenty of those in a single batch
// is nearly 6 MB, and Graph caps a batch response. If it refuses, the fallback
// to individual requests still imports everything — but it does so twenty
// round trips at a time, and that is the difference between minutes and tens
// of minutes, so it is worth knowing rather than assuming.
//
// Also captures an `<object>` attachment, which one page in sixty carries and
// the converter currently only counts.
//
// Run: $env:ONOTE_GRAPH_PROBE4="C:\dir"; flutter test test/manual/graph_probe4_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/core/secret_store.dart';
import 'package:openote/onenote/graph_auth.dart';
import 'package:openote/onenote/graph_client.dart';

const String _refreshKey = 'onenote.graph.refresh';

void main() {
  final dest = Platform.environment['ONOTE_GRAPH_PROBE4'];

  test('batching with ink, and attachments', () async {
    final outDir = Directory(dest!)..createSync(recursive: true);
    final stored = SecretStore.debugPlatformRead(_refreshKey);
    expect(stored, isNotNull, reason: 'sign in through the app first');
    SecretStore.debugBackend = {_refreshKey: stored!};

    final auth = GraphAuth();
    final client = GraphClient(token: auth.accessToken);
    final log = StringBuffer();

    try {
      final notebooks = await client.notebooks();
      final all = <GraphSectionRef>[];
      for (final n in notebooks) {
        for (final s in await client.sections(n.id)) {
          all.add(s);
        }
      }

      // A section with enough pages to fill a batch.
      GraphSectionRef? big;
      var pages = <GraphPageRef>[];
      for (final s in all) {
        final p = await client.pages(s.id);
        if (p.length >= 20) {
          big = s;
          pages = p;
          break;
        }
      }
      if (big == null) {
        log.writeln('no section with 20+ pages');
      } else {
        final sw = Stopwatch()..start();
        final got = await client.pageHtmlMany(
            [for (final p in pages.take(20)) p.id]);
        sw.stop();
        final ok = got.where((h) => h != null).length;
        final bytes =
            got.fold<int>(0, (a, h) => a + (h?.length ?? 0));
        final withInk =
            got.where((h) => h != null && h.contains('<inkml:trace ')).length;
        log.writeln('20 pages from "${big.name}": $ok returned, '
            '$bytes bytes, $withInk with ink, ${sw.elapsedMilliseconds} ms');
      }

      // An attachment, so the converter can do more than count it.
      var scanned = 0;
      for (final s in all) {
        if (scanned >= 90) break;
        final p = await client.pages(s.id);
        final htmls =
            await client.pageHtmlMany([for (final x in p.take(3)) x.id]);
        for (final h in htmls) {
          scanned++;
          if (h == null || !h.contains('<object')) continue;
          final m = RegExp(r'<object[^>]*>').firstMatch(h);
          if (m != null) {
            log.writeln('\nOBJECT: ${m.group(0)}');
            File('${outDir.path}/object-page.txt').writeAsStringSync(h);
            scanned = 999;
            break;
          }
        }
      }
      log.writeln('scanned $scanned for attachments');
    } catch (e) {
      log.writeln('STOPPED: $e');
    } finally {
      client.close();
      SecretStore.debugBackend = null;
      File('${outDir.path}/log4.txt').writeAsStringSync(log.toString());
    }

    // ignore: avoid_print
    print(log);
  },
      timeout: const Timeout(Duration(minutes: 25)),
      skip: dest == null ? 'set ONOTE_GRAPH_PROBE4 to run' : null);
}
