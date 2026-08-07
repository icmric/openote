import 'package:media_kit/media_kit.dart';

/// Whether this machine can actually play video, and why not when it cannot.
///
/// media_kit plays through libmpv. Windows and macOS get it from the
/// `media_kit_libs_*` packages, which ship the library inside the app bundle,
/// so there it is simply always present. On Linux it is a system library —
/// `mpv-libs` on Fedora, `libmpv2` on Debian and Ubuntu — declared as a
/// dependency by the .rpm and the .deb, which means the package manager
/// normally installs it alongside Openote and this is a formality.
///
/// It is not always a formality. A user who unpacked the tarball, or who
/// removed mpv afterwards, has an Openote that cannot decode a frame. The
/// honest answer there is a card that says which package to install, not a
/// play button that throws — so availability is resolved ONCE, at startup,
/// before any block asks to play something.
abstract final class VideoPlayback {
  static bool _tried = false;
  static bool _available = false;
  static Object? _error;

  /// True when a [Player] can be created. Resolved by [probe]; false until then.
  static bool get available => _available;

  /// What went wrong, for the message on the card. Null when nothing did.
  static Object? get error => _error;

  /// Load libmpv, once. Safe to call more than once and safe to call on a
  /// machine without it — the whole point is that it does not throw.
  static void probe() {
    if (_tried) return;
    _tried = true;
    try {
      MediaKit.ensureInitialized();
      _available = true;
    } catch (e) {
      _error = e;
      _available = false;
    }
  }

  /// What to tell a user whose machine cannot play video. Platform-specific,
  /// because "install libmpv" is not something anyone can act on directly.
  static String get missingLibraryAdvice =>
      'Openote plays video through libmpv, which is not installed.\n\n'
      'Fedora and RHEL:  sudo dnf install mpv-libs\n'
      'Debian and Ubuntu:  sudo apt install libmpv2\n'
      '(older Debian and Ubuntu: libmpv1)\n\n'
      'The .deb and .rpm packages ask for this automatically — this normally '
      'only comes up when Openote was unpacked by hand.';

  /// Pretend the library is missing, for tests that need the fallback path.
  /// No effect in a release build's normal flow, which only calls [probe].
  static void debugSetAvailable(bool value, {Object? error}) {
    _tried = true;
    _available = value;
    _error = error;
  }
}
