// Reclaiming the space of videos no page references — and, far more of this
// file, NOT reclaiming the space of videos something still does.
//
// "Space used by videos whose block you deleted is not reclaimed
// automatically" (0.4.2 known gaps). The reason it was left is written into
// `media_store.dart`: a sweep has to enumerate every reference across live
// pages, trashed pages and the op log, "and getting that scan wrong deletes a
// lecture that undo cannot bring back".
//
// This project has shipped that bug three times — a9e584a and 3630eb6 deleted
// ink because a scan asked a structural question the structure had moved on
// from, and 7851c3d deleted the OTHER DEVICE'S data because the check could
// only see this workspace. So the shape of this file is deliberate: one test
// reclaims, and a dozen prove that a video in each of the places a reference
// can hide is still on disk, byte for byte, afterwards.
//
// Every fixture video is filled with a distinct byte so "it survived" can be
// checked as "these are the same bytes" rather than "a file of about the right
// size is still there".
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openote/model/history.dart' show kRecentDeletionsKept;
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/media_gc.dart';
import 'package:openote/store/media_store.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late NotebookRef ref;
  late String nb;
  late String sectionId;

  /// Fixture videos, by the label this file calls them, so a failure names the
  /// reference source rather than a UUID.
  late Map<String, String> stored; // label -> stored name
  late Map<String, int> fill; // label -> the byte it is filled with

  setUp(() async {
    if (!haveSqlite) return;
    tmp = Directory.systemTemp.createTempSync('onote_reclaim_');
    repo = await Repository.openAt(tmp);
    final created = await repo.createNotebook('Lectures');
    nb = created.id;
    ref = repo.notebooks.firstWhere((n) => n.id == nb);
    sectionId = repo
        .loadNodes(nb)
        .firstWhere((n) => n.kind == NodeKind.section)
        .id;
    stored = {};
    fill = {};
  });

  tearDown(() {
    if (!haveSqlite) return;
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// A stored video of [bytes] bytes, every byte [byteValue], backdated so the
  /// age floor is not what is under test.
  Future<String> video(String label, int byteValue,
      {int bytes = 2048, Duration age = const Duration(days: 90)}) async {
    final src = File(p.join(tmp.path, 'src_$label.mp4'))
      ..writeAsBytesSync(Uint8List(bytes)..fillRange(0, bytes, byteValue));
    final name = await MediaStore.add(ref, src);
    src.deleteSync();
    MediaStore.resolve(ref, name)!
        .setLastModifiedSync(DateTime.now().subtract(age));
    stored[label] = name;
    fill[label] = byteValue;
    return name;
  }

  Block videoBlock(String name) => Block(
      type: BlockType.file,
      x: 0,
      y: 0,
      content: {
        'kind': 'video',
        'media': name,
        'name': 'Lecture.mp4',
        'mime': 'video/mp4',
        'size': 2048,
      });

  String newPage(String title, List<Block> blocks) {
    final page = repo.upsertNode(
        nb, TreeNode(kind: NodeKind.page, parentId: sectionId, title: title));
    repo.writePage(nb, page.id, blocks, PageProps());
    return page.id;
  }

  /// A raw op-log line naming [media], as `SyncRecorder.page` writes one.
  void appendOp(String device, String media) {
    final dir = Directory(p.join(ref.logDirPath, 'ops'))
      ..createSync(recursive: true);
    final line = jsonEncode({
      'v': 1,
      'dev': device,
      'seq': 1,
      'lc': 1,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'op': 'block.set',
      'd': {
        'pageId': 'some-page',
        'block': {
          'type': 'file',
          'content': {'kind': 'video', 'media': media},
        },
      },
    });
    File(p.join(dir.path, '$device.oplog'))
        .writeAsStringSync('$line\n', mode: FileMode.append);
  }

  Future<VideoSweep> sweep({Iterable<String> live = const []}) => MediaGc.sweep(
        ref: ref,
        containerText: () => repo.everyStoredPageText(nb),
        liveText: () => live,
      );

  /// The bytes on disk for [label], or null if the file is gone.
  Uint8List? bytesOf(String label) {
    final f = MediaStore.resolve(ref, stored[label]!);
    return f?.readAsBytesSync();
  }

  /// Fails if [label] is not still on disk, unchanged.
  void expectSurvived(String label, {required String because}) {
    final b = bytesOf(label);
    expect(b, isNotNull,
        reason: 'RECLAIM DELETED A REFERENCED VIDEO — $because');
    expect(b!.length, 2048, reason: 'truncated: $because');
    expect(b.every((x) => x == fill[label]), isTrue,
        reason: 'bytes changed: $because');
  }

  group('what the sweep will not touch', () {
    // The negative control, and the reason this feature was left unbuilt for
    // three releases. Each of these videos is referenced from exactly ONE
    // place, and that place is the only thing standing between the file and
    // deletion. If any assertion in here fails, a student has lost a lecture.
    test('a video referenced from anywhere at all survives, byte for byte',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');

      await video('live', 0x11);
      await video('trashed', 0x22);
      await video('deletionList', 0x33);
      await video('thisDevice', 0x44);
      await video('otherDevice', 0x55);
      await video('template', 0x66);
      await video('undo', 0x77);
      await video('clipboard', 0x88);
      await video('onScreen', 0x99);
      await video('orphan', 0xAA);

      // 1. A live page.
      newPage('Live', [videoBlock(stored['live']!)]);

      // 2. A page in the recycle bin. Soft delete stamps `deleted_at` and
      //    leaves the content row alone; the page comes back for 30 days.
      final trashed = newPage('Trashed', [videoBlock(stored['trashed']!)]);
      repo.softDeleteNode(nb, trashed);

      // 3. The ten-deep notable-deletions list ONLY: the page held the video and
      //    the block was taken out, so the list offers "put it back" and the
      //    bytes are still owed.
      //
      //    **This source replaced a much bigger one** (v0.17 plan, decision 1).
      //    It used to be a `page_versions` snapshot — the page held the video,
      //    was snapshotted, and the block was removed — and the plan's own list
      //    of prune sites did not mention this test at all. A snapshot was
      //    evicted only by thirty NEWER snapshots of the same page, so a video
      //    on a page the student stopped editing was pinned for ever, and on a
      //    single-device notebook it was the only pin, because the sweep skips
      //    this device's own log. Ten entries is a bound; thirty-per-page was
      //    not. The pin is fed in here through `liveText` exactly as
      //    `AppState._volatileMediaText` yields it, and that AppState really
      //    does yield it is pinned by "THE story" below.
      newPage('Deleted from here', const []);

      // 4/5. The op log — this device's, and ANOTHER DEVICE'S. The second is
      //    7851c3d exactly: in a folder-shared notebook the other machine's
      //    log and the other machine's videos are both in this directory, and
      //    a sweep that only asks this workspace deletes them.
      appendOp('device-a', stored['thisDevice']!);
      appendOp('device-b', stored['otherDevice']!);

      // 6/7/8/9. The four sources that are not in the container at all, in the
      //    shape `AppState._volatileMediaText` yields them: a workspace
      //    template (saved outside any notebook, appliable into any of them),
      //    the undo stack, the block clipboard, and the blocks on screen
      //    during the save debounce. That AppState really does gather each of
      //    these is what the "through AppState" group below pins; here they
      //    are fed in directly so that a failure means the SCAN missed one.
      final template = jsonEncode({
        'page': PageProps().toJson(),
        'blocks': [videoBlock(stored['template']!).toJson()],
      });
      repo.setSetting('templates', {'Lecture page': template});
      final live = [
        template,
        // Source 3: the deletion list's `pins`, which AppState yields as one
        // newline-joined string of stored media names.
        stored['deletionList']!,
        jsonEncode({
          'blocks': [videoBlock(stored['undo']!).toJson()]
        }),
        jsonEncode([videoBlock(stored['clipboard']!).toJson()]),
        jsonEncode({
          'blocks': [videoBlock(stored['onScreen']!).toJson()]
        }),
      ];

      final before = MediaStore.totalBytes(ref);
      expect(before, 10 * 2048, reason: 'ten videos, 2 KB each');

      final s = await sweep(live: live);
      expect(s.refusal, isNull);
      // Named by the reference source, not by UUID: a failure here has to say
      // WHICH place the scan stopped seeing.
      final byName = {for (final e in stored.entries) e.value: e.key};
      expect(s.unused.map((u) => byName[u.name]).toList(), ['orphan'],
          reason: 'exactly one video is unreferenced');

      final freed = MediaGc.reclaim(s.unused);
      expect(freed, 2048);

      expectSurvived('live', because: 'it is on a live page');
      expectSurvived('trashed', because: 'its page is in the recycle bin');
      expectSurvived('deletionList',
          because: 'the last ten deletions can still put it back');
      expectSurvived('thisDevice', because: "this device's op log names it");
      expectSurvived('otherDevice',
          because: "ANOTHER DEVICE'S op log names it (7851c3d)");
      expectSurvived('template', because: 'a workspace template names it');
      expectSurvived('undo', because: 'undo can bring the block back');
      expectSurvived('clipboard', because: 'it is on the block clipboard');
      expectSurvived('onScreen', because: 'it is on screen, not yet saved');

      expect(MediaStore.resolve(ref, stored['orphan']!), isNull,
          reason: 'the unreferenced one did go');
      expect(MediaStore.totalBytes(ref), 9 * 2048);
      expect(before - MediaStore.totalBytes(ref), 2048);
    });

    test('a copy still in flight is never a candidate', () async {
      // `MediaStore.add` writes `<name>.part` and renames on success, so a
      // `.part` is the gigabyte whose progress bar the user is watching. It
      // has no reference because it is not finished yet — the one case where
      // "unreferenced" is guaranteed to be the wrong conclusion.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final dir = MediaStore.dirFor(ref)..createSync(recursive: true);
      final part = File(p.join(dir.path, 'half-a-lecture.mp4.part'))
        ..writeAsBytesSync(Uint8List(4096))
        ..setLastModifiedSync(DateTime.now().subtract(const Duration(days: 90)));

      final s = await sweep();
      expect(s.unused, isEmpty);
      MediaGc.reclaim(s.unused);
      expect(part.existsSync(), isTrue);
    });

    test('a video younger than the age floor is left alone', () async {
      // The window where a reference legitimately does not exist yet: the save
      // debounce, and a folder-shared notebook where the other computer's file
      // has arrived from the sync client but its op-log line has not.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await video('fresh', 0x01, age: const Duration(days: 3));
      final s = await sweep();
      expect(s.unused, isEmpty);
      expect(s.keptFiles, 1);
      expect(s.keptBytes, 2048);
    });

    test('the floor is thirty days, the same promise as the recycle bin', () {
      expect(kVideoReclaimMinimumAge, const Duration(days: 30));
      expect(kVideoReclaimMinimumAge.inDays, Repository.recycleRetentionDays);
    });

    test('a source that cannot be read reclaims nothing and says so', () async {
      // "No evidence is not evidence of absence" — the closing rule of both
      // ink-deletion fixes. A locked container or an undownloaded cloud
      // placeholder must never read as "no reference found".
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await video('orphan', 0xAA);
      final s = await MediaGc.sweep(
        ref: ref,
        containerText: () sync* {
          throw const FileSystemException('database is locked');
        },
        liveText: () => const [],
      );
      expect(s.unused, isEmpty);
      expect(s.refusal, isNotNull);
      expect(s.refusal, contains('nothing was removed'));
      expect(MediaGc.reclaim(s.unused), 0);
      expectSurvived('orphan', because: 'the scan could not finish');
    });

    test('a reference lying across a chunk boundary is still found', () async {
      // The op log is read a megabyte at a time so a 64 MB scan does not
      // freeze the app. A name that straddles one of those boundaries is in
      // neither chunk, and the cost of missing it is not a slow scan — it is
      // a deleted lecture. The carried tail exists for this, and this test is
      // the only thing that proves the tail is long enough.
      //
      // Every offset across a boundary is tried, because "it worked when I
      // split it in the middle" is exactly the test that passes while the
      // off-by-one at the edge still deletes.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final original = MediaGc.chunkBytes;
      MediaGc.chunkBytes = 512;
      addTearDown(() => MediaGc.chunkBytes = original);

      final name = await video('straddling', 0xEE);
      final ops = Directory(p.join(ref.logDirPath, 'ops'))
        ..createSync(recursive: true);
      final log = File(p.join(ops.path, 'device-a.oplog'));

      for (var split = 1; split < name.length; split++) {
        // Put the name so that `split` of its characters land in the first
        // chunk and the rest in the second.
        final pad = 512 - split;
        log.writeAsStringSync('${'.' * pad}$name\n');
        final s = await sweep();
        expect(s.unused, isEmpty,
            reason: 'RECLAIM DELETED A REFERENCED VIDEO — the name was split '
                '$split/${name.length - split} across a chunk boundary');
      }
    });

    test('a name the store would not resolve is not a name we delete',
        () async {
      // Anything else in this directory is not ours: the user may be syncing
      // it with tools of their own, and a name `MediaStore.resolve` refuses is
      // one no block can be pointing at through any path we support.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final dir = MediaStore.dirFor(ref)..createSync(recursive: true);
      final theirs = File(p.join(dir.path, '.DS_Store'))
        ..writeAsBytesSync(Uint8List(64))
        ..setLastModifiedSync(DateTime.now().subtract(const Duration(days: 90)));
      final s = await sweep();
      expect(s.unused, isEmpty);
      MediaGc.reclaim(s.unused);
      expect(theirs.existsSync(), isTrue);
    });
  });

  group('what it does reclaim', () {
    test('the space of a video whose block was deleted', () async {
      // The ask. A page held a lecture, the block was deleted, the page was
      // saved — and until now the gigabyte stayed on disk for ever.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await video('gone', 0x5A, bytes: 8192);
      final page = newPage('Lecture 1', [videoBlock(stored['gone']!)]);
      expect(MediaStore.totalBytes(ref), 8192);

      // The block is removed and the page saved. Nothing else in this notebook
      // ever named it — no snapshot, no op log, no template.
      repo.writePage(nb, page, [], PageProps());

      final s = await sweep();
      expect(s.unused.length, 1);
      expect(s.freeableBytes, 8192);
      expect(MediaGc.reclaim(s.unused), 8192);
      expect(MediaStore.totalBytes(ref), 0);
    });

    test('nothing to reclaim is reported as what is still in use', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await video('live', 0x11);
      newPage('Live', [videoBlock(stored['live']!)]);
      final s = await sweep();
      expect(s.unused, isEmpty);
      expect(s.freeableBytes, 0);
      expect(s.keptFiles, 0, reason: 'it was a candidate, just not an unused one');
      // The honest answer to "can I get space back?" is "no, all 2 KB of it is
      // still in your notes" — different from "you have no videos".
      expect(MediaStore.totalBytes(ref), 2048);
    });

    test('a partial reference is not a reference', () async {
      // The scan matches the whole stored name. A file whose name merely
      // starts the same way as one that IS referenced must still be found.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await video('orphan', 0xAA);
      newPage('Live', [
        Block(type: BlockType.text, x: 0, y: 0, content: {
          'text': stored['orphan']!.substring(0, 8),
        })
      ]);
      final s = await sweep();
      expect(s.unused.length, 1, reason: 'a prefix is not the name');
    });
  });

  group('when it declines to run at all', () {
    // The container and the log have to agree about what exists before the
    // question can be asked. Each of these is a state where they do not.
    test('unsaved edits are a refusal, not a verdict', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = AppState(repo)..notebookId = nb;
      addTearDown(app.cancelPendingSave);
      await video('orphan', 0xAA);
      app.markDirty();

      final s = await app.findUnusedVideos(nb);
      expect(s.unused, isEmpty);
      expect(s.refusal, contains('still saving'));
      expectSurvived('orphan', because: 'the notebook had unsaved edits');
    });

    test('an unknown notebook reclaims nothing', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = AppState(repo)..notebookId = nb;
      addTearDown(app.cancelPendingSave);
      final s = await app.findUnusedVideos('no-such-notebook');
      expect(s.unused, isEmpty);
      expect(s.refusal, isNull);
    });
  });

  group('through AppState, on a real notebook', () {
    test('the templates a user saved are consulted even from another notebook',
        () async {
      // Templates are workspace-global: one saved from THIS notebook's page
      // carries a name that only resolves here, and it can be applied into any
      // other notebook. The container knows nothing about it.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = AppState(repo)..notebookId = nb;
      addTearDown(app.cancelPendingSave);
      await video('template', 0x66);
      repo.setSetting('templates', {
        'Lecture page': jsonEncode({
          'page': PageProps().toJson(),
          'blocks': [videoBlock(stored['template']!).toJson()],
        }),
      });

      final s = await app.findUnusedVideos(nb);
      expect(s.refusal, isNull);
      expect(s.unused, isEmpty);
      await app.deleteUnusedVideos(s.unused);
      expectSurvived('template', because: 'a workspace template names it');
    });

    test('undo alone is enough to keep a video', () async {
      // The story that makes an eager sweep destructive, set up so that the
      // UNDO STACK IS THE ONLY THING holding the file. The block is added and
      // removed between two saves, so it never reaches the page mirror, never
      // reaches a version snapshot and is never recorded as a `block.set` —
      // every durable source says the video is unused, and every one of them
      // is wrong, because Ctrl+Z is one keystroke away.
      //
      // Isolation is the point. An earlier version of this test wrote the
      // block to the container first, and then passed even with undo removed
      // from the scan: the version snapshot was quietly doing the work.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = AppState(repo)..notebookId = nb;
      addTearDown(app.cancelPendingSave);
      await video('undone', 0xC3);

      final page = newPage('Lecture 1', const []);
      await app.selectPage(page);
      await app.flushSave(); // a clean baseline that names nothing

      app.addBlock(videoBlock(stored['undone']!));
      app.select(app.blocks.first.id);
      app.removeSelected(); // Del — pushes the page onto the undo stack
      await app.flushSave();

      final s = await app.findUnusedVideos(nb);
      expect(s.refusal, isNull);
      expect(s.unused, isEmpty, reason: 'undo can still bring the block back');
      await app.deleteUnusedVideos(s.unused);
      expectSurvived('undone', because: 'the user can still press Ctrl+Z');

      // And it really does come back, to the same file.
      app.undo();
      expect(app.blocks.single.content['media'], stored['undone']);
      expect(MediaStore.resolve(ref, stored['undone']!), isNotNull);
    });

    test('the block clipboard alone is enough to keep a video', () async {
      // The clipboard is never cleared — not by switching page, not by
      // switching notebook — so a video cut hours ago is still pasteable. Undo
      // is cleared here (by moving to another page) precisely so that the
      // clipboard is the only holder left.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = AppState(repo)..notebookId = nb;
      addTearDown(app.cancelPendingSave);
      await video('cut', 0xD4);

      final page = newPage('Lecture 1', const []);
      final elsewhere = newPage('Somewhere else', const []);
      await app.selectPage(page);
      await app.flushSave();

      app.addBlock(videoBlock(stored['cut']!));
      app.select(app.blocks.first.id);
      app.cutSelectedBlocks(); // Ctrl+X
      await app.flushSave();
      await app.selectPage(elsewhere); // clears undo and redo

      expect(app.canPasteBlocks, isTrue, reason: 'still pasteable');
      final s = await app.findUnusedVideos(nb);
      expect(s.unused, isEmpty, reason: 'the clipboard still names it');
      await app.deleteUnusedVideos(s.unused);
      expectSurvived('cut', because: 'it can still be pasted');
    });

    test('THE story: a video deleted from a saved page is held for ten '
        'deletions, then reclaimed', () async {
      // Put a lecture on a page, save, delete it weeks later, save. This is
      // what the button is for, and measuring it is what caught the design
      // being useless: the op log is append-only and nothing compacts it, so
      // this device's own log STILL names the video after the block is gone.
      // Counting that as a reference pinned every video that had ever been on
      // a saved page — the whole feature reclaimed nothing at all.
      //
      // **What changed, and why this test grew a second half (v0.17 Step 8a).**
      // A deleted video is now held by the ten-deep notable-deletions list,
      // deliberately: that list offers "put it back", and a restore that
      // returns a page with a hole in it is worse than no restore. So the pin
      // is real — and, unlike `page_versions`, it is BOUNDED. Ten more notable
      // deletions push the entry out and the bytes become reclaimable, where a
      // snapshot was evicted only by thirty newer snapshots of the same page
      // and therefore pinned a video on a page you stopped editing FOR EVER.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = AppState(repo)..notebookId = nb;
      addTearDown(app.cancelPendingSave);
      await video('finished', 0x3C, bytes: 4096);

      final page = newPage('Week 1', const []);
      await app.selectPage(page);
      app.addBlock(videoBlock(stored['finished']!));
      await app.flushSave(); // the video is on a SAVED page

      app.select(app.blocks.first.id);
      app.removeSelected();
      await app.flushSave();
      await app.selectPage(page); // clears undo, the way switching page does

      // The two facts that make this test worth having.
      final ops = Directory(p.join(ref.logDirPath, 'ops'));
      expect(
          ops
              .listSync()
              .whereType<File>()
              .any((f) => f.readAsStringSync().contains(stored['finished']!)),
          isTrue,
          reason: 'our own log still names it, and always will');
      expect(repo.everyStoredPageText(nb).any((t) => t.contains(stored['finished']!)),
          isFalse,
          reason: 'the container does not');

      // Half one: it is on the "recently deleted" list, so it is held.
      await app.refreshHistory(nb);
      expect(app.recentDeletions().map((d) => d.pins).expand((p) => p),
          contains(stored['finished']!));
      var s = await app.findUnusedVideos(nb);
      expect(s.refusal, isNull);
      expect(s.unused, isEmpty,
          reason: 'the deletions list can still put it back');

      // Half two: ten more notable deletions, and the entry is gone.
      for (var i = 0; i < kRecentDeletionsKept; i++) {
        app.blocks = [
          Block(
              id: 'push$i',
              type: BlockType.image,
              x: 0,
              y: 0,
              content: {'blob': 'sha256:push$i'})
        ];
        app.markDirty();
        await app.flushSave();
        app.blocks = [];
        app.markDirty();
        await app.flushSave();
      }
      expect(app.recentDeletions().map((d) => d.pins).expand((p) => p),
          isNot(contains(stored['finished']!)),
          reason: 'the cap is the prune — ten rows cannot leak');

      s = await app.findUnusedVideos(nb);
      expect(s.refusal, isNull);
      expect(s.unused.length, 1, reason: 'so it IS reclaimable');
      expect(await app.deleteUnusedVideos(s.unused), 4096);
      expect((await app.storageFor(nb)).mediaBytes, 0);
    });

    test("another computer's log still pins a video ours would release",
        () async {
      // The other half of the same rule. Our own log is history; a log we did
      // not write may hold something our container has not caught up with, and
      // that one is read in full — 7851c3d, where deleting on this
      // workspace's evidence alone destroyed the other device's data.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = AppState(repo)..notebookId = nb;
      addTearDown(app.cancelPendingSave);
      await video('theirs', 0x9F);
      appendOp('some-other-computer', stored['theirs']!);

      final s = await app.findUnusedVideos(nb);
      expect(s.unused, isEmpty);
      await app.deleteUnusedVideos(s.unused);
      expectSurvived('theirs', because: "another computer's log names it");
    });

    test('an unreferenced video is found and its bytes come back', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = AppState(repo)..notebookId = nb;
      addTearDown(app.cancelPendingSave);
      await video('orphan', 0xAA, bytes: 16384);

      final before = (await app.storageFor(nb)).mediaBytes;
      expect(before, 16384);

      final s = await app.findUnusedVideos(nb);
      expect(s.unused.length, 1);
      expect(await app.deleteUnusedVideos(s.unused), 16384);
      expect((await app.storageFor(nb)).mediaBytes, 0);
    });
  });
}
