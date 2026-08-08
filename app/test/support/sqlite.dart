import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
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
/// Where the library was found, for handing to a spawned isolate.
///
/// `open.overrideForAll` is a static and statics are **per isolate**, so the
/// override [initSqliteForTests] installs applies only to the isolate that
/// called it. Anything spawned has to be told the path.
String? sqliteLibraryPathForTests;

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

/// A copy of [src] in the temp directory, or null if one cannot be made.
///
/// Named after the source's size and modification time, so a rebuilt library
/// produces a new name and a stale copy is never used. Several test processes
/// run concurrently and will all want the same name: an existing copy is reused
/// rather than rewritten, which is safe precisely because the name pins the
/// bytes.
String? _loadableCopy(File src) {
  // **Windows only, and that is not a shortcut — it is the whole reason.**
  //
  // The problem being solved is a Windows one: a loaded DLL is locked, so a
  // test run stopped the next `flutter run` from overwriting `sqlite3.dll`.
  // Unix has no such lock; a running process keeps its inode and the file can
  // be replaced underneath it.
  //
  // And copying actively BREAKS the other two. macOS refuses to load a
  // `.dylib`/framework whose code signature no longer matches its location,
  // and a Linux `/tmp` is routinely mounted `noexec`, which makes `dlopen`
  // fail outright. Both showed up as every sqlite-dependent test failing on
  // CI while Windows stayed green.
  if (!Platform.isWindows) return null;
  try {
    final stat = src.statSync();
    final name = 'onote-sqlite-${stat.size}-'
        '${stat.modified.millisecondsSinceEpoch}'
        '${p.extension(src.path)}';
    final dest = File(p.join(Directory.systemTemp.path, name));
    if (!dest.existsSync() || dest.lengthSync() != stat.size) {
      // A partially written copy from a process that died mid-write would be
      // the wrong length, hence the size check rather than mere existence.
      src.copySync(dest.path);
    }
    return dest.absolute.path;
  } catch (_) {
    // No temp space, a locked destination mid-copy, an exotic filesystem.
    // Falling back to the original is what happened before this existed, so
    // the worst case is the old behaviour rather than a failure.
    return null;
  }
}

bool _findSqlite() {
  for (final rel in const [
    'build/windows/x64/runner/Debug/sqlite3.dll',
    'build/windows/x64/runner/Release/sqlite3.dll',
    'build/linux/x64/debug/bundle/lib/libsqlite3.so',
    'build/linux/x64/release/bundle/lib/libsqlite3.so',
    'build/macos/Build/Products/Debug/sqlite3.framework/sqlite3',
    // Release, not just Debug. CI builds `flutter build macos --release`, so
    // the Debug path never existed there and macOS silently fell through to
    // the system `libsqlite3.dylib` below — testing Apple's SQLite instead of
    // the one the app actually ships. Windows and Linux both list their
    // release path; macOS was the odd one out.
    'build/macos/Build/Products/Release/sqlite3.framework/sqlite3',
  ]) {
    final f = File(rel);
    if (f.existsSync()) {
      // **Load a COPY, never the build output itself.**
      //
      // The first path on this list is the Debug DLL that `flutter run` has to
      // overwrite on its next build — and a loaded library is locked on
      // Windows. So a test run left the build broken:
      //
      //   file INSTALL cannot copy file ".../plugins/.../Debug/sqlite3.dll"
      //   to ".../runner/Debug/sqlite3.dll": Permission denied.
      //
      // Worse, it survived the run: `flutter_tester` processes routinely
      // outlive the suite (a leaked timer, an open handle), so the lock
      // persisted until they were killed by hand. The symptom is a CMake error
      // deep in MSBuild output that looks nothing like "your tests are still
      // running".
      //
      // Copying costs ~2 MB and one file write per build, and it decouples
      // the two entirely.
      final path = _loadableCopy(f) ?? f.absolute.path;
      sqliteLibraryPathForTests = path;
      open.overrideForAll(() => DynamicLibrary.open(path));
      return true;
    }
  }
  // Fall back to whatever the platform provides (Linux/macOS usually ship one).
  try {
    if (Platform.isLinux) {
      DynamicLibrary.open('libsqlite3.so.0');
      sqliteLibraryPathForTests = 'libsqlite3.so.0';
      open.overrideForAll(() => DynamicLibrary.open('libsqlite3.so.0'));
      return true;
    }
    if (Platform.isMacOS) {
      DynamicLibrary.open('libsqlite3.dylib');
      sqliteLibraryPathForTests = 'libsqlite3.dylib';
      open.overrideForAll(() => DynamicLibrary.open('libsqlite3.dylib'));
      return true;
    }
  } catch (_) {/* no system sqlite either */}
  return false;
}
