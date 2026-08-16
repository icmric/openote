// One unreadable image must cost exactly one placeholder — never the page.
//
// Every `ImageBlockView` funnels its cold blob read through ONE shared,
// chained queue (`_readQueue = _readQueue.then(...)`), which is what keeps a
// page switch cheap: one read per event-loop turn. The flip side of chaining
// is that a future carrying an error never runs the callbacks `.then`ed onto
// it — so a single read that threw (a file a cloud client had locked, a bad
// sector) used to poison the queue and silently blank every image loaded
// after it, page after page, for the rest of the session.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/image_block_view.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

/// An `AppState` whose blob read throws for one hash — the shape
/// `OpLogStore.readBlob` can no longer produce itself (it catches and answers
/// null), kept reachable here because `AppState.blob` also spans the engine
/// and container paths, and the queue must survive ANY of them throwing.
class _ThrowingApp extends AppState {
  _ThrowingApp(super.repo, this.goodPng);

  final Uint8List goodPng;

  @override
  Uint8List? blob(String hash) {
    if (hash == 'queue-bad') {
      throw const FileSystemException('held by a cloud client');
    }
    return goodPng;
  }
}

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  // A real 1x1 transparent PNG — Flutter resolves the codec for real, and an
  // undecodable one throws into the test.
  final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwACh'
      'wGA60e6kgAAAABJRU5ErkJggg==');

  // Built in setUp, NOT in the test body: `testWidgets` runs inside a
  // fake-async zone where `Repository.openAt`'s real file I/O never completes.
  late Repository repo;
  late Directory tmp;
  late _ThrowingApp app;

  setUp(() async {
    if (!haveSqlite) return;
    tmp = Directory.systemTemp.createTempSync('onote_imgqueue_');
    repo = await Repository.openAt(tmp);
    app = _ThrowingApp(repo, png);
  });

  tearDown(() async {
    if (!haveSqlite) return;
    app.cancelPendingSave();
    await repo.flushWorkspace();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('a throwing read costs one placeholder, not every later image',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // `naturalW`/`naturalH` pre-filled so a successful read does not call
    // `markDirty` (which arms the 700 ms save debounce — a pending timer this
    // widget test would fail on, and beside the point here).
    Block img(String id, String hash) => Block(
        id: id,
        type: BlockType.image,
        x: 0,
        y: 0,
        w: 40,
        h: 40,
        content: {'blob': hash, 'naturalW': 1.0, 'naturalH': 1.0});

    // The bad read is queued FIRST, so the good image's read is chained
    // behind the failure — the exact ordering that used to lose it.
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          ImageBlockView(block: img('b1', 'queue-bad'), app: app),
          ImageBlockView(block: img('b2', 'queue-good'), app: app),
        ]),
      ),
    ));
    // The queue paces one read per event-loop turn; give it a few.
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 10));
    }

    // MUTATION: remove the try/catch around `widget.app.blob(h)` in
    // image_block_view.dart and BOTH of these fail — the error rides the
    // shared queue, the good image never loads, and the test zone reports
    // the uncaught exception.
    expect(find.text('Missing image'), findsOneWidget,
        reason: 'the unreadable image gets its own placeholder');
    expect(find.byType(Image), findsOneWidget,
        reason: 'the image queued BEHIND the failure still loads');
  });
}
