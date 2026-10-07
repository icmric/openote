/// The Windows half of [FreeSpace], behind a conditional import.
///
/// `dart:ffi` does not exist on the web and importing it is a hard compile
/// error — not a stub that throws, the way `dart:io` degrades — so every FFI
/// call in the app sits behind one of these pairs. See `free_space_web.dart`
/// for the other side, and `free_space.dart` for the class that chooses.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// `GetDiskFreeSpaceExW`, and specifically its **first** out-parameter.
///
/// `lpFreeBytesAvailableToCaller` respects a per-user disk quota where
/// `lpTotalNumberOfFreeBytes` does not, and a quota is exactly the
/// circumstance — a school machine — where the volume looks empty and the
/// write still fails.
int? windowsFreeBytes(String dir) {
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

final _getDiskFreeSpaceExW = DynamicLibrary.open('kernel32.dll').lookupFunction<
    Int32 Function(
        Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>),
    int Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>,
        Pointer<Uint64>)>('GetDiskFreeSpaceExW');
