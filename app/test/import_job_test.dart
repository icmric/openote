// The background import (v0.9 §1): the batched writer, its cancel point, and
// the "the app stays alive" property itself.
//
// The Rust parser is not exercised here — these tests feed the writer the
// structure the parse isolate produces, which is exactly the seam the job was
// split at. The parser has its own e2e tests against real .one fixtures.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/export/import_job.dart';
import 'package:openote/export/onenote_import.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

/// A parsed page in the shape the isolate hands over.
Map<String, dynamic> page(String title, {int boxes = 1, bool tagged = false}) =>
    {
      'title': title,
      'boxes': [
        for (var i = 0; i < boxes; i++)
          {
            'kind': 'text',
            'markdown': tagged && i == 0
                ? 'What is a proposition?\n  A statement that is true or false.'
                : 'Body text $i of $title',
            'x': 60.0,
            'y': 120.0 + i * 40,
            'w': 480.0,
            'flow': 0,
            if (tagged && i == 0)
              'tags': [
                {'line': 0, 'label': 'Question'}
              ],
          }
      ],
      'images': const [],
      'ink': const [],
    };

Map<String, dynamic> section(String name, List<Map<String, dynamic>> pages,
        {String? group}) =>
    {
      'name': name,
      if (group != null) 'group': group,
      'section': {'pages': pages},
    };

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Future<(Repository, Directory, AppState, String)> fixture(
      String name) async {
    final tmp = Directory.systemTemp.createTempSync(name);
    final repo = await Repository.openAt(tmp);
    addTearDown(() async {
      await repo.flushWorkspace();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final app = AppState(repo);
    final ref = await app.importCreateNotebook('Imported');
    return (repo, tmp, app, ref.id);
  }

  group('writePackageInBatches', () {
    test('imports sections, groups and pages with the right counts', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, _, app, nb) = await fixture('onote_job_counts_');

      final r = await writePackageInBatches(app, nb, [
        section('Week 1', [page('Mon'), page('Tue', tagged: true)]),
        section('Week 2', [page('Wed')], group: 'Semester 1'),
      ]);

      expect(r.pages, 3);
      expect(r.firstPageId, isNotNull);
      final nodes = repo.loadNodes(nb);
      expect(nodes.where((n) => n.kind == NodeKind.section).length, 2);
      expect(nodes.where((n) => n.kind == NodeKind.sectionGroup).length, 1);
      expect(nodes.where((n) => n.kind == NodeKind.page).length, 3);
      // The seeded starter section is gone once real content landed.
      expect(nodes.where((n) => n.title == 'Section 1'), isEmpty);
      // The tag arrived and is findable without opening the page.
      expect(repo.pageIdsWithTags(nb), hasLength(1));
    });

    test('keeps the app responsive: the event loop runs between batches',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (_, _, app, nb) = await fixture('onote_job_yield_');

      // A 40-page section. The old writer put the whole section in one
      // synchronous transaction, so a timer armed before it could not fire
      // until every page was written — which, scaled to a real notebook, was
      // the reported "the whole app completely locks up".
      var ticks = 0;
      final timer =
          Timer.periodic(const Duration(milliseconds: 1), (_) => ticks++);
      addTearDown(timer.cancel);

      await writePackageInBatches(
        app,
        nb,
        [
          section('Big', [for (var i = 0; i < 40; i++) page('P$i', boxes: 3)])
        ],
        batchPages: 4,
      );

      expect(ticks, greaterThan(0),
          reason: 'nothing else ran during the entire import — that is the '
              'lockup this feature exists to remove');
    });

    test('cancel stops at a batch boundary, not at the end', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (_, _, app, nb) = await fixture('onote_job_cancel_');

      var written = 0;
      var cancelled = false;
      final r = await writePackageInBatches(
        app,
        nb,
        [
          section('Big', [for (var i = 0; i < 40; i++) page('P$i')])
        ],
        batchPages: 4,
        shouldCancel: () => cancelled,
        onProgress: (_, done, __) {
          written = done;
          if (done >= 8) cancelled = true;
        },
      );

      expect(r.pages, lessThan(40));
      expect(r.pages, written);
    });

    test('progress narrates pages done against the true total', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (_, _, app, nb) = await fixture('onote_job_progress_');
      final seen = <(int, int)>[];
      await writePackageInBatches(
        app,
        nb,
        [
          section('A', [for (var i = 0; i < 5; i++) page('A$i')]),
          section('B', [for (var i = 0; i < 3; i++) page('B$i')]),
        ],
        batchPages: 2,
        onProgress: (_, done, total) => seen.add((done, total)),
      );
      expect(seen.last, (8, 8));
      expect(seen.every((e) => e.$2 == 8), isTrue,
          reason: 'the denominator must be the whole package, not the section');
      expect(seen.map((e) => e.$1).toList(), List.of(seen.map((e) => e.$1))
        ..sort(), reason: 'progress never goes backwards');
    });
  });

  group('image decoding at the isolate seam', () {
    test('decodePageImagesInPlace turns base64 into bytes', () {
      final png = Uint8List.fromList(List.generate(64, (i) => i));
      final p = <String, dynamic>{
        'images': [
          {'data_base64': base64Encode(png), 'in_flow': false},
          {'data_base64': '', 'in_flow': false},
        ],
      };
      decodePageImagesInPlace(p);
      final imgs = p['images'] as List;
      expect((imgs[0] as Map)['bytes'], png);
      expect((imgs[0] as Map).containsKey('data_base64'), isFalse);
      expect((imgs[1] as Map).containsKey('bytes'), isFalse);
    });

    test('the page writer accepts bytes and base64 alike', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, _, app, nb) = await fixture('onote_job_img_');
      final png = Uint8List.fromList(List.generate(256, (i) => i % 251));

      final withBytes = page('Bytes');
      withBytes['images'] = [
        {'bytes': png, 'in_flow': false, 'x': 10.0, 'y': 120.0}
      ];
      final withB64 = page('B64');
      withB64['images'] = [
        {'data_base64': base64Encode(png), 'in_flow': false, 'x': 10.0, 'y': 120.0}
      ];

      final r = await writePackageInBatches(app, nb, [
        section('S', [withBytes, withB64])
      ]);
      expect(r.pages, 2);
      // One blob, stored once — identical bytes share a hash by design.
      expect(repo.blobIndex(nb).length, 1);
    });
  });
}
