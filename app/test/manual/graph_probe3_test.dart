// Third look at the wire: can the two things the .onepkg route has and this
// one does not be got at all?
//
//   1. **Ink.** The page HTML has none. The OneNote API documents an
//      `includeinkML=true` on page content — if that really returns InkML,
//      handwriting is reachable and parity is a parser away rather than
//      impossible.
//   2. **Attachments.** One `<object>` in sixty pages; what does it carry?
//
// Run: $env:ONOTE_GRAPH_PROBE3="C:\dir"; flutter test test/manual/graph_probe3_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/core/secret_store.dart';
import 'package:openote/onenote/graph_auth.dart';
import 'package:openote/onenote/graph_client.dart';

const String _refreshKey = 'onenote.graph.refresh';

void main() {
  final dest = Platform.environment['ONOTE_GRAPH_PROBE3'];

  test('ink and attachments', () async {
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

      // Look for a page that has ink by asking for it WITH inkML and seeing
      // whether the answer changes shape.
      var checked = 0;
      var withInk = 0;
      String? sample;
      for (final section in all) {
        if (checked >= 90) break;
        final pages = await client.pages(section.id);
        for (final p in pages.take(4)) {
          if (checked >= 90) break;
          checked++;
          final raw = await client.debugRawText(
              'https://graph.microsoft.com/v1.0/me/onenote/pages/${p.id}'
              '/content?includeinkML=true');
          final looksMultipart = raw.contains('--') &&
              raw.toLowerCase().contains('content-type:');
          // A page with REAL ink, not merely an empty envelope: every page
          // carries `<inkml:traceGroup />` whether or not anything was drawn.
          final hasInk = raw.contains('<inkml:trace ') ||
              raw.contains('<inkml:trace>');
          if (hasInk) {
            withInk++;
            // WHOLE response. Truncating it was how the last run reported ink
            // on every page: the check matched something in the part it kept
            // and the InkML part, if any, was past the cut.
            if (sample == null) {
              sample = raw;
              File('${outDir.path}/full-response.txt').writeAsStringSync(raw);
            }
          }
          if (checked <= 1) {
            log.writeln('page $checked: ${raw.length} bytes, '
                'multipart=$looksMultipart ink=$hasInk');
            log.writeln('  starts: ${raw.substring(0, raw.length < 220 ? raw.length : 220).replaceAll('\n', ' | ')}');
          }
        }
      }
      log.writeln('\nchecked $checked pages, $withInk carried InkML');
      if (sample != null) {
        File('${outDir.path}/ink-sample.txt').writeAsStringSync(sample);
        log.writeln('ink sample written');
      }
    } catch (e) {
      log.writeln('STOPPED: $e');
    } finally {
      client.close();
      SecretStore.debugBackend = null;
      File('${outDir.path}/log3.txt').writeAsStringSync(log.toString());
    }

    // ignore: avoid_print
    print(log);
  },
      timeout: const Timeout(Duration(minutes: 20)),
      skip: dest == null ? 'set ONOTE_GRAPH_PROBE3 to run' : null);
}
