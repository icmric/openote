/// The OS credential-store half of [SecretStore], behind a conditional import.
///
/// Three platforms, three APIs, no dependency: `advapi32` on Windows,
/// Security.framework on macOS, `secret-tool` over pipes on Linux. See
/// `secret_store.dart` for why each was chosen and what has actually been
/// verified by running it, and `secret_store_web.dart` for the fourth case,
/// which is "there is no store here".
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// `flutter test` sets FLUTTER_TEST in the environment. [SecretStore] uses
/// this as the safety net under its own override, so that a test which forgot
/// to set `debugBackend` lands in a memory map rather than in the developer's
/// real credential manager. It lives in the halves because
/// `Platform.environment` is `dart:io`, which throws in a browser.
bool platformIsUnderTest() => Platform.environment['FLUTTER_TEST'] != null;

String? platformSecretRead(String key) {
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

Future<bool> platformSecretWrite(String key, String value) async {
  try {
    if (Platform.isWindows) return _winWrite(key, value);
    if (Platform.isMacOS) return _macWrite(key, value);
    if (Platform.isLinux) return await _linuxWrite(key, value);
  } catch (_) {
    // fall through to false
  }
  return false;
}

bool platformSecretDelete(String key) {
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
String _winTarget(String key) => 'Openote/$key';

const int _credTypeGeneric = 1; // CRED_TYPE_GENERIC
const int _credPersistLocalMachine = 2; // survives logoff, this user

// Resolved lazily, exactly as `WindowFocus` resolves user32: a top-level
// `DynamicLibrary.open` would run on Linux the moment this library loads.
DynamicLibrary get _advapi32 => DynamicLibrary.open('advapi32.dll');

final _credWriteW = _advapi32.lookupFunction<
    Int32 Function(Pointer<_CredentialW>, Uint32),
    int Function(Pointer<_CredentialW>, int)>('CredWriteW');

final _credReadW = _advapi32.lookupFunction<
    Int32 Function(Pointer<Utf16>, Uint32, Uint32,
        Pointer<Pointer<_CredentialW>>),
    int Function(Pointer<Utf16>, int, int,
        Pointer<Pointer<_CredentialW>>)>('CredReadW');

final _credDeleteW = _advapi32.lookupFunction<
    Int32 Function(Pointer<Utf16>, Uint32, Uint32),
    int Function(Pointer<Utf16>, int, int)>('CredDeleteW');

final _credFree = _advapi32.lookupFunction<
    Void Function(Pointer<Void>),
    void Function(Pointer<Void>)>('CredFree');

bool _winWrite(String key, String value) {
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

String? _winRead(String key) {
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

bool _winDelete(String key) {
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

const _macService = 'Openote';

DynamicLibrary get _security => DynamicLibrary.open(
    '/System/Library/Frameworks/Security.framework/Security');

DynamicLibrary get _coreFoundation => DynamicLibrary.open(
    '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation');

final _secAdd = _security.lookupFunction<
    Int32 Function(Pointer<Void>, Uint32, Pointer<Utf8>, Uint32,
        Pointer<Utf8>, Uint32, Pointer<Uint8>, Pointer<Pointer<Void>>),
    int Function(Pointer<Void>, int, Pointer<Utf8>, int, Pointer<Utf8>, int,
        Pointer<Uint8>,
        Pointer<Pointer<Void>>)>('SecKeychainAddGenericPassword');

final _secFind = _security.lookupFunction<
    Int32 Function(Pointer<Void>, Uint32, Pointer<Utf8>, Uint32,
        Pointer<Utf8>, Pointer<Uint32>, Pointer<Pointer<Uint8>>,
        Pointer<Pointer<Void>>),
    int Function(Pointer<Void>, int, Pointer<Utf8>, int, Pointer<Utf8>,
        Pointer<Uint32>, Pointer<Pointer<Uint8>>,
        Pointer<Pointer<Void>>)>('SecKeychainFindGenericPassword');

final _secItemDelete = _security.lookupFunction<
    Int32 Function(Pointer<Void>),
    int Function(Pointer<Void>)>('SecKeychainItemDelete');

final _secFreeContent = _security.lookupFunction<
    Int32 Function(Pointer<Void>, Pointer<Void>),
    int Function(Pointer<Void>, Pointer<Void>)>('SecKeychainItemFreeContent');

final _cfRelease = _coreFoundation.lookupFunction<
    Void Function(Pointer<Void>),
    void Function(Pointer<Void>)>('CFRelease');

String? _macRead(String key) {
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

bool _macWrite(String key, String value) {
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

bool _macDelete(String key) {
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

List<String> _linuxAttrs(String key) =>
    ['application', 'openote', 'key', key];

String? _linuxRead(String key) {
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

Future<bool> _linuxWrite(String key, String value) async {
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

bool _linuxDelete(String key) {
  try {
    return Process.runSync(
                'secret-tool', ['clear', ..._linuxAttrs(key)]).exitCode ==
            0 ||
        _linuxRead(key) == null;
  } on ProcessException {
    return true; // no tool means no stored secret to worry about
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
