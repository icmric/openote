import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';

/// Point `package:sqlite3` at the native library the desktop build bundles.
///
/// Every test that touches a real `.onote` needs this, and each one used to
/// re-implement the search (and silently skip when it failed, so a clean
/// checkout appeared to pass while exercising almost nothing). Call this in
/// `setUpAll` and gate the test body on the return value.
bool initSqliteForTests() {
  for (final rel in const [
    'build/windows/x64/runner/Debug/sqlite3.dll',
    'build/windows/x64/runner/Release/sqlite3.dll',
    'build/linux/x64/debug/bundle/lib/libsqlite3.so',
    'build/linux/x64/release/bundle/lib/libsqlite3.so',
    'build/macos/Build/Products/Debug/sqlite3.framework/sqlite3',
  ]) {
    final f = File(rel);
    if (f.existsSync()) {
      open.overrideForAll(() => DynamicLibrary.open(f.absolute.path));
      return true;
    }
  }
  // Fall back to whatever the platform provides (Linux/macOS usually ship one).
  try {
    if (Platform.isLinux) {
      DynamicLibrary.open('libsqlite3.so.0');
      open.overrideForAll(() => DynamicLibrary.open('libsqlite3.so.0'));
      return true;
    }
    if (Platform.isMacOS) {
      DynamicLibrary.open('libsqlite3.dylib');
      open.overrideForAll(() => DynamicLibrary.open('libsqlite3.dylib'));
      return true;
    }
  } catch (_) {/* no system sqlite either */}
  return false;
}
