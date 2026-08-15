// Re-importing the same OneNote handwriting must not store it twice.
//
// Ink became content-addressed binary blobs so a 63 MB notebook of ASCII floats
// became 3 MB (`ink_codec.dart`). That only pays if identical handwriting
// produces identical bytes — and `Stroke.strokeStart` defaulted to `nowMs()`,
// which the encoder writes into the blob. So an import stamped the wall clock
// onto every stroke and the blob hashed differently every time.
//
// Measured on the owner's notebook before the fix, importing the same two
// sections twice: 82 blobs / 2,947,882 bytes, then 82 MORE blobs / 2,947,288
// bytes with not one hash shared, for stroke geometry that decoded identically.
// The duplicate lands in the container AND in the op log, which is append-only
// and never compacted.
//
// The parser gives ink no timing at all (`ImportedStroke {x, y, p, color, size,
// opacity}`), so 0 — "no time known" — is what an import states, and it is what
// makes the bytes a function of the handwriting alone.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/export/import_sink.dart';
import 'package:openote/export/onenote_import.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

/// One section, one page, two strokes — the shape the parse isolate produces.
List<dynamic> _sections() => [
      {
        'name': 'Discrete Mathematics',
        'section': {
          'pages': [
            {
              'title': 'Hasse Diagram',
              'level': 0,
              'boxes': const [],
              'ink': [
                {
                  'x': [120.5, 121.25, 123.0, 126.75],
                  'y': [96.0, 96.75, 98.5, 101.25],
                  'p': [0.42, 0.47, 0.51, 0.4],
                  'color': '#211F1B',
                  'size': 2.0,
                  'opacity': 1.0,
                },
                {
                  'x': [220.0, 224.5, 231.25],
                  'y': [180.0, 184.75, 188.0],
                  'p': [0.3, 0.55, 0.35],
                  'color': '#2E67D3',
                  'size': 3.5,
                  'opacity': 1.0,
                },
              ],
            }
          ]
        }
      }
    ];

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  test('re-importing the same handwriting reuses its ink blob rather than '
      'storing a second copy', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final tmp = Directory.systemTemp.createTempSync('onote_ink_dedup_');
    final repo = await Repository.openAt(tmp);
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {/* best-effort temp cleanup */}
    });
    final app = AppState(repo);

    // Two notebooks rather than two imports into one: a second
    // `buildNotebookFromPackage` purges the sections that preceded it, which
    // would take the first import's pages (and their `blob_refs`) with it.
    Future<({List<String> refs, List<int> starts})> importOnce(String name) async {
      final nb = await repo.createNotebook(name);
      await buildNotebookFromPackage(AppStateImportSink(app, nb.id), _sections());
      final page = repo.loadNodes(nb.id).firstWhere(
          (n) => n.kind == NodeKind.page && n.title == 'Hasse Diagram');
      final ink = repo
          .readPage(nb.id, page.id)
          .blocks
          .singleWhere((b) => b.type == BlockType.ink);
      return (
        refs: repo.blobRefsForTest(nb.id, page.id),
        starts: [
          for (final s in (ink.content['strokes'] as List))
            Stroke.fromJson((s as Map).cast<String, dynamic>()).strokeStart
        ],
      );
    }

    final first = await importOnce('Import one');
    final second = await importOnce('Import two');

    // The direct cause, asserted directly: an import states "no time known"
    // instead of reading the clock. Without this the equality below is a
    // coincidence of two imports landing in the same millisecond.
    expect(first.starts, everyElement(0),
        reason: 'imported strokes carry no fabricated timestamp');
    expect(first.starts.length, 2);

    expect(first.refs, isNotEmpty, reason: 'the ink reached a blob at all');
    expect(second.refs, first.refs,
        reason: 'identical handwriting is identical bytes, so the second '
            'import references the blob the first one wrote');
  });
}
