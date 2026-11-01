// The demo notebook is a FILE now, not code — `assets/demo/demo.onote`, meant
// to be edited by opening it in Openote and copying it back. That is the whole
// point of it, and it is also the risk: nothing about replacing a binary asset
// is checked by the compiler, and the one build that reads it is the one
// nobody runs locally.
//
// So this is the floor. It does not care what the demo *says* — change the
// words freely, that is the point — only that the file is a notebook the app
// can open, with something on its pages, and that the two places the title
// lives still agree.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/model/models.dart';
import 'package:openote/store/database.dart';
import 'package:openote/store/demo_notebook.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late String path;

  setUpAll(() async {
    final bytes =
        (await rootBundle.load(kDemoNotebookAsset)).buffer.asUint8List();
    dir = Directory.systemTemp.createTempSync('onote_demo_check');
    path = '${dir.path}/demo.onote';
    File(path).writeAsBytesSync(bytes);
  });

  tearDownAll(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {
      // Windows keeps a handle on a container that was open; the temp
      // directory is the OS's problem, not this test's.
    }
  });

  test('the shipped asset is a container Openote can open', () {
    // `openOnote` rather than a raw sqlite3 open, because the question is not
    // "is this a database" but "will the app accept it" — which includes the
    // application_id and user_version checks that make a stray .db fail.
    final db = openOnote(path, notebookId: 'check', title: 'check');
    addTearDown(() => checkpointAndClose(db));

    expect(db.select('PRAGMA integrity_check;').first.columnAt(0), 'ok');

    final nodes = db.select('SELECT kind, title FROM nodes WHERE deleted_at IS NULL;');
    final sections =
        nodes.where((r) => r['kind'] == NodeKind.section.name).toList();
    final pages = nodes.where((r) => r['kind'] == NodeKind.page.name).toList();

    expect(sections, isNotEmpty, reason: 'the demo needs a section');
    expect(pages, isNotEmpty, reason: 'the demo needs at least one page');
    for (final p in pages) {
      expect((p['title'] as String).trim(), isNotEmpty,
          reason: 'an untitled page in the sidebar reads as a bug');
    }
  });

  test('its pages are not empty', () {
    final db = openOnote(path, notebookId: 'check', title: 'check');
    addTearDown(() => checkpointAndClose(db));

    // A demo whose pages are blank is worse than no demo: it is the exact
    // first impression this file exists to prevent.
    final mirrors = db.select('SELECT json FROM page_mirror;');
    expect(mirrors, isNotEmpty);
    var blocks = 0;
    for (final row in mirrors) {
      final decoded = jsonDecode(row['json'] as String) as Map<String, dynamic>;
      blocks += (decoded['blocks'] as List? ?? const []).length;
    }
    expect(blocks, greaterThan(5),
        reason: 'the demo notebook has almost nothing on it');
  });

  test('the title inside the container matches the one the sidebar shows', () {
    // Two places, by design — `adoptWorkspaceNotebook` names a notebook after
    // its file, and the container carries its own title in `notebook_meta`.
    // They are shown in different screens, so a disagreement is invisible
    // until somebody notices the app calling one notebook two things.
    final db = openOnote(path, notebookId: 'check', title: 'check');
    addTearDown(() => checkpointAndClose(db));

    final row = db.select(
        "SELECT value FROM notebook_meta WHERE key = 'title';");
    expect(row, isNotEmpty, reason: 'the container has no title');
    expect(jsonDecode(row.first['value'] as String), kDemoNotebookTitle,
        reason: 'assets/demo/demo.onote and kDemoNotebookTitle disagree — see '
            'assets/demo/README.md');
  });
}
