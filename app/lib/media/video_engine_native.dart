/// The loader half of [VideoEngine], behind a conditional import.
///
/// Two `dart:ffi` calls, and both are about making Windows find a DLL that is
/// not beside the executable. See `video_engine.dart` for why the engine ships
/// separately at all, and `video_engine_web.dart` for the browser, where there
/// is no library to load and nothing to add to a search path.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// False in a browser, where none of this applies.
const bool platformCanLoadEngine = true;

/// Open every library in [dir] by ABSOLUTE path.
///
/// The plugin's imports of these libraries are delay-loaded (see
/// tool/split_video_engine.dart), so the loader has not looked for them
/// before now. Loading each by absolute path registers it under its base
/// name, which is what the deferred `LoadLibrary("libmpv-2.dll")` inside the
/// plugin then finds.
bool platformLoadEngineLibraries(String dir, List<String> names) {
  try {
    _addToDllSearchPath(dir);
    for (final name in names) {
      DynamicLibrary.open('$dir/$name');
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// `SetDllDirectoryW`. Belt and braces beside the explicit opens above: a
/// library that loads a *sibling* we have not named — ANGLE picks its
/// backend at run time — has to be able to find it too.
void _addToDllSearchPath(String dir) {
  if (!Platform.isWindows) return;
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final setDllDirectory = kernel32.lookupFunction<
      Int32 Function(Pointer<Utf16>),
      int Function(Pointer<Utf16>)>('SetDllDirectoryW');
  final p = dir.toNativeUtf16();
  try {
    setDllDirectory(p);
  } finally {
    calloc.free(p);
  }
}
