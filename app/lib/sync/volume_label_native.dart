/// What the operating system calls a drive, so a picker can say which one.
///
/// Openote detects Google Drive on Windows by probing drive letters for a
/// `My Drive` folder, which gives the user "Google Drive" and a letter. That is
/// not enough to choose with: Drive mounts **one letter per signed-in account**,
/// and somebody with a personal and a work account sees two identical rows.
/// Measured on the owner's machine — G: and I:, both "Google Drive".
///
/// The volume label carries the account. Drive sets it to something like
/// `name@example.com - Google Drive`, which Windows truncates to its 32-character
/// label limit — so what comes back is `name@example.com -...`. Truncated, and
/// still the part that identifies the account.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// The volume label for [driveLetter] (`'G'`), or null when there is none.
///
/// Null for every reason: not Windows, no such drive, an unlabelled volume, a
/// call that failed. A caller must treat null as "no extra detail" and never as
/// an error — this is decoration on a picker row, and a `DynamicLibrary` that
/// will not load must not stop somebody choosing a folder.
String? platformVolumeLabel(String driveLetter) {
  if (driveLetter.isEmpty) return null;
  try {
    final k32 = DynamicLibrary.open('kernel32.dll');
    final getVolumeInformation = k32.lookupFunction<
        Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32, Pointer<Uint32>,
            Pointer<Uint32>, Pointer<Uint32>, Pointer<Utf16>, Uint32),
        int Function(Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Uint32>,
            Pointer<Uint32>, Pointer<Uint32>, Pointer<Utf16>, int)>(
      'GetVolumeInformationW',
    );

    // MAX_PATH + 1. The label itself cannot exceed 32 characters, but the API
    // is documented against this buffer size and a short one is a buffer
    // overrun rather than a truncated answer.
    const cap = 261;
    final root = '${driveLetter[0].toUpperCase()}:\\'.toNativeUtf16();
    final name = calloc<Uint16>(cap).cast<Utf16>();
    final fsName = calloc<Uint16>(cap).cast<Utf16>();
    final serial = calloc<Uint32>();
    final maxComponent = calloc<Uint32>();
    final flags = calloc<Uint32>();
    try {
      final ok = getVolumeInformation(root, name, cap, serial, maxComponent,
          flags, fsName, cap);
      if (ok == 0) return null;
      final label = name.toDartString();
      return label.trim().isEmpty ? null : label.trim();
    } finally {
      calloc.free(root);
      calloc.free(name);
      calloc.free(fsName);
      calloc.free(serial);
      calloc.free(maxComponent);
      calloc.free(flags);
    }
  } catch (_) {
    return null;
  }
}
