// A picture whose bytes arrive after the page does.
//
// Reported (issue #10): *"I sometimes can't see the imported images on the
// canvas. They usually load after a minute or two or after restarting
// openote."* — from somebody syncing through a self-hosted git server, which
// is exactly the setup that produces it.
//
// The two halves of a blob travel separately: the op carries hash, mime and
// size, the bytes arrive as their own file beside the log. So a page routinely
// opens holding a reference to bytes still in flight, and `AppState.blob`
// answers null for it — correctly, and only for that moment.
//
// Nothing told the picture when the moment passed. `didUpdateWidget` re-reads
// only when the HASH changes, and a blob that is merely late keeps the same
// hash for ever, so one null read was final. The placeholder stayed until the
// State was destroyed outright — a page switch, a pull bumping `docRevision`,
// or a restart. "A minute or two" is the 60-second git cycle reloading the
// page for its own reasons; the restart is the restart.
//
// The second test is the other half of the fix and matters just as much: the
// retry must not become a read per frame. That is the page-switch stall the
// shared deferred queue exists to prevent ("about half a second or so very
// consistently"), and re-reading on every notification would hand it straight
// back — `markDirty` notifies on every keystroke.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/image_block_view.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/notebook_writer.dart' show sha256Hex;
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

/// Counts the cold reads, so "it retried" and "it retried too often" are
/// different assertions rather than the same one hopefully.
class _CountingApp extends AppState {
  _CountingApp(super.repo);

  int reads = 0;

  @override
  Uint8List? blob(String hash) {
    reads++;
    return super.blob(hash);
  }
}

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  // Two real 1x1 PNGs, DIFFERENT ones: Flutter resolves the codec for real,
  // and `_blobCache` in image_block_view.dart is static and content-addressed
  // — so a second test reusing the same bytes would silently be served from
  // the first test's cache entry and assert nothing at all. Distinct pixels,
  // distinct hashes, distinct cache keys.
  final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAF'
      'AAH/iZk9HQAAAABJRU5ErkJggg==');
  final otherPng = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYPj/HwAD'
      'AgH/5ncLrgAAAABJRU5ErkJggg==');

  late Directory tmp;
  late Repository repo;
  late _CountingApp app;
  late String hash;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_lateblob_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Late');
    app = _CountingApp(repo)..notebookId = nb.id;
    // The name the bytes WILL have. The block can reference a picture the
    // notebook does not hold yet — that is the whole situation being tested.
    hash = 'sha256:${sha256Hex(png)}';
  });

  tearDown(() async {
    AppState.syncLogEnabled = true;
    if (!haveSqlite) return;
    app.cancelPendingSave();
    await repo.flushWorkspace();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// `naturalW`/`naturalH` pre-filled so a successful read does not call
  /// `markDirty`, which arms the 700 ms save debounce the binding fails on.
  Block picture([String? h]) => Block(
      id: 'b1',
      type: BlockType.image,
      x: 0,
      y: 0,
      w: 40,
      h: 40,
      content: {'blob': h ?? hash, 'naturalW': 1.0, 'naturalH': 1.0});

  /// The read queue paces one read per event-loop turn.
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 10));
    }
  }

  /// Mounted the way the canvas mounts a block: under a listener, so every
  /// `notifyListeners` rebuilds it. Without that there is no rebuild to
  /// retry ON, and the test would be asserting about a tree the app never
  /// builds.
  Future<void> pump(WidgetTester t, Block b) async {
    // **In the test body, not in `setUp`.** The queue is static and chained,
    // and a future only completes in the zone that made it — so the
    // replacement has to be created inside this test's fake-async zone, which
    // `setUp` is not. Resetting there left every read pending for ever and the
    // picture on its spinner. See [ImageBlockView.resetReadQueue].
    ImageBlockView.resetReadQueue();
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: Scaffold(
        body: ListenableBuilder(
          listenable: app,
          builder: (_, __) => ImageBlockView(block: b, app: app),
        ),
      ),
    ));
    await settle(t);
  }

  testWidgets('bytes that arrive late are picked up, with no page switch',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(t, picture());

    expect(find.text('Missing image'), findsOneWidget,
        reason: 'precondition: the notebook does not hold these bytes yet');
    expect(find.byType(Image), findsNothing);
    final afterFirstLook = app.reads;
    expect(afterFirstLook, greaterThan(0), reason: 'it did look once');

    // **Nothing new.** Twenty notifications carrying no bytes — which is what
    // typing looks like from here, since `markDirty` notifies per keystroke.
    // Asserted BEFORE the arrival, because the cheap way to make the first
    // half of this test pass is to re-read on every rebuild, and that is the
    // page-switch stall the shared read queue exists to prevent.
    for (var i = 0; i < 20; i++) {
      app.notifyListeners();
      await t.pump(const Duration(milliseconds: 10));
    }
    await settle(t);
    expect(app.reads, afterFirstLook,
        reason: 'a cold blob read is synchronous and megabytes wide; one per '
            'frame is exactly what the read queue exists to prevent');
    expect(find.text('Missing image'), findsOneWidget);

    // **Now the bytes land.** Two separate things, kept separate on purpose:
    // the file appears, and the app learns that a file appeared. `addBlob`
    // only does the first — a local write never rescues a placeholder,
    // because every local route stores the bytes BEFORE creating the block
    // that names them, and notifying from there would fire once per ink blob
    // on every autosave. `debugBytesArrived` is the second, standing in for
    // the pull or the repair that really carries it.
    app.addBlob(png, 'image/png');
    app.debugBytesArrived();
    await settle(t);

    expect(find.byType(Image), findsOneWidget,
        reason: 'THE BUG: the placeholder stayed until the State was '
            'destroyed — a page switch, a pull, or a restart');
    expect(find.text('Missing image'), findsNothing);
    expect(app.reads, greaterThan(afterFirstLook),
        reason: 'and it looked again exactly once something had arrived');
  });

  testWidgets('and a picture that is simply there still loads at once',
      (t) async {
    // Negative control, on its OWN bytes: the retry must not have made the
    // ordinary case conditional on anything arriving.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.addBlob(otherPng, 'image/png');
    await pump(t, picture('sha256:${sha256Hex(otherPng)}'));
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Missing image'), findsNothing);
  });
}
