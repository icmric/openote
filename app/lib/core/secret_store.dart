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
///   words instead of falling back to a plain file. **Verified by running it,
///   2026-09-02** — on a Linux machine WITHOUT libsecret-tools, which is the
///   case this promise exists for and the default on a minimal desktop: write
///   returns false, read returns null, delete returns true, and nothing
///   throws. `github_token_storage_test.dart` asserts both branches and says
///   which one it took.
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

// Three OS credential APIs live in the native half; the web half has no store
// to offer, which is the case this class already refuses to paper over.
import 'secret_store_native.dart'
    if (dart.library.js_interop) 'secret_store_web.dart';

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
      debugBackend ?? (platformIsUnderTest() ? _testStore : null);

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

  static String? _platformRead(String key) => platformSecretRead(key);

  static Future<bool> _platformWrite(String key, String value) =>
      platformSecretWrite(key, value);

  static bool _platformDelete(String key) => platformSecretDelete(key);
}
