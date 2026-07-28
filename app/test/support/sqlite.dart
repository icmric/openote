import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';

/// Point `package:sqlite3` at the native library the desktop build bundles.
///
/// Every test that touches a real `.onote` needs this, and each one used to
/// re-implement the search (and silently skip when it failed, so a clean
/// checkout appeared to pass while exercising almost nothing). Call this in
/// `setUpAll` and gate the test body on the return value.
///
/// **Under CI this never returns false** — it throws instead. A skip is the
/// right behaviour on a developer's machine that hasn't built the desktop
/// runner yet, but in CI it would mean the storage, persistence and import
/// suites quietly pass without executing, which is precisely the false
/// confidence CI exists to prevent. The workflow builds the app before running
/// tests so the bundled library is present; if that ever stops being true, this
/// fails loudly instead of going green.
bool initSqliteForTests() {
  final found = _findSqlite();
  if (!found && Platform.environment['CI'] == 'true') {
    throw StateError(
        'SQLite native library not found under CI. The desktop build must run '
        'before `flutter test` so the bundled library exists — otherwise every '
        'test that touches a .onote silently skips. Searched the build output '
        'paths and the system library.');
  }
  return found;
}

bool _findSqlite() {
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
