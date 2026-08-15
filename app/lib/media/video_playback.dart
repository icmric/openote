import 'package:media_kit/media_kit.dart';

import 'video_engine.dart';

/// Why a machine cannot play video in the page, when it cannot.
enum VideoUnavailable {
  /// It can. Nothing to say.
  none,

  /// Windows: the engine has not been downloaded yet. One click fixes it, and
  /// the video itself is already on this computer — see [VideoEngine].
  needsDownload,

  /// Linux: libmpv is a distribution package and this machine has not got it.
  /// Nothing Openote can download will help; the answer is a package name.
  missingSystemLibrary,
}

/// Whether this machine can actually play video, and why not when it cannot.
///
/// media_kit plays through libmpv, and the three platforms get it three ways.
/// On Linux it is a system library — `mpv-libs` on Fedora, `libmpv2` on Debian
/// and Ubuntu — declared as a dependency by the .rpm and the .deb, so the
/// package manager normally installs it alongside Openote. macOS bundles it.
/// **Windows downloads it the first time somebody plays something**, because
/// bundling it costs every student 48 MB of install for a feature most of them
/// never use (see media/video_engine.dart, and tool/split_video_engine.dart
/// for the build half).
///
/// None of those is a state a widget may discover by throwing. Availability is
/// resolved ONCE, at startup, before any block asks to play something: a throw
/// inside a widget build is a red screen where a card belongs.
abstract final class VideoPlayback {
  static bool _tried = false;
  static bool _available = false;
  static Object? _error;
  static VideoUnavailable _reason = VideoUnavailable.none;

  /// True when a [Player] can be created. Resolved by [probe]; false until then.
  static bool get available => _available;

  /// What went wrong, for **Details (advanced)**. Null when nothing did.
  static Object? get error => _error;

  /// Which of the three situations this machine is in.
  static VideoUnavailable get reason => _reason;

  /// Load the engine, once. Safe to call more than once and safe to call on a
  /// machine that has not got one — the whole point is that it does not throw.
  static Future<void> probe() async {
    if (_tried) return;
    _tried = true;
    await _resolve();
  }

  /// Look again, after the engine has just been installed. Separate from
  /// [probe] because [probe]'s once-only guard is what keeps startup cheap,
  /// and because "nothing changed" is the wrong answer to "I just downloaded
  /// it".
  static Future<void> reprobe() async {
    _tried = true;
    await _resolve();
  }

  static Future<void> _resolve() async {
    _error = null;
    if (VideoEngine.splitOnThisPlatform) {
      await VideoEngine.prepare();
      // Put the downloaded libraries on the loader's search path BEFORE
      // media_kit looks for them. The plugin's imports are delay-loaded, so
      // this is the moment they become resolvable at all.
      //
      // A failure here is NOT the answer. An installation upgraded from a
      // build that still bundled the engine has the libraries sitting beside
      // openote.exe — Inno removes a file at uninstall, never merely because
      // it left the script — and asking that student to download 46 MB they
      // already have would be absurd. So the attempt below runs either way,
      // and only its failure means "needs downloading".
      VideoEngine.load();
    }
    try {
      MediaKit.ensureInitialized();
      _available = true;
      _reason = VideoUnavailable.none;
    } catch (e) {
      _error = e;
      _available = false;
      _reason = VideoEngine.splitOnThisPlatform
          ? VideoUnavailable.needsDownload
          : VideoUnavailable.missingSystemLibrary;
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
  static void debugSetAvailable(bool value,
      {Object? error, VideoUnavailable? reason}) {
    _tried = true;
    _available = value;
    _error = error;
    _reason = reason ??
        (value
            ? VideoUnavailable.none
            : VideoEngine.splitOnThisPlatform
                ? VideoUnavailable.needsDownload
                : VideoUnavailable.missingSystemLibrary);
  }
}
