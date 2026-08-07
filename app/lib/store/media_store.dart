import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../model/models.dart';

/// Files too big to live inside the container.
///
/// The rest of the app is content-addressed and byte-oriented: images, PDFs
/// and attachments go into the `blobs` table, get mirrored into
/// `.onotebook/blobs/`, and are read back into memory whole. That is the right
/// shape for a 300 KB screenshot and the wrong shape for a 90-minute lecture.
/// A 700 MB video in `blobs` would be one enormous SQLite row that has to be
/// decoded into memory in full before a single frame plays, and it would be
/// carried by every backup, every op-log backfill and every integrity scan.
///
/// So video stays a FILE, at `<notebook>.onotebook/media/`, beside the op logs
/// and the blob mirror — a directory that already travels with the notebook
/// (`Repository.moveNotebook` copies it, `purgeNotebook` deletes it) and is
/// already the agreed home for bytes that live outside the container. Being a
/// file is also the point: a media player wants a path, and handing it one
/// means playback reads what it needs when it needs it instead of loading
/// three quarters of a gigabyte to show the first frame.
///
/// Names are random, not hashes. Content addressing would let two copies of
/// the same lecture share one file, which is worth very little, and it would
/// cost a full read of every gigabyte at insert time before the copy even
/// starts — a visible stall on the one operation where the user is already
/// waiting.
class MediaCopyCancelled implements Exception {
  const MediaCopyCancelled();
  @override
  String toString() => 'The copy was cancelled.';
}

abstract final class MediaStore {
  static const _uuid = Uuid();

  /// Where [ref]'s media lives. Not created until something is stored.
  static Directory dirFor(NotebookRef ref) =>
      Directory(p.join(ref.logDirPath, 'media'));

  /// A stored name is a bare filename and nothing else.
  ///
  /// The reference comes out of page content, which comes out of a file that
  /// may have been imported, synced or handed over by someone else. Without
  /// this, `"media": "../../../../etc/passwd"` in a page is a read of any file
  /// the user can read, and "Save a copy…" is a way to get it back out.
  static final _validName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');

  static bool isValidName(String name) =>
      _validName.hasMatch(name) && !name.contains('..');

  /// The file for a stored name, or null if the name is not one we wrote or
  /// the bytes are not here — a notebook copied without its `.onotebook`, or a
  /// sync that has not finished bringing the video across.
  static File? resolve(NotebookRef ref, String name) {
    if (!isValidName(name)) return null;
    final f = File(p.join(dirFor(ref).path, name));
    return f.existsSync() ? f : null;
  }

  /// Copy [source] in, and return the stored name to put in a block.
  ///
  /// Streamed rather than read-then-write: the whole point of this store is
  /// files that do not fit comfortably in memory. [onProgress] reports
  /// 0.0-1.0 so a gigabyte does not look like a hang.
  ///
  /// Written under a temporary name and renamed on success, so a copy
  /// interrupted by a crash or a full disk leaves nothing that later looks
  /// like a playable video.
  static Future<String> add(
    NotebookRef ref,
    File source, {
    void Function(double fraction)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final dir = dirFor(ref);
    await dir.create(recursive: true);
    final ext = _safeExtension(source.path);
    final name = '${_uuid.v7()}$ext';
    final dest = File(p.join(dir.path, '$name.part'));

    final total = await source.length();
    var done = 0;
    var lastReport = 0;
    final sink = dest.openWrite();
    try {
      await source.openRead().map((chunk) {
        // Throwing here errors the pipe, which lands in the catch below and
        // takes the half-written file with it — a cancelled copy leaves the
        // disk exactly as it found it.
        if (isCancelled != null && isCancelled()) {
          throw const MediaCopyCancelled();
        }
        done += chunk.length;
        // Reporting per chunk is reporting ~10 000 times for a gigabyte, and
        // every report is a rebuild. Once per percent is enough to look alive.
        final pct = total > 0 ? (done * 100) ~/ total : 100;
        if (pct != lastReport) {
          lastReport = pct;
          onProgress?.call(total > 0 ? done / total : 1.0);
        }
        return chunk;
      }).pipe(sink);
    } catch (_) {
      // pipe() closes the sink itself; only the half-written file is ours.
      try {
        await dest.delete();
      } catch (_) {}
      rethrow;
    }
    await dest.rename(p.join(dir.path, name));
    return name;
  }

  /// Total bytes held, for the storage line in the sync dialog.
  ///
  /// There is deliberately no sweep yet. Deleting a block does NOT delete its
  /// file — undo has to be able to bring the video back, and a page can be
  /// restored from the recycle bin days later — so files outlive their
  /// references on purpose and the space has to be reclaimed deliberately.
  /// Doing that safely means enumerating every reference across live pages,
  /// trashed pages and the op log, and getting that scan wrong deletes a
  /// lecture that undo cannot bring back. Showing the number is honest;
  /// acting on it without that scan would not be.
  static int totalBytes(NotebookRef ref) {
    final dir = dirFor(ref);
    if (!dir.existsSync()) return 0;
    var n = 0;
    for (final e in dir.listSync()) {
      if (e is File) {
        try {
          n += e.lengthSync();
        } catch (_) {}
      }
    }
    return n;
  }

  /// The source file's extension if it is a plausible one, else nothing.
  ///
  /// Kept because it is what makes "Open with the default app" and "Save a
  /// copy…" land on the right program, and because a player given a path with
  /// no extension has to sniff. Bounded and character-checked for the same
  /// reason [isValidName] exists.
  static String _safeExtension(String path) {
    final ext = p.extension(path).toLowerCase();
    if (ext.length < 2 || ext.length > 8) return '';
    return RegExp(r'^\.[a-z0-9]+$').hasMatch(ext) ? ext : '';
  }
}

/// The file extensions this offers to store as playable video.
///
/// Not a guarantee — the player decides what it can actually decode — just the
/// filter on the picker and the "is this a video?" hint for the icon.
const kVideoExtensions = <String>[
  'mp4', 'm4v', 'mov', 'mkv', 'webm', 'avi', 'wmv', 'flv', 'mpg', 'mpeg', 'ts',
];

/// Audio too: a recorded lecture is as often an .m4a as an .mp4, and the same
/// player handles both.
const kAudioExtensions = <String>[
  'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus', 'wma',
];

String? mimeForMediaExtension(String path) {
  final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
  if (ext.isEmpty) return null;
  const known = {
    'mp4': 'video/mp4',
    'm4v': 'video/x-m4v',
    'mov': 'video/quicktime',
    'mkv': 'video/x-matroska',
    'webm': 'video/webm',
    'avi': 'video/x-msvideo',
    'wmv': 'video/x-ms-wmv',
    'flv': 'video/x-flv',
    'mpg': 'video/mpeg',
    'mpeg': 'video/mpeg',
    'ts': 'video/mp2t',
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
    'wav': 'audio/wav',
    'flac': 'audio/flac',
    'ogg': 'audio/ogg',
    'opus': 'audio/opus',
    'wma': 'audio/x-ms-wma',
  };
  return known[ext];
}
