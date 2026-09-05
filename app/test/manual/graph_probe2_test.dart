// Second look at the wire, aimed at the four questions the first one raised.
//
//   1. Is `level` selectable? The default projection has no `level` and no
//      `order`, which is why every imported page was flat — so the question is
//      whether asking for them by name brings them back, or whether the
//      hierarchy has to come from somewhere else entirely.
//   2. Where are the equations? Forty-seven pages had no MathML at all.
//   3. What do `span` and `li` styles carry? They are the commonest styled
//      elements and the converter ignores both.
//   4. Are there images and attachments anywhere?
//
// Run: $env:ONOTE_GRAPH_PROBE2="C:\dir"; flutter test test/manual/graph_probe2_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/core/secret_store.dart';
import 'package:openote/onenote/graph_auth.dart';
import 'package:openote/onenote/graph_client.dart';

const String _refreshKey = 'onenote.graph.refresh';

void main() {
  final dest = Platform.environment['ONOTE_GRAPH_PROBE2'];

  test('the four open questions', () async {
    final outDir = Directory(dest!)..createSync(recursive: true);
    final stored = SecretStore.debugPlatformRead(_refreshKey);
    expect(stored, isNotNull, reason: 'sign in through the app first');
    SecretStore.debugBackend = {_refreshKey: stored!};

    final auth = GraphAuth();
    final client = GraphClient(token: auth.accessToken);
    final log = StringBuffer();

    try {
      final notebooks = await client.notebooks();
      // Every section of every notebook, so the sample is the whole library
      // rather than whichever notebook happened to be biggest.
      final all = <GraphSectionRef>[];
      for (final n in notebooks) {
        for (final s in await client.sections(n.id)) {
          all.add(s);
        }
      }
      log.writeln('sections across all notebooks: ${all.length}');

      // ── 1. Is `level` selectable? ──────────────────────────────────────
      for (final attempt in [
        r'$select=id,title,level,order',
        r'$select=id,title,level',
        r'$orderby=order&$top=3',
      ]) {
        try {
          final raw = await client.debugRawJson(
              'https://graph.microsoft.com/v1.0/me/onenote/sections/'
              '${all.first.id}/pages?$attempt');
          final rows =
              ((jsonDecode(raw) as Map<String, dynamic>)['value'] as List?) ??
                  const [];
          log.writeln('SELECT "$attempt" -> ok, keys '
              '${rows.isEmpty ? '(no rows)' : (rows.first as Map).keys.toList()}');
        } catch (e) {
          log.writeln('SELECT "$attempt" -> $e');
        }
      }

      // ── 2/3/4. Sweep a wide sample for the markup that matters ────────
      var scanned = 0;
      var withMath = 0;
      var withImg = 0;
      var withObject = 0;
      final spanStyles = <String, int>{};
      final liStyles = <String, int>{};
      final mathSamples = <String>[];
      final imgSamples = <String>[];

      for (final section in all) {
        if (scanned >= 60) break;
        final pages = await client.pages(section.id);
        final take = pages.length < 3 ? pages.length : 3;
        final htmls =
            await client.pageHtmlMany([for (final p in pages.take(take)) p.id]);
        for (final html in htmls) {
          if (html == null) continue;
          scanned++;
          if (RegExp(r'<math', caseSensitive: false).hasMatch(html)) {
            withMath++;
            if (mathSamples.length < 3) {
              final m =
                  RegExp(r'<math.*?</math>', dotAll: true).firstMatch(html);
              if (m != null) mathSamples.add(m.group(0)!);
            }
          }
          if (html.contains('<img')) {
            withImg++;
            if (imgSamples.length < 4) {
              final m = RegExp(r'<img[^>]*>').firstMatch(html);
              if (m != null) imgSamples.add(m.group(0)!);
            }
          }
          if (html.contains('<object')) withObject++;
          for (final m
              in RegExp(r'<span[^>]*style="([^"]*)"').allMatches(html)) {
            for (final decl in m.group(1)!.split(';')) {
              final prop = decl.split(':').first.trim().toLowerCase();
              if (prop.isEmpty) continue;
              spanStyles[prop] = (spanStyles[prop] ?? 0) + 1;
            }
          }
          for (final m in RegExp(r'<li[^>]*style="([^"]*)"').allMatches(html)) {
            for (final decl in m.group(1)!.split(';')) {
              final prop = decl.split(':').first.trim().toLowerCase();
              if (prop.isEmpty) continue;
              liStyles[prop] = (liStyles[prop] ?? 0) + 1;
            }
          }
        }
      }

      log.writeln('\nscanned $scanned pages');
      log.writeln('  with <math>: $withMath');
      log.writeln('  with <img>: $withImg');
      log.writeln('  with <object>: $withObject');
      log.writeln('  span styles: $spanStyles');
      log.writeln('  li styles: $liStyles');
      for (final m in mathSamples) {
        log.writeln('\nMATH SAMPLE:\n${m.length > 900 ? m.substring(0, 900) : m}');
      }
      for (final i in imgSamples) {
        log.writeln('\nIMG SAMPLE: $i');
      }
    } catch (e) {
      log.writeln('STOPPED: $e');
    } finally {
      client.close();
      SecretStore.debugBackend = null;
      File('${outDir.path}/log2.txt').writeAsStringSync(log.toString());
    }

    // ignore: avoid_print
    print(log);
  },
      timeout: const Timeout(Duration(minutes: 20)),
      skip: dest == null ? 'set ONOTE_GRAPH_PROBE2 to run' : null);
}
