/// The operating system's own password storage, for the one secret Openote
/// keeps: the user's GitHub access key.
///
/// Task #73: the key used to be written into `workspace.json` in clear text,
/// where anything that can read files could read it — a synced Documents
/// folder, a backup, a helpful screenshot of "what's in this folder". The rule
/// now is the same one `git_sync.dart` already applies to the command line and
/// `.git/config`: **the key never touches a plain file**. It lives in the
/// place the OS built for exactly this:
///
/// * **Windows** — the Credential Manager, over direct FFI to `advapi32.dll`
///   (`CredWriteW` / `CredReadW` / `CredDeleteW`), the same dependency-free
///   pattern `window_focus.dart` uses for user32. This half is exercised for
///   real by a round-trip test on Windows.
/// * **macOS** — the login Keychain, over FFI to Security.framework's
///   `SecKeychainAddGenericPassword` family. Those calls are the older, plain-C
///   corner of the Keychain API — chosen because they need no CoreFoundation
///   object plumbing, which keeps this file inspectable. Apple marks them
///   deprecated but ships and honours them in every current macOS.
///   **Not verified by running it** — same honesty note as `window_focus.dart`:
///   nothing here can be exercised by `flutter test` on this machine.
/// * **Linux** — `secret-tool` (libsecret's own CLI, package `libsecret-tools`
///   on Debian/Ubuntu), with the secret passed over **stdin/stdout pipes
///   only**, never argv — an argv secret is visible to every process on the
///   machine, which is the exact leak `git_sync.dart` documents. If the tool
///   is not installed, [write] reports false and the caller says so in plain
///   words instead of falling back to a plain file. **Not verified by running
///   it** either.
///
/// There is deliberately **no plaintext fallback of any kind**: a machine with
/// no usable store means "connecting a GitHub account is not available here",
/// said out loud, not "we quietly kept it in a file".
///
/// Under `flutter test` every call is routed to an in-memory map instead, so
/// no test can ever write into the developer's real credential manager by
/// accident. Tests that WANT the real thing (the Windows round-trip proof) go
/// through the `debugPlatform*` doors.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

abstract final class SecretStore {
  /// Test override: when set, every read/write/delete uses this map and the
  /// real platform store is never touched. Same shape as
  /// `AppState.debugGitHubBase` — one static, reset in tearDown.
  static Map<String, String>? debugBackend;

  /// The safety net under the override: `flutter test` sets FLUTTER_TEST in
  /// the environment, and any test that forgot to set [debugBackend] lands in
  /// this process-wide map rather than in the user's actual credentials.
  static final Map<String, String> _testStore = {};

  static Map<String, String>? get _memory =>
      debugBackend ??
      (Platform.environment['FLUTTER_TEST'] != null ? _testStore : null);

  /// Test override: when true, [write] reports failure — the "this machine
  /// has no password storage" machine, without needing one. Reset alongside
  /// [debugBackend].
  static bool debugRefuseWrites = false;

  /// The secret stored under [key], or null if there is none (or no store).
  static String? read(String key) {
    final m = _memory;
    if (m != null) return m[key];
    return _platformRead(key);
  }

  /// Store [value] under [key], replacing any previous value.
  ///
  /// Returns false when the platform has no usable store (or refused) — the
  /// caller must treat that as "not saved" and say so, never write a file.
  static Future<bool> write(String key, String value) async {
    if (debugRefuseWrites) return false;
    final m = _memory;
    if (m != null) {
      m[key] = value;
      return true;
    }
    return _platformWrite(key, value);
  }

  /// Remove [key]. True when it is gone (including "was never there" on
  /// platforms that can tell us so cheaply — callers treat absence as done).
  static bool delete(String key) {
    final m = _memory;
    if (m != null) {
      m.remove(key);
      return true;
    }
    return _platformDelete(key);
  }

  // ── The real platform store, reachable from a test on purpose ────────
  //
  // The FLUTTER_TEST guard above would otherwise make the FFI in this file
  // dead code under the entire suite — and unexecuted FFI is exactly where a
  // wrong struct offset hides. The Windows round-trip test goes through these.

  static String? debugPlatformRead(String key) => _platformRead(key);
  static Future<bool> debugPlatformWrite(String key, String value) =>
      _platformWrite(key, value);
  static bool debugPlatformDelete(String key) => _platformDelete(key);

  static String? _platformRead(String key) {
    try {
      if (Platform.isWindows) return _winRead(key);
      if (Platform.isMacOS) return _macRead(key);
      if (Platform.isLinux) return _linuxRead(key);
    } catch (_) {
      // A missing export or library must read as "no secret", never crash the
      // app on startup — reloadGitHub runs on every notebook open.
    }
    return null;
  }

  static Future<bool> _platformWrite(String key, String value) async {
    try {
      if (Platform.isWindows) return _winWrite(key, value);
      if (Platform.isMacOS) return _macWrite(key, value);
      if (Platform.isLinux) return await _linuxWrite(key, value);
    } catch (_) {
      // fall through to false
    }
    return false;
  }

  static bool _platformDelete(String key) {
    try {
      if (Platform.isWindows) return _winDelete(key);
      if (Platform.isMacOS) return _macDelete(key);
      if (Platform.isLinux) return _linuxDelete(key);
    } catch (_) {
      // fall through to false
    }
    return false;
  }

  // ── Windows: Credential Manager via advapi32 ─────────────────────────

  /// How the entry is named in the Credential Manager UI ("Windows
  /// Credentials" → "Generic Credentials"): `Openote/<key>`.
  static String _winTarget(String key) => 'Openote/$key';

  static const int _credTypeGeneric = 1; // CRED_TYPE_GENERIC
  static const int _credPersistLocalMachine = 2; // survives logoff, this user

  // Resolved lazily, exactly as `WindowFocus` resolves user32: a top-level
  // `DynamicLibrary.open` would run on Linux the moment this library loads.
  static DynamicLibrary get _advapi32 => DynamicLibrary.open('advapi32.dll');

  static final _credWriteW = _advapi32.lookupFunction<
      Int32 Function(Pointer<_CredentialW>, Uint32),
      int Function(Pointer<_CredentialW>, int)>('CredWriteW');

  static final _credReadW = _advapi32.lookupFunction<
      Int32 Function(Pointer<Utf16>, Uint32, Uint32,
          Pointer<Pointer<_CredentialW>>),
      int Function(Pointer<Utf16>, int, int,
          Pointer<Pointer<_CredentialW>>)>('CredReadW');

  static final _credDeleteW = _advapi32.lookupFunction<
      Int32 Function(Pointer<Utf16>, Uint32, Uint32),
      int Function(Pointer<Utf16>, int, int)>('CredDeleteW');

  static final _credFree = _advapi32.lookupFunction<
      Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('CredFree');

  static bool _winWrite(String key, String value) {
    final target = _winTarget(key).toNativeUtf16();
    final user = 'openote'.toNativeUtf16(); // cosmetic, shown in the manager
    final bytes = utf8.encode(value);
    final blob = calloc<Uint8>(bytes.length);
    blob.asTypedList(bytes.length).setAll(0, bytes);
    final cred = calloc<_CredentialW>();
    try {
      cred.ref
        ..flags = 0
        ..type = _credTypeGeneric
        ..targetName = target
        ..comment = nullptr
        ..lastWrittenLow = 0
        ..lastWrittenHigh = 0
        ..credentialBlobSize = bytes.length
        ..credentialBlob = blob
        ..persist = _credPersistLocalMachine
        ..attributeCount = 0
        ..attributes = nullptr
        ..targetAlias = nullptr
        ..userName = user;
      // CredWrite with an existing target name REPLACES it — no read-first.
      return _credWriteW(cred, 0) != 0;
    } finally {
      calloc.free(cred);
      calloc.free(blob);
      calloc.free(user);
      calloc.free(target);
    }
  }

  static String? _winRead(String key) {
    final target = _winTarget(key).toNativeUtf16();
    final out = calloc<Pointer<_CredentialW>>();
    try {
      if (_credReadW(target, _credTypeGeneric, 0, out) == 0) return null;
      final c = out.value.ref;
      final s = c.credentialBlobSize == 0
          ? null
          : utf8.decode(c.credentialBlob.asTypedList(c.credentialBlobSize),
              allowMalformed: true);
      _credFree(out.value.cast());
      return s;
    } finally {
      calloc.free(out);
      calloc.free(target);
    }
  }

  static bool _winDelete(String key) {
    final target = _winTarget(key).toNativeUtf16();
    try {
      // FALSE with "not found" still means the credential is gone, which is
      // what the caller asked for.
      return _credDeleteW(target, _credTypeGeneric, 0) != 0 ||
          _winRead(key) == null;
    } finally {
      calloc.free(target);
    }
  }

  // ── macOS: login Keychain via Security.framework ─────────────────────

  static const _macService = 'Openote';

  static DynamicLibrary get _security => DynamicLibrary.open(
      '/System/Library/Frameworks/Security.framework/Security');

  static DynamicLibrary get _coreFoundation => DynamicLibrary.open(
      '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation');

  static final _secAdd = _security.lookupFunction<
      Int32 Function(Pointer<Void>, Uint32, Pointer<Utf8>, Uint32,
          Pointer<Utf8>, Uint32, Pointer<Uint8>, Pointer<Pointer<Void>>),
      int Function(Pointer<Void>, int, Pointer<Utf8>, int, Pointer<Utf8>, int,
          Pointer<Uint8>,
          Pointer<Pointer<Void>>)>('SecKeychainAddGenericPassword');

  static final _secFind = _security.lookupFunction<
      Int32 Function(Pointer<Void>, Uint32, Pointer<Utf8>, Uint32,
          Pointer<Utf8>, Pointer<Uint32>, Pointer<Pointer<Uint8>>,
          Pointer<Pointer<Void>>),
      int Function(Pointer<Void>, int, Pointer<Utf8>, int, Pointer<Utf8>,
          Pointer<Uint32>, Pointer<Pointer<Uint8>>,
          Pointer<Pointer<Void>>)>('SecKeychainFindGenericPassword');

  static final _secItemDelete = _security.lookupFunction<
      Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('SecKeychainItemDelete');

  static final _secFreeContent = _security.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Void>),
      int Function(Pointer<Void>, Pointer<Void>)>('SecKeychainItemFreeContent');

  static final _cfRelease = _coreFoundation.lookupFunction<
      Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('CFRelease');

  static String? _macRead(String key) {
    final svc = _macService.toNativeUtf8();
    final acc = key.toNativeUtf8();
    final len = calloc<Uint32>();
    final data = calloc<Pointer<Uint8>>();
    try {
      final status = _secFind(nullptr, utf8.encode(_macService).length, svc,
          utf8.encode(key).length, acc, len, data, nullptr);
      if (status != 0) return null; // errSecItemNotFound and friends
      final s = len.value == 0
          ? ''
          : utf8.decode(data.value.asTypedList(len.value),
              allowMalformed: true);
      _secFreeContent(nullptr, data.value.cast());
      return s;
    } finally {
      calloc.free(data);
      calloc.free(len);
      calloc.free(acc);
      calloc.free(svc);
    }
  }

  static bool _macWrite(String key, String value) {
    // Delete-then-add rather than modify-in-place: two plain calls instead of
    // one that needs an attribute list built by hand.
    _macDelete(key);
    final svc = _macService.toNativeUtf8();
    final acc = key.toNativeUtf8();
    final bytes = utf8.encode(value);
    final blob = calloc<Uint8>(bytes.length);
    blob.asTypedList(bytes.length).setAll(0, bytes);
    try {
      final status = _secAdd(nullptr, utf8.encode(_macService).length, svc,
          utf8.encode(key).length, acc, bytes.length, blob, nullptr);
      return status == 0;
    } finally {
      calloc.free(blob);
      calloc.free(acc);
      calloc.free(svc);
    }
  }

  static bool _macDelete(String key) {
    final svc = _macService.toNativeUtf8();
    final acc = key.toNativeUtf8();
    final item = calloc<Pointer<Void>>();
    try {
      final status = _secFind(nullptr, utf8.encode(_macService).length, svc,
          utf8.encode(key).length, acc, nullptr, nullptr, item);
      if (status != 0) return true; // not there is the state we wanted
      final ok = _secItemDelete(item.value) == 0;
      _cfRelease(item.value);
      return ok;
    } finally {
      calloc.free(item);
      calloc.free(acc);
      calloc.free(svc);
    }
  }

  // ── Linux: libsecret via secret-tool, secret only ever on a pipe ─────

  static List<String> _linuxAttrs(String key) =>
      ['application', 'openote', 'key', key];

  static String? _linuxRead(String key) {
    try {
      final r = Process.runSync(
          'secret-tool', ['lookup', ..._linuxAttrs(key)]);
      if (r.exitCode != 0) return null;
      // `lookup` prints the secret bare; a trailing newline appears on some
      // versions. GitHub tokens cannot contain whitespace, so trimming is
      // lossless here.
      final s = (r.stdout as String).trimRight();
      return s.isEmpty ? null : s;
    } on ProcessException {
      return null; // secret-tool not installed
    }
  }

  static Future<bool> _linuxWrite(String key, String value) async {
    try {
      final p = await Process.start('secret-tool',
          ['store', '--label=Openote ($key)', ..._linuxAttrs(key)]);
      p.stdout.drain<void>().ignore();
      p.stderr.drain<void>().ignore();
      p.stdin.write(value);
      await p.stdin.close();
      return await p.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  static bool _linuxDelete(String key) {
    try {
      return Process.runSync(
                  'secret-tool', ['clear', ..._linuxAttrs(key)]).exitCode ==
              0 ||
          _linuxRead(key) == null;
    } on ProcessException {
      return true; // no tool means no stored secret to worry about
    }
  }
}

/// `CREDENTIALW` from wincred.h, x64/arm64 layout (all Flutter Windows
/// targets are 64-bit): 4+4, ptr, ptr, FILETIME as two DWORDs, DWORD (+4
/// padding), ptr, DWORD, DWORD, ptr, ptr, ptr — 80 bytes. The round-trip test
/// on Windows is what stands behind these offsets, not this comment.
final class _CredentialW extends Struct {
  @Uint32()
  external int flags;
  @Uint32()
  external int type;
  external Pointer<Utf16> targetName;
  external Pointer<Utf16> comment;
  @Uint32()
  external int lastWrittenLow;
  @Uint32()
  external int lastWrittenHigh;
  @Uint32()
  external int credentialBlobSize;
  external Pointer<Uint8> credentialBlob;
  @Uint32()
  external int persist;
  @Uint32()
  external int attributeCount;
  external Pointer<Void> attributes;
  external Pointer<Utf16> targetAlias;
  external Pointer<Utf16> userName;
}
