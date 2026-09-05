// Subpage nesting over Graph, which was written off as impossible.
//
// The owner: "Ideally id love to have it actually put them into their
// respective subpage structure, try everything you can think of to reliably do
// this (i.e. DO NOT GUESS BASED ON THE NAME)".
//
// It IS possible, and the reason it looked otherwise is worth keeping. `level`
// is never returned — `$select=id,title,level` comes back as `[id,title]` with
// the field silently dropped, on v1.0 and on beta, on a collection and on a
// single page; all four checked against the live service. So "the value cannot
// be read" was true, and "the hierarchy cannot be imported" was written down
// as settled on the strength of it.
//
// But `$orderby=order` works, which means the fields exist server-side and are
// merely never projected. A field the server can sort by is a field it may
// also FILTER by — and a filter turns "what level is this page?" into "which
// pages are at this level?". The same information, asked the other way round.
//
// Measured on a real 80-page section:
//
//     $filter=level eq 0  -> Week 12, Week 11: Power Series, …
//     $filter=level eq 1  -> Test Notes, Taylor Series, Maclaurin Series, …
//     $filter=level eq 2  -> none
//     $filter=level eq 99 -> none        <- the control
//
// The control is what makes that evidence rather than coincidence: a filter
// being IGNORED returns everything, so an impossible value returning nothing
// proves the server is really applying it.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/onenote/graph_client.dart';

void main() {
  tearDown(() => GraphClient.debugFetch = null);

  String rows(List<String> ids) => jsonEncode({
        'value': [for (final id in ids) {'id': id}]
      });

  group('pageLevels', () {
    test('asks per level and stops at the first empty one', () async {
      final asked = <String>[];
      GraphClient.debugFetch = (url) async {
        asked.add(url);
        if (url.contains('level%20eq%201')) {
          return (200, rows(['a', 'b']), <String, String>{});
        }
        return (200, rows(const []), <String, String>{});
      };
      final c = GraphClient(token: () async => 't');

      expect(await c.pageLevels('s1'), {'a': 1, 'b': 1});
      // Level 1 had pages so level 2 is worth asking; level 2 was empty so
      // nothing deeper is asked for. OneNote cannot make a sub-subpage
      // without a subpage above it.
      expect(asked.where((u) => u.contains('level%20eq%201')), hasLength(1));
      expect(asked.where((u) => u.contains('level%20eq%202')), hasLength(1));
      expect(asked.where((u) => u.contains('level%20eq%203')), isEmpty);
    });

    test('a section with no subpages costs exactly one request', () async {
      var n = 0;
      GraphClient.debugFetch = (url) async {
        n++;
        return (200, rows(const []), <String, String>{});
      };
      final c = GraphClient(token: () async => 't');

      expect(await c.pageLevels('s1'), isEmpty);
      expect(n, 1,
          reason: 'the common case must not pay for levels that cannot exist');
    });

    test('two levels of nesting are both recovered', () async {
      GraphClient.debugFetch = (url) async {
        if (url.contains('level%20eq%201')) {
          return (200, rows(['sub']), <String, String>{});
        }
        if (url.contains('level%20eq%202')) {
          return (200, rows(['subsub']), <String, String>{});
        }
        return (200, rows(const []), <String, String>{});
      };
      final c = GraphClient(token: () async => 't');

      expect(await c.pageLevels('s1'), {'sub': 1, 'subsub': 2});
    });

    test('it asks for ids only, not whole pages', () async {
      // The levels are joined back onto the page list by id, so asking for
      // anything else would be paying per page for something already held.
      final asked = <String>[];
      GraphClient.debugFetch = (url) async {
        asked.add(url);
        return (200, rows(const []), <String, String>{});
      };
      final c = GraphClient(token: () async => 't');
      await c.pageLevels('s1');

      expect(asked.single, contains(r'$select=id'));
      expect(asked.single, contains('level%20eq%201'));
    });

    test('a service that stops honouring the filter gets us nothing, not lies',
        () async {
      // The whole method rests on the service applying a filter it never
      // echoes back. If that ever stopped being true, every query would
      // return every page and the notebook would arrive with all of its
      // pages indented to the deepest level asked for — silently, and
      // wrongly.
      //
      // A page cannot be at two depths at once, so an overlap is proof it
      // happened. The safe answer is the one that was true before any of
      // this: flat. Better a notebook with no nesting than one with invented
      // nesting.
      GraphClient.debugFetch = (url) async =>
          (200, rows(['a', 'b', 'c']), <String, String>{});
      final c = GraphClient(token: () async => 't');

      expect(await c.pageLevels('s1'), isEmpty);
    });

    test('it never goes deeper than OneNote can nest', () async {
      // Every level costs a round trip on a service that throttles by request
      // count, so an unbounded loop would be a real cost for an impossible
      // case.
      var deepest = 0;
      GraphClient.debugFetch = (url) async {
        final m = RegExp(r'level%20eq%20(\d+)').firstMatch(url);
        if (m != null) {
          final lv = int.parse(m.group(1)!);
          if (lv > deepest) deepest = lv;
        }
        // Never empty: if the loop had no bound this would not terminate.
        return (200, rows(['p$deepest']), <String, String>{});
      };
      final c = GraphClient(token: () async => 't');
      await c.pageLevels('s1');

      expect(deepest, lessThanOrEqualTo(2));
    });
  });
}
