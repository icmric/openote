// **Can subpage nesting be recovered over Graph at all?**
//
// The owner: "Ideally id love to have it actually put them into their
// respective subpage structure, try everything you can think of to reliably do
// this (i.e. DO NOT GUESS BASED ON THE NAME), however if its truly not
// possible at all over the graph API then thats ok".
//
// Already known and not repeated here: the default page object carries neither
// `level` nor `order`, and `$select=id,title,level` comes back as `[id,title]`
// with `level` silently dropped. What IS known is that `$orderby=order` works
// — so the fields exist server-side, they are simply never projected into the
// response.
//
// That asymmetry is the opening. A field the server can SORT by is a field the
// server may also FILTER by, and a filter turns "tell me the value" into "tell
// me which pages have this value" — which is the same information, obtained
// the other way round, and is not a guess about anybody's title.
//
// This probe tries, in order of how much it would buy:
//
//   1. `$filter=level eq N` — exact membership per level. Would settle it.
//   2. The beta endpoint, which frequently projects fields v1.0 does not.
//   3. `$expand` and `$select=*`, in case the field is merely not default.
//   4. `Prefer: odata.include-annotations="*"`, which some Graph workloads
//      use to attach extra properties.
//
// Run: $env:ONOTE_GRAPH_LEVEL="C:\some\dir"; flutter test test/manual/graph_level_probe_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/core/secret_store.dart';
import 'package:openote/onenote/graph_auth.dart';
import 'package:openote/onenote/graph_client.dart';

const String _refreshKey = 'onenote.graph.refresh';

void main() {
  final dest = Platform.environment['ONOTE_GRAPH_LEVEL'];

  test('is a page level reachable by any means', () async {
    final outDir = Directory(dest!)..createSync(recursive: true);
    final stored = SecretStore.debugPlatformRead(_refreshKey);
    expect(stored, isNotNull, reason: 'sign in through the app first');
    SecretStore.debugBackend = {_refreshKey: stored!};

    final auth = GraphAuth();
    final client = GraphClient(token: auth.accessToken);
    final log = StringBuffer();

    void say(String s) {
      log.writeln(s);
      // ignore: avoid_print
      print(s);
    }

    try {
      // A section with enough pages that nesting is likely to exist.
      final notebooks = await client.notebooks();
      GraphSectionRef? best;
      var most = -1;
      for (final n in notebooks) {
        for (final s in await client.sections(n.id)) {
          final pages = await client.pages(s.id);
          if (pages.length > most) {
            most = pages.length;
            best = s;
          }
        }
      }
      final sec = best!;
      say('section "${sec.name}" with $most pages');

      Future<void> attempt(String label, String url) async {
        try {
          final raw = await client.debugRawText(url);
          final ok = raw.contains('"level"') || raw.contains('"order"');
          say('$label -> ${ok ? "HAS level/order" : "no level/order"} '
              '(${raw.length} bytes)');
          File('${outDir.path}/${label.replaceAll(RegExp(r"[^a-z0-9]+", caseSensitive: false), "_")}.json')
              .writeAsStringSync(raw);
        } catch (e) {
          say('$label -> FAILED: $e');
        }
      }

      final base = 'https://graph.microsoft.com/v1.0/me/onenote';
      final beta = 'https://graph.microsoft.com/beta/me/onenote';

      // 1. The one that would settle it.
      for (final n in [0, 1, 2]) {
        await attempt('filter-level-eq-$n',
            '$base/sections/${sec.id}/pages?\$filter=level%20eq%20$n&\$top=5');
      }
      // A filter the server rejects tells us as much as one it accepts, so
      // ask for something impossible too — if THAT succeeds, the filter is
      // being ignored rather than honoured, and any "match" above is noise.
      await attempt('filter-level-eq-99',
          '$base/sections/${sec.id}/pages?\$filter=level%20eq%2099&\$top=5');

      // 2. Beta.
      await attempt('beta-pages', '$beta/sections/${sec.id}/pages?\$top=5');
      await attempt('beta-pages-select-level',
          '$beta/sections/${sec.id}/pages?\$select=id,title,level&\$top=5');

      // 3. Everything the projection might be hiding.
      await attempt('v1-select-star',
          '$base/sections/${sec.id}/pages?\$select=*&\$top=5');
      await attempt('v1-expand-parent',
          '$base/sections/${sec.id}/pages?\$expand=parentSection&\$top=3');
      await attempt(
          'v1-orderby-level', '$base/sections/${sec.id}/pages?\$orderby=level&\$top=5');

      // 4. One page on its own, in case the collection projection is thinner
      // than the single-entity one.
      final pages = await client.pages(sec.id);
      if (pages.isNotEmpty) {
        await attempt('v1-single-page', '$base/pages/${pages.first.id}');
        await attempt(
            'beta-single-page', '$beta/pages/${pages.first.id}');
      }
    } finally {
      File('${outDir.path}/level-probe.txt').writeAsStringSync(log.toString());
    }
  }, skip: dest == null, timeout: const Timeout(Duration(minutes: 10)));
}
