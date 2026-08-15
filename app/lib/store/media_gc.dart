/// Which copied-in videos nothing points at any more — and, far more
/// importantly, which ones something still does.
///
/// `media_store.dart` has said since videos shipped that a sweep would need to
/// enumerate "every reference across live pages, trashed pages and the op log",
/// and that "getting that scan wrong deletes a lecture that undo cannot bring
/// back". That list turned out to be short. The full set of places a stored
/// name can survive is enumerated in [VideoSweep.sources]; the scan takes all
/// of them.
///
/// **The rule this file exists to enforce: a wrong KEEP costs disk space, a
/// wrong DELETE costs somebody's lecture.** Every decision here is therefore
/// asymmetric on purpose, and three of them are worth stating outright.
///
///  * **The match is a raw substring search for the stored filename, not a
///    parse.** Asking "does this page decode to a block whose `content.media`
///    equals this name?" is the question that has already destroyed content in
///    this project twice — a9e584a and 3630eb6 both deleted ink because a scan
///    asked a structural question and the structure had moved. A substring
///    search cannot miss a reference it does not understand: a block type that
///    does not exist yet, an op envelope that gains a field, an unknown-field
///    passthrough (`Block.fromJson` keeps `content` verbatim, so a build that
///    has never heard of video still carries the name through). It can only
///    ever over-report, and over-reporting is the safe direction.
///
///  * **No evidence is not evidence of absence.** If any source cannot be
///    read — a locked container, an offline placeholder in a cloud folder, a
///    log being written as we look at it — the sweep reclaims NOTHING and says
///    why. It never falls back to "well, the sources I could read had no
///    reference". That is the closing rule of both ink-deletion fixes.
///
///  * **Every device's log, not this one's.** In a folder-shared notebook two
///    computers write into ONE `.onotebook`, so `ops/` holds the other
///    machine's `<device>.oplog` and `media/` holds the other machine's
///    videos. Deleting on the evidence of this workspace alone is exactly
///    7851c3d, where purge deleted the other device's data because
///    `_logDirIsShared` could only see this device's registry.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../model/models.dart';
import 'media_store.dart';

/// One stored video or recording that nothing points at any more.
class UnusedVideo {
  const UnusedVideo({
    required this.name,
    required this.path,
    required this.bytes,
  });

  /// The stored name — what `content['media']` would have held.
  final String name;
  final String path;
  final int bytes;
}

/// What a sweep found.
class VideoSweep {
  const VideoSweep({
    this.unused = const [],
    this.keptFiles = 0,
    this.keptBytes = 0,
    this.refusal,
  });

  final List<UnusedVideo> unused;

  /// Files left alone, and their size. Reported because "nothing to reclaim"
  /// and "four gigabytes, all of it still in use" are different answers and
  /// the user deserves the second one.
  final int keptFiles;
  final int keptBytes;

  /// Set when the sweep declined to reclaim anything at all, in the words the
  /// user should read. Null on a normal run.
  ///
  /// A refusal is never a partial result: [unused] is empty whenever this is
  /// set, so a caller cannot accidentally act on half a scan.
  final String? refusal;

  int get freeableBytes => unused.fold(0, (a, b) => a + b.bytes);

  /// Every place a stored media name can survive, as at the time this was
  /// written. Kept here as prose because the scan's correctness is entirely a
  /// question of whether this list is complete, and a future reader adding a
  /// sixth kind of snapshot needs to find this note.
  ///
  ///  1. `page_mirror.json` — live pages.
  ///  2. `page_mirror.json` — pages in the recycle bin. Deleting a page only
  ///     stamps `nodes.deleted_at`; the content row is untouched, and the
  ///     usual `WHERE deleted_at IS NULL` filter would hide exactly the pages
  ///     whose videos are most likely to look unused.
  ///  3. `page_versions.snapshot` — up to thirty autosaves per page, each a
  ///     full copy of the page as it was, each restorable from the UI.
  ///  4. `ops/<device>.oplog`, for EVERY device — append-only, never
  ///     compacted, so every name ever written is in there permanently.
  ///  5. Workspace templates. Saved page-shaped JSON, stored outside the
  ///     notebook and appliable into any other one.
  ///  6. The undo and redo stacks — a hundred page snapshots per page, in
  ///     memory, which is precisely how "I deleted it by accident" is undone.
  ///  7. The block clipboard, which is never cleared and survives switching
  ///     page and notebook.
  ///  8. The blocks on screen right now, which for the 700 ms of the save
  ///     debounce are the only copy that exists anywhere.
  ///
  /// Not on the list, having been checked: page embeds hold a page pointer and
  /// never copy block content; flashcards store text; board cards are strings.
  static const sources = '''
live pages · the recycle bin · saved page versions · every device's op log ·
workspace templates · undo and redo · the block clipboard · unsaved blocks''';
}

/// How long a file is left alone regardless of what the scan concludes.
///
/// This is the guard for every window in which a reference legitimately does
/// not exist yet:
///
///  * the copy itself — `MediaStore.add` writes `<name>.part` and renames, but
///    the block that names it is only added once the copy finishes;
///  * the save debounce, where the block exists only in memory;
///  * a folder-shared notebook where the other computer's video file has
///    arrived from the sync client but its `.oplog` line has not. There is no
///    ordering guarantee between two files in one folder, and the whole
///    reference lives in the second one.
///
/// Thirty days is not a guess: it is the promise the app already makes about
/// deleted pages (`Repository.recycleRetentionDays`), so it is the same
/// sentence the user has already been told once.
const kVideoReclaimMinimumAge = Duration(days: 30);

abstract final class MediaGc {
  /// How much of an op log is searched between yields.
  ///
  /// Measured: twenty candidate names against the 64 MB log `op_log.dart`
  /// records from the real notebook took **1,830 ms in one go**. That is the
  /// same order as the 1,977 ms whole-log parse which was "most of the
  /// reported *app fully locks up for 10-20s*", and it would be paid on the UI
  /// thread with a spinner on screen that cannot even turn. A megabyte at a
  /// time is ~30 ms of work between yields — a hitch rather than a freeze.
  @visibleForTesting
  static int chunkBytes = 1 << 20;

  /// What could be reclaimed from [ref]'s media directory.
  ///
  /// [containerText] yields page content out of the container — every
  /// `page_mirror` row INCLUDING trashed pages, and every `page_versions`
  /// snapshot. [liveText] is everything held in memory or in the workspace:
  /// undo, redo, clipboard, on-screen blocks, templates. Both are `Iterable`
  /// so a caller can stream rather than materialise a notebook's worth of JSON,
  /// and both are allowed to throw — a throw is a refusal, not a crash.
  ///
  /// Sources are consulted cheapest-first and a name drops out of the search
  /// the moment it is found, so the expensive pass (megabytes of op log) runs
  /// against the few names that survived everything else.
  /// [ownDevice] is this installation's device id, whose own `.oplog` is the
  /// one file in the notebook that is HISTORY rather than a reference — see
  /// [_eliminateInFiles]. Passing null scans every log, which is safe and, on
  /// a notebook that has ever synced, reclaims nothing.
  static Future<VideoSweep> sweep({
    required NotebookRef ref,
    required Iterable<String> Function() containerText,
    required Iterable<String> Function() liveText,
    String? ownDevice,
    Duration minimumAge = kVideoReclaimMinimumAge,
    DateTime? now,
  }) async {
    final dir = MediaStore.dirFor(ref);
    if (!dir.existsSync()) return const VideoSweep();

    final at = now ?? DateTime.now();
    final candidates = <String, File>{};
    var keptFiles = 0;
    var keptBytes = 0;

    try {
      for (final e in dir.listSync(followLinks: false)) {
        if (e is! File) continue;
        final name = p.basename(e.path);
        final bytes = e.lengthSync();
        // A `.part` is a copy in flight — quite possibly of the gigabyte the
        // user is watching the progress bar for. It has no reference because
        // it is not finished, which is the one case where "unreferenced" is
        // certain to be wrong. Not counted as kept either: it is not yet a
        // video, and reporting it as one would make the totals lie.
        if (name.endsWith('.part')) continue;
        // A name this store would refuse to resolve is a name no block can be
        // pointing at through any supported path — but it is also not a file
        // we can prove we wrote, and this directory is inside a folder the
        // user may be syncing with tools of their own. Left alone.
        if (!MediaStore.isValidName(name) ||
            at.difference(e.lastModifiedSync()) < minimumAge) {
          keptFiles++;
          keptBytes += bytes;
          continue;
        }
        candidates[name] = e;
      }
    } catch (e) {
      return VideoSweep(refusal: _cannotRead(e));
    }
    if (candidates.isEmpty) {
      return VideoSweep(keptFiles: keptFiles, keptBytes: keptBytes);
    }

    try {
      _eliminate(candidates, liveText());
      if (candidates.isNotEmpty) _eliminate(candidates, containerText());
      if (candidates.isNotEmpty) {
        await _eliminateInFiles(candidates, ref, ownDevice);
      }
    } catch (e) {
      return VideoSweep(refusal: _cannotRead(e));
    }

    final unused = <UnusedVideo>[];
    for (final e in candidates.entries) {
      try {
        unused.add(UnusedVideo(
            name: e.key, path: e.value.path, bytes: e.value.lengthSync()));
      } catch (_) {
        // Vanished under us between listing and now. Nothing to reclaim and
        // nothing to report.
      }
    }
    unused.sort((a, b) => b.bytes.compareTo(a.bytes));
    return VideoSweep(
        unused: unused, keptFiles: keptFiles, keptBytes: keptBytes);
  }

  /// Delete [files], and report the bytes actually recovered.
  ///
  /// Counted from what the delete really achieved rather than from what the
  /// scan predicted — a file locked by a player, or already gone, must not be
  /// added to a total the user is shown.
  static int reclaim(Iterable<UnusedVideo> files) {
    var freed = 0;
    for (final f in files) {
      try {
        final file = File(f.path);
        final bytes = file.lengthSync();
        file.deleteSync();
        freed += bytes;
      } catch (_) {
        // Locked, read-only, or gone. Report what actually went.
      }
    }
    return freed;
  }

  /// Drop every candidate whose name appears anywhere in [sources].
  static void _eliminate(Map<String, File> candidates, Iterable<String> sources) {
    for (final text in sources) {
      if (candidates.isEmpty) return;
      candidates.removeWhere((name, _) => text.contains(name));
    }
  }

  /// The same, over every file in the `.onotebook` that could hold a
  /// reference.
  ///
  /// **Everything except `media/` and `blobs/`.** Naming `ops/*.oplog`
  /// explicitly would be the narrower and more obviously correct-looking
  /// choice, and it is the one that goes stale: the next thing to be written
  /// into this directory would be invisible to the scan and its references
  /// would not count. `blobs/` is excluded because it holds content-addressed
  /// image and ink bytes, where a chance run of matching bytes is noise rather
  /// than a reference — and where a notebook's worth of pictures is the one
  /// thing here big enough to make the scan unreasonable.
  ///
  /// Searched as BYTES, not as a decoded string. A real op log runs to tens of
  /// megabytes, decoding one to UTF-16 doubles that in memory before the
  /// search starts, and a log whose tail is half-written decodes badly anyway.
  /// Stored names are ASCII by [MediaStore.isValidName], so the byte search is
  /// exact.
  ///
  /// **[ownDevice]'s own log is the one exception, and without it this feature
  /// does nothing at all.** Measured on the real flow — put a video on a page,
  /// save, delete the block, save — the container ends up naming nothing and
  /// this device's log still names it, because the log is append-only and
  /// nothing ever compacts it. Treating that as a reference pins every video
  /// that was ever on a saved page, for ever: a 4 GB folder of finished
  /// lectures that the button would report as entirely in use.
  ///
  /// It is safe to skip because of what this device's log IS. The container is
  /// authoritative and the log is written alongside it (`op_log.dart`), and
  /// `SyncRecorder.page` declines to record while foreign ops are pending — so
  /// our own log can lag our container but never lead it. Every live
  /// consequence of every op we ever wrote is already in `page_mirror`,
  /// including the pages in the recycle bin. The log is the history of how the
  /// container got here, and history is not a reference.
  ///
  /// **Every OTHER device's log is still read in full**, because that is the
  /// one that can hold something our container has not caught up with — the
  /// 7851c3d case. The caller additionally refuses to run at all while foreign
  /// ops are pending, so this is the second of two guards, not the only one.
  static Future<void> _eliminateInFiles(
      Map<String, File> candidates, NotebookRef ref, String? ownDevice) async {
    final root = Directory(ref.logDirPath);
    if (!root.existsSync()) return;
    final skip = {
      p.canonicalize(MediaStore.dirFor(ref).path),
      p.canonicalize(p.join(ref.logDirPath, 'blobs')),
    };
    final ownLog = ownDevice == null || ownDevice.isEmpty
        ? null
        : p.canonicalize(p.join(ref.logDirPath, 'ops', '$ownDevice.oplog'));
    for (final e in root.listSync(recursive: true, followLinks: false)) {
      if (candidates.isEmpty) return;
      if (e is! File) continue;
      if (skip.contains(p.canonicalize(p.dirname(e.path)))) continue;
      if (ownLog != null && p.canonicalize(e.path) == ownLog) continue;
      await _searchFile(candidates, e);
    }
  }

  /// Search one file a chunk at a time, yielding between chunks.
  ///
  /// **The carried tail is the whole difficulty.** A name that happens to
  /// straddle a chunk boundary is in neither chunk, and the consequence of
  /// missing it is not a slow scan but a deleted lecture. So the last
  /// [_maxNameBytes] − 1 bytes of each chunk are prepended to the next, which
  /// is exactly enough for any valid stored name to be found whole no matter
  /// where the boundary falls. The overlap is a constant rather than the
  /// longest name still being looked for, because that set shrinks as names
  /// are found and a shrinking overlap would reintroduce the gap.
  static Future<void> _searchFile(
      Map<String, File> candidates, File file) async {
    final raf = file.openSync();
    try {
      var carry = Uint8List(0);
      while (true) {
        final chunk = raf.readSync(chunkBytes);
        if (chunk.isEmpty) return;
        final Uint8List window;
        if (carry.isEmpty) {
          window = chunk;
        } else {
          window = Uint8List(carry.length + chunk.length)
            ..setRange(0, carry.length, carry)
            ..setRange(carry.length, carry.length + chunk.length, chunk);
        }
        candidates.removeWhere(
            (name, _) => _containsAscii(window, name.codeUnits));
        if (candidates.isEmpty) return;
        final keep =
            window.length < _maxNameBytes ? window.length : _maxNameBytes - 1;
        carry = Uint8List.sublistView(window, window.length - keep);
        // A real yield, not `Duration.zero`: on Windows the message loop needs
        // a timer to get a look in, which is the lesson `_syncPullLocked`
        // records from the same class of long scan.
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    } finally {
      raf.closeSync();
    }
  }

  /// The longest name [MediaStore.isValidName] will accept: one leading
  /// character plus its 127-character tail.
  static const _maxNameBytes = 128;

  /// Naive substring search over bytes. Needles are short filenames and
  /// haystacks are read once each, so the simple loop is not the cost — and it
  /// is the version whose correctness is readable, which for a search that
  /// decides whether a file gets deleted is the property that matters.
  static bool _containsAscii(Uint8List haystack, List<int> needle) {
    if (needle.isEmpty || needle.length > haystack.length) return false;
    final first = needle[0];
    final last = haystack.length - needle.length;
    outer:
    for (var i = 0; i <= last; i++) {
      if (haystack[i] != first) continue;
      for (var j = 1; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) continue outer;
      }
      return true;
    }
    return false;
  }

  /// One sentence, no cause. The causes are a locked database, a cloud
  /// placeholder that is not downloaded, a log mid-write — none of which the
  /// reader can act on, and all of which are fixed by waiting.
  static String _cannotRead(Object _) =>
      'Some of this notebook could not be read just now, so nothing was '
      'removed. Try again in a moment.';
}
