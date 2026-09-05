// Reading a notebook out of Graph, and writing it as it arrives.
//
// Every request is answered by a fake, so the whole import runs with no
// network and no Microsoft account. What matters most here is the PROGRESSIVE
// half: the owner's requirement was that a large notebook must not be thirty
// seconds of a frozen screen, so these pin that pages are written as sections
// land rather than all at once at the end.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/export/import_sink.dart';
import 'package:openote/model/models.dart';
import 'package:openote/onenote/graph_client.dart';
import 'package:openote/onenote/graph_import.dart';

/// A sink that records what it was told, in order.
class RecordingSink implements ImportSink {
  final List<TreeNode> written = [];
  final List<String> pageOrder = [];
  final Map<String, List<Block>> pages = {};
  final List<String> purged = [];
  int batches = 0;
  List<TreeNode> seeded = [];

  @override
  List<TreeNode> nodes() => seeded;

  @override
  TreeNode node(TreeNode n) {
    written.add(n);
    return n;
  }

  @override
  void page(String pageId, List<Block> blocks, PageProps props) {
    pageOrder.add(pageId);
    pages[pageId] = blocks;
  }

  @override
  String blob(dynamic bytes, String mime) => 'HASH${pages.length}';

  @override
  T batch<T>(T Function() body) {
    batches++;
    return body();
  }

  @override
  void purgeNode(String id) => purged.add(id);
}

/// A Graph that exists only in this file.
///
/// Keyed on a substring of the URL, so a test declares what it wants back
/// without reproducing Graph's whole query-string grammar.
GraphClient fakeGraph(Map<String, String> routes,
    {List<String>? requestLog, Map<String, int>? statuses}) {
  GraphClient.debugFetch = (url) async {
    requestLog?.add(url);
    for (final entry in routes.entries) {
      if (url.contains(entry.key)) {
        return (statuses?[entry.key] ?? 200, entry.value, <String, String>{});
      }
    }
    return (404, '{"error":"no route"}', <String, String>{});
  };
  return GraphClient(token: () async => 'TOKEN');
}

String listOf(List<Map<String, dynamic>> value, {String? next}) => jsonEncode({
      'value': value,
      if (next != null) '@odata.nextLink': next,
    });

String pageHtml(String body) =>
    '<html><body data-absolute-enabled="true">'
    '<div style="position:absolute;left:48px;top:90px;width:600px">$body</div>'
    '</body></html>';

void main() {
  tearDown(() => GraphClient.debugFetch = null);

  group('listing', () {
    test('notebooks come back named', () async {
      final c = fakeGraph({
        '/notebooks?': listOf([
          {'id': 'nb1', 'displayName': 'Physics'},
          {'id': 'nb2', 'displayName': 'History'},
        ]),
      });
      final got = await c.notebooks();
      expect(got.map((n) => n.name), ['Physics', 'History']);
    });

    test('a notebook with no name is not blank in the picker', () async {
      final c = fakeGraph({
        '/notebooks?': listOf([
          {'id': 'nb1', 'displayName': '  '}
        ]),
      });
      expect((await c.notebooks()).single.name, 'Untitled notebook');
    });

    test('sections inside section groups are found and keep their path',
        () async {
      // The bug this stops: reading only the notebook's top-level sections
      // silently imports a fraction of a notebook that uses groups, which is
      // most real ones.
      final c = fakeGraph({
        '/notebooks/nb1/sections?': listOf([
          {'id': 's1', 'displayName': 'Loose'}
        ]),
        '/notebooks/nb1/sectionGroups?': listOf([
          {'id': 'g1', 'displayName': 'Y1'}
        ]),
        '/sectionGroups/g1/sections?': listOf([
          {'id': 's2', 'displayName': 'Term 1'}
        ]),
        '/sectionGroups/g1/sectionGroups?': listOf([
          {'id': 'g2', 'displayName': 'S2'}
        ]),
        '/sectionGroups/g2/sections?': listOf([
          {'id': 's3', 'displayName': 'Term 2'}
        ]),
        '/sectionGroups/g2/sectionGroups?': listOf([]),
      });
      final got = await c.sections('nb1');
      expect(got.map((s) => s.name), ['Loose', 'Term 1', 'Term 2']);
      expect(got.map((s) => s.groupPath), ['', 'Y1', 'Y1/S2']);
    });

    test('paging is followed to the end', () async {
      // Graph caps a page of results at 100 and hands back a nextLink.
      // Ignoring it imports the first hundred pages of a section and nothing
      // else, with no error anywhere.
      var served = 0;
      GraphClient.debugFetch = (url) async {
        served++;
        if (url.contains('cursor=2')) {
          return (200, listOf([
            {'id': 'p3', 'title': 'Three'}
          ]), <String, String>{});
        }
        return (200, listOf([
          {'id': 'p1', 'title': 'One'},
          {'id': 'p2', 'title': 'Two'},
        ], next: 'https://graph.microsoft.com/v1.0/me/onenote/x?cursor=2'),
            <String, String>{});
      };
      final c = GraphClient(token: () async => 'T');
      final pages = await c.pages('s1');
      expect(pages.map((p) => p.title), ['One', 'Two', 'Three']);
      expect(served, 2);
    });
  });

  group('throttling', () {
    test('a 429 is retried rather than failing the import', () async {
      // OneNote's endpoints throttle harder than most of Graph, and a
      // five-year notebook is hundreds of requests. Giving up on the first
      // 429 would make a large import impossible.
      var calls = 0;
      GraphClient.debugFetch = (url) async {
        calls++;
        if (calls == 1) {
          return (429, '', {'retry-after': '0'});
        }
        return (200, listOf([
          {'id': 'nb1', 'displayName': 'Physics'}
        ]), <String, String>{});
      };
      final c = GraphClient(token: () async => 'T');
      expect((await c.notebooks()).single.name, 'Physics');
      expect(calls, 2);
    });

    test('a hard failure is a sentence, not a status code', () async {
      GraphClient.debugFetch =
          (url) async => (401, '', <String, String>{});
      final c = GraphClient(token: () async => 'T');
      await expectLater(
          c.notebooks(),
          throwsA(isA<GraphException>().having((e) => e.message, 'message',
              contains('sign-in has expired'))));
    });
  });

  group('importing, progressively', () {
    /// Two sections of two pages each.
    GraphClient twoSections({List<String>? log}) => fakeGraph({
          '/notebooks/nb1/sections?': listOf([
            {'id': 's1', 'displayName': 'Week 1'},
            {'id': 's2', 'displayName': 'Week 2'},
          ]),
          '/notebooks/nb1/sectionGroups?': listOf([]),
          '/sections/s1/pages': listOf([
            {'id': 'p1', 'title': 'Intro'},
            {'id': 'p2', 'title': 'Notes'},
          ]),
          '/sections/s2/pages': listOf([
            {'id': 'p3', 'title': 'More'},
            {'id': 'p4', 'title': 'End'},
          ]),
          '/pages/p1/content': pageHtml('<p>one</p>'),
          '/pages/p2/content': pageHtml('<p>two</p>'),
          '/pages/p3/content': pageHtml('<p>three</p>'),
          '/pages/p4/content': pageHtml('<p>four</p>'),
        }, requestLog: log);

    test('every page lands, under the right section', () async {
      final sink = RecordingSink();
      final result = await importNotebookFromGraph(
        client: twoSections(),
        notebookId: 'nb1',
        sink: sink,
      );
      expect(result.pages, 4);
      expect(result.sections, 2);
      final sections =
          sink.written.where((n) => n.kind == NodeKind.section).toList();
      expect(sections.map((n) => n.title), ['Week 1', 'Week 2']);
      final pages = sink.written.where((n) => n.kind == NodeKind.page).toList();
      expect(pages.map((n) => n.title), ['Intro', 'Notes', 'More', 'End']);
      // Each page under its own section, not all under the first.
      expect(pages[0].parentId, sections[0].id);
      expect(pages[3].parentId, sections[1].id);
    });

    test('a section is written BEFORE the next one is fetched', () async {
      // The whole point. If the import gathered everything and wrote at the
      // end, the student would watch nothing happen for the entire download.
      final log = <String>[];
      final sink = RecordingSink();
      final order = <String>[];
      await importNotebookFromGraph(
        client: twoSections(log: log),
        notebookId: 'nb1',
        sink: sink,
        onProgress: (p) => order.add('progress:${p.sectionName}'),
      );
      // Week 1's pages were reported done before Week 2's pages were asked
      // for at all.
      final firstWeek2Fetch =
          log.indexWhere((u) => u.contains('/sections/s2/pages'));
      final firstWeek1Progress = order.indexOf('progress:Week 1');
      expect(firstWeek1Progress, isNonNegative);
      expect(firstWeek2Fetch, isNonNegative);
      expect(order.first, 'progress:Week 1',
          reason: 'the first section must be reported before the second runs');
    });

    test('progress is reported more than once for a multi-batch section',
        () async {
      final sink = RecordingSink();
      final seen = <int>[];
      // Sized from the constant, not from a number that happened to be
      // bigger than it: when the batch grew from 3 to 12 for concurrency, a
      // hard-coded 7 quietly became a SINGLE batch and this stopped testing
      // anything.
      const count = kGraphBatchPages * 2 + 1;
      final many = [
        for (var i = 0; i < count; i++) {'id': 'p$i', 'title': 'Page $i'}
      ];
      final routes = <String, String>{
        '/notebooks/nb1/sections?': listOf([
          {'id': 's1', 'displayName': 'Big'}
        ]),
        '/notebooks/nb1/sectionGroups?': listOf([]),
        '/sections/s1/pages': listOf(many),
        for (var i = 0; i < count; i++)
          '/pages/p$i/content': pageHtml('<p>page $i</p>'),
      };
      await importNotebookFromGraph(
        client: fakeGraph(routes),
        notebookId: 'nb1',
        sink: sink,
        onProgress: (p) => seen.add(p.pagesDone),
      );
      // Seven pages at three per batch: the student sees the count climb
      // rather than jumping from nothing to done.
      expect(seen.length, greaterThan(1));
      expect(seen.last, count);
    });

    test('sections keep the order OneNote gave them, however the '
        'network answers',
        () async {
      // The requests go out together now, so the order they come BACK in is
      // whatever the network decides. Appending to one shared list as replies
      // landed would shuffle a student's sections differently on every import
      // and never match OneNote.
      final sink = RecordingSink();
      await importNotebookFromGraph(
        client: fakeGraph({
          '/notebooks/nb1/sections?': listOf([
            {'id': 's1', 'displayName': 'Loose'}
          ]),
          '/notebooks/nb1/sectionGroups?': listOf([
            {'id': 'g1', 'displayName': 'Y1'}
          ]),
          '/sectionGroups/g1/sections?': listOf([
            {'id': 's2', 'displayName': 'Term 1'},
            {'id': 's3', 'displayName': 'Term 2'},
          ]),
          '/sectionGroups/g1/sectionGroups?': listOf([]),
          '/sections/s1/pages': listOf([
            {'id': 'p1', 'title': 'A'}
          ]),
          '/sections/s2/pages': listOf([
            {'id': 'p2', 'title': 'B'}
          ]),
          '/sections/s3/pages': listOf([
            {'id': 'p3', 'title': 'C'}
          ]),
          '/pages/p1/content': pageHtml('<p>a</p>'),
          '/pages/p2/content': pageHtml('<p>b</p>'),
          '/pages/p3/content': pageHtml('<p>c</p>'),
        }),
        notebookId: 'nb1',
        sink: sink,
      );
      expect(
          sink.written
              .where((n) => n.kind == NodeKind.section)
              .map((n) => n.title),
          ['Loose', 'Term 1', 'Term 2']);
    });

    test('one unreadable page does not end the import', () async {
      // A five-year notebook with one bad page must not lose the other 400.
      final routes = <String, String>{
        '/notebooks/nb1/sections?': listOf([
          {'id': 's1', 'displayName': 'Week 1'}
        ]),
        '/notebooks/nb1/sectionGroups?': listOf([]),
        '/sections/s1/pages': listOf([
          {'id': 'p1', 'title': 'Good'},
          {'id': 'p2', 'title': 'Bad'},
          {'id': 'p3', 'title': 'Also good'},
        ]),
        '/pages/p1/content': pageHtml('<p>one</p>'),
        '/pages/p3/content': pageHtml('<p>three</p>'),
      };
      final sink = RecordingSink();
      final result = await importNotebookFromGraph(
        client: fakeGraph(routes, statuses: {'/pages/p2/content': 500}),
        notebookId: 'nb1',
        sink: sink,
      );
      expect(result.pages, 2);
      expect(
          sink.written
              .where((n) => n.kind == NodeKind.page)
              .map((n) => n.title),
          ['Good', 'Also good']);
    });

    test('cancelling stops within a batch and keeps what landed', () async {
      var stop = false;
      final sink = RecordingSink();
      final result = await importNotebookFromGraph(
        client: twoSections(),
        notebookId: 'nb1',
        sink: sink,
        onProgress: (_) => stop = true,
        shouldCancel: () => stop,
      );
      expect(result.cancelled, isTrue);
      // What arrived before the stop is kept — a cancel is not a rollback of
      // the pages already on screen.
      expect(result.pages, greaterThan(0));
      expect(result.pages, lessThan(4));
    });

    test('the starter section is removed only once real pages exist',
        () async {
      final sink = RecordingSink()
        ..seeded = [
          TreeNode(kind: NodeKind.section, title: 'My Section', position: 'a')
        ];
      await importNotebookFromGraph(
        client: twoSections(),
        notebookId: 'nb1',
        sink: sink,
      );
      expect(sink.purged, hasLength(1));
    });

    test('an import that brought nothing leaves the starter section alone',
        () async {
      // Otherwise a failed import produces a notebook with nothing in it at
      // all, which reads as "it deleted my stuff".
      final sink = RecordingSink()
        ..seeded = [
          TreeNode(kind: NodeKind.section, title: 'My Section', position: 'a')
        ];
      final result = await importNotebookFromGraph(
        client: fakeGraph({
          '/notebooks/nb1/sections?': listOf([]),
          '/notebooks/nb1/sectionGroups?': listOf([]),
        }),
        notebookId: 'nb1',
        sink: sink,
      );
      expect(result.pages, 0);
      expect(sink.purged, isEmpty);
    });

    test('a section group becomes a group node', () async {
      final sink = RecordingSink();
      await importNotebookFromGraph(
        client: fakeGraph({
          '/notebooks/nb1/sections?': listOf([]),
          '/notebooks/nb1/sectionGroups?': listOf([
            {'id': 'g1', 'displayName': 'Y1'}
          ]),
          '/sectionGroups/g1/sections?': listOf([
            {'id': 's1', 'displayName': 'Term 1'}
          ]),
          '/sectionGroups/g1/sectionGroups?': listOf([]),
          '/sections/s1/pages': listOf([
            {'id': 'p1', 'title': 'Intro'}
          ]),
          '/pages/p1/content': pageHtml('<p>hi</p>'),
        }),
        notebookId: 'nb1',
        sink: sink,
      );
      final group =
          sink.written.firstWhere((n) => n.kind == NodeKind.sectionGroup);
      expect(group.title, 'Y1');
      final section =
          sink.written.firstWhere((n) => n.kind == NodeKind.section);
      expect(section.parentId, group.id);
    });
  });
}
