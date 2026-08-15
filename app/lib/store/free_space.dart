import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

/// How much room is left on the volume a path lives on.
///
/// **Why this exists at all.** v0.17 Step 7 empties a notebook's `blobs` table
/// and then `VACUUM`s the container, and `VACUUM` is not a shrink in place: it
/// writes a whole second copy of the database and swaps it. Measured on the
/// owner's 97,542,144-byte container the peak on disk was **192,787,184 bytes**
/// across the `.onote`, a 95,048,432-byte `-wal` and the `-shm` — 1.98× the
/// starting file. On a 322 MB container that is most of a gigabyte, and the
/// step it is paying for is the one that deletes bytes.
///
/// Dart has no free-space API, so this is the platform call in each case. It is
/// deliberately allowed to answer **null**, and callers must treat null as
/// "refuse", never as "probably fine": the whole hazard list for this step is
/// headed by *"a disk-full VACUUM is reported to the user as success"*, and a
/// precheck that quietly degrades to no check is that same failure one layer up.
abstract final class FreeSpace {
  /// Bytes usable at [path] by this user, or null when it cannot be measured.
  ///
  /// [path] may be a file or a directory; the volume is what is measured, so a
  /// file's parent directory is asked about.
  static int? bytesFor(String path) {
    final probe = overrideForTest;
    if (probe != null) return probe(path);
    final dir = FileSystemEntity.isDirectorySync(path)
        ? path
        : File(path).parent.path;
    try {
      return Platform.isWindows ? _windows(dir) : _posix(dir);
    } catch (e) {
      // Never rethrow: "I could not measure" is a legitimate answer that the
      // caller already has to handle, and an exception here would abort the
      // gate that was about to protect the user.
      debugPrint('[openote/store] could not measure free space at $dir: $e');
      return null;
    }
  }

  /// Stand in for the platform call. The 2.0× refusal cannot otherwise be
  /// exercised: filling a real volume is the one Group D cell the plan marks
  /// **skip** on Windows ("a fixed-size VHD via `diskpart` is flaky").
  @visibleForTesting
  static int? Function(String path)? overrideForTest;

  /// `GetDiskFreeSpaceExW`, and specifically its **first** out-parameter.
  ///
  /// `lpFreeBytesAvailableToCaller` respects a per-user disk quota where
  /// `lpTotalNumberOfFreeBytes` does not, and a quota is exactly the
  /// circumstance — a school machine — where the volume looks empty and the
  /// write still fails.
  static int? _windows(String dir) {
    final name = dir.toNativeUtf16();
    final free = calloc<Uint64>();
    final total = calloc<Uint64>();
    final totalFree = calloc<Uint64>();
    try {
      final ok = _getDiskFreeSpaceExW(name, free, total, totalFree);
      return ok == 0 ? null : free.value;
    } finally {
      calloc
        ..free(name)
        ..free(free)
        ..free(total)
        ..free(totalFree);
    }
  }

  static final _getDiskFreeSpaceExW = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<
          Int32 Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>,
              Pointer<Uint64>),
          int Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>,
              Pointer<Uint64>)>('GetDiskFreeSpaceExW');

  /// `df -Pk`. `-P` is the POSIX output format, which is specified rather than
  /// implementation-defined, and `-k` fixes the block size at 1024 so macOS's
  /// 512-byte default cannot halve the answer.
  ///
  /// The available column is found by walking **back** from the capacity field
  /// — the one that ends in `%` — rather than counting from the left, because
  /// a device name with a space in it shifts every field after it.
  static int? _posix(String dir) {
    final r = Process.runSync('df', ['-Pk', dir]);
    if (r.exitCode != 0) return null;
    final lines = (r.stdout as String).trim().split('\n');
    if (lines.length < 2) return null;
    final parts = lines.last.trim().split(RegExp(r'\s+'));
    final pct = parts.indexWhere((f) => f.endsWith('%'));
    if (pct < 1) return null;
    final kb = int.tryParse(parts[pct - 1]);
    return kb == null ? null : kb * 1024;
  }
}
