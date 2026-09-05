// Why did `pageLevels` come back empty when the raw probe found pages?
//
// The probe asked `?$filter=level eq 1&$top=5` and got a real, distinct set of
// subpages. `pageLevels` asks the same thing plus `$select=id`, and a full
// import reported zero subpages. So the question is narrow: does adding
// `$select` to a `$filter` on this endpoint change the answer?
//
// Run: $env:ONOTE_GRAPH_LEVELCHECK="1"; flutter test test/manual/graph_levelcheck_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/core/secret_store.dart';
import 'package:openote/onenote/graph_auth.dart';
import 'package:openote/onenote/graph_client.dart';

const String _refreshKey = 'onenote.graph.refresh';

void main() {
  final on = Platform.environment['ONOTE_GRAPH_LEVELCHECK'];

  test('does \$select break \$filter', () async {
    final stored = SecretStore.debugPlatformRead(_refreshKey);
    expect(stored, isNotNull, reason: 'sign in through the app first');
    SecretStore.debugBackend = {_refreshKey: stored!};

    final auth = GraphAuth();
    final client = GraphClient(token: auth.accessToken);

    void say(String s) {
      // ignore: avoid_print
      print(s);
    }

    // The same section the earlier probe used: the biggest one.
    final notebooks = await client.notebooks();
    GraphSectionRef? best;
    var most = -1;
    for (final n in notebooks) {
      for (final s in await client.sections(n.id)) {
        final ps = await client.pages(s.id);
        if (ps.length > most) {
          most = ps.length;
          best = s;
        }
      }
    }
    final sec = best!;
    say('section "${sec.name}" ($most pages)');

    const base = 'https://graph.microsoft.com/v1.0/me/onenote';
    Future<int> count(String label, String q) async {
      try {
        final raw = await client.debugRawText('$base/sections/${sec.id}/pages?$q');
        final v = (jsonDecode(raw) as Map)['value'] as List? ?? const [];
        say('  $label -> ${v.length}');
        return v.length;
      } catch (e) {
        say('  $label -> ERROR $e');
        return -1;
      }
    }

    await count('filter only', r'$filter=level%20eq%201&$top=100');
    await count('filter + select', r'$filter=level%20eq%201&$select=id&$top=100');
    await count('filter + orderby', r'$filter=level%20eq%201&$orderby=order&$top=100');
    await count('select only', r'$select=id&$top=5');

    // And what the app's own method says, end to end.
    final levels = await client.pageLevels(sec.id);
    say('pageLevels -> ${levels.length} entries');
  },
      skip: on == null,
      timeout: const Timeout(Duration(minutes: 10)));
}
